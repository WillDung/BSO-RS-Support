#requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$Apply,
    [switch]$PlanOnly,
    [switch]$CreateOnlyRecovery,
    [string]$AuthorizationReference,
    [string]$EnvironmentName = $env:BSO_RS_ENVIRONMENT_NAME,
    [string]$OrganizationUrl = $env:BSO_RS_ORG_URL,
    [string]$ExpectedEnvironmentId = $env:BSO_RS_EXPECTED_ENVIRONMENT_ID,
    [string]$ExpectedOrganizationId = $env:BSO_RS_EXPECTED_ORG_ID,
    [string]$ExpectedUserId = $env:BSO_RS_EXPECTED_USER_ID,
    [string]$DisplayCollectionName,
    [ValidateSet('os_sr_ta', 'os_sr_pos', 'os_sr_csrc', 'os_sr_loc')]
    [string]$TableName = 'os_sr_ta'
)

$ErrorActionPreference = 'Stop'
$script:AccessToken = $null
$script:AccessTokenIssuedAt = [DateTimeOffset]::MinValue
$script:AccessTokenExpiresOn = [DateTimeOffset]::MinValue
$script:LastHttpFailure = $null
$script:LastRequestDispatchStarted = $false
$script:ApiRoot = $null
$script:WritesStarted = $false
$script:WritesAllowed = $false
$script:RequestCounts = @{ GET = 0; POST = 0 }
$script:WriteResults = [System.Collections.Generic.List[object]]::new()
$script:RecoveryState = if ($CreateOnlyRecovery) { 'PRECHECK' } else { $null }
$script:RecoveryTransitions = [System.Collections.Generic.List[object]]::new()
$script:RecoveryExpectedFingerprint = '0f7372eeb66c0214ae08ed0dc74f82c981cc4cd73baa9156f16d6e1bd1f48e80'
$script:RecoveryActualFingerprint = $null
$script:RecoveryReconciliation = $null
$script:RecoveryResponseClass = $null
$script:RecoveryAttemptTimestampUtc = $null
$script:RecoveryEnvironmentVerified = $false
$script:RecoveryIdentityVerified = $false
$script:RecoveryVerifiedPrivileges = @()
$script:RecoveryPreflight = $null
$script:RecoveryRequestId = $null
$script:RecoveryCorrelationId = $null
$script:Definitions = Import-PowerShellDataFile (Join-Path $PSScriptRoot 'ReferenceTableDefinitions.psd1')
$script:Definition = $script:Definitions[$TableName]
$expectedCollectionName = $script:Definition.DisplayCollectionName
$collectionNameWasExplicit = -not [string]::IsNullOrWhiteSpace($DisplayCollectionName)
if (-not $collectionNameWasExplicit) { $DisplayCollectionName = $expectedCollectionName }

function New-Label {
    param([Parameter(Mandatory = $true)][string]$Text)
    [ordered]@{
        '@odata.type' = 'Microsoft.Dynamics.CRM.Label'
        LocalizedLabels = @([ordered]@{
            '@odata.type' = 'Microsoft.Dynamics.CRM.LocalizedLabel'
            Label = $Text
            LanguageCode = 1033
        })
    }
}

function New-RequiredLevel {
    param([ValidateSet('None', 'ApplicationRequired')][string]$Value = 'ApplicationRequired')
    [ordered]@{
        Value = $Value
        CanBeChanged = $true
        ManagedPropertyLogicalName = 'canmodifyrequirementlevelsettings'
    }
}

function New-ColumnPayload {
    param([Parameter(Mandatory = $true)][System.Collections.IDictionary]$Column)
    if ($Column.AttributeType -notin @('String', 'Memo')) { throw 'Unsupported reference column type.' }
    $payload = [ordered]@{
        '@odata.type' = "Microsoft.Dynamics.CRM.$($Column.AttributeType)AttributeMetadata"
        AttributeType = $Column.AttributeType
        AttributeTypeName = [ordered]@{ Value = "$($Column.AttributeType)Type" }
        SchemaName = $Column.SchemaName
        DisplayName = New-Label $Column.DisplayName
        RequiredLevel = New-RequiredLevel $Column.RequiredLevel
        MaxLength = $Column.MaxLength
        IsPrimaryName = [bool]$Column.IsPrimaryName
    }
    if ($Column.AttributeType -ceq 'String') { $payload.FormatName = [ordered]@{ Value = $Column.FormatName } }
    else { $payload.Format = $Column.FormatName }
    $payload
}

function New-SchemaPayloads {
    $table = [ordered]@{
        '@odata.type' = 'Microsoft.Dynamics.CRM.EntityMetadata'
        SchemaName = $TableName
        DisplayName = New-Label $script:Definition.DisplayName
        DisplayCollectionName = New-Label $DisplayCollectionName
        OwnershipType = $script:Definition.OwnershipType
        IsActivity = $false
        HasActivities = $false
        HasNotes = $false
        Attributes = @(New-ColumnPayload $script:Definition.PrimaryName)
    }
    $columns = @($script:Definition.Columns | ForEach-Object { New-ColumnPayload $_ })
    [pscustomobject]@{ Table = $table; Columns = $columns; EmailColumn = @($columns | Where-Object { $_.FormatName.Value -ceq 'Email' }) | Select-Object -First 1 }
}

