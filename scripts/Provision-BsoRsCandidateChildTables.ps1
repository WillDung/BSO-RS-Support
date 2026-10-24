#requires -Version 7.4
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$EnvironmentName,
    [Parameter(Mandatory = $true)][string]$OrganizationUrl,
    [Parameter(Mandatory = $true)][string]$ExpectedEnvironmentId,
    [Parameter(Mandatory = $true)][string]$ExpectedOrganizationId,
    [Parameter(Mandatory = $true)][string]$AuthorizationReference,
    [switch]$ReconcileOnly,
    [switch]$PreflightOnly
)

$ErrorActionPreference = 'Stop'
$script:SolutionName = 'os_sr_bso_rs_support'
$script:PublisherName = 'os_bso_rs_support'
$script:PublisherPrefix = 'os'
$script:ManifestPath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\docs\PHASE_3A_CANDIDATE_CORE_METADATA_PLAN.json'))
$script:CandidateRunner = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'Provision-BsoRsCandidateTable.ps1'))
$script:ExpectedManifestSha256 = 'b7d0abb9335fd30925911059ef9744a1a519c84338354549768879083cc30ca4'
$script:RequestCounts = @{ GET = 0; POST = 0 }
$script:WriteStages = [System.Collections.Generic.List[string]]::new()
$script:WriteHashes = [System.Collections.Generic.List[object]]::new()
$script:ApiRoot = $null
$script:AccessToken = $null
$script:ExpectedUserId = $null
$script:PacUserEmail = $null
$script:Publisher = $null
$script:Solution = $null
$script:CurrentStage = 'LOCAL_MANIFEST'
$script:MaximumWrites = 9
$script:ExpectedWritePaths = @()
$script:ChoiceName = 'os_sr_callout'
$script:OutcomeLabels = @('Answered', 'No Answer', 'Call Back Requested')
$script:TableNames = @('os_sr_call', 'os_sr_csh')
$script:RelationshipNames = @(
    'os_sr_cand_call',
    'os_sr_cand_csh',
    'os_sr_usr_call_ctby',
    'os_sr_usr_csh_actr'
)
$script:KeyNames = @('os_sr_call_ak_cand_action', 'os_sr_csh_ak_cand_action')

function Get-Sha256 {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes)).ToLowerInvariant()
}

function Get-ManifestHash {
    Get-Sha256 -Bytes ([IO.File]::ReadAllBytes($script:ManifestPath))
}

