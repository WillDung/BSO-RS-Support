#requires -Version 7.4
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Preflight', 'Apply', 'Reconcile', 'PartialPreflight', 'ContinuePartial')][string]$Mode,
    [Parameter(Mandatory)][string]$EnvironmentName,
    [Parameter(Mandatory)][string]$OrganizationUrl,
    [Parameter(Mandatory)][string]$ExpectedEnvironmentId,
    [Parameter(Mandatory)][string]$ExpectedOrganizationId,
    [Parameter(Mandatory)][string]$ReleaseManifestPath,
    [Parameter(Mandatory)][string]$PlanPath,
    [Parameter(Mandatory)][string]$BaselinePath,
    [string]$ExpectedPlanSha256,
    [string]$EvidencePath,
    [string]$PriorJournalPath,
    [string]$ExpectedPriorJournalSha256,
    [string]$ContinuationPlanPath,
    [string]$ExpectedContinuationPlanSha256,
    [string]$PacPath = 'pac'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$script:Root = Split-Path $PSScriptRoot -Parent
$script:OrganizationUrl = $OrganizationUrl.TrimEnd('/')
$script:ApiRoot = $script:OrganizationUrl + '/api/data/v9.2/'
$script:SolutionUniqueName = 'os_sr_bso_rs_support'
$script:PublisherUniqueName = 'os_bso_rs_support'
$script:AccessToken = $null
$script:Plan = $null
$script:Journal = $null
$script:JournalOwned = $false
$script:RequestCounts = @{ GET = 0; POST = 0 }
$script:WriteIndex = 0
$script:Manifest = $null
$script:ExpectedDelta = @()
$script:MaximumReads = 160
$script:MaximumWrites = 5
$script:IsPartialContinuation = $Mode -cin @('PartialPreflight', 'ContinuePartial')
$script:EvidenceLocks = [Collections.Generic.List[IDisposable]]::new()

if ($EnvironmentName -cne 'VN LMV IT' -or
    ([Uri]$script:OrganizationUrl).AbsoluteUri.TrimEnd('/') -cne 'https://org14938ec2.crm4.dynamics.com' -or
    $ExpectedEnvironmentId -ine '92e44afb-6c3a-eb1a-8154-4ed51e1e6e42' -or
    $ExpectedOrganizationId -ine '0706072c-54ea-f011-872b-000d3ab60060') {
    throw 'The target does not match the explicitly authorized VN LMV IT environment.'
}
$expectedManifestPath = Join-Path $script:Root 'docs\CANDIDATE_CORE_PAGINATION_1.0.10_RELEASE_MANIFEST.json'
if (-not [string]::Equals(
        [IO.Path]::GetFullPath($ReleaseManifestPath),
        [IO.Path]::GetFullPath($expectedManifestPath),
        [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Only the versioned Candidate Core 1.0.10 release manifest is permitted.'
}
if ($Mode -ceq 'Preflight' -and
    ((Test-Path -LiteralPath $PlanPath) -or (Test-Path -LiteralPath $BaselinePath))) {
    throw 'Preflight requires new plan and baseline paths; existing evidence is never overwritten.'
}
if ($Mode -ceq 'Apply' -and
    (-not $ExpectedPlanSha256 -or -not $EvidencePath -or
        (Test-Path -LiteralPath $EvidencePath) -or
        -not (Test-Path -LiteralPath $PlanPath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $BaselinePath -PathType Leaf))) {
    throw 'Apply requires a pinned plan, baseline, and new evidence path.'
}
if ($Mode -ceq 'Reconcile' -and
    (-not $ExpectedPlanSha256 -or -not $EvidencePath -or
        -not (Test-Path -LiteralPath $PlanPath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $BaselinePath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $EvidencePath -PathType Leaf))) {
    throw 'Reconcile requires the pinned plan, baseline, and consumed evidence.'
}
if ($script:IsPartialContinuation) {
    if ($ExpectedPlanSha256 -cnotmatch '^[0-9a-f]{64}$' -or
        $ExpectedPriorJournalSha256 -cnotmatch '^[0-9a-f]{64}$' -or
        -not $PriorJournalPath -or -not $ContinuationPlanPath -or
        -not (Test-Path -LiteralPath $PriorJournalPath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $PlanPath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $BaselinePath -PathType Leaf)) {
        throw 'Partial continuation requires the original pinned plan, baseline and immutable journal.'
    }
    $claimPath = [IO.Path]::GetFullPath($PriorJournalPath) + '.scoped-total-count-continuation.json'
    if (Test-Path -LiteralPath $claimPath) {
        throw 'The one-shot continuation has already been reserved; reconcile without repeating it.'
    }
    if ($Mode -ceq 'PartialPreflight' -and (Test-Path -LiteralPath $ContinuationPlanPath)) {
        throw 'Partial preflight requires a new continuation plan path.'
    }
    if ($Mode -ceq 'ContinuePartial' -and
        ($ExpectedContinuationPlanSha256 -cnotmatch '^[0-9a-f]{64}$' -or
         -not (Test-Path -LiteralPath $ContinuationPlanPath -PathType Leaf) -or
         -not $EvidencePath -or
         -not [string]::Equals([IO.Path]::GetFullPath($EvidencePath), $claimPath,
             [StringComparison]::OrdinalIgnoreCase))) {
        throw 'Continuation must use its pinned plan and unique prior-journal-derived claim path.'
    }
}
if (-not (Test-Path -LiteralPath (Split-Path -Parent $PlanPath) -PathType Container) -or
    -not (Test-Path -LiteralPath (Split-Path -Parent $BaselinePath) -PathType Container)) {
    throw 'The plan and baseline directories must already exist.'
}

$script:Manifest = Get-Content -LiteralPath $ReleaseManifestPath -Raw | ConvertFrom-Json
if ([string]$script:Manifest.release.artifactVersion -cne '1.0.10' -or
    [string]$script:Manifest.customApiContract.uniqueName -cne 'os_sr_cact' -or
    [int]$script:Manifest.customApiContract.additiveMetadataWriteCount -ne 5 -or
    [int]$script:Manifest.customApiContract.baselineRequestParameterCount -ne 22 -or
    [int]$script:Manifest.customApiContract.baselineResponsePropertyCount -ne 9 -or
    $script:Manifest.release.reportedBaseline.normalCreateEnabled -isnot [bool]) {
    throw 'The release manifest does not declare the exact 1.0.10 baseline and five-item API delta.'
}
$enabledLiteral = if ([bool]$script:Manifest.release.reportedBaseline.normalCreateEnabled) {
    'true'
} else { 'false' }
$script:ExpectedGateValue = "v1|enabled=$enabledLiteral|organizationId=$ExpectedOrganizationId"

function Get-Sha256 {
    param([Parameter(Mandatory)][byte[]]$Bytes)
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes)).ToLowerInvariant()
}

function ConvertTo-CanonicalGuid {
    param([Parameter(Mandatory)][string]$Value)
    $parsed = [Guid]::Empty
    if (-not [Guid]::TryParse($Value, [ref]$parsed) -or $parsed -eq [Guid]::Empty) {
        throw 'A Dataverse component identifier is invalid.'
    }
    $parsed.ToString('D').ToLowerInvariant()
}

function Save-Json {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][object]$Value,
        [switch]$CreateNew)
    $modeValue = if ($CreateNew) { [IO.FileMode]::CreateNew } else { [IO.FileMode]::Open }
    $stream = [IO.File]::Open($Path, $modeValue, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
        if (-not $CreateNew) { $stream.SetLength(0) }
        $bytes = [Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $Value -Depth 40))
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush($true)
    } finally { $stream.Dispose() }
}

function Get-Api {
    param(
        [Parameter(Mandatory)][ValidateSet('GET', 'POST')][string]$Method,
        [Parameter(Mandatory)][string]$Path,
        [AllowNull()][object]$Body
    )
    if ($Method -ceq 'GET' -and $script:RequestCounts.GET -ge $script:MaximumReads) {
        throw 'The bounded metadata read budget was exhausted.'
    }
    $uri = if ($Path -match '^https://') { [Uri]$Path } else { [Uri]($script:ApiRoot + $Path) }
    if ($uri.Scheme -cne 'https' -or $uri.Authority -ine ([Uri]$script:OrganizationUrl).Authority -or
        $uri.AbsolutePath -notmatch '^/api/data/v9\.2/' -or $uri.UserInfo -or $uri.Fragment) {
        throw 'Dataverse request target failed the exact HTTPS origin check.'
    }
    if ($Method -ceq 'POST') {
        if ($Mode -cnotin @('Apply', 'ContinuePartial') -or $null -eq $script:Plan -or
            $script:WriteIndex -ge $script:Plan.Writes.Count) {
            throw 'Metadata POST is outside the pinned five-component Apply plan.'
        }
        $write = $script:Plan.Writes[$script:WriteIndex]
        if ($Mode -ceq 'ContinuePartial' -and
            ($script:WriteIndex -ne 4 -or $script:RequestCounts.POST -ne 0 -or
             $write.Name -cne 'ScopedTotalCount' -or $write.Kind -cne 'CustomApiResponseProperty')) {
            throw 'Continuation permits only one ScopedTotalCount POST; prior writes cannot be replayed.'
        }
        $payloadHash = Get-Sha256 -Bytes ([Text.Encoding]::UTF8.GetBytes(
            (ConvertTo-Json -InputObject $Body -Depth 20 -Compress)
        ))
        if ($Path -cne [string]$write.Path -or
            $payloadHash -cne [string]$write.PayloadSha256 -or
            $script:Journal.Writes[$script:WriteIndex].State -cne 'DISPATCH_RESERVED') {
            throw 'Metadata payload differs from the reserved plan entry.'
        }
        $script:WriteIndex++
    }
    $headers = @{
        Authorization = 'Bearer ' + $script:AccessToken
        Accept = 'application/json'
        'OData-Version' = '4.0'
        'OData-MaxVersion' = '4.0'
        Consistency = 'Strong'
    }
    $request = @{
        Uri = $uri
        Method = $Method
        Headers = $headers
        MaximumRetryCount = 0
        MaximumRedirection = 0
        TimeoutSec = 120
        SkipHttpErrorCheck = $true
    }
    if ($Method -ceq 'POST') {
        $headers['MSCRM.SolutionUniqueName'] = $script:SolutionUniqueName
        $request.Body = ConvertTo-Json -InputObject $Body -Depth 20 -Compress
        $request.ContentType = 'application/json; charset=utf-8'
    }
    if ($Method -ceq 'GET') { $script:RequestCounts.GET++ } else { $script:RequestCounts.POST++ }
    try { $response = Invoke-WebRequest @request }
    catch { throw 'Dataverse transport outcome is uncertain; stop and reconcile without retry.' }
    if ([int]$response.StatusCode -lt 200 -or [int]$response.StatusCode -ge 300) {
        throw "Dataverse $Method was rejected with HTTP $([int]$response.StatusCode); stop without retry."
    }
    if ([string]::IsNullOrWhiteSpace([string]$response.Content)) { return $null }
    $response.Content | ConvertFrom-Json -ErrorAction Stop
}