function Get-PayloadFingerprint {
    param([Parameter(Mandatory = $true)][object]$Payload)
    $json = ConvertTo-Json -InputObject $Payload -Depth 40 -Compress
    $bytes = [Text.Encoding]::UTF8.GetBytes($json)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-', '').ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}

function Set-RecoveryState {
    param([Parameter(Mandatory = $true)][string]$State)
    $allowed = @{
        PRECHECK = @('READY', 'BLOCKED', 'FAILED_VALIDATION')
        READY = @('WRITE_ATTEMPTED', 'BLOCKED', 'FAILED_VALIDATION')
        WRITE_ATTEMPTED = @('RECONCILING')
        RECONCILING = @('VERIFIED_SUCCESS', 'BLOCKED', 'FAILED_AUTH', 'FAILED_AUTHZ', 'FAILED_VALIDATION', 'UNCERTAIN', 'PARTIAL_STATE')
        VERIFIED_SUCCESS = @()
        BLOCKED = @()
        FAILED_AUTH = @()
        FAILED_AUTHZ = @()
        FAILED_VALIDATION = @()
        UNCERTAIN = @()
        PARTIAL_STATE = @()
    }
    if ($State -notin $allowed.Keys) { throw 'Unknown recovery state.' }
    if ($script:RecoveryState -eq $State) { return }
    if ($null -eq $script:RecoveryState -or $State -notin $allowed[$script:RecoveryState]) {
        throw 'Invalid recovery state transition.'
    }
    $script:RecoveryState = $State
    $script:RecoveryTransitions.Add([ordered]@{
        State = $State
        TimestampUtc = [DateTimeOffset]::UtcNow.ToString('o')
    })
}

function Get-RecoveryFailureClass {
    param([Nullable[int]]$StatusCode, [string]$ExceptionCategory)
    if ($null -ne $StatusCode -and $StatusCode -ge 100 -and $StatusCode -le 599) {
        if ($StatusCode -eq 401) { return 'HTTP_401' }
        if ($StatusCode -eq 403) { return 'HTTP_403' }
        if ($StatusCode -eq 408) { return 'TIMEOUT' }
        if ($StatusCode -eq 429) { return 'HTTP_429' }
        if ($StatusCode -ge 500) { return 'HTTP_5XX' }
        if ($StatusCode -ge 400) { return 'HTTP_4XX_VALIDATION' }
        return 'UNKNOWN_HTTP_FAILURE'
    }
    if ($ExceptionCategory -eq 'Timeout') { return 'TIMEOUT' }
    if ($ExceptionCategory -eq 'Transport') { return 'TRANSPORT_FAILURE' }
    'UNKNOWN_HTTP_FAILURE'
}

function Get-RecoveryFailureState {
    param([Nullable[int]]$StatusCode, [string]$FailureClass)
    if ($FailureClass -eq 'HTTP_401' -or $StatusCode -eq 401) { return 'FAILED_AUTH' }
    if ($FailureClass -eq 'HTTP_403' -or $StatusCode -eq 403) { return 'FAILED_AUTHZ' }
    if ($FailureClass -eq 'HTTP_4XX_VALIDATION' -or
        ($null -ne $StatusCode -and $StatusCode -ge 400 -and $StatusCode -lt 500 -and $StatusCode -notin @(408, 429))) {
        return 'FAILED_VALIDATION'
    }
    'UNCERTAIN'
}

function Assert-CreateOnlyRecoveryTable {
    param([Parameter(Mandatory = $true)][string]$Name)
    if ($Name -cne 'os_sr_pos') { throw 'Create-only recovery is restricted to os_sr_pos.' }
}

function Assert-PositionPayloadFingerprint {
    param([Parameter(Mandatory = $true)][object]$Payload)
    $script:RecoveryActualFingerprint = Get-PayloadFingerprint -Payload $Payload
    if ($script:RecoveryActualFingerprint -cne $script:RecoveryExpectedFingerprint) {
        if ($script:RecoveryState -eq 'PRECHECK') { Set-RecoveryState -State 'FAILED_VALIDATION' }
        throw 'Position payload fingerprint differs from the approved recovery payload; no authentication or request was attempted.'
    }
    $script:RecoveryActualFingerprint
}

function Assert-ExpectedRecoveryUser {
    param([Parameter(Mandatory = $true)][string]$ActualUserId)
    $expectedUserGuid = [Guid]::Empty
    if (-not [Guid]::TryParse($ExpectedUserId, [ref]$expectedUserGuid) -or
        $ActualUserId -ine $expectedUserGuid.ToString()) {
        throw 'PAC identity does not match BSO_RS_EXPECTED_USER_ID; stop without displaying the identity.'
    }
}

function Assert-RequiredPrivilegeSet {
    param(
        [Parameter(Mandatory = $true)][object[]]$Privileges,
        [Parameter(Mandatory = $true)][string[]]$RequiredNames
    )
    if (@($Privileges).Count -ne @($RequiredNames).Count) {
        throw 'Current identity lacks one or more required metadata privileges; stop without writes.'
    }
}

function Assert-RecoveryInventory {
    param(
        [Parameter(Mandatory = $true)][string[]]$ProjectTables,
        [Parameter(Mandatory = $true)][object[]]$SolutionComponents,
        [Parameter(Mandatory = $true)][string[]]$ExistingTableIds
    )
    if (@($ProjectTables).Count -ne 1 -or $ProjectTables[0] -cne 'os_sr_ta') {
        throw 'Create-only recovery requires the verified TA-only project table inventory.'
    }
    if (@($SolutionComponents | Where-Object {
        [int]$_.componenttype -in @(1, 2) -and [string]$_.objectid -notin $ExistingTableIds
    }).Count) {
        throw 'Solution contains an unverified table or column component; Position absence cannot be established.'
    }
}

function Assert-SchemaPayloads {
    param([Parameter(Mandatory = $true)][object]$Payloads)
    if ($Payloads.Table.SchemaName -cne $TableName -or
        $Payloads.Table.'@odata.type' -cne 'Microsoft.Dynamics.CRM.EntityMetadata' -or
        $Payloads.Table.OwnershipType -cne 'OrganizationOwned' -or
        $Payloads.Table.DisplayName.LocalizedLabels[0].Label -cne $script:Definition.DisplayName -or
        $Payloads.Table.DisplayCollectionName.LocalizedLabels[0].Label -cne $expectedCollectionName -or
        $Payloads.Table.IsActivity -ne $false -or $Payloads.Table.HasActivities -ne $false -or $Payloads.Table.HasNotes -ne $false -or
        @($Payloads.Table.Attributes).Count -ne 1 -or @($Payloads.Columns).Count -ne @($script:Definition.Columns).Count) {
        throw 'Local table payload differs from the declared reference schema.'
    }
    $tableKeys = @('@odata.type', 'SchemaName', 'DisplayName', 'DisplayCollectionName', 'OwnershipType', 'IsActivity', 'HasActivities', 'HasNotes', 'Attributes')
    if (@($Payloads.Table.GetEnumerator() | Where-Object { $_.Key -notin $tableKeys }).Count) { throw 'Unintended table payload property.' }
    $actual = @($Payloads.Table.Attributes) + @($Payloads.Columns)
    $declared = @($script:Definition.PrimaryName) + @($script:Definition.Columns)
    for ($index = 0; $index -lt $declared.Count; $index++) {
        $expected = New-ColumnPayload $declared[$index]
        if (($actual[$index] | ConvertTo-Json -Depth 20 -Compress) -cne ($expected | ConvertTo-Json -Depth 20 -Compress)) {
            throw "Local column payload mismatch: $($declared[$index].SchemaName)."
        }
    }
}

function Write-Result {
    param(
        [Parameter(Mandatory = $true)][string]$Stage,
        [Parameter(Mandatory = $true)][string]$Status,
        [Parameter(Mandatory = $true)][object]$Details
    )
    [pscustomobject]@{ Stage = $Stage; Status = $Status; Details = $Details } |
        ConvertTo-Json -Depth 40 -Compress | Write-Output
}

function Get-SafeErrorMessage {
    param([Parameter(Mandatory = $true)][System.Management.Automation.ErrorRecord]$Record)
    'Operation stopped; raw exception details omitted. Review the safe diagnostic and reconcile before any recovery.'
}

function Get-SafeDiagnosticText {
    param([AllowEmptyString()][string]$Text)
    'Untrusted text omitted.'
}

function Get-SafeResponseHeader {
    param([object]$Headers, [Parameter(Mandatory = $true)][string]$Name)
    if ($null -eq $Headers) { return $null }
    $value = $null
    if ($Headers -is [System.Net.Http.Headers.HttpHeaders]) {
        $values = $null
        if (-not $Headers.TryGetValues($Name, [ref]$values)) { return $null }
        $value = [string](@($values) -join ', ')
    }
    elseif ($Headers -is [System.Collections.Specialized.NameValueCollection]) {
        $value = [string]$Headers.Get($Name)
    }
    elseif ($Headers -is [System.Collections.IDictionary]) {
        foreach ($key in $Headers.Keys) {
            if ([string]$key -ieq $Name) {
                $value = [string](@($Headers[$key]) -join ', ')
                break
            }
        }
    }
    else {
        $property = $Headers.PSObject.Properties | Where-Object { $_.Name -ieq $Name } | Select-Object -First 1
        if ($property) { $value = [string]$property.Value }
    }
    if ($value -cmatch '^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$') {
        return $value.ToLowerInvariant()
    }
    return $null
}

function Get-SafeAuthenticationChallenge {
    param([object]$Headers)
    $challenge = Get-SafeRawResponseHeader -Headers $Headers -Name 'WWW-Authenticate'
    if ([string]::IsNullOrWhiteSpace($challenge)) { return $null }
    $scheme = if ($challenge -match '^\s*Bearer(?:\s|$)') { 'Bearer' }
        elseif ($challenge -match '^\s*Basic(?:\s|$)') { 'Basic' }
        else { 'Other' }
    $errorMatch = [regex]::Match($challenge, '(?i)(?:^|[, ]+)error\s*=\s*"?([a-z_]+)"?')
    $safeError = if ($errorMatch.Success -and $errorMatch.Groups[1].Value.ToLowerInvariant() -in @('invalid_token','insufficient_scope')) {
        $errorMatch.Groups[1].Value.ToLowerInvariant()
    } else { $null }
    [ordered]@{
        Scheme = $scheme
        Error = $safeError
        ErrorDescriptionPresent = ($challenge -match '(?i)(?:^|[, ]+)error_description\s*=')
        ClaimsChallengePresent = ($challenge -match '(?i)(?:^|[, ]+)claims\s*=')
    }
}

function Get-SafeRawResponseHeader {
    param([object]$Headers, [Parameter(Mandatory = $true)][string]$Name)
    if ($null -eq $Headers) { return $null }
    if ($Headers -is [System.Net.Http.Headers.HttpHeaders]) {
        $values = $null
        if ($Headers.TryGetValues($Name, [ref]$values)) { return [string](@($values) -join ', ') }
        return $null
    }
    if ($Headers -is [System.Collections.Specialized.NameValueCollection]) {
        return [string]$Headers.Get($Name)
    }
    if ($Headers -is [System.Collections.IDictionary]) {
        foreach ($key in $Headers.Keys) {
            if ([string]$key -ieq $Name) { return [string](@($Headers[$key]) -join ', ') }
        }
        return $null
    }
    $property = $Headers.PSObject.Properties | Where-Object { $_.Name -ieq $Name } | Select-Object -First 1
    if ($property) { return [string]$property.Value }
    return $null
}

function Get-HttpExceptionDetails {
    param([System.Management.Automation.ErrorRecord]$ErrorRecord)
    $response = $null
    $exception = $ErrorRecord.Exception
    for ($depth = 0; $null -ne $exception -and $depth -lt 5; $depth++) {
        try { $response = $exception.Response } catch { }
        if ($response -or -not $exception.InnerException) { break }
        $exception = $exception.InnerException
    }
    $statusCode = $null
    if ($null -ne $response) {
        try {
            $candidate = [int]$response.StatusCode
            if ($candidate -ge 100 -and $candidate -le 599) { $statusCode = $candidate }
        } catch { }
    }
    if ($null -eq $statusCode) {
        try {
            $candidate = [int]$exception.StatusCode
            if ($candidate -ge 100 -and $candidate -le 599) { $statusCode = $candidate }
        } catch { }
    }
    $headers = $null
    if ($null -ne $response) {
        $headers = $response.Headers
        if ($null -ne $response.Content -and $response.Content.Headers) {
            $contentHeaders = $response.Content.Headers
            $headers = @{
                'x-ms-service-request-id' = Get-SafeRawResponseHeader -Headers $headers -Name 'x-ms-service-request-id'
                'x-ms-request-id' = Get-SafeRawResponseHeader -Headers $headers -Name 'x-ms-request-id'
                'x-ms-correlation-request-id' = Get-SafeRawResponseHeader -Headers $headers -Name 'x-ms-correlation-request-id'
                'request-id' = Get-SafeRawResponseHeader -Headers $headers -Name 'request-id'
                'WWW-Authenticate' = Get-SafeRawResponseHeader -Headers $headers -Name 'WWW-Authenticate'
            }
            foreach ($name in @('x-ms-service-request-id','x-ms-request-id','x-ms-correlation-request-id','request-id','WWW-Authenticate')) {
                $value = Get-SafeRawResponseHeader -Headers $contentHeaders -Name $name
                if ($value) { $headers[$name] = $value }
            }
        }
    }
    $exceptionCategory = 'Unknown'
    if ($exception -is [System.TimeoutException] -or
        $exception -is [System.Threading.Tasks.TaskCanceledException] -or
        ($exception -is [System.Net.WebException] -and $exception.Status -eq [System.Net.WebExceptionStatus]::Timeout)) {
        $exceptionCategory = 'Timeout'
    }
    elseif ($null -ne $statusCode) { $exceptionCategory = 'HttpResponse' }
    elseif ($exception -is [System.Net.Http.HttpRequestException] -or
        $exception -is [System.Net.WebException] -or
        $exception -is [System.IO.IOException]) {
        $exceptionCategory = 'Transport'
    }
    $errorCode = $null
    $message = [string]$ErrorRecord.ErrorDetails.Message
    if (-not [string]::IsNullOrWhiteSpace($message) -and $message.Length -le 65536) {
        try {
            $body = ConvertFrom-Json -InputObject $message -ErrorAction Stop
            if ([string]$body.error.code -cmatch '^0x[0-9a-fA-F]{8}$') {
                $errorCode = ([string]$body.error.code).ToLowerInvariant()
            }
        } catch { }
    }
    [pscustomobject]@{
        StatusCode = $statusCode
        Headers = $headers
        ErrorCode = $errorCode
        ExceptionCategory = $exceptionCategory
    }
}

function New-SafeHttpFailure {
    param([string]$Method, [string]$Resource, [DateTimeOffset]$Timestamp,
        [Nullable[int]]$StatusCode, [object]$Response, [object]$Headers,
        [System.Management.Automation.ErrorRecord]$ErrorRecord,
        [bool]$DispatchStarted = $false, [bool]$WritesMayHaveOccurred = $script:WritesStarted,
        [string]$ExceptionCategoryOverride)
    $exceptionDetails = if ($ErrorRecord) { Get-HttpExceptionDetails -ErrorRecord $ErrorRecord } else { $null }
    if ($null -eq $StatusCode -and $exceptionDetails) { $StatusCode = $exceptionDetails.StatusCode }
    if ($null -eq $Headers -and $exceptionDetails) { $Headers = $exceptionDetails.Headers }
    $endpoint = switch -Regex ($Resource) {
        '^EntityDefinitions' { '/api/data/v9.2/EntityDefinitions'; break }
        '^PublishXml$' { '/api/data/v9.2/PublishXml'; break }
        '^WhoAmI$' { '/api/data/v9.2/WhoAmI'; break }
        '^organizations\(' { '/api/data/v9.2/organizations'; break }
        '^publishers$' { '/api/data/v9.2/publishers'; break }
        '^solutions$' { '/api/data/v9.2/solutions'; break }
        '^solutioncomponents$' { '/api/data/v9.2/solutioncomponents'; break }
        default { '/api/data/v9.2/[omitted]' }
    }
    $validStatus = if ($null -ne $StatusCode -and $StatusCode -ge 100 -and $StatusCode -le 599) { [int]$StatusCode } else { $null }
    $exceptionCategory = if ($ExceptionCategoryOverride -in @('HttpResponse','Timeout','Transport','Unknown')) {
        $ExceptionCategoryOverride
    } elseif ($exceptionDetails) { [string]$exceptionDetails.ExceptionCategory } else { 'None' }
    $failureClass = Get-RecoveryFailureClass -StatusCode $validStatus -ExceptionCategory $exceptionCategory
    $operation = if ($Method -eq 'POST') {
        if ($Resource -ceq 'PublishXml') { 'PublishTable' }
        elseif ($Resource -ceq 'EntityDefinitions') { 'CreateTable' }
        else { 'CreateAttribute' }
    } else { 'ReadMetadata' }
    $summary = switch ($failureClass) {
        'HTTP_401' { 'Authentication/token failure; unsafe response details omitted.' }
        'HTTP_403' { 'Authorization/privilege failure; unsafe response details omitted.' }
        'HTTP_4XX_VALIDATION' { 'Dataverse rejected the request; unsafe response details omitted.' }
        'HTTP_429' { 'Dataverse rate limited the request; no automatic retry.' }
        'HTTP_5XX' { 'Dataverse server failure; write outcome may be uncertain.' }
        'TIMEOUT' { 'Request timed out; write outcome may be uncertain.' }
        'TRANSPORT_FAILURE' { 'Transport failed; HTTP response unavailable.' }
        default { 'HTTP status unavailable or unexpected; write outcome may be uncertain.' }
    }
    $code = $null
    if ($null -ne $Response -and [string]$Response.error.code -cmatch '^0x[0-9a-fA-F]{8}$') { $code = ([string]$Response.error.code).ToLowerInvariant() }
    if (-not $code -and $exceptionDetails) { $code = $exceptionDetails.ErrorCode }
    $requestId = Get-SafeResponseHeader -Headers $Headers -Name 'x-ms-service-request-id'
    if (-not $requestId) { $requestId = Get-SafeResponseHeader -Headers $Headers -Name 'x-ms-request-id' }
    $correlationId = Get-SafeResponseHeader -Headers $Headers -Name 'x-ms-correlation-request-id'
    if (-not $correlationId) { $correlationId = Get-SafeResponseHeader -Headers $Headers -Name 'request-id' }
    [ordered]@{
        Operation = $operation
        Method = if ($Method -in @('GET','POST')) { $Method } else { 'UNKNOWN' }
        ApiPath = $endpoint
        TimestampUtc = $Timestamp.ToUniversalTime().ToString('o')
        StatusCode = $validStatus
        HttpStatus = if ($null -ne $validStatus) { $validStatus } else { 'UNKNOWN' }
        DataverseErrorCode = $code
        ErrorSummary = $summary
        RequestId = $requestId
        CorrelationId = $correlationId
        AuthenticationChallenge = Get-SafeAuthenticationChallenge -Headers $Headers
        FailureClass = $failureClass
        ExceptionCategory = $exceptionCategory
        TransportKind = if ($exceptionCategory -eq 'Timeout') { 'TIMEOUT' } elseif ($exceptionCategory -eq 'Transport') { 'TRANSPORT' } elseif ($null -ne $validStatus) { 'HTTP' } else { 'UNKNOWN' }
        DispatchStarted = [bool]$DispatchStarted
        WritesMayHaveOccurred = [bool]$WritesMayHaveOccurred
        ReconciliationCompleted = $false
        ReconciliationOutcome = 'UNKNOWN'
    }
}

function Get-StoppedDetails {
    $originalFailure = if ($null -ne $script:LastHttpFailure) { [ordered]@{} + $script:LastHttpFailure } else { $null }
    $reconciliation = [ordered]@{ Completed = $false; Outcome = 'UNKNOWN' }
    try {
        if ($CreateOnlyRecovery -and $null -ne $script:RecoveryReconciliation) {
            $reconciliation = $script:RecoveryReconciliation
        }
        elseif ($script:WritesStarted) { $reconciliation = Get-ReconciliationSummary }
    }
    catch { $reconciliation = [ordered]@{ Completed = $false; Outcome = 'UNKNOWN' } }
    finally { $script:LastHttpFailure = $originalFailure }
    if ($null -ne $originalFailure) {
        $originalFailure.WritesMayHaveOccurred = [bool]$script:WritesStarted
        $originalFailure.ReconciliationCompleted = $reconciliation.Completed
        $originalFailure.ReconciliationOutcome = $reconciliation.Outcome
    }
    $details = [ordered]@{
        Error = 'Operation stopped; raw exception details omitted. Do not retry automatically.'
        WritesMayHaveOccurred = [bool]$script:WritesStarted
        Reconciliation = $reconciliation
        RequestsAttempted = $script:RequestCounts
        WriteResults = $script:WriteResults.ToArray()
        HttpFailure = $originalFailure
    }
    if ($CreateOnlyRecovery) {
        $details.Recovery = [ordered]@{
            State = $script:RecoveryState
            StateTransitions = $script:RecoveryTransitions.ToArray()
            ResponseClass = $script:RecoveryResponseClass
            AttemptTimestampUtc = $script:RecoveryAttemptTimestampUtc
            EnvironmentVerified = $script:RecoveryEnvironmentVerified
            IdentityVerified = $script:RecoveryIdentityVerified
            VerifiedPrivileges = $script:RecoveryVerifiedPrivileges
            Preflight = $script:RecoveryPreflight
            ExpectedPayloadSha256 = $script:RecoveryExpectedFingerprint
            ActualPayloadSha256 = $script:RecoveryActualFingerprint
            Reconciliation = $reconciliation
            AuthorizationReferenceSupplied = -not [string]::IsNullOrWhiteSpace($AuthorizationReference)
        }
    }
    $details
}

function Assert-PacEnvironment {
    if ($EnvironmentName -cne 'VN LMV IT') { throw 'BSO_RS_ENVIRONMENT_NAME must be VN LMV IT; environment switching is prohibited.' }
    if ([string]::IsNullOrWhiteSpace($OrganizationUrl) -or
        [string]::IsNullOrWhiteSpace($ExpectedEnvironmentId) -or
        [string]::IsNullOrWhiteSpace($ExpectedOrganizationId)) {
        throw 'Set BSO_RS_ORG_URL, BSO_RS_EXPECTED_ENVIRONMENT_ID, and BSO_RS_EXPECTED_ORG_ID to operator-verified values.'
    }
    $organizationUri = [Uri]$OrganizationUrl
    if ($organizationUri.Scheme -cne 'https' -or $organizationUri.AbsolutePath -ne '/' -or
        -not [string]::IsNullOrEmpty($organizationUri.Query) -or -not [string]::IsNullOrEmpty($organizationUri.Fragment)) {
        throw 'Organization URL must be an HTTPS origin without a path, query, or fragment.'
    }
    foreach ($value in @($ExpectedEnvironmentId, $ExpectedOrganizationId)) {
        $parsed = [Guid]::Empty
        if (-not [Guid]::TryParse($value, [ref]$parsed)) { throw 'Expected environment/organization IDs must be GUIDs.' }
    }

    # PAC is used only for identity verification. Its token cache is never read.
    $pacOutput = @(& pac env who 2>&1 | ForEach-Object { [string]$_ })
    if ($LASTEXITCODE -ne 0) { throw 'pac env who failed; stop before Web API requests.' }
    $pacText = $pacOutput -join "`n"
    $name = [regex]::Match($pacText, '(?m)^\s*Friendly Name:\s*(.+?)\s*$')
    $url = [regex]::Match($pacText, '(?m)^\s*Org URL:\s*(\S+)')
    $orgId = [regex]::Match($pacText, '(?m)^\s*Org ID:\s*([0-9a-fA-F-]{36})')
    $envId = [regex]::Match($pacText, '(?m)^\s*Environment ID:\s*([0-9a-fA-F-]{36})')
    $userId = [regex]::Match($pacText, '(?m)^\s*User ID:\s*([0-9a-fA-F-]{36})')
    $userEmail = [regex]::Match($pacText, '(?m)^\s*User Email:\s*(\S+)')
    if (-not $name.Success -or -not $url.Success -or -not $orgId.Success -or -not $envId.Success -or -not $userId.Success -or -not $userEmail.Success) {
        throw 'Could not parse PAC identity response; stop without switching environments.'
    }
    if ($name.Groups[1].Value -cne 'VN LMV IT' -or
        $url.Groups[1].Value.TrimEnd('/') -cne $OrganizationUrl.TrimEnd('/') -or
        $orgId.Groups[1].Value -cne $ExpectedOrganizationId -or
        $envId.Groups[1].Value -cne $ExpectedEnvironmentId) {
        throw 'PAC active environment does not match the configured VN LMV IT target; stop without switching.'
    }
    if ($CreateOnlyRecovery) {
        Assert-ExpectedRecoveryUser -ActualUserId $userId.Groups[1].Value
        $script:RecoveryEnvironmentVerified = $true
    }
    $script:PacUserId = $userId.Groups[1].Value
    $script:PacUserEmail = $userEmail.Groups[1].Value
    $script:ApiRoot = $OrganizationUrl.TrimEnd('/') + '/api/data/v9.2/'
}

function New-PrivatePipeline {
    [System.Management.Automation.PowerShell]::Create()
}

function Invoke-PrivateOperation {
    param([scriptblock]$Action, [object[]]$Arguments)
    $pipeline = New-PrivatePipeline
    try {
        $null = $pipeline.AddScript({
            param($operation, $parameters)
            try { & ([scriptblock]::Create($operation)) @parameters }
            catch {
                $record = $_
                $exception = $record.Exception
                $responseStatus = $null
                $category = 'Unknown'
                for ($depth = 0; $null -ne $exception -and $depth -lt 8; $depth++) {
                    try {
                        $candidate = [int]$exception.Response.StatusCode
                        if ($candidate -ge 100 -and $candidate -le 599) { $responseStatus = $candidate }
                    } catch { }
                    if ($null -eq $responseStatus) {
                        try {
                            $candidate = [int]$exception.StatusCode
                            if ($candidate -ge 100 -and $candidate -le 599) { $responseStatus = $candidate }
                        } catch { }
                    }
                    if ($null -ne $responseStatus) { $category = 'HttpResponse'; break }
                    if ($exception -is [System.TimeoutException] -or
                        $exception -is [System.Threading.Tasks.TaskCanceledException] -or
                        ($exception -is [System.Net.WebException] -and $exception.Status -eq [System.Net.WebExceptionStatus]::Timeout)) {
                        $category = 'Timeout'
                        break
                    }
                    if ($exception -is [System.Net.Http.HttpRequestException] -or
                        $exception -is [System.Net.WebException] -or
                        $exception -is [System.IO.IOException]) {
                        $category = 'Transport'
                        break
                    }
                    $exception = $exception.InnerException
                }
                [pscustomobject]@{ Succeeded = $false; ErrorRecord = $record; StatusCode = $responseStatus; ExceptionCategory = $category }
            }
        }).AddArgument($Action.ToString()).AddArgument($Arguments)
        $records = @($pipeline.Invoke())
        if ($records.Count -ne 1) {
            $pipelineError = if ($pipeline.Streams.Error.Count) { $pipeline.Streams.Error[0] } else { $null }
            return [pscustomobject]@{ Succeeded = $false; ErrorRecord = $pipelineError }
        }
        $records[0]
    }
    finally { $pipeline.Dispose() }
}

function Get-ValidatedAccessToken {
    if ($PSVersionTable.PSVersion -lt [Version]'7.4') {
        throw 'Online mode requires PowerShell 7.4 or later per the Microsoft Dataverse PowerShell quickstart. -PlanOnly remains available in Windows PowerShell 5.1.'
    }
    $azAccounts = @(Get-Module -ListAvailable -Name Az.Accounts | Sort-Object Version -Descending)
    if ($azAccounts.Count -eq 0) {
        throw 'Online mode requires Az.Accounts with Get-AzAccessToken -ResourceUrl -AsSecureString. The quickstart Az 11.1.0 minimum refers to the umbrella module, not Az.Accounts.'
    }
    Import-Module Az.Accounts -ErrorAction Stop
    $tokenCommand = Get-Command Az.Accounts\Get-AzAccessToken -ErrorAction Stop
    if (-not $tokenCommand.Parameters.ContainsKey('ResourceUrl') -or
        -not $tokenCommand.Parameters.ContainsKey('AsSecureString')) {
        throw 'Installed Az.Accounts must support Get-AzAccessToken -ResourceUrl -AsSecureString.'
    }
    $authorizedTenants = @(Get-AzTenant -ErrorAction SilentlyContinue)
    if ($authorizedTenants.Count -eq 0) {
        if ($CreateOnlyRecovery) { throw 'No existing Az user context is available; recovery will not trigger interactive sign-in.' }
        Connect-AzAccount -ErrorAction Stop | Out-Null
    }
    $context = Get-AzContext -ErrorAction Stop
    if ($null -eq $context -or $context.Account.Type -ne 'User' -or $context.Account.Id -ine $script:PacUserEmail) {
        throw 'Az user context must match the verified PAC user; no context switching will be attempted.'
    }

    $secureToken = $null
    $tokenText = $null
    $tokenResult = $null
    $claims = $null
    try {
        $tokenResult = Get-AzAccessToken -ResourceUrl $OrganizationUrl -AsSecureString -ErrorAction Stop
        $secureToken = $tokenResult.Token
        if ($secureToken -isnot [Security.SecureString]) {
            throw 'Get-AzAccessToken did not return a SecureString. Verify Az.Accounts version and -AsSecureString support.'
        }
        $tokenText = ConvertFrom-SecureString -SecureString $secureToken -AsPlainText
        $parts = $tokenText.Split('.')
        if ($parts.Count -ne 3) { throw 'Dataverse access token is not a JWT; stop without an API request.' }
        $encodedPayload = $parts[1].Replace('-', '+').Replace('_', '/')
        switch ($encodedPayload.Length % 4) { 2 { $encodedPayload += '==' } 3 { $encodedPayload += '=' } }
        $claims = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encodedPayload)) | ConvertFrom-Json
        $context = Get-AzContext -ErrorAction Stop
        $audience = [Uri]([string]$claims.aud)
        $organization = [Uri]$OrganizationUrl
        $scopes = @(([string]$claims.scp) -split '\s+')
        $issuedAt = [DateTimeOffset]::FromUnixTimeSeconds([long]$claims.iat)
        $expiresAt = [DateTimeOffset]::FromUnixTimeSeconds([long]$claims.exp)
        if ($claims.tid -cne $context.Tenant.Id -or $audience.Authority -ine $organization.Authority -or
            'user_impersonation' -notin $scopes -or $expiresAt -le [DateTimeOffset]::UtcNow -or
            [math]::Abs(($expiresAt - [DateTimeOffset]$tokenResult.ExpiresOn).TotalMinutes) -gt 2) {
            throw 'Dataverse token tenant, audience, delegated scope, or expiry validation failed; no API request sent.'
        }
        $script:AccessToken = $tokenText
        $script:AccessTokenIssuedAt = $issuedAt
        $script:AccessTokenExpiresOn = [DateTimeOffset]$tokenResult.ExpiresOn
    }
    finally {
        $tokenText = $null
        $encodedPayload = $null
        $parts = $null
        $claims = $null
        $secureToken = $null
        $tokenResult = $null
    }
}

