#requires -Version 7.4
[CmdletBinding()]
param(
    [switch]$Apply,
    [switch]$PreflightOnly,
    [switch]$ReconcileOnly,
    [switch]$ContinueAfterTable,
    [string]$Confirmation,
    [string]$AuthorizationReference,
    [string]$EnvironmentName = $env:BSO_RS_ENVIRONMENT_NAME,
    [string]$OrganizationUrl = $env:BSO_RS_ORG_URL,
    [string]$ExpectedEnvironmentId = $env:BSO_RS_EXPECTED_ENVIRONMENT_ID,
    [string]$ExpectedOrganizationId = $env:BSO_RS_EXPECTED_ORG_ID
)

$ErrorActionPreference = 'Stop'
$script:RequestCounts = @{ GET = 0; POST = 0 }
$script:WriteStages = [System.Collections.Generic.List[string]]::new()
$script:LastWriteStage = $null
$script:ApiRoot = $null
$script:AccessToken = $null
$script:SolutionName = 'os_sr_bso_rs_support'
$script:PublisherName = 'os_bso_rs_support'
$script:PublisherPrefix = 'os'
$script:NamespacePrefix = 'sr_'
$script:CandidateName = 'os_sr_cand'
$script:ChoiceName = 'os_sr_candstat'
$script:ExcludedTables = @('os_sr_call', 'os_sr_csh')
$script:ExcludedChoice = 'os_sr_callout'
$script:MaximumWrites = 5
$script:CurrentStage = 'LOCAL_MANIFEST'
$script:LastWriteHttpStatus = $null
$script:SafeBlockReason = $null
$script:LastSolutionMembershipCount = $null
$script:CandidateAttributeSummary = @()
$script:ExpectedManifestSha256 = '7cfe13bb7450946c17e3659e02a4b78aecfd93f50c272561b1e88c6084d566d1'
$script:ExpectedCandidateProjectionSha256 = '7168980f2d13d8e406a25854fef3dafad118673e1c5661fb9461e52f41b4f7d8'
$script:StatusLabels = @(
    'Need Call Candidate',
    'Candidate Answered',
    'Waiting Manual Scheduling',
    'Round 1 Scheduled',
    'Offer Extended',
    'Candidate Failed'
)

function Get-Sha256 {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { [BitConverter]::ToString($sha.ComputeHash($Bytes)).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Get-FileSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    Get-Sha256 -Bytes ([IO.File]::ReadAllBytes($Path))
}

function Get-PayloadSha256 {
    param([Parameter(Mandatory = $true)][object]$Payload)
    Get-Sha256 -Bytes ([Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $Payload -Depth 80 -Compress)))
}

function Get-CandidateProjection {
    param([Parameter(Mandatory = $true)][object]$Manifest)
    $candidate = @($Manifest.tables | Where-Object logicalName -CEQ $script:CandidateName)
    $relationships = @($Manifest.relationships | Where-Object {
        $_.child -ceq $script:CandidateName -and $_.parent -in @('os_sr_pos', 'os_sr_csrc', 'os_sr_ta')
    })
    if ($candidate.Count -ne 1) { throw 'Candidate manifest table is missing or duplicated.' }
    [ordered]@{
        proposalType = 'Candidate-only schema proposal; non-dispatchable'
        solutionUniqueName = $Manifest.solutionUniqueName
        publisherPrefix = $Manifest.publisherPrefix
        projectNamespace = $Manifest.projectNamespace
        table = $candidate[0]
        statusChoice = $Manifest.globalChoice
        candidateReferenceRelationships = $relationships
        excluded = @('os_sr_call', 'os_sr_csh', 'os_sr_callout', 'os_sr_cact', 'plug-in', 'roles', 'app navigation', 'business records')
    }
}

function Assert-Manifest {
    param([Parameter(Mandatory = $true)][object]$Manifest)
    $hash = Get-FileSha256 -Path $script:ManifestPath
    if ($hash -cne $script:ExpectedManifestSha256) {
        throw 'Manifest fingerprint changed; no environment request or write is allowed.'
    }
    if ($Manifest.status -cne 'CANDIDATE_TABLE_KEYS_LOOKUPS_AND_SOLUTION_MEMBERSHIP_RECONCILED' -or
        $Manifest.solutionUniqueName -cne $script:SolutionName -or
        $Manifest.publisherPrefix -cne $script:PublisherPrefix -or
        $Manifest.projectNamespace -cne $script:NamespacePrefix -or
        $Manifest.globalChoice.logicalName -cne $script:ChoiceName) {
        throw 'Candidate-only manifest identity or proposal state differs from the guarded baseline.'
    }
    $candidate = @($Manifest.tables | Where-Object logicalName -CEQ $script:CandidateName)
    if ($candidate.Count -ne 1 -or $candidate[0].ownership -cne 'UserOwned' -or
        $candidate[0].primaryName.logicalName -cne 'os_sr_cand_cnum' -or
        $candidate[0].primaryName.type -cne 'AutoNumber' -or
        $candidate[0].primaryName.format -cne 'CAND-{SEQNUM:8}' -or
        $candidate[0].primaryName.maxLength -ne 100 -or
        -not $candidate[0].audit.enabled) {
        throw 'Candidate table ownership, AutoNumber, length, or auditing proposal differs from the approved baseline.'
    }
    $options = @($Manifest.globalChoice.options)
    $expectedValues = @(100010000, 100010001, 100010002, 100010003, 100010004, 100010005)
    if ($options.Count -ne $script:StatusLabels.Count -or
        (Compare-Object $script:StatusLabels @($options | ForEach-Object label)).Count -ne 0 -or
        (Compare-Object $expectedValues @($options | ForEach-Object value)).Count -ne 0 -or
        [int]$Manifest.globalChoice.valuePrefix -ne 10001 -or
        [int]$Manifest.globalChoice.defaultValue -ne 100010000 -or
        $Manifest.globalChoice.valueStatus -notmatch 'GET-reconciled') {
        throw 'Candidate Status options must match the frozen Dataverse GET-reconciled label/value mapping.'
    }
    $statusColumn = @($candidate[0].columns | Where-Object logicalName -CEQ 'os_sr_cand_stat')
    if ($statusColumn.Count -ne 1 -or [int]$statusColumn[0].defaultValue -ne 100010000) {
        throw 'Candidate Status column default differs from the frozen Dataverse Choice allocation.'
    }
    $script:ApprovedStatusOptions = @($options)
    $expectedRelationships = @('os_sr_pos_cand', 'os_sr_csrc_cand', 'os_sr_ta_cand')
    if ((Compare-Object $expectedRelationships @($Manifest.relationships | Where-Object {
        $_.child -ceq $script:CandidateName -and $_.parent -in @('os_sr_pos', 'os_sr_csrc', 'os_sr_ta')
    } | ForEach-Object schemaName)).Count -ne 0) {
        throw 'Candidate reference relationship proposal differs from the approved baseline.'
    }
    $projectionHash = Get-PayloadSha256 -Payload (Get-CandidateProjection -Manifest $Manifest)
    if ($projectionHash -cne $script:ExpectedCandidateProjectionSha256) {
        throw 'Candidate-only proposal projection fingerprint changed; no environment request or write is allowed.'
    }
    [ordered]@{
        ManifestSha256 = $hash
        CandidateProjectionSha256 = $projectionHash
        CandidateTable = $script:CandidateName
        CandidateStatusChoice = $script:ChoiceName
        Excluded = @($script:ExcludedTables) + @($script:ExcludedChoice) + @('os_sr_cact', 'plug-in', 'roles', 'app navigation', 'business records')
    }
}

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