function Get-Rows {
    param([Parameter(Mandatory)][string]$Path)
    $rows = [Collections.Generic.List[object]]::new()
    $next = $Path
    while ($next) {
        $result = Get-Api -Method GET -Path $next
        if ($null -eq $result -or -not $result.PSObject.Properties['value']) {
            throw 'Dataverse collection response is missing its value array.'
        }
        foreach ($row in @($result.value)) { $rows.Add($row) }
        $next = if ($result.PSObject.Properties['@odata.nextLink']) {
            [string]$result.'@odata.nextLink'
        } else { '' }
    }
    @($rows)
}

function Get-RelationshipBinding {
    param([Parameter(Mandatory)][string]$LogicalName)
    $relationships = @(Get-Rows -Path "EntityDefinitions(LogicalName='$LogicalName')/ManyToOneRelationships?%24select=ReferencingAttribute,ReferencedEntity,ReferencingEntityNavigationPropertyName")
    $matches = @($relationships | Where-Object {
        [string]$_.ReferencingAttribute -ceq 'customapiid' -and
        [string]$_.ReferencedEntity -ceq 'customapi'
    })
    if ($matches.Count -ne 1 -or
        [string]::IsNullOrWhiteSpace([string]$matches[0].ReferencingEntityNavigationPropertyName)) {
        throw "The $LogicalName-to-Custom-API binding metadata is missing or ambiguous."
    }
    [string]$matches[0].ReferencingEntityNavigationPropertyName
}

function Get-SourceDelta {
    $components = @($script:Manifest.exactComponentDelta | Where-Object {
        [string]$_.kind -in @('CustomApiRequestParameter', 'CustomApiResponseProperty')
    })
    if ($components.Count -ne 5 -or
        @($components | Where-Object parentApiUniqueName -cne 'os_sr_cact').Count -ne 0) {
        throw 'The release manifest must pin exactly five components bound to os_sr_cact.'
    }
    $parsed = [Collections.Generic.List[object]]::new()
    foreach ($component in $components) {
        $path = [IO.Path]::GetFullPath((Join-Path (Split-Path $ReleaseManifestPath -Parent) ([string]$component.sourceFile)))
        $expectedDirectory = [IO.Path]::GetFullPath((Join-Path $script:Root 'solutions\customapis\os_sr_cact'))
        if (-not $path.StartsWith($expectedDirectory + [IO.Path]::DirectorySeparatorChar,
                [StringComparison]::OrdinalIgnoreCase) -or
            (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -cne
                [string]$component.sourceSha256) {
            throw "A Custom API source definition is outside the pinned folder or has changed: $($component.uniqueName)."
        }
        $settings = [Xml.XmlReaderSettings]::new()
        $settings.DtdProcessing = [Xml.DtdProcessing]::Prohibit
        $settings.XmlResolver = $null
        $reader = [Xml.XmlReader]::Create($path, $settings)
        $document = [Xml.XmlDocument]::new()
        $document.XmlResolver = $null
        try { $document.Load($reader) } finally { $reader.Dispose() }
        $root = $document.DocumentElement
        $expectedRoot = if ($component.kind -ceq 'CustomApiRequestParameter') {
            'customapirequestparameter'
        } else { 'customapiresponseproperty' }
        $shortName = [string]$component.uniqueName -replace '^os_sr_cact\.', ''
        $nameNode = $document.SelectSingleNode('/' + $expectedRoot + '/name')
        $displayNode = $document.SelectSingleNode('/' + $expectedRoot + '/displayname')
        $typeNode = $document.SelectSingleNode('/' + $expectedRoot + '/type')
        $optionalNode = $document.SelectSingleNode('/' + $expectedRoot + '/isoptional')
        $optional = $component.kind -ceq 'CustomApiRequestParameter' -and
            $null -ne $optionalNode -and [string]$optionalNode.InnerText -ceq '1'
        if ($root.LocalName -cne $expectedRoot -or
            $root.GetAttribute('uniquename') -cne $shortName -or
            $null -eq $nameNode -or [string]$nameNode.InnerText -cne [string]$component.uniqueName -or
            $null -eq $displayNode -or
            [string]::IsNullOrWhiteSpace([string]$displayNode.GetAttribute('default')) -or
            $null -eq $typeNode -or [int]$typeNode.InnerText -ne [int]$component.typeCode -or
            [string]$component.type -notin @('String', 'Integer', 'Boolean') -or
            ($component.kind -ceq 'CustomApiRequestParameter' -and
                ([bool]$component.optional -ne $true -or -not $optional)) -or
            ($component.kind -ceq 'CustomApiResponseProperty' -and
                ($component.PSObject.Properties['optional'] -or $null -ne $optionalNode))) {
            throw "Custom API XML does not match the versioned delta: $($component.uniqueName)."
        }
        $parsed.Add([pscustomobject]@{
            Kind = [string]$component.kind
            Name = $shortName
            UniqueName = [string]$component.uniqueName
            Type = [int]$component.typeCode
            IsOptional = if ($component.kind -ceq 'CustomApiRequestParameter') { $true } else { $null }
            SourcePath = $path
            SourceSha256 = [string]$component.sourceSha256
            DisplayName = [string]$displayNode.GetAttribute('default')
        })
    }
    $requests = @($parsed | Where-Object Kind -ceq 'CustomApiRequestParameter')
    $responses = @($parsed | Where-Object Kind -ceq 'CustomApiResponseProperty')
    if ($requests.Count -ne 3 -or $responses.Count -ne 2 -or
        [string]::Join('|', @($requests | ForEach-Object Name | Sort-Object -CaseSensitive)) -cne
            'CandidatePageNumber|CandidateSearchText|CandidateStatusFilter' -or
        [string]::Join('|', @($responses | ForEach-Object Name | Sort-Object -CaseSensitive)) -cne
            'ScopedHasNextPage|ScopedTotalCount') {
        throw 'The Custom API additions differ from the exact pagination delta.'
    }
    @($parsed)
}

function Get-CanonicalApiHash {
    param([Parameter(Mandatory)][object]$Api,
        [Parameter(Mandatory)][object[]]$Inputs,
        [Parameter(Mandatory)][object[]]$Outputs)
    $canonical = [ordered]@{
        customapiid = [string]$Api.customapiid
        uniquename = [string]$Api.uniquename
        name = [string]$Api.name
        displayname = [string]$Api.displayname
        description = [string]$Api.description
        executeprivilegename = [string]$Api.executeprivilegename
        bindingtype = [int]$Api.bindingtype
        isfunction = [bool]$Api.isfunction
        isprivate = [bool]$Api.isprivate
        allowedcustomprocessingsteptype = [int]$Api.allowedcustomprocessingsteptype
        handlerTypeId = [string]$Api._plugintypeid_value
        inputs = @($Inputs | Sort-Object uniquename | ForEach-Object {
            [ordered]@{
                uniquename = [string]$_.uniquename
                type = [int]$_.type
                isoptional = [bool]$_.isoptional
                logicalentityname = [string]$_.logicalentityname
            }
        })
        outputs = @($Outputs | Sort-Object uniquename | ForEach-Object {
            [ordered]@{ uniquename = [string]$_.uniquename; type = [int]$_.type }
        })
    }
    Get-Sha256 -Bytes ([Text.Encoding]::UTF8.GetBytes(
        (ConvertTo-Json -InputObject $canonical -Depth 20 -Compress)
    ))
}

function Get-BaselineContract {
    $v108 = Get-Content -LiteralPath (Join-Path $script:Root 'docs\CANDIDATE_CORE_1.0.8_RELEASE_MANIFEST.json') -Raw |
        ConvertFrom-Json
    $v109 = Get-Content -LiteralPath (Join-Path $script:Root 'docs\CANDIDATE_CORE_NORMAL_CREATE_1.0.9_RELEASE_MANIFEST.json') -Raw |
        ConvertFrom-Json
    $requests = @($v108.customApi.requestParameters | ForEach-Object {
        [pscustomobject]@{ Name = [string]$_.name; Type = [int]$_.type; IsOptional = [bool]$_.isOptional }
    })
    $responses = [Collections.Generic.List[object]]::new()
    foreach ($item in @($v108.customApi.responseProperties)) {
        $responses.Add([pscustomobject]@{ Name = [string]$item.name; Type = [int]$item.type })
    }
    foreach ($component in @($v109.exactComponentDelta | Where-Object kind -ceq 'CustomApiResponseProperty')) {
        $path = Join-Path $script:Root ([string]$component.sourceFile -replace '^\.\./', '')
        if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -cne
            [string]$component.sourceSha256) {
            throw "The 1.0.9 baseline response source has changed: $($component.uniqueName)."
        }
        $xml = [xml](Get-Content -LiteralPath $path -Raw)
        $responses.Add([pscustomobject]@{
            Name = ([string]$component.uniqueName -replace '^os_sr_cact\.', '')
            Type = [int]$xml.customapiresponseproperty.type
        })
    }
    if ($requests.Count -ne 22 -or $responses.Count -ne 9) {
        throw 'The versioned 1.0.9 baseline contract is not exactly 22 inputs and 9 outputs.'
    }
    [pscustomobject]@{ Requests = $requests; Responses = @($responses) }
}

