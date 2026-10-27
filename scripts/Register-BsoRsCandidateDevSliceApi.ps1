#requires -Version 7.4
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Preflight', 'Apply', 'Reconcile')][string]$Mode,
    [Parameter(Mandatory)][string]$OrganizationUrl,
    [Parameter(Mandatory)][string]$ExpectedEnvironmentId,
    [Parameter(Mandatory)][string]$ExpectedOrganizationId,
    [string]$SolutionUniqueName = 'os_sr_bso_rs_support',
    [string]$EvidencePath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$organizationUrl = $OrganizationUrl.TrimEnd('/')
$parsedOrganizationUrl = [Uri]$organizationUrl
$apiRoot = $organizationUrl + '/api/data/v9.2/'
$handlerName = 'os_sr_cact.ApplyCandidateAction'
$apiName = 'os_sr_devcs'
$inputDefinitions = @(
    @{ Name = 'ActionType'; Type = 10; Optional = $false },
    @{ Name = 'CorrelationId'; Type = 10; Optional = $false },
    @{ Name = 'CandidateId'; Type = 10; Optional = $true },
    @{ Name = 'ExpectedStatus'; Type = 7; Optional = $true },
    @{ Name = 'CandidateName'; Type = 10; Optional = $true },
    @{ Name = 'CandidateEmail'; Type = 10; Optional = $true },
    @{ Name = 'CandidatePhone'; Type = 10; Optional = $true },
    @{ Name = 'PositionId'; Type = 10; Optional = $true },
    @{ Name = 'CandidateSourceId'; Type = 10; Optional = $true },
    @{ Name = 'CallOutcome'; Type = 7; Optional = $true },
    @{ Name = 'ContactedAt'; Type = 10; Optional = $true },
    @{ Name = 'Notes'; Type = 10; Optional = $true }
)
$outputDefinitions = @(
    @{ Name = 'ResultCode'; Type = 10 },
    @{ Name = 'CandidateId'; Type = 10 }
)

$parsedEnvironmentId = [Guid]::Empty
$parsedOrganizationId = [Guid]::Empty
if ($parsedOrganizationUrl.Scheme -cne 'https' -or
    $parsedOrganizationUrl.AbsolutePath -cne '/' -or
    -not [Guid]::TryParse($ExpectedEnvironmentId, [ref]$parsedEnvironmentId) -or
    -not [Guid]::TryParse($ExpectedOrganizationId, [ref]$parsedOrganizationId)) {
    throw 'Target must be an HTTPS organization URL with explicit expected environment and organization IDs.'
}
if ($Mode -ceq 'Apply' -and (-not $EvidencePath -or (Test-Path -LiteralPath $EvidencePath))) {
    throw 'Apply requires a new, absent one-shot evidence path.'
}

$pacOutput = @(& pac org who --json 2>&1)
if ($LASTEXITCODE -ne 0) { throw 'PAC identity check failed; no metadata write was sent.' }
$pac = ($pacOutput -join "`n") | ConvertFrom-Json
if ([string]$pac.OrgUrl.TrimEnd('/') -cne $organizationUrl -or
    [string]$pac.EnvironmentId -ine $ExpectedEnvironmentId -or
    [string]$pac.OrgId -ine $ExpectedOrganizationId) {
    throw 'PAC environment identity mismatch; no metadata write was sent.'
}

