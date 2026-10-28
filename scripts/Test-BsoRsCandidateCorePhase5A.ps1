#requires -Version 7.4
[CmdletBinding()]
param(
    [ValidateSet('PlanOnly', 'Apply')][string]$Mode = 'PlanOnly',
    [Parameter(Mandatory)][string]$EnvironmentName,
    [Parameter(Mandatory)][string]$OrganizationUrl,
    [Parameter(Mandatory)][string]$ExpectedEnvironmentId,
    [Parameter(Mandatory)][string]$ExpectedOrganizationId,
    [string]$EvidencePath
)

$ErrorActionPreference = 'Stop'
$script:ExpectedDispatches = 27
$script:MaximumReads = 180
$script:ReadCount = 0
$script:DispatchCount = 0
$script:ApiRoot = $null
$script:AccessToken = $null
$script:ExpectedUserId = $null
$script:PacUserEmail = $null
$script:Journal = $null
$script:allCorrelations = [Collections.Generic.List[string]]::new()
$script:CurrentStage = 'INITIALIZATION'

if ($EnvironmentName -cne 'VN LMV IT' -or
    $OrganizationUrl.TrimEnd('/') -cne 'https://org14938ec2.crm4.dynamics.com' -or
    $ExpectedEnvironmentId -notmatch '^[0-9a-fA-F-]{36}$' -or
    $ExpectedOrganizationId -notmatch '^[0-9a-fA-F-]{36}$') {
    throw 'Only the explicitly designated VN LMV IT target is permitted.'
}
if ($Mode -ceq 'Apply' -and (-not $EvidencePath -or (Test-Path -LiteralPath $EvidencePath))) {
    throw 'Apply requires a new evidence path; existing evidence is never overwritten.'
}

$helperPath = Join-Path $PSScriptRoot 'Provision-BsoRsCandidateChildTables.ps1'
$tokens = $null
$parseErrors = $null
$helperAst = [System.Management.Automation.Language.Parser]::ParseFile(
    $helperPath, [ref]$tokens, [ref]$parseErrors
)
if ($parseErrors.Count) { throw 'Existing PAC identity helper has parser errors.' }
foreach ($functionName in @('Assert-PacIdentity', 'Get-ValidatedToken')) {
    $definitions = @($helperAst.EndBlock.Statements | Where-Object {
        $_ -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $_.Name -ceq $functionName
    })
    if ($definitions.Count -ne 1) { throw "Required identity helper is missing or ambiguous: $functionName" }
    . ([scriptblock]::Create($definitions[0].Extent.Text))
}

$script:ApiRoot = $OrganizationUrl.TrimEnd('/') + '/api/data/v9.2/'

function Save-Phase5ARuntimeJournal {
    $json = ConvertTo-Json -InputObject $script:Journal -Depth 20
    $bytes = [Text.Encoding]::UTF8.GetBytes($json)
    $stream = [IO.File]::Open($EvidencePath, [IO.FileMode]::Open, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
        $stream.SetLength(0)
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush($true)
    }
    finally { $stream.Dispose() }
}