function Get-ApiSnapshot {
    $solutions = @(Get-Rows -Path "solutions?%24select=solutionid,uniquename,ismanaged,_publisherid_value,version&%24filter=uniquename eq '$script:SolutionUniqueName'&%24top=2")
    $publishers = @(Get-Rows -Path "publishers?%24select=publisherid,uniquename,customizationprefix&%24filter=uniquename eq '$script:PublisherUniqueName'&%24top=2")
    if ($solutions.Count -ne 1 -or [bool]$solutions[0].ismanaged -or
        $publishers.Count -ne 1 -or [string]$publishers[0].customizationprefix -cne 'os' -or
        [string]$solutions[0]._publisherid_value -ine [string]$publishers[0].publisherid) {
        throw 'The existing project Solution or Publisher differs from the approved metadata boundary.'
    }
    $apis = @(Get-Rows -Path "customapis?%24select=customapiid,uniquename,name,displayname,description,executeprivilegename,bindingtype,isfunction,isprivate,allowedcustomprocessingsteptype,_plugintypeid_value&%24filter=uniquename eq 'os_sr_cact'&%24top=2")
    if ($apis.Count -ne 1 -or [string]$apis[0].executeprivilegename -cne 'prvReados_sr_cand' -or
        [bool]$apis[0].isprivate -ne $true -or [bool]$apis[0].isfunction -or
        [int]$apis[0].bindingtype -ne 0) {
        throw 'The existing os_sr_cact API security contract differs from 1.0.9.'
    }
    $api = $apis[0]
    $apiId = ConvertTo-CanonicalGuid ([string]$api.customapiid)
    $inputs = @(Get-Rows -Path "customapirequestparameters?%24select=customapirequestparameterid,uniquename,name,displayname,type,isoptional,logicalentityname,versionnumber,_customapiid_value&%24filter=_customapiid_value eq $apiId&%24top=100")
    $outputs = @(Get-Rows -Path "customapiresponseproperties?%24select=customapiresponsepropertyid,uniquename,name,displayname,type,versionnumber,_customapiid_value&%24filter=_customapiid_value eq $apiId&%24top=100")
    $baseline = Get-BaselineContract
    if ($script:IsPartialContinuation) {
        $baseline.Requests = @($baseline.Requests) + @($script:ExpectedDelta |
            Where-Object Kind -CEQ 'CustomApiRequestParameter' |
            ForEach-Object { [pscustomobject]@{ Name = $_.Name; Type = $_.Type; IsOptional = $true } })
        $baseline.Responses = @($baseline.Responses) + @($script:ExpectedDelta |
            Where-Object Name -CEQ 'ScopedHasNextPage' |
            ForEach-Object { [pscustomobject]@{ Name = $_.Name; Type = $_.Type } })
    }
    foreach ($pair in @(
        [pscustomobject]@{ Actual = $inputs; Expected = $baseline.Requests; Kind = 'request' },
        [pscustomobject]@{ Actual = $outputs; Expected = $baseline.Responses; Kind = 'response' }
    )) {
        $actualNames = @($pair.Actual | ForEach-Object { [string]$_.uniquename })
        $expectedNames = @($pair.Expected | ForEach-Object { [string]$_.Name })
        if (@($actualNames | Group-Object | Where-Object Count -ne 1).Count -gt 0 -or
            [string]::Join('|', @($actualNames | Sort-Object -CaseSensitive)) -cne
                [string]::Join('|', @($expectedNames | Sort-Object -CaseSensitive))) {
            throw ("The live Custom API {0} inventory differs from the 1.0.9 baseline " +
                "(actual={1}; expected={2})." -f $pair.Kind,
                [string]::Join(',', @($actualNames | Sort-Object -CaseSensitive)),
                [string]::Join(',', @($expectedNames | Sort-Object -CaseSensitive)))
        }
        foreach ($row in $pair.Actual) {
            $rowName = [string]$row.uniquename
            $expected = @($pair.Expected | Where-Object {
                [string]$_.Name -ceq $rowName
            })
            if ($expected.Count -ne 1) {
                throw "The 1.0.9 baseline has no unique $($pair.Kind) definition for $rowName."
            }
            if ([int]$row.type -ne [int]$expected[0].Type -or
                ($pair.Kind -ceq 'request' -and
                    [bool]$row.isoptional -ne [bool]$expected[0].IsOptional) -or
                [string]$row._customapiid_value -ine $apiId) {
                throw ("The live Custom API {0} definition {1} differs " +
                    "(type {2}/{3}; optional {4}/{5}; API binding match={6})." -f
                    $pair.Kind, $rowName, $row.type, $expected[0].Type,
                    $row.isoptional, $expected[0].IsOptional,
                    ([string]$row._customapiid_value -ieq $apiId))
            }
        }
    }
    $packageRows = @(Get-Rows -Path "pluginpackages?%24select=pluginpackageid,uniquename,version,modifiedon&%24filter=uniquename eq 'os_sr_cact_pkg'&%24top=2")
    if ($packageRows.Count -ne 1 -or [string]$packageRows[0].version -cne '1.0.0') {
        throw 'The existing Candidate Core package record does not match the 1.0.9 baseline.'
    }
    $typeRows = @(Get-Rows -Path "plugintypes?%24select=plugintypeid,typename,_pluginassemblyid_value&%24filter=plugintypeid eq $($api._plugintypeid_value)&%24top=2")
    if ($typeRows.Count -ne 1 -or [string]$typeRows[0].typename -cne 'os_sr_cact.ApplyCandidateAction') {
        throw 'The installed Custom API handler is not the expected Candidate Core handler.'
    }
    $relationshipRows = @(Get-Rows -Path "EntityDefinitions(LogicalName='pluginassembly')/ManyToOneRelationships?%24select=ReferencingAttribute,ReferencedEntity")
    $packageRelations = @($relationshipRows | Where-Object ReferencedEntity -ceq 'pluginpackage')
    if ($packageRelations.Count -ne 1) { throw 'The plug-in assembly/package relationship is missing or ambiguous.' }
    $packageLookup = "_$([string]$packageRelations[0].ReferencingAttribute)_value"
    $assemblies = @(Get-Rows -Path "pluginassemblies?%24select=pluginassemblyid,name,version,$packageLookup&%24filter=$packageLookup eq $($packageRows[0].pluginpackageid)&%24top=2")
    if ($assemblies.Count -ne 1 -or [string]$assemblies[0].name -cne 'os_sr_cact' -or
        [string]$assemblies[0].version -cne '1.0.9.0' -or
        [string]$assemblies[0].pluginassemblyid -ine [string]$typeRows[0]._pluginassemblyid_value) {
        throw 'The installed Candidate Core assembly/handler is not the exact 1.0.9 package-backed registration.'
    }
    $configDefinitions = @(Get-Rows -Path "environmentvariabledefinitions?%24select=environmentvariabledefinitionid,schemaname,statecode&%24filter=schemaname eq 'os_sr_ncrcfg'&%24top=2")
    if ($configDefinitions.Count -ne 1 -or [int]$configDefinitions[0].statecode -ne 0) {
        throw 'The organization-bound NORMAL Create configuration definition is missing or ambiguous.'
    }
    $configValues = @(Get-Rows -Path "environmentvariablevalues?%24select=environmentvariablevalueid,value,statecode,_environmentvariabledefinitionid_value&%24filter=_environmentvariabledefinitionid_value eq $($configDefinitions[0].environmentvariabledefinitionid) and statecode eq 0&%24top=2")
    $expectedGate = $script:ExpectedGateValue
    if ($configValues.Count -ne 1 -or [string]$configValues[0].value -cne $expectedGate) {
        throw 'The active organization-bound NORMAL Create value is not the expected disabled exact-org value.'
    }
    $requestEntity = Get-Api -Method GET -Path "EntityDefinitions(LogicalName='customapirequestparameter')?%24select=ObjectTypeCode"
    $responseEntity = Get-Api -Method GET -Path "EntityDefinitions(LogicalName='customapiresponseproperty')?%24select=ObjectTypeCode"
    $apiEntity = Get-Api -Method GET -Path "EntityDefinitions(LogicalName='customapi')?%24select=ObjectTypeCode"
    $solutionId = ConvertTo-CanonicalGuid ([string]$solutions[0].solutionid)
    $membership = @(Get-Rows -Path "solutioncomponents?%24select=componenttype,objectid,rootcomponentbehavior&%24filter=_solutionid_value eq $solutionId")
    $apiMembership = @($membership | Where-Object {
        [int]$_.componenttype -eq [int]$apiEntity.ObjectTypeCode -and
        [string]$_.objectid -ieq $apiId
    })
    if ($apiMembership.Count -ne 1) { throw 'The existing Custom API is not uniquely included in the project Solution.' }
    $apps = @(Get-Rows -Path "appmodules?%24select=appmoduleid,uniquename,statecode&%24filter=uniquename eq 'srapp'&%24top=2")
    if ($apps.Count -ne 1 -or [string]$apps[0].uniquename -cne 'srapp' -or
        [int]$apps[0].statecode -ne 0) {
        throw 'The approved srapp application module is missing, inactive, or ambiguous.'
    }
    $guardTypes = @(Get-Rows -Path "plugintypes?%24select=plugintypeid,typename&%24filter=typename eq 'os_sr_cact.ProtectCandidateCore'")
    $guardSteps = @()
    if ($guardTypes.Count -gt 0) {
        $typeIds = @($guardTypes | ForEach-Object { ConvertTo-CanonicalGuid ([string]$_.plugintypeid) })
        $filter = [string]::Join(' or ', @($typeIds | ForEach-Object { "_eventhandler_value eq $_" }))
        $guardSteps = @(Get-Rows -Path "sdkmessageprocessingsteps?%24select=sdkmessageprocessingstepid,statecode,_eventhandler_value&%24filter=($filter)")
    }
    $activeGuardSteps = @($guardSteps | Where-Object { [int]$_.statecode -eq 0 }).Count
    $disabledGuardSteps = @($guardSteps | Where-Object { [int]$_.statecode -eq 1 }).Count
    if ($activeGuardSteps + $disabledGuardSteps -ne $guardSteps.Count) {
        throw 'The legacy Candidate Core guard registrations include an unrecognized state.'
    }
    $sourceNames = @($script:ExpectedDelta | ForEach-Object UniqueName)
    $present = @(
        foreach ($item in $script:ExpectedDelta) {
            $table = if ($item.Kind -ceq 'CustomApiRequestParameter') { $inputs } else { $outputs }
            @($table | Where-Object uniquename -ceq $item.Name).Count
        }
    )
    if (-not $script:IsPartialContinuation -and @($present | Where-Object { $_ -ne 0 }).Count -gt 0) {
        throw 'The live API is not at the exact 1.0.9 pre-delta baseline; partial additions are not repaired.'
    }
    $membershipLines = @($membership | ForEach-Object {
        '{0}|{1}|{2}' -f [int]$_.componenttype, ([string]$_.objectid).ToLowerInvariant(),
            [int]$_.rootcomponentbehavior
    } | Sort-Object -CaseSensitive)
    $canonicalMembershipHash = Get-Sha256 -Bytes ([Text.Encoding]::UTF8.GetBytes(
        [string]::Join("`n", $membershipLines)
    ))
    $inputHash = Get-CanonicalApiHash -Api $api -Inputs $inputs -Outputs $outputs
    [pscustomobject]@{
        Api = $api
        ApiId = $apiId
        Inputs = $inputs
        Outputs = $outputs
        Package = $packageRows[0]
        Assembly = $assemblies[0]
        Handler = $typeRows[0]
        Solution = $solutions[0]
        App = $apps[0]
        Publisher = $publishers[0]
        GuardSteps = $guardSteps
        ActiveGuardSteps = $activeGuardSteps
        DisabledGuardSteps = $disabledGuardSteps
        Membership = $membership
        MembershipLines = $membershipLines
        MembershipSha256 = $canonicalMembershipHash
        ApiMetadataSha256 = $inputHash
        NormalCreateGate = [string]$configValues[0].value
        RequestComponentType = [int]$requestEntity.ObjectTypeCode
        ResponseComponentType = [int]$responseEntity.ObjectTypeCode
        ApiComponentType = [int]$apiEntity.ObjectTypeCode
    }
}

