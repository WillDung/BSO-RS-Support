#requires -Version 7.4
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Preflight', 'Apply', 'Reconcile')][string]$Mode,
    [Parameter(Mandatory)][string]$EnvironmentName,
    [Parameter(Mandatory)][string]$OrganizationUrl,
    [Parameter(Mandatory)][string]$ExpectedEnvironmentId,
    [Parameter(Mandatory)][string]$ExpectedOrganizationId,
    [Parameter(Mandatory)][string]$PlanPath,
    [string]$ExpectedPlanSha256,
    [string]$EvidencePath
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$script:SolutionUniqueName = 'os_sr_bso_rs_support'
$script:PublisherUniqueName = 'os_bso_rs_support'
$script:OrganizationUrl = $OrganizationUrl.TrimEnd('/')
$script:ApiRoot = $script:OrganizationUrl + '/api/data/v9.2/'
$script:Contract = Get-Content -LiteralPath (Join-Path $root 'docs\PHASE_3C_API_CONTRACT.json') -Raw |
    ConvertFrom-Json
$script:AccessToken = $null
$script:RequestCounts = @{ GET = 0; POST = 0 }
$script:WriteIndex = 0
$script:Plan = $null
$script:Journal = $null
$maximumReads = 100
$maximumWrites = 1
$allowedMissingNames = @('ProfileFieldMask')

if ($EnvironmentName -cne 'VN LMV IT' -or
    $script:OrganizationUrl -cne 'https://org14938ec2.crm4.dynamics.com' -or
    $ExpectedEnvironmentId -notmatch '^[0-9a-fA-F-]{36}$' -or
    $ExpectedOrganizationId -notmatch '^[0-9a-fA-F-]{36}$') {
    throw 'Only the explicitly designated VN LMV IT target is permitted.'
}
if ($Mode -ceq 'Preflight' -and (Test-Path -LiteralPath $PlanPath)) {
    throw 'Preflight requires a new plan path; existing plans are never overwritten.'
}
if ($Mode -ceq 'Apply' -and
    (-not $ExpectedPlanSha256 -or -not $EvidencePath -or (Test-Path -LiteralPath $EvidencePath))) {
    throw 'Apply requires a pinned plan hash and a new, absent evidence path.'
}
if ($Mode -ceq 'Reconcile' -and (-not $ExpectedPlanSha256 -or -not $EvidencePath)) {
    throw 'Reconcile requires the pinned plan hash and its consumed evidence path.'
}

$baselinePath = Join-Path $PSScriptRoot 'Provision-BsoRsCandidateChildTables.ps1'
$tokens = $null
$parseErrors = $null
$baselineAst = [System.Management.Automation.Language.Parser]::ParseFile(
    $baselinePath, [ref]$tokens, [ref]$parseErrors
)
if ($parseErrors.Count) { throw 'The guarded PAC identity helper has parser errors.' }
foreach ($name in @('Assert-TargetInput', 'Assert-PacIdentity', 'Get-ValidatedToken')) {
    $definitions = @($baselineAst.EndBlock.Statements | Where-Object {
        $_ -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $_.Name -ceq $name
    })
    if ($definitions.Count -ne 1) { throw "Required identity helper is missing or ambiguous: $name" }
    . ([scriptblock]::Create($definitions[0].Extent.Text))
}