function Get-InteractiveAccessToken {
    $material = $null
    try {
        $material = Invoke-PrivateOperation -Arguments @(${function:Get-ValidatedAccessToken}.ToString(), $OrganizationUrl, $script:PacUserEmail) -Action {
            param($definition, $organizationUrl, $pacUserEmail)
            $OrganizationUrl = $organizationUrl
            $script:PacUserEmail = $pacUserEmail
            . ([scriptblock]::Create($definition)) *> $null
            [pscustomobject]@{
                Succeeded = $true
                Token = $script:AccessToken
                IssuedAt = $script:AccessTokenIssuedAt
                ExpiresOn = $script:AccessTokenExpiresOn
            }
        }
        if (-not $material.Succeeded) { throw 'Dataverse authentication failed; raw authentication details omitted. Review sign-in policy with the administrator.' }
        $script:AccessToken = $material.Token
        $script:AccessTokenIssuedAt = $material.IssuedAt
        $script:AccessTokenExpiresOn = $material.ExpiresOn
    }
    finally { $material = $null }
}

function Ensure-DataverseAccessToken {
    param([scriptblock]$RefreshAction = { Get-InteractiveAccessToken })
    $refreshBefore = [DateTimeOffset]::UtcNow.AddMinutes(5)
    if ([string]::IsNullOrWhiteSpace($script:AccessToken) -or $script:AccessTokenExpiresOn -le $refreshBefore) {
        & $RefreshAction
    }
    if ([string]::IsNullOrWhiteSpace($script:AccessToken) -or $script:AccessTokenExpiresOn -le [DateTimeOffset]::UtcNow) {
        throw 'A valid Dataverse token is unavailable; no Web API request was sent.'
    }
}