function Get-Phase5ARows {
    param([Parameter(Mandatory)][string]$Path)
    if ($script:ReadCount -ge $script:MaximumReads) {
        throw 'Read budget exhausted; runtime acceptance stopped.'
    }
    $script:ReadCount++
    $uri = [Uri]($script:ApiRoot + $Path)
    if ($uri.Scheme -cne 'https' -or $uri.Authority -ine ([Uri]$OrganizationUrl).Authority -or
        $uri.AbsolutePath -notmatch '^/api/data/v9\.2/' -or $uri.UserInfo -or $uri.Fragment) {
        throw 'Read target is outside the verified VN LMV IT organization.'
    }
    try {
        $response = Invoke-RestMethod -Uri $uri.AbsoluteUri -Method GET -Headers @{
            Authorization = 'Bearer ' + $script:AccessToken
            Accept = 'application/json'
            'OData-Version' = '4.0'
            'OData-MaxVersion' = '4.0'
            Consistency = 'Strong'
        } -MaximumRetryCount 0 -MaximumRedirection 0 -TimeoutSec 120 `
            -SkipHttpErrorCheck -StatusCodeVariable readStatus -ErrorAction Stop
    }
    catch {
        throw "Dataverse GET transport failed at $($script:CurrentStage); no retry was attempted."
    }
    if ([int]$readStatus -lt 200 -or [int]$readStatus -ge 300) {
        $detail = if ($response.error -and $response.error.message) {
            [string]$response.error.message
        } else { 'Dataverse returned no readable diagnostic.' }
        $detail = $detail -replace '(?i)https?://\S+', '[URL]'
        $detail = $detail -replace '(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b', '[EMAIL]'
        $detail = $detail -replace '\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b', '[ID]'
        $detail = $detail -replace '(?i)\bBearer\s+\S+', '******'
        if ($detail.Length -gt 300) { $detail = $detail.Substring(0, 300) }
        throw "Dataverse GET failed at $($script:CurrentStage) with HTTP $readStatus; $detail"
    }
    $collection = $response.PSObject.Properties['value']
    if ($null -ne $collection) { return @($collection.Value) }
    @($response)
}

function Get-Phase5AErrorCode {
    param([object]$Response)
    $message = ''
    if ($null -ne $Response -and $Response.error) {
        $message = [string]$Response.error.message
    }
    elseif ($Response -is [string]) {
        try {
            $parsed = $Response | ConvertFrom-Json -ErrorAction Stop
            if ($parsed.error) { $message = [string]$parsed.error.message }
        }
        catch { $message = '' }
    }
    foreach ($code in @('CORRELATION_CONFLICT', 'STALE_EXPECTED_STATUS')) {
        if ($message -match "(?<![A-Z0-9_])$([regex]::Escape($code))(?![A-Z0-9_])") {
            return $code
        }
    }
    $match = [regex]::Match($message,
        '(?<![A-Z0-9_])DATAVERSE_OPERATION_REJECTED:(CC_[A-Z_]+):0x[0-9A-Fa-f]{8}(?![A-Z0-9_])')
    if ($match.Success) { return $match.Value }
    $null
}

function Invoke-Phase5AOperation {
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Body,
        [string]$ExpectedFailure
    )
    if ($script:DispatchCount -ge $script:ExpectedDispatches) {
        throw 'The fixed Candidate Core dispatch budget is exhausted.'
    }
    $action = [string]$Body.ActionType
    if ($action -notin @(
        'CreateCandidate', 'RecordCall', 'ProceedToScheduling', 'MarkRound1Scheduled',
        'RecordPass', 'RecordFail', 'RequestReschedule', 'CancelRound1'
    )) {
        throw 'Action is outside the fixed Phase 5A runtime acceptance matrix.'
    }
    $correlation = [string]$Body.CorrelationId
    if ($correlation -notmatch '^[0-9a-fA-F-]{36}$') {
        throw 'Runtime operation lacks a valid correlation identifier.'
    }
    $payload = ConvertTo-Json -InputObject $Body -Depth 8 -Compress
    $payloadHash = [Convert]::ToHexString(
        [Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($payload))
    ).ToLowerInvariant()
    $correlationHash = [Convert]::ToHexString(
        [Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($correlation))
    ).ToLowerInvariant()
    $entry = [ordered]@{
        Action = $action
        CorrelationSha256 = $correlationHash
        PayloadSha256 = $payloadHash
        State = 'DISPATCH_RESERVED'
        HttpStatus = $null
        ResultCode = $null
        CurrentStatus = $null
        ExpectedFailure = $ExpectedFailure
        ErrorCode = $null
    }
    $script:Journal.Dispatches.Add($entry)
    Save-Phase5ARuntimeJournal
    $script:DispatchCount++

    $uri = [Uri]($script:ApiRoot + 'os_sr_cact')
    if ($uri.Scheme -cne 'https' -or $uri.Authority -ine ([Uri]$OrganizationUrl).Authority) {
        $entry.State = 'NOT_SENT_INVALID_TARGET'
        Save-Phase5ARuntimeJournal
        throw 'Custom API target is outside the verified VN LMV IT organization.'
    }
    try {
        $response = Invoke-RestMethod -Uri $uri.AbsoluteUri -Method POST -Headers @{
            Authorization = 'Bearer ' + $script:AccessToken
            Accept = 'application/json'
            'OData-Version' = '4.0'
            'OData-MaxVersion' = '4.0'
        } -ContentType 'application/json; charset=utf-8' -Body $payload `
            -MaximumRetryCount 0 -MaximumRedirection 0 -TimeoutSec 120 `
            -SkipHttpErrorCheck -StatusCodeVariable httpStatus -ErrorAction Stop
    }
    catch {
        $entry.State = 'UNCERTAIN_OUTCOME_NO_RETRY'
        Save-Phase5ARuntimeJournal
        throw 'Custom API transport outcome is uncertain; the operation was not retried.'
    }
    $entry.HttpStatus = [int]$httpStatus
    if ([int]$httpStatus -ge 200 -and [int]$httpStatus -lt 300) {
        $entry.ResultCode = [string]$response.ResultCode
        $entry.CurrentStatus = if ($null -ne $response.CurrentStatus) {
            [int]$response.CurrentStatus
        } else { $null }
        if ($ExpectedFailure) {
            $entry.State = 'UNEXPECTED_SUCCESS'
            Save-Phase5ARuntimeJournal
            throw "Expected $ExpectedFailure rejection for $action but the operation succeeded."
        }
        if ($entry.ResultCode -notin @('Applied', 'DuplicateReplay')) {
            $entry.State = 'UNEXPECTED_RESPONSE'
            Save-Phase5ARuntimeJournal
            throw "Custom API returned an unexpected result for $action."
        }
        $entry.State = 'ACKNOWLEDGED'
        Save-Phase5ARuntimeJournal
        return $response
    }

    $entry.ErrorCode = Get-Phase5AErrorCode -Response $response
    if ($ExpectedFailure -and $entry.ErrorCode -ceq $ExpectedFailure) {
        $entry.State = 'EXPECTED_REJECTION'
        Save-Phase5ARuntimeJournal
        return $null
    }
    $entry.State = if ($entry.ErrorCode) { 'REJECTED' } else { 'REJECTED_UNCLASSIFIED' }
    Save-Phase5ARuntimeJournal
    if ($entry.ErrorCode) {
        throw "Custom API rejected $action with $($entry.ErrorCode); no retry was attempted."
    }
    throw "Custom API rejected $action with HTTP $httpStatus; response details suppressed and no retry was attempted."
}

function New-Phase5ACorrelation {
    [Guid]::NewGuid().ToString('D').ToLowerInvariant()
}

function Add-Phase5ACorrelation {
    param([Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[string]]$List)
    $value = New-Phase5ACorrelation
    $List.Add($value)
    $value
}

function New-Phase5AAction {
    param(
        [Parameter(Mandatory)][string]$Action,
        [Parameter(Mandatory)][string]$Correlation,
        [int]$ExpectedStatus,
        [string]$CandidateId,
        [System.Collections.IDictionary]$Inputs
    )
    $body = [ordered]@{
        ActionType = $Action
        CorrelationId = $Correlation
    }
    if ($CandidateId) { $body.CandidateId = $CandidateId }
    if ($PSBoundParameters.ContainsKey('ExpectedStatus')) { $body.ExpectedStatus = $ExpectedStatus }
    if ($Inputs) {
        foreach ($key in $Inputs.Keys) { $body[$key] = $Inputs[$key] }
    }
    $body
}

function Assert-Phase5AResult {
    param([object]$Result, [string]$ResultCode, [int]$CurrentStatus, [string]$Action)
    if ($null -eq $Result -or [string]$Result.ResultCode -cne $ResultCode -or
        $null -eq $Result.CurrentStatus -or [int]$Result.CurrentStatus -ne $CurrentStatus) {
        throw "Candidate Core result did not match the $Action acceptance checkpoint."
    }
}

function Get-Phase5ACandidateId {
    param([string]$CandidateSet, [string]$CreationCorrelation)
    $filter = "os_sr_cand_corid eq '$CreationCorrelation'"
    $rows = @(Get-Phase5ARows -Path "$CandidateSet?%24select=os_sr_candid,os_sr_cand_corid,os_sr_cand_stat&%24filter=$([Uri]::EscapeDataString($filter))&%24top=2")
    if ($rows.Count -ne 1 -or [string]$rows[0].os_sr_candid -notmatch '^[0-9a-fA-F-]{36}$') {
        throw 'Candidate created through Candidate Core did not reconcile by its unique operation correlation.'
    }
    [string]$rows[0].os_sr_candid
}

function Get-Phase5ACandidate {
    param([string]$CandidateSet, [string]$CandidateId)
    $rows = @(Get-Phase5ARows -Path "$CandidateSet($CandidateId)?%24select=os_sr_candid,os_sr_cand_stat,os_sr_cand_corid")
    if ($rows.Count -ne 1) { throw 'Scoped Candidate readback was not unique.' }
    $rows[0]
}

function Assert-Phase5AStatus {
    param([string]$CandidateSet, [string]$CandidateId, [int]$ExpectedStatus)
    $row = Get-Phase5ACandidate -CandidateSet $CandidateSet -CandidateId $CandidateId
    if ([int]$row.os_sr_cand_stat -ne $ExpectedStatus) {
        throw 'Candidate status did not reconcile to the expected workflow state.'
    }
}

function Get-Phase5ARelatedRows {
    param(
        [Parameter(Mandatory)][string]$EntitySet,
        [Parameter(Mandatory)][string]$Select,
        [Parameter(Mandatory)][string]$Lookup,
        [Parameter(Mandatory)][string]$CandidateId
    )
    $filter = "$Lookup eq $CandidateId"
    @(Get-Phase5ARows -Path "$EntitySet?%24select=$Select&%24filter=$([Uri]::EscapeDataString($filter))&%24top=20")
}

function Assert-Phase5ACount {
    param([object[]]$Rows, [int]$Expected, [string]$Kind)
    if ($Rows.Count -ne $Expected) {
        throw "Scoped $Kind readback count differs from the Phase 5A acceptance expectation."
    }
}

function Get-Phase5AEntityInfo {
    param([Parameter(Mandatory)][string]$LogicalName)
    $rows = @(Get-Phase5ARows -Path "EntityDefinitions(LogicalName='$LogicalName')?%24select=EntitySetName,PrimaryIdAttribute,PrimaryNameAttribute")
    if ($rows.Count -ne 1 -or -not $rows[0].EntitySetName -or -not $rows[0].PrimaryIdAttribute) {
        throw "Required Dataverse entity metadata is unavailable for $LogicalName."
    }
    $rows[0]
}

function Get-Phase5ASyntheticReference {
    param([string]$LogicalName)
    $info = Get-Phase5AEntityInfo -LogicalName $LogicalName
    if (-not $info.PrimaryNameAttribute) { throw "Primary name metadata is unavailable for $LogicalName." }
    $filter = 'statecode eq 0'
    $select = "$($info.PrimaryIdAttribute),$($info.PrimaryNameAttribute),statecode"
    $rows = @(Get-Phase5ARows -Path "$($info.EntitySetName)?%24select=$select&%24filter=$([Uri]::EscapeDataString($filter))&%24orderby=$($info.PrimaryNameAttribute)%20asc&%24top=5000")
    if ($rows.Count -ge 5000) {
        throw "Active $LogicalName reference results reached the page limit; complete synthetic-reference reconciliation is required."
    }
    $syntheticRows = @($rows | Where-Object {
        [int]$_.statecode -eq 0 -and
        ([string]$_.($info.PrimaryNameAttribute)).StartsWith('[DEV]', [StringComparison]::Ordinal) -and
        [string]$_.($info.PrimaryIdAttribute) -match '^[0-9a-fA-F-]{36}$'
    })
    if ($syntheticRows.Count -lt 1) {
        throw "No active [DEV]-prefixed $LogicalName reference is available; no operation was dispatched."
    }
    [ordered]@{
        LogicalName = $LogicalName
        EntitySetName = [string]$info.EntitySetName
        Id = [string]$syntheticRows[0].($info.PrimaryIdAttribute)
    }
}

try {
    Assert-PacIdentity
    Get-ValidatedToken

    $script:CurrentStage = 'CUSTOM_API_METADATA'
    $apis = @(Get-Phase5ARows -Path "customapis?%24select=uniquename,executeprivilegename,isprivate,isfunction,bindingtype&%24filter=uniquename eq 'os_sr_cact'&%24top=2")
    if ($apis.Count -ne 1 -or [string]$apis[0].uniquename -cne 'os_sr_cact' -or
        [string]$apis[0].executeprivilegename -cne 'prvReados_sr_cand' -or
        [bool]$apis[0].isprivate -ne $true -or
        [bool]$apis[0].isfunction -or [int]$apis[0].bindingtype -ne 0) {
        throw 'Live os_sr_cact metadata differs from the approved Phase 5A unbound operation contract.'
    }

    $script:CurrentStage = 'CANDIDATE_ENTITY_METADATA'
    $candidateInfo = Get-Phase5AEntityInfo -LogicalName 'os_sr_cand'
    $script:CurrentStage = 'CALL_LOG_ENTITY_METADATA'
    $callInfo = Get-Phase5AEntityInfo -LogicalName 'os_sr_call'
    $script:CurrentStage = 'STATUS_HISTORY_ENTITY_METADATA'
    $historyInfo = Get-Phase5AEntityInfo -LogicalName 'os_sr_csh'
    $script:CurrentStage = 'INTERVIEW_SCHEDULE_ENTITY_METADATA'
    $scheduleInfo = Get-Phase5AEntityInfo -LogicalName 'os_sr_intv'
    $script:CurrentStage = 'OPERATION_RECEIPT_ENTITY_METADATA'
    $receiptInfo = Get-Phase5AEntityInfo -LogicalName 'os_sr_oprc'
    if ([string]$candidateInfo.PrimaryIdAttribute -cne 'os_sr_candid' -or
        [string]$callInfo.EntitySetName -cne 'os_sr_calls' -or
        [string]$historyInfo.EntitySetName -cne 'os_sr_cshs' -or
        [string]$scheduleInfo.EntitySetName -cne 'os_sr_intvs' -or
        [string]$receiptInfo.EntitySetName -cne 'os_sr_oprcs') {
        throw 'Candidate Core entity metadata differs from the reviewed table contract.'
    }

    $script:CurrentStage = 'SYNTHETIC_TA_REFERENCE_PREFLIGHT'
    $ta = Get-Phase5ASyntheticReference -LogicalName 'os_sr_ta'
    $script:CurrentStage = 'SYNTHETIC_LOCATION_REFERENCE_PREFLIGHT'
    $location = Get-Phase5ASyntheticReference -LogicalName 'os_sr_loc'
    $stamp = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfff')
    $cases = @(
        [ordered]@{
            Key = 'A'
            Email = "phase5a.$stamp.a@example.invalid"
            Name = "SYNTHETIC Phase5A A $stamp"
            Create = Add-Phase5ACorrelation -List $script:allCorrelations
        },
        [ordered]@{
            Key = 'B'
            Email = "phase5a.$stamp.b@example.invalid"
            Name = "SYNTHETIC Phase5A B $stamp"
            Create = Add-Phase5ACorrelation -List $script:allCorrelations
        },
        [ordered]@{
            Key = 'C'
            Email = "phase5a.$stamp.c@example.invalid"
            Name = "SYNTHETIC Phase5A C $stamp"
            Create = Add-Phase5ACorrelation -List $script:allCorrelations
        },
        [ordered]@{
            Key = 'D'
            Email = "phase5a.$stamp.d@example.invalid"
            Name = "SYNTHETIC Phase5A D $stamp"
            Create = Add-Phase5ACorrelation -List $script:allCorrelations
        }
    )
    foreach ($case in $cases) {
        $case.Answer = Add-Phase5ACorrelation -List $script:allCorrelations
        $case.Waiting = Add-Phase5ACorrelation -List $script:allCorrelations
        $case.Schedule = Add-Phase5ACorrelation -List $script:allCorrelations
        if ($case.Key -ceq 'A') {
            $case.NoAnswer = Add-Phase5ACorrelation -List $script:allCorrelations
            $case.Callback = Add-Phase5ACorrelation -List $script:allCorrelations
            $case.Stale = Add-Phase5ACorrelation -List $script:allCorrelations
            $case.Result = Add-Phase5ACorrelation -List $script:allCorrelations
        }
        elseif ($case.Key -ceq 'C') {
            $case.Result = Add-Phase5ACorrelation -List $script:allCorrelations
        }
        elseif ($case.Key -ceq 'D') {
            $case.Result = Add-Phase5ACorrelation -List $script:allCorrelations
        }
        else {
            $case.Result = Add-Phase5ACorrelation -List $script:allCorrelations
        }
    }
    if ($script:allCorrelations.Count -ne 23) {
        throw 'The fixed Phase 5A correlation matrix is incomplete.'
    }

    $emailsToCheck = @($cases | ForEach-Object { [string]$_.Email }) +
        "conflict.$stamp@example.invalid"
    $candidateSet = [string]$candidateInfo.EntitySetName
    $receiptSet = [string]$receiptInfo.EntitySetName
    $script:CurrentStage = 'CANDIDATE_CORRELATION_COLLISION_GATE'
    $candidateCollisions = [Collections.Generic.List[object]]::new()
    $gateIndex = 0
    foreach ($case in $cases) {
        $gateIndex++
        $script:CurrentStage = "CANDIDATE_CORRELATION_COLLISION_$gateIndex"
        $filter = "os_sr_cand_corid eq '$($case.Create)'"
        foreach ($row in @(Get-Phase5ARows -Path "$candidateSet?%24select=$($candidateInfo.PrimaryIdAttribute)&%24filter=$([Uri]::EscapeDataString($filter))&%24top=2")) {
            $candidateCollisions.Add($row)
        }
    }
    $script:CurrentStage = 'CANDIDATE_EMAIL_COLLISION_GATE'
    $emailCollisions = [Collections.Generic.List[object]]::new()
    foreach ($email in $emailsToCheck) {
        $filter = "os_sr_cand_eml eq '$email'"
        foreach ($row in @(Get-Phase5ARows -Path "$candidateSet?%24select=$($candidateInfo.PrimaryIdAttribute)&%24filter=$([Uri]::EscapeDataString($filter))&%24top=2")) {
            $emailCollisions.Add($row)
        }
    }
    $script:CurrentStage = 'RECEIPT_CORRELATION_COLLISION_GATE'
    $receiptCollisions = [Collections.Generic.List[object]]::new()
    foreach ($correlation in $script:allCorrelations) {
        $filter = "os_sr_oprc_corid eq '$correlation'"
        foreach ($row in @(Get-Phase5ARows -Path "$receiptSet?%24select=$($receiptInfo.PrimaryIdAttribute)&%24filter=$([Uri]::EscapeDataString($filter))&%24top=2")) {
            $receiptCollisions.Add($row)
        }
    }
    if ($candidateCollisions.Count -ne 0 -or $emailCollisions.Count -ne 0 -or $receiptCollisions.Count -ne 0) {
        throw 'A synthetic fixture/correlation collision was found; no Candidate Core operation was dispatched.'
    }

    if ($Mode -ceq 'PlanOnly') {
        [ordered]@{
            Outcome = 'PHASE_5A_RUNTIME_PREFLIGHT_READY'
            Environment = 'VN LMV IT'
            Organization = $OrganizationUrl.TrimEnd('/')
            ApiUniqueName = 'os_sr_cact'
            ExecutePrivilegeName = [string]$apis[0].executeprivilegename
            SyntheticCandidates = $cases.Count
            PlannedApiDispatches = $script:ExpectedDispatches
            PlannedDistinctCorrelations = $script:allCorrelations.Count
            ActiveSyntheticTaReference = $true
            ActiveSyntheticLocationReference = $true
            CandidateCorrelationCollisions = $candidateCollisions.Count
            CandidateEmailCollisions = $emailCollisions.Count
            ReceiptCorrelationCollisions = $receiptCollisions.Count
            RequestCounters = @{ GET = $script:ReadCount; POST = 0 }
            AutomaticRetries = 0
        } | ConvertTo-Json -Depth 8
        return
    }

    $evidenceDirectory = Split-Path -Parent $EvidencePath
    if (-not (Test-Path -LiteralPath $evidenceDirectory -PathType Container)) {
        throw 'Evidence directory must exist before runtime dispatch.'
    }
    $evidenceStream = [IO.File]::Open($EvidencePath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    $evidenceStream.Dispose()

    $correlationHashes = @($script:allCorrelations | ForEach-Object {
        [Convert]::ToHexString(
            [Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($_))
        ).ToLowerInvariant()
    })
    $script:Journal = [ordered]@{
        SchemaVersion = 1
        Target = 'VN LMV IT'
        Organization = $OrganizationUrl.TrimEnd('/')
        Api = 'os_sr_cact'
        ExecutionPrivilegeName = [string]$apis[0].executeprivilegename
        StartedAtUtc = [DateTime]::UtcNow.ToString('o')
        DispatchBudget = $script:ExpectedDispatches
        Dispatches = [Collections.Generic.List[object]]::new()
        CorrelationSha256 = $correlationHashes
        CandidateEmailDomains = @('example.invalid')
        SyntheticCandidateCount = $cases.Count
        ReadBudget = $script:MaximumReads
        InitialCollisionCounts = [ordered]@{
            CandidateCorrelation = $candidateCollisions.Count
            CandidateEmail = $emailCollisions.Count
            ReceiptCorrelation = $receiptCollisions.Count
        }
        FinalCounts = $null
        FinalStates = $null
        RequestCounters = $null
        Outcome = 'IN_PROGRESS'
    }
    Save-Phase5ARuntimeJournal

    $scheduleBaseUtc = [DateTime]::UtcNow.Date.AddDays(7).AddHours(15)
    $candidateIds = @{}
    $expectedCounts = @{
        A = @{ Calls = 3; History = 4; Schedules = 1; Receipts = 7; Status = 100010004 }
        B = @{ Calls = 1; History = 4; Schedules = 1; Receipts = 5; Status = 100010005 }
        C = @{ Calls = 1; History = 4; Schedules = 2; Receipts = 5; Status = 100010000 }
        D = @{ Calls = 1; History = 4; Schedules = 1; Receipts = 5; Status = 100010000 }
    }

    foreach ($case in $cases) {
        $createBody = New-Phase5AAction -Action 'CreateCandidate' -Correlation $case.Create -Inputs @{
            CandidateName = $case.Name
            CandidateEmail = $case.Email
        }
        $createResult = Invoke-Phase5AOperation -Body $createBody
        Assert-Phase5AResult -Result $createResult -ResultCode 'Applied' -CurrentStatus 100010000 -Action "CreateCandidate $($case.Key)"
        $candidateId = Get-Phase5ACandidateId -CandidateSet $candidateSet -CreationCorrelation $case.Create
        $candidateIds[$case.Key] = $candidateId
        Assert-Phase5AStatus -CandidateSet $candidateSet -CandidateId $candidateId -ExpectedStatus 100010000

        if ($case.Key -ceq 'A') {
            $replay = Invoke-Phase5AOperation -Body $createBody
            Assert-Phase5AResult -Result $replay -ResultCode 'DuplicateReplay' -CurrentStatus 100010000 -Action 'CreateCandidate identical replay'
            $conflictBody = New-Phase5AAction -Action 'CreateCandidate' -Correlation $case.Create -Inputs @{
                CandidateName = $case.Name
                CandidateEmail = "conflict.$stamp@example.invalid"
            }
            $null = Invoke-Phase5AOperation -Body $conflictBody -ExpectedFailure 'CORRELATION_CONFLICT'

            $contactedAt = [DateTime]::UtcNow.AddSeconds(-15).ToString('o')
            $noAnswerBody = New-Phase5AAction -Action 'RecordCall' -Correlation $case.NoAnswer `
                -ExpectedStatus 100010000 -CandidateId $candidateId -Inputs @{
                    CallOutcome = 100010001; ContactedAt = $contactedAt; Notes = 'SYNTHETIC no answer'
                }
            $noAnswer = Invoke-Phase5AOperation -Body $noAnswerBody
            Assert-Phase5AResult -Result $noAnswer -ResultCode 'Applied' -CurrentStatus 100010000 -Action 'RecordCall No Answer'
            $noAnswerReplay = Invoke-Phase5AOperation -Body $noAnswerBody
            Assert-Phase5AResult -Result $noAnswerReplay -ResultCode 'DuplicateReplay' -CurrentStatus 100010000 -Action 'RecordCall identical replay'
            $noAnswerConflictBody = New-Phase5AAction -Action 'RecordCall' -Correlation $case.NoAnswer `
                -ExpectedStatus 100010000 -CandidateId $candidateId -Inputs @{
                    CallOutcome = 100010002; ContactedAt = $contactedAt; Notes = 'SYNTHETIC conflicting replay'
                }
            $null = Invoke-Phase5AOperation -Body $noAnswerConflictBody -ExpectedFailure 'CORRELATION_CONFLICT'
            $null = Invoke-Phase5AOperation -Body (New-Phase5AAction -Action 'RecordCall' -Correlation $case.Callback `
                -ExpectedStatus 100010000 -CandidateId $candidateId -Inputs @{
                    CallOutcome = 100010002; ContactedAt = $contactedAt; Notes = 'SYNTHETIC call back requested'
                })
        }

        $answer = Invoke-Phase5AOperation -Body (New-Phase5AAction -Action 'RecordCall' -Correlation $case.Answer `
            -ExpectedStatus 100010000 -CandidateId $candidateId -Inputs @{
                CallOutcome = 100010000
                ContactedAt = [DateTime]::UtcNow.AddSeconds(-15).ToString('o')
                Notes = "SYNTHETIC answered case $($case.Key)"
            })
        Assert-Phase5AResult -Result $answer -ResultCode 'Applied' -CurrentStatus 100010001 -Action "RecordCall Answered $($case.Key)"
        Assert-Phase5AStatus -CandidateSet $candidateSet -CandidateId $candidateId -ExpectedStatus 100010001

        $waiting = Invoke-Phase5AOperation -Body (New-Phase5AAction -Action 'ProceedToScheduling' -Correlation $case.Waiting `
            -ExpectedStatus 100010001 -CandidateId $candidateId)
        Assert-Phase5AResult -Result $waiting -ResultCode 'Applied' -CurrentStatus 100010002 -Action "ProceedToScheduling $($case.Key)"
        Assert-Phase5AStatus -CandidateSet $candidateSet -CandidateId $candidateId -ExpectedStatus 100010002

        if ($case.Key -ceq 'A') {
            $stale = New-Phase5AAction -Action 'RecordCall' -Correlation $case.Stale `
                -ExpectedStatus 100010000 -CandidateId $candidateId -Inputs @{
                    CallOutcome = 100010001
                    ContactedAt = [DateTime]::UtcNow.AddSeconds(-15).ToString('o')
                    Notes = 'SYNTHETIC stale status rejection'
                }
            $null = Invoke-Phase5AOperation -Body $stale -ExpectedFailure 'STALE_EXPECTED_STATUS'
            $script:Journal.StaleExpectedStatusVerified = $true
            Save-Phase5ARuntimeJournal
        }

        $startAt = $scheduleBaseUtc.AddDays([int]([char]$case.Key - [char]'A'))
        $scheduleInputs = @{
            InterviewerId = [string]$ta.Id
            LocationId = [string]$location.Id
            StartAt = $startAt.ToString('o')
            EndAt = $startAt.AddHours(1).ToString('o')
            Notes = "SYNTHETIC Phase5A initial schedule $($case.Key)"
        }
        $schedule = Invoke-Phase5AOperation -Body (New-Phase5AAction -Action 'MarkRound1Scheduled' -Correlation $case.Schedule `
            -ExpectedStatus 100010002 -CandidateId $candidateId -Inputs $scheduleInputs)
        Assert-Phase5AResult -Result $schedule -ResultCode 'Applied' -CurrentStatus 100010003 -Action "MarkRound1Scheduled $($case.Key)"
        Assert-Phase5AStatus -CandidateSet $candidateSet -CandidateId $candidateId -ExpectedStatus 100010003

        if ($case.Key -ceq 'A' -or $case.Key -ceq 'B') {
            $resultAction = if ($case.Key -ceq 'A') { 'RecordPass' } else { 'RecordFail' }
            $resultStatus = if ($case.Key -ceq 'A') { 100010004 } else { 100010005 }
            $resultNotes = "SYNTHETIC Phase5A $($case.Key) result"
            $result = Invoke-Phase5AOperation -Body (New-Phase5AAction -Action $resultAction -Correlation $case.Result `
                -ExpectedStatus 100010003 -CandidateId $candidateId -Inputs @{ ResultNotes = $resultNotes })
            Assert-Phase5AResult -Result $result -ResultCode 'Applied' -CurrentStatus $resultStatus -Action $resultAction
            Assert-Phase5AStatus -CandidateSet $candidateSet -CandidateId $candidateId -ExpectedStatus $resultStatus
        }
        elseif ($case.Key -ceq 'C') {
            $rescheduleStart = $startAt.AddDays(2)
            $rescheduleInputs = @{
                InterviewerId = [string]$ta.Id
                LocationId = [string]$location.Id
                StartAt = $rescheduleStart.ToString('o')
                EndAt = $rescheduleStart.AddHours(1).ToString('o')
                Notes = 'SYNTHETIC Phase5A replacement schedule'
                Reason = 'SYNTHETIC candidate requested reschedule'
            }
            $reschedule = Invoke-Phase5AOperation -Body (New-Phase5AAction -Action 'RequestReschedule' -Correlation $case.Result `
                -ExpectedStatus 100010003 -CandidateId $candidateId -Inputs $rescheduleInputs)
            Assert-Phase5AResult -Result $reschedule -ResultCode 'Applied' -CurrentStatus 100010000 -Action 'RequestReschedule'
            Assert-Phase5AStatus -CandidateSet $candidateSet -CandidateId $candidateId -ExpectedStatus 100010000
        }
        else {
            $cancel = Invoke-Phase5AOperation -Body (New-Phase5AAction -Action 'CancelRound1' -Correlation $case.Result `
                -ExpectedStatus 100010003 -CandidateId $candidateId -Inputs @{
                    Reason = 'SYNTHETIC candidate requested cancellation'
                })
            Assert-Phase5AResult -Result $cancel -ResultCode 'Applied' -CurrentStatus 100010000 -Action 'CancelRound1'
            Assert-Phase5AStatus -CandidateSet $candidateSet -CandidateId $candidateId -ExpectedStatus 100010000
        }
    }

    if ($script:DispatchCount -ne $script:ExpectedDispatches) {
        throw 'Runtime dispatch count differs from the fixed acceptance matrix.'
    }
    $allCalls = [Collections.Generic.List[object]]::new()
    $allHistory = [Collections.Generic.List[object]]::new()
    $allSchedules = [Collections.Generic.List[object]]::new()
    $allReceipts = [Collections.Generic.List[object]]::new()
    $finalStates = [ordered]@{}
    foreach ($case in $cases) {
        $candidateId = $candidateIds[$case.Key]
        $expected = $expectedCounts[$case.Key]
        $calls = Get-Phase5ARelatedRows -EntitySet ([string]$callInfo.EntitySetName) `
            -Select 'os_sr_call_corid,os_sr_call_out' -Lookup '_os_sr_call_cand_value' -CandidateId $candidateId
        $history = Get-Phase5ARelatedRows -EntitySet ([string]$historyInfo.EntitySetName) `
            -Select 'os_sr_csh_corid,os_sr_csh_cact,os_sr_csh_prevstat,os_sr_csh_newstat,os_sr_csh_rsn' `
            -Lookup '_os_sr_csh_cand_value' -CandidateId $candidateId
        $schedules = Get-Phase5ARelatedRows -EntitySet ([string]$scheduleInfo.EntitySetName) `
            -Select 'os_sr_intv_rnd,os_sr_intv_stat,os_sr_intv_res,os_sr_intv_rsn,os_sr_intv_chg,os_sr_intv_recat,os_sr_intv_rnts' `
            -Lookup '_os_sr_intv_cand_value' -CandidateId $candidateId
        $receipts = Get-Phase5ARelatedRows -EntitySet ([string]$receiptInfo.EntitySetName) `
            -Select 'os_sr_oprc_corid,os_sr_oprc_cact,os_sr_oprc_newstat,os_sr_oprc_prevstat' `
            -Lookup '_os_sr_oprc_cand_value' -CandidateId $candidateId
        Assert-Phase5ACount -Rows $calls -Expected $expected.Calls -Kind "Call Log $($case.Key)"
        Assert-Phase5ACount -Rows $history -Expected $expected.History -Kind "Status History $($case.Key)"
        Assert-Phase5ACount -Rows $schedules -Expected $expected.Schedules -Kind "Interview Schedule $($case.Key)"
        Assert-Phase5ACount -Rows $receipts -Expected $expected.Receipts -Kind "Operation Receipt $($case.Key)"
        if (@($receipts | ForEach-Object { [string]$_.os_sr_oprc_corid } | Sort-Object -Unique).Count -ne $expected.Receipts) {
            throw "Operation Receipt correlations were duplicated for Candidate $($case.Key)."
        }
        if (@($history | Where-Object {
            [int]$_.os_sr_csh_newstat -notin @(100010001, 100010002, 100010003, 100010004, 100010005)
        }).Count -ne 0) {
            throw "Unexpected Status History values were found for Candidate $($case.Key)."
        }
        if ($case.Key -ceq 'A' -or $case.Key -ceq 'B') {
            $resultCode = if ($case.Key -ceq 'A') { 100000001 } else { 100000002 }
            if (@($schedules | Where-Object {
                [int]$_.os_sr_intv_stat -eq 100000001 -and
                [int]$_.os_sr_intv_res -eq $resultCode -and
                $_.os_sr_intv_recat -and $_.os_sr_intv_rnts
            }).Count -ne 1) {
                throw "Persisted Round 1 result evidence did not reconcile for Candidate $($case.Key)."
            }
        }
        elseif ($case.Key -ceq 'C') {
            if (@($schedules | Where-Object { [int]$_.os_sr_intv_stat -eq 100000003 -and $_.os_sr_intv_rsn -and $_.os_sr_intv_chg }).Count -ne 1 -or
                @($schedules | Where-Object { [int]$_.os_sr_intv_stat -eq 100000000 }).Count -ne 1) {
                throw 'Reschedule did not preserve the superseded schedule and one proposed replacement.'
            }
            if (@($history | Where-Object {
                [string]$_.os_sr_csh_cact -ceq 'RequestReschedule' -and
                [int]$_.os_sr_csh_newstat -eq 100010000 -and $_.os_sr_csh_rsn
            }).Count -ne 1) {
                throw 'Reschedule Status History did not preserve its reason and return state.'
            }
        }
        else {
            if (@($schedules | Where-Object { [int]$_.os_sr_intv_stat -eq 100000002 -and $_.os_sr_intv_rsn -and $_.os_sr_intv_chg }).Count -ne 1 -or
                @($history | Where-Object {
                    [string]$_.os_sr_csh_cact -ceq 'CancelRound1' -and
                    [int]$_.os_sr_csh_newstat -eq 100010000 -and $_.os_sr_csh_rsn
                }).Count -ne 1) {
                throw 'Cancellation schedule/history evidence did not reconcile.'
            }
        }
        $finalStates[$case.Key] = $expected.Status
        foreach ($row in $calls) { $allCalls.Add($row) }
        foreach ($row in $history) { $allHistory.Add($row) }
        foreach ($row in $schedules) { $allSchedules.Add($row) }
        foreach ($row in $receipts) { $allReceipts.Add($row) }
    }
    if ($allCalls.Count -ne 6 -or $allHistory.Count -ne 16 -or
        $allSchedules.Count -ne 5 -or $allReceipts.Count -ne 22) {
        throw 'Aggregate Candidate Core persistence counts differ from the expected runtime matrix.'
    }
    $receiptActionCounts = @{}
    foreach ($row in $allReceipts) {
        $action = [string]$row.os_sr_oprc_cact
        if (-not $receiptActionCounts.ContainsKey($action)) { $receiptActionCounts[$action] = 0 }
        $receiptActionCounts[$action]++
    }
    $expectedReceiptActions = @{
        CreateCandidate = 4; RecordCall = 6; ProceedToScheduling = 4
        MarkRound1Scheduled = 4; RecordPass = 1; RecordFail = 1
        RequestReschedule = 1; CancelRound1 = 1
    }
    foreach ($action in $expectedReceiptActions.Keys) {
        if ([int]$receiptActionCounts[$action] -ne $expectedReceiptActions[$action]) {
            throw "Operation Receipt action count did not match the runtime matrix for $action."
        }
    }
    if ($script:Journal.Dispatches.Count -ne $script:ExpectedDispatches -or
        @($script:Journal.Dispatches | Where-Object State -eq 'ACKNOWLEDGED').Count -ne 24 -or
        @($script:Journal.Dispatches | Where-Object State -eq 'EXPECTED_REJECTION').Count -ne 3) {
        throw 'Runtime dispatch journal does not reconcile with the expected applied, replayed, and rejected calls.'
    }

    $script:Journal.CompletedAtUtc = [DateTime]::UtcNow.ToString('o')
    $script:Journal.FinalCounts = [ordered]@{
        Candidates = $cases.Count
        CallLogs = $allCalls.Count
        StatusHistories = $allHistory.Count
        InterviewSchedules = $allSchedules.Count
        OperationReceipts = $allReceipts.Count
    }
    $script:Journal.FinalStates = $finalStates
    $script:Journal.RequestCounters = @{ GET = $script:ReadCount; POST = $script:DispatchCount }
    $script:Journal.Outcome = 'PHASE_5A_CANDIDATE_CORE_RUNTIME_MATRIX_PASSED'
    Save-Phase5ARuntimeJournal
    [ordered]@{
        Outcome = $script:Journal.Outcome
        Environment = 'VN LMV IT'
        ApiUniqueName = 'os_sr_cact'
        ExecutePrivilegeName = [string]$apis[0].executeprivilegename
        SyntheticCandidates = $cases.Count
        CandidateStatuses = $finalStates
        PersistedCounts = $script:Journal.FinalCounts
        ReplayAndConcurrency = 'Identical replay returned DuplicateReplay; conflicting replay and stale ExpectedStatus were rejected.'
        Dispatches = $script:DispatchCount
        AutomaticRetries = 0
        EvidencePath = [IO.Path]::GetFullPath($EvidencePath)
        RequestCounters = $script:Journal.RequestCounters
    } | ConvertTo-Json -Depth 8
}
catch {
    if ($script:Journal) {
        $script:Journal.Outcome = 'STOPPED_WITHOUT_RETRY'
        $script:Journal.StoppedAtUtc = [DateTime]::UtcNow.ToString('o')
        $script:Journal.RequestCounters = @{ GET = $script:ReadCount; POST = $script:DispatchCount }
        Save-Phase5ARuntimeJournal
    }
    throw "Phase 5A runtime stopped at $($script:CurrentStage); no operation was retried. $($_.Exception.Message)"
}
finally {
    $script:AccessToken = $null
    $script:PacUserEmail = $null
    $script:ExpectedUserId = $null
    [Environment]::SetEnvironmentVariable('BSO_RS_EXPECTED_USER_ID', $null, 'Process')
}