function Get-ApiRows {
    param([Parameter(Mandatory)][ValidateSet('GET', 'POST')][string]$Method,
        [Parameter(Mandatory)][string]$Path, [object]$Body)
    if ($Method -ceq 'GET' -and $script:RequestCounts.GET -ge $maximumReads) {
        throw 'Candidate Core metadata read budget exhausted.'
    }
    if ($Method -ceq 'POST') {
        if ($Mode -cne 'Apply' -or $null -eq $script:Plan -or
            $script:WriteIndex -ge $maximumWrites -or $script:WriteIndex -ge $script:Plan.Writes.Count) {
            throw 'Request-parameter write is outside the pinned bounded Apply plan.'
        }
        $plannedWrite = $script:Plan.Writes[$script:WriteIndex]
        $bodyHash = (Get-FileHash -InputStream ([IO.MemoryStream]::new(
            [Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $Body -Depth 20 -Compress))
        )) -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($Path -cne $plannedWrite.Path -or $bodyHash -cne $plannedWrite.PayloadSha256 -or
            $script:Journal.Writes[$script:WriteIndex].State -cne 'DISPATCH_RESERVED') {
            throw 'Request-parameter payload differs from the reserved plan entry.'
        }
        $script:WriteIndex++
    }
    $uri = [Uri]($script:ApiRoot + $Path)
    if ($uri.Scheme -cne 'https' -or $uri.Authority -ine ([Uri]$script:OrganizationUrl).Authority -or
        $uri.AbsolutePath -notmatch '^/api/data/v9\.2/' -or $uri.UserInfo -or $uri.Fragment) {
        throw 'Dataverse request target failed the pinned HTTPS origin check.'
    }
    $headers = @{
        Authorization = 'Bearer ' + $script:AccessToken
        Accept = 'application/json'
        'OData-Version' = '4.0'
        'OData-MaxVersion' = '4.0'
        Consistency = 'Strong'
    }
    $arguments = @{
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
        $arguments.Body = ConvertTo-Json -InputObject $Body -Depth 20 -Compress
        $arguments.ContentType = 'application/json; charset=utf-8'
    }
    if ($Method -ceq 'GET') { $script:RequestCounts.GET++ } else { $script:RequestCounts.POST++ }
    try { $response = Invoke-WebRequest @arguments }
    catch { throw "Dataverse $Method transport outcome is uncertain; stop without retry." }
    if ([int]$response.StatusCode -lt 200 -or [int]$response.StatusCode -ge 300) {
        throw "Dataverse $Method was rejected with HTTP $([int]$response.StatusCode); stop without retry."
    }
    if ([string]::IsNullOrWhiteSpace([string]$response.Content)) { return $null }
    $response.Content | ConvertFrom-Json -ErrorAction Stop
}

function Get-ApiRowsPage {
    param([Parameter(Mandatory)][string]$Path)
    $response = Get-ApiRows -Method GET -Path $Path
    @($response.value)
}

function Get-ApiNavigationProperty {
    $matches = @(Get-ApiRowsPage -Path "EntityDefinitions(LogicalName='customapirequestparameter')/ManyToOneRelationships?%24select=ReferencingAttribute,ReferencedEntity,ReferencingEntityNavigationPropertyName" |
        Where-Object {
            $_.ReferencingAttribute -ceq 'customapiid' -and $_.ReferencedEntity -ceq 'customapi'
        })
    if ($matches.Count -ne 1 -or -not $matches[0].ReferencingEntityNavigationPropertyName) {
        throw 'Custom API request-parameter relationship metadata is missing or ambiguous.'
    }
    [string]$matches[0].ReferencingEntityNavigationPropertyName
}