function New-StringAttribute {
    param(
        [Parameter(Mandatory = $true)][string]$SchemaName,
        [Parameter(Mandatory = $true)][string]$DisplayName,
        [Parameter(Mandatory = $true)][int]$MaxLength,
        [ValidateSet('Text', 'Email', 'Phone', 'Url')][string]$FormatName = 'Text',
        [ValidateSet('None', 'ApplicationRequired')][string]$RequiredLevel = 'None',
        [bool]$IsPrimaryName = $false,
        [string]$AutoNumberFormat
    )
    $attribute = [ordered]@{
        '@odata.type' = 'Microsoft.Dynamics.CRM.StringAttributeMetadata'
        AttributeType = 'String'
        AttributeTypeName = [ordered]@{ Value = 'StringType' }
        SchemaName = $SchemaName
        DisplayName = New-Label -Text $DisplayName
        RequiredLevel = New-RequiredLevel -Value $RequiredLevel
        FormatName = [ordered]@{ Value = $FormatName }
        MaxLength = $MaxLength
        IsPrimaryName = $IsPrimaryName
    }
    if ($AutoNumberFormat) { $attribute.AutoNumberFormat = $AutoNumberFormat }
    $attribute
}

function New-ChoicePayload {
    param([Parameter(Mandatory = $true)][object]$Manifest)
    [ordered]@{
        '@odata.type' = 'Microsoft.Dynamics.CRM.OptionSetMetadata'
        Name = $script:ChoiceName
        DisplayName = New-Label -Text 'Candidate Workflow Status'
        OptionSetType = 'Picklist'
        Options = @($Manifest.globalChoice.options | ForEach-Object {
            [ordered]@{ Value = $null; Label = (New-Label -Text ([string]$_.label)) }
        })
    }
}

