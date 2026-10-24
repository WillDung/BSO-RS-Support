#requires -Version 7.4
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$EnvironmentName,
    [Parameter(Mandatory = $true)][string]$OrganizationUrl,
    [Parameter(Mandatory = $true)][string]$ExpectedEnvironmentId,
    [Parameter(Mandatory = $true)][string]$ExpectedOrganizationId,
    [Parameter(Mandatory = $true)][string]$AuthorizationReference,
    [switch]$ReconcileOnly,
    [switch]$PreflightOnly,
    [switch]$ResumeRemainingScope,
    [switch]$RepairPreflightOnly,
    [switch]$RepairStatusChoiceBindings
)

$ErrorActionPreference = 'Stop'
$script:SolutionName = 'os_sr_bso_rs_support'
$script:PublisherName = 'os_bso_rs_support'
$script:PublisherPrefix = 'os'
$script:ManifestPath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\docs\PHASE_3A_CANDIDATE_CORE_METADATA_PLAN.json'))
$script:CandidateRunner = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'Provision-BsoRsCandidateTable.ps1'))
$script:ExpectedManifestSha256 = '63f56173f61265f539d23d6ceffb5631e23f438e4e254755c1e24c7d17eb1915'
$script:RequestCounts = @{ GET = 0; PUT = 0; POST = 0 }
$script:WriteStages = [System.Collections.Generic.List[string]]::new()
$script:WriteHashes = [System.Collections.Generic.List[object]]::new()
$script:ApiRoot = $null
$script:AccessToken = $null
$script:ExpectedUserId = $null
$script:PacUserEmail = $null
$script:Publisher = $null
$script:Solution = $null
$script:CurrentStage = 'LOCAL_MANIFEST'
$script:MaximumWrites = 8
$script:CorrectedCallLogCreateDispatches = 0
$script:ProvisioningReconciled = $false
$script:ExpectedWritePaths = @()
$script:ChoiceName = 'os_sr_callout'
$script:OutcomeLabels = @('Answered', 'No Answer', 'Call Back Requested')
$script:TableNames = @('os_sr_call', 'os_sr_csh')
$script:ExpectedTableCreateNames = @('os_sr_call', 'os_sr_csh')
$script:RelationshipNames = @(
    'os_sr_cand_call',
    'os_sr_cand_csh',
    'os_sr_usr_call_ctby',
    'os_sr_usr_csh_actr'
)
$script:KeyNames = @('os_sr_call_ak_cand_action', 'os_sr_csh_ak_cand_action')
$script:ExpectedRelationshipNames = $script:RelationshipNames
$script:ExpectedKeyNames = $script:KeyNames
$script:TableCreateDispatches = 0
$script:RelationshipDispatches = 0
$script:KeyDispatches = 0
$script:RemainingScopeDispatches = 0
$script:RemainingScopeAuthorizationConsumed = $false
$script:StatusChoiceRepairWriteCount = 0
$script:LastWriteOutcomeUncertain = $false
$script:LastSanitizedWriteError = $null
$script:LastWriteHttpStatus = $null
$script:RepairAllowedColumns = @()
$script:StatusChoiceRepairResults = [System.Collections.Generic.List[object]]::new()

function Get-Sha256 {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes)).ToLowerInvariant()
}

function Set-ManifestContinuationState {
    param(
        [Parameter(Mandatory = $true)][string]$Status,
        [Parameter(Mandatory = $true)][int]$CorrectedCallLogDispatches,
        [int]$RemainingScopeWritesDispatched = -1,
        [switch]$ConsumeRemainingScopeAuthorization
    )
    $manifest = Get-Content -LiteralPath $script:ManifestPath -Raw | ConvertFrom-Json
    $continuation = $manifest.provisioning.phase3B2AuthorizedContinuation
    $continuation.status = $Status
    $continuation.correctedCallLogCreateDispatches = $CorrectedCallLogDispatches
    if ($RemainingScopeWritesDispatched -ge 0) {
        $continuation.remainingMetadataWritesDispatched = $RemainingScopeWritesDispatched
    }
    if ($ConsumeRemainingScopeAuthorization) {
        $continuation.remainingMetadataAuthorizationConsumed = $true
    }
    $json = ConvertTo-Json -InputObject $manifest -Depth 100
    [IO.File]::WriteAllText($script:ManifestPath, $json + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
    $script:ExpectedManifestSha256 = Get-ManifestHash
}

function Get-ManifestHash {
    Get-Sha256 -Bytes ([IO.File]::ReadAllBytes($script:ManifestPath))
}

function Get-SanitizedDataverseError {
    param(
        [Parameter(Mandatory = $true)][int]$StatusCode,
        [object]$Response
    )
    $code = ''
    $message = ''
    if ($null -ne $Response) {
        if ($Response.error) {
            $code = [string]$Response.error.code
            $message = [string]$Response.error.message
        }
        elseif ($Response -is [string]) {
            try {
                $parsed = $Response | ConvertFrom-Json -ErrorAction Stop
                if ($parsed.error) {
                    $code = [string]$parsed.error.code
                    $message = [string]$parsed.error.message
                }
            }
            catch {
                $message = $Response
            }
        }
    }
    if ([string]::IsNullOrWhiteSpace($message)) {
        $message = 'Dataverse returned an error response without a readable error message.'
    }
    $message = $message -replace '(?i)https?://\S+', '[URL]'
    $message = $message -replace '(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b', '[EMAIL]'
    $message = $message -replace '\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b', '[ID]'
    $message = $message -replace '(?i)\bBearer\s+\S+', 'Bearer [REDACTED]'
    if ($message.Length -gt 600) { $message = $message.Substring(0, 600) }
    $safeCode = if ($code -match '^(0x[0-9a-fA-F]{8}|[A-Za-z0-9_.-]{1,80})$') { $code } else { 'UNAVAILABLE' }
    "HTTP $StatusCode; Dataverse code $safeCode; $message"
}

function Get-SanitizedFailureMessage {
    param([Parameter(Mandatory = $true)][string]$Message)
    $safe = $Message -replace '(?i)https?://\S+', '[URL]'
    $safe = $safe -replace '(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b', '[EMAIL]'
    $safe = $safe -replace '\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b', '[ID]'
    $safe = $safe -replace '(?i)\bBearer\s+\S+', '******'
    if ($safe.Length -gt 600) { $safe = $safe.Substring(0, 600) }
    $safe
}

function Assert-Manifest {
    param([Parameter(Mandatory = $true)][object]$Manifest)
    if ((Get-ManifestHash) -cne $script:ExpectedManifestSha256) {
        throw 'Current manifest fingerprint differs from the authorized Phase 3B.2 baseline.'
    }
    $continuation = $Manifest.provisioning.phase3B2AuthorizedContinuation
    $writeAuthorizationIsFresh = $continuation.status -ceq 'AUTHORIZED_CORRECTED_CALLLOG_AND_REMAINING_CHILD_METADATA' -and
        $continuation.correctedCallLogCreateDispatchLimit -eq 1 -and
        $continuation.correctedCallLogCreateDispatches -eq 0
    $remainingScopeAuthorizationIsAvailable = $ResumeRemainingScope -and
        $continuation.status -ceq 'CALL_LOG_RECONCILED_REMAINING_SCOPE_AUTHORIZED' -and
        $continuation.correctedCallLogCreateDispatches -eq 1 -and
        $continuation.remainingMetadataDispatchLimit -eq 7 -and
        $continuation.remainingMetadataWritesDispatched -eq 0 -and
        -not $continuation.remainingMetadataAuthorizationConsumed
    $statusChoiceRepairRequested = $RepairPreflightOnly -or $RepairStatusChoiceBindings
    $statusChoiceRepairIsAuthorized = $statusChoiceRepairRequested -and
        $continuation.status -ceq 'STOPPED_AFTER_REMAINING_METADATA_MISMATCH_NO_FURTHER_WRITES' -and
        $continuation.remainingMetadataAuthorizationConsumed -and
        $continuation.latestResumeClassification -ceq 'PARTIAL_METADATA_STATE' -and
        $continuation.correctedCallLogCreateDispatches -eq 1 -and
        $continuation.remainingMetadataWritesDispatched -eq 7
    $readOnlyRecoveryIsAllowed = $ReconcileOnly -and
        $continuation.correctedCallLogCreateDispatches -eq 1 -and
        $continuation.status -in @(
            'CALL_LOG_RECONCILED_REMAINING_SCOPE_AUTHORIZED',
            'STOPPED_AFTER_CORRECTED_CONTINUATION_REQUIRES_RECONCILIATION',
            'STOPPED_AFTER_REMAINING_METADATA_MISMATCH_NO_FURTHER_WRITES',
            'REMAINING_SCOPE_AUTHORIZATION_CONSUMED_RECONCILIATION_PENDING',
            'PHASE_3B2_STORAGE_RECONCILED_AUTHORIZATION_CONSUMED'
        )
    if ($statusChoiceRepairRequested -and [string]::IsNullOrWhiteSpace($AuthorizationReference)) {
        throw 'Status Choice repair requires an explicit owner authorization reference.'
    }
    $modeCount = @($ReconcileOnly, $PreflightOnly, $ResumeRemainingScope, $RepairPreflightOnly, $RepairStatusChoiceBindings |
        Where-Object { $_ }).Count
    if ($modeCount -gt 1) { throw 'Provisioning modes are mutually exclusive.' }
    if ($Manifest.phase -cne '3A' -or $Manifest.solutionUniqueName -cne $script:SolutionName -or
        $Manifest.publisherPrefix -cne $script:PublisherPrefix -or
        (-not $writeAuthorizationIsFresh -and -not $remainingScopeAuthorizationIsAvailable -and
            -not $readOnlyRecoveryIsAllowed -and -not $statusChoiceRepairIsAuthorized) -or
        $Manifest.provisioning.phase3B2AuthorizedContinuation.automaticRetries -ne 0 -or
        $Manifest.provisioning.phase3B2AuthorizedContinuation.candidateCreateOrModification -or
        $Manifest.provisioning.phase3B2AuthorizedContinuation.businessDataWrites -or
        $Manifest.provisioning.phase3B2AuthorizedContinuation.customApiOrPlugin -or
        $Manifest.provisioning.phase3B2AuthorizedContinuation.securityOrAppChanges -or
        $Manifest.provisioning.phase3B2AuthorizedContinuation.publication) {
        throw 'Phase 3B.2 manifest authorization or exclusions differ from the approved scope.'
    }
    $expectedRelations = @(
        'os_sr_cand_call',
        'os_sr_cand_csh',
        'os_sr_usr_call_ctby',
        'os_sr_usr_csh_actr'
    )
    $relations = @($Manifest.relationships | Where-Object {
        $_.child -in $script:TableNames
    })
    $allRelationships = @($Manifest.relationships)
    if ($relations.Count -ne 4 -or
        (Compare-Object $expectedRelations @($relations | ForEach-Object schemaName)).Count -ne 0 -or
        @($allRelationships | ForEach-Object schemaName | Select-Object -Unique).Count -ne $allRelationships.Count) {
        throw 'Child relationship names or uniqueness differ from the normalized manifest.'
    }
    foreach ($relation in $relations) {
        if ($relation.delete -cne 'Restrict' -or $relation.assignShareReparent -cne 'NoCascade') {
            throw 'Child history relationship cascade behavior is not the approved non-destructive configuration.'
        }
        $table = @($Manifest.tables | Where-Object logicalName -CEQ $relation.child)
        $lookup = @($table[0].columns | Where-Object logicalName -CEQ $relation.lookup)
        if ($table.Count -ne 1 -or $lookup.Count -ne 1 -or $lookup[0].relationship -cne $relation.schemaName) {
            throw 'Child relationship target or lookup schema differs from the manifest.'
        }
    }
    $call = @($Manifest.tables | Where-Object logicalName -CEQ 'os_sr_call')
    $history = @($Manifest.tables | Where-Object logicalName -CEQ 'os_sr_csh')
    if ($call.Count -ne 1 -or $history.Count -ne 1 -or
        $call[0].ownership -cne 'UserOwned' -or $history[0].ownership -cne 'UserOwned' -or
        -not $call[0].audit.enabled -or -not $history[0].audit.enabled -or
        $call[0].primaryName.format -cne 'CALL-{SEQNUM:8}' -or
        $history[0].primaryName.format -cne 'HIST-{SEQNUM:8}' -or
        $Manifest.callOutcomeChoice.logicalName -cne $script:ChoiceName -or
        (Compare-Object $script:OutcomeLabels @($Manifest.callOutcomeChoice.options | ForEach-Object label)).Count -ne 0) {
        throw 'Child table, auditing, AutoNumber, or Call Outcome Choice proposal is not exact.'
    }
    foreach ($table in @($call[0], $history[0])) {
        if ($table.primaryName.type -cne 'AutoNumber' -or
            $table.primaryName.storageType -cne 'String' -or
            [int]$table.primaryName.maxLength -ne 100 -or
            $table.primaryName.formatName -cne 'Text' -or
            $table.primaryName.required -cne 'SystemGenerated' -or
            [string]::IsNullOrWhiteSpace([string]$table.primaryName.logicalName) -or
            [string]::IsNullOrWhiteSpace([string]$table.primaryName.displayName) -or
            [string]::IsNullOrWhiteSpace([string]$table.primaryName.format)) {
            throw "Approved String/AutoNumber primary-name metadata is incomplete for $($table.logicalName)."
        }
    }
    foreach ($key in $script:KeyNames) {
        $matches = @($Manifest.tables.alternateKeys | Where-Object name -CEQ $key)
        if ($matches.Count -ne 1) { throw 'An approved child-table idempotency key is missing or ambiguous.' }
    }
}

function New-Label {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)
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
    param([bool]$Required)
    [ordered]@{
        Value = if ($Required) { 'ApplicationRequired' } else { 'None' }
        CanBeChanged = $true
        ManagedPropertyLogicalName = 'canmodifyrequirementlevelsettings'
    }
}

function Get-Required {
    param([string]$Requirement)
    $Requirement -in @('Required', 'RequiredForOperationWrites', 'RequiredForOperationTransitions')
}

function Assert-PrimaryNameDefinition {
    param([Parameter(Mandatory = $true)][object]$Table)
    $primaryName = $Table.primaryName
    $maxLength = 0
    $maxLengthIsValid = $null -ne $primaryName.maxLength -and
        [int]::TryParse([string]$primaryName.maxLength, [ref]$maxLength)
    if ($primaryName.type -cne 'AutoNumber' -or
        $primaryName.storageType -cne 'String' -or
        -not $maxLengthIsValid -or
        $maxLength -ne 100 -or
        $maxLength -lt 1 -or
        $maxLength -gt 4000 -or
        $primaryName.formatName -cne 'Text' -or
        $primaryName.required -cne 'SystemGenerated' -or
        [string]::IsNullOrWhiteSpace([string]$primaryName.logicalName) -or
        [string]::IsNullOrWhiteSpace([string]$primaryName.displayName) -or
        [string]::IsNullOrWhiteSpace([string]$primaryName.format)) {
        throw "Primary-name String/AutoNumber definition is incomplete or outside the owner-approved contract for $($Table.logicalName)."
    }
    [pscustomobject]@{
        SchemaName = [string]$primaryName.logicalName
        DisplayName = [string]$primaryName.displayName
        RequiredLevel = 'ApplicationRequired'
        MaxLength = $maxLength
        FormatName = 'Text'
        AutoNumberFormat = [string]$primaryName.format
    }
}