function Assert-Manifest {
    param([Parameter(Mandatory = $true)][object]$Manifest)
    if ((Get-ManifestHash) -cne $script:ExpectedManifestSha256) {
        throw 'Current manifest fingerprint differs from the authorized Phase 3B.2 baseline.'
    }
    if ($Manifest.provisioning.phase3B2AuthorizedContinuation.status -ceq 'STOPPED_AFTER_REJECTED_TABLE_CREATE_NO_RETRY') {
        throw 'The Phase 3B.2 authorization was stopped after a rejected table-create request; no further writes are permitted.'
    }
    if ($Manifest.phase -cne '3A' -or $Manifest.solutionUniqueName -cne $script:SolutionName -or
        $Manifest.publisherPrefix -cne $script:PublisherPrefix -or
        $Manifest.provisioning.phase3B2AuthorizedContinuation.status -cne 'AUTHORIZED_CHILD_TABLE_METADATA_ONLY' -or
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

function New-AttributePayload {
    param(
        [Parameter(Mandatory = $true)][object]$Column,
        [Parameter(Mandatory = $true)][object]$ChoiceMetadata
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
            [ordered]@{
                '@odata.type' = 'Microsoft.Dynamics.CRM.PicklistAttributeMetadata'
                AttributeType = 'Picklist'
                AttributeTypeName = [ordered]@{ Value = 'PicklistType' }
                SchemaName = [string]$Column.logicalName
                DisplayName = New-Label -Text ([string]$Column.displayName)
                RequiredLevel = New-RequiredLevel -Required $required
                IsPrimaryName = $false
                'GlobalOptionSet@odata.bind' = "/GlobalOptionSetDefinitions($($ChoiceMetadata.MetadataId))"
            }
        }
        default { throw "Unsupported child column type in approved manifest: $($Column.type)" }
    }
}

function New-TablePayload {
    param(
        [Parameter(Mandatory = $true)][object]$Table,
        [Parameter(Mandatory = $true)][object]$Manifest,
        [Parameter(Mandatory = $true)][object]$ChoiceMetadata
    )
    $primaryMaxLength = 0
    if ($null -ne $Table.primaryName.maxLength) {
        $primaryMaxLength = [int]$Table.primaryName.maxLength
    }
    if ($primaryMaxLength -lt 1 -or $primaryMaxLength -gt 4000) {
        throw "Primary-name MaxLength is missing or invalid for $($Table.logicalName); no table payload can be created safely."
    }
    $attributes = [System.Collections.Generic.List[object]]::new()
    $attributes.Add([ordered]@{
        '@odata.type' = 'Microsoft.Dynamics.CRM.StringAttributeMetadata'
        AttributeType = 'String'
        AttributeTypeName = [ordered]@{ Value = 'StringType' }
        SchemaName = [string]$Table.primaryName.logicalName
        DisplayName = New-Label -Text ([string]$Table.primaryName.displayName)
        RequiredLevel = New-RequiredLevel -Required $true
        FormatName = [ordered]@{ Value = 'Text' }
        MaxLength = $primaryMaxLength
        IsPrimaryName = $true
        AutoNumberFormat = [string]$Table.primaryName.format
    })
    foreach ($column in @($Table.columns | Where-Object type -ne 'Lookup')) {
        $attributes.Add((New-AttributePayload -Column $column -ChoiceMetadata $ChoiceMetadata))
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
        [Parameter(Mandatory = $true)][ValidateSet('GET', 'POST')][string]$Method,
        [Parameter(Mandatory = $true)][string]$Path,
        [object]$Body,
        [switch]$WithSolutionHeader
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
    if ($Method -eq 'POST') {
        $index = $script:WriteStages.Count
        if ($index -ge $script:MaximumWrites -or -not $WithSolutionHeader) {
            throw 'Write ceiling or approved Solution header guard failed.'
        }
        $pathIsApproved = $index -lt $script:ExpectedWritePaths.Count -and $Path -ceq $script:ExpectedWritePaths[$index]
        $bodyIsApproved = switch -Regex ($Path) {
            '^GlobalOptionSetDefinitions$' {
                $Body.Name -ceq $script:ChoiceName -and @($Body.Options).Count -eq 3 -and
                @($Body.Options | Where-Object { $null -ne $_.Value }).Count -eq 0
                break
            }
            '^EntityDefinitions$' {
                $Body.SchemaName -in $script:TableNames -and $Body.OwnershipType -ceq 'UserOwned' -and
                $Body.SchemaName -ceq $(if ($index -eq $(if ($script:ExpectedWritePaths[0] -ceq 'GlobalOptionSetDefinitions') { 1 } else { 0 })) {
                    'os_sr_call'
                } else {
                    'os_sr_csh'
                }) -and $Body.IsAuditEnabled.Value -eq $true -and @($Body.Attributes).Count -gt 0
                break
            }
            '^RelationshipDefinitions$' {
                $Body.SchemaName -in $script:RelationshipNames -and
                $Body.ReferencingEntity -in $script:TableNames -and
                $Body.SchemaName -ceq $script:RelationshipNames[$index - $(if ($script:ExpectedWritePaths[0] -ceq 'GlobalOptionSetDefinitions') { 3 } else { 2 })] -and
                $Body.CascadeConfiguration.Delete -ceq 'Restrict' -and
                $Body.CascadeConfiguration.Assign -ceq 'NoCascade' -and
                $Body.CascadeConfiguration.Share -ceq 'NoCascade' -and
                $Body.CascadeConfiguration.Reparent -ceq 'NoCascade'
                break
            }
            '/Keys$' {
                $Body.SchemaName -in $script:KeyNames -and @($Body.KeyAttributes).Count -eq 2
                break
            }
            default { $false }
        }
        if (-not $pathIsApproved -or -not $bodyIsApproved) {
            throw 'POST path or payload is outside the fixed Phase 3B.2 allowlist.'
        }
        $payloadHash = Get-Sha256 -Bytes ([Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $Body -Depth 80 -Compress)))
        $script:WriteStages.Add($Path)
        $script:WriteHashes.Add([ordered]@{ Path = $Path; PayloadSha256 = $payloadHash })
    }
    $headers = @{
        Authorization = 'Bearer ' + $script:AccessToken
        Accept = 'application/json'
        'OData-MaxVersion' = '4.0'
        'OData-Version' = '4.0'
        'If-None-Match' = 'null'
    }
    if ($WithSolutionHeader) { $headers['MSCRM.SolutionUniqueName'] = $script:SolutionName }
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
        if ($Method -eq 'POST') { throw 'A metadata POST transport outcome is uncertain; do not retry.' }
        throw 'A Dataverse GET failed; no write was sent by this request.'
    }
    if ([int]$statusCode -lt 200 -or [int]$statusCode -ge 300) {
        throw "Dataverse returned HTTP $statusCode; response content suppressed and no retry was attempted."
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
    Assert-ChildTableAbsent
    $script:CurrentStage = 'CALL_OUTCOME_CHOICE_READ'
    $choice = Get-OptionalMetadata -Path "GlobalOptionSetDefinitions(Name='$($script:ChoiceName)')"
    if ($null -ne $choice) { $null = Assert-Choice -Choice $choice }
    $script:CurrentStage = 'ORGANIZATION_AUDIT_READ'
    $organization = Invoke-DataverseRequest -Method GET -Path "organizations($ExpectedOrganizationId)?`$select=organizationid,isauditenabled"
    if ([string]$organization.organizationid -ine $ExpectedOrganizationId) {
        throw 'Organization audit response target did not match the approved organization.'
    }
    $script:ExpectedWritePaths = @()
    if ($null -eq $choice) { $script:ExpectedWritePaths += 'GlobalOptionSetDefinitions' }
    $script:ExpectedWritePaths += @('EntityDefinitions', 'EntityDefinitions')
    $script:ExpectedWritePaths += @('RelationshipDefinitions', 'RelationshipDefinitions', 'RelationshipDefinitions', 'RelationshipDefinitions')
    $script:ExpectedWritePaths += @(
        "EntityDefinitions(LogicalName='os_sr_call')/Keys",
        "EntityDefinitions(LogicalName='os_sr_csh')/Keys"
    )
    $script:MaximumWrites = $script:ExpectedWritePaths.Count
    [pscustomobject]@{
        Candidate = $candidate
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
        [Parameter(Mandatory = $true)][object]$Choice
    )
    $name = [string]$Table.logicalName
    $metadata = Get-OptionalMetadata -Path "EntityDefinitions(LogicalName='$name')?`$select=LogicalName,MetadataId,OwnershipType,PrimaryIdAttribute,PrimaryNameAttribute,IsAuditEnabled"
    if ($null -eq $metadata -or $metadata.LogicalName -cne $name -or
        $metadata.OwnershipType -cne 'UserOwned' -or
        $metadata.PrimaryNameAttribute -cne $Table.primaryName.logicalName -or
        $metadata.IsAuditEnabled.Value -ne $true) {
        throw "Created child table $name failed identity, ownership, primary-name, or audit reconciliation."
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
        if ($column.type -eq 'String' -and [int]$field[0].MaxLength -ne [int]$column.maxLength) {
            throw "Column $($column.logicalName) max length did not reconcile."
        }
        if ($column.type -eq 'Memo' -and [int]$field[0].MaxLength -ne [int]$column.maxLength) {
            throw "Column $($column.logicalName) memo max length did not reconcile."
        }
    }
    foreach ($column in @($Table.columns | Where-Object type -eq 'GlobalChoice')) {
        $filter = [Uri]::EscapeDataString("LogicalName eq '$($column.logicalName)'")
        $picklist = @(Get-ODataRows -Path "EntityDefinitions(LogicalName='$name')/Attributes/Microsoft.Dynamics.CRM.PicklistAttributeMetadata?`$select=LogicalName&`$filter=$filter&`$expand=GlobalOptionSet" |
            Where-Object LogicalName -CEQ $column.logicalName)
        if ($picklist.Count -ne 1 -or
            [string]$picklist[0].GlobalOptionSet.Name -cne [string]$column.target) {
            throw "Global Choice binding for $($column.logicalName) did not reconcile."
        }
    }
    [pscustomobject]@{ Metadata = $metadata; Root = $roots[0]; Attributes = $actual }
}

function Assert-RelationshipsAndKeys {
    foreach ($name in $script:TableNames) {
        $relationships = @(Get-ODataRows -Path "EntityDefinitions(LogicalName='$name')/ManyToOneRelationships")
        $expected = @($script:RelationshipNames | Where-Object { $_ -in @(
            if ($name -ceq 'os_sr_call') { 'os_sr_cand_call'; 'os_sr_usr_call_ctby' }
            else { 'os_sr_cand_csh'; 'os_sr_usr_csh_actr' }
        ) })
        foreach ($relationshipName in $expected) {
            $match = @($relationships | Where-Object SchemaName -CEQ $relationshipName)
            if ($match.Count -ne 1 -or $match[0].CascadeConfiguration.Delete -cne 'Restrict' -or
                $match[0].CascadeConfiguration.Assign -cne 'NoCascade' -or
                $match[0].CascadeConfiguration.Share -cne 'NoCascade' -or
                $match[0].CascadeConfiguration.Reparent -cne 'NoCascade') {
                throw "Relationship $relationshipName did not reconcile to the manifest."
            }
        }
    }
    $keys = [System.Collections.Generic.List[object]]::new()
    foreach ($name in $script:TableNames) {
        $table = @($manifest.tables | Where-Object logicalName -CEQ $name)[0]
        $actual = @(Get-ODataRows -Path "EntityDefinitions(LogicalName='$name')/Keys")
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

$failure = $null
$manifest = Get-Content -LiteralPath $script:ManifestPath -Raw | ConvertFrom-Json
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
    if ($candidateResult.Result -cne 'CANDIDATE_TABLE_KEYS_LOOKUPS_AND_SOLUTION_MEMBERSHIP_RECONCILED' -or
        $candidateResult.CandidateTable -cne 'EXACT_SCHEMA_AND_AUDIT_RECONCILED' -or
        $candidateResult.ExcludedTablesPresent.Count -ne 0 -or $candidateResult.Requests.POST -ne 0) {
        throw 'Fresh Candidate reconciliation, child absence, or zero-write condition did not pass.'
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
    $initialState = Assert-InitialState
    $script:CurrentStage = 'CHOICE_CREATE_OR_REUSE'
    $choice = $initialState.CallOutcomeChoice
    if ($PreflightOnly) {
        if ($null -eq $choice) { throw 'Preflight-only mode requires the Call Outcome Choice to exist; no writes are allowed.' }
        $choiceReadback = Assert-Choice -Choice $choice
        foreach ($expectedOption in $manifest.callOutcomeChoice.options) {
            $liveOption = @($choiceReadback.Options | Where-Object Label -CEQ $expectedOption.label)
            if ($liveOption.Count -ne 1 -or [int]$liveOption[0].Value -ne [int]$expectedOption.value) {
                throw 'Live Call Outcome Choice mapping differs from its frozen manifest values.'
            }
        }
        $previewTables = @($manifest.tables | Where-Object logicalName -in $script:TableNames | ForEach-Object {
            (New-TablePayload -Table $_ -Manifest $manifest -ChoiceMetadata $choice).SchemaName
        })
        [ordered]@{
            Result = 'READ_ONLY_CHILD_PREFLIGHT_PASSED'
            Candidate = $candidateResult.Result
            CallOutcomeChoice = 'EXACT_LABEL_VALUE_MAPPING_AND_SOLUTION_MEMBERSHIP'
            PlannedTables = $previewTables
            PlannedRelationships = $script:RelationshipNames
            PlannedKeys = $script:KeyNames
            Requests = [ordered]@{
                CandidateReconciliationGET = [int]$candidateResult.Requests.GET
                ChildScopeGET = $script:RequestCounts.GET
            }
            Writes = @()
            AutomaticRetries = 0
        } | ConvertTo-Json -Depth 20
        return
    }
    if ($null -eq $choice) {
        $choicePayload = New-CallOutcomeChoicePayload
        $null = Invoke-DataverseRequest -Method POST -Path 'GlobalOptionSetDefinitions' -Body $choicePayload -WithSolutionHeader
        Start-Sleep -Seconds 5
        $choice = Get-OptionalMetadata -Path "GlobalOptionSetDefinitions(Name='$($script:ChoiceName)')"
        if ($null -eq $choice) { throw 'Call Outcome Choice POST returned without a visible GET-reconciled component; do not retry.' }
        $choiceReadback = Assert-Choice -Choice $choice
    }
    else {
        $choiceReadback = Assert-Choice -Choice $choice
    }
    Update-ManifestChoiceValues -Options $choiceReadback.Options
    $script:ExpectedManifestSha256 = Get-ManifestHash
    $manifest = Get-Content -LiteralPath $script:ManifestPath -Raw | ConvertFrom-Json
    Assert-Manifest -Manifest $manifest
    $choice = $choiceReadback.Metadata

    $script:CurrentStage = 'CREATE_CHILD_TABLES'
    foreach ($name in $script:TableNames) {
        $table = @($manifest.tables | Where-Object logicalName -CEQ $name)[0]
        $payload = New-TablePayload -Table $table -Manifest $manifest -ChoiceMetadata $choice
        $null = Invoke-DataverseRequest -Method POST -Path 'EntityDefinitions' -Body $payload -WithSolutionHeader
    }
    Start-Sleep -Seconds 20
    $candidateMetadata = Get-OptionalMetadata -Path "EntityDefinitions(LogicalName='os_sr_cand')?`$select=LogicalName,PrimaryIdAttribute"
    $systemUserMetadata = Get-OptionalMetadata -Path "EntityDefinitions(LogicalName='systemuser')?`$select=LogicalName,PrimaryIdAttribute"
    if ($null -eq $candidateMetadata -or $null -eq $systemUserMetadata) {
        throw 'A relationship target disappeared after child table creation; no further writes were sent.'
    }
    $script:CurrentStage = 'CREATE_CHILD_RELATIONSHIPS'
    foreach ($relationName in $script:RelationshipNames) {
        $relation = @($manifest.relationships | Where-Object schemaName -CEQ $relationName)[0]
        $parent = if ($relation.parent -ceq 'os_sr_cand') { $candidateMetadata } else { $systemUserMetadata }
        $payload = Get-RelationshipPayload -Relation $relation -ReferencedAttribute ([string]$parent.PrimaryIdAttribute)
        $null = Invoke-DataverseRequest -Method POST -Path 'RelationshipDefinitions' -Body $payload -WithSolutionHeader
        Start-Sleep -Seconds 5
    }
    Start-Sleep -Seconds 20
    $script:CurrentStage = 'CREATE_CHILD_KEYS'
    foreach ($name in $script:TableNames) {
        $table = @($manifest.tables | Where-Object logicalName -CEQ $name)[0]
        foreach ($definition in $table.alternateKeys) {
            $payload = [ordered]@{
                '@odata.type' = 'Microsoft.Dynamics.CRM.EntityKeyMetadata'
                SchemaName = [string]$definition.name
                DisplayName = New-Label -Text ([string]$definition.name)
                KeyAttributes = @($definition.columns)
            }
            $null = Invoke-DataverseRequest -Method POST -Path "EntityDefinitions(LogicalName='$name')/Keys" -Body $payload -WithSolutionHeader
            Start-Sleep -Seconds 5
        }
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
    [ordered]@{
        Result = 'PHASE_3B2_CHILD_TABLES_AND_CALL_OUTCOME_CHOICE_RECONCILED'
        ManifestSha256AtStart = $initialHash
        ManifestSha256AfterChoiceFreeze = Get-ManifestHash
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
    [ordered]@{
        Result = if ($script:WriteStages.Count -eq 0) { 'BLOCKED_BEFORE_WRITE' } else { 'STOPPED_AFTER_WRITE_REQUIRES_REVIEW' }
        Stage = $script:CurrentStage
        SafeError = if ($script:WriteStages.Count -eq 0) {
            'A fresh guard, schema preflight, or payload validation failed; no child metadata write was sent.'
        } else {
            'A metadata write was sent; inspect reported write stages and reconcile live state before any further action. No retry occurred.'
        }
        FailureReason = [string]$failure.Exception.Message
        ManifestSha256 = Get-ManifestHash
        CandidateResult = if ($null -eq $candidateResult) { 'NOT_RECONCILED' } else { $candidateResult.Result }
        Requests = $script:RequestCounts
        Writes = $script:WriteStages.ToArray()
        WritePayloadHashes = $script:WriteHashes.ToArray()
        AutomaticRetries = 0
        CandidateWrites = 0
        BusinessDataWrites = 0
        CustomApiOrPluginWrites = 0
        SecurityOrAppWrites = 0
        PublicationWrites = 0
    } | ConvertTo-Json -Depth 30
    throw 'Phase 3B.2 stopped. Use sanitized output and fresh read-only reconciliation; never retry automatically.'
}
finally {
    $script:AccessToken = $null
    $script:ExpectedUserId = $null
    [Environment]::SetEnvironmentVariable('BSO_RS_EXPECTED_USER_ID', $null, 'Process')
}