function New-CandidateTablePayload {
    param([Parameter(Mandatory = $true)][object]$Manifest, [Parameter(Mandatory = $true)][int]$StatusDefault)
    $candidate = @($Manifest.tables | Where-Object logicalName -CEQ $script:CandidateName)[0]
    $attributes = [System.Collections.Generic.List[object]]::new()
    $attributes.Add((New-StringAttribute -SchemaName 'os_sr_cand_cnum' -DisplayName 'Candidate Number' `
        -MaxLength 100 -FormatName Text -RequiredLevel ApplicationRequired -IsPrimaryName $true -AutoNumberFormat 'CAND-{SEQNUM:8}'))
    $attributes.Add((New-StringAttribute -SchemaName 'os_sr_cand_nm' -DisplayName 'Candidate Name' -MaxLength 200 -RequiredLevel ApplicationRequired))
    $attributes.Add((New-StringAttribute -SchemaName 'os_sr_cand_eml' -DisplayName 'Candidate Email' -MaxLength 254 -FormatName Email -RequiredLevel ApplicationRequired))
    $attributes.Add((New-StringAttribute -SchemaName 'os_sr_cand_phn' -DisplayName 'Candidate Phone' -MaxLength 50 -FormatName Phone))
    $attributes.Add((New-StringAttribute -SchemaName 'os_sr_cand_corid' -DisplayName 'Creation Correlation ID' -MaxLength 36))
    $attributes.Add((New-StringAttribute -SchemaName 'os_sr_cand_cvurl' -DisplayName 'Candidate CV URL' -MaxLength 2000 -FormatName Url))
    $status = [ordered]@{
        '@odata.type' = 'Microsoft.Dynamics.CRM.PicklistAttributeMetadata'
        AttributeType = 'Picklist'
        AttributeTypeName = [ordered]@{ Value = 'PicklistType' }
        SchemaName = 'os_sr_cand_stat'
        DisplayName = New-Label -Text 'Candidate Workflow Status'
        RequiredLevel = New-RequiredLevel -Value ApplicationRequired
        DefaultFormValue = $StatusDefault
        IsPrimaryName = $false
        'GlobalOptionSet@odata.bind' = $null
    }
    $attributes.Add($status)
    [ordered]@{
        '@odata.type' = 'Microsoft.Dynamics.CRM.EntityMetadata'
        SchemaName = $script:CandidateName
        DisplayName = New-Label -Text 'Candidate'
        DisplayCollectionName = New-Label -Text 'Candidates'
        Description = New-Label -Text 'Candidate core business record.'
        OwnershipType = 'UserOwned'
        IsActivity = $false
        HasActivities = $false
        HasNotes = $false
        IsAuditEnabled = [ordered]@{
            Value = [bool]$candidate.audit.enabled
            CanBeChanged = $true
            ManagedPropertyLogicalName = 'canmodifyauditsettings'
        }
        Attributes = $attributes.ToArray()
    }
}

function Assert-ApplyAuthorization {
    if (-not $ContinueAfterTable -or $Confirmation -cne 'CONTINUE-CANDIDATE-SCHEMA' -or
        [string]::IsNullOrWhiteSpace($AuthorizationReference)) {
        throw 'Apply requires the exact Candidate table continuation, confirmation, and owner-authorization reference.'
    }
    if ($script:MaximumWrites -ne 5) { throw 'Candidate-only table continuation write ceiling changed.' }
}

function Assert-TargetConfiguration {
    if ($script:EnvironmentName -cne 'VN LMV IT' -or
        [string]::IsNullOrWhiteSpace($script:OrganizationUrl) -or
        [string]::IsNullOrWhiteSpace($script:ExpectedEnvironmentId) -or
        [string]::IsNullOrWhiteSpace($script:ExpectedOrganizationId)) {
        throw 'Configured VN LMV IT target is incomplete; do not switch or sign in.'
    }
    $org = [Uri]$script:OrganizationUrl
    if ($org.Scheme -cne 'https' -or $org.AbsolutePath -ne '/' -or $org.Query -or $org.Fragment) {
        throw 'Configured organization URL is not a plain HTTPS origin.'
    }
    foreach ($id in @($script:ExpectedEnvironmentId, $script:ExpectedOrganizationId)) {
        $guid = [Guid]::Empty
        if (-not [Guid]::TryParse($id, [ref]$guid)) { throw 'Configured target identifiers are invalid.' }
    }
}

function Assert-PacIdentity {
    $output = @(& pac env who 2>&1 | ForEach-Object { [string]$_ })
    if ($LASTEXITCODE -ne 0) { throw 'PAC active identity check failed; no environment switch or sign-in attempted.' }
    $text = $output -join "`n"
    $name = [regex]::Match($text, '(?m)^\s*Friendly Name:\s*(.+?)\s*$')
    $url = [regex]::Match($text, '(?m)^\s*Org URL:\s*(\S+)')
    $org = [regex]::Match($text, '(?m)^\s*Org ID:\s*([0-9a-fA-F-]{36})')
    $envId = [regex]::Match($text, '(?m)^\s*Environment ID:\s*([0-9a-fA-F-]{36})')
    $userId = [regex]::Match($text, '(?m)^\s*User ID:\s*([0-9a-fA-F-]{36})')
    $email = [regex]::Match($text, '(?m)^\s*User Email:\s*(\S+)')
    if (-not ($name.Success -and $url.Success -and $org.Success -and $envId.Success -and $userId.Success -and $email.Success) -or
        $name.Groups[1].Value -cne 'VN LMV IT') {
        throw 'PAC active target is not the approved VN LMV IT environment.'
    }
    $configured = @($EnvironmentName, $OrganizationUrl, $ExpectedEnvironmentId, $ExpectedOrganizationId)
    $configuredCount = @($configured | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count
    if ($configuredCount -notin @(0, 4)) {
        throw 'The configured target pin is incomplete; no PAC-derived fallback is allowed.'
    }
    if ($configuredCount -eq 4 -and
        ($EnvironmentName -cne 'VN LMV IT' -or
         $url.Groups[1].Value.TrimEnd('/') -cne $OrganizationUrl.TrimEnd('/') -or
         $org.Groups[1].Value -ine $ExpectedOrganizationId -or
         $envId.Groups[1].Value -ine $ExpectedEnvironmentId)) {
        throw 'PAC active target differs from the configured VN LMV IT target.'
    }
    $script:EnvironmentName = 'VN LMV IT'
    $script:OrganizationUrl = $url.Groups[1].Value.TrimEnd('/')
    $script:ExpectedOrganizationId = $org.Groups[1].Value.ToLowerInvariant()
    $script:ExpectedEnvironmentId = $envId.Groups[1].Value.ToLowerInvariant()
    $script:PacUserId = $userId.Groups[1].Value.ToLowerInvariant()
    $script:PacUserEmail = $email.Groups[1].Value
    [Environment]::SetEnvironmentVariable('BSO_RS_EXPECTED_USER_ID', $script:PacUserId, 'Process')
    if ([Environment]::GetEnvironmentVariable('BSO_RS_EXPECTED_USER_ID', 'Process') -cne $script:PacUserId) {
        throw 'Process-scoped expected-user guard could not be established from the verified PAC context.'
    }
}

function Get-ValidatedToken {
    if (-not (Get-Module -ListAvailable -Name Az.Accounts)) { throw 'Existing Az.Accounts installation is unavailable.' }
    Import-Module Az.Accounts -ErrorAction Stop
    $tokenCommand = Get-Command Az.Accounts\Get-AzAccessToken -ErrorAction Stop
    if (-not $tokenCommand.Parameters.ContainsKey('ResourceUrl') -or
        -not $tokenCommand.Parameters.ContainsKey('AsSecureString')) {
        throw 'Az.Accounts does not support the required secure Dataverse token path.'
    }
    $context = Get-AzContext -ErrorAction Stop
    if ($null -eq $context -or $context.Account.Type -ne 'User' -or $context.Account.Id -ine $script:PacUserEmail) {
        throw 'Existing Az.Accounts user context does not match PAC; no sign-in or context switch attempted.'
    }
    $result = $null
    $secure = $null
    $token = $null
    try {
        $result = Get-AzAccessToken -ResourceUrl $script:OrganizationUrl -AsSecureString -ErrorAction Stop
        $secure = $result.Token
        if ($secure -isnot [Security.SecureString]) { throw 'Az.Accounts did not return a secure token.' }
        $token = ConvertFrom-SecureString -SecureString $secure -AsPlainText
        $parts = $token.Split('.')
        if ($parts.Count -ne 3) { throw 'Dataverse access token was not a JWT.' }
        $payload = $parts[1].Replace('-', '+').Replace('_', '/')
        switch ($payload.Length % 4) { 2 { $payload += '==' } 3 { $payload += '=' } }
        $claims = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload)) | ConvertFrom-Json
        $audience = [Uri]([string]$claims.aud)
        $expires = [DateTimeOffset]::FromUnixTimeSeconds([long]$claims.exp)
        $issued = [DateTimeOffset]::FromUnixTimeSeconds([long]$claims.iat)
        $context = Get-AzContext -ErrorAction Stop
        if ($claims.tid -ine $context.Tenant.Id -or $audience.Authority -ine ([Uri]$script:OrganizationUrl).Authority -or
            'user_impersonation' -notin @(([string]$claims.scp) -split '\s+') -or
            $expires -le [DateTimeOffset]::UtcNow -or
            [math]::Abs(($expires - [DateTimeOffset]$result.ExpiresOn).TotalMinutes) -gt 2) {
            throw 'Dataverse token target, tenant, delegated scope, or expiry validation failed.'
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
    $uri = if ([Uri]::IsWellFormedUriString($Path, [UriKind]::Absolute)) { [Uri]$Path } else { [Uri]($script:ApiRoot + $Path) }
    if ($uri.Scheme -cne 'https' -or $uri.Authority -ine ([Uri]$script:OrganizationUrl).Authority -or
        $uri.AbsolutePath -notmatch '^/api/data/v9\.2/' -or $uri.UserInfo -or $uri.Fragment) {
        throw 'Dataverse request target is outside the verified organization API.'
    }
    if ($Method -eq 'POST') {
        $expectedOrder = @(
            'GlobalOptionSetDefinitions',
            'EntityDefinitions',
            "EntityDefinitions(LogicalName='$($script:CandidateName)')/Keys",
            "EntityDefinitions(LogicalName='$($script:CandidateName)')/Keys",
            'RelationshipDefinitions',
            'RelationshipDefinitions',
            'RelationshipDefinitions'
        )
        if ($ContinueAfterTable) { $expectedOrder = @($expectedOrder | Select-Object -Skip 2) }
        $expectedPath = if ($script:WriteStages.Count -lt $expectedOrder.Count) {
            $expectedOrder[$script:WriteStages.Count]
        } else { $null }
        $bodyMatchesPath = switch ($Path) {
            'GlobalOptionSetDefinitions' {
                $Body.Name -ceq $script:ChoiceName -and @($Body.Options).Count -eq $script:StatusLabels.Count -and
                @($Body.Options | Where-Object { $null -ne $_.Value }).Count -eq 0
                break
            }
            'EntityDefinitions' {
                $Body.SchemaName -ceq $script:CandidateName -and $Body.OwnershipType -ceq 'UserOwned' -and
                @($Body.Attributes).Count -eq 7 -and $Body.IsAuditEnabled.Value -eq $true
                break
            }
            "EntityDefinitions(LogicalName='$($script:CandidateName)')/Keys" {
                $Body.SchemaName -in @('os_sr_cand_ak_cnum', 'os_sr_cand_ak_corid') -and
                @($Body.KeyAttributes).Count -eq 1
                break
            }
            'RelationshipDefinitions' {
                $Body.SchemaName -in @('os_sr_pos_cand', 'os_sr_csrc_cand', 'os_sr_ta_cand') -and
                $Body.ReferencingEntity -ceq $script:CandidateName
                break
            }
            default { $false }
        }
        if ($Path -cne $expectedPath -or -not $bodyMatchesPath -or -not $WithSolutionHeader -or
            $script:RequestCounts.POST -ge $script:MaximumWrites) {
            throw 'Write path or count is outside the Candidate-only allowlist.'
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
        ResponseHeadersVariable = 'responseHeaders'
    }
    if ($PSBoundParameters.ContainsKey('Body')) {
        $request.ContentType = 'application/json; charset=utf-8'
        $request.Body = ConvertTo-Json -InputObject $Body -Depth 80 -Compress
    }
    $script:RequestCounts[$Method]++
    if ($Method -eq 'POST') {
        $script:LastWriteStage = $Path
        $script:LastWriteHttpStatus = 'UNKNOWN'
        $script:WriteStages.Add($Path)
    }
    try { $response = Invoke-RestMethod @request }
    catch {
        if ($Method -eq 'POST') {
            throw 'Dataverse POST transport failed; reconcile before any new write.'
        }
        throw 'Dataverse GET transport failed; no write was sent by this request.'
    }
    if ($Method -eq 'POST') { $script:LastWriteHttpStatus = [int]$statusCode }
    if ([int]$statusCode -lt 200 -or [int]$statusCode -ge 300) {
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
    $response = Invoke-DataverseRequest -Method GET -Path $Path
    @($response.value)
}

function Assert-GlobalPrivileges {
    $required = @('prvCreateEntity', 'prvCreateAttribute', 'prvCreateCustomization')
    $names = ConvertTo-Json -InputObject $required -Compress
    $path = "systemusers($($script:PacUserId))/Microsoft.Dynamics.CRM.RetrieveUserSetOfPrivilegesByNames(PrivilegeNames=@p)?@p=$([Uri]::EscapeDataString($names))"
    $result = Invoke-DataverseRequest -Method GET -Path $path
    foreach ($name in $required) {
        $matches = @($result.RolePrivileges | Where-Object PrivilegeName -CEQ $name)
        if ($matches.Count -ne 1 -or [string]$matches[0].Depth -notin @('Global', '3')) {
            throw 'Required global metadata privileges were not proven.'
        }
    }
}

function Assert-LiveReadiness {
    $script:CurrentStage = 'LIVE_WHOAMI'
    $who = Invoke-DataverseRequest -Method GET -Path 'WhoAmI'
    if ([string]$who.OrganizationId -ine $script:ExpectedOrganizationId -or
        [string]$who.UserId -ine $script:PacUserId -or
        [Environment]::GetEnvironmentVariable('BSO_RS_EXPECTED_USER_ID', 'Process') -cne $script:PacUserId) {
        throw 'PAC, Az.Accounts, Dataverse WhoAmI, or the process-scoped user guard differ.'
    }
    $script:CurrentStage = 'LIVE_PUBLISHER'
    $publishers = @(Get-ODataRows -Path "publishers?`$select=publisherid,uniquename,friendlyname,customizationprefix,customizationoptionvalueprefix&`$filter=uniquename eq '$($script:PublisherName)'")
    if ($publishers.Count -ne 1 -or $publishers[0].uniquename -cne $script:PublisherName -or
        $publishers[0].customizationprefix -cne $script:PublisherPrefix -or
        [int]$publishers[0].customizationoptionvalueprefix -le 0) {
        throw 'Exact project Publisher or its option-value prefix was not verified.'
    }
    $script:CurrentStage = 'LIVE_SOLUTION'
    $solutions = @(Get-ODataRows -Path "solutions?`$select=solutionid,uniquename,ismanaged,_publisherid_value&`$filter=uniquename eq '$($script:SolutionName)'")
    if ($solutions.Count -ne 1 -or $solutions[0].uniquename -cne $script:SolutionName -or
        [bool]$solutions[0].ismanaged -or
        [string]$solutions[0]._publisherid_value -ine [string]$publishers[0].publisherid) {
        throw 'Exact unmanaged project Solution/Publisher linkage was not verified.'
    }
    $script:Publisher = $publishers[0]
    $script:Solution = $solutions[0]
    $script:CurrentStage = 'LIVE_PRIVILEGES'
    Assert-GlobalPrivileges
    foreach ($name in $script:ExcludedTables) {
        $script:CurrentStage = "LIVE_TABLE_$name"
        $found = Get-OptionalMetadata -Path "EntityDefinitions(LogicalName='$name')?`$select=LogicalName,MetadataId,OwnershipType,PrimaryIdAttribute,PrimaryNameAttribute,IsAuditEnabled"
        if ($null -ne $found) { throw 'Candidate-only table inventory differs from the approved all-absent baseline.' }
    }
    $expectedPrimaryNames = @{
        os_sr_pos = 'os_sr_pos_ttl'
        os_sr_csrc = 'os_sr_csrc_nm'
        os_sr_ta = 'os_sr_ta_nm'
    }
    foreach ($name in @('os_sr_pos', 'os_sr_csrc', 'os_sr_ta')) {
        $script:CurrentStage = "LIVE_REFERENCE_$name"
        $table = Get-OptionalMetadata -Path "EntityDefinitions(LogicalName='$name')?`$select=LogicalName,MetadataId,OwnershipType,PrimaryIdAttribute,PrimaryNameAttribute"
        if ($null -eq $table -or [string]$table.LogicalName -cne $name -or
            [string]::IsNullOrWhiteSpace([string]$table.PrimaryIdAttribute) -or
            [string]$table.PrimaryNameAttribute -cne $expectedPrimaryNames[$name]) {
            throw 'An approved Candidate reference table is absent or has invalid metadata.'
        }
    }
    $script:CurrentStage = 'LIVE_CANDIDATE_STATUS_CHOICE_LOOKUP'
    $choice = Get-OptionalMetadata -Path "GlobalOptionSetDefinitions(Name='$($script:ChoiceName)')?`$select=MetadataId,Name"
    if ($null -eq $choice) {
        $script:CandidateStatusChoiceAbsent = $true
        $script:CandidateStatusChoiceOptions = @()
    }
    else {
        $script:CandidateStatusChoiceAbsent = $false
        $script:CurrentStage = 'LIVE_CANDIDATE_STATUS_CHOICE_RECONCILIATION'
        $choiceState = Assert-ChoiceReadback
        $script:CandidateStatusChoiceOptions = $choiceState.Options
        if ((Compare-Object @($script:ApprovedStatusOptions | ForEach-Object { [int]$_.value }) `
                @($script:CandidateStatusChoiceOptions | ForEach-Object { [int]$_.Value })).Count -ne 0) {
            $script:SafeBlockReason = 'LIVE_CHOICE_VALUES_DIFFER_FROM_FROZEN_MANIFEST'
            throw 'Live Candidate Status values differ from the frozen local manifest.'
        }
    }
    $script:CurrentStage = 'LIVE_CANDIDATE_TABLE_STATE'
    $candidateMetadata = Get-OptionalMetadata -Path "EntityDefinitions(LogicalName='$($script:CandidateName)')?`$select=LogicalName,MetadataId,OwnershipType,PrimaryIdAttribute,PrimaryNameAttribute,IsAuditEnabled"
    if ($ContinueAfterTable) {
        if ($null -eq $candidateMetadata) { throw 'Candidate table is not visible; continuation cannot create or retry it.' }
        $candidateState = Assert-CandidateReadback -ChoiceState $choiceState
        $keyNames = @('os_sr_cand_ak_cnum', 'os_sr_cand_ak_corid')
        $existingKeys = @(Get-ODataRows -Path "EntityDefinitions(LogicalName='$($script:CandidateName)')/Keys")
        if (@($existingKeys | Where-Object { $_.SchemaName -in $keyNames }).Count -ne 0) {
            throw 'A Candidate alternate key already exists; no duplicate or recovery write is permitted.'
        }
        $relationshipNames = @('os_sr_pos_cand', 'os_sr_csrc_cand', 'os_sr_ta_cand')
        $existingRelationships = @(Get-ODataRows -Path "EntityDefinitions(LogicalName='$($script:CandidateName)')/ManyToOneRelationships")
        if (@($existingRelationships | Where-Object { $_.SchemaName -in $relationshipNames }).Count -ne 0) {
            throw 'A Candidate reference relationship already exists; no duplicate or recovery write is permitted.'
        }
    }
    elseif ($null -ne $candidateMetadata) {
        throw 'Candidate table already exists; creation is not safe under the initial-provisioning path.'
    }
    $script:CurrentStage = 'LIVE_ORGANIZATION_AUDIT'
    $organization = Invoke-DataverseRequest -Method GET -Path "organizations($script:ExpectedOrganizationId)?`$select=organizationid,isauditenabled,isuseraccessauditenabled"
    if ([string]$organization.organizationid -ine $script:ExpectedOrganizationId) {
        throw 'Organization identity did not match the approved target during audit-state inspection.'
    }
    [ordered]@{
        TargetGuard = 'PASS'
        TargetSource = 'Existing PAC active profile; no environment switch'
        PacAzWhoAmI = 'AGREED'
        ExpectedUserProcessGuard = 'PASS'
        SolutionPublisher = 'PASS'
        MetadataPrivileges = 'GLOBAL'
        CandidateTable = if ($null -ne $candidateMetadata) { 'PRESENT_AND_RECONCILED' } else { 'ABSENT' }
        ExcludedTables = 'ABSENT'
        CandidateReferences = 'PRESENT'
        CandidateStatusChoice = if ($script:CandidateStatusChoiceAbsent) { 'ABSENT' } else { 'PRESENT_AND_RECONCILED' }
        CandidateStatusOptions = @($script:CandidateStatusChoiceOptions | ForEach-Object {
            [ordered]@{ Label = $_.Label; Value = $_.Value }
        })
        CandidateKeys = if ($ContinueAfterTable) { 'NOT_PRESENT' } else { 'NOT_APPLICABLE' }
        CandidateReferenceRelationships = if ($ContinueAfterTable) { 'NOT_PRESENT' } else { 'NOT_APPLICABLE' }
        OrganizationAuditing = if ($organization.isauditenabled) { 'ENABLED' } else { 'DISABLED; NO CANDIDATE DATA MAY BE CREATED' }
        UserAccessAuditing = [bool]$organization.isuseraccessauditenabled
        OptionValuePrefix = [int]$script:Publisher.customizationoptionvalueprefix
    }
}

function Assert-SolutionMembership {
    param(
        [Parameter(Mandatory = $true)][Guid]$ObjectId,
        [int]$ExpectedComponentType = -1,
        [int]$ExpectedRootComponentBehavior = -1
    )
    $solutionId = [string]$script:Solution.solutionid
    $filter = [Uri]::EscapeDataString("_solutionid_value eq $solutionId")
    $components = @(Get-ODataRows -Path "solutioncomponents?`$select=componenttype,objectid,rootcomponentbehavior&`$filter=$filter")
    $matches = @($components | Where-Object { [string]$_.objectid -ieq [string]$ObjectId })
    $script:LastSolutionMembershipCount = $matches.Count
    if ($matches.Count -ne 1 -or [string]$matches[0].objectid -ine [string]$ObjectId) {
        $script:SafeBlockReason = if ($matches.Count -eq 0) { 'SOLUTION_COMPONENT_NOT_FOUND' } else { 'SOLUTION_COMPONENT_COUNT_MISMATCH' }
        throw 'A newly created Candidate component is not present exactly once in the approved Solution.'
    }
    if (($ExpectedComponentType -ge 0 -and [int]$matches[0].componenttype -ne $ExpectedComponentType) -or
        ($ExpectedRootComponentBehavior -ge 0 -and [int]$matches[0].rootcomponentbehavior -ne $ExpectedRootComponentBehavior)) {
        $script:SafeBlockReason = 'SOLUTION_COMPONENT_TYPE_OR_ROOT_BEHAVIOR_MISMATCH'
        throw 'The Solution component type or root inclusion behavior differed from the approved Candidate scope.'
    }
}

function Assert-ChoiceReadback {
    $choice = Get-OptionalMetadata -Path "GlobalOptionSetDefinitions(Name='$($script:ChoiceName)')"
    if ($null -eq $choice -or [string]$choice.Name -cne $script:ChoiceName -or
        $choice.IsGlobal -ne $true -or [string]$choice.OptionSetType -cne 'Picklist' -or
        $choice.Options.Count -ne $script:StatusLabels.Count) {
        $script:SafeBlockReason = 'CHOICE_METADATA_NAME_TYPE_OR_OPTION_COUNT_MISMATCH'
        throw 'Candidate Status Choice read-back failed; stop and reconcile without retry.'
    }
    $actual = @($choice.Options | ForEach-Object {
        [pscustomobject]@{ Label = [string]$_.Label.UserLocalizedLabel.Label; Value = [int]$_.Value }
    })
    if ((Compare-Object $script:StatusLabels @($actual | ForEach-Object Label)).Count -ne 0 -or
        @($actual | Select-Object -ExpandProperty Value -Unique).Count -ne $script:StatusLabels.Count -or
        @($actual | Where-Object { $_.Value -le 0 }).Count -ne 0) {
        $script:SafeBlockReason = 'CHOICE_LABEL_OR_ALLOCATED_VALUE_MISMATCH'
        throw 'Candidate Status Choice values or labels failed exact reconciliation.'
    }
    $script:CurrentStage = 'LIVE_CANDIDATE_STATUS_SOLUTION_MEMBERSHIP'
    Assert-SolutionMembership -ObjectId ([Guid]$choice.MetadataId) -ExpectedComponentType 9
    [pscustomobject]@{ Metadata = $choice; Options = $actual }
}

function Assert-CandidateReadback {
    param([Parameter(Mandatory = $true)][object]$ChoiceState)
    $table = Get-OptionalMetadata -Path "EntityDefinitions(LogicalName='$($script:CandidateName)')?`$select=LogicalName,MetadataId,OwnershipType,PrimaryIdAttribute,PrimaryNameAttribute,IsAuditEnabled"
    if ($null -eq $table -or $table.OwnershipType -cne 'UserOwned' -or
        $table.IsAuditEnabled.Value -ne $true -or
        $table.PrimaryNameAttribute -cne 'os_sr_cand_cnum' -or
        [string]::IsNullOrWhiteSpace([string]$table.PrimaryIdAttribute)) {
        $script:SafeBlockReason = 'CANDIDATE_TABLE_OWNERSHIP_OR_AUDIT_MISMATCH'
        throw 'Candidate table read-back failed ownership or auditing verification.'
    }
    Assert-SolutionMembership -ObjectId ([Guid]$table.MetadataId) -ExpectedComponentType 1 -ExpectedRootComponentBehavior 0
    $allAttributes = @(Get-ODataRows -Path "EntityDefinitions(LogicalName='$($script:CandidateName)')/Attributes")
    $virtualAttributes = @($allAttributes | Where-Object {
        [string]$_.LogicalName -like 'os_sr_cand_*' -and [string]$_.AttributeType -ceq 'Virtual'
    })
    if ($virtualAttributes.Count -ne 1 -or $virtualAttributes[0].LogicalName -cne 'os_sr_cand_statname') {
        $script:SafeBlockReason = 'CANDIDATE_GENERATED_VIRTUAL_ATTRIBUTE_MISMATCH'
        throw 'Candidate table generated virtual attribute set differed from the expected Choice name column.'
    }
    $expectedLookupNameAttributes = @{
        os_sr_cand_posname = 'os_sr_cand_pos'
        os_sr_cand_csrcname = 'os_sr_cand_csrc'
        os_sr_cand_taname = 'os_sr_cand_ta'
    }
    $lookupNameAttributes = @($allAttributes | Where-Object {
        [string]$_.LogicalName -in $expectedLookupNameAttributes.Keys
    })
    if ($lookupNameAttributes.Count -ne $expectedLookupNameAttributes.Count) {
        $script:SafeBlockReason = 'CANDIDATE_GENERATED_LOOKUP_NAME_ATTRIBUTE_MISMATCH'
        throw 'Candidate lookup companion attribute set differed from the approved lookups.'
    }
    foreach ($expectedName in $expectedLookupNameAttributes.Keys) {
        $generatedName = @($lookupNameAttributes | Where-Object LogicalName -CEQ $expectedName)
        if ($generatedName.Count -ne 1 -or $generatedName[0].AttributeType -cne 'String' -or
            [string]$generatedName[0].AttributeOf -cne $expectedLookupNameAttributes[$expectedName]) {
            $script:SafeBlockReason = 'CANDIDATE_GENERATED_LOOKUP_NAME_ATTRIBUTE_MISMATCH'
            throw 'Candidate lookup companion attribute did not map to its approved lookup.'
        }
    }
    $generatedAttributeNames = @($virtualAttributes.LogicalName) + @($lookupNameAttributes.LogicalName)
    $attrs = @($allAttributes | Where-Object {
        [string]$_.LogicalName -like 'os_sr_cand_*' -and
        [string]$_.LogicalName -notin $generatedAttributeNames
    })
    $statusAttributeFilter = [Uri]::EscapeDataString("LogicalName eq 'os_sr_cand_stat'")
    $statusAttributeRows = @(Get-ODataRows -Path "EntityDefinitions(LogicalName='$($script:CandidateName)')/Attributes/Microsoft.Dynamics.CRM.PicklistAttributeMetadata?`$select=LogicalName,AttributeType,DefaultFormValue&`$filter=$statusAttributeFilter&`$expand=GlobalOptionSet")
    $statusAttributeMatches = @($statusAttributeRows | Where-Object {
        [string]$_.LogicalName -ceq 'os_sr_cand_stat'
    })
    if ($statusAttributeMatches.Count -ne 1) {
        $script:SafeBlockReason = 'CANDIDATE_STATUS_ATTRIBUTE_READBACK_MISMATCH'
        throw 'Candidate Status attribute could not be reconciled exactly.'
    }
    $statusAttribute = $statusAttributeMatches[0]
    $globalOptionSet = $statusAttribute.GlobalOptionSet
    $script:CandidateAttributeSummary = @($attrs | ForEach-Object {
        $attributeGlobalOptionSet = if ([string]$_.LogicalName -ceq 'os_sr_cand_stat') { $globalOptionSet } else { $null }
        [ordered]@{
            LogicalName = [string]$_.LogicalName
            AttributeType = [string]$_.AttributeType
            MaxLength = $_.MaxLength
            AutoNumberFormat = [string]$_.AutoNumberFormat
            DefaultFormValue = $_.DefaultFormValue
            GlobalOptionSetName = [string]$attributeGlobalOptionSet.Name
            GlobalOptionSetMetadataIdMatches = [string]$attributeGlobalOptionSet.MetadataId -ieq [string]$ChoiceState.Metadata.MetadataId
        }
    })
    $expectedAttributes = @{
        os_sr_cand_cnum = @{ Type = 'String'; MaxLength = 100; AutoNumberFormat = 'CAND-{SEQNUM:8}' }
        os_sr_cand_nm = @{ Type = 'String'; MaxLength = 200 }
        os_sr_cand_eml = @{ Type = 'String'; MaxLength = 254 }
        os_sr_cand_phn = @{ Type = 'String'; MaxLength = 50 }
        os_sr_cand_corid = @{ Type = 'String'; MaxLength = 36 }
        os_sr_cand_cvurl = @{ Type = 'String'; MaxLength = 2000 }
        os_sr_cand_stat = @{ Type = 'Picklist'; MaxLength = $null }
        os_sr_cand_pos = @{ Type = 'Lookup'; MaxLength = $null }
        os_sr_cand_csrc = @{ Type = 'Lookup'; MaxLength = $null }
        os_sr_cand_ta = @{ Type = 'Lookup'; MaxLength = $null }
    }
    if ($attrs.Count -ne $expectedAttributes.Count) {
        $script:SafeBlockReason = 'CANDIDATE_CUSTOM_ATTRIBUTE_COUNT_MISMATCH'
        throw 'Candidate table has an unexpected custom attribute count.'
    }
    foreach ($name in $expectedAttributes.Keys) {
        $matches = @($attrs | Where-Object LogicalName -CEQ $name)
        if ($matches.Count -ne 1 -or $matches[0].AttributeType -cne $expectedAttributes[$name].Type) {
            $script:SafeBlockReason = "CANDIDATE_ATTRIBUTE_TYPE_OR_NAME_MISMATCH_$name"
            throw "Candidate attribute read-back failed for $name."
        }
        if ($null -ne $expectedAttributes[$name].MaxLength -and
            [int]$matches[0].MaxLength -ne $expectedAttributes[$name].MaxLength) {
            $script:SafeBlockReason = "CANDIDATE_ATTRIBUTE_LENGTH_MISMATCH_$name"
            throw "Candidate attribute length read-back failed for $name."
        }
        if ($name -ceq 'os_sr_cand_cnum' -and $matches[0].AutoNumberFormat -cne 'CAND-{SEQNUM:8}') {
            $script:SafeBlockReason = 'CANDIDATE_AUTONUMBER_FORMAT_MISMATCH'
            throw 'Candidate Number AutoNumber format read-back failed.'
        }
        if ($name -in @('os_sr_cand_nm', 'os_sr_cand_eml', 'os_sr_cand_stat') -and
            $matches[0].RequiredLevel.Value -cne 'ApplicationRequired') {
            $script:SafeBlockReason = "CANDIDATE_REQUIREDNESS_MISMATCH_$name"
            throw 'Candidate requiredness read-back failed.'
        }
        if ($name -ceq 'os_sr_cand_phn' -and $matches[0].RequiredLevel.Value -cne 'None') {
            $script:SafeBlockReason = 'CANDIDATE_PHONE_REQUIREDNESS_MISMATCH'
            throw 'Candidate phone optionality read-back failed.'
        }
        if ($name -ceq 'os_sr_cand_stat' -and
            [int]$matches[0].DefaultFormValue -ne [int]($ChoiceState.Options | Where-Object Label -CEQ $script:StatusLabels[0]).Value) {
            $script:SafeBlockReason = 'CANDIDATE_STATUS_DEFAULT_MISMATCH'
            throw 'Candidate Status default does not match the allocated Need Call Candidate value.'
        }
        if ($name -ceq 'os_sr_cand_stat' -and
            ([string]$globalOptionSet.Name -cne $script:ChoiceName -or
                [string]$globalOptionSet.MetadataId -ine [string]$ChoiceState.Metadata.MetadataId -or
                $statusAttribute.AttributeType -cne 'Picklist')) {
            $script:SafeBlockReason = 'CANDIDATE_STATUS_CHOICE_BINDING_MISMATCH'
            throw 'Candidate Status column does not reference the reconciled global Choice.'
        }
    }
    [pscustomobject]@{ Metadata = $table; Attributes = $attrs }
}

function Assert-KeyAndRelationshipReadback {
    param([Parameter(Mandatory = $true)][object]$Candidate)
    $keys = @(Get-ODataRows -Path "EntityDefinitions(LogicalName='$($script:CandidateName)')/Keys?`$select=MetadataId,SchemaName,KeyAttributes,EntityKeyIndexStatus")
    foreach ($expected in @(
        @{ Name = 'os_sr_cand_ak_cnum'; Attribute = 'os_sr_cand_cnum' },
        @{ Name = 'os_sr_cand_ak_corid'; Attribute = 'os_sr_cand_corid' }
    )) {
        $key = @($keys | Where-Object SchemaName -CEQ $expected.Name)
        if ($key.Count -ne 1 -or @($key[0].KeyAttributes).Count -ne 1 -or
            $key[0].KeyAttributes[0] -cne $expected.Attribute) {
            throw 'Candidate alternate-key read-back did not match the approved proposal.'
        }
    }
    $relationships = @(Get-ODataRows -Path "EntityDefinitions(LogicalName='$($script:CandidateName)')/ManyToOneRelationships?`$select=MetadataId,SchemaName,ReferencedEntity,ReferencingEntity,ReferencedAttribute,ReferencingAttribute,CascadeConfiguration")
    foreach ($expected in @(
        @{ Name = 'os_sr_pos_cand'; Parent = 'os_sr_pos'; Attribute = 'os_sr_cand_pos' },
        @{ Name = 'os_sr_csrc_cand'; Parent = 'os_sr_csrc'; Attribute = 'os_sr_cand_csrc' },
        @{ Name = 'os_sr_ta_cand'; Parent = 'os_sr_ta'; Attribute = 'os_sr_cand_ta' }
    )) {
        $relationship = @($relationships | Where-Object SchemaName -CEQ $expected.Name)
        if ($relationship.Count -ne 1 -or $relationship[0].ReferencedEntity -cne $expected.Parent -or
            $relationship[0].ReferencingEntity -cne $script:CandidateName -or
            $relationship[0].ReferencingAttribute -cne $expected.Attribute -or
            $relationship[0].CascadeConfiguration.Delete -cne 'Restrict' -or
            $relationship[0].CascadeConfiguration.Assign -cne 'NoCascade' -or
            $relationship[0].CascadeConfiguration.Reparent -cne 'NoCascade' -or
            $relationship[0].CascadeConfiguration.Share -cne 'NoCascade') {
            throw 'Candidate lookup relationship read-back did not match the approved proposal.'
        }
    }
    Assert-SolutionMembership -ObjectId ([Guid]$Candidate.Metadata.MetadataId) -ExpectedComponentType 1 -ExpectedRootComponentBehavior 0
    $keys
}

function Reconcile-AfterFailure {
    $result = [ordered]@{
        Completed = $false
        Outcome = 'UNKNOWN'
        Tables = @()
        Choice = 'UNKNOWN'
        Keys = @()
        Relationships = @()
    }
    try {
        $result.Choice = if ($null -ne (Get-OptionalMetadata -Path "GlobalOptionSetDefinitions(Name='$($script:ChoiceName)')")) { 'PRESENT_REQUIRES_REVIEW' } else { 'ABSENT' }
        foreach ($name in @($script:CandidateName) + $script:ExcludedTables) {
            $item = Get-OptionalMetadata -Path "EntityDefinitions(LogicalName='$name')?`$select=LogicalName,MetadataId"
            if ($null -ne $item) { $result.Tables += [string]$item.LogicalName }
        }
        if ($result.Tables -contains $script:CandidateName) {
            $result.Keys = @(Get-ODataRows -Path "EntityDefinitions(LogicalName='$($script:CandidateName)')/Keys")
            $result.Relationships = @(Get-ODataRows -Path "EntityDefinitions(LogicalName='$($script:CandidateName)')/ManyToOneRelationships")
        }
        $result.Completed = $true
        $result.Outcome = if ($result.Choice -eq 'ABSENT' -and $result.Tables.Count -eq 0) { 'NO_COMPONENTS_FOUND' } else { 'PARTIAL_OR_UNCERTAIN_STATE' }
    }
    catch { $result.Outcome = 'RECONCILIATION_FAILED' }
    $result
}

$script:ManifestPath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\docs\PHASE_3A_CANDIDATE_CORE_METADATA_PLAN.json'))
$manifest = Get-Content -LiteralPath $script:ManifestPath -Raw | ConvertFrom-Json
$proposal = Assert-Manifest -Manifest $manifest
if (-not $Apply -and -not $PreflightOnly -and -not $ReconcileOnly) {
    $previewPayload = New-CandidateTablePayload -Manifest $manifest -StatusDefault ([int]$manifest.globalChoice.defaultValue)
    if ($previewPayload.SchemaName -cne $script:CandidateName -or
        $previewPayload.Attributes.Count -ne 7 -or
        $previewPayload.Attributes[0].MaxLength -ne 100 -or
        $previewPayload.Attributes[6].'GlobalOptionSet@odata.bind' -ne $null) {
        throw 'Offline Candidate metadata payload construction failed.'
    }
    [ordered]@{
        Mode = 'PLAN_ONLY'
        Proposal = $proposal
        CandidateTablePayload = 'STRUCTURE_VALIDATED; live Choice binding requires the verified metadata ID.'
        CandidateAttributes = @($previewPayload.Attributes | ForEach-Object SchemaName)
        DataverseRequests = 0
        Writes = 0
    } | ConvertTo-Json -Depth 20
    return
}

$failure = $null
$reconciliation = $null
try {
    $modeCount = 0
    if ($Apply) { $modeCount++ }
    if ($PreflightOnly) { $modeCount++ }
    if ($ReconcileOnly) { $modeCount++ }
    if ($modeCount -gt 1) {
        throw 'Apply, PreflightOnly, and ReconcileOnly are mutually exclusive.'
    }
    if ($Apply) { Assert-ApplyAuthorization }
    $script:CurrentStage = 'PAC_IDENTITY'
    Assert-PacIdentity
    $script:CurrentStage = 'TARGET_GUARD'
    Assert-TargetConfiguration
    $script:CurrentStage = 'AZ_TOKEN'
    Get-ValidatedToken
    $script:ApiRoot = $script:OrganizationUrl.TrimEnd('/') + '/api/data/v9.2/'
    if ($ReconcileOnly) {
        $script:CurrentStage = 'RECONCILE_WHOAMI'
        $who = Invoke-DataverseRequest -Method GET -Path 'WhoAmI'
        if ([string]$who.OrganizationId -ine $script:ExpectedOrganizationId -or
            [string]$who.UserId -ine $script:PacUserId) {
            throw 'PAC and Dataverse WhoAmI do not agree during read-only reconciliation.'
        }
        $script:CurrentStage = 'RECONCILE_SOLUTION_PUBLISHER'
        $publishers = @(Get-ODataRows -Path "publishers?`$select=publisherid,uniquename,customizationprefix&`$filter=uniquename eq '$($script:PublisherName)'")
        $solutions = @(Get-ODataRows -Path "solutions?`$select=solutionid,uniquename,ismanaged,_publisherid_value&`$filter=uniquename eq '$($script:SolutionName)'")
        if ($publishers.Count -ne 1 -or $solutions.Count -ne 1 -or
            $publishers[0].customizationprefix -cne $script:PublisherPrefix -or
            $solutions[0].uniquename -cne $script:SolutionName -or
            [bool]$solutions[0].ismanaged -or
            [string]$solutions[0]._publisherid_value -ine [string]$publishers[0].publisherid) {
            throw 'Exact Solution/Publisher could not be verified during read-only reconciliation.'
        }
        $script:Publisher = $publishers[0]
        $script:Solution = $solutions[0]
        $script:CurrentStage = 'RECONCILE_CANDIDATE_STATUS_CHOICE'
        $choiceState = Assert-ChoiceReadback
        $script:CurrentStage = 'RECONCILE_CANDIDATE_TABLE'
        $candidateMetadata = Get-OptionalMetadata -Path "EntityDefinitions(LogicalName='$($script:CandidateName)')?`$select=LogicalName,MetadataId,OwnershipType,PrimaryIdAttribute,PrimaryNameAttribute,IsAuditEnabled"
        $candidateState = if ($null -ne $candidateMetadata) {
            Assert-CandidateReadback -ChoiceState $choiceState
        } else { $null }
        $keys = @()
        $relationships = @()
        $componentMembership = @()
        $candidateRoot = @()
        $candidateRelationships = @()
        if ($null -ne $candidateMetadata) {
            $script:CurrentStage = 'RECONCILE_KEYS_AND_RELATIONSHIPS'
            $keys = @(Get-ODataRows -Path "EntityDefinitions(LogicalName='$($script:CandidateName)')/Keys")
            $relationships = @(Get-ODataRows -Path "EntityDefinitions(LogicalName='$($script:CandidateName)')/ManyToOneRelationships")
            $solutionFilter = [Uri]::EscapeDataString("_solutionid_value eq $($script:Solution.solutionid)")
            $solutionComponents = @(Get-ODataRows -Path "solutioncomponents?`$select=componenttype,objectid,rootcomponentbehavior&`$filter=$solutionFilter")
            $candidateRoot = @($solutionComponents | Where-Object {
                [string]$_.objectid -ieq [string]$candidateMetadata.MetadataId -and [int]$_.componenttype -eq 1
            })
            $expectedKeyNames = @('os_sr_cand_ak_corid', 'os_sr_cand_ak_cnum')
            $expectedRelationshipNames = @('os_sr_pos_cand', 'os_sr_csrc_cand', 'os_sr_ta_cand')
            $candidateRelationships = @($relationships | Where-Object {
                [string]$_.SchemaName -in $expectedRelationshipNames
            })
            foreach ($component in @($keys | Where-Object SchemaName -in $expectedKeyNames) + $candidateRelationships) {
                $matches = @($solutionComponents | Where-Object {
                    [string]$_.objectid -ieq [string]$component.MetadataId
                })
                $componentMembership += [ordered]@{
                    SchemaName = [string]$component.SchemaName
                    ComponentType = @($matches | ForEach-Object { [int]$_.componenttype })
                    MembershipCount = $matches.Count
                    Inclusion = if ($matches.Count -eq 1) {
                        'DIRECT'
                    } elseif ($candidateRoot.Count -eq 1 -and [int]$candidateRoot[0].rootcomponentbehavior -eq 0) {
                        'INCLUDED_BY_CANDIDATE_ROOT'
                    } else {
                        'NOT_VERIFIED'
                    }
                }
                $null = Assert-KeyAndRelationshipReadback -Candidate $candidateState
            }
        }
        $script:CurrentStage = 'RECONCILE_EXCLUDED_TABLES'
        $excludedPresent = @()
        foreach ($name in $script:ExcludedTables) {
            if ($null -ne (Get-OptionalMetadata -Path "EntityDefinitions(LogicalName='$name')?`$select=LogicalName")) {
                $excludedPresent += $name
            }
        }
        $script:CurrentStage = 'RECONCILE_ORGANIZATION_AUDIT'
        $organization = Invoke-DataverseRequest -Method GET -Path "organizations($script:ExpectedOrganizationId)?`$select=organizationid,isauditenabled,isuseraccessauditenabled"
        [ordered]@{
            Result = if ($null -eq $candidateMetadata) {
                'TABLE_WRITE_HTTP_204_BUT_TABLE_NOT_YET_VISIBLE'
            } elseif ($candidateRoot.Count -ne 1 -or [int]$candidateRoot[0].rootcomponentbehavior -ne 0 -or
                $keys.Count -ne 2 -or $candidateRelationships.Count -ne 3 -or
                @($componentMembership | Where-Object Inclusion -eq 'NOT_VERIFIED').Count -gt 0) {
                'CANDIDATE_SCHEMA_OR_SOLUTION_MEMBERSHIP_REVIEW_REQUIRED'
            } else {
                'CANDIDATE_TABLE_KEYS_LOOKUPS_AND_SOLUTION_MEMBERSHIP_RECONCILED'
            }
            CandidateStatusChoice = 'PRESENT_AND_RECONCILED'
            CandidateStatusOptions = @($choiceState.Options | ForEach-Object { [ordered]@{ Label = $_.Label; Value = $_.Value } })
            CandidateTable = if ($null -eq $candidateMetadata) { 'NOT_VISIBLE' } else { 'EXACT_SCHEMA_AND_AUDIT_RECONCILED' }
            CandidateKeyNames = @($keys | ForEach-Object SchemaName)
            CandidateKeyStates = @($keys | ForEach-Object { [string]$_.EntityKeyIndexStatus })
            CandidateRelationshipNames = @($candidateRelationships | ForEach-Object SchemaName)
            CandidateComponentMembership = $componentMembership
            ExcludedTablesPresent = $excludedPresent
            OrganizationAuditing = if ($organization.isauditenabled) { 'ENABLED' } else { 'DISABLED; NO CANDIDATE DATA MAY BE CREATED' }
            Requests = $script:RequestCounts
            Writes = $script:WriteStages.ToArray()
            BusinessDataWrites = 0
            PublicationWrites = 0
        } | ConvertTo-Json -Depth 30
        return
    }
    $script:CurrentStage = 'READ_ONLY_LIVE_PREFLIGHT'
    $liveState = Assert-LiveReadiness
    $script:PreflightComplete = $true
    if ($PreflightOnly) {
        [ordered]@{
            Result = 'READ_ONLY_PREFLIGHT_PASSED'
            Guards = $liveState
            Requests = $script:RequestCounts
            Writes = $script:WriteStages.ToArray()
        } | ConvertTo-Json -Depth 20
        return
    }
    if (-not $Apply) { throw 'A write requires -Apply; preflight-only cannot proceed to metadata creation.' }
    if (-not $ContinueAfterTable -or
        $liveState.CandidateStatusChoice -cne 'PRESENT_AND_RECONCILED' -or
        $liveState.CandidateTable -cne 'PRESENT_AND_RECONCILED') {
        throw 'Continuation requires the exact existing Candidate table and Choice to be reconciled.'
    }
    $choiceState = Assert-ChoiceReadback
    $script:CurrentStage = 'RECONCILE_EXISTING_CANDIDATE_TABLE'
    $statusValue = [int]($choiceState.Options | Where-Object Label -CEQ $script:StatusLabels[0]).Value
    $candidateState = Assert-CandidateReadback -ChoiceState $choiceState

    $script:CurrentStage = 'METADATA_PROPAGATION_AFTER_TABLE'
    Start-Sleep -Seconds 20
    $script:CurrentStage = 'CREATE_ALTERNATE_KEYS'
    $keyPayloads = @(
        [ordered]@{
            '@odata.type' = 'Microsoft.Dynamics.CRM.EntityKeyMetadata'
            SchemaName = 'os_sr_cand_ak_cnum'
            DisplayName = New-Label -Text 'Candidate Number Key'
            KeyAttributes = @('os_sr_cand_cnum')
        },
        [ordered]@{
            '@odata.type' = 'Microsoft.Dynamics.CRM.EntityKeyMetadata'
            SchemaName = 'os_sr_cand_ak_corid'
            DisplayName = New-Label -Text 'Candidate Creation Correlation Key'
            KeyAttributes = @('os_sr_cand_corid')
        }
    )
    foreach ($keyPayload in $keyPayloads) {
        $null = Invoke-DataverseRequest -Method POST -Path "EntityDefinitions(LogicalName='$($script:CandidateName)')/Keys" -Body $keyPayload -WithSolutionHeader
        Start-Sleep -Seconds 5
    }

    $script:CurrentStage = 'METADATA_PROPAGATION_AFTER_KEYS'
    Start-Sleep -Seconds 20
    $script:CurrentStage = 'CREATE_LOOKUP_RELATIONSHIPS'
    $references = @(
        @{ SchemaName = 'os_sr_pos_cand'; Parent = 'os_sr_pos'; Attribute = 'os_sr_cand_pos'; Label = 'Position' },
        @{ SchemaName = 'os_sr_csrc_cand'; Parent = 'os_sr_csrc'; Attribute = 'os_sr_cand_csrc'; Label = 'Candidate Source' },
        @{ SchemaName = 'os_sr_ta_cand'; Parent = 'os_sr_ta'; Attribute = 'os_sr_cand_ta'; Label = 'Assigned TA' }
    )
    foreach ($reference in $references) {
        $parent = Get-OptionalMetadata -Path "EntityDefinitions(LogicalName='$($reference.Parent)')?`$select=LogicalName,PrimaryIdAttribute"
        if ($null -eq $parent) { throw 'A Candidate lookup target disappeared after preflight; no further writes.' }
        $relationshipPayload = [ordered]@{
            '@odata.type' = 'Microsoft.Dynamics.CRM.OneToManyRelationshipMetadata'
            SchemaName = $reference.SchemaName
            ReferencedEntity = $reference.Parent
            ReferencingEntity = $script:CandidateName
            ReferencedAttribute = [string]$parent.PrimaryIdAttribute
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
                SchemaName = $reference.Attribute
                DisplayName = New-Label -Text $reference.Label
                RequiredLevel = New-RequiredLevel -Value None
            }
        }
        $null = Invoke-DataverseRequest -Method POST -Path 'RelationshipDefinitions' -Body $relationshipPayload -WithSolutionHeader
        Start-Sleep -Seconds 5
    }

    $script:CurrentStage = 'METADATA_PROPAGATION_AFTER_RELATIONSHIPS'
    Start-Sleep -Seconds 15
    $script:CurrentStage = 'FINAL_RECONCILIATION'
    $keys = Assert-KeyAndRelationshipReadback -Candidate $candidateState
    $org = Invoke-DataverseRequest -Method GET -Path "organizations($script:ExpectedOrganizationId)?`$select=organizationid,isauditenabled"
    $auditEnabled = [bool]$org.isauditenabled
    [ordered]@{
        Result = 'CANDIDATE_SCHEMA_CREATED_AND_RECONCILED'
        CandidateTable = $script:CandidateName
        CandidateStatusChoice = $script:ChoiceName
        AllocatedStatusOptions = @($choiceState.Options | ForEach-Object { [ordered]@{ Label = $_.Label; Value = $_.Value } })
        AutoNumberMaxLength = 100
        TableAuditMetadata = 'ENABLED'
        OrganizationAuditing = if ($auditEnabled) { 'ENABLED' } else { 'DISABLED; NO CANDIDATE DATA MAY BE CREATED' }
        KeyStates = @($keys | ForEach-Object { [ordered]@{ Name = $_.SchemaName; State = [string]$_.EntityKeyIndexStatus } })
        Relationships = @($references | ForEach-Object SchemaName)
        PayloadSha256 = [ordered]@{ CandidateStatusChoice = 'READ_ONLY_REUSED'; CandidateTable = 'READ_ONLY_REUSED' }
        Requests = $script:RequestCounts
        Writes = $script:WriteStages.ToArray()
        AuthorizationReferenceSupplied = -not [string]::IsNullOrWhiteSpace($AuthorizationReference)
        BusinessDataWrites = 0
        PublicationWrites = 0
        OtherTableWrites = 0
    } | ConvertTo-Json -Depth 40
}
catch {
    $failure = $_
    if ($script:RequestCounts.POST -gt 0) { $reconciliation = Reconcile-AfterFailure }
    [ordered]@{
        Result = if ($script:RequestCounts.POST -eq 0) { 'BLOCKED_BEFORE_WRITE' } else { 'STOPPED_AFTER_WRITE_REQUIRES_REVIEW' }
        Stage = $script:CurrentStage
        SafeBlockReason = $script:SafeBlockReason
        SolutionMembershipMatches = $script:LastSolutionMembershipCount
        CandidateAttributeSummary = $script:CandidateAttributeSummary
        LastWriteStage = $script:LastWriteStage
        LastWriteHttpStatus = $script:LastWriteHttpStatus
        SafeError = if ($script:RequestCounts.POST -eq 0) { 'Preflight or payload validation failed; no write was sent.' } else { 'A write failed or was not fully reconciled; no retries or further writes were attempted.' }
        Reconciliation = $reconciliation
        Requests = $script:RequestCounts
        Writes = $script:WriteStages.ToArray()
        BusinessDataWrites = 0
        PublicationWrites = 0
        OtherTableWrites = 0
    } | ConvertTo-Json -Depth 30
    throw 'Candidate-only provisioning stopped. Use the sanitized reconciliation result; do not retry automatically.'
}
finally {
    $script:AccessToken = $null
    [Environment]::SetEnvironmentVariable('BSO_RS_EXPECTED_USER_ID', $null, 'Process')
}