function Get-ApiSnapshot {
    $solutions = @(Get-ApiRowsPage -Path "solutions?%24select=solutionid,uniquename,ismanaged,_publisherid_value&%24filter=uniquename eq '$($script:SolutionUniqueName)'&%24top=2")
    $publishers = @(Get-ApiRowsPage -Path "publishers?%24select=publisherid,uniquename,customizationprefix&%24filter=uniquename eq '$($script:PublisherUniqueName)'&%24top=2")
    if ($solutions.Count -ne 1 -or [bool]$solutions[0].ismanaged -or
        $publishers.Count -ne 1 -or $publishers[0].customizationprefix -cne 'os' -or
        [string]$solutions[0]._publisherid_value -ine [string]$publishers[0].publisherid) {
        throw 'Existing project Solution or Publisher does not match the approved metadata boundary.'
    }
    $apis = @(Get-ApiRowsPage -Path "customapis?%24select=customapiid,uniquename,executeprivilegename,isprivate,isfunction,bindingtype&%24filter=uniquename eq 'os_sr_cact'&%24top=2")
    if ($apis.Count -ne 1 -or [string]$apis[0].executeprivilegename -cne 'prvReados_sr_cand' -or
        [bool]$apis[0].isprivate -ne $true -or [bool]$apis[0].isfunction -or
        [int]$apis[0].bindingtype -ne 0) {
        throw 'Existing os_sr_cact metadata differs from the approved unbound API contract.'
    }
    $api = $apis[0]
    $apiId = [string]$api.customapiid
    if ($apiId -notmatch '^[0-9a-fA-F-]{36}$') { throw 'Candidate Core API identifier is invalid.' }
    $apiType = Get-ApiRows -Method GET -Path "EntityDefinitions(LogicalName='customapi')?%24select=ObjectTypeCode"
    if ($null -eq $apiType -or [int]$apiType.ObjectTypeCode -le 0) {
        throw 'Custom API solution component type is unavailable.'
    }
    $components = @(Get-ApiRowsPage -Path "solutioncomponents?%24select=objectid,componenttype,rootcomponentbehavior&%24filter=_solutionid_value eq $($solutions[0].solutionid) and objectid eq $apiId and componenttype eq $([int]$apiType.ObjectTypeCode)&%24top=2" |
        Where-Object {
            [string]$_.objectid -ieq $apiId -and [int]$_.componenttype -eq [int]$apiType.ObjectTypeCode
        })
    if ($components.Count -ne 1) { throw 'Existing Candidate Core Custom API is not uniquely included in the target Solution.' }
    $inputs = @(Get-ApiRowsPage -Path "customapirequestparameters?%24select=customapirequestparameterid,uniquename,type,isoptional,_customapiid_value&%24filter=_customapiid_value eq $apiId&%24top=100")
    $expectedInputs = @($script:Contract.inputs)
    $expectedNames = @($expectedInputs | ForEach-Object { [string]$_.name })
    $actualNames = @($inputs | ForEach-Object { [string]$_.uniquename })
    if (@($actualNames | Group-Object | Where-Object Count -ne 1).Count -gt 0) {
        throw 'Duplicate Candidate Core request-parameter names exist.'
    }
    $unexpected = @($actualNames | Where-Object { $_ -cnotin $expectedNames })
    $invalid = [Collections.Generic.List[string]]::new()
    foreach ($liveParameter in $inputs) {
        $expected = @($expectedInputs | Where-Object { [string]$_.name -ceq [string]$liveParameter.uniquename })
        if ($expected.Count -ne 1 -or [int]$liveParameter.type -ne [int]$expected[0].type -or
            [bool]$liveParameter.isoptional -ne [bool]$expected[0].optional) {
            $invalid.Add(('{0}|{1}|{2}' -f [string]$liveParameter.uniquename,
                [int]$liveParameter.type, [bool]$liveParameter.isoptional))
        }
    }
    if ($unexpected.Count -or $invalid.Count) {
        $unexpectedText = if ($unexpected.Count) { [string]::Join(',', $unexpected) } else { 'none' }
        $invalidText = if ($invalid.Count) { [string]::Join(',', $invalid) } else { 'none' }
        throw "Existing Candidate Core request parameters contain an unapproved shape; unexpected=$unexpectedText; invalid=$invalidText."
    }
    $missing = @($expectedInputs | Where-Object { [string]$_.name -cnotin $actualNames } |
        ForEach-Object { [string]$_.name })
    $canonical = @($inputs | ForEach-Object {
        '{0}|{1}|{2}' -f $_.uniquename, [int]$_.type, [bool]$_.isoptional
    } | Sort-Object -CaseSensitive)
    $snapshotHash = (Get-FileHash -InputStream ([IO.MemoryStream]::new(
        [Text.Encoding]::UTF8.GetBytes([string]::Join("`n", $canonical))
    )) -Algorithm SHA256).Hash.ToLowerInvariant()
    [pscustomobject]@{
        Api = $api
        ApiId = $apiId
        SolutionId = [string]$solutions[0].solutionid
        Inputs = $inputs
        MissingNames = $missing
        SnapshotSha256 = $snapshotHash
    }
}

function New-RequestParameterWrites {
    param([Parameter(Mandatory)][object]$Snapshot)
    $navigation = Get-ApiNavigationProperty
    @($script:Contract.inputs | Where-Object { [string]$_.name -cin $Snapshot.MissingNames } | ForEach-Object {
        $name = [string]$_.name
        $body = [ordered]@{
            customapirequestparameterid = [Guid]::NewGuid().ToString()
            uniquename = $name
            name = "os_sr_cact.$name"
            displayname = $name
            type = [int]$_.type
            isoptional = [bool]$_.optional
            "$navigation@odata.bind" = "/customapis($($Snapshot.ApiId))"
        }
        $payload = ConvertTo-Json -InputObject $body -Depth 20 -Compress
        [ordered]@{
            Path = 'customapirequestparameters'
            Id = [string]$body.customapirequestparameterid
            Name = $name
            Type = [int]$_.type
            IsOptional = [bool]$_.optional
            Body = $body
            PayloadSha256 = (Get-FileHash -InputStream ([IO.MemoryStream]::new(
                [Text.Encoding]::UTF8.GetBytes($payload)
            )) -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    })
}

function Save-JsonFile {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][object]$Value,
        [switch]$CreateNew)
    $mode = if ($CreateNew) { [IO.FileMode]::CreateNew } else { [IO.FileMode]::Open }
    $stream = [IO.File]::Open($Path, $mode, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
        $stream.SetLength(0)
        $bytes = [Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $Value -Depth 30))
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush($true)
    } finally { $stream.Dispose() }
}