function Get-DeterministicComponentId {
    param([Parameter(Mandatory)][string]$UniqueName)
    $namespace = [Guid]::Parse('6ba7b811-9dad-11d1-80b4-00c04fd430c8')
    $namespaceBytes = [Convert]::FromHexString($namespace.ToString('N'))
    $nameBytes = [Text.Encoding]::UTF8.GetBytes(
        "urn:bso-rs-support:candidate-core:1.0.10:$UniqueName"
    )
    $inputBytes = [byte[]]::new($namespaceBytes.Length + $nameBytes.Length)
    [Array]::Copy($namespaceBytes, 0, $inputBytes, 0, $namespaceBytes.Length)
    [Array]::Copy($nameBytes, 0, $inputBytes, $namespaceBytes.Length, $nameBytes.Length)
    $digest = [Security.Cryptography.SHA1]::HashData($inputBytes)
    $uuidBytes = [byte[]]$digest[0..15]
    $uuidBytes[6] = [byte](($uuidBytes[6] -band 0x0f) -bor 0x50)
    $uuidBytes[8] = [byte](($uuidBytes[8] -band 0x3f) -bor 0x80)
    [Guid]::ParseExact([Convert]::ToHexString($uuidBytes), 'N').ToString('D').ToLowerInvariant()
}