function Invoke-DataverseRequest {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('GET', 'POST')][string]$Method,
        [Parameter(Mandatory = $true)][string]$Path,
        [object]$Body,
        [switch]$WithSolutionHeader
    )
    if ($Method -eq 'POST') {
        if ($CreateOnlyRecovery) {
            if (-not $script:WritesAllowed -or $Apply -or $PlanOnly -or $TableName -cne 'os_sr_pos' -or
                $Path -cne 'EntityDefinitions' -or $Body.SchemaName -cne 'os_sr_pos' -or
                -not $WithSolutionHeader -or $script:RecoveryState -cne 'READY' -or
                $script:RequestCounts.POST -ne 0 -or
                $script:RecoveryActualFingerprint -cne $script:RecoveryExpectedFingerprint -or
                (Get-PayloadFingerprint -Payload $Body) -cne $script:RecoveryExpectedFingerprint) {
                throw 'Create-only recovery POST blocked by its one-write guard.'
            }
        }
        else {
            if (-not $Apply -or $PlanOnly -or -not $script:WritesAllowed) { throw 'POST blocked: confirmed Apply is required.' }
            $attributePath = "EntityDefinitions(LogicalName='$TableName')/Attributes"
            if ($Path -notin @('EntityDefinitions', $attributePath, 'PublishXml')) { throw 'Unapproved write path.' }
            if ($Path -eq 'EntityDefinitions' -and $Body.SchemaName -cne $TableName) { throw 'Unapproved table payload.' }
            if ($Path -eq $attributePath -and $Body.SchemaName -notin @($script:Definition.Columns | ForEach-Object { $_.SchemaName })) { throw 'Unapproved column payload.' }
            if ($Path -ne 'PublishXml' -and -not $WithSolutionHeader) { throw 'Metadata creation requires the project Solution header.' }
            if ($Path -eq 'PublishXml' -and $Body.ParameterXml -cne "<importexportxml><entities><entity>$TableName</entity></entities></importexportxml>") { throw 'Unapproved publish scope.' }
        }
    }
    Ensure-DataverseAccessToken
    $headers = @{
        Authorization = 'Bearer ' + $script:AccessToken
        Accept = 'application/json'
        'OData-MaxVersion' = '4.0'
        'OData-Version' = '4.0'
        'If-None-Match' = 'null'
    }
    if ($WithSolutionHeader) { $headers['MSCRM.SolutionUniqueName'] = 'os_sr_bso_rs_support' }
    $requestUri = if ([Uri]::IsWellFormedUriString($Path, [UriKind]::Absolute)) { $Path } else { $script:ApiRoot + $Path }
    $parsedRequestUri = [Uri]$requestUri
    $organizationUri = [Uri]$OrganizationUrl
    if ($parsedRequestUri.Scheme -cne 'https' -or $parsedRequestUri.Authority -ine $organizationUri.Authority -or
        $parsedRequestUri.AbsolutePath -notmatch '^/api/data/v9\.2/' -or $parsedRequestUri.UserInfo -or $parsedRequestUri.Fragment) {
        throw 'Dataverse request URL is outside the verified organization API origin.'
    }
    $resource = $parsedRequestUri.AbsolutePath.Substring('/api/data/v9.2/'.Length)
    if ($Method -eq 'GET' -and $resource -notmatch '^(WhoAmI$|organizations\(|publishers$|solutions$|solutioncomponents$|systemusers\([0-9a-fA-F-]{36}\)/Microsoft\.Dynamics\.CRM\.RetrieveUserSetOfPrivilegesByNames\(PrivilegeNames=@p\)$|EntityDefinitions($|\(|/))') {
        throw 'GET blocked: only identity, configuration, and schema metadata reads are allowed.'
    }
    $request = @{
        Method = $Method
        Uri = $requestUri
        Headers = $headers
        SkipHeaderValidation = $true
        MaximumRedirection = 0
        SkipHttpErrorCheck = $true
        StatusCodeVariable = 'responseStatusCode'
        ResponseHeadersVariable = 'responseHeaders'
        TimeoutSec = 120
        ErrorAction = 'Stop'
    }
    if ($CreateOnlyRecovery) { $request.MaximumRetryCount = 0 }
    if ($PSBoundParameters.ContainsKey('Body')) {
        $request.ContentType = 'application/json; charset=utf-8'
        $request.Body = ConvertTo-Json -InputObject $Body -Depth 40 -Compress
    }
    $requestStartedUtc = [DateTimeOffset]::UtcNow
    $responseStatusCode = 0
    $responseHeaders = $null
    $script:LastRequestDispatchStarted = $false
    if ($Method -eq 'POST') {
        if ($CreateOnlyRecovery) {
            if (-not $script:WritesAllowed -or $Apply -or $PlanOnly -or $TableName -cne 'os_sr_pos' -or
                $Path -cne 'EntityDefinitions' -or $Body.SchemaName -cne 'os_sr_pos' -or
                -not $WithSolutionHeader -or $script:RecoveryState -cne 'READY' -or
                $script:RequestCounts.POST -ne 0 -or
                $script:RecoveryActualFingerprint -cne $script:RecoveryExpectedFingerprint -or
                (Get-PayloadFingerprint -Payload $Body) -cne $script:RecoveryExpectedFingerprint) {
                throw 'Create-only recovery POST blocked by its one-write guard.'
            }
            Set-RecoveryState -State 'WRITE_ATTEMPTED'
        }
        elseif (-not $Apply -or $PlanOnly -or -not $script:WritesAllowed) {
            throw 'POST blocked: confirmed Apply is required.'
        }
        $script:WritesStarted = $true
        if ($CreateOnlyRecovery) { $script:RecoveryAttemptTimestampUtc = $requestStartedUtc.ToString('o') }
    }
    $script:RequestCounts[$Method]++
    $script:LastRequestDispatchStarted = $true
    $transport = Invoke-PrivateOperation -Arguments @($request) -Action {
        param($parameters)
        $response = Invoke-RestMethod @parameters -Verbose:$false -Debug:$false -WarningAction SilentlyContinue -InformationAction SilentlyContinue 2>$null 3>$null 4>$null 5>$null 6>$null
        [pscustomobject]@{ Succeeded = $true; Response = $response; Status = $responseStatusCode; Headers = $responseHeaders }
    }
    if (-not $transport.Succeeded) {
        $script:LastHttpFailure = New-SafeHttpFailure -Method $Method -Resource $resource -Timestamp $requestStartedUtc `
            -StatusCode $transport.StatusCode -ErrorRecord $transport.ErrorRecord -ExceptionCategoryOverride $transport.ExceptionCategory `
            -DispatchStarted $script:LastRequestDispatchStarted `
            -WritesMayHaveOccurred:$script:WritesStarted
        if ($CreateOnlyRecovery -and $Method -eq 'POST') {
            $script:RecoveryRequestId = $script:LastHttpFailure.RequestId
            $script:RecoveryCorrelationId = $script:LastHttpFailure.CorrelationId
        }
        throw 'Dataverse transport failed; raw exception details omitted. Reconcile before recovery.'
    }
    $response = $transport.Response
    $responseHeaders = $transport.Headers
    $statusCode = [int]$transport.Status
    if ($CreateOnlyRecovery -and $Method -eq 'POST') {
        $script:RecoveryRequestId = Get-SafeResponseHeader -Headers $responseHeaders -Name 'x-ms-service-request-id'
        if (-not $script:RecoveryRequestId) { $script:RecoveryRequestId = Get-SafeResponseHeader -Headers $responseHeaders -Name 'x-ms-request-id' }
        $script:RecoveryCorrelationId = Get-SafeResponseHeader -Headers $responseHeaders -Name 'x-ms-correlation-request-id'
        if (-not $script:RecoveryCorrelationId) { $script:RecoveryCorrelationId = Get-SafeResponseHeader -Headers $responseHeaders -Name 'request-id' }
    }
    if ($Method -eq 'POST') {
        $script:WriteResults.Add([ordered]@{ Method = $Method; Path = $Path; StatusCode = $statusCode })
    }
    if ($statusCode -lt 200 -or $statusCode -ge 300) {
        $script:LastHttpFailure = New-SafeHttpFailure -Method $Method -Resource $resource -Timestamp $requestStartedUtc `
            -StatusCode $statusCode -Response $response -Headers $responseHeaders -DispatchStarted $script:LastRequestDispatchStarted `
            -WritesMayHaveOccurred:$script:WritesStarted
        if ($CreateOnlyRecovery -and $Method -eq 'POST') {
            $script:RecoveryRequestId = $script:LastHttpFailure.RequestId
            $script:RecoveryCorrelationId = $script:LastHttpFailure.CorrelationId
        }
        throw "Dataverse HTTP $statusCode; raw response details omitted. Review the safe diagnostic."
    }
    $response
}

function Get-ODataList {
    param([Parameter(Mandatory = $true)][string]$Path)
    $items = [System.Collections.Generic.List[object]]::new()
    $nextPath = $Path
    $seenLinks = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    while ($nextPath) {
        $response = Invoke-DataverseRequest -Method GET -Path $nextPath
        if ($null -ne $response.value) {
            foreach ($item in $response.value) { $items.Add($item) }
        }
        $nextPath = [string]$response.'@odata.nextLink'
        if ($nextPath -and -not $seenLinks.Add($nextPath)) { throw 'Repeated OData next link detected; stop inventory read.' }
    }
    return $items.ToArray()
}

function Get-EntityMetadata {
    param([string]$LogicalName = $TableName)
    if ($LogicalName -notin $script:Definitions.Keys) { throw 'Undeclared reference table.' }
    $basePath = "EntityDefinitions(LogicalName='$LogicalName')"
    $common = 'LogicalName,SchemaName,MetadataId,DisplayName,AttributeType,AttributeTypeName,IsPrimaryName,IsPrimaryId,RequiredLevel,IsCustomAttribute,IsAuditEnabled'
    $path = "$basePath`?`$select=LogicalName,SchemaName,MetadataId,OwnershipType,PrimaryIdAttribute,PrimaryNameAttribute,DisplayName,DisplayCollectionName,IsAuditEnabled,IsDuplicateDetectionEnabled&`$expand=Attributes(`$select=$common),ManyToOneRelationships(`$select=SchemaName,IsCustomRelationship),OneToManyRelationships(`$select=SchemaName,IsCustomRelationship),ManyToManyRelationships(`$select=SchemaName,IsCustomRelationship)"
    $metadata = Invoke-DataverseRequest -Method GET -Path $path
    $stringAttributes = @(Get-ODataList -Path "$basePath/Attributes/Microsoft.Dynamics.CRM.StringAttributeMetadata?`$select=$common,MaxLength,FormatName")
    $metadata.Attributes = @($metadata.Attributes | Where-Object { $_.AttributeType -cne 'String' }) + $stringAttributes
    if (@($metadata.Attributes | Where-Object { $_.AttributeType -ceq 'Memo' }).Count) {
        $memoAttributes = @(Get-ODataList -Path "$basePath/Attributes/Microsoft.Dynamics.CRM.MemoAttributeMetadata?`$select=$common,MaxLength,Format")
        $metadata.Attributes = @($metadata.Attributes | Where-Object { $_.AttributeType -cne 'Memo' }) + $memoAttributes
    }
    $metadata.Attributes = @($metadata.Attributes | Sort-Object LogicalName)
    $metadata | Add-Member -NotePropertyName Keys -NotePropertyValue @(Get-ODataList -Path "$basePath/Keys?`$select=LogicalName,KeyAttributes")
    $metadata
}