function New-AttributePayload {
    param(
        [Parameter(Mandatory = $true)][object]$Column,
        [Parameter(Mandatory = $true)][hashtable]$ChoiceMetadataByName
    )
    $required = Get-Required -Requirement ([string]$Column.required)
    switch ([string]$Column.type) {
        'String' {
            $format = if ($Column.format -in @('Email', 'Phone', 'Url')) { [string]$Column.format } else { 'Text' }
            [ordered]@{
                '@odata.type' = 'Microsoft.Dynamics.CRM.StringAttributeMetadata'
                AttributeType = 'String'
                AttributeTypeName = [ordered]@{ Value = 'StringType' }
                SchemaName = [string]$Column.logicalName
                DisplayName = New-Label -Text ([string]$Column.displayName)
                RequiredLevel = New-RequiredLevel -Required $required
                FormatName = [ordered]@{ Value = $format }
                MaxLength = [int]$Column.maxLength
                IsPrimaryName = $false
            }
        }
        'Memo' {
            [ordered]@{
                '@odata.type' = 'Microsoft.Dynamics.CRM.MemoAttributeMetadata'
                AttributeType = 'Memo'
                AttributeTypeName = [ordered]@{ Value = 'MemoType' }
                SchemaName = [string]$Column.logicalName
                DisplayName = New-Label -Text ([string]$Column.displayName)
                RequiredLevel = New-RequiredLevel -Required $required
                Format = 'Text'
                MaxLength = [int]$Column.maxLength
                IsPrimaryName = $false
            }
        }
        'DateTime' {
            [ordered]@{
                '@odata.type' = 'Microsoft.Dynamics.CRM.DateTimeAttributeMetadata'
                AttributeType = 'DateTime'
                AttributeTypeName = [ordered]@{ Value = 'DateTimeType' }
                SchemaName = [string]$Column.logicalName
                DisplayName = New-Label -Text ([string]$Column.displayName)
                RequiredLevel = New-RequiredLevel -Required $required
                Format = 'DateAndTime'
                DateTimeBehavior = [ordered]@{ Value = [string]$Column.behavior }
                IsPrimaryName = $false
            }
        }
        'GlobalChoice' {
            $targetName = [string]$Column.target
            if (-not $ChoiceMetadataByName.ContainsKey($targetName)) {
                throw "Global Choice metadata for $targetName is unavailable; no table payload can be created safely."
            }
            [ordered]@{
                '@odata.type' = 'Microsoft.Dynamics.CRM.PicklistAttributeMetadata'
                AttributeType = 'Picklist'
                AttributeTypeName = [ordered]@{ Value = 'PicklistType' }
                SchemaName = [string]$Column.logicalName
                DisplayName = New-Label -Text ([string]$Column.displayName)
                RequiredLevel = New-RequiredLevel -Required $required
                IsPrimaryName = $false
                'GlobalOptionSet@odata.bind' = "/GlobalOptionSetDefinitions($($ChoiceMetadataByName[$targetName].MetadataId))"
            }
        }
        default { throw "Unsupported child column type in approved manifest: $($Column.type)" }
    }
}

function New-TablePayload {
    param(
        [Parameter(Mandatory = $true)][object]$Table,
        [Parameter(Mandatory = $true)][object]$Manifest,
        [Parameter(Mandatory = $true)][hashtable]$ChoiceMetadataByName
    )
    $primaryName = Assert-PrimaryNameDefinition -Table $Table
    $attributes = [System.Collections.Generic.List[object]]::new()
    $attributes.Add([ordered]@{
        '@odata.type' = 'Microsoft.Dynamics.CRM.StringAttributeMetadata'
        AttributeType = 'String'
        AttributeTypeName = [ordered]@{ Value = 'StringType' }
        SchemaName = $primaryName.SchemaName
        DisplayName = New-Label -Text $primaryName.DisplayName
        RequiredLevel = New-RequiredLevel -Required ($primaryName.RequiredLevel -ceq 'ApplicationRequired')
        FormatName = [ordered]@{ Value = $primaryName.FormatName }
        MaxLength = $primaryName.MaxLength
        IsPrimaryName = $true
        AutoNumberFormat = $primaryName.AutoNumberFormat
    })
    foreach ($column in @($Table.columns | Where-Object type -ne 'Lookup')) {
        $attributes.Add((New-AttributePayload -Column $column -ChoiceMetadataByName $ChoiceMetadataByName))
    }
    [ordered]@{
        '@odata.type' = 'Microsoft.Dynamics.CRM.EntityMetadata'
        SchemaName = [string]$Table.logicalName
        DisplayName = New-Label -Text ([string]$Table.displayName)
        DisplayCollectionName = New-Label -Text $(if ($Table.logicalName -ceq 'os_sr_call') {
            'Call Logs'
        } else {
            'Candidate Status Histories'
        })
        Description = New-Label -Text ''
        OwnershipType = [string]$Table.ownership
        IsActivity = $false
        HasActivities = $false
        HasNotes = $false
        IsAuditEnabled = [ordered]@{
            Value = [bool]$Table.audit.enabled
            CanBeChanged = $true
            ManagedPropertyLogicalName = 'canmodifyauditsettings'
        }
        Attributes = $attributes.ToArray()
    }
}

function Assert-TargetInput {
    if ($EnvironmentName -cne 'VN LMV IT' -or
        ([Uri]$OrganizationUrl).AbsoluteUri.TrimEnd('/') -cne 'https://org14938ec2.crm4.dynamics.com' -or
        [Guid]::Empty -eq [Guid]$ExpectedEnvironmentId -or
        [Guid]::Empty -eq [Guid]$ExpectedOrganizationId) {
        throw 'Confirmed environment target parameters do not match the fixed Phase 3B.2 target.'
    }
}

function Assert-PacIdentity {
    $output = @(& pac env who 2>&1 | ForEach-Object { [string]$_ })
    if ($LASTEXITCODE -ne 0) { throw 'PAC identity check failed; no environment switch or sign-in was attempted.' }
    $text = $output -join "`n"
    $name = [regex]::Match($text, '(?m)^\s*Friendly Name:\s*(.+?)\s*$')
    $url = [regex]::Match($text, '(?m)^\s*Org URL:\s*(\S+)')
    $org = [regex]::Match($text, '(?m)^\s*Org ID:\s*([0-9a-fA-F-]{36})')
    $environment = [regex]::Match($text, '(?m)^\s*Environment ID:\s*([0-9a-fA-F-]{36})')
    $user = [regex]::Match($text, '(?m)^\s*User ID:\s*([0-9a-fA-F-]{36})')
    $email = [regex]::Match($text, '(?m)^\s*User Email:\s*(\S+)')
    if (-not ($name.Success -and $url.Success -and $org.Success -and $environment.Success -and $user.Success -and $email.Success) -or
        $name.Groups[1].Value -cne $EnvironmentName -or
        $url.Groups[1].Value.TrimEnd('/') -cne $OrganizationUrl.TrimEnd('/') -or
        $org.Groups[1].Value -ine $ExpectedOrganizationId -or
        $environment.Groups[1].Value -ine $ExpectedEnvironmentId) {
        throw 'PAC target or user identity differs from the owner-confirmed target.'
    }
    $script:PacUserEmail = $email.Groups[1].Value
    $script:ExpectedUserId = $user.Groups[1].Value.ToLowerInvariant()
    [Environment]::SetEnvironmentVariable('BSO_RS_EXPECTED_USER_ID', $script:ExpectedUserId, 'Process')
    if ([Environment]::GetEnvironmentVariable('BSO_RS_EXPECTED_USER_ID', 'Process') -cne $script:ExpectedUserId) {
        throw 'Process-scoped expected-user identity guard could not be established.'
    }
}

function Get-ValidatedToken {
    if (-not (Get-Module -ListAvailable -Name Az.Accounts)) { throw 'Existing Az.Accounts module is unavailable.' }
    Import-Module Az.Accounts -ErrorAction Stop
    $context = Get-AzContext -ErrorAction Stop
    if ($null -eq $context -or $context.Account.Type -ne 'User' -or
        $context.Account.Id -ine $script:PacUserEmail) {
        throw 'Existing Az.Accounts identity does not match the PAC identity; no login or context switch attempted.'
    }
    $result = Get-AzAccessToken -ResourceUrl $OrganizationUrl -AsSecureString -ErrorAction Stop
    $secure = $result.Token
    if ($secure -isnot [Security.SecureString]) { throw 'Az.Accounts did not return a secure token.' }
    $token = ConvertFrom-SecureString -SecureString $secure -AsPlainText
    try {
        $parts = $token.Split('.')
        if ($parts.Count -ne 3) { throw 'Dataverse credential was not a JWT.' }
        $payload = $parts[1].Replace('-', '+').Replace('_', '/')
        switch ($payload.Length % 4) { 2 { $payload += '==' } 3 { $payload += '=' } }
        $claims = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload)) | ConvertFrom-Json
        $audience = [Uri]([string]$claims.aud)
        $expires = [DateTimeOffset]::FromUnixTimeSeconds([long]$claims.exp)
        if ($claims.tid -ine $context.Tenant.Id -or
            $audience.Authority -ine ([Uri]$OrganizationUrl).Authority -or
            'user_impersonation' -notin @(([string]$claims.scp) -split '\s+') -or
            $expires -le [DateTimeOffset]::UtcNow -or
            [math]::Abs(($expires - [DateTimeOffset]$result.ExpiresOn).TotalMinutes) -gt 2) {
            throw 'Dataverse credential target, tenant, delegated scope, or expiry validation failed.'
        }
        $script:AccessToken = $token
    }
    finally {
        $token = $null
        $secure = $null
        $result = $null
    }
}