function New-Plan {
    param([Parameter(Mandatory)][object]$Snapshot)
    $requestBinding = Get-RelationshipBinding -LogicalName 'customapirequestparameter'
    $responseBinding = Get-RelationshipBinding -LogicalName 'customapiresponseproperty'
    $writes = @(
        foreach ($item in $script:ExpectedDelta) {
            $isRequest = $item.Kind -ceq 'CustomApiRequestParameter'
            $idName = if ($isRequest) { 'customapirequestparameterid' } else { 'customapiresponsepropertyid' }
            $binding = if ($isRequest) { $requestBinding } else { $responseBinding }
            $componentType = if ($isRequest) { $Snapshot.RequestComponentType } else { $Snapshot.ResponseComponentType }
            $body = [ordered]@{
                $idName = Get-DeterministicComponentId -UniqueName ([string]$item.UniqueName)
                uniquename = $item.Name
                name = $item.UniqueName
                displayname = $item.DisplayName
                type = [int]$item.Type
                "$binding@odata.bind" = "/customapis($($Snapshot.ApiId))"
            }
            if ($isRequest) { $body.isoptional = $true }
            $path = if ($isRequest) { 'customapirequestparameters' } else { 'customapiresponseproperties' }
            $payload = ConvertTo-Json -InputObject $body -Depth 20 -Compress
            [ordered]@{
                Id = [string]$body[$idName]
                Kind = $item.Kind
                Name = $item.Name
                UniqueName = $item.UniqueName
                Type = [int]$item.Type
                IsOptional = $item.IsOptional
                Path = $path
                BindingProperty = $binding
                ComponentType = [int]$componentType
                Body = $body
                PayloadSha256 = Get-Sha256 -Bytes ([Text.Encoding]::UTF8.GetBytes($payload))
            }
        }
    )
    $baselineLines = @($Snapshot.MembershipLines)
    $addedLines = @($writes | ForEach-Object {
        '{0}|{1}|0' -f [int]$_.ComponentType, ([string]$_.Id).ToLowerInvariant()
    } | Sort-Object -CaseSensitive)
    $expectedLines = @($baselineLines + $addedLines | Sort-Object -CaseSensitive)
    $expectedInputs = @(
        @($Snapshot.Inputs | ForEach-Object {
            [pscustomobject]@{
                uniquename = [string]$_.uniquename
                type = [int]$_.type
                isoptional = [bool]$_.isoptional
                logicalentityname = [string]$_.logicalentityname
            }
        }) + @($writes | Where-Object Kind -ceq 'CustomApiRequestParameter' | ForEach-Object {
            [pscustomobject]@{
                uniquename = [string]$_.Name
                type = [int]$_.Type
                isoptional = [bool]$_.IsOptional
                logicalentityname = ''
            }
        }) | Sort-Object uniquename -CaseSensitive
    )
    $expectedOutputs = @(
        @($Snapshot.Outputs | ForEach-Object {
            [pscustomobject]@{ uniquename = [string]$_.uniquename; type = [int]$_.type }
        }) + @($writes | Where-Object Kind -ceq 'CustomApiResponseProperty' | ForEach-Object {
            [pscustomobject]@{ uniquename = [string]$_.Name; type = [int]$_.Type }
        }) | Sort-Object uniquename -CaseSensitive
    )
    $baseline = [ordered]@{
        Classification = 'OWNER_DEV_FUNCTIONAL_IDENTITY'
        OrganizationUrl = $script:OrganizationUrl
        EnvironmentId = $ExpectedEnvironmentId.ToLowerInvariant()
        OrganizationId = $ExpectedOrganizationId.ToLowerInvariant()
        Solution = [ordered]@{
            solutionid = [string]$Snapshot.Solution.solutionid
            version = [string]$Snapshot.Solution.version
        }
        App = [ordered]@{ appmoduleid = [string]$Snapshot.App.appmoduleid }
        Api = [ordered]@{ customapiid = $Snapshot.ApiId }
        Package = [ordered]@{
            pluginpackageid = [string]$Snapshot.Package.pluginpackageid
            modifiedon = [string]$Snapshot.Package.modifiedon
        }
        Assembly = [ordered]@{
            pluginassemblyid = [string]$Snapshot.Assembly.pluginassemblyid
            version = [string]$Snapshot.Assembly.version
        }
        Handler = [ordered]@{ plugintypeid = [string]$Snapshot.Handler.plugintypeid }
        Guards = [ordered]@{
            LegacySteps = [int]$Snapshot.GuardSteps.Count
            ActiveLegacySteps = [int]$Snapshot.ActiveGuardSteps
            DisabledLegacySteps = [int]$Snapshot.DisabledGuardSteps
        }
        Memberships = @($Snapshot.Membership | ForEach-Object {
            [ordered]@{
                componenttype = [int]$_.componenttype
                objectid = [string]$_.objectid
                rootcomponentbehavior = [int]$_.rootcomponentbehavior
            }
        })
        ApiMetadataSha256 = [string]$Snapshot.ApiMetadataSha256
        NormalCreateGate = [string]$Snapshot.NormalCreateGate
    }
    $baselineSnapshot = [ordered]@{
        ApiMetadataSha256 = [string]$Snapshot.ApiMetadataSha256
        MembershipSha256 = [string]$Snapshot.MembershipSha256
        PackageId = [string]$Snapshot.Package.pluginpackageid
        PackageModifiedOn = [string]$Snapshot.Package.modifiedon
        AssemblyId = [string]$Snapshot.Assembly.pluginassemblyid
        AssemblyVersion = [string]$Snapshot.Assembly.version
        HandlerId = [string]$Snapshot.Handler.plugintypeid
        OrganizationId = $ExpectedOrganizationId.ToLowerInvariant()
        Gate = [bool]$script:Manifest.release.reportedBaseline.normalCreateEnabled
    }
    $plan = [ordered]@{
        PlanVersion = 1
        EnvironmentName = $EnvironmentName
        OrganizationUrl = $script:OrganizationUrl
        ExpectedEnvironmentId = $ExpectedEnvironmentId.ToLowerInvariant()
        ExpectedOrganizationId = $ExpectedOrganizationId.ToLowerInvariant()
        SolutionUniqueName = $script:SolutionUniqueName
        SolutionId = [string]$Snapshot.Solution.solutionid
        PublisherUniqueName = $script:PublisherUniqueName
        ApiUniqueName = 'os_sr_cact'
        ApiId = $Snapshot.ApiId
        NormalCreateGate = [string]$Snapshot.NormalCreateGate
        ReleaseManifestSha256 = (Get-FileHash -LiteralPath $ReleaseManifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
        BaselineApiMetadataSha256 = [string]$Snapshot.ApiMetadataSha256
        BaselineSnapshotSha256 = Get-Sha256 -Bytes ([Text.Encoding]::UTF8.GetBytes(
            (ConvertTo-Json -InputObject $baselineSnapshot -Depth 10 -Compress)
        ))
        BaselineMembershipSha256 = [string]$Snapshot.MembershipSha256
        BaselineMembershipLines = $baselineLines
        ExpectedAddedMembershipLines = $addedLines
        ExpectedMembershipSha256 = Get-Sha256 -Bytes ([Text.Encoding]::UTF8.GetBytes(
            [string]::Join("`n", $expectedLines)
        ))
        ExpectedApiMetadataSha256 = Get-CanonicalApiHash -Api $Snapshot.Api `
            -Inputs $expectedInputs -Outputs $expectedOutputs
        ExpectedMissingNames = @($script:ExpectedDelta | ForEach-Object UniqueName)
        BaselineRequestParameters = @($Snapshot.Inputs | ForEach-Object {
            [ordered]@{ name = [string]$_.uniquename; type = [int]$_.type; isOptional = [bool]$_.isoptional }
        } | Sort-Object name -CaseSensitive)
        BaselineResponseProperties = @($Snapshot.Outputs | ForEach-Object {
            [ordered]@{ name = [string]$_.uniquename; type = [int]$_.type }
        } | Sort-Object name -CaseSensitive)
        ExpectedRequestParameters = @(
            @($Snapshot.Inputs | ForEach-Object {
                [ordered]@{ name = [string]$_.uniquename; type = [int]$_.type; isOptional = [bool]$_.isoptional }
            }) + @($writes | Where-Object Kind -ceq 'CustomApiRequestParameter' | ForEach-Object {
                [ordered]@{ name = [string]$_.Name; type = [int]$_.Type; isOptional = $true }
            }) | Sort-Object name -CaseSensitive
        )
        ExpectedResponseProperties = @(
            @($Snapshot.Outputs | ForEach-Object {
                [ordered]@{ name = [string]$_.uniquename; type = [int]$_.type }
            }) + @($writes | Where-Object Kind -ceq 'CustomApiResponseProperty' | ForEach-Object {
                [ordered]@{ name = [string]$_.Name; type = [int]$_.Type }
            }) | Sort-Object name -CaseSensitive
        )
        Writes = $writes
        AutomaticRetries = 0
        MaximumPostDispatches = 5
    }
    [pscustomobject]@{ Plan = $plan; Baseline = $baseline }
}

function Assert-Plan {
    param(
        [Parameter(Mandatory)][object]$Plan,
        [Parameter(Mandatory)][string]$ExpectedApiId,
        [Parameter(Mandatory)][string]$ExpectedSolutionId
    )
    $hash = (Get-FileHash -LiteralPath $PlanPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($hash -cne $ExpectedPlanSha256 -or
        [string]$Plan.ReleaseManifestSha256 -cne
            (Get-FileHash -LiteralPath $ReleaseManifestPath -Algorithm SHA256).Hash.ToLowerInvariant() -or
        [string]$Plan.OrganizationUrl -cne $script:OrganizationUrl -or
        (ConvertTo-CanonicalGuid ([string]$Plan.ExpectedEnvironmentId)) -cne $ExpectedEnvironmentId.ToLowerInvariant() -or
        (ConvertTo-CanonicalGuid ([string]$Plan.ExpectedOrganizationId)) -cne $ExpectedOrganizationId.ToLowerInvariant() -or
        [string]$Plan.PublisherUniqueName -cne $script:PublisherUniqueName -or
        (ConvertTo-CanonicalGuid ([string]$Plan.SolutionId)) -cne
            (ConvertTo-CanonicalGuid $ExpectedSolutionId) -or
        (ConvertTo-CanonicalGuid ([string]$Plan.ApiId)) -cne (ConvertTo-CanonicalGuid $ExpectedApiId) -or
        [string]$Plan.ApiUniqueName -cne 'os_sr_cact' -or
        [string]$Plan.NormalCreateGate -cne $script:ExpectedGateValue -or
        [string]$Plan.SolutionUniqueName -cne $script:SolutionUniqueName -or
        [int]$Plan.AutomaticRetries -ne 0 -or
        [int]$Plan.MaximumPostDispatches -ne 5 -or
        @($Plan.Writes).Count -ne 5 -or
        [string]::Join('|', @($Plan.ExpectedMissingNames | Sort-Object -CaseSensitive)) -cne
            [string]::Join('|', @($script:ExpectedDelta | ForEach-Object UniqueName | Sort-Object -CaseSensitive))) {
        throw 'The pinned plan does not match the exact 1.0.10 five-component metadata delta.'
    }
    $Plan
}

function Assert-WriteReadback {
    param([Parameter(Mandatory)][object]$Write)
    $idField = if ($Write.Kind -ceq 'CustomApiRequestParameter') {
        'customapirequestparameterid'
    } else { 'customapiresponsepropertyid' }
    $optionalField = if ($Write.Kind -ceq 'CustomApiRequestParameter') { ',isoptional' } else { '' }
    $path = "$($Write.Path)?%24select=$idField,uniquename,name,displayname,type$optionalField,_customapiid_value&%24filter=_customapiid_value eq $($script:Plan.ApiId) and $idField eq $($Write.Id)&%24top=2"
    $rows = @(Get-Rows -Path $path)
    if ($rows.Count -ne 1 -or
        [string]$rows[0].$idField -ine [string]$Write.Id -or
        [string]$rows[0].uniquename -cne [string]$Write.Name -or
        [string]$rows[0].name -cne [string]$Write.Body.name -or
        [string]$rows[0].displayname -cne [string]$Write.Body.displayname -or
        [int]$rows[0].type -ne [int]$Write.Type -or
        [string]$rows[0]._customapiid_value -ine [string]$script:Plan.ApiId -or
        ($Write.Kind -ceq 'CustomApiRequestParameter' -and
            [bool]$rows[0].isoptional -ne [bool]$Write.IsOptional)) {
        throw "Created Custom API metadata did not reconcile exactly: $($Write.UniqueName)."
    }
    $components = @(Get-Rows -Path "solutioncomponents?%24select=objectid,componenttype,rootcomponentbehavior&%24filter=_solutionid_value eq $($script:Plan.SolutionId) and objectid eq $($Write.Id)&%24top=2")
    if ($components.Count -ne 1 -or
        [string]$components[0].objectid -ine [string]$Write.Id -or
        [int]$components[0].componenttype -ne [int]$Write.ComponentType -or
        [int]$components[0].rootcomponentbehavior -ne 0) {
        throw "Created Custom API metadata is not uniquely included in the project Solution: $($Write.UniqueName)."
    }
}

function Assert-CompleteMetadataContract {
    $api = Get-Api -Method GET -Path "customapis($($script:Plan.ApiId))?%24select=customapiid,uniquename,name,displayname,description,executeprivilegename,bindingtype,isfunction,isprivate,allowedcustomprocessingsteptype,_plugintypeid_value"
    $inputs = @(Get-Rows -Path "customapirequestparameters?%24select=uniquename,type,isoptional,logicalentityname,_customapiid_value&%24filter=_customapiid_value eq $($script:Plan.ApiId)&%24top=100")
    $outputs = @(Get-Rows -Path "customapiresponseproperties?%24select=uniquename,type,_customapiid_value&%24filter=_customapiid_value eq $($script:Plan.ApiId)&%24top=100")
    $actualInputs = @($inputs | ForEach-Object {
        '{0}|{1}|{2}' -f [string]$_.uniquename, [int]$_.type, [bool]$_.isoptional
    } | Sort-Object -CaseSensitive)
    $expectedInputs = @($script:Plan.ExpectedRequestParameters | ForEach-Object {
        '{0}|{1}|{2}' -f [string]$_.name, [int]$_.type, [bool]$_.isOptional
    } | Sort-Object -CaseSensitive)
    $actualOutputs = @($outputs | ForEach-Object {
        '{0}|{1}' -f [string]$_.uniquename, [int]$_.type
    } | Sort-Object -CaseSensitive)
    $expectedOutputs = @($script:Plan.ExpectedResponseProperties | ForEach-Object {
        '{0}|{1}' -f [string]$_.name, [int]$_.type
    } | Sort-Object -CaseSensitive)
    if ($inputs.Count -ne 25 -or $outputs.Count -ne 11 -or
        [string]::Join('|', $actualInputs) -cne [string]::Join('|', $expectedInputs) -or
        [string]::Join('|', $actualOutputs) -cne [string]::Join('|', $expectedOutputs) -or
        @($inputs | Where-Object { [string]$_._customapiid_value -ine [string]$script:Plan.ApiId }).Count -gt 0 -or
        @($outputs | Where-Object { [string]$_._customapiid_value -ine [string]$script:Plan.ApiId }).Count -gt 0) {
        throw 'Final Custom API metadata does not match exactly 25 request parameters and 11 response properties.'
    }
    $apiHash = Get-CanonicalApiHash -Api $api -Inputs $inputs -Outputs $outputs
    if ($apiHash -cne [string]$script:Plan.ExpectedApiMetadataSha256) {
        throw 'Final Custom API metadata fingerprint differs from the planned additive result.'
    }
    $membership = @(Get-Rows -Path "solutioncomponents?%24select=componenttype,objectid,rootcomponentbehavior&%24filter=_solutionid_value eq $($script:Plan.SolutionId)")
    $lines = @($membership | ForEach-Object {
        '{0}|{1}|{2}' -f [int]$_.componenttype, ([string]$_.objectid).ToLowerInvariant(),
            [int]$_.rootcomponentbehavior
    } | Sort-Object -CaseSensitive)
    $membershipHash = Get-Sha256 -Bytes ([Text.Encoding]::UTF8.GetBytes([string]::Join("`n", $lines)))
    if ($membershipHash -cne [string]$script:Plan.ExpectedMembershipSha256 -or
        $membership.Count -ne $script:Plan.BaselineMembershipLines.Count + 5) {
        throw 'Final Solution membership does not equal the original inventory plus the five planned components.'
    }
    [pscustomobject]@{
        ApiMetadataSha256 = $apiHash
        ApiRequestParameterCount = $inputs.Count
        ApiResponsePropertyCount = $outputs.Count
        SolutionMembershipCount = $membership.Count
        SolutionMembershipSha256 = $membershipHash
    }
}

function Assert-PartialJournal {
    param([Parameter(Mandatory)][object]$PriorJournal, [Parameter(Mandatory)][object]$OriginalPlan)
    if ($PriorJournal.PlanSha256 -cne $ExpectedPlanSha256 -or
        $PriorJournal.ApiUniqueName -cne 'os_sr_cact' -or
        $PriorJournal.Outcome -cne 'STOPPED_WITHOUT_RETRY' -or
        $PriorJournal.AutomaticRetries -ne 0 -or $PriorJournal.MaximumPostDispatches -ne 5 -or
        $PriorJournal.RequestCounters.POST -ne 4 -or @($PriorJournal.Writes).Count -ne 5 -or
        @($OriginalPlan.Writes).Count -ne 5) {
        throw 'Prior journal is not the exact four-dispatch partial deployment.'
    }
    foreach ($index in 0..4) {
        $entry = $PriorJournal.Writes[$index]
        $write = $OriginalPlan.Writes[$index]
        $expectedState = if ($index -lt 3) { 'GET_RECONCILED' }
            elseif ($index -eq 3) { 'ACKNOWLEDGED' } else { 'PLANNED' }
        if ($entry.Name -cne $write.Name -or $entry.Kind -cne $write.Kind -or
            $entry.Id -cne $write.Id -or $entry.State -cne $expectedState -or
            ($index -lt 4 -and $entry.HttpStatus -ne 204) -or
            ($index -eq 4 -and $null -ne $entry.HttpStatus)) {
            throw 'Prior journal differs from the original ordered component dispatches.'
        }
    }
    if ($OriginalPlan.Writes[3].Name -cne 'ScopedHasNextPage' -or
        $OriginalPlan.Writes[4].Name -cne 'ScopedTotalCount' -or
        $OriginalPlan.Writes[4].Kind -cne 'CustomApiResponseProperty') {
        throw 'Continuation is limited to the missing ScopedTotalCount response.'
    }
}

function Get-PartialState {
    param([Parameter(Mandatory)][object]$Snapshot)
    $prior = Get-Content -LiteralPath $PriorJournalPath -Raw | ConvertFrom-Json
    Assert-PartialJournal -PriorJournal $prior -OriginalPlan $script:Plan
    $baseline = Get-Content -LiteralPath $BaselinePath -Raw | ConvertFrom-Json
    if ($Snapshot.Assembly.version -cne [string]$baseline.Assembly.version -or
        $Snapshot.Assembly.pluginassemblyid -ine [string]$baseline.Assembly.pluginassemblyid -or
        $Snapshot.Package.pluginpackageid -ine [string]$baseline.Package.pluginpackageid -or
        [string]$Snapshot.Package.modifiedon -cne [string]$baseline.Package.modifiedon -or
        $Snapshot.Handler.plugintypeid -ine [string]$baseline.Handler.plugintypeid -or
        $Snapshot.ApiId -ine [string]$baseline.Api.customapiid -or
        $Snapshot.NormalCreateGate -cne [string]$baseline.NormalCreateGate -or
        $Snapshot.Solution.solutionid -ine [string]$baseline.Solution.solutionid -or
        $Snapshot.Solution.version -cne [string]$baseline.Solution.version -or
        $Snapshot.App.appmoduleid -ine [string]$baseline.App.appmoduleid -or
        $Snapshot.GuardSteps.Count -ne $baseline.Guards.LegacySteps -or
        $Snapshot.ActiveGuardSteps -ne $baseline.Guards.ActiveLegacySteps -or
        $Snapshot.DisabledGuardSteps -ne $baseline.Guards.DisabledLegacySteps) {
        throw 'Package, handler or gate differs from the immutable original baseline.'
    }
    $versions = @(
        foreach ($write in $script:Plan.Writes[0..3]) {
            Assert-WriteReadback -Write $write
            $rows = if ($write.Kind -ceq 'CustomApiRequestParameter') { $Snapshot.Inputs } else { $Snapshot.Outputs }
            $row = @($rows | Where-Object { $_.uniquename -ceq $write.Name })
            if ($row.Count -ne 1 -or -not $row[0].versionnumber -or
                -not $row[0].PSObject.Properties['@odata.etag']) {
                throw 'Partial component version is missing or ambiguous.'
            }
            [ordered]@{
                Id = $write.Id; Name = $write.Name; Type = $write.Type
                Version = [string]$row[0].versionnumber; ETag = [string]$row[0].'@odata.etag'
            }
        }
    )
    $missing = $script:Plan.Writes[4]
    $conflicts = @(Get-Rows -Path ("customapiresponseproperties?%24select=customapiresponsepropertyid&" +
        "%24filter=customapiresponsepropertyid eq $($missing.Id) or " +
        "(_customapiid_value eq $($script:Plan.ApiId) and uniquename eq '$($missing.Name)')&%24top=2"))
    if ($conflicts.Count -ne 0) { throw 'ScopedTotalCount is present or its planned ID conflicts; no POST is permitted.' }
    $priorIds = @($script:Plan.Writes[0..3] | ForEach-Object Id)
    $original = $Snapshot.PSObject.Copy()
    $original.Inputs = @($Snapshot.Inputs | Where-Object { $_.uniquename -notin @($script:Plan.Writes[0..2].Name) })
    $original.Outputs = @($Snapshot.Outputs | Where-Object uniquename -CNE 'ScopedHasNextPage')
    $original.Membership = @($Snapshot.Membership | Where-Object { $_.objectid -notin $priorIds })
    $original.MembershipLines = @($original.Membership | ForEach-Object {
        '{0}|{1}|{2}' -f [int]$_.componenttype, ([string]$_.objectid).ToLowerInvariant(), [int]$_.rootcomponentbehavior
    } | Sort-Object -CaseSensitive)
    $original.MembershipSha256 = Get-Sha256 -Bytes ([Text.Encoding]::UTF8.GetBytes(
        [string]::Join("`n", $original.MembershipLines)))
    $original.ApiMetadataSha256 = Get-CanonicalApiHash -Api $Snapshot.Api -Inputs $original.Inputs -Outputs $original.Outputs
    $rebuilt = (New-Plan -Snapshot $original).Plan
    foreach ($property in @('BaselineSnapshotSha256', 'BaselineMembershipSha256',
        'BaselineApiMetadataSha256', 'ExpectedApiMetadataSha256', 'ExpectedMembershipSha256')) {
        if ([string]$rebuilt[$property] -cne [string]$script:Plan.$property) {
            throw "Partial-state original plan reconstruction failed: $property."
        }
    }
    if ((ConvertTo-Json -InputObject $rebuilt.Writes -Depth 20 -Compress) -cne
        (ConvertTo-Json -InputObject $script:Plan.Writes -Depth 20 -Compress) -or
        $Snapshot.Membership.Count -ne $original.Membership.Count + 4) {
        throw 'Partial-state payloads or membership differ from the original release.'
    }
    [ordered]@{
        ApiMetadataSha256 = $Snapshot.ApiMetadataSha256
        ApiVersion = [string]$Snapshot.Api.'@odata.etag'
        MembershipSha256 = $Snapshot.MembershipSha256
        PackageVersion = [string]$Snapshot.Package.'@odata.etag'
        AssemblyVersion = [string]$Snapshot.Assembly.'@odata.etag'
        HandlerVersion = [string]$Snapshot.Handler.'@odata.etag'
        SolutionVersion = [string]$Snapshot.Solution.'@odata.etag'
        AppVersion = [string]$Snapshot.App.'@odata.etag'
        NormalCreateGate = $Snapshot.NormalCreateGate
        InstalledAssemblyVersion = $Snapshot.Assembly.version
        PriorComponents = $versions
        PriorJournalSha256 = (Get-FileHash -LiteralPath $PriorJournalPath -Algorithm SHA256).Hash.ToLowerInvariant()
        BaselineSha256 = (Get-FileHash -LiteralPath $BaselinePath -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}

function Assert-PreservedComponentVersions {
    param([Parameter(Mandatory)][object[]]$Components)
    foreach ($component in $Components) {
        $write = @($script:Plan.Writes[0..3] | Where-Object Id -CEQ $component.Id)
        if ($write.Count -ne 1) { throw 'Preserved component is outside the original four additions.' }
        $row = Get-Api -Method GET -Path "$($write[0].Path)($($component.Id))?%24select=versionnumber"
        if ([string]$row.versionnumber -cne [string]$component.Version -or
            [string]$row.'@odata.etag' -cne [string]$component.ETag) {
            throw "A previously applied component changed version: $($component.Name)."
        }
    }
}

function Invoke-PartialContinuation {
    $script:Plan = Get-Content -LiteralPath $PlanPath -Raw | ConvertFrom-Json
    $script:Plan = Assert-Plan -Plan $script:Plan -ExpectedApiId $script:Plan.ApiId `
        -ExpectedSolutionId $script:Plan.SolutionId
    if ((Get-FileHash -LiteralPath $PriorJournalPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne
        $ExpectedPriorJournalSha256) { throw 'The immutable prior journal hash does not match.' }
    $state = Get-PartialState -Snapshot (Get-ApiSnapshot)
    if ($Mode -ceq 'PartialPreflight') {
        $continuation = [ordered]@{
            ContinuationId = [Guid]::NewGuid().ToString('D')
            OriginalPlanSha256 = $ExpectedPlanSha256
            PriorJournalSha256 = $ExpectedPriorJournalSha256
            ReleaseManifestSha256 = $script:Plan.ReleaseManifestSha256
            PartialState = $state
            MaximumPostDispatches = 1
            Write = $script:Plan.Writes[4]
        }
        Save-Json -Path $ContinuationPlanPath -Value $continuation -CreateNew
        return [pscustomobject]@{
            Outcome = 'PARTIAL_METADATA_RECONCILED_CONTINUATION_READY'
            ContinuationId = $continuation.ContinuationId
            ContinuationPlanSha256 = (Get-FileHash -LiteralPath $ContinuationPlanPath -Algorithm SHA256).Hash.ToLowerInvariant()
            PriorComponents = $state.PriorComponents
            MissingOutput = 'ScopedTotalCount'
            RequestCounters = $script:RequestCounts
        }
    }
    if ((Get-FileHash -LiteralPath $ContinuationPlanPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne
        $ExpectedContinuationPlanSha256) { throw 'Continuation plan hash does not match.' }
    $continuation = Get-Content -LiteralPath $ContinuationPlanPath -Raw | ConvertFrom-Json
    $null = ConvertTo-CanonicalGuid $continuation.ContinuationId
    if ($continuation.OriginalPlanSha256 -cne $ExpectedPlanSha256 -or
        $continuation.PriorJournalSha256 -cne $ExpectedPriorJournalSha256 -or
        $continuation.ReleaseManifestSha256 -cne $script:Plan.ReleaseManifestSha256 -or
        $continuation.MaximumPostDispatches -ne 1 -or
        (ConvertTo-Json -InputObject $continuation.PartialState -Depth 20 -Compress) -cne
            (ConvertTo-Json -InputObject $state -Depth 20 -Compress) -or
        (ConvertTo-Json -InputObject $continuation.Write -Depth 20 -Compress) -cne
            (ConvertTo-Json -InputObject $script:Plan.Writes[4] -Depth 20 -Compress)) {
        throw 'Continuation target, prior journal or fresh component versions differ from preflight.'
    }
    $freshState = Get-PartialState -Snapshot (Get-ApiSnapshot)
    if ((ConvertTo-Json -InputObject $freshState -Depth 20 -Compress) -cne
        (ConvertTo-Json -InputObject $state -Depth 20 -Compress)) {
        throw 'Partial baseline changed immediately before continuation dispatch.'
    }
    $script:Journal = [ordered]@{
        ContinuationId = $continuation.ContinuationId
        ContinuationPlanSha256 = $ExpectedContinuationPlanSha256
        PriorJournalSha256 = $ExpectedPriorJournalSha256
        Writes = @($script:Plan.Writes | ForEach-Object {
            [ordered]@{ Name = $_.Name; Id = $_.Id; State = 'PRESERVED_NOT_DISPATCHED' }
        })
        Outcome = 'DISPATCH_RESERVED'
        AutomaticRetries = 0
        RequestCounters = $script:RequestCounts
    }
    $script:Journal.Writes[4].State = 'DISPATCH_RESERVED'
    Save-Json -Path $EvidencePath -Value $script:Journal -CreateNew
    $script:JournalOwned = $true
    $script:WriteIndex = 4
    $write = $script:Plan.Writes[4]
    $null = Get-Api -Method POST -Path $write.Path -Body $write.Body
    $script:Journal.Writes[4].State = 'ACKNOWLEDGED'
    Save-Json -Path $EvidencePath -Value $script:Journal
    Assert-WriteReadback -Write $write
    foreach ($prior in $script:Plan.Writes[0..3]) { Assert-WriteReadback -Write $prior }
    Assert-PreservedComponentVersions -Components $state.PriorComponents
    $script:Journal.Writes[4].State = 'GET_RECONCILED'
    $script:Journal.FinalContract = Assert-CompleteMetadataContract
    $script:Journal.Outcome = 'CANDIDATE_PAGINATION_API_METADATA_RECONCILED'
    Save-Json -Path $EvidencePath -Value $script:Journal
    [pscustomobject]@{
        Outcome = $script:Journal.Outcome
        ContinuationId = $continuation.ContinuationId
        FinalContract = $script:Journal.FinalContract
        RequestCounters = $script:RequestCounts
        PriorJournalUnchanged = ((Get-FileHash -LiteralPath $PriorJournalPath -Algorithm SHA256).Hash.ToLowerInvariant() -ceq
            $ExpectedPriorJournalSha256)
    }
}

try {
    $helperPath = Join-Path $PSScriptRoot 'Provision-BsoRsCandidateChildTables.ps1'
    $tokens = $null
    $parseErrors = $null
    $helperAst = [System.Management.Automation.Language.Parser]::ParseFile($helperPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count) { throw 'The guarded PAC identity helper has parser errors.' }
    foreach ($functionName in @('Assert-TargetInput', 'Assert-PacIdentity', 'Get-ValidatedToken')) {
        $definitions = @($helperAst.EndBlock.Statements | Where-Object {
            $_ -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $_.Name -ceq $functionName
        })
        if ($definitions.Count -ne 1) { throw "Required guarded identity helper is missing or ambiguous: $functionName" }
        . ([scriptblock]::Create($definitions[0].Extent.Text))
    }
    Assert-TargetInput
    Assert-PacIdentity
    Get-ValidatedToken
    $script:ApiRoot = $script:OrganizationUrl + '/api/data/v9.2/'
    $who = Get-Api -Method GET -Path 'WhoAmI'
    if ((ConvertTo-CanonicalGuid ([string]$who.OrganizationId)) -cne
        (ConvertTo-CanonicalGuid $ExpectedOrganizationId) -or
        (ConvertTo-CanonicalGuid ([string]$who.UserId)) -cne $script:ExpectedUserId) {
        throw 'Dataverse WhoAmI does not match the PAC identity and exact organization.'
    }
    $script:ExpectedDelta = Get-SourceDelta
    if ($script:IsPartialContinuation) {
        foreach ($path in @($PriorJournalPath, $PlanPath, $BaselinePath)) {
            $script:EvidenceLocks.Add([IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read))
        }
        if ($Mode -ceq 'ContinuePartial') {
            $script:EvidenceLocks.Add([IO.File]::Open($ContinuationPlanPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read))
        }
        Invoke-PartialContinuation
        return
    }
    $snapshot = Get-ApiSnapshot

    if ($Mode -ceq 'Preflight') {
        $planned = New-Plan -Snapshot $snapshot
        Save-Json -Path $PlanPath -Value $planned.Plan -CreateNew
        Save-Json -Path $BaselinePath -Value $planned.Baseline -CreateNew
        [pscustomobject]@{
            Outcome = 'CANDIDATE_PAGINATION_API_METADATA_PLAN_READY_NOT_DISPATCHED'
            RequestParameters = 3
            ResponseProperties = 2
            PlannedPOST = 5
            NormalCreateEnabled = [bool]$script:Manifest.release.reportedBaseline.normalCreateEnabled
            CandidateCoreAssemblyVersion = [string]$snapshot.Assembly.version
            ApiMetadataSha256 = $snapshot.ApiMetadataSha256
            PlanSha256 = (Get-FileHash -LiteralPath $PlanPath -Algorithm SHA256).Hash.ToLowerInvariant()
            BaselinePath = [IO.Path]::GetFullPath($BaselinePath)
            RequestCounters = $script:RequestCounts
            AutomaticRetries = 0
        }
        return
    }

    $script:Plan = Get-Content -LiteralPath $PlanPath -Raw | ConvertFrom-Json
    $script:Plan = Assert-Plan -Plan $script:Plan `
        -ExpectedApiId ([string]$snapshot.ApiId) `
        -ExpectedSolutionId ([string]$snapshot.Solution.solutionid)
    if ($Mode -ceq 'Apply') {
        $baselineHash = Get-Sha256 -Bytes ([Text.Encoding]::UTF8.GetBytes(
            (ConvertTo-Json -InputObject ([ordered]@{
                ApiMetadataSha256 = $snapshot.ApiMetadataSha256
                MembershipSha256 = $snapshot.MembershipSha256
                PackageId = [string]$snapshot.Package.pluginpackageid
                PackageModifiedOn = [string]$snapshot.Package.modifiedon
                AssemblyId = [string]$snapshot.Assembly.pluginassemblyid
                AssemblyVersion = [string]$snapshot.Assembly.version
                HandlerId = [string]$snapshot.Handler.plugintypeid
                OrganizationId = $ExpectedOrganizationId.ToLowerInvariant()
                Gate = [bool]$script:Manifest.release.reportedBaseline.normalCreateEnabled
            }) -Depth 10 -Compress)
        ))
        if ($snapshot.ApiId -ine [string]$script:Plan.ApiId -or
            $snapshot.ApiMetadataSha256 -cne [string]$script:Plan.BaselineApiMetadataSha256 -or
            $baselineHash -cne [string]$script:Plan.BaselineSnapshotSha256 -or
            $snapshot.MembershipSha256 -cne [string]$script:Plan.BaselineMembershipSha256 -or
            [string]::Join('|', $snapshot.MembershipLines) -cne
                [string]::Join('|', @($script:Plan.BaselineMembershipLines | Sort-Object -CaseSensitive)) -or
            $snapshot.Assembly.version -cne '1.0.9.0' -or
            $snapshot.Api.executeprivilegename -cne 'prvReados_sr_cand' -or
            $snapshot.Inputs.Count -ne 22 -or $snapshot.Outputs.Count -ne 9) {
            throw 'The exact 1.0.9 API/package/gate/membership baseline changed after planning.'
        }
        $script:Journal = [ordered]@{
            PlanSha256 = $ExpectedPlanSha256.ToLowerInvariant()
            ApiUniqueName = 'os_sr_cact'
            Writes = @($script:Plan.Writes | ForEach-Object {
                [ordered]@{ Name = $_.Name; Kind = $_.Kind; Id = $_.Id; State = 'PLANNED'; HttpStatus = $null }
            })
            AutomaticRetries = 0
            MaximumPostDispatches = 5
            Outcome = 'IN_PROGRESS'
        }
        Save-Json -Path $EvidencePath -Value $script:Journal -CreateNew
        $script:JournalOwned = $true
        for ($index = 0; $index -lt $script:Plan.Writes.Count; $index++) {
            $write = $script:Plan.Writes[$index]
            $entitySet = [string]$write.Path
            $duplicates = @(Get-Rows -Path "${entitySet}?%24select=uniquename&%24filter=_customapiid_value eq $($script:Plan.ApiId) and uniquename eq '$($write.Name)'&%24top=2")
            if ($duplicates.Count -ne 0) { throw "Metadata appeared after preflight; stop before dispatch: $($write.UniqueName)." }
            $script:Journal.Writes[$index].State = 'DISPATCH_RESERVED'
            Save-Json -Path $EvidencePath -Value $script:Journal
            $null = Get-Api -Method POST -Path $write.Path -Body $write.Body
            $script:Journal.Writes[$index].HttpStatus = 204
            $script:Journal.Writes[$index].State = 'ACKNOWLEDGED'
            Save-Json -Path $EvidencePath -Value $script:Journal
            Assert-WriteReadback -Write $write
            $script:Journal.Writes[$index].State = 'GET_RECONCILED'
            Save-Json -Path $EvidencePath -Value $script:Journal
        }
        if ($script:RequestCounts.POST -ne 5 -or
            @($script:Journal.Writes | Where-Object State -ne 'GET_RECONCILED').Count -ne 0) {
            throw 'The five planned metadata additions did not reconcile one-for-one.'
        }
        $finalContract = Assert-CompleteMetadataContract
        $script:Journal.Outcome = 'CANDIDATE_PAGINATION_API_METADATA_RECONCILED'
        $script:Journal.RequestCounters = $script:RequestCounts
        $script:Journal.FinalContract = $finalContract
        Save-Json -Path $EvidencePath -Value $script:Journal
        [pscustomobject]@{
            Outcome = $script:Journal.Outcome
            RequestParameters = 3
            ResponseProperties = 2
            Dispatches = $script:RequestCounts.POST
            FinalContract = $finalContract
            AutomaticRetries = 0
            EvidencePath = [IO.Path]::GetFullPath($EvidencePath)
        }
        return
    }

    $script:Journal = Get-Content -LiteralPath $EvidencePath -Raw | ConvertFrom-Json
    if ($script:Journal.PlanSha256 -cne $ExpectedPlanSha256.ToLowerInvariant() -or
        $script:Journal.AutomaticRetries -ne 0 -or
        $script:Journal.MaximumPostDispatches -ne 5 -or
        $script:Journal.Writes.Count -ne 5) {
        throw 'The consumed metadata journal does not match the pinned one-shot plan.'
    }
    $script:JournalOwned = $true
    foreach ($index in 0..($script:Plan.Writes.Count - 1)) {
        $write = $script:Plan.Writes[$index]
        try {
            Assert-WriteReadback -Write $write
            $script:Journal.Writes[$index].State = 'GET_RECONCILED'
        } catch {
            if ($script:Journal.Writes[$index].State -ceq 'PLANNED') {
                $script:Journal.Writes[$index].State = 'PLANNED_NOT_DISPATCHED'
            } else {
                $script:Journal.Writes[$index].State = 'UNRESOLVED_NO_RETRY'
            }
        }
    }
    $script:Journal.Outcome = if (@($script:Journal.Writes | Where-Object State -ne 'GET_RECONCILED').Count -eq 0) {
        'CANDIDATE_PAGINATION_API_METADATA_RECONCILED'
    } else { 'PARTIAL_RECONCILED_NO_RETRY' }
    if ($script:Journal.Outcome -ceq 'CANDIDATE_PAGINATION_API_METADATA_RECONCILED') {
        $script:Journal.FinalContract = Assert-CompleteMetadataContract
    }
    $script:Journal.RequestCounters = $script:RequestCounts
    Save-Json -Path $EvidencePath -Value $script:Journal
    [pscustomobject]@{
        Outcome = $script:Journal.Outcome
        Reconciled = @($script:Journal.Writes | Where-Object State -eq 'GET_RECONCILED' | ForEach-Object Name)
        Unresolved = @($script:Journal.Writes | Where-Object State -ne 'GET_RECONCILED' | ForEach-Object Name)
        RequestCounters = $script:RequestCounts
        AutomaticRetries = 0
    }
}
catch {
    if ($script:JournalOwned -and $script:Journal -and $EvidencePath -and (Test-Path -LiteralPath $EvidencePath)) {
        $script:Journal.Outcome = 'STOPPED_WITHOUT_RETRY'
        $script:Journal.RequestCounters = $script:RequestCounts
        Save-Json -Path $EvidencePath -Value $script:Journal
    }
    throw "Candidate pagination metadata deployment stopped without retry. $($_.Exception.Message)"
}
finally {
    foreach ($lock in $script:EvidenceLocks) { $lock.Dispose() }
    $script:AccessToken = $null
    [Environment]::SetEnvironmentVariable('BSO_RS_EXPECTED_USER_ID', $null, 'Process')
}