function Get-TableMetadataIfPresent {
    $filter = [Uri]::EscapeDataString("LogicalName eq '$TableName'")
    $tableMatches = @(Get-ODataList -Path "EntityDefinitions?`$select=LogicalName,MetadataId&`$filter=$filter")
    if ($tableMatches.Count -eq 0) { return $null }
    if ($tableMatches.Count -ne 1) { throw 'Multiple target table definitions found.' }
    Get-EntityMetadata
}

function Get-ProjectEntityNames {
    $path = "EntityDefinitions?`$select=LogicalName"
    @(Get-ODataList -Path $path | Where-Object { $_.LogicalName -like 'os_sr_*' } | ForEach-Object { $_.LogicalName })
}

function Get-SolutionMembership {
    param([string]$SolutionId, [string]$ObjectId, [int]$ComponentType)
    $filter = [Uri]::EscapeDataString("_solutionid_value eq $SolutionId and objectid eq $ObjectId and componenttype eq $ComponentType")
    @(Get-ODataList -Path "solutioncomponents?`$select=solutioncomponentid,componenttype,objectid,_solutionid_value,rootcomponentbehavior&`$filter=$filter")
}

function Get-SolutionSchemaComponents {
    param([Parameter(Mandatory = $true)][string]$SolutionId)
    $filter = [Uri]::EscapeDataString("_solutionid_value eq $SolutionId")
    @(Get-ODataList -Path "solutioncomponents?`$select=objectid,componenttype,rootcomponentbehavior&`$filter=$filter")
}