function Invoke-DataverseRequest {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('GET', 'PUT', 'POST')][string]$Method,
        [Parameter(Mandatory = $true)][string]$Path,
        [object]$Body,
        [switch]$WithSolutionHeader,
        [switch]$WithMergeLabels
    )
    $uri = if ([Uri]::IsWellFormedUriString($Path, [UriKind]::Absolute)) {
        [Uri]$Path
    } else {
        [Uri]($script:ApiRoot + $Path)
    }
    if ($uri.Scheme -cne 'https' -or $uri.Authority -ine ([Uri]$OrganizationUrl).Authority -or
        $uri.AbsolutePath -notmatch '^/api/data/v9\.2/' -or $uri.UserInfo -or $uri.Fragment) {
        throw 'Dataverse request target is outside the verified organization API.'
    }
    if ($Method -in @('PUT', 'POST')) {
        $index = $script:WriteStages.Count
        if ($index -ge $script:MaximumWrites -or -not $WithSolutionHeader) {
            throw 'Write ceiling or approved Solution header guard failed.'
        }
        $pathIsApproved = $index -lt $script:ExpectedWritePaths.Count -and $Path -ceq $script:ExpectedWritePaths[$index]
        $bodyIsApproved = if ($Method -eq 'PUT' -and $RepairStatusChoiceBindings) {
            $columnName = [string]$Body.LogicalName
            $targetChoiceId = [string]$script:RepairTargetChoice.MetadataId
            $expectedColumn = if ($index -lt $script:RepairAllowedColumns.Count) {
                [string]$script:RepairAllowedColumns[$index]
            } else { $null }
            $metadataId = [regex]::Match($Path, '/Attributes\(([0-9a-fA-F-]{36})\)$')
            $columnName -in $script:RepairAllowedColumns -and
            $columnName -ceq $expectedColumn -and
            $script:StatusChoiceRepairWriteCount -lt 2 -and
            $metadataId.Success -and
            $metadataId.Groups[1].Value -ieq [string]$script:RepairAttributeIds[$columnName] -and
            [string]$Body.MetadataId -ieq [string]$script:RepairAttributeIds[$columnName] -and
            [string]$Body.SchemaName -ceq $columnName -and
            [string]$Body.'@odata.type' -ceq 'Microsoft.Dynamics.CRM.PicklistAttributeMetadata' -and
            [string]$Body.'GlobalOptionSet@odata.bind' -ceq "/GlobalOptionSetDefinitions($targetChoiceId)" -and
            -not $Body.ContainsKey('GlobalOptionSet')
        } else {
            $false
        }
        if ($Method -eq 'POST') {
            $bodyIsApproved = switch -Regex ($Path) {
            '^GlobalOptionSetDefinitions$' {
                $Body.Name -ceq $script:ChoiceName -and @($Body.Options).Count -eq 3 -and
                @($Body.Options | Where-Object { $null -ne $_.Value }).Count -eq 0
                break
            }
            '^EntityDefinitions$' {
                $Body.SchemaName -in $script:TableNames -and $Body.OwnershipType -ceq 'UserOwned' -and
                $script:TableCreateDispatches -lt $script:ExpectedTableCreateNames.Count -and
                $Body.SchemaName -ceq $script:ExpectedTableCreateNames[$script:TableCreateDispatches] -and
                $Body.IsAuditEnabled.Value -eq $true -and @($Body.Attributes).Count -gt 0
                break
            }
            '^RelationshipDefinitions$' {
                $Body.SchemaName -in $script:RelationshipNames -and
                $Body.ReferencingEntity -in $script:TableNames -and
                $script:RelationshipDispatches -lt $script:ExpectedRelationshipNames.Count -and
                $Body.SchemaName -ceq $script:ExpectedRelationshipNames[$script:RelationshipDispatches] -and
                $Body.CascadeConfiguration.Delete -ceq 'Restrict' -and
                $Body.CascadeConfiguration.Assign -ceq 'NoCascade' -and
                $Body.CascadeConfiguration.Share -ceq 'NoCascade' -and
                $Body.CascadeConfiguration.Reparent -ceq 'NoCascade'
                break
            }
            '/Keys$' {
                $Body.SchemaName -in $script:KeyNames -and
                $script:KeyDispatches -lt $script:ExpectedKeyNames.Count -and
                $Body.SchemaName -ceq $script:ExpectedKeyNames[$script:KeyDispatches] -and
                @($Body.KeyAttributes).Count -eq 2
                break
            }
            default { $false }
            }
        }
        if (-not $pathIsApproved -or -not $bodyIsApproved) {
            throw "$Method path or payload is outside the active fixed Phase 3B.2 allowlist."
        }
        if ($Method -eq 'PUT') {
            $script:StatusChoiceRepairWriteCount++
        }
        if ($Method -eq 'POST' -and $ResumeRemainingScope) {
            if (-not $script:RemainingScopeAuthorizationConsumed) {
                Set-ManifestContinuationState -Status 'REMAINING_SCOPE_AUTHORIZATION_CONSUMED_RECONCILIATION_PENDING' `
                    -CorrectedCallLogDispatches 1 -RemainingScopeWritesDispatched 0 -ConsumeRemainingScopeAuthorization
                $script:RemainingScopeAuthorizationConsumed = $true
            }
            $script:RemainingScopeDispatches++
            Set-ManifestContinuationState -Status 'REMAINING_SCOPE_AUTHORIZATION_CONSUMED_RECONCILIATION_PENDING' `
                -CorrectedCallLogDispatches 1 -RemainingScopeWritesDispatched $script:RemainingScopeDispatches `
                -ConsumeRemainingScopeAuthorization
        }
        if ($Method -eq 'POST' -and $Path -ceq 'EntityDefinitions' -and $Body.SchemaName -ceq 'os_sr_call') {
            if ($script:CorrectedCallLogCreateDispatches -ge 1) {
                throw 'The separately authorized corrected Call Log table-create dispatch limit has been reached.'
            }
            $script:CorrectedCallLogCreateDispatches++
            Set-ManifestContinuationState -Status 'CORRECTED_CALLLOG_DISPATCHED_RECONCILIATION_PENDING' -CorrectedCallLogDispatches 1
        }
        if ($Method -eq 'POST' -and $Path -ceq 'EntityDefinitions') { $script:TableCreateDispatches++ }
        elseif ($Method -eq 'POST' -and $Path -ceq 'RelationshipDefinitions') { $script:RelationshipDispatches++ }
        elseif ($Method -eq 'POST' -and $Path -match '/Keys$') { $script:KeyDispatches++ }
        $payloadHash = Get-Sha256 -Bytes ([Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $Body -Depth 80 -Compress)))
        if ($Method -eq 'PUT' -and $RepairStatusChoiceBindings) {
            $logicalName = [string]$Body.LogicalName
            $script:WriteStages.Add("PUT $logicalName")
            $script:WriteHashes.Add([ordered]@{
                LogicalName = $logicalName
                AttributeMetadataIdSha256 = Get-MetadataIdFingerprint -MetadataId ([string]$script:RepairAttributeIds[$logicalName])
                PayloadSha256 = $payloadHash
            })
        } else {
            $script:WriteStages.Add($Path)
            $script:WriteHashes.Add([ordered]@{ Path = $Path; PayloadSha256 = $payloadHash })
        }
    }
    $headers = @{
        Authorization = 'Bearer ' + $script:AccessToken
        Accept = 'application/json'
        'OData-MaxVersion' = '4.0'
        'OData-Version' = '4.0'
        'If-None-Match' = 'null'
    }
    if ($WithSolutionHeader) { $headers['MSCRM.SolutionUniqueName'] = $script:SolutionName }
    if ($WithMergeLabels) { $headers['MSCRM.MergeLabels'] = 'true' }
    $request = @{
        Uri = $uri.AbsoluteUri
        Method = $Method
        Headers = $headers
        SkipHeaderValidation = $true
        MaximumRedirection = 0
        MaximumRetryCount = 0
        SkipHttpErrorCheck = $true
        TimeoutSec = 120
        ErrorAction = 'Stop'
        StatusCodeVariable = 'statusCode'
    }
    if ($PSBoundParameters.ContainsKey('Body')) {
        $request.ContentType = 'application/json; charset=utf-8'
        $request.Body = ConvertTo-Json -InputObject $Body -Depth 80 -Compress
    }
    $script:RequestCounts[$Method]++
    try { $response = Invoke-RestMethod @request }
    catch {
        if ($Method -in @('PUT', 'POST')) {
            $script:LastWriteOutcomeUncertain = $true
            $script:LastSanitizedWriteError = "HTTP status unavailable; transport outcome uncertain; Dataverse $Method was not retried."
            throw "A metadata $Method transport outcome is uncertain; do not retry."
        }
        throw 'A Dataverse GET failed; no write was sent by this request.'
    }
    if ($Method -in @('PUT', 'POST')) { $script:LastWriteHttpStatus = [int]$statusCode }
    if ([int]$statusCode -lt 200 -or [int]$statusCode -ge 300) {
        if ($Method -in @('PUT', 'POST')) {
        $script:LastSanitizedWriteError = Get-SanitizedDataverseError -StatusCode ([int]$statusCode) -Response $response
        throw $script:LastSanitizedWriteError
    }
        throw "Dataverse returned HTTP $statusCode; response content suppressed."
    }
    $response
}

function Get-OptionalMetadata {
    param([Parameter(Mandatory = $true)][string]$Path)
    try { Invoke-DataverseRequest -Method GET -Path $Path }
    catch {
        if ($_.Exception.Message -match 'HTTP 404') { return $null }
        throw
    }
}

function Get-ODataRows {
    param([Parameter(Mandatory = $true)][string]$Path)
    @((Invoke-DataverseRequest -Method GET -Path $Path).value)
}

function Assert-GlobalPrivileges {
    $required = @('prvCreateEntity', 'prvCreateAttribute', 'prvCreateCustomization')
    $query = [Uri]::EscapeDataString((ConvertTo-Json -InputObject $required -Compress))
    $rows = Invoke-DataverseRequest -Method GET -Path "systemusers($($script:ExpectedUserId))/Microsoft.Dynamics.CRM.RetrieveUserSetOfPrivilegesByNames(PrivilegeNames=@p)?@p=$query"
    foreach ($name in $required) {
        $match = @($rows.RolePrivileges | Where-Object PrivilegeName -CEQ $name)
        if ($match.Count -ne 1 -or [string]$match[0].Depth -notin @('Global', '3')) {
            throw 'Required global metadata privileges were not proven.'
        }
    }
}

function Assert-Choice {
    param([Parameter(Mandatory = $true)][object]$Choice)
    if ([string]$Choice.Name -cne $script:ChoiceName -or
        $Choice.IsGlobal -ne $true -or [string]$Choice.OptionSetType -cne 'Picklist' -or
        @($Choice.Options).Count -ne 3) {
        throw 'Call Outcome Choice identity or shape differs from the approved proposal.'
    }
    $actual = @($Choice.Options | ForEach-Object {
        [pscustomobject]@{
            Label = [string]$_.Label.UserLocalizedLabel.Label
            Value = [int]$_.Value
        }
    })
    if ((Compare-Object $script:OutcomeLabels @($actual | ForEach-Object Label)).Count -ne 0 -or
        @($actual | Select-Object -ExpandProperty Value -Unique).Count -ne 3 -or
        @($actual | Where-Object Value -le 0).Count -ne 0) {
        throw 'Call Outcome Choice labels or Dataverse-assigned values failed exact reconciliation.'
    }
    $solutionFilter = [Uri]::EscapeDataString("_solutionid_value eq $($script:Solution.solutionid)")
    $matches = @(Get-ODataRows -Path "solutioncomponents?`$select=componenttype,objectid&`$filter=$solutionFilter" |
        Where-Object { [string]$_.objectid -ieq [string]$Choice.MetadataId -and [int]$_.componenttype -eq 9 })
    if ($matches.Count -ne 1) { throw 'Call Outcome Choice is not included exactly once in the approved Solution.' }
    [pscustomobject]@{ Metadata = $Choice; Options = $actual }
}

function Update-ManifestChoiceValues {
    param([Parameter(Mandatory = $true)][object[]]$Options)
    if ($Options.Count -ne 3 -or
        (Compare-Object $script:OutcomeLabels @($Options | ForEach-Object Label)).Count -ne 0) {
        throw 'Refusing to freeze a Call Outcome mapping with unexpected labels.'
    }
    $text = [IO.File]::ReadAllText($script:ManifestPath)
    $blockMatch = [regex]::Match($text, '(?s)"callOutcomeChoice"\s*:\s*\{(?<body>.*?)\r?\n\s*\},\r?\n\s*"relationships"\s*:')
    if (-not $blockMatch.Success) { throw 'Cannot isolate the Call Outcome Choice manifest block safely.' }
    $body = $blockMatch.Groups['body'].Value
    $valueMatches = [regex]::Matches($body, '"value"\s*:\s*null')
    if ($valueMatches.Count -eq 3) {
        for ($i = 0; $i -lt 3; $i++) {
            $label = $script:OutcomeLabels[$i]
            $option = @($Options | Where-Object Label -CEQ $label)
            if ($option.Count -ne 1) { throw "Live Choice label $label is not unique." }
            $match = [regex]::Match($body, '"value"\s*:\s*null')
            if (-not $match.Success) { throw 'Choice value placeholder count changed during freeze.' }
            $replacement = '"value": ' + [int]$option[0].Value
            $body = $body.Substring(0, $match.Index) + $replacement + $body.Substring($match.Index + $match.Length)
        }
    }
    else {
        $existing = @([regex]::Matches($body, '"value"\s*:\s*(\d+)'))
        if ($existing.Count -ne 3) { throw 'Call Outcome Choice manifest values are neither unassigned nor a three-value mapping.' }
        $current = @($existing | ForEach-Object { [int]$_.Groups[1].Value })
        $desired = @($Options | ForEach-Object { [int]$_.Value })
        if ((Compare-Object $current $desired).Count -ne 0) {
            throw 'Frozen Call Outcome Choice values differ from live Dataverse.'
        }
    }
    $body = [regex]::Replace($body, '"valueStatus"\s*:\s*"[^"]*"', '"valueStatus": "Dataverse option values GET-reconciled and frozen during the authorized Phase 3B.2 continuation."')
    $updated = $text.Substring(0, $blockMatch.Groups['body'].Index) + $body +
        $text.Substring($blockMatch.Groups['body'].Index + $blockMatch.Groups['body'].Length)
    [IO.File]::WriteAllText($script:ManifestPath, $updated, [Text.UTF8Encoding]::new($false))
    $script:ExpectedManifestSha256 = Get-ManifestHash
}

function Assert-ChildTableAbsent {
    foreach ($name in $script:TableNames) {
        $table = Get-OptionalMetadata -Path "EntityDefinitions(LogicalName='$name')?`$select=LogicalName,MetadataId"
        if ($null -ne $table) { throw "Child table $name already exists; no create or replacement is authorized." }
    }
}

function Assert-CallLogResumeReadback {
    param(
        [Parameter(Mandatory = $true)][object]$Table,
        [Parameter(Mandatory = $true)][object]$Choice
    )
    $name = [string]$Table.logicalName
    $metadata = Get-OptionalMetadata -Path "EntityDefinitions(LogicalName='$name')?`$select=LogicalName,MetadataId,OwnershipType,PrimaryNameAttribute,IsAuditEnabled"
    if ($null -eq $metadata -or $metadata.LogicalName -cne $name -or
        $metadata.OwnershipType -cne 'UserOwned' -or
        $metadata.PrimaryNameAttribute -cne $Table.primaryName.logicalName -or
        $metadata.IsAuditEnabled.Value -ne $true) {
        throw 'Existing Call Log identity, ownership, primary name, or audit metadata differs from the approved manifest.'
    }

    $attributes = @(Get-ODataRows -Path "EntityDefinitions(LogicalName='$name')/Attributes")
    $customAttributes = @($attributes | Where-Object {
        [string]$_.LogicalName -like "$name`_*" -and
        [string]$_.AttributeType -cne 'Virtual' -and
        [string]::IsNullOrWhiteSpace([string]$_.AttributeOf)
    })
    $expectedNames = @($Table.primaryName.logicalName) + @(
        $Table.columns | Where-Object type -ne 'Lookup' | ForEach-Object logicalName
    )
    if ((Compare-Object $expectedNames @($customAttributes | ForEach-Object LogicalName)).Count -ne 0) {
        throw 'Existing Call Log non-lookup attribute inventory differs from the approved pre-relationship state.'
    }
    $primary = @($customAttributes | Where-Object LogicalName -CEQ $Table.primaryName.logicalName)
    if ($primary.Count -ne 1 -or $primary[0].AttributeType -cne 'String' -or
        [int]$primary[0].MaxLength -ne [int]$Table.primaryName.maxLength -or
        [string]$primary[0].FormatName.Value -cne [string]$Table.primaryName.formatName -or
        [string]$primary[0].AutoNumberFormat -cne [string]$Table.primaryName.format -or
        $primary[0].IsPrimaryName -ne $true) {
        throw 'Existing Call Log AutoNumber primary-name metadata differs from the approved manifest.'
    }

    foreach ($column in @($Table.columns | Where-Object type -ne 'Lookup')) {
        $field = @($customAttributes | Where-Object LogicalName -CEQ $column.logicalName)
        $expectedType = switch ([string]$column.type) {
            'String' { 'String' }
            'Memo' { 'Memo' }
            'DateTime' { 'DateTime' }
            'GlobalChoice' { 'Picklist' }
            default { throw 'Resume encountered an unsupported Call Log non-lookup column type.' }
        }
        if ($field.Count -ne 1 -or $field[0].AttributeType -cne $expectedType -or
            $field[0].RequiredLevel.Value -cne $(if (Get-Required -Requirement ([string]$column.required)) {
                'ApplicationRequired'
            } else {
                'None'
            })) {
            throw "Existing Call Log column $($column.logicalName) type or requiredness differs from the manifest."
        }
        if ($column.type -in @('String', 'Memo') -and [int]$field[0].MaxLength -ne [int]$column.maxLength) {
            throw "Existing Call Log column $($column.logicalName) length differs from the manifest."
        }
        if ($column.type -eq 'GlobalChoice') {
            $filter = [Uri]::EscapeDataString("LogicalName eq '$($column.logicalName)'")
            $picklist = @(Get-ODataRows -Path "EntityDefinitions(LogicalName='$name')/Attributes/Microsoft.Dynamics.CRM.PicklistAttributeMetadata?`$select=LogicalName&`$filter=$filter&`$expand=GlobalOptionSet" |
                Where-Object LogicalName -CEQ $column.logicalName)
            if ($picklist.Count -ne 1 -or
                [string]$picklist[0].GlobalOptionSet.Name -cne $script:ChoiceName) {
                throw "Existing Call Log Choice binding for $($column.logicalName) differs from the approved Choice."
            }
        }
    }

    $solutionFilter = [Uri]::EscapeDataString("_solutionid_value eq $($script:Solution.solutionid)")
    $components = @(Get-ODataRows -Path "solutioncomponents?`$select=componenttype,objectid,rootcomponentbehavior&`$filter=$solutionFilter")
    $tableRoots = @($components | Where-Object {
        [string]$_.objectid -ieq [string]$metadata.MetadataId -and [int]$_.componenttype -eq 1
    })
    $choiceRoots = @($components | Where-Object {
        [string]$_.objectid -ieq [string]$Choice.MetadataId -and [int]$_.componenttype -eq 9
    })
    if ($tableRoots.Count -ne 1 -or [int]$tableRoots[0].rootcomponentbehavior -ne 0 -or
        $choiceRoots.Count -ne 1) {
        throw 'Existing Call Log or Call Outcome Choice Solution membership differs from the approved root-component baseline.'
    }

    $relationships = @(Get-ODataRows -Path "EntityDefinitions(LogicalName='$name')/ManyToOneRelationships?`$select=SchemaName")
    if (@($relationships | Where-Object {
            [string]$_.SchemaName -like 'os_sr_*' -or [string]$_.SchemaName -in $script:RelationshipNames
        }).Count -ne 0) {
        throw 'Existing Call Log has an unexpected project relationship before the approved resume.'
    }
    $keys = @(Get-ODataRows -Path "EntityDefinitions(LogicalName='$name')/Keys?`$select=SchemaName")
    if ($keys.Count -ne 0) {
        throw 'Existing Call Log has an unexpected key before the approved resume.'
    }
}

function Assert-InitialState {
    $who = Invoke-DataverseRequest -Method GET -Path 'WhoAmI'
    if ([string]$who.OrganizationId -ine $ExpectedOrganizationId -or
        [string]$who.UserId -ine $script:ExpectedUserId -or
        [Environment]::GetEnvironmentVariable('BSO_RS_EXPECTED_USER_ID', 'Process') -cne $script:ExpectedUserId) {
        throw 'PAC, Dataverse WhoAmI, and process-scoped user guard do not agree.'
    }
    $publishers = @(Get-ODataRows -Path "publishers?`$select=publisherid,uniquename,customizationprefix,customizationoptionvalueprefix&`$filter=uniquename eq '$($script:PublisherName)'")
    $solutions = @(Get-ODataRows -Path "solutions?`$select=solutionid,uniquename,ismanaged,_publisherid_value&`$filter=uniquename eq '$($script:SolutionName)'")
    if ($publishers.Count -ne 1 -or $publishers[0].customizationprefix -cne $script:PublisherPrefix -or
        [int]$publishers[0].customizationoptionvalueprefix -le 0 -or
        $solutions.Count -ne 1 -or [bool]$solutions[0].ismanaged -or
        [string]$solutions[0]._publisherid_value -ine [string]$publishers[0].publisherid) {
        throw 'Exact unmanaged Solution, Publisher, or Publisher option-value prefix failed reconciliation.'
    }
    $script:Publisher = $publishers[0]
    $script:Solution = $solutions[0]
    $script:CurrentStage = 'CALL_OUTCOME_CHOICE_READ'
    $choice = Get-OptionalMetadata -Path "GlobalOptionSetDefinitions(Name='$($script:ChoiceName)')"
    if ($null -eq $choice) {
        throw 'The previously created Call Outcome Choice is absent; do not recreate it in this corrected continuation.'
    }
    $null = Assert-Choice -Choice $choice
    if ($ResumeRemainingScope) {
        foreach ($expectedOption in $manifest.callOutcomeChoice.options) {
            $liveOption = @($choice.Options | Where-Object {
                $_.Label.UserLocalizedLabel.Label -ceq $expectedOption.label
            })
            if ($liveOption.Count -ne 1 -or [int]$liveOption[0].Value -ne [int]$expectedOption.value) {
                throw 'The existing Call Outcome Choice mapping differs from the frozen manifest.'
            }
        }
    }
    Assert-GlobalPrivileges
    foreach ($relationName in $script:RelationshipNames) {
        $escapedName = $relationName.Replace("'", "''")
        $existing = @(Get-ODataRows -Path "RelationshipDefinitions?`$select=SchemaName&`$filter=SchemaName eq '$escapedName'")
        if (@($existing | Where-Object SchemaName -CEQ $relationName).Count -ne 0) {
            throw "Relationship schema name $relationName already exists; no child schema write is authorized."
        }
    }
    $candidate = Invoke-DataverseRequest -Method GET -Path "EntityDefinitions(LogicalName='os_sr_cand')?`$select=LogicalName,PrimaryIdAttribute,MetadataId,OwnershipType,IsAuditEnabled"
    if ($candidate.LogicalName -cne 'os_sr_cand' -or $candidate.OwnershipType -cne 'UserOwned' -or
        $candidate.IsAuditEnabled.Value -ne $true) {
        throw 'Candidate identity, ownership, or audit metadata does not match the approved baseline.'
    }
    $excluded = @(Get-ODataRows -Path "EntityDefinitions(LogicalName='os_sr_cand')/ManyToOneRelationships")
    $candidateStatus = Get-OptionalMetadata -Path "GlobalOptionSetDefinitions(Name='os_sr_candstat')"
    if ($null -eq $candidateStatus -or $candidateStatus.IsGlobal -ne $true) {
        throw 'The reconciled Candidate Status Choice is unavailable.'
    }
    if ($ResumeRemainingScope) {
        $script:CurrentStage = 'CALL_LOG_RESUME_RECONCILIATION'
        Assert-CallLogResumeReadback -Table (@($manifest.tables | Where-Object logicalName -CEQ 'os_sr_call')[0]) -Choice $choice
        $history = Get-OptionalMetadata -Path "EntityDefinitions(LogicalName='os_sr_csh')?`$select=LogicalName,MetadataId"
        if ($null -ne $history) {
            throw 'Candidate Status History already exists; no create or replacement is authorized by resume.'
        }
    } else {
        Assert-ChildTableAbsent
    }
    $systemUser = Invoke-DataverseRequest -Method GET -Path "EntityDefinitions(LogicalName='systemuser')?`$select=LogicalName,PrimaryIdAttribute"
    if ($systemUser.LogicalName -cne 'systemuser' -or $systemUser.PrimaryIdAttribute -cne 'systemuserid') {
        throw 'System User primary key metadata did not reconcile.'
    }
    $script:CurrentStage = 'ORGANIZATION_AUDIT_READ'
    $organization = Invoke-DataverseRequest -Method GET -Path "organizations($ExpectedOrganizationId)?`$select=organizationid,isauditenabled"
    if ([string]$organization.organizationid -ine $ExpectedOrganizationId) {
        throw 'Organization audit response target did not match the approved organization.'
    }
    if ($ResumeRemainingScope) {
        $script:ExpectedTableCreateNames = @('os_sr_csh')
        $script:ExpectedRelationshipNames = $script:RelationshipNames
        $script:ExpectedKeyNames = $script:KeyNames
        $script:ExpectedWritePaths = @('EntityDefinitions')
        $script:ExpectedWritePaths += @('RelationshipDefinitions', 'RelationshipDefinitions', 'RelationshipDefinitions', 'RelationshipDefinitions')
        $script:ExpectedWritePaths += @(
            "EntityDefinitions(LogicalName='os_sr_call')/Keys",
            "EntityDefinitions(LogicalName='os_sr_csh')/Keys"
        )
    } else {
        $script:ExpectedTableCreateNames = @('os_sr_call', 'os_sr_csh')
        $script:ExpectedRelationshipNames = $script:RelationshipNames
        $script:ExpectedKeyNames = $script:KeyNames
        $script:ExpectedWritePaths = @('EntityDefinitions', 'EntityDefinitions')
        $script:ExpectedWritePaths += @('RelationshipDefinitions', 'RelationshipDefinitions', 'RelationshipDefinitions', 'RelationshipDefinitions')
        $script:ExpectedWritePaths += @(
            "EntityDefinitions(LogicalName='os_sr_call')/Keys",
            "EntityDefinitions(LogicalName='os_sr_csh')/Keys"
        )
    }
    $script:MaximumWrites = $script:ExpectedWritePaths.Count
    $script:RemainingScopeAuthorizationConsumed = [bool]$manifest.provisioning.phase3B2AuthorizedContinuation.remainingMetadataAuthorizationConsumed
    [pscustomobject]@{
        Candidate = $candidate
        SystemUser = $systemUser
        CandidateStatusChoice = $candidateStatus
        CallOutcomeChoice = $choice
        OrganizationAuditing = [bool]$organization.isauditenabled
    }
}

function Get-ReconciliationSnapshot {
    $who = Invoke-DataverseRequest -Method GET -Path 'WhoAmI'
    if ([string]$who.OrganizationId -ine $ExpectedOrganizationId -or
        [string]$who.UserId -ine $script:ExpectedUserId -or
        [Environment]::GetEnvironmentVariable('BSO_RS_EXPECTED_USER_ID', 'Process') -cne $script:ExpectedUserId) {
        throw 'PAC, Dataverse WhoAmI, and process-scoped user guard do not agree during reconciliation.'
    }
    $publishers = @(Get-ODataRows -Path "publishers?`$select=publisherid,uniquename,customizationprefix&`$filter=uniquename eq '$($script:PublisherName)'")
    $solutions = @(Get-ODataRows -Path "solutions?`$select=solutionid,uniquename,ismanaged,_publisherid_value&`$filter=uniquename eq '$($script:SolutionName)'")
    if ($publishers.Count -ne 1 -or $publishers[0].customizationprefix -cne $script:PublisherPrefix -or
        $solutions.Count -ne 1 -or [bool]$solutions[0].ismanaged -or
        [string]$solutions[0]._publisherid_value -ine [string]$publishers[0].publisherid) {
        throw 'Solution/Publisher guard failed during read-only reconciliation.'
    }
    $script:Solution = $solutions[0]
    $choice = Get-OptionalMetadata -Path "GlobalOptionSetDefinitions(Name='$($script:ChoiceName)')"
    $choiceOptions = @()
    if ($null -ne $choice) {
        $choiceOptions = @($choice.Options | ForEach-Object {
            [ordered]@{
                Label = [string]$_.Label.UserLocalizedLabel.Label
                Value = [int]$_.Value
            }
        })
    }
    $componentFilter = [Uri]::EscapeDataString("_solutionid_value eq $($script:Solution.solutionid)")
    $components = @(Get-ODataRows -Path "solutioncomponents?`$select=componenttype,objectid,rootcomponentbehavior&`$filter=$componentFilter")
    $choiceMembership = if ($null -eq $choice) { 0 } else {
        @($components | Where-Object {
            [string]$_.objectid -ieq [string]$choice.MetadataId -and [int]$_.componenttype -eq 9
        }).Count
    }
    $tables = @()
    $relationships = @()
    $keys = @()
    foreach ($name in $script:TableNames) {
        $table = Get-OptionalMetadata -Path "EntityDefinitions(LogicalName='$name')?`$select=LogicalName,MetadataId,OwnershipType,PrimaryNameAttribute,IsAuditEnabled"
        if ($null -ne $table) {
            $attributes = @(Get-ODataRows -Path "EntityDefinitions(LogicalName='$name')/Attributes")
            $primary = @($attributes | Where-Object LogicalName -CEQ $table.PrimaryNameAttribute)
            $customAttributes = @($attributes | Where-Object {
                [string]$_.LogicalName -like "$name`_*" -and
                [string]$_.AttributeType -cne 'Virtual' -and
                [string]::IsNullOrWhiteSpace([string]$_.AttributeOf)
            })
            $choiceBindings = @()
            foreach ($attribute in @($customAttributes | Where-Object AttributeType -CEQ 'Picklist')) {
                $filter = [Uri]::EscapeDataString("LogicalName eq '$($attribute.LogicalName)'")
                $picklist = @(Get-ODataRows -Path "EntityDefinitions(LogicalName='$name')/Attributes/Microsoft.Dynamics.CRM.PicklistAttributeMetadata?`$select=LogicalName&`$filter=$filter&`$expand=GlobalOptionSet" |
                    Where-Object LogicalName -CEQ $attribute.LogicalName)
                $choiceBindings += [ordered]@{
                    LogicalName = [string]$attribute.LogicalName
                    GlobalChoiceName = if ($picklist.Count -eq 1) {
                        [string]$picklist[0].GlobalOptionSet.Name
                    } else {
                        'NOT_FOUND_OR_AMBIGUOUS'
                    }
                }
            }
            $tableComponents = @($components | Where-Object {
                [string]$_.objectid -ieq [string]$table.MetadataId -and [int]$_.componenttype -eq 1
            })
            $tables += [ordered]@{
                LogicalName = [string]$table.LogicalName
                OwnershipType = [string]$table.OwnershipType
                PrimaryNameAttribute = [string]$table.PrimaryNameAttribute
                Auditing = [bool]$table.IsAuditEnabled.Value
                SolutionRootCount = $tableComponents.Count
                RootIncludesSubcomponents = ($tableComponents.Count -eq 1 -and [int]$tableComponents[0].rootcomponentbehavior -eq 0)
                PrimaryNameMetadata = if ($primary.Count -eq 1) {
                    [ordered]@{
                        AttributeType = [string]$primary[0].AttributeType
                        MaxLength = [int]$primary[0].MaxLength
                        FormatName = [string]$primary[0].FormatName.Value
                        AutoNumberFormat = [string]$primary[0].AutoNumberFormat
                        IsPrimaryName = [bool]$primary[0].IsPrimaryName
                    }
                } else { 'NOT_FOUND_OR_AMBIGUOUS' }
                Attributes = @($attributes | Where-Object {
                    [string]$_.LogicalName -like "$name`_*" -and
                    [string]$_.AttributeType -cne 'Virtual' -and
                    [string]::IsNullOrWhiteSpace([string]$_.AttributeOf)
                } | ForEach-Object { [string]$_.LogicalName })
                CustomAttributes = @($customAttributes | ForEach-Object {
                    [ordered]@{
                        LogicalName = [string]$_.LogicalName
                        AttributeType = [string]$_.AttributeType
                        MaxLength = if ($null -ne $_.MaxLength) { [int]$_.MaxLength } else { $null }
                        FormatName = [string]$_.FormatName.Value
                        AutoNumberFormat = [string]$_.AutoNumberFormat
                        RequiredLevel = [string]$_.RequiredLevel.Value
                    }
                })
                ChoiceBindings = $choiceBindings
            }
            $relationships += @(Get-ODataRows -Path "EntityDefinitions(LogicalName='$name')/ManyToOneRelationships?`$select=SchemaName,ReferencedEntity,ReferencingEntity,ReferencedAttribute,ReferencingAttribute,CascadeConfiguration" |
                ForEach-Object {
                    [ordered]@{
                        SchemaName = [string]$_.SchemaName
                        ReferencedEntity = [string]$_.ReferencedEntity
                        ReferencingEntity = [string]$_.ReferencingEntity
                        ReferencingAttribute = [string]$_.ReferencingAttribute
                        Delete = [string]$_.CascadeConfiguration.Delete
                        Assign = [string]$_.CascadeConfiguration.Assign
                        Share = [string]$_.CascadeConfiguration.Share
                        Reparent = [string]$_.CascadeConfiguration.Reparent
                    }
                })
            $keys += @(Get-ODataRows -Path "EntityDefinitions(LogicalName='$name')/Keys?`$select=SchemaName,KeyAttributes,EntityKeyIndexStatus" |
                ForEach-Object {
                    [ordered]@{
                        SchemaName = [string]$_.SchemaName
                        Attributes = @($_.KeyAttributes)
                        State = [string]$_.EntityKeyIndexStatus
                    }
                })
        }
        else {
            $tables += [ordered]@{ LogicalName = $name; State = 'ABSENT' }
        }
    }
    [ordered]@{
        Result = 'READ_ONLY_RECONCILIATION_COMPLETE'
        Candidate = $candidateResult.Result
        CallOutcomeChoice = if ($null -eq $choice) { 'ABSENT' } else { 'PRESENT' }
        CallOutcomeOptions = $choiceOptions
        CallOutcomeSolutionMembershipCount = $choiceMembership
        ChildTables = $tables
        Relationships = $relationships
        Keys = $keys
        OrganizationAuditing = if ((Invoke-DataverseRequest -Method GET -Path "organizations($ExpectedOrganizationId)?`$select=organizationid,isauditenabled").isauditenabled) {
            'ENABLED'
        } else {
            'DISABLED'
        }
        Requests = $script:RequestCounts
        Writes = $script:WriteStages.ToArray()
        AutomaticRetries = 0
    }
}

function New-CallOutcomeChoicePayload {
    [ordered]@{
        '@odata.type' = 'Microsoft.Dynamics.CRM.OptionSetMetadata'
        Name = $script:ChoiceName
        DisplayName = New-Label -Text 'Call Outcome'
        Description = New-Label -Text 'Approved initial Candidate call outcome taxonomy.'
        IsGlobal = $true
        OptionSetType = 'Picklist'
        Options = @($script:OutcomeLabels | ForEach-Object {
            [ordered]@{ Value = $null; Label = New-Label -Text $_ }
        })
    }
}

function Get-RelationshipPayload {
    param(
        [Parameter(Mandatory = $true)][object]$Relation,
        [Parameter(Mandatory = $true)][string]$ReferencedAttribute
    )
    $column = @($manifest.tables | Where-Object logicalName -CEQ $Relation.child).columns |
        Where-Object logicalName -CEQ $Relation.lookup
    if (@($column).Count -ne 1) { throw 'Relationship lookup does not map to one manifest column.' }
    [ordered]@{
        '@odata.type' = 'Microsoft.Dynamics.CRM.OneToManyRelationshipMetadata'
        SchemaName = [string]$Relation.schemaName
        ReferencedEntity = [string]$Relation.parent
        ReferencingEntity = [string]$Relation.child
        ReferencedAttribute = $ReferencedAttribute
        CascadeConfiguration = [ordered]@{
            Assign = 'NoCascade'
            Delete = 'Restrict'
            Merge = 'NoCascade'
            Reparent = 'NoCascade'
            Share = 'NoCascade'
            Unshare = 'NoCascade'
            RollupView = 'NoCascade'
        }
        Lookup = [ordered]@{
            '@odata.type' = 'Microsoft.Dynamics.CRM.LookupAttributeMetadata'
            SchemaName = [string]$Relation.lookup
            DisplayName = New-Label -Text ([string]$column.displayName)
            RequiredLevel = New-RequiredLevel -Required $true
        }
    }
}

function Assert-TableReadback {
    param(
        [Parameter(Mandatory = $true)][object]$Table,
        [Parameter(Mandatory = $true)][object]$Choice,
        [switch]$AllowKnownStatusChoiceMismatch
    )
    $name = [string]$Table.logicalName
    $metadata = Get-OptionalMetadata -Path "EntityDefinitions(LogicalName='$name')?`$select=LogicalName,MetadataId,EntitySetName,OwnershipType,PrimaryIdAttribute,PrimaryNameAttribute,IsAuditEnabled"
    if ($null -eq $metadata -or $metadata.LogicalName -cne $name -or
        $metadata.OwnershipType -cne 'UserOwned' -or
        $metadata.PrimaryNameAttribute -cne $Table.primaryName.logicalName -or
        $metadata.IsAuditEnabled.Value -ne $true) {
        throw "Created child table $name failed identity, ownership, primary-name, or audit reconciliation."
    }
    $primary = @(Get-ODataRows -Path "EntityDefinitions(LogicalName='$name')/Attributes" |
        Where-Object LogicalName -CEQ $Table.primaryName.logicalName)
    if ($primary.Count -ne 1 -or
        [string]$primary[0].SchemaName -cne [string]$Table.primaryName.logicalName -or
        [string]$primary[0].DisplayName.UserLocalizedLabel.Label -cne [string]$Table.primaryName.displayName -or
        [int]$primary[0].MaxLength -ne [int]$Table.primaryName.maxLength -or
        [string]$primary[0].FormatName.Value -cne [string]$Table.primaryName.formatName -or
        [string]$primary[0].AutoNumberFormat -cne [string]$Table.primaryName.format -or
        [string]$primary[0].RequiredLevel.Value -cne 'ApplicationRequired' -or
        $primary[0].IsPrimaryName -ne $true) {
        throw "Created child table $name primary-name String/AutoNumber metadata did not reconcile."
    }
    $filter = [Uri]::EscapeDataString("_solutionid_value eq $($script:Solution.solutionid)")
    $components = @(Get-ODataRows -Path "solutioncomponents?`$select=componenttype,objectid,rootcomponentbehavior&`$filter=$filter")
    $roots = @($components | Where-Object {
        [string]$_.objectid -ieq [string]$metadata.MetadataId -and [int]$_.componenttype -eq 1
    })
    if ($roots.Count -ne 1 -or [int]$roots[0].rootcomponentbehavior -ne 0) {
        throw "Created child table $name is not included as an exact root with subcomponents in the approved Solution."
    }
    $attributes = @(Get-ODataRows -Path "EntityDefinitions(LogicalName='$name')/Attributes")
    $actual = @($attributes | Where-Object {
        [string]$_.LogicalName -like "$name`_*" -and
        [string]$_.AttributeType -cne 'Virtual' -and
        [string]::IsNullOrWhiteSpace([string]$_.AttributeOf)
    })
    $expectedNames = @($Table.primaryName.logicalName) + @($Table.columns | ForEach-Object logicalName)
    if ((Compare-Object $expectedNames @($actual | ForEach-Object LogicalName)).Count -ne 0) {
        throw "Created child table $name custom attribute inventory did not reconcile exactly."
    }
    foreach ($column in $Table.columns) {
        $field = @($actual | Where-Object LogicalName -CEQ $column.logicalName)
        if ($field.Count -ne 1) { throw "Expected column $($column.logicalName) was not found exactly once." }
        $expectedType = switch ([string]$column.type) {
            'String' { 'String' }
            'Memo' { 'Memo' }
            'DateTime' { 'DateTime' }
            'GlobalChoice' { 'Picklist' }
            'Lookup' { 'Lookup' }
        }
        if ($field[0].AttributeType -cne $expectedType) {
            throw "Column $($column.logicalName) type did not reconcile."
        }
        if ([string]$field[0].SchemaName -cne [string]$column.logicalName -or
            [string]$field[0].DisplayName.UserLocalizedLabel.Label -cne [string]$column.displayName -or
            [string]$field[0].RequiredLevel.Value -cne $(if (Get-Required -Requirement ([string]$column.required)) {
                'ApplicationRequired'
            } else {
                'None'
            })) {
            throw "Column $($column.logicalName) schema, display label, or requiredness did not reconcile."
        }
        if ($column.type -eq 'String' -and [int]$field[0].MaxLength -ne [int]$column.maxLength) {
            throw "Column $($column.logicalName) max length did not reconcile."
        }
        if ($column.type -eq 'Memo' -and [int]$field[0].MaxLength -ne [int]$column.maxLength) {
            throw "Column $($column.logicalName) memo max length did not reconcile."
        }
        if ($column.type -eq 'String') {
            $expectedFormat = if ($column.format -in @('Email', 'Phone', 'Url')) {
                [string]$column.format
            } else { 'Text' }
            if ([string]$field[0].FormatName.Value -cne $expectedFormat) {
                throw "Column $($column.logicalName) format did not reconcile."
            }
        }
    }
    foreach ($column in @($Table.columns | Where-Object type -eq 'GlobalChoice')) {
        $filter = [Uri]::EscapeDataString("LogicalName eq '$($column.logicalName)'")
        $picklist = @(Get-ODataRows -Path "EntityDefinitions(LogicalName='$name')/Attributes/Microsoft.Dynamics.CRM.PicklistAttributeMetadata?`$select=LogicalName,MetadataId&`$filter=$filter&`$expand=GlobalOptionSet" |
            Where-Object LogicalName -CEQ $column.logicalName)
        $knownMismatchIsAllowed = $false
        if ($picklist.Count -eq 1) {
            $knownMismatchIsAllowed = $AllowKnownStatusChoiceMismatch -and
                $name -ceq 'os_sr_csh' -and
                $column.logicalName -in $script:RepairAllowedColumns -and
                [string]$picklist[0].GlobalOptionSet.Name -ceq $script:ChoiceName
        }
        if ($picklist.Count -ne 1 -or
            ([string]$picklist[0].GlobalOptionSet.Name -cne [string]$column.target -and
                -not $knownMismatchIsAllowed)) {
            throw "Global Choice binding for $($column.logicalName) did not reconcile."
        }
    }
    [pscustomobject]@{ Metadata = $metadata; Root = $roots[0]; Attributes = $actual }
}

function Assert-TableCreateReadback {
    param([Parameter(Mandatory = $true)][object]$Table)
    $name = [string]$Table.logicalName
    $metadata = Get-OptionalMetadata -Path "EntityDefinitions(LogicalName='$name')?`$select=LogicalName,MetadataId,OwnershipType,PrimaryNameAttribute,IsAuditEnabled"
    if ($null -eq $metadata -or $metadata.LogicalName -cne $name -or
        $metadata.OwnershipType -cne 'UserOwned' -or
        $metadata.PrimaryNameAttribute -cne $Table.primaryName.logicalName -or
        $metadata.IsAuditEnabled.Value -ne $true) {
        throw "Immediate readback did not verify the created table identity, ownership, primary name, and audit flag for $name."
    }
    $filter = [Uri]::EscapeDataString("LogicalName eq '$($Table.primaryName.logicalName)'")
    $primary = @(Get-ODataRows -Path "EntityDefinitions(LogicalName='$name')/Attributes/Microsoft.Dynamics.CRM.StringAttributeMetadata?`$select=LogicalName,MaxLength,FormatName,AutoNumberFormat,IsPrimaryName&`$filter=$filter")
    if ($primary.Count -ne 1 -or
        $primary[0].LogicalName -cne $Table.primaryName.logicalName -or
        [int]$primary[0].MaxLength -ne [int]$Table.primaryName.maxLength -or
        [string]$primary[0].FormatName.Value -cne [string]$Table.primaryName.formatName -or
        [string]$primary[0].AutoNumberFormat -cne [string]$Table.primaryName.format -or
        $primary[0].IsPrimaryName -ne $true) {
        throw "Immediate readback did not verify the corrected AutoNumber primary-name metadata for $name."
    }
    [pscustomobject]@{
        LogicalName = $name
        PrimaryName = [string]$primary[0].LogicalName
        MaxLength = [int]$primary[0].MaxLength
        FormatName = [string]$primary[0].FormatName.Value
        AutoNumberFormat = [string]$primary[0].AutoNumberFormat
        TableAuditEnabled = $true
    }
}

function Assert-RelationshipsAndKeys {
    foreach ($name in $script:TableNames) {
        $relationships = @(Get-ODataRows -Path "EntityDefinitions(LogicalName='$name')/ManyToOneRelationships?`$select=SchemaName,ReferencedEntity,ReferencingEntity,ReferencedAttribute,ReferencingAttribute,CascadeConfiguration")
        $expectedDefinitions = @($manifest.relationships | Where-Object child -CEQ $name)
        $expected = @($expectedDefinitions | ForEach-Object schemaName)
        $actualProjectRelationships = @($relationships | Where-Object {
            [string]$_.SchemaName -like 'os_sr_*'
        } | ForEach-Object SchemaName)
        if ((Compare-Object $expected $actualProjectRelationships).Count -ne 0) {
            throw "Project relationship inventory for $name differs from the approved manifest."
        }
        foreach ($definition in $expectedDefinitions) {
            $relationshipName = [string]$definition.schemaName
            $referencedAttribute = if ([string]$definition.parent -ceq 'systemuser') {
                'systemuserid'
            } else {
                $parent = Get-OptionalMetadata -Path "EntityDefinitions(LogicalName='$($definition.parent)')?`$select=PrimaryIdAttribute"
                if ($null -eq $parent) { throw "Relationship parent $($definition.parent) is absent." }
                [string]$parent.PrimaryIdAttribute
            }
            $match = @($relationships | Where-Object SchemaName -CEQ $relationshipName)
            if ($match.Count -ne 1 -or $match[0].CascadeConfiguration.Delete -cne 'Restrict' -or
                $match[0].CascadeConfiguration.Assign -cne 'NoCascade' -or
                $match[0].CascadeConfiguration.Share -cne 'NoCascade' -or
                $match[0].CascadeConfiguration.Reparent -cne 'NoCascade' -or
                [string]$match[0].ReferencedEntity -cne [string]$definition.parent -or
                [string]$match[0].ReferencingEntity -cne [string]$definition.child -or
                [string]$match[0].ReferencingAttribute -cne [string]$definition.lookup -or
                [string]$match[0].ReferencedAttribute -cne $referencedAttribute) {
                throw "Relationship $relationshipName did not reconcile to the manifest."
            }
        }
    }
    $keys = [System.Collections.Generic.List[object]]::new()
    foreach ($name in $script:TableNames) {
        $table = @($manifest.tables | Where-Object logicalName -CEQ $name)[0]
        $actual = @(Get-ODataRows -Path "EntityDefinitions(LogicalName='$name')/Keys")
        $expectedNames = @($table.alternateKeys | ForEach-Object name)
        $actualProjectKeys = @($actual | Where-Object {
            [string]$_.SchemaName -like 'os_sr_*'
        } | ForEach-Object SchemaName)
        if ((Compare-Object $expectedNames $actualProjectKeys).Count -ne 0) {
            throw "Project alternate-key inventory for $name differs from the approved manifest."
        }
        foreach ($definition in $table.alternateKeys) {
            $match = @($actual | Where-Object SchemaName -CEQ $definition.name)
            if ($match.Count -ne 1 -or [string]$match[0].EntityKeyIndexStatus -cne 'Active' -or
                (Compare-Object @($definition.columns) @($match[0].KeyAttributes)).Count -ne 0) {
                throw "Alternate key $($definition.name) did not reconcile as Active with exact attributes."
            }
            $keys.Add([ordered]@{ Name = $definition.name; State = [string]$match[0].EntityKeyIndexStatus })
        }
    }
    $keys.ToArray()
}

function Get-ChoiceOptionsForRepair {
    param(
        [Parameter(Mandatory = $true)][object]$Choice,
        [Parameter(Mandatory = $true)][object[]]$ExpectedOptions,
        [Parameter(Mandatory = $true)][string]$ExpectedName
    )
    if ($Choice.Name -cne $ExpectedName -or $Choice.IsGlobal -ne $true -or
        [string]$Choice.OptionSetType -cne 'Picklist' -or
        (Compare-Object @($ExpectedOptions | ForEach-Object label) @(
            $Choice.Options | ForEach-Object { [string]$_.Label.UserLocalizedLabel.Label }
        )).Count -ne 0) {
        throw "Global Choice $ExpectedName differs from the current approved manifest."
    }
    $options = @($Choice.Options | ForEach-Object {
        [pscustomobject]@{
            Label = [string]$_.Label.UserLocalizedLabel.Label
            Value = [int]$_.Value
        }
    })
    foreach ($expected in $ExpectedOptions) {
        $actual = @($options | Where-Object Label -CEQ $expected.label)
        if ($actual.Count -ne 1 -or $actual[0].Value -ne [int]$expected.value) {
            throw "Global Choice $ExpectedName option values differ from the current approved manifest."
        }
    }
    $options
}

function Get-StatusChoiceAttribute {
    param([Parameter(Mandatory = $true)][string]$LogicalName)
    $filter = [Uri]::EscapeDataString("LogicalName eq '$LogicalName'")
    $matches = @(Get-ODataRows -Path "EntityDefinitions(LogicalName='os_sr_csh')/Attributes/Microsoft.Dynamics.CRM.PicklistAttributeMetadata?`$filter=$filter&`$expand=OptionSet,GlobalOptionSet" |
        Where-Object LogicalName -CEQ $LogicalName)
    if ($matches.Count -ne 1) {
        throw "Picklist metadata for $LogicalName did not resolve to exactly one definition."
    }
    $matches[0]
}

function Assert-StatusChoiceColumn {
    param(
        [Parameter(Mandatory = $true)][object]$Attribute,
        [Parameter(Mandatory = $true)][object]$ManifestColumn,
        [Parameter(Mandatory = $true)][string]$ExpectedChoiceName,
        [Parameter(Mandatory = $true)][object]$ExpectedChoice
    )
    $label = [string]$Attribute.DisplayName.UserLocalizedLabel.Label
    $failedChecks = [System.Collections.Generic.List[string]]::new()
    if ([string]$Attribute.MetadataId -notmatch '^[0-9a-fA-F-]{36}$') { $failedChecks.Add('MetadataId') }
    if ($Attribute.LogicalName -cne $ManifestColumn.logicalName) { $failedChecks.Add('LogicalName') }
    if ($Attribute.SchemaName -cne $ManifestColumn.logicalName) { $failedChecks.Add('SchemaName') }
    if ($Attribute.AttributeType -cne 'Picklist') { $failedChecks.Add('AttributeType') }
    if ($Attribute.AttributeTypeName.Value -cne 'PicklistType') { $failedChecks.Add('AttributeTypeName') }
    if ($Attribute.IsCustomAttribute -ne $true) { $failedChecks.Add('IsCustomAttribute') }
    if ($Attribute.IsManaged -ne $false) { $failedChecks.Add('IsManaged') }
    if ($Attribute.IsCustomizable.Value -ne $true) { $failedChecks.Add('IsCustomizable') }
    if ($label -cne $ManifestColumn.displayName) { $failedChecks.Add('DisplayName') }
    if ($Attribute.RequiredLevel.Value -cne 'ApplicationRequired') { $failedChecks.Add('RequiredLevel') }
    if ($Attribute.IsPrimaryName -ne $false) { $failedChecks.Add('IsPrimaryName') }
    if ($Attribute.GlobalOptionSet.Name -cne $ExpectedChoiceName) { $failedChecks.Add('GlobalOptionSet.Name') }
    if ([string]$Attribute.GlobalOptionSet.MetadataId -ine [string]$ExpectedChoice.MetadataId) {
        $failedChecks.Add('GlobalOptionSet.MetadataId')
    }
    if ($null -ne $ManifestColumn.defaultValue -and
        [int]$Attribute.DefaultFormValue -ne [int]$ManifestColumn.defaultValue) {
        $failedChecks.Add('DefaultFormValue')
    }
    $actualOptionMappings = @($Attribute.GlobalOptionSet.Options | ForEach-Object {
        "$([string]$_.Label.UserLocalizedLabel.Label)|$([int]$_.Value)"
    })
    $expectedOptionMappings = @($ExpectedChoice.Options | ForEach-Object {
        "$([string]$_.Label.UserLocalizedLabel.Label)|$([int]$_.Value)"
    })
    if ((Compare-Object $expectedOptionMappings $actualOptionMappings).Count -ne 0) {
        $failedChecks.Add('GlobalOptionSet.Options')
    }
    if ($failedChecks.Count -gt 0) {
        throw "Status Choice column $($ManifestColumn.logicalName) failed readback checks: $($failedChecks -join ', '); observed binding '$($Attribute.GlobalOptionSet.Name)'."
    }
}

function New-StatusChoiceBindingUpdatePayload {
    param(
        [Parameter(Mandatory = $true)][object]$Attribute,
        [Parameter(Mandatory = $true)][string]$TargetMetadataId
    )
    if ([string]$Attribute.LogicalName -notin $script:RepairAllowedColumns -or
        [string]$Attribute.MetadataId -notmatch '^[0-9a-fA-F-]{36}$' -or
        $TargetMetadataId -notmatch '^[0-9a-fA-F-]{36}$' -or
        [string]$Attribute.GlobalOptionSet.Name -cne $script:ChoiceName) {
        throw 'Refusing to build an in-place binding payload outside the two approved Status History columns.'
    }
    $payload = ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $Attribute -Depth 80 -Compress) -AsHashtable
    if ($payload -isnot [System.Collections.IDictionary] -or
        [string]$payload.LogicalName -cne [string]$Attribute.LogicalName -or
        [string]$payload.SchemaName -cne [string]$Attribute.SchemaName) {
        throw 'Full Picklist metadata could not be safely round-tripped for replacement.'
    }
    $payload.Remove('@odata.context')
    $payload.Remove('@odata.etag')
    $payload.Remove('GlobalOptionSet')
    $payload.Remove('OptionSet')
    $payload['@odata.type'] = 'Microsoft.Dynamics.CRM.PicklistAttributeMetadata'
    $payload['GlobalOptionSet@odata.bind'] = "/GlobalOptionSetDefinitions($TargetMetadataId)"
    $payload
}