function Assert-RequestParameterReadback {
    param([Parameter(Mandatory)][object]$Write)
    $rows = @(Get-ApiRowsPage -Path "customapirequestparameters?%24select=customapirequestparameterid,uniquename,type,isoptional,_customapiid_value&%24filter=_customapiid_value eq $($script:Plan.ApiId) and customapirequestparameterid eq $($Write.Id)&%24top=2")
    if ($rows.Count -ne 1 -or [string]$rows[0].customapirequestparameterid -ine $Write.Id -or
        [string]$rows[0].uniquename -cne $Write.Name -or [int]$rows[0].type -ne [int]$Write.Type -or
        [bool]$rows[0].isoptional -ne [bool]$Write.IsOptional -or
        [string]$rows[0]._customapiid_value -ine [string]$script:Plan.ApiId) {
        throw "Created API input did not reconcile exactly: $($Write.Name)."
    }
}

try {
    Assert-TargetInput
    Assert-PacIdentity
    Get-ValidatedToken
    $who = Get-ApiRows -Method GET -Path 'WhoAmI'
    if ([string]$who.OrganizationId -ine $ExpectedOrganizationId -or
        [string]$who.UserId -ine $script:ExpectedUserId) {
        throw 'Dataverse identity does not match the pinned PAC identity and organization.'
    }
    $script:ApiRoot = $script:OrganizationUrl + '/api/data/v9.2/'
    if ($Mode -ceq 'Preflight') {
        if (-not (Test-Path -LiteralPath (Split-Path -Parent $PlanPath) -PathType Container)) {
            throw 'The plan directory must already exist.'
        }
        $snapshot = Get-ApiSnapshot
        $unapprovedMissing = @($snapshot.MissingNames | Where-Object { $_ -cnotin $allowedMissingNames })
        if ($unapprovedMissing.Count -gt 0 -or $snapshot.MissingNames.Count -gt $maximumWrites) {
            throw 'Live request-parameter gap differs from the approved Phase 5A correction boundary.'
        }
        if ($snapshot.MissingNames.Count -eq 0) {
            [ordered]@{
                Outcome = 'CANDIDATE_CORE_API_INPUTS_ALREADY_RECONCILED'
                MissingInputs = @()
                RequestCounters = $script:RequestCounts
                AutomaticRetries = 0
            } | ConvertTo-Json -Depth 8
            return
        }
        $writes = @(New-RequestParameterWrites -Snapshot $snapshot)
        if ($writes.Count -ne $snapshot.MissingNames.Count -or
            @($writes | Where-Object { $_.Name -notin $allowedMissingNames }).Count -gt 0) {
            throw 'Preflight writes exceed the exact names missing from the live API.'
        }
        $script:Plan = [ordered]@{
            EnvironmentName = 'VN LMV IT'
            OrganizationUrl = $script:OrganizationUrl
            ExpectedEnvironmentId = $ExpectedEnvironmentId
            ExpectedOrganizationId = $ExpectedOrganizationId
            SolutionUniqueName = $script:SolutionUniqueName
            PublisherUniqueName = $script:PublisherUniqueName
            ApiUniqueName = 'os_sr_cact'
            ApiId = $snapshot.ApiId
            ExistingInputsSha256 = $snapshot.SnapshotSha256
            ExpectedMissingNames = $snapshot.MissingNames
            Writes = $writes
            AutomaticRetries = 0
            MaximumPostDispatches = $writes.Count
        }
        Save-JsonFile -Path $PlanPath -Value $script:Plan -CreateNew
        [ordered]@{
            Outcome = 'CANDIDATE_CORE_API_INPUT_PLAN_READY'
            MissingInputs = @($writes | ForEach-Object Name)
            PlannedPOST = $writes.Count
            RequestCounters = $script:RequestCounts
            AutomaticRetries = 0
            PlanSha256 = (Get-FileHash -LiteralPath $PlanPath -Algorithm SHA256).Hash.ToLowerInvariant()
        } | ConvertTo-Json -Depth 8
        return
    }

    $planHash = (Get-FileHash -LiteralPath $PlanPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($planHash -cne $ExpectedPlanSha256) { throw 'Pinned request-parameter plan hash does not match.' }
    $script:Plan = Get-Content -LiteralPath $PlanPath -Raw | ConvertFrom-Json
    if ($script:Plan.EnvironmentName -cne 'VN LMV IT' -or
        $script:Plan.OrganizationUrl -cne $script:OrganizationUrl -or
        $script:Plan.ExpectedEnvironmentId -ine $ExpectedEnvironmentId -or
        $script:Plan.ExpectedOrganizationId -ine $ExpectedOrganizationId -or
        $script:Plan.SolutionUniqueName -cne $script:SolutionUniqueName -or
        $script:Plan.PublisherUniqueName -cne $script:PublisherUniqueName -or
        $script:Plan.ApiUniqueName -cne 'os_sr_cact' -or
        $script:Plan.AutomaticRetries -ne 0 -or
        $script:Plan.Writes.Count -lt 1 -or
        $script:Plan.Writes.Count -gt $maximumWrites -or
        $script:Plan.MaximumPostDispatches -ne $script:Plan.Writes.Count -or
        @($script:Plan.ExpectedMissingNames | Where-Object { $_ -cnotin $allowedMissingNames }).Count -gt 0 -or
        [string]::Join(';', @($script:Plan.Writes | ForEach-Object Name | Sort-Object -CaseSensitive)) -cne
        [string]::Join(';', @($script:Plan.ExpectedMissingNames | Sort-Object -CaseSensitive))) {
        throw 'Request-parameter plan differs from the pinned, bounded metadata correction.'
    }
    $snapshot = Get-ApiSnapshot

    if ($Mode -ceq 'Apply') {
        if ($script:RequestCounts.POST -ne 0) { throw 'Unexpected metadata POST before Apply dispatch.' }
        if ($snapshot.ApiId -ine $script:Plan.ApiId -or
            $snapshot.SnapshotSha256 -cne $script:Plan.ExistingInputsSha256 -or
            [string]::Join(';', @($snapshot.MissingNames | Sort-Object -CaseSensitive)) -cne
            [string]::Join(';', @($script:Plan.ExpectedMissingNames | Sort-Object -CaseSensitive))) {
            throw 'Live API identity or existing input inventory changed after preflight.'
        }
        $script:Journal = [ordered]@{
            PlanSha256 = $planHash
            ApiUniqueName = 'os_sr_cact'
            Writes = @($script:Plan.Writes | ForEach-Object {
                [ordered]@{ Name = $_.Name; Id = $_.Id; State = 'PLANNED'; HttpStatus = $null }
            })
            AutomaticRetries = 0
            MaximumPostDispatches = $script:Plan.Writes.Count
            Outcome = 'IN_PROGRESS'
        }
        Save-JsonFile -Path $EvidencePath -Value $script:Journal -CreateNew
        for ($index = 0; $index -lt $script:Plan.Writes.Count; $index++) {
            $write = $script:Plan.Writes[$index]
            $duplicates = @(Get-ApiRowsPage -Path "customapirequestparameters?%24select=customapirequestparameterid&%24filter=_customapiid_value eq $($script:Plan.ApiId) and uniquename eq '$($write.Name)'&%24top=2")
            if ($duplicates.Count -ne 0) { throw "API input appeared after preflight; stop before dispatch: $($write.Name)." }
            $script:Journal.Writes[$index].State = 'DISPATCH_RESERVED'
            Save-JsonFile -Path $EvidencePath -Value $script:Journal
            $null = Get-ApiRows -Method POST -Path $write.Path -Body $write.Body
            $script:Journal.Writes[$index].HttpStatus = 204
            $script:Journal.Writes[$index].State = 'ACKNOWLEDGED'
            Save-JsonFile -Path $EvidencePath -Value $script:Journal
            Assert-RequestParameterReadback -Write $write
            $script:Journal.Writes[$index].State = 'GET_RECONCILED'
            Save-JsonFile -Path $EvidencePath -Value $script:Journal
        }
        if ($script:RequestCounts.POST -ne $script:Plan.Writes.Count -or
            @($script:Journal.Writes | Where-Object State -ne 'GET_RECONCILED').Count -ne 0) {
            throw 'Planned API inputs did not reconcile one-for-one with the bounded dispatch journal.'
        }
        $script:Journal.Outcome = 'CANDIDATE_CORE_API_INPUTS_RECONCILED'
        $script:Journal.RequestCounters = $script:RequestCounts
        Save-JsonFile -Path $EvidencePath -Value $script:Journal
    } else {
        $script:Journal = Get-Content -LiteralPath $EvidencePath -Raw | ConvertFrom-Json
        if ($script:Journal.PlanSha256 -cne $planHash -or
            $script:Journal.AutomaticRetries -ne 0 -or
            $script:Journal.MaximumPostDispatches -ne $script:Plan.Writes.Count -or
            $script:Journal.Writes.Count -ne $script:Plan.Writes.Count) {
            throw 'Consumed API input journal does not match the pinned one-shot plan.'
        }
        foreach ($index in 0..($script:Plan.Writes.Count - 1)) {
            $write = $script:Plan.Writes[$index]
            $rows = @(Get-ApiRowsPage -Path "customapirequestparameters?%24select=customapirequestparameterid,uniquename,type,isoptional,_customapiid_value&%24filter=_customapiid_value eq $($script:Plan.ApiId) and uniquename eq '$($write.Name)'&%24top=2")
            if ($rows.Count -eq 1 -and [string]$rows[0].customapirequestparameterid -ieq [string]$write.Id -and
                [int]$rows[0].type -eq [int]$write.Type -and
                [bool]$rows[0].isoptional -eq [bool]$write.IsOptional -and
                [string]$rows[0]._customapiid_value -ieq [string]$script:Plan.ApiId) {
                $script:Journal.Writes[$index].State = 'GET_RECONCILED'
            } elseif ($rows.Count -eq 0 -and $script:Journal.Writes[$index].State -ceq 'PLANNED') {
                $script:Journal.Writes[$index].State = 'PLANNED_NOT_DISPATCHED'
            } else {
                $script:Journal.Writes[$index].State = 'UNRESOLVED_NO_RETRY'
            }
        }
        $finalSnapshot = Get-ApiSnapshot
        if ($finalSnapshot.ApiId -ine $script:Plan.ApiId) {
            throw 'Read-only API input reconciliation found an API identity mismatch.'
        }
        $allReconciled = @($script:Journal.Writes | Where-Object State -ne 'GET_RECONCILED').Count -eq 0
        $complete = $allReconciled -and $finalSnapshot.MissingNames.Count -eq 0
        $script:Journal.Outcome = if ($complete) {
            'CANDIDATE_CORE_API_INPUTS_RECONCILED'
        } else { 'PARTIAL_RECONCILED_NO_RETRY' }
        $script:Journal.RequestCounters = $script:RequestCounts
        Save-JsonFile -Path $EvidencePath -Value $script:Journal
        [ordered]@{
            Outcome = $script:Journal.Outcome
            ReconciledInputs = @($script:Journal.Writes | Where-Object State -eq 'GET_RECONCILED' | ForEach-Object Name)
            UnresolvedInputs = @($script:Journal.Writes | Where-Object State -ne 'GET_RECONCILED' | ForEach-Object Name)
            StillMissingInputs = @($finalSnapshot.MissingNames)
            RequestCounters = $script:RequestCounts
            AutomaticRetries = 0
        } | ConvertTo-Json -Depth 8
        return
    }
    [ordered]@{
        Outcome = 'CANDIDATE_CORE_API_INPUTS_RECONCILED'
        Environment = 'VN LMV IT'
        ApiUniqueName = 'os_sr_cact'
        AddedInputs = @($script:Plan.Writes | ForEach-Object Name)
        Dispatches = [int]$script:RequestCounts.POST
        RequestCounters = $script:RequestCounts
        AutomaticRetries = 0
        EvidencePath = if ($EvidencePath) { [IO.Path]::GetFullPath($EvidencePath) } else { $null }
    } | ConvertTo-Json -Depth 8
}
catch {
    if ($script:Journal) {
        $script:Journal.Outcome = 'STOPPED_WITHOUT_RETRY'
        $script:Journal.RequestCounters = $script:RequestCounts
        if ($EvidencePath -and (Test-Path -LiteralPath $EvidencePath)) {
            Save-JsonFile -Path $EvidencePath -Value $script:Journal
        }
    }
    throw "Candidate Core API input repair stopped; no automatic retry. $($_.Exception.Message)"
}
finally {
    $script:AccessToken = $null
    [Environment]::SetEnvironmentVariable('BSO_RS_EXPECTED_USER_ID', $null, 'Process')
}