function Assert-SolutionMembership {
    param([Parameter(Mandatory = $true)][string]$SolutionId, [Parameter(Mandatory = $true)][object]$Metadata,
        [System.Collections.IDictionary]$Definition = $script:Definitions[$Metadata.LogicalName])
    if ($null -eq $Definition) { throw 'Missing declared schema for Solution verification.' }
    $entityMembership = @(Get-SolutionMembership -SolutionId $SolutionId -ObjectId $Metadata.MetadataId -ComponentType 1)
    if ($entityMembership.Count -ne 1) { throw 'Table Solution membership verification failed.' }
    if ($null -ne $entityMembership[0].rootcomponentbehavior -and $entityMembership[0].rootcomponentbehavior -eq 0) { return }
    foreach ($columnName in @($Definition.PrimaryName.SchemaName) + @($Definition.Columns | ForEach-Object { $_.SchemaName })) {
        $column = @($Metadata.Attributes | Where-Object { $_.LogicalName -ceq $columnName })
        if ($column.Count -ne 1) { throw 'Column metadata missing during Solution verification.' }
        $membership = @(Get-SolutionMembership -SolutionId $SolutionId -ObjectId $column[0].MetadataId -ComponentType 2)
        if ($membership.Count -ne 1) { throw "Solution does not include subcomponents or explicit column $columnName." }
    }
}

function Assert-RecoveryPrivileges {
    $requiredPrivileges = @('prvCreateEntity', 'prvCreateAttribute', 'prvCreateCustomization')
    $names = ConvertTo-Json -InputObject $requiredPrivileges -Compress
    $path = "systemusers($($script:PacUserId))/Microsoft.Dynamics.CRM.RetrieveUserSetOfPrivilegesByNames(PrivilegeNames=@p)?@p=$names"
    $result = Invoke-DataverseRequest -Method GET -Path $path
    Assert-RequiredPrivilegeSet -Privileges @($result.RolePrivileges) -RequiredNames $requiredPrivileges
    $requiredPrivileges
}

function Get-AuditState {
    $org = Invoke-DataverseRequest -Method GET -Path "organizations($ExpectedOrganizationId)?`$select=organizationid,isauditenabled,auditretentionperiod,isuseraccessauditenabled"
    if ($org.organizationid -ne $ExpectedOrganizationId) { throw 'Organization ID mismatch during audit-state read.' }
    [ordered]@{
        OrganizationId = [string]$org.organizationid
        AuditingEnabled = [bool]$org.isauditenabled
        RetentionDays = [string]$org.auditretentionperiod
        UserAccessAuditingEnabled = [bool]$org.isuseraccessauditenabled
    }
}

function Get-Preflight {
    Assert-PacEnvironment
    Get-InteractiveAccessToken
    $who = Invoke-DataverseRequest -Method GET -Path 'WhoAmI'
    if ($who.OrganizationId -ne $ExpectedOrganizationId -or $who.UserId -ne $script:PacUserId) { throw 'WhoAmI organization/user mismatch; stop without writes.' }
    if ($CreateOnlyRecovery) { $script:RecoveryIdentityVerified = $true }
    $org = Invoke-DataverseRequest -Method GET -Path "organizations($ExpectedOrganizationId)?`$select=organizationid"
    if ($org.organizationid -ne $ExpectedOrganizationId) { throw 'Organization metadata mismatch; stop without writes.' }

    $publisherFilter = [Uri]::EscapeDataString("uniquename eq 'os_bso_rs_support'")
    $publishers = @(Get-ODataList -Path "publishers?`$select=publisherid,friendlyname,uniquename,customizationprefix&`$filter=$publisherFilter")
    if ($publishers.Count -ne 1 -or $publishers[0].friendlyname -cne 'BSO-RS-Support Publisher' -or
        $publishers[0].customizationprefix -cne 'os') { throw 'Project Publisher mismatch; stop without writes.' }
    $solutionFilter = [Uri]::EscapeDataString("uniquename eq 'os_sr_bso_rs_support'")
    $solutions = @(Get-ODataList -Path "solutions?`$select=solutionid,friendlyname,uniquename,version,ismanaged,_publisherid_value&`$filter=$solutionFilter")
    if ($solutions.Count -ne 1 -or $solutions[0].friendlyname -cne 'BSO-RS-Support' -or
        $solutions[0].version -cne '1.0.0.0' -or $solutions[0].ismanaged -ne $false -or
        $solutions[0]._publisherid_value -ne $publishers[0].publisherid) { throw 'Project Solution/Publisher linkage mismatch; stop without writes.' }

    $projectTables = @(Get-ProjectEntityNames)
    if (@($projectTables | Where-Object { $_ -notin $script:Definitions.Keys }).Count) { throw 'Unexpected project table exists; stop for reconciliation.' }
    $snapshots = @{}
    $existingTableIds = [System.Collections.Generic.List[string]]::new()
    foreach ($existingName in $projectTables) {
        $existing = Get-EntityMetadata -LogicalName $existingName
        Assert-TableMetadata -Metadata $existing -Definition $script:Definitions[$existingName]
        Assert-SolutionMembership -SolutionId $solutions[0].solutionid -Metadata $existing
        $snapshots[$existingName] = $existing | ConvertTo-Json -Depth 40 -Compress
        $existingTableIds.Add([string]$existing.MetadataId)
        foreach ($attribute in @($existing.Attributes)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$attribute.MetadataId)) {
                $existingTableIds.Add([string]$attribute.MetadataId)
            }
        }
    }
    if ($CreateOnlyRecovery) {
        $solutionComponents = @(Get-SolutionSchemaComponents -SolutionId $solutions[0].solutionid)
        Assert-RecoveryInventory -ProjectTables $projectTables -SolutionComponents $solutionComponents -ExistingTableIds $existingTableIds.ToArray()
        if ($TableName -in $projectTables) { throw 'Position already exists; recovery will not update, delete, or recreate it.' }
    }
    elseif ($Apply -and $TableName -in $projectTables) { throw 'Target already exists; Apply will not update, delete, or recreate it.' }
    $verifiedPrivileges = if ($CreateOnlyRecovery) { @(Assert-RecoveryPrivileges) } else { @() }
    if ($CreateOnlyRecovery) { $script:RecoveryVerifiedPrivileges = $verifiedPrivileges }
    $audit = Get-AuditState
    if ($audit.AuditingEnabled -ne $false -or $audit.UserAccessAuditingEnabled -ne $false) {
        throw 'Audit state differs from the documented baseline; this script will not modify audit settings.'
    }
    [pscustomobject]@{
        OrganizationId = [string]$org.organizationid
        PublisherId = [string]$publishers[0].publisherid
        PublisherPrefix = [string]$publishers[0].customizationprefix
        SolutionId = [string]$solutions[0].solutionid
        SolutionUniqueName = [string]$solutions[0].uniquename
        Audit = $audit
        ProjectTables = $projectTables
        ExistingSnapshots = $snapshots
        TargetExists = ($TableName -in $projectTables)
        VerifiedPrivileges = $verifiedPrivileges
    }
}