function Get-StatusChoiceAttributePath {
    param([Parameter(Mandatory = $true)][object]$Attribute)
    if ([string]$Attribute.LogicalName -notin $script:RepairAllowedColumns -or
        [string]$Attribute.MetadataId -notmatch '^[0-9a-fA-F-]{36}$') {
        throw 'Refusing to target an attribute outside the manifest-resolved repair set.'
    }
    "EntityDefinitions(LogicalName='os_sr_csh')/Attributes($($Attribute.MetadataId))"
}

function Get-MetadataIdFingerprint {
    param([AllowNull()][string]$MetadataId)
    if ([string]::IsNullOrWhiteSpace($MetadataId)) { return $null }
    Get-Sha256 -Bytes ([Text.Encoding]::UTF8.GetBytes($MetadataId.ToLowerInvariant()))
}

function Get-StatusChoicePreservationFingerprint {
    param([Parameter(Mandatory = $true)][object]$Attribute)
    $snapshot = ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $Attribute -Depth 80 -Compress) -AsHashtable
    foreach ($property in @(
        '@odata.context',
        '@odata.etag',
        'GlobalOptionSet',
        'OptionSet',
        'ModifiedOn',
        'HasChanged'
    )) {
        $snapshot.Remove($property)
    }
    Get-Sha256 -Bytes ([Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $snapshot -Depth 80 -Compress)))
}