Import-Module Az.Accounts -ErrorAction Stop
$context = Get-AzContext
if ($null -eq $context -or $context.Account.Type -ne 'User' -or
    $context.Account.Id -ine [string]$pac.UserEmail) {
    throw 'PowerShell and PAC identities differ; no metadata write was sent.'
}
$accessToken = ConvertFrom-SecureString `
    (Get-AzAccessToken -ResourceUrl $organizationUrl -AsSecureString).Token -AsPlainText
$headers = @{
    Authorization = "Bearer $accessToken"
    Accept = 'application/json'
    'OData-Version' = '4.0'
    'OData-MaxVersion' = '4.0'
    Consistency = 'Strong'
}

function Invoke-DataverseRequest {
    param(
        [Parameter(Mandatory)][ValidateSet('GET', 'POST')][string]$Method,
        [Parameter(Mandatory)][string]$Path,
        [object]$Body
    )
    $uri = [Uri]($apiRoot + $Path)
    if ($uri.Scheme -cne 'https' -or $uri.Authority -ine ([Uri]$organizationUrl).Authority -or
        $uri.AbsolutePath -notmatch '^/api/data/v9\.2/' -or $uri.UserInfo -or $uri.Fragment) {
        throw 'Dataverse request target failed the pinned HTTPS origin check.'
    }
    $requestHeaders = @{} + $headers
    $arguments = @{
        Uri = $uri
        Method = $Method
        Headers = $requestHeaders
        MaximumRetryCount = 0
        MaximumRedirection = 0
        TimeoutSec = 120
        SkipHttpErrorCheck = $true
    }
    if ($Method -ceq 'POST') {
        $requestHeaders['MSCRM.SolutionUniqueName'] = $SolutionUniqueName
        $arguments.Body = ConvertTo-Json -InputObject $Body -Depth 20 -Compress
        $arguments.ContentType = 'application/json; charset=utf-8'
    }
    try { $response = Invoke-WebRequest @arguments }
    catch { throw 'Dataverse request outcome is uncertain; stop and reconcile without retry.' }
    if ([int]$response.StatusCode -lt 200 -or [int]$response.StatusCode -ge 300) {
        throw "Dataverse request was rejected with HTTP $([int]$response.StatusCode); no retry was attempted."
    }
    if ([string]::IsNullOrWhiteSpace($response.Content)) { return $null }
    $response.Content | ConvertFrom-Json
}

function Get-Rows {
    param([Parameter(Mandatory)][string]$Path)
    $page = Invoke-DataverseRequest -Method GET -Path $Path
    @($page.value)
}

function Get-NavigationProperty {
    param([string]$Table, [string]$Attribute, [string]$Target)
    $rows = Get-Rows -Path "EntityDefinitions(LogicalName='$Table')/ManyToOneRelationships?%24select=ReferencingAttribute,ReferencedEntity,ReferencingEntityNavigationPropertyName"
    $matches = @($rows | Where-Object {
        $_.ReferencingAttribute -ceq $Attribute -and $_.ReferencedEntity -ceq $Target
    })
    if ($matches.Count -ne 1 -or -not $matches[0].ReferencingEntityNavigationPropertyName) {
        throw "Registration navigation was not uniquely resolved for $Table."
    }
    [string]$matches[0].ReferencingEntityNavigationPropertyName
}

function Save-Evidence {
    param([object]$Value, [switch]$Create)
    $json = ConvertTo-Json -InputObject $Value -Depth 30
    if ($Create) {
        [IO.File]::WriteAllText($EvidencePath, $json, [Text.UTF8Encoding]::new($false))
        return
    }
    $stream = [IO.File]::Open($EvidencePath, [IO.FileMode]::Open, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
        $bytes = [Text.UTF8Encoding]::new($false).GetBytes($json)
        $stream.SetLength(0)
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush($true)
    } finally { $stream.Dispose() }
}

function New-TrackedComponent {
    param([string]$Path, [string]$IdColumn, [object]$Body, [object]$Journal)
    $entry = [ordered]@{
        Path = $Path
        Name = [string]$Body.uniquename
        State = 'PLANNED'
        HttpStatus = $null
    }
    $Journal.Writes += $entry
    Save-Evidence -Value $Journal
    $entry.State = 'DISPATCH_RESERVED'
    Save-Evidence -Value $Journal
    try {
        $null = Invoke-DataverseRequest -Method POST -Path $Path -Body $Body
    } catch {
        $entry.State = 'UNCERTAIN_OR_REJECTED'
        Save-Evidence -Value $Journal
        throw
    }
    $entry.State = 'POST_ACKNOWLEDGED'
    Save-Evidence -Value $Journal
    $readback = Invoke-DataverseRequest -Method GET -Path "$Path($($Body.$IdColumn))"
    if ([string]$readback.$IdColumn -ine [string]$Body.$IdColumn -or
        [string]$readback.uniquename -cne [string]$Body.uniquename) {
        $entry.State = 'READBACK_MISMATCH'
        Save-Evidence -Value $Journal
        throw 'Created API component failed exact identity readback; do not retry.'
    }
    $entry.State = 'GET_RECONCILED'
    Save-Evidence -Value $Journal
}

try {
    $who = Invoke-DataverseRequest -Method GET -Path 'WhoAmI'
    if ([string]$who.OrganizationId -ine $ExpectedOrganizationId -or
        [string]$who.UserId -ine [string]$pac.UserId) {
        throw 'WhoAmI identity mismatch; no metadata write was sent.'
    }

    $solutions = @(Get-Rows -Path "solutions?%24select=solutionid,uniquename&%24filter=uniquename eq '$SolutionUniqueName'")
    if ($solutions.Count -ne 1) { throw 'The target solution is missing or ambiguous.' }
    $packages = @(Get-Rows -Path "pluginpackages?%24select=pluginpackageid,uniquename,version&%24filter=uniquename eq 'os_sr_cact_pkg'")
    if ($packages.Count -ne 1 -or [string]$packages[0].version -cne '1.0.0') {
        throw 'The existing unsigned Candidate Core package is missing, duplicated, or version-mismatched.'
    }
    $assemblies = @(Get-Rows -Path "pluginassemblies?%24select=pluginassemblyid,name,_packageid_value&%24filter=name eq 'os_sr_cact'")
    $packageAssemblies = @($assemblies | Where-Object {
        $_.name -ceq 'os_sr_cact' -and [string]$_._packageid_value -ieq [string]$packages[0].pluginpackageid
    })
    if ($packageAssemblies.Count -ne 1) { throw 'The existing package-backed Candidate Core assembly is missing or ambiguous.' }
    $types = @(Get-Rows -Path "plugintypes?%24select=plugintypeid,typename,_pluginassemblyid_value&%24filter=typename eq 'os_sr_cact.ApplyCandidateAction' or typename eq 'os_sr_cact.ProtectCandidateCore'")
    $handlerTypes = @($types | Where-Object {
        $_.typename -ceq $handlerName -and
        [string]$_._pluginassemblyid_value -ieq [string]$packageAssemblies[0].pluginassemblyid
    })
    if ($handlerTypes.Count -ne 1) { throw 'The existing Candidate Core handler type is missing or ambiguous.' }
    $existingApi = @(Get-Rows -Path "customapis?%24select=customapiid,uniquename,_plugintypeid_value&%24filter=uniquename eq 'os_sr_cact'")
    if ($existingApi.Count -ne 1 -or
        [string]$existingApi[0]._plugintypeid_value -ine [string]$handlerTypes[0].plugintypeid) {
        throw 'Existing os_sr_cact handler mapping differs; no metadata write was sent.'
    }
    $devApis = @(Get-Rows -Path "customapis?%24select=customapiid,uniquename&%24filter=uniquename eq '$apiName'")
    if ($Mode -in @('Preflight', 'Apply') -and $devApis.Count -ne 0) {
        throw 'A DEV Candidate Slice API already exists; inspect it rather than creating or overwriting it.'
    }
    if ($Mode -ceq 'Reconcile' -and $devApis.Count -ne 1) {
        throw 'The DEV Candidate Slice API is missing or ambiguous.'
    }
    $apiNavigation = Get-NavigationProperty -Table 'customapi' -Attribute 'plugintypeid' -Target 'plugintype'
    $apiObjectType = Invoke-DataverseRequest -Method GET `
        -Path "EntityDefinitions(LogicalName='customapi')?%24select=ObjectTypeCode"
    $inputNavigation = Get-NavigationProperty -Table 'customapirequestparameter' -Attribute 'customapiid' -Target 'customapi'
    $outputNavigation = Get-NavigationProperty -Table 'customapiresponseproperty' -Attribute 'customapiid' -Target 'customapi'
    if ([int]$apiObjectType.ObjectTypeCode -le 0) { throw 'Custom API component type is unavailable.' }

    if ($Mode -ceq 'Preflight') {
        [ordered]@{
            Result = 'DEV_CANDIDATE_SLICE_API_PREFLIGHT_READY'
            Environment = $organizationUrl
            Solution = $SolutionUniqueName
            ExistingPackage = 'os_sr_cact_pkg'
            ExistingHandler = $handlerName
            ExistingCoreApiUnchanged = $true
            DevApiExists = $false
            PlannedRequestParameters = $inputDefinitions.Count
            PlannedResponseProperties = $outputDefinitions.Count
            AutomaticRetries = 0
            Writes = 0
        } | ConvertTo-Json -Compress
        return
    }

    if ($Mode -ceq 'Reconcile') {
        $apiId = [string]$devApis[0].customapiid
        $api = Invoke-DataverseRequest -Method GET `
            -Path "customapis($apiId)?%24select=customapiid,uniquename,isfunction,isprivate,bindingtype,executeprivilegename,_plugintypeid_value"
        $requestRows = @(Get-Rows -Path "customapirequestparameters?%24select=uniquename,type,isoptional,_customapiid_value&%24filter=_customapiid_value eq $apiId")
        $responseRows = @(Get-Rows -Path "customapiresponseproperties?%24select=uniquename,type,_customapiid_value&%24filter=_customapiid_value eq $apiId")
        $componentType = [int]$apiObjectType.ObjectTypeCode
        $solutionComponents = @(Get-Rows -Path "solutioncomponents?%24select=objectid,componenttype&%24filter=_solutionid_value eq $($solutions[0].solutionid) and objectid eq $apiId and componenttype eq $componentType")
        $requestMismatch = @($inputDefinitions | Where-Object {
            $definition = $_
            $foundParameters = @($requestRows | Where-Object { $_.uniquename -ceq $definition.Name })
            $foundParameters.Count -ne 1 -or [int]$foundParameters[0].type -ne [int]$definition.Type -or
                [bool]$foundParameters[0].isoptional -ne [bool]$definition.Optional
        })
        $responseMismatch = @($outputDefinitions | Where-Object {
            $definition = $_
            $foundOutputs = @($responseRows | Where-Object { $_.uniquename -ceq $definition.Name })
            $foundOutputs.Count -ne 1 -or [int]$foundOutputs[0].type -ne [int]$definition.Type
        })
        if ([string]$api.uniquename -cne $apiName -or [int]$api.isfunction -ne 0 -or
            [int]$api.isprivate -ne 1 -or [int]$api.bindingtype -ne 0 -or
            $api.executeprivilegename -cne 'prvWriteos_sr_cand' -or
            [string]$api._plugintypeid_value -ine [string]$handlerTypes[0].plugintypeid -or
            $requestRows.Count -ne $inputDefinitions.Count -or
            $responseRows.Count -ne $outputDefinitions.Count -or
            $requestMismatch.Count -ne 0 -or $responseMismatch.Count -ne 0 -or
            $solutionComponents.Count -ne 1) {
            throw 'DEV Candidate Slice API metadata or solution membership failed reconciliation.'
        }
        [ordered]@{
            Result = 'DEV_CANDIDATE_SLICE_API_RECONCILED'
            Environment = $organizationUrl
            Solution = $SolutionUniqueName
            ApiUniqueName = $apiName
            Handler = $handlerName
            RequestParameters = $requestRows.Count
            ResponseProperties = $responseRows.Count
            CoreApiPatched = $false
            Writes = 0
        } | ConvertTo-Json -Compress
        return
    }

    $journal = [ordered]@{
        Purpose = 'VN_LMV_IT_DEV_CANDIDATE_SLICE_API'
        ApiUniqueName = $apiName
        Solution = $SolutionUniqueName
        Writes = @()
        AutomaticRetries = 0
    }
    Save-Evidence -Value $journal -Create

    $apiId = [Guid]::NewGuid().ToString('D')
    $apiBody = [ordered]@{
        customapiid = $apiId
        uniquename = $apiName
        name = 'DEV Candidate Slice'
        displayname = 'DEV Candidate Slice'
        description = 'Temporary VN LMV IT synthetic-only Candidate demo operation. Not production-ready.'
        isfunction = $false
        isprivate = $true
        bindingtype = 0
        allowedcustomprocessingsteptype = 0
        workflowsdkstepenabled = $false
        executeprivilegename = 'prvWriteos_sr_cand'
        "$apiNavigation@odata.bind" = "/plugintypes($($handlerTypes[0].plugintypeid))"
    }
    New-TrackedComponent -Path 'customapis' -IdColumn 'customapiid' -Body $apiBody -Journal $journal

    foreach ($definition in $inputDefinitions) {
        $parameterId = [Guid]::NewGuid().ToString('D')
        $body = [ordered]@{
            customapirequestparameterid = $parameterId
            uniquename = [string]$definition.Name
            name = "$apiName.$($definition.Name)"
            displayname = [string]$definition.Name
            type = [int]$definition.Type
            isoptional = [bool]$definition.Optional
            "$inputNavigation@odata.bind" = "/customapis($apiId)"
        }
        New-TrackedComponent -Path 'customapirequestparameters' `
            -IdColumn 'customapirequestparameterid' -Body $body -Journal $journal
    }

    foreach ($definition in $outputDefinitions) {
        $propertyId = [Guid]::NewGuid().ToString('D')
        $body = [ordered]@{
            customapiresponsepropertyid = $propertyId
            uniquename = [string]$definition.Name
            name = "$apiName.$($definition.Name)"
            displayname = [string]$definition.Name
            type = [int]$definition.Type
            "$outputNavigation@odata.bind" = "/customapis($apiId)"
        }
        New-TrackedComponent -Path 'customapiresponseproperties' `
            -IdColumn 'customapiresponsepropertyid' -Body $body -Journal $journal
    }

    $finalApi = Invoke-DataverseRequest -Method GET `
        -Path "customapis($apiId)?%24select=customapiid,uniquename,isfunction,isprivate,bindingtype,_plugintypeid_value"
    $componentType = [int]$apiObjectType.ObjectTypeCode
    $solutionComponents = @(Get-Rows -Path "solutioncomponents?%24select=objectid,componenttype&%24filter=_solutionid_value eq $($solutions[0].solutionid) and objectid eq $apiId and componenttype eq $componentType")
    if ([string]$finalApi.customapiid -ine $apiId -or
        [string]$finalApi.uniquename -cne $apiName -or
        [int]$finalApi.isfunction -ne 0 -or
        [int]$finalApi.isprivate -ne 1 -or
        [int]$finalApi.bindingtype -ne 0 -or
        [string]$finalApi._plugintypeid_value -ine [string]$handlerTypes[0].plugintypeid -or
        $solutionComponents.Count -ne 1) {
        throw 'Final DEV Custom API reconciliation failed.'
    }
    $journal.Result = 'DEV_CANDIDATE_SLICE_API_CREATED'
    Save-Evidence -Value $journal
    [ordered]@{
        Result = 'DEV_CANDIDATE_SLICE_API_CREATED'
        Environment = $organizationUrl
        Solution = $SolutionUniqueName
        ApiUniqueName = $apiName
        RequestParameters = $inputDefinitions.Count
        ResponseProperties = $outputDefinitions.Count
        CoreApiPatched = $false
        AutomaticRetries = 0
        EvidencePath = $EvidencePath
    } | ConvertTo-Json -Compress
} finally {
    $accessToken = $null
}