function Assert-TableMetadata {
    param([Parameter(Mandatory = $true)][object]$Metadata,
        [System.Collections.IDictionary]$Definition = $script:Definitions[$Metadata.LogicalName])
    if ($null -eq $Definition) { throw 'Missing declared reference schema.' }
    $logicalName = $Metadata.LogicalName
    if ($logicalName -notin $script:Definitions.Keys -or $Metadata.SchemaName -cne $logicalName -or
        $Metadata.OwnershipType -cne 'OrganizationOwned' -or $Metadata.PrimaryNameAttribute -cne $Definition.PrimaryName.SchemaName -or
        $Metadata.PrimaryIdAttribute -cne ($logicalName + 'id') -or
        $Metadata.DisplayName.UserLocalizedLabel.Label -cne $Definition.DisplayName -or
        $Metadata.DisplayCollectionName.UserLocalizedLabel.Label -cne $Definition.DisplayCollectionName) {
        throw 'Table schema, display labels, ownership, primary-name, or primary-GUID validation failed.'
    }
    $attrs = @($Metadata.Attributes)
    foreach ($column in @($Definition.PrimaryName) + @($Definition.Columns)) {
        $actual = @($attrs | Where-Object { $_.LogicalName -ceq $column.SchemaName })
        if ($actual.Count -ne 1) { throw "Missing declared column $($column.SchemaName)." }
        $format = if ($column.AttributeType -ceq 'Memo') { $actual[0].Format } else { $actual[0].FormatName.Value }
        if ($actual[0].SchemaName -cne $column.SchemaName -or $actual[0].DisplayName.UserLocalizedLabel.Label -cne $column.DisplayName -or
            $actual[0].AttributeType -cne $column.AttributeType -or $actual[0].AttributeTypeName.Value -cne "$($column.AttributeType)Type" -or
            $actual[0].MaxLength -ne $column.MaxLength -or $format -cne $column.FormatName -or
            $actual[0].RequiredLevel.Value -cne $column.RequiredLevel -or $actual[0].IsPrimaryName -ne [bool]$column.IsPrimaryName) {
            throw "Column metadata mismatch: $($column.SchemaName)."
        }
    }
    foreach ($sys in @('statecode','statuscode')) {
        if (@($attrs | Where-Object { $_.LogicalName -ceq $sys }).Count -ne 1) { throw "System field $sys missing." }
    }
    $custom = @($attrs | Where-Object { $_.IsCustomAttribute -eq $true } | ForEach-Object { $_.LogicalName })
    $expected = @($Definition.PrimaryName.SchemaName) + @($Definition.Columns | ForEach-Object { $_.SchemaName })
    $primaryId = @($attrs | Where-Object { $_.LogicalName -ceq ($logicalName + 'id') })
    if ($primaryId.Count -ne 1 -or $primaryId[0].AttributeType -cne 'Uniqueidentifier' -or $primaryId[0].IsPrimaryId -ne $true) {
        throw 'Primary GUID attribute metadata mismatch.'
    }
    if (@($custom | Where-Object { $_ -notin ($expected + @($logicalName + 'id')) }).Count -gt 0 -or @($expected | Where-Object { $_ -notin $custom }).Count -gt 0) {
        throw 'Unexpected or missing custom column metadata.'
    }
    if ($Metadata.IsAuditEnabled.Value -ne $false -or $Metadata.IsDuplicateDetectionEnabled.Value -ne $false) {
        throw 'Audit or duplicate-detection option is enabled unexpectedly.'
    }
    if ($null -eq $Metadata.Keys -or @($Metadata.Keys).Count -ne 0) {
        throw 'Alternate key exists unexpectedly.'
    }
    foreach ($navigation in @('ManyToOneRelationships', 'OneToManyRelationships', 'ManyToManyRelationships')) {
        if ($null -eq $Metadata.$navigation -or @($Metadata.$navigation | Where-Object { $_.IsCustomRelationship -eq $true }).Count) {
            throw 'Custom relationship exists or relationship inventory is incomplete.'
        }
    }
}

function Assert-UnchangedState {
    param([Parameter(Mandatory = $true)][object]$Preflight, [switch]$Created)
    $auditAfter = Get-AuditState
    if (($auditAfter | ConvertTo-Json -Compress) -cne ($Preflight.Audit | ConvertTo-Json -Compress)) { throw 'Environment audit settings changed during execution.' }
    $after = @(Get-ProjectEntityNames | Sort-Object)
    $expected = @($Preflight.ProjectTables)
    if ($Created) { $expected += $TableName }
    if (($after -join ',') -cne ((@($expected | Sort-Object)) -join ',')) { throw 'Project table inventory changed unexpectedly.' }
    foreach ($existingName in $Preflight.ExistingSnapshots.Keys) {
        $snapshot = Get-EntityMetadata -LogicalName $existingName | ConvertTo-Json -Depth 40 -Compress
        if ($snapshot -cne $Preflight.ExistingSnapshots[$existingName]) { throw "Existing table metadata changed: $existingName." }
    }
}

function Get-ReconciliationSummary {
    try {
        $table = Get-TableMetadataIfPresent
        if (-not $table) { return [ordered]@{ Completed = $true; Outcome = 'ABSENT' } }
        try {
            Assert-TableMetadata -Metadata $table
            Assert-SolutionMembership -SolutionId $script:ReconciliationSolutionId -Metadata $table
        }
        catch { return [ordered]@{ Completed = $true; Outcome = 'PARTIAL' } }
        return [ordered]@{ Completed = $true; Outcome = 'PRESENT' }
    }
    catch { return [ordered]@{ Completed = $false; Outcome = 'UNKNOWN' } }
}

function Invoke-PositionCreateOnlyRecovery {
    param(
        [Parameter(Mandatory = $true)][object]$Payload,
        [Parameter(Mandatory = $true)][string]$SolutionId
    )
    $script:ReconciliationSolutionId = $SolutionId
    $statusCode = 0
    try {
        $null = Invoke-DataverseRequest -Method POST -Path 'EntityDefinitions' -Body $Payload -WithSolutionHeader
        $statusCode = [int]$script:WriteResults[$script:WriteResults.Count - 1].StatusCode
        $script:RecoveryResponseClass = 'SUCCESS_RESPONSE'
    }
    catch {
        if ($null -eq $script:LastHttpFailure) {
            $script:LastHttpFailure = New-SafeHttpFailure -Method POST -Resource 'EntityDefinitions' `
                -Timestamp ([DateTimeOffset]::UtcNow) -StatusCode $null -ErrorRecord $_ `
                -DispatchStarted $script:LastRequestDispatchStarted -WritesMayHaveOccurred:$script:WritesStarted
        }
        if ($null -ne $script:LastHttpFailure.StatusCode) { $statusCode = [int]$script:LastHttpFailure.StatusCode }
        $script:RecoveryResponseClass = [string]$script:LastHttpFailure.FailureClass
    }

    Set-RecoveryState -State 'RECONCILING'
    $originalFailure = if ($null -ne $script:LastHttpFailure) { [ordered]@{} + $script:LastHttpFailure } else { $null }
    try { $script:RecoveryReconciliation = Get-ReconciliationSummary }
    finally { $script:LastHttpFailure = $originalFailure }
    if ($null -ne $originalFailure) {
        $originalFailure.WritesMayHaveOccurred = [bool]$script:WritesStarted
        $originalFailure.ReconciliationCompleted = $script:RecoveryReconciliation.Completed
        $originalFailure.ReconciliationOutcome = $script:RecoveryReconciliation.Outcome
    }
    $terminalState = switch ($script:RecoveryReconciliation.Outcome) {
        'PRESENT' { 'VERIFIED_SUCCESS'; break }
        'PARTIAL' { 'PARTIAL_STATE'; break }
        default {
            if ($statusCode -ge 200 -and $statusCode -lt 300) { 'UNCERTAIN' }
            else { Get-RecoveryFailureState -StatusCode $script:LastHttpFailure.StatusCode -FailureClass $script:LastHttpFailure.FailureClass }
        }
    }
    Set-RecoveryState -State $terminalState
    [pscustomobject]@{
        State = $script:RecoveryState
        ResponseClass = $script:RecoveryResponseClass
        StatusCode = if ($statusCode -ge 100 -and $statusCode -le 599) { $statusCode } else { $null }
        Method = 'POST'
        ApiPath = '/api/data/v9.2/EntityDefinitions'
        RequestId = $script:RecoveryRequestId
        CorrelationId = $script:RecoveryCorrelationId
        Reconciliation = $script:RecoveryReconciliation
        StateTransitions = $script:RecoveryTransitions.ToArray()
        ExpectedPayloadSha256 = $script:RecoveryExpectedFingerprint
        ActualPayloadSha256 = $script:RecoveryActualFingerprint
        Preflight = $script:RecoveryPreflight
        HttpFailure = if ($null -ne $originalFailure) { $originalFailure } else { $null }
        WritesMayHaveOccurred = [bool]$script:WritesStarted
    }
}