function Get-StatusChoiceRepairPreflightResult {
    param(
        [Parameter(Mandatory = $true)][object]$Manifest,
        [Parameter(Mandatory = $true)][object]$CandidateResult
    )
    $preflight = Assert-StatusChoiceRepairPreflight -Manifest $Manifest
    $attributeSummaries = foreach ($column in $preflight.Columns) {
        $attribute = $preflight.Attributes[[string]$column.logicalName]
        $payload = New-StatusChoiceBindingUpdatePayload -Attribute $attribute `
            -TargetMetadataId ([string]$preflight.CandidateStatusChoice.MetadataId)
        [ordered]@{
            DisplayName = [string]$column.displayName
            LogicalName = [string]$attribute.LogicalName
            SchemaName = [string]$attribute.SchemaName
            AttributeMetadataIdSha256 = Get-MetadataIdFingerprint -MetadataId ([string]$attribute.MetadataId)
            AttributeType = [string]$attribute.AttributeType
            AttributeTypeName = [string]$attribute.AttributeTypeName.Value
            RequiredLevel = [string]$attribute.RequiredLevel.Value
            DefaultFormValue = $attribute.DefaultFormValue
            IsManaged = [bool]$attribute.IsManaged
            IsCustomizable = [bool]$attribute.IsCustomizable.Value
            IsAuditEnabled = [bool]$attribute.IsAuditEnabled.Value
            IsSecured = [bool]$attribute.IsSecured
            OptionSet = [ordered]@{
                Name = [string]$attribute.OptionSet.Name
                MetadataIdSha256 = Get-MetadataIdFingerprint -MetadataId ([string]$attribute.OptionSet.MetadataId)
            }
            GlobalOptionSet = [ordered]@{
                Name = [string]$attribute.GlobalOptionSet.Name
                MetadataIdSha256 = Get-MetadataIdFingerprint -MetadataId ([string]$attribute.GlobalOptionSet.MetadataId)
                Options = @($attribute.GlobalOptionSet.Options | ForEach-Object {
                    [ordered]@{
                        Label = [string]$_.Label.UserLocalizedLabel.Label
                        Value = [int]$_.Value
                    }
                })
            }
            CorrectedPayloadSha256 = Get-Sha256 -Bytes ([Text.Encoding]::UTF8.GetBytes(
                (ConvertTo-Json -InputObject $payload -Depth 80 -Compress)
            ))
        }
    }
    [ordered]@{
        Result = 'READ_ONLY_STATUS_CHOICE_REPAIR_PREFLIGHT_PASSED'
        ManifestSha256 = Get-ManifestHash
        Target = 'Owner-confirmed VN LMV IT organization URL matched PAC and Dataverse'
        CredentialSource = 'Existing Az.Accounts context via Get-AzAccessToken; PAC identity agreement validated'
        IdentityGuard = 'Dataverse WhoAmI matched PAC user, organization, and process-scoped expected-user pin'
        SolutionPublisher = 'Approved unmanaged Solution and os Publisher prefix reconciled'
        Candidate = $CandidateResult.Result
        CandidateStatusChoice = [ordered]@{
            Name = [string]$preflight.CandidateStatusChoice.Name
            MetadataIdSha256 = Get-MetadataIdFingerprint -MetadataId ([string]$preflight.CandidateStatusChoice.MetadataId)
            Options = @($Manifest.globalChoice.options | ForEach-Object {
                [ordered]@{ Label = [string]$_.label; Value = [int]$_.value }
            })
        }
        CallOutcomeChoice = [ordered]@{
            Name = [string]$preflight.CallOutcomeChoice.Name
            MetadataIdSha256 = Get-MetadataIdFingerprint -MetadataId ([string]$preflight.CallOutcomeChoice.MetadataId)
            Options = @($Manifest.callOutcomeChoice.options | ForEach-Object {
                [ordered]@{ Label = [string]$_.label; Value = [int]$_.value }
            })
        }
        CallLog = 'EXACT_SCHEMA_AUDIT_SOLUTION_RELATIONSHIPS_AND_KEYS'
        CandidateStatusHistory = 'EXACT_EXCEPT_TWO_APPROVED_CHOICE_BINDINGS'
        CandidateStatusHistoryRows = [long]$preflight.InitialRowCount
        Attributes = @($attributeSummaries)
        RelationshipAndKeyChecks = 'EXACT_MANIFEST_INVENTORY_AND_CONFIGURATION'
        Requests = [ordered]@{
            CandidateReconciliationGET = [int]$CandidateResult.Requests.GET
            ChildScopeGET = [int]$script:RequestCounts.GET
            ChildScopePUT = 0
            ChildScopePOST = 0
        }
        Writes = @()
        AutomaticRetries = 0
    }
}

function Get-CandidateStatusHistoryRowCount {
    param([Parameter(Mandatory = $true)][string]$EntitySetName, [Parameter(Mandatory = $true)][string]$PrimaryIdAttribute)
    $fetchXml = "<fetch aggregate='true'><entity name='os_sr_csh'><attribute name='$PrimaryIdAttribute' alias='record_count' aggregate='count' /></entity></fetch>"
    $path = $EntitySetName + '?fetchXml=' + [Uri]::EscapeDataString($fetchXml)
    $response = Invoke-DataverseRequest -Method GET -Path $path
    $rows = @($response.value)
    if ($rows.Count -ne 1 -or $null -eq $rows[0].record_count) {
        throw 'Candidate Status History aggregate count did not return exactly one scalar result.'
    }
    [long]$rows[0].record_count
}

function Assert-StatusChoiceRepairPreflight {
    param([Parameter(Mandatory = $true)][object]$Manifest)
    $who = Invoke-DataverseRequest -Method GET -Path 'WhoAmI'
    if ([string]$who.OrganizationId -ine $ExpectedOrganizationId -or
        [string]$who.UserId -ine $script:ExpectedUserId -or
        [Environment]::GetEnvironmentVariable('BSO_RS_EXPECTED_USER_ID', 'Process') -cne $script:ExpectedUserId) {
        throw 'PAC, Dataverse WhoAmI, and process-scoped identity guard do not agree.'
    }

    $publisher = @(Get-ODataRows -Path "publishers?`$select=publisherid,uniquename,customizationprefix&`$filter=uniquename eq '$($script:PublisherName)'")
    $solutions = @(Get-ODataRows -Path "solutions?`$select=solutionid,uniquename,ismanaged,_publisherid_value&`$filter=uniquename eq '$($script:SolutionName)'")
    if ($publisher.Count -ne 1 -or $publisher[0].customizationprefix -cne $script:PublisherPrefix -or
        $solutions.Count -ne 1 -or [bool]$solutions[0].ismanaged -or
        [string]$solutions[0]._publisherid_value -ine [string]$publisher[0].publisherid) {
        throw 'Approved Solution and Publisher do not reconcile for metadata repair.'
    }
    $script:Solution = $solutions[0]

    $targetChoiceName = [string]$Manifest.globalChoice.logicalName
    if ($targetChoiceName -cne 'os_sr_candstat') { throw 'Manifest Candidate Status Choice identity is not exact.' }
    $targetChoice = Get-OptionalMetadata -Path "GlobalOptionSetDefinitions(Name='$targetChoiceName')"
    $wrongChoice = Get-OptionalMetadata -Path "GlobalOptionSetDefinitions(Name='$($script:ChoiceName)')"
    if ($null -eq $targetChoice -or $null -eq $wrongChoice) {
        throw 'One of the required global Choices is absent; no binding write is authorized.'
    }
    foreach ($choice in @($targetChoice, $wrongChoice)) {
        if ($choice.IsManaged -ne $false -or $choice.IsCustomizable.Value -ne $true) {
            throw "Global Choice $($choice.Name) is not the expected unmanaged customizable component."
        }
    }
    $null = Get-ChoiceOptionsForRepair -Choice $targetChoice `
        -ExpectedOptions @($Manifest.globalChoice.options) -ExpectedName $targetChoiceName
    $null = Get-ChoiceOptionsForRepair -Choice $wrongChoice `
        -ExpectedOptions @($Manifest.callOutcomeChoice.options) -ExpectedName $script:ChoiceName
    if ([string]$targetChoice.MetadataId -ieq [string]$wrongChoice.MetadataId) {
        throw 'Wrong and intended Choice metadata identities unexpectedly match.'
    }
    $script:RepairTargetChoice = $targetChoice
    $script:RepairWrongChoice = $wrongChoice

    $historyDefinition = @($Manifest.tables | Where-Object logicalName -CEQ 'os_sr_csh')
    $callDefinition = @($Manifest.tables | Where-Object logicalName -CEQ 'os_sr_call')
    if ($historyDefinition.Count -ne 1 -or $callDefinition.Count -ne 1) {
        throw 'Candidate child table definitions are missing or ambiguous in the current manifest.'
    }
    $columns = @($historyDefinition[0].columns | Where-Object {
        $_.type -ceq 'GlobalChoice' -and $_.target -ceq $targetChoiceName
    })
    $previousColumn = @($columns | Where-Object displayName -CEQ 'Previous Status')
    $newColumn = @($columns | Where-Object displayName -CEQ 'New Status')
    if ($columns.Count -ne 2 -or $previousColumn.Count -ne 1 -or $newColumn.Count -ne 1) {
        throw 'Manifest does not define exactly the two authorized columns against Candidate Status Choice.'
    }
    $orderedColumns = @($previousColumn[0], $newColumn[0])
    $script:RepairAllowedColumns = @($orderedColumns | ForEach-Object { [string]$_.logicalName })

    $callReadback = Assert-TableReadback -Table $callDefinition[0] -Choice $wrongChoice
    $historyReadback = Assert-TableReadback -Table $historyDefinition[0] -Choice $targetChoice `
        -AllowKnownStatusChoiceMismatch
    $keys = @(Assert-RelationshipsAndKeys)

    $attributes = @{}
    $attributeIds = @{}
    foreach ($column in $orderedColumns) {
        $attribute = Get-StatusChoiceAttribute -LogicalName ([string]$column.logicalName)
        Assert-StatusChoiceColumn -Attribute $attribute -ManifestColumn $column `
            -ExpectedChoiceName $script:ChoiceName -ExpectedChoice $wrongChoice
        $attributes[[string]$column.logicalName] = $attribute
        $attributeIds[[string]$column.logicalName] = [string]$attribute.MetadataId
    }
    $script:RepairAttributeIds = $attributeIds
    $table = $historyReadback.Metadata
    $rowCount = Get-CandidateStatusHistoryRowCount -EntitySetName ([string]$table.EntitySetName) `
        -PrimaryIdAttribute ([string]$table.PrimaryIdAttribute)
    if ($rowCount -ne 0) { throw "Candidate Status History contains $rowCount business rows; binding repair is not authorized." }
    [pscustomobject]@{
        Table = $table
        Columns = $orderedColumns
        Attributes = $attributes
        AttributeIds = $attributeIds
        CallLog = $callReadback
        CandidateStatusHistory = $historyReadback
        Keys = $keys
        CandidateStatusChoice = $targetChoice
        CallOutcomeChoice = $wrongChoice
        InitialRowCount = $rowCount
    }
}

function Invoke-StatusChoiceBindingRepair {
    param([Parameter(Mandatory = $true)][object]$Manifest)
    $script:CurrentStage = 'STATUS_CHOICE_REPAIR_PREFLIGHT'
    $preflight = Assert-StatusChoiceRepairPreflight -Manifest $Manifest
    $script:ExpectedWritePaths = @($preflight.Columns | ForEach-Object {
        Get-StatusChoiceAttributePath -Attribute $preflight.Attributes[[string]$_.logicalName]
    })
    $script:MaximumWrites = 2
    foreach ($column in $preflight.Columns) {
        $logicalName = [string]$column.logicalName
        $count = Get-CandidateStatusHistoryRowCount -EntitySetName ([string]$preflight.Table.EntitySetName) `
            -PrimaryIdAttribute ([string]$preflight.Table.PrimaryIdAttribute)
        if ($count -ne 0) { throw "Candidate Status History count changed to $count before $logicalName update." }
        $attribute = Get-StatusChoiceAttribute -LogicalName $logicalName
        if ([string]$attribute.MetadataId -ine [string]$preflight.AttributeIds[$logicalName]) {
            throw "Status History attribute identity changed before the authorized $logicalName update."
        }
        Assert-StatusChoiceColumn -Attribute $attribute -ManifestColumn $column `
            -ExpectedChoiceName $script:ChoiceName -ExpectedChoice $preflight.CallOutcomeChoice
        $payload = New-StatusChoiceBindingUpdatePayload -Attribute $attribute `
            -TargetMetadataId ([string]$preflight.CandidateStatusChoice.MetadataId)
        $preservedFingerprint = Get-StatusChoicePreservationFingerprint -Attribute $attribute
        $payloadFingerprint = Get-Sha256 -Bytes ([Text.Encoding]::UTF8.GetBytes(
            (ConvertTo-Json -InputObject $payload -Depth 80 -Compress)
        ))
        $script:CurrentStage = "PUT_$logicalName"
        $script:LastWriteOutcomeUncertain = $false
        $script:LastSanitizedWriteError = $null
        $script:LastWriteHttpStatus = $null
        try {
            $null = Invoke-DataverseRequest -Method PUT `
                -Path $script:ExpectedWritePaths[$script:StatusChoiceRepairWriteCount] `
                -Body $payload -WithSolutionHeader -WithMergeLabels
        } catch {
            if ($script:LastWriteOutcomeUncertain) {
                $script:CurrentStage = "UNCERTAIN_GET_$logicalName"
                try {
                    $uncertainReadback = Get-StatusChoiceAttribute -LogicalName $logicalName
                    $bindingAfterUncertain = [string]$uncertainReadback.GlobalOptionSet.Name
                } catch {
                    $bindingAfterUncertain = 'RECONCILIATION_FAILED'
                }
                $script:StatusChoiceRepairResults.Add([ordered]@{
                    LogicalName = $logicalName
                    AttributeMetadataIdSha256 = Get-MetadataIdFingerprint -MetadataId ([string]$attribute.MetadataId)
                    PayloadSha256 = $payloadFingerprint
                    HttpStatus = $null
                    Outcome = 'UNCERTAIN_STOPPED'
                    ObservedBinding = $bindingAfterUncertain
                })
            } elseif ($null -ne $script:LastSanitizedWriteError) {
                $script:StatusChoiceRepairResults.Add([ordered]@{
                    LogicalName = $logicalName
                    AttributeMetadataIdSha256 = Get-MetadataIdFingerprint -MetadataId ([string]$attribute.MetadataId)
                    PayloadSha256 = $payloadFingerprint
                    HttpStatus = $script:LastWriteHttpStatus
                    Outcome = 'DEFINITE_FAILURE_STOPPED'
                    SanitizedError = [string]$script:LastSanitizedWriteError
                })
            }
            throw
        }
        $dispatch = [ordered]@{
            LogicalName = $logicalName
            AttributeMetadataIdSha256 = Get-MetadataIdFingerprint -MetadataId ([string]$attribute.MetadataId)
            PayloadSha256 = $payloadFingerprint
            HttpStatus = $script:LastWriteHttpStatus
            Outcome = 'DISPATCHED_READBACK_PENDING'
        }
        $script:StatusChoiceRepairResults.Add($dispatch)
        $script:CurrentStage = "IMMEDIATE_GET_$logicalName"
        try {
            $readback = Get-StatusChoiceAttribute -LogicalName $logicalName
        } catch {
            $script:LastWriteOutcomeUncertain = $true
            $script:CurrentStage = "UNCERTAIN_GET_$logicalName"
            try {
                $readback = Get-StatusChoiceAttribute -LogicalName $logicalName
                $dispatch.ObservedBinding = [string]$readback.GlobalOptionSet.Name
            } catch {
                $dispatch.ObservedBinding = 'RECONCILIATION_FAILED'
            }
            $dispatch.Outcome = 'UNCERTAIN_STOPPED'
            throw 'Immediate metadata readback failed; one GET reconciliation was attempted and the repair stopped.'
        }
        try {
            Assert-StatusChoiceColumn -Attribute $readback -ManifestColumn $column `
                -ExpectedChoiceName ([string]$Manifest.globalChoice.logicalName) `
                -ExpectedChoice $preflight.CandidateStatusChoice
            if ([string]$readback.MetadataId -ine [string]$attribute.MetadataId -or
                (Get-StatusChoicePreservationFingerprint -Attribute $readback) -cne $preservedFingerprint) {
                throw "Status Choice rebind altered preserved metadata for $logicalName."
            }
        } catch {
            $dispatch.ObservedBinding = [string]$readback.GlobalOptionSet.Name
            $dispatch.ReconciliationFailure = Get-SanitizedFailureMessage -Message ([string]$_.Exception.Message)
            $dispatch.Outcome = 'IMMEDIATE_GET_MISMATCH_STOPPED'
            throw
        }
        $dispatch.Outcome = 'UPDATED_AND_GET_RECONCILED'
        $dispatch.GlobalChoiceName = [string]$readback.GlobalOptionSet.Name
    }

    $callOutcomeAfter = Get-OptionalMetadata -Path "GlobalOptionSetDefinitions(Name='$($script:ChoiceName)')"
    $candidateStatusAfter = Get-OptionalMetadata -Path "GlobalOptionSetDefinitions(Name='$($Manifest.globalChoice.logicalName)')"
    if ($null -eq $callOutcomeAfter -or $null -eq $candidateStatusAfter -or
        [string]$callOutcomeAfter.MetadataId -ine [string]$preflight.CallOutcomeChoice.MetadataId -or
        [string]$candidateStatusAfter.MetadataId -ine [string]$preflight.CandidateStatusChoice.MetadataId) {
        throw 'A global Choice identity changed during the attribute-binding repair.'
    }
    $null = Get-ChoiceOptionsForRepair -Choice $callOutcomeAfter `
        -ExpectedOptions @($Manifest.callOutcomeChoice.options) -ExpectedName $script:ChoiceName
    $null = Get-ChoiceOptionsForRepair -Choice $candidateStatusAfter `
        -ExpectedOptions @($Manifest.globalChoice.options) -ExpectedName ([string]$Manifest.globalChoice.logicalName)

    $callDefinition = @($Manifest.tables | Where-Object logicalName -CEQ 'os_sr_call')[0]
    $historyDefinition = @($Manifest.tables | Where-Object logicalName -CEQ 'os_sr_csh')[0]
    $null = Assert-TableReadback -Table $callDefinition -Choice $callOutcomeAfter
    $null = Assert-TableReadback -Table $historyDefinition -Choice $candidateStatusAfter
    $keys = @(Assert-RelationshipsAndKeys)
    $finalCount = Get-CandidateStatusHistoryRowCount -EntitySetName ([string]$preflight.Table.EntitySetName) `
        -PrimaryIdAttribute ([string]$preflight.Table.PrimaryIdAttribute)
    if ($finalCount -ne 0) { throw "Candidate Status History contains $finalCount rows after repair." }

    $finalCandidateOutput = @(& $script:CandidateRunner -ReconcileOnly `
        -EnvironmentName $EnvironmentName -OrganizationUrl $OrganizationUrl `
        -ExpectedEnvironmentId $ExpectedEnvironmentId -ExpectedOrganizationId $ExpectedOrganizationId 2>&1 |
        ForEach-Object { [string]$_ })
    if ($LASTEXITCODE -ne 0) { throw 'Fresh final Candidate reconciliation failed after the Choice binding updates.' }
    try { $finalCandidateResult = ($finalCandidateOutput -join "`n") | ConvertFrom-Json }
    catch { throw 'Final Candidate runner did not return a parseable reconciliation result.' }
    if ($finalCandidateResult.Result -cne 'CANDIDATE_TABLE_KEYS_LOOKUPS_AND_SOLUTION_MEMBERSHIP_RECONCILED' -or
        $finalCandidateResult.CandidateTable -cne 'EXACT_SCHEMA_AND_AUDIT_RECONCILED' -or
        $finalCandidateResult.Requests.POST -ne 0) {
        throw 'Fresh final Candidate schema reconciliation did not pass without writes.'
    }

    $organization = Invoke-DataverseRequest -Method GET `
        -Path "organizations($ExpectedOrganizationId)?`$select=organizationid,isauditenabled"
    if ([string]$organization.organizationid -ine $ExpectedOrganizationId) {
        throw 'Final organization audit read returned a different target.'
    }
    $classification = if ($organization.isauditenabled) {
        'CANDIDATE_CORE_STORAGE_PROVISIONED'
    } else {
        'CANDIDATE_CORE_STORAGE_PROVISIONED_AUDIT_ACTIVATION_PENDING'
    }
    [ordered]@{
        Result = $classification
        PreviousStatus = [string]$script:StatusChoiceRepairResults[0].Outcome
        NewStatus = [string]$script:StatusChoiceRepairResults[1].Outcome
        TargetChoice = [string]$preflight.CandidateStatusChoice.Name
        CallOutcomeChoice = 'READ_ONLY_RECONCILED_UNMODIFIED'
        CandidateStatusChoice = 'READ_ONLY_RECONCILED_UNMODIFIED'
        CandidateStatusHistoryRowsBeforeEachWrite = 0
        CandidateStatusHistoryRowsAfter = $finalCount
        OrganizationAuditing = if ($organization.isauditenabled) { 'ENABLED' } else { 'DISABLED' }
        RelationshipsAndKeys = $keys
        Requests = [ordered]@{
            CandidateReconciliationGET = [int]$candidateResult.Requests.GET + [int]$finalCandidateResult.Requests.GET
            GET = [int]$script:RequestCounts.GET
            PreviousStatusMetadataUpdate = [int](@($script:WriteStages | Where-Object { $_ -ceq "PUT $($script:RepairAllowedColumns[0])" }).Count)
            NewStatusMetadataUpdate = [int](@($script:WriteStages | Where-Object { $_ -ceq "PUT $($script:RepairAllowedColumns[1])" }).Count)
            TableCreates = 0
            ColumnCreates = 0
            ChoiceDefinitionWrites = 0
            BusinessDataWrites = 0
            AppWrites = 0
            PublishXml = 0
            AutomaticRetries = 0
        }
        Writes = $script:WriteStages.ToArray()
        WritePayloadHashes = $script:WriteHashes.ToArray()
        AutomaticRetries = 0
        CandidateWrites = 0
        CallLogWrites = 0
        BusinessDataWrites = 0
        CustomApiOrPluginWrites = 0
        SecurityOrAppWrites = 0
        PublicationWrites = 0
        AuthorizationReference = $AuthorizationReference
    }
}

$failure = $null
$manifest = Get-Content -LiteralPath $script:ManifestPath -Raw | ConvertFrom-Json
$script:CorrectedCallLogCreateDispatches = [int]$manifest.provisioning.phase3B2AuthorizedContinuation.correctedCallLogCreateDispatches
$candidateResult = $null
$choiceReadback = $null
try {
    Assert-Manifest -Manifest $manifest
    Assert-TargetInput
    $initialHash = Get-ManifestHash
    $candidateOutput = @(& $script:CandidateRunner -ReconcileOnly `
        -EnvironmentName $EnvironmentName -OrganizationUrl $OrganizationUrl `
        -ExpectedEnvironmentId $ExpectedEnvironmentId -ExpectedOrganizationId $ExpectedOrganizationId 2>&1 |
        ForEach-Object { [string]$_ })
    if ($LASTEXITCODE -ne 0) { throw 'Fresh Candidate-only guarded reconciliation failed; no child write was attempted.' }
    try { $candidateResult = ($candidateOutput -join "`n") | ConvertFrom-Json }
    catch { throw 'Candidate runner did not return a parseable reconciliation result.' }
    $excludedTablesMatchMode = if ($RepairStatusChoiceBindings -or $RepairPreflightOnly) {
        (Compare-Object @('os_sr_call', 'os_sr_csh') @($candidateResult.ExcludedTablesPresent)).Count -eq 0
    } elseif ($ResumeRemainingScope) {
        (Compare-Object @('os_sr_call') @($candidateResult.ExcludedTablesPresent)).Count -eq 0
    } elseif ($ReconcileOnly) {
        $true
    } else {
        $candidateResult.ExcludedTablesPresent.Count -eq 0
    }
    if ($candidateResult.Result -cne 'CANDIDATE_TABLE_KEYS_LOOKUPS_AND_SOLUTION_MEMBERSHIP_RECONCILED' -or
        $candidateResult.CandidateTable -cne 'EXACT_SCHEMA_AND_AUDIT_RECONCILED' -or
        -not $excludedTablesMatchMode -or
        $candidateResult.Requests.POST -ne 0) {
        throw 'Fresh Candidate reconciliation, mode-specific child state, or zero-write condition did not pass.'
    }

    $script:CurrentStage = 'TARGET_AND_IDENTITY'
    Assert-PacIdentity
    Assert-TargetInput
    Get-ValidatedToken
    $script:ApiRoot = $OrganizationUrl.TrimEnd('/') + '/api/data/v9.2/'
    if ($ReconcileOnly) {
        $script:CurrentStage = 'READ_ONLY_RECONCILIATION'
        Get-ReconciliationSnapshot | ConvertTo-Json -Depth 30
        return
    }
    if ($RepairPreflightOnly) {
        $script:CurrentStage = 'STATUS_CHOICE_REPAIR_READ_ONLY_PREFLIGHT'
        Get-StatusChoiceRepairPreflightResult -Manifest $manifest -CandidateResult $candidateResult |
            ConvertTo-Json -Depth 40
        return
    }
    if ($RepairStatusChoiceBindings) {
        $result = Invoke-StatusChoiceBindingRepair -Manifest $manifest
        $result.ManifestSha256 = Get-ManifestHash
        $result | ConvertTo-Json -Depth 40
        return
    }
    $initialState = Assert-InitialState
    $script:CurrentStage = 'CHOICE_CREATE_OR_REUSE'
    $choice = $initialState.CallOutcomeChoice
    $choiceMetadataByName = @{
        os_sr_callout = $initialState.CallOutcomeChoice
        os_sr_candstat = $initialState.CandidateStatusChoice
    }
    if ($PreflightOnly) {
        $choiceReadback = Assert-Choice -Choice $choice
        foreach ($expectedOption in $manifest.callOutcomeChoice.options) {
            $liveOption = @($choiceReadback.Options | Where-Object Label -CEQ $expectedOption.label)
            if ($liveOption.Count -ne 1 -or [int]$liveOption[0].Value -ne [int]$expectedOption.value) {
                throw 'Live Call Outcome Choice mapping differs from its frozen manifest values.'
            }
        }
        $payloadPlan = [System.Collections.Generic.List[object]]::new()
        foreach ($table in $manifest.tables | Where-Object logicalName -in $script:ExpectedTableCreateNames) {
            $payload = New-TablePayload -Table $table -Manifest $manifest -ChoiceMetadataByName $choiceMetadataByName
            $payloadPlan.Add([ordered]@{
                Path = 'EntityDefinitions'
                SchemaName = [string]$payload.SchemaName
                PayloadSha256 = Get-Sha256 -Bytes ([Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $payload -Depth 80 -Compress)))
            })
        }
        foreach ($relationshipName in $script:RelationshipNames) {
            $relation = @($manifest.relationships | Where-Object schemaName -CEQ $relationshipName)[0]
            $parent = if ($relation.parent -ceq 'os_sr_cand') { $initialState.Candidate } else { $initialState.SystemUser }
            $payload = Get-RelationshipPayload -Relation $relation -ReferencedAttribute ([string]$parent.PrimaryIdAttribute)
            $payloadPlan.Add([ordered]@{
                Path = 'RelationshipDefinitions'
                SchemaName = [string]$payload.SchemaName
                PayloadSha256 = Get-Sha256 -Bytes ([Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $payload -Depth 80 -Compress)))
            })
        }
        foreach ($name in $script:TableNames) {
            $table = @($manifest.tables | Where-Object logicalName -CEQ $name)[0]
            foreach ($definition in $table.alternateKeys) {
                $payload = [ordered]@{
                    '@odata.type' = 'Microsoft.Dynamics.CRM.EntityKeyMetadata'
                    SchemaName = [string]$definition.name
                    DisplayName = New-Label -Text ([string]$definition.name)
                    KeyAttributes = @($definition.columns)
                }
                $payloadPlan.Add([ordered]@{
                    Path = "EntityDefinitions(LogicalName='$name')/Keys"
                    SchemaName = [string]$definition.name
                    PayloadSha256 = Get-Sha256 -Bytes ([Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $payload -Depth 80 -Compress)))
                })
            }
        }
        [ordered]@{
            Result = if ($ResumeRemainingScope) {
                'READ_ONLY_REMAINING_SCOPE_RESUME_PREFLIGHT_PASSED'
            } else {
                'READ_ONLY_CHILD_PREFLIGHT_PASSED'
            }
            Candidate = $candidateResult.Result
            CallOutcomeChoice = 'EXACT_LABEL_VALUE_MAPPING_AND_SOLUTION_MEMBERSHIP'
            PlannedTables = @($script:ExpectedTableCreateNames)
            PlannedRelationships = $script:RelationshipNames
            PlannedKeys = $script:KeyNames
            ManifestSha256 = Get-ManifestHash
            PlannedWrites = $payloadPlan.ToArray()
            CorrectedCallLogCreateDispatchLimit = 1
            Requests = [ordered]@{
                CandidateReconciliationGET = [int]$candidateResult.Requests.GET
                ChildScopeGET = $script:RequestCounts.GET
            }
            Writes = @()
            AutomaticRetries = 0
            CorrectedCallLogCreateDispatches = [int]$manifest.provisioning.phase3B2AuthorizedContinuation.correctedCallLogCreateDispatches
            RemainingScopeAuthorizationConsumed = [bool]$manifest.provisioning.phase3B2AuthorizedContinuation.remainingMetadataAuthorizationConsumed
        } | ConvertTo-Json -Depth 20
        return
    }
    $choiceReadback = Assert-Choice -Choice $choice
    if (-not $ResumeRemainingScope) {
        Update-ManifestChoiceValues -Options $choiceReadback.Options
        $script:ExpectedManifestSha256 = Get-ManifestHash
        $manifest = Get-Content -LiteralPath $script:ManifestPath -Raw | ConvertFrom-Json
        Assert-Manifest -Manifest $manifest
    }
    $choice = $choiceReadback.Metadata
    $choiceMetadataByName.os_sr_callout = $choice

    $script:CurrentStage = 'CREATE_CHILD_TABLES'
    foreach ($name in $script:ExpectedTableCreateNames) {
        $table = @($manifest.tables | Where-Object logicalName -CEQ $name)[0]
        $payload = New-TablePayload -Table $table -Manifest $manifest -ChoiceMetadataByName $choiceMetadataByName
        $null = Invoke-DataverseRequest -Method POST -Path 'EntityDefinitions' -Body $payload -WithSolutionHeader
        if ($name -ceq 'os_sr_call') {
            $script:CurrentStage = 'CALL_LOG_IMMEDIATE_READBACK'
            $null = Assert-TableCreateReadback -Table $table
            Set-ManifestContinuationState -Status 'CORRECTED_CALLLOG_RECONCILED_REMAINING_SCOPE_AUTHORIZED' -CorrectedCallLogDispatches 1
            $script:CurrentStage = 'CREATE_CHILD_TABLES'
        }
    }
    Start-Sleep -Seconds 20
    $candidateMetadata = Get-OptionalMetadata -Path "EntityDefinitions(LogicalName='os_sr_cand')?`$select=LogicalName,PrimaryIdAttribute"
    $systemUserMetadata = Get-OptionalMetadata -Path "EntityDefinitions(LogicalName='systemuser')?`$select=LogicalName,PrimaryIdAttribute"
    if ($null -eq $candidateMetadata -or $null -eq $systemUserMetadata) {
        throw 'A relationship target disappeared after child table creation; no further writes were sent.'
    }
    $script:CurrentStage = 'CREATE_CHILD_RELATIONSHIPS'
    foreach ($relationName in $script:ExpectedRelationshipNames) {
        $relation = @($manifest.relationships | Where-Object schemaName -CEQ $relationName)[0]
        $parent = if ($relation.parent -ceq 'os_sr_cand') { $candidateMetadata } else { $systemUserMetadata }
        $payload = Get-RelationshipPayload -Relation $relation -ReferencedAttribute ([string]$parent.PrimaryIdAttribute)
        $null = Invoke-DataverseRequest -Method POST -Path 'RelationshipDefinitions' -Body $payload -WithSolutionHeader
        Start-Sleep -Seconds 5
    }
    Start-Sleep -Seconds 20
    $script:CurrentStage = 'CREATE_CHILD_KEYS'
    foreach ($keyName in $script:ExpectedKeyNames) {
        $table = @($manifest.tables | Where-Object {
            @($_.alternateKeys | Where-Object name -CEQ $keyName).Count -eq 1
        })[0]
        $definition = @($table.alternateKeys | Where-Object name -CEQ $keyName)[0]
        $payload = [ordered]@{
            '@odata.type' = 'Microsoft.Dynamics.CRM.EntityKeyMetadata'
            SchemaName = [string]$definition.name
            DisplayName = New-Label -Text ([string]$definition.name)
            KeyAttributes = @($definition.columns)
        }
        $null = Invoke-DataverseRequest -Method POST -Path "EntityDefinitions(LogicalName='$($table.logicalName)')/Keys" -Body $payload -WithSolutionHeader
        Start-Sleep -Seconds 5
    }
    Start-Sleep -Seconds 20
    $script:CurrentStage = 'FINAL_SCHEMA_RECONCILIATION'
    $tableResults = @()
    foreach ($table in $manifest.tables | Where-Object logicalName -in $script:TableNames) {
        $tableResults += Assert-TableReadback -Table $table -Choice $choice
    }
    $keys = @(Assert-RelationshipsAndKeys)
    $org = Invoke-DataverseRequest -Method GET -Path "organizations($ExpectedOrganizationId)?`$select=organizationid,isauditenabled"
    if ([string]$org.organizationid -ine $ExpectedOrganizationId) {
        throw 'Final organization audit read returned a different target.'
    }
    Set-ManifestContinuationState -Status 'PHASE_3B2_STORAGE_RECONCILED_AUTHORIZATION_CONSUMED' `
        -CorrectedCallLogDispatches 1 -RemainingScopeWritesDispatched $script:RemainingScopeDispatches
    $script:ProvisioningReconciled = $true
    [ordered]@{
        Result = 'PHASE_3B2_CHILD_TABLES_AND_CALL_OUTCOME_CHOICE_RECONCILED'
        ManifestSha256AtStart = $initialHash
        ManifestSha256AfterChoiceFreeze = Get-ManifestHash
        FinalManifestSha256 = Get-ManifestHash
        Candidate = $candidateResult.Result
        CandidateStatusChoice = 'RECONCILED_UNMODIFIED'
        CallOutcomeChoice = [ordered]@{
            Name = $choice.Name
            Options = @($choiceReadback.Options | ForEach-Object { [ordered]@{ Label = $_.Label; Value = $_.Value } })
        }
        ChildTables = @($script:TableNames)
        RelationshipNames = @($script:RelationshipNames)
        AlternateKeys = $keys
        TableAuditing = 'ENABLED'
        OrganizationAuditing = if ($org.isauditenabled) { 'ENABLED' } else { 'DISABLED; NO BUSINESS DATA AUTHORIZED' }
        Requests = [ordered]@{
            CandidateReconciliationGET = [int]$candidateResult.Requests.GET
            ChildScopeGET = $script:RequestCounts.GET
            ChildScopePOST = $script:RequestCounts.POST
        }
        Writes = $script:WriteStages.ToArray()
        WritePayloadHashes = $script:WriteHashes.ToArray()
        AutomaticRetries = 0
        CandidateWrites = 0
        BusinessDataWrites = 0
        CustomApiOrPluginWrites = 0
        SecurityOrAppWrites = 0
        PublicationWrites = 0
        AuthorizationReference = $AuthorizationReference
    } | ConvertTo-Json -Depth 40
}
catch {
    $failure = $_
    if ($script:WriteStages.Count -gt 0 -and -not $script:ProvisioningReconciled -and
        -not $RepairStatusChoiceBindings) {
        Set-ManifestContinuationState -Status 'STOPPED_AFTER_CORRECTED_CONTINUATION_REQUIRES_RECONCILIATION' `
            -CorrectedCallLogDispatches $script:CorrectedCallLogCreateDispatches `
            -RemainingScopeWritesDispatched $script:RemainingScopeDispatches `
            -ConsumeRemainingScopeAuthorization:$script:RemainingScopeAuthorizationConsumed
    }
    $repairMode = $RepairPreflightOnly -or $RepairStatusChoiceBindings
    $repairClassification = if ($script:LastWriteOutcomeUncertain) {
        'UNCERTAIN_WRITE_OUTCOME'
    } elseif ($repairMode -and $null -ne $script:LastSanitizedWriteError -and
        @($script:StatusChoiceRepairResults | Where-Object Outcome -CEQ 'UPDATED_AND_GET_RECONCILED').Count -eq 0) {
        'IN_PLACE_CHOICE_REBIND_UNSUPPORTED_OR_REJECTED'
    } elseif ($repairMode -and $null -ne $script:LastSanitizedWriteError) {
        'PARTIAL_METADATA_STATE'
    } elseif ($repairMode -and $script:WriteStages.Count -gt 0) {
        'PARTIAL_METADATA_STATE'
    } elseif ($repairMode -and
        ([string]$failure.Exception.Message -match '(?i)row count|business rows|aggregate count')) {
        'REBIND_BLOCKED_DATA_PRESENT_OR_UNKNOWN'
    } elseif ($repairMode -and $script:CurrentStage -ceq 'TARGET_AND_IDENTITY') {
        'FAILED_AUTH'
    } elseif ($repairMode -and
        ([string]$failure.Exception.Message -match 'WhoAmI|process-scoped identity')) {
        'FAILED_AUTHZ'
    } elseif ($repairMode) {
        'PARTIAL_METADATA_STATE'
    } elseif ($script:WriteStages.Count -eq 0) {
        'BLOCKED_BEFORE_WRITE'
    } else {
        'STOPPED_AFTER_WRITE_REQUIRES_REVIEW'
    }
    [ordered]@{
        Result = $repairClassification
        Stage = $script:CurrentStage
        SafeError = if ($script:WriteStages.Count -eq 0) {
            'A fresh guard, schema preflight, or payload validation failed; no child metadata write was sent.'
        } else {
            'A metadata write was sent; inspect reported write stages and reconcile live state before any further action. No retry occurred.'
        }
        FailureReason = Get-SanitizedFailureMessage -Message ([string]$failure.Exception.Message)
        HttpStatus = $script:LastWriteHttpStatus
        SanitizedDataverseError = $script:LastSanitizedWriteError
        ManifestSha256 = Get-ManifestHash
        CandidateResult = if ($null -eq $candidateResult) { 'NOT_RECONCILED' } else { $candidateResult.Result }
        Requests = $script:RequestCounts
        Writes = $script:WriteStages.ToArray()
        WritePayloadHashes = $script:WriteHashes.ToArray()
        StatusChoiceRepairResults = $script:StatusChoiceRepairResults.ToArray()
        CorrectedCallLogCreateDispatches = $script:CorrectedCallLogCreateDispatches
        RemainingScopeWritesDispatched = $script:RemainingScopeDispatches
        AutomaticRetries = 0
        TableCreates = 0
        ColumnCreates = 0
        ChoiceDefinitionWrites = 0
        CandidateWrites = 0
        BusinessDataWrites = 0
        CustomApiOrPluginWrites = 0
        SecurityOrAppWrites = 0
        PublicationWrites = 0
        PublishXml = 0
    } | ConvertTo-Json -Depth 30
    throw 'Phase 3B.2 stopped. Use sanitized output and fresh read-only reconciliation; never retry automatically.'
}
finally {
    $script:AccessToken = $null
    $script:ExpectedUserId = $null
    [Environment]::SetEnvironmentVariable('BSO_RS_EXPECTED_USER_ID', $null, 'Process')
}