function Show-Plan {
    param([Parameter(Mandatory = $true)][object]$Payloads)
    $preview = [ordered]@{
        Mode = if ($CreateOnlyRecovery) { 'CreateOnlyRecovery; Position-only; one POST maximum; GET-only reconciliation' } elseif ($PlanOnly) { 'PlanOnly; no authentication/network calls' } elseif ($Apply) { 'Apply requested; preflight and typed confirmation required' } else { 'DryRun; interactive auth and GET-only preflight' }
        Environment = if ($EnvironmentName) { $EnvironmentName } else { 'NOT SUPPLIED' }
        OrganizationUrl = if ($CreateOnlyRecovery) { '[omitted]' } elseif ($OrganizationUrl) { $OrganizationUrl.TrimEnd('/') } else { 'NOT SUPPLIED' }
        ExpectedEnvironmentId = if ($CreateOnlyRecovery) { '[omitted]' } elseif ($ExpectedEnvironmentId) { $ExpectedEnvironmentId } else { 'NOT SUPPLIED' }
        ExpectedOrganizationId = if ($CreateOnlyRecovery) { '[omitted]' } elseif ($ExpectedOrganizationId) { $ExpectedOrganizationId } else { 'NOT SUPPLIED' }
        SolutionUniqueName = 'os_sr_bso_rs_support'
        PublisherUniqueName = 'os_bso_rs_support'
        PublisherPrefix = 'os'
        TableSchemaName = $Payloads.Table.SchemaName
        OwnershipType = $Payloads.Table.OwnershipType
        TableDisplayName = $script:Definition.DisplayName
        DisplayCollectionName = $DisplayCollectionName
        DisplayCollectionNameStatus = if ($script:Definition.PluralApproved) { if ($TableName -ceq 'os_sr_ta') { 'Owner-approved Phase 1D-C' } else { 'Owner-approved Phase 1D-D' } } else { 'Pending owner approval; explicit input does not grant authorization' }
        PrimaryNameSchemaName = $Payloads.Table.Attributes[0].SchemaName
        PrimaryNameDataType = 'String/Text'
        PrimaryNameMaxLength = $script:Definition.PrimaryName.MaxLength
        PrimaryNameRequiredLevel = 'ApplicationRequired'
        PrimaryGuidLogicalName = $TableName + 'id'
        AdditionalColumnSchemaName = $Payloads.EmailColumn.SchemaName
        AdditionalColumnFormatName = $Payloads.EmailColumn.FormatName.Value
        AdditionalColumnMaxLength = $Payloads.EmailColumn.MaxLength
        AdditionalColumnRequiredLevel = $Payloads.EmailColumn.RequiredLevel.Value
        AlternateKeys = 'None'
        DuplicateDetection = 'None'
        AuditChanges = 'None; do not set audit properties and compare environment flags after Apply.'
        DataRowOperations = 'None; script contains no data-table requests.'
        ApiOperations = if ($CreateOnlyRecovery) {
            @('GET-only target, identity, privilege, Solution, Publisher, inventory, and audit preflight',
                'At most one POST EntityDefinitions for Position with MSCRM.SolutionUniqueName',
                'GET-only Position schema and Solution membership reconciliation')
        } else {
            @(
                'GET WhoAmI, Organization, Publisher, Solution, EntityDefinitions, audit flags',
                'POST EntityDefinitions with MSCRM.SolutionUniqueName: table and primary name',
                'POST EntityDefinitions(...)/Attributes with MSCRM.SolutionUniqueName: each declared additional column, if any',
                "POST PublishXml: publish only $TableName metadata",
                'GET EntityDefinitions, Keys, solutioncomponents, Organization: independent read-back'
            )
        }
        TablePayload = $Payloads.Table
        EmailColumnPayload = $Payloads.EmailColumn
        AdditionalColumnPayloads = @($Payloads.Columns)
    }
    Write-Output ($preview | ConvertTo-Json -Depth 40 -Compress)
}

try {
    if (($Apply -and $PlanOnly) -or ($CreateOnlyRecovery -and ($Apply -or $PlanOnly))) {
        if ($CreateOnlyRecovery) { Set-RecoveryState -State 'BLOCKED' }
        throw 'Choose exactly one of -Apply, -PlanOnly, or -CreateOnlyRecovery.'
    }
    if ($CreateOnlyRecovery -and $TableName -cne 'os_sr_pos') {
        Set-RecoveryState -State 'BLOCKED'
        Assert-CreateOnlyRecoveryTable -Name $TableName
    }
    if ($CreateOnlyRecovery -and -not $collectionNameWasExplicit) {
        Set-RecoveryState -State 'BLOCKED'
        throw 'Create-only recovery requires explicit -DisplayCollectionName Positions.'
    }
    if ($CreateOnlyRecovery -and $AuthorizationReference -notmatch '^[A-Za-z0-9][A-Za-z0-9._/-]{0,99}$') {
        Set-RecoveryState -State 'BLOCKED'
        throw 'Create-only recovery requires a safe, non-empty external authorization reference.'
    }
    if ($Apply -and -not $collectionNameWasExplicit) { throw 'Apply requires explicit -DisplayCollectionName and separate owner authorization.' }
    if ($DisplayCollectionName -cne $expectedCollectionName) {
        if ($CreateOnlyRecovery) { Set-RecoveryState -State 'FAILED_VALIDATION' }
        throw 'Collection label differs from the declared reference schema; stop for review.'
    }
    $payloads = New-SchemaPayloads
    if ($CreateOnlyRecovery) {
        Assert-PositionPayloadFingerprint -Payload $payloads.Table | Out-Null
    }
    try { Assert-SchemaPayloads -Payloads $payloads }
    catch {
        if ($CreateOnlyRecovery -and $script:RecoveryState -eq 'PRECHECK') {
            Set-RecoveryState -State 'FAILED_VALIDATION'
        }
        throw
    }
    Show-Plan -Payloads $payloads
    if ($PlanOnly) { return }

    $preflight = Get-Preflight
    $script:ReconciliationSolutionId = $preflight.SolutionId
    if ($CreateOnlyRecovery) {
        $script:RecoveryPreflight = [ordered]@{
            EnvironmentName = 'VN LMV IT'
            EnvironmentVerified = $script:RecoveryEnvironmentVerified
            IdentityVerified = $script:RecoveryIdentityVerified
            SolutionUniqueName = $preflight.SolutionUniqueName
            SolutionUnmanaged = $true
            PublisherUniqueName = 'os_bso_rs_support'
            PublisherPrefix = $preflight.PublisherPrefix
            ProjectTables = $preflight.ProjectTables
            TargetAbsent = -not $preflight.TargetExists
            SolutionSchemaComponentsMapped = $true
            VerifiedPrivileges = $preflight.VerifiedPrivileges
        }
        $confirmationPhrase = "RECOVER CREATE os_sr_pos IN VN LMV IT AUTHORIZATION $AuthorizationReference"
        $confirmation = Read-Host "Type '$confirmationPhrase' only after confirming the external approval"
        if ($confirmation -cne $confirmationPhrase) {
            Set-RecoveryState -State 'BLOCKED'
            throw 'Create-only recovery confirmation did not match; no write performed.'
        }
        Ensure-DataverseAccessToken
        $script:WritesAllowed = $true
        Set-RecoveryState -State 'READY'
        $recovery = Invoke-PositionCreateOnlyRecovery -Payload $payloads.Table -SolutionId $preflight.SolutionId
        Write-Result -Stage 'CreateOnlyRecovery' -Status $recovery.State -Details $recovery
        if ($recovery.State -cne 'VERIFIED_SUCCESS') { exit 1 }
        return
    }
    if (-not $Apply) {
        Assert-UnchangedState -Preflight $preflight
        Write-Result -Stage 'Preflight' -Status 'DryRunPassed' -Details ([ordered]@{
            OrganizationId = $preflight.OrganizationId
            PublisherUniqueName = 'os_bso_rs_support'
            PublisherPrefix = $preflight.PublisherPrefix
            SolutionUniqueName = $preflight.SolutionUniqueName
            TableLogicalName = $TableName
            TargetExists = $preflight.TargetExists
            TableAbsent = -not $preflight.TargetExists
            ExistingProjectTablesVerified = $preflight.ProjectTables
            ExistingMetadataUnchanged = $true
            AuditStateUnchanged = $true
            WritesPerformed = 0
            RequestsAttempted = $script:RequestCounts
        })
        return
    }

    $confirmationPhrase = "CREATE $TableName IN VN LMV IT WITH COLLECTION $DisplayCollectionName"
    $confirmation = Read-Host "Type '$confirmationPhrase' to authorize metadata writes"
    if ($confirmation -cne $confirmationPhrase) { throw 'Apply confirmation did not match; no writes performed.' }

    # The operator may take time to review and enter the typed confirmation.
    Ensure-DataverseAccessToken

    $script:WritesAllowed = $true
    Invoke-DataverseRequest -Method POST -Path 'EntityDefinitions' -Body $payloads.Table -WithSolutionHeader | Out-Null
    $tableAfterCreate = Get-EntityMetadata
    $partialDefinition = $script:Definition.Clone()
    $partialDefinition.Columns = @()
    Assert-TableMetadata -Metadata $tableAfterCreate -Definition $partialDefinition

    foreach ($columnPayload in $payloads.Columns) {
        Invoke-DataverseRequest -Method POST -Path "EntityDefinitions(LogicalName='$TableName')/Attributes" -Body $columnPayload -WithSolutionHeader | Out-Null
    }
    Invoke-DataverseRequest -Method POST -Path 'PublishXml' -Body ([ordered]@{ ParameterXml = "<importexportxml><entities><entity>$TableName</entity></entities></importexportxml>" }) | Out-Null

    $finalMetadata = Get-EntityMetadata
    Assert-TableMetadata -Metadata $finalMetadata
    Assert-SolutionMembership -SolutionId $preflight.SolutionId -Metadata $finalMetadata
    Assert-UnchangedState -Preflight $preflight -Created
    Write-Result -Stage 'Complete' -Status 'Verified' -Details ([ordered]@{
        TableLogicalName = $finalMetadata.LogicalName
        OwnershipType = $finalMetadata.OwnershipType
        PrimaryName = $finalMetadata.PrimaryNameAttribute
        PrimaryGuid = $finalMetadata.PrimaryIdAttribute
        CustomColumns = @($script:Definition.PrimaryName.SchemaName) + @($script:Definition.Columns | ForEach-Object { $_.SchemaName })
        TableAndColumnsSolutionMembershipVerified = $true
        AlternateKeys = 0
        ProjectTables = @($preflight.ProjectTables) + @($TableName)
        DataRowsCreated = 0
        AuditSettingsUnchanged = $true
        ExistingMetadataUnchanged = $true
        RequestsAttempted = $script:RequestCounts
        WriteResults = $script:WriteResults.ToArray()
        HttpFailure = $script:LastHttpFailure
    })
}
catch {
    if ($CreateOnlyRecovery -and $script:RecoveryState -in @('PRECHECK', 'READY')) {
        Set-RecoveryState -State 'BLOCKED'
    }
    Write-Result -Stage 'PreflightOrExecution' -Status 'Stopped' -Details (Get-StoppedDetails)
    exit 1
}
finally {
    $script:AccessToken = $null
    $script:AccessTokenIssuedAt = [DateTimeOffset]::MinValue
    $script:AccessTokenExpiresOn = [DateTimeOffset]::MinValue
    $script:WritesAllowed = $false
}
