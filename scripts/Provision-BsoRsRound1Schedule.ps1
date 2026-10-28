#requires -Version 7.4
[CmdletBinding()]
param(
    [ValidateSet('PlanOnly', 'PreflightOnly', 'Apply', 'ReconcileOnly')]
    [string]$Mode = 'PlanOnly',
    [string]$EnvironmentName,
    [string]$OrganizationUrl,
    [string]$ExpectedEnvironmentId,
    [string]$ExpectedOrganizationId,
    [string]$AuthorizationReference
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$script:Target = [ordered]@{
    EnvironmentName = 'VN LMV IT'
    OrganizationUrl = $null
    SolutionName = 'os_sr_bso_rs_support'
    PublisherName = 'os_bso_rs_support'
    PublisherPrefix = 'os'
}
$script:TableName = 'os_sr_intv'
$script:PrimaryName = 'os_sr_intv_ref'
$script:PrimaryNameFormat = 'INTV-{SEQNUM:8}'
$script:ExpectedAttributes = @(
    'os_sr_intv_ref',
    'os_sr_intv_rnd',
    'os_sr_intv_strt',
    'os_sr_intv_end',
    'os_sr_intv_nts',
    'os_sr_intv_res',
    'os_sr_intv_recat',
    'os_sr_intv_rnts',
    'os_sr_intv_cand',
    'os_sr_intv_ta',
    'os_sr_intv_loc'
)
$script:ResultAttributes = @(
    [ordered]@{
        LogicalName = 'os_sr_intv_res'
        Type = 'Picklist'
        DisplayName = 'Interview Result'
    }
    [ordered]@{
        LogicalName = 'os_sr_intv_recat'
        Type = 'DateTime'
        DisplayName = 'Result Recorded At'
    }
    [ordered]@{
        LogicalName = 'os_sr_intv_rnts'
        Type = 'Memo'
        DisplayName = 'Result Notes'
    }
)
$script:Relations = @(
    [ordered]@{
        SchemaName = 'os_sr_cand_intv'
        Parent = 'os_sr_cand'
        ParentId = 'os_sr_candid'
        Lookup = 'os_sr_intv_cand'
        Label = 'Candidate'
    }
    [ordered]@{
        SchemaName = 'os_sr_ta_intv'
        Parent = 'os_sr_ta'
        ParentId = 'os_sr_taid'
        Lookup = 'os_sr_intv_ta'
        Label = 'Interviewer / TA'
    }
    [ordered]@{
        SchemaName = 'os_sr_loc_intv'
        Parent = 'os_sr_loc'
        ParentId = 'os_sr_locid'
        Lookup = 'os_sr_intv_loc'
        Label = 'Location'
    }
)
$script:ApiRoot = $null
$script:AccessToken = $null
$script:PacUserId = $null
$script:Solution = $null
$script:WriteCount = 0
$script:SolutionComponentDispatches = 0
$script:CurrentStage = 'PARAMETERS'
$script:WrittenPaths = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$script:MaximumWrites = 7

function New-Label {
    param([Parameter(Mandatory)][string]$Text)
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
    param([ValidateSet('None', 'ApplicationRequired')][string]$Value = 'None')
    [ordered]@{
        Value = $Value
        CanBeChanged = $true
        ManagedPropertyLogicalName = 'canmodifyrequirementlevelsettings'
    }
}

function New-AuditSetting {
    [ordered]@{
        Value = $true
        CanBeChanged = $true
        ManagedPropertyLogicalName = 'canmodifyauditsettings'
    }
}

function New-StringAttribute {
    [ordered]@{
        '@odata.type' = 'Microsoft.Dynamics.CRM.StringAttributeMetadata'
        AttributeType = 'String'
        AttributeTypeName = [ordered]@{ Value = 'StringType' }
        SchemaName = $script:PrimaryName
        DisplayName = New-Label -Text 'Interview Reference'
        RequiredLevel = New-RequiredLevel -Value ApplicationRequired
        FormatName = [ordered]@{ Value = 'Text' }
        MaxLength = 100
        AutoNumberFormat = $script:PrimaryNameFormat
        IsPrimaryName = $true
        IsAuditEnabled = New-AuditSetting
    }
}

function New-DateTimeAttribute {
    param(
        [Parameter(Mandatory)][string]$SchemaName,
        [Parameter(Mandatory)][string]$DisplayName
    )
    [ordered]@{
        '@odata.type' = 'Microsoft.Dynamics.CRM.DateTimeAttributeMetadata'
        AttributeType = 'DateTime'
        AttributeTypeName = [ordered]@{ Value = 'DateTimeType' }
        SchemaName = $SchemaName
        DisplayName = New-Label -Text $DisplayName
        RequiredLevel = New-RequiredLevel -Value ApplicationRequired
        Format = 'DateAndTime'
        DateTimeBehavior = [ordered]@{ Value = 'UserLocal' }
        IsPrimaryName = $false
        IsAuditEnabled = New-AuditSetting
    }
}

function New-InterviewResultChoiceAttribute {
    $options = @('Pending', 'Pass', 'Fail') | ForEach-Object {
        [ordered]@{
            '@odata.type' = 'Microsoft.Dynamics.CRM.OptionMetadata'
            Value = $null
            Label = New-Label -Text $_
        }
    }
    [ordered]@{
        '@odata.type' = 'Microsoft.Dynamics.CRM.PicklistAttributeMetadata'
        AttributeType = 'Picklist'
        AttributeTypeName = [ordered]@{ Value = 'PicklistType' }
        SchemaName = 'os_sr_intv_res'
        DisplayName = New-Label -Text 'Interview Result'
        RequiredLevel = New-RequiredLevel
        IsPrimaryName = $false
        IsAuditEnabled = New-AuditSetting
        OptionSet = [ordered]@{
            '@odata.type' = 'Microsoft.Dynamics.CRM.OptionSetMetadata'
            IsGlobal = $false
            OptionSetType = 'Picklist'
            Options = $options
        }
    }
}

function New-ResultRecordedAtAttribute {
    [ordered]@{
        '@odata.type' = 'Microsoft.Dynamics.CRM.DateTimeAttributeMetadata'
        AttributeType = 'DateTime'
        AttributeTypeName = [ordered]@{ Value = 'DateTimeType' }
        SchemaName = 'os_sr_intv_recat'
        DisplayName = New-Label -Text 'Result Recorded At'
        RequiredLevel = New-RequiredLevel
        Format = 'DateAndTime'
        DateTimeBehavior = [ordered]@{ Value = 'UserLocal' }
        IsPrimaryName = $false
        IsAuditEnabled = New-AuditSetting
    }
}

function New-ResultNotesAttribute {
    [ordered]@{
        '@odata.type' = 'Microsoft.Dynamics.CRM.MemoAttributeMetadata'
        AttributeType = 'Memo'
        AttributeTypeName = [ordered]@{ Value = 'MemoType' }
        SchemaName = 'os_sr_intv_rnts'
        DisplayName = New-Label -Text 'Result Notes'
        RequiredLevel = New-RequiredLevel
        Format = 'Text'
        MaxLength = 1000
        IsPrimaryName = $false
        IsAuditEnabled = New-AuditSetting
    }
}

function New-TablePayload {
    $round = [ordered]@{
        '@odata.type' = 'Microsoft.Dynamics.CRM.PicklistAttributeMetadata'
        AttributeType = 'Picklist'
        AttributeTypeName = [ordered]@{ Value = 'PicklistType' }
        SchemaName = 'os_sr_intv_rnd'
        DisplayName = New-Label -Text 'Interview Round'
        RequiredLevel = New-RequiredLevel -Value ApplicationRequired
        IsPrimaryName = $false
        IsAuditEnabled = New-AuditSetting
        OptionSet = [ordered]@{
            '@odata.type' = 'Microsoft.Dynamics.CRM.OptionSetMetadata'
            IsGlobal = $false
            OptionSetType = 'Picklist'
            Options = @([ordered]@{
                '@odata.type' = 'Microsoft.Dynamics.CRM.OptionMetadata'
                Value = $null
                Label = New-Label -Text 'Round 1'
            })
        }
    }
    $notes = [ordered]@{
        '@odata.type' = 'Microsoft.Dynamics.CRM.MemoAttributeMetadata'
        AttributeType = 'Memo'
        AttributeTypeName = [ordered]@{ Value = 'MemoType' }
        SchemaName = 'os_sr_intv_nts'
        DisplayName = New-Label -Text 'Notes'
        RequiredLevel = New-RequiredLevel
        Format = 'Text'
        MaxLength = 1000
        IsPrimaryName = $false
        IsAuditEnabled = New-AuditSetting
    }
    [ordered]@{
        '@odata.type' = 'Microsoft.Dynamics.CRM.EntityMetadata'
        SchemaName = $script:TableName
        DisplayName = New-Label -Text 'Interview Schedule'
        DisplayCollectionName = New-Label -Text 'Interview Schedules'
        Description = New-Label -Text 'Round 1 DEV scheduling evidence for the BSO-RS Candidate workflow.'
        OwnershipType = 'UserOwned'
        IsActivity = $false
        HasActivities = $false
        HasNotes = $false
        IsAuditEnabled = New-AuditSetting
        Attributes = @(
            (New-StringAttribute)
            $round
            (New-DateTimeAttribute -SchemaName 'os_sr_intv_strt' -DisplayName 'Start Date/Time')
            (New-DateTimeAttribute -SchemaName 'os_sr_intv_end' -DisplayName 'End Date/Time')
            $notes
            (New-InterviewResultChoiceAttribute)
            (New-ResultRecordedAtAttribute)
            (New-ResultNotesAttribute)
        )
    }
}

function New-RelationshipPayload {
    param([Parameter(Mandatory)][object]$Relation)
    [ordered]@{
        '@odata.type' = 'Microsoft.Dynamics.CRM.OneToManyRelationshipMetadata'
        SchemaName = $Relation.SchemaName
        ReferencedEntity = $Relation.Parent
        ReferencedAttribute = $Relation.ParentId
        ReferencingEntity = $script:TableName
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
            SchemaName = $Relation.Lookup
            DisplayName = New-Label -Text $Relation.Label
            RequiredLevel = New-RequiredLevel -Value ApplicationRequired
            IsAuditEnabled = New-AuditSetting
            IsSecured = $false
        }
    }
}

function Get-Plan {
    [ordered]@{
        Table = $script:TableName
        DisplayName = 'Interview Schedule'
        Solution = $script:Target.SolutionName
        Ownership = 'UserOwned'
        TableAudit = $true
        PrimaryName = [ordered]@{
            LogicalName = $script:PrimaryName
            Type = 'AutoNumber String'
            Format = $script:PrimaryNameFormat
            ContainsPersonalData = $false
        }
        Fields = @(
            [ordered]@{ LogicalName = 'os_sr_intv_rnd'; Type = 'Local Choice'; Required = $true; Options = @('Round 1') }
            [ordered]@{ LogicalName = 'os_sr_intv_strt'; Type = 'DateTime UserLocal'; Required = $true }
            [ordered]@{ LogicalName = 'os_sr_intv_end'; Type = 'DateTime UserLocal'; Required = $true }
            [ordered]@{ LogicalName = 'os_sr_intv_nts'; Type = 'Memo'; Required = $false }
            [ordered]@{ LogicalName = 'os_sr_intv_res'; Type = 'Local Choice'; Required = $false; Options = @('Pending', 'Pass', 'Fail') }
            [ordered]@{ LogicalName = 'os_sr_intv_recat'; Type = 'DateTime UserLocal'; Required = $false }
            [ordered]@{ LogicalName = 'os_sr_intv_rnts'; Type = 'Memo'; Required = $false; MaxLength = 1000 }
        )
        Relationships = @($script:Relations | ForEach-Object {
            [ordered]@{
                SchemaName = $_.SchemaName
                Parent = $_.Parent
                Lookup = $_.Lookup
                Required = $true
                Delete = 'Restrict'
            }
        })
        Writes = 0
        SolutionComponentAdds = 0
    }
}

function Assert-TargetInput {
    try { $organizationUri = [Uri]$OrganizationUrl }
    catch { throw 'Organization URL is invalid; no connection was attempted.' }
    if ($null -eq $organizationUri -or
        $EnvironmentName -cne $script:Target.EnvironmentName -or
        $organizationUri.Scheme -cne 'https' -or
        $organizationUri.Host -notmatch '^org[0-9a-f]{6,}\.crm\d?\.dynamics\.com$' -or
        [string]::IsNullOrWhiteSpace($organizationUri.Authority) -or
        -not [string]::IsNullOrEmpty($organizationUri.UserInfo) -or
        $organizationUri.AbsolutePath -cne '/' -or
        -not [string]::IsNullOrEmpty($organizationUri.Query) -or
        -not [string]::IsNullOrEmpty($organizationUri.Fragment) -or
        [Guid]::Empty -eq [Guid]$ExpectedEnvironmentId -or
        [Guid]::Empty -eq [Guid]$ExpectedOrganizationId) {
        throw 'Environment or expected identity is invalid for the VN LMV IT DEV target.'
    }
    $script:Target.OrganizationUrl = $organizationUri.GetLeftPart([UriPartial]::Authority)
    if ($Mode -eq 'Apply' -and [string]::IsNullOrWhiteSpace($AuthorizationReference)) {
        throw 'Apply requires the explicit owner authorization reference.'
    }
}

function Initialize-Connection {
    $pacOutput = @(& pac env who 2>&1 | ForEach-Object { [string]$_ })
    if ($LASTEXITCODE -ne 0) { throw 'PAC identity check failed; no sign-in or environment switch was attempted.' }
    $pacText = $pacOutput -join "`n"
    $name = [regex]::Match($pacText, '(?m)^\s*Friendly Name:\s*(.+?)\s*$')
    $url = [regex]::Match($pacText, '(?m)^\s*Org URL:\s*(\S+)')
    $org = [regex]::Match($pacText, '(?m)^\s*Org ID:\s*([0-9a-fA-F-]{36})')
    $environment = [regex]::Match($pacText, '(?m)^\s*Environment ID:\s*([0-9a-fA-F-]{36})')
    $user = [regex]::Match($pacText, '(?m)^\s*User ID:\s*([0-9a-fA-F-]{36})')
    $email = [regex]::Match($pacText, '(?m)^\s*User Email:\s*(\S+)')
    if (-not ($name.Success -and $url.Success -and $org.Success -and $environment.Success -and $user.Success -and $email.Success) -or
        $name.Groups[1].Value -cne $script:Target.EnvironmentName -or
        $url.Groups[1].Value.TrimEnd('/') -cne $script:Target.OrganizationUrl -or
        $org.Groups[1].Value -ine $ExpectedOrganizationId -or
        $environment.Groups[1].Value -ine $ExpectedEnvironmentId) {
        throw 'PAC target does not match the explicitly bounded DEV environment.'
    }
    if (-not (Get-Module -ListAvailable -Name Az.Accounts)) { throw 'Existing Az.Accounts module is unavailable.' }
    Import-Module Az.Accounts -ErrorAction Stop
    $context = Get-AzContext -ErrorAction Stop
    if ($null -eq $context -or $context.Account.Type -ne 'User' -or
        $context.Account.Id -ine $email.Groups[1].Value) {
        throw 'Existing Az identity does not match PAC; no login or context switch was attempted.'
    }
    $tokenResult = Get-AzAccessToken -ResourceUrl $script:Target.OrganizationUrl -AsSecureString -ErrorAction Stop
    $secure = $tokenResult.Token
    if ($secure -isnot [Security.SecureString]) { throw 'Az.Accounts did not return a secure Dataverse token.' }
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
            $audience.Authority -ine ([Uri]$script:Target.OrganizationUrl).Authority -or
            'user_impersonation' -notin @(([string]$claims.scp) -split '\s+') -or
            $expires -le [DateTimeOffset]::UtcNow -or
            [math]::Abs(($expires - [DateTimeOffset]$tokenResult.ExpiresOn).TotalMinutes) -gt 2) {
            throw 'Dataverse credential target, tenant, delegated scope, or expiry validation failed.'
        }
        $script:AccessToken = $token
    }
    finally {
        $token = $null
        $tokenResult = $null
        $secure = $null
    }
    $script:PacUserId = $user.Groups[1].Value.ToLowerInvariant()
    $script:ApiRoot = $script:Target.OrganizationUrl.TrimEnd('/') + '/api/data/v9.2/'
    $whoAmI = Invoke-DataverseRequest -Method GET -Path 'WhoAmI'
    if ([string]$whoAmI.OrganizationId -ine $ExpectedOrganizationId -or
        [string]$whoAmI.UserId -ine $script:PacUserId) {
        throw 'PAC and Dataverse WhoAmI identities do not agree.'
    }
}

function Invoke-DataverseRequest {
    param(
        [Parameter(Mandatory)][ValidateSet('GET', 'POST', 'PUT')][string]$Method,
        [Parameter(Mandatory)][string]$Path,
        [object]$Body,
        [switch]$WithSolutionHeader
    )
    $uri = if ([Uri]::IsWellFormedUriString($Path, [UriKind]::Absolute)) { [Uri]$Path } else { [Uri]($script:ApiRoot + $Path) }
    if ($uri.Scheme -cne 'https' -or $uri.Authority -ine ([Uri]$script:Target.OrganizationUrl).Authority -or
        $uri.AbsolutePath -notmatch '^/api/data/v9\.2/' -or $uri.UserInfo -or $uri.Fragment) {
        throw 'Dataverse request target is outside the verified DEV organization API.'
    }
    $headers = @{
        Authorization = 'Bearer ' + $script:AccessToken
        Accept = 'application/json'
        'OData-MaxVersion' = '4.0'
        'OData-Version' = '4.0'
    }
    if ($WithSolutionHeader) { $headers['MSCRM.SolutionName'] = $script:Target.SolutionName }
    $arguments = @{
        Uri = $uri.AbsoluteUri
        Method = $Method
        Headers = $headers
        MaximumRetryCount = 0
        MaximumRedirection = 0
        TimeoutSec = 120
        SkipHttpErrorCheck = $true
        StatusCodeVariable = 'statusCode'
        ErrorAction = 'Stop'
    }
    if ($PSBoundParameters.ContainsKey('Body')) {
        $arguments.ContentType = 'application/json; charset=utf-8'
        $arguments.Body = ConvertTo-Json -InputObject $Body -Depth 80 -Compress
    }
    try { $response = Invoke-RestMethod @arguments }
    catch {
        if ($Method -in @('POST', 'PUT')) {
            throw "Metadata $Method outcome is uncertain at $script:CurrentStage; no retry was sent. Reconcile live metadata before any further Apply."
        }
        throw "Dataverse GET failed at $script:CurrentStage; no write was sent by this request."
    }
    if ([int]$statusCode -eq 404 -and $Method -eq 'GET') { return $null }
    if ([int]$statusCode -lt 200 -or [int]$statusCode -ge 300) {
        $code = ''
        $message = ''
        $errorBody = $response
        if ($response -is [string]) {
            try { $errorBody = $response | ConvertFrom-Json -ErrorAction Stop } catch { $errorBody = $null }
        }
        if ($null -ne $errorBody -and $errorBody.error) {
            $code = [string]$errorBody.error.code
            $message = [string]$errorBody.error.message
        }
        $message = $message -replace '(?i)https?://\S+', '[URL]'
        $message = $message -replace '(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b', '[EMAIL]'
        $message = $message -replace '\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b', '[ID]'
        $message = $message -replace '(?i)\bBearer\s+\S+', '******'
        if ($message.Length -gt 500) { $message = $message.Substring(0, 500) }
        $safeCode = if ($code -match '^(0x[0-9a-fA-F]{8}|[A-Za-z0-9_.-]{1,80})$') { $code } else { 'UNAVAILABLE' }
        if ($Method -in @('POST', 'PUT')) { throw "Metadata $Method at $script:CurrentStage returned HTTP $statusCode; Dataverse code $safeCode; $message. No retry was sent; reconcile before continuing." }
        throw "Dataverse GET returned HTTP $statusCode; response content suppressed."
    }
    $response
}

function Get-ODataRows {
    param([Parameter(Mandatory)][string]$Path)
    @((Invoke-DataverseRequest -Method GET -Path $Path).value)
}

function Get-TableMetadata {
    Invoke-DataverseRequest -Method GET -Path "EntityDefinitions(LogicalName='$script:TableName')?`$select=LogicalName,MetadataId,EntitySetName,PrimaryIdAttribute,PrimaryNameAttribute,OwnershipType,IsAuditEnabled"
}

function Assert-SolutionPublisher {
    $publishers = @(Get-ODataRows -Path "publishers?`$select=publisherid,uniquename,customizationprefix&`$filter=uniquename%20eq%20%27$($script:Target.PublisherName)%27")
    $solutions = @(Get-ODataRows -Path "solutions?`$select=solutionid,uniquename,ismanaged,_publisherid_value&`$filter=uniquename%20eq%20%27$($script:Target.SolutionName)%27")
    if ($publishers.Count -ne 1 -or $solutions.Count -ne 1 -or
        $publishers[0].customizationprefix -cne $script:Target.PublisherPrefix -or
        $solutions[0].uniquename -cne $script:Target.SolutionName -or
        [bool]$solutions[0].ismanaged -or
        [string]$solutions[0]._publisherid_value -ine [string]$publishers[0].publisherid) {
        throw 'Exact unmanaged solution and Publisher metadata did not reconcile.'
    }
    $script:Solution = $solutions[0]
    foreach ($relation in $script:Relations) {
        $parent = Invoke-DataverseRequest -Method GET -Path "EntityDefinitions(LogicalName='$($relation.Parent)')?`$select=LogicalName,PrimaryIdAttribute"
        if ($null -eq $parent -or $parent.LogicalName -cne $relation.Parent -or
            $parent.PrimaryIdAttribute -cne $relation.ParentId) {
            throw "Required lookup target $($relation.Parent) is absent or mismatched."
        }
    }
}

function Assert-WriteAllowlist {
    param(
        [Parameter(Mandatory)][ValidateSet('POST', 'PUT')][string]$Method,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][object]$Body
    )
    $writeIdentity = "$Path|$($Body.SchemaName)"
    if ($script:WriteCount -ge $script:MaximumWrites -or
        $script:WrittenPaths.Contains($writeIdentity)) {
        throw 'Fixed metadata write ceiling or duplicate-dispatch guard failed.'
    }
    $approved = $false
    if ($Method -ceq 'POST' -and $Path -ceq 'EntityDefinitions') {
        $approved = $Body.SchemaName -ceq $script:TableName -and
            $Body.OwnershipType -ceq 'UserOwned' -and
            $Body.IsAuditEnabled.Value -eq $true -and
            @($Body.Attributes).Count -eq 8
    }
    elseif ($Method -ceq 'POST' -and
        $Path -ceq "EntityDefinitions(LogicalName='$script:TableName')/Attributes") {
        $definition = @($script:ResultAttributes | Where-Object LogicalName -CEQ $Body.SchemaName)
        $typeMap = @{
            os_sr_intv_res = 'Microsoft.Dynamics.CRM.PicklistAttributeMetadata'
            os_sr_intv_recat = 'Microsoft.Dynamics.CRM.DateTimeAttributeMetadata'
            os_sr_intv_rnts = 'Microsoft.Dynamics.CRM.MemoAttributeMetadata'
        }
        $approved = $definition.Count -eq 1 -and
            $Body.DisplayName.LocalizedLabels[0].Label -ceq $definition[0].DisplayName -and
            [string]$Body['@odata.type'] -ceq $typeMap[[string]$Body.SchemaName] -and
            $Body.IsAuditEnabled.Value -eq $true
        if ($approved -and $Body.SchemaName -ceq 'os_sr_intv_res') {
            $labels = @($Body.OptionSet.Options | ForEach-Object { [string]$_.Label.LocalizedLabels[0].Label } | Sort-Object)
            $approved = $Body.OptionSet.IsGlobal -eq $false -and
                [string]$Body.RequiredLevel.Value -ceq 'None' -and
                ($labels -join '|') -ceq 'Fail|Pass|Pending'
        }
        elseif ($approved -and $Body.SchemaName -ceq 'os_sr_intv_recat') {
            $approved = [string]$Body.DateTimeBehavior.Value -ceq 'UserLocal' -and
                [string]$Body.Format -ceq 'DateAndTime' -and
                [string]$Body.RequiredLevel.Value -ceq 'None'
        }
        elseif ($approved -and $Body.SchemaName -ceq 'os_sr_intv_rnts') {
            $approved = [string]$Body.RequiredLevel.Value -ceq 'None' -and
                [int]$Body.MaxLength -eq 1000
        }
    }
    elseif ($Method -ceq 'POST' -and $Path -ceq 'RelationshipDefinitions') {
        $relation = @($script:Relations | Where-Object SchemaName -CEQ $Body.SchemaName)
        $approved = $relation.Count -eq 1 -and
            $Body.ReferencedEntity -ceq $relation[0].Parent -and
            $Body.ReferencedAttribute -ceq $relation[0].ParentId -and
            $Body.ReferencingEntity -ceq $script:TableName -and
            $Body.Lookup.SchemaName -ceq $relation[0].Lookup -and
            $Body.CascadeConfiguration.Delete -ceq 'Restrict'
    }
    elseif ($Method -ceq 'PUT' -and
        $Path -match "^EntityDefinitions\(LogicalName='os_sr_intv'\)/Attributes\([0-9a-fA-F-]{36}\)$") {
        $relation = @($script:Relations | Where-Object Lookup -CEQ $Body.SchemaName)
        $approved = $relation.Count -eq 1 -and
            [string]$Body.LogicalName -ceq $relation[0].Lookup -and
            [string]$Body['@odata.type'] -ceq 'Microsoft.Dynamics.CRM.LookupAttributeMetadata' -and
            $Body.IsAuditEnabled.Value -eq $true
    }
    if (-not $approved) { throw 'Metadata request is outside the fixed Phase 4C allowlist.' }
    $script:WriteCount++
    $null = $script:WrittenPaths.Add($writeIdentity)
}

function Send-MetadataWrite {
    param(
        [ValidateSet('POST', 'PUT')][string]$Method = 'POST',
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][object]$Body
    )
    Assert-WriteAllowlist -Method $Method -Path $Path -Body $Body
    Invoke-DataverseRequest -Method $Method -Path $Path -Body $Body -WithSolutionHeader | Out-Null
}

function Get-TableAttributes {
    Get-ODataRows -Path "EntityDefinitions(LogicalName='$script:TableName')/Attributes?`$select=MetadataId,LogicalName,SchemaName,AttributeType,RequiredLevel,IsAuditEnabled,IsValidForCreate"
}

function Get-RelationshipRows {
    Get-ODataRows -Path "EntityDefinitions(LogicalName='$script:TableName')/ManyToOneRelationships?`$select=MetadataId,SchemaName,ReferencedEntity,ReferencedAttribute,ReferencingEntity,ReferencingAttribute,ReferencingEntityNavigationPropertyName"
}

function Assert-BaseTable {
    param([Parameter(Mandatory)][object]$Metadata)
    if ($null -eq $Metadata -or $Metadata.LogicalName -cne $script:TableName -or
        $Metadata.OwnershipType -cne 'UserOwned' -or
        $Metadata.PrimaryNameAttribute -cne $script:PrimaryName -or
        $Metadata.IsAuditEnabled.Value -ne $true -or
        [string]::IsNullOrWhiteSpace([string]$Metadata.EntitySetName)) {
        throw 'Interview Schedule table identity, ownership, audit, or primary metadata mismatched.'
    }
    $generatedLookupNames = @($script:Relations | ForEach-Object { "$($_.Lookup)Name" })
    $attributes = @(Get-TableAttributes | Where-Object {
        [string]$_.SchemaName -like 'os_sr_intv_*' -and
        [string]$_.AttributeType -cne 'Virtual' -and
        [string]$_.SchemaName -notin $generatedLookupNames
    })
    $actualNames = @($attributes | ForEach-Object { [string]$_.SchemaName } | Sort-Object -Unique)
    $expectedBase = @(
        'os_sr_intv_ref', 'os_sr_intv_rnd', 'os_sr_intv_strt',
        'os_sr_intv_end', 'os_sr_intv_nts'
    )
    $baseActual = @($actualNames | Where-Object { $_ -notin @('os_sr_intv_cand', 'os_sr_intv_ta', 'os_sr_intv_loc') })
    $missingAttributes = @($expectedBase | Where-Object { $_ -notin $baseActual })
    $unexpectedAttributes = @($actualNames | Where-Object { $_ -notin $script:ExpectedAttributes })
    if ($missingAttributes.Count -gt 0 -or $unexpectedAttributes.Count -gt 0) {
        throw "Interview Schedule custom attributes mismatch; missing: $($missingAttributes -join ', '); unexpected: $($unexpectedAttributes -join ', ')."
    }
    $primaryRows = @(Get-ODataRows -Path "EntityDefinitions(LogicalName='$script:TableName')/Attributes/Microsoft.Dynamics.CRM.StringAttributeMetadata?`$select=LogicalName,MaxLength,AutoNumberFormat,IsPrimaryName,RequiredLevel,FormatName,IsAuditEnabled&`$filter=LogicalName%20eq%20%27$script:PrimaryName%27")
    if ($primaryRows.Count -ne 1 -or
        [int]$primaryRows[0].MaxLength -ne 100 -or
        [string]$primaryRows[0].AutoNumberFormat -cne $script:PrimaryNameFormat -or
        $primaryRows[0].IsPrimaryName -ne $true -or
        [string]$primaryRows[0].RequiredLevel.Value -cne 'ApplicationRequired' -or
        [string]$primaryRows[0].FormatName.Value -cne 'Text' -or
        $primaryRows[0].IsAuditEnabled.Value -ne $true) {
        throw 'Interview Schedule primary reference column failed readback.'
    }
    foreach ($name in @('os_sr_intv_strt', 'os_sr_intv_end')) {
        $dates = @(Get-ODataRows -Path "EntityDefinitions(LogicalName='$script:TableName')/Attributes/Microsoft.Dynamics.CRM.DateTimeAttributeMetadata?`$select=LogicalName,Format,DateTimeBehavior,RequiredLevel,IsAuditEnabled&`$filter=LogicalName%20eq%20%27$name%27")
        if ($dates.Count -ne 1 -or [string]$dates[0].Format -cne 'DateAndTime' -or
            [string]$dates[0].DateTimeBehavior.Value -cne 'UserLocal' -or
            [string]$dates[0].RequiredLevel.Value -cne 'ApplicationRequired' -or
            $dates[0].IsAuditEnabled.Value -ne $true) {
            throw "Interview Schedule Date/Time field $name failed readback."
        }
    }
    $notes = @(Get-ODataRows -Path "EntityDefinitions(LogicalName='$script:TableName')/Attributes/Microsoft.Dynamics.CRM.MemoAttributeMetadata?`$select=LogicalName,MaxLength,RequiredLevel,IsAuditEnabled&`$filter=LogicalName%20eq%20%27os_sr_intv_nts%27")
    if ($notes.Count -ne 1 -or [int]$notes[0].MaxLength -ne 1000 -or
        [string]$notes[0].RequiredLevel.Value -cne 'None' -or
        $notes[0].IsAuditEnabled.Value -ne $true) {
        throw 'Interview Schedule Notes field failed readback.'
    }
    $choiceRows = @(Get-ODataRows -Path "EntityDefinitions(LogicalName='$script:TableName')/Attributes/Microsoft.Dynamics.CRM.PicklistAttributeMetadata?`$select=LogicalName,RequiredLevel,IsAuditEnabled&`$filter=LogicalName%20eq%20%27os_sr_intv_rnd%27&`$expand=OptionSet")
    if ($choiceRows.Count -ne 1 -or $choiceRows[0].OptionSet.IsGlobal -ne $false -or
        [string]$choiceRows[0].OptionSet.OptionSetType -cne 'Picklist' -or
        @($choiceRows[0].OptionSet.Options).Count -ne 1 -or
        [string]$choiceRows[0].OptionSet.Options[0].Label.UserLocalizedLabel.Label -cne 'Round 1' -or
        [int]$choiceRows[0].OptionSet.Options[0].Value -le 0 -or
        [string]$choiceRows[0].RequiredLevel.Value -cne 'ApplicationRequired' -or
        $choiceRows[0].IsAuditEnabled.Value -ne $true) {
        throw 'Interview Schedule local Choice must contain only the reconciled Round 1 option.'
    }
    [pscustomobject]@{
        Metadata = $Metadata
        Attributes = $attributes
        Round1Value = [int]$choiceRows[0].OptionSet.Options[0].Value
    }
}

function Assert-InterviewResultAttributes {
    $choiceRows = @(Get-ODataRows -Path "EntityDefinitions(LogicalName='$script:TableName')/Attributes/Microsoft.Dynamics.CRM.PicklistAttributeMetadata?`$select=LogicalName,RequiredLevel,IsAuditEnabled&`$filter=LogicalName%20eq%20%27os_sr_intv_res%27&`$expand=OptionSet")
    $labels = @()
    $values = @()
    if ($choiceRows.Count -eq 1) {
        $labels = @($choiceRows[0].OptionSet.Options | ForEach-Object { [string]$_.Label.UserLocalizedLabel.Label } | Sort-Object)
        $values = @($choiceRows[0].OptionSet.Options | ForEach-Object { [int]$_.Value })
    }
    if ($choiceRows.Count -ne 1 -or $choiceRows[0].OptionSet.IsGlobal -ne $false -or
        [string]$choiceRows[0].OptionSet.OptionSetType -cne 'Picklist' -or
        ($labels -join '|') -cne 'Fail|Pass|Pending' -or
        $values.Count -ne 3 -or @($values | Where-Object { $_ -le 0 }).Count -gt 0 -or
        @($values | Select-Object -Unique).Count -ne 3 -or
        [string]$choiceRows[0].RequiredLevel.Value -cne 'None' -or
        $choiceRows[0].IsAuditEnabled.Value -ne $true) {
        throw 'Interview Result must be an optional audited local Choice with exactly Pending, Pass, and Fail.'
    }
    $dates = @(Get-ODataRows -Path "EntityDefinitions(LogicalName='$script:TableName')/Attributes/Microsoft.Dynamics.CRM.DateTimeAttributeMetadata?`$select=LogicalName,Format,DateTimeBehavior,RequiredLevel,IsAuditEnabled&`$filter=LogicalName%20eq%20%27os_sr_intv_recat%27")
    if ($dates.Count -ne 1 -or [string]$dates[0].Format -cne 'DateAndTime' -or
        [string]$dates[0].DateTimeBehavior.Value -cne 'UserLocal' -or
        [string]$dates[0].RequiredLevel.Value -cne 'None' -or
        $dates[0].IsAuditEnabled.Value -ne $true) {
        throw 'Result Recorded At must be optional, audited User Local Date/Time.'
    }
    $notes = @(Get-ODataRows -Path "EntityDefinitions(LogicalName='$script:TableName')/Attributes/Microsoft.Dynamics.CRM.MemoAttributeMetadata?`$select=LogicalName,MaxLength,RequiredLevel,IsAuditEnabled&`$filter=LogicalName%20eq%20%27os_sr_intv_rnts%27")
    if ($notes.Count -ne 1 -or [int]$notes[0].MaxLength -ne 1000 -or
        [string]$notes[0].RequiredLevel.Value -cne 'None' -or
        $notes[0].IsAuditEnabled.Value -ne $true) {
        throw 'Result Notes must be optional audited multiline text with max length 1000.'
    }
    [pscustomobject]@{
        ChoiceValues = [ordered]@{
            Pending = [int]($choiceRows[0].OptionSet.Options | Where-Object { $_.Label.UserLocalizedLabel.Label -ceq 'Pending' } | Select-Object -ExpandProperty Value -First 1)
            Pass = [int]($choiceRows[0].OptionSet.Options | Where-Object { $_.Label.UserLocalizedLabel.Label -ceq 'Pass' } | Select-Object -ExpandProperty Value -First 1)
            Fail = [int]($choiceRows[0].OptionSet.Options | Where-Object { $_.Label.UserLocalizedLabel.Label -ceq 'Fail' } | Select-Object -ExpandProperty Value -First 1)
        }
    }
}

function New-ResultAttributePayload {
    param([Parameter(Mandatory)][string]$LogicalName)
    switch ($LogicalName) {
        'os_sr_intv_res' { return (New-InterviewResultChoiceAttribute) }
        'os_sr_intv_recat' { return (New-ResultRecordedAtAttribute) }
        'os_sr_intv_rnts' { return (New-ResultNotesAttribute) }
        default { throw 'Interview Result field is outside the fixed provisioning allowlist.' }
    }
}

function Ensure-InterviewResultAttributes {
    $existing = @(Get-TableAttributes | Where-Object SchemaName -in @($script:ResultAttributes | ForEach-Object LogicalName))
    foreach ($attribute in $existing) {
        $definition = @($script:ResultAttributes | Where-Object LogicalName -CEQ $attribute.SchemaName)
        $expectedType = switch ($attribute.SchemaName) {
            'os_sr_intv_res' { 'Picklist' }
            'os_sr_intv_recat' { 'DateTime' }
            'os_sr_intv_rnts' { 'Memo' }
            default { 'INVALID' }
        }
        if ($definition.Count -ne 1 -or
            [string]$attribute.LogicalName -cne $attribute.SchemaName -or
            [string]$attribute.AttributeType -cne $expectedType) {
            throw "Existing Interview Result field $($attribute.SchemaName) has unexpected metadata; no changes were sent."
        }
    }
    foreach ($definition in $script:ResultAttributes) {
        $present = @($existing | Where-Object SchemaName -CEQ $definition.LogicalName)
        if ($present.Count -gt 1) { throw "Duplicate Interview Result field metadata detected: $($definition.LogicalName)." }
        if ($present.Count -eq 0) {
            $script:CurrentStage = "INTERVIEW_RESULT_ATTRIBUTE_POST_$($definition.LogicalName)"
            Send-MetadataWrite -Path "EntityDefinitions(LogicalName='$script:TableName')/Attributes" `
                -Body (New-ResultAttributePayload -LogicalName $definition.LogicalName)
            $readback = $null
            for ($poll = 0; $poll -lt 6; $poll++) {
                Start-Sleep -Seconds 5
                $readback = @(Get-TableAttributes | Where-Object SchemaName -CEQ $definition.LogicalName)
                if ($readback.Count -eq 1) { break }
                if ($readback.Count -gt 1) { throw "Duplicate Interview Result field metadata detected after write: $($definition.LogicalName)." }
            }
            if ($readback.Count -ne 1 -or
                [string]$readback[0].LogicalName -cne $definition.LogicalName -or
                [string]$readback[0].AttributeType -cne $definition.Type) {
                throw "Interview Result field $($definition.LogicalName) did not reconcile; do not retry before read-only reconciliation."
            }
        }
    }
    $null = Assert-InterviewResultAttributes
}

function Assert-Relationship {
    param([Parameter(Mandatory)][object]$Relation, [Parameter(Mandatory)][object[]]$Rows)
    $matches = @($Rows | Where-Object SchemaName -CEQ $Relation.SchemaName)
    if ($matches.Count -ne 1 -or
        [string]$matches[0].ReferencedEntity -cne $Relation.Parent -or
        [string]$matches[0].ReferencedAttribute -cne $Relation.ParentId -or
        [string]$matches[0].ReferencingEntity -cne $script:TableName -or
        [string]$matches[0].ReferencingAttribute -cne $Relation.Lookup -or
        [string]$matches[0].ReferencingEntityNavigationPropertyName -cne $Relation.Lookup) {
        throw "Interview Schedule relationship $($Relation.SchemaName) did not reconcile."
    }
    $attributes = @(Get-ODataRows -Path "EntityDefinitions(LogicalName='$script:TableName')/Attributes/Microsoft.Dynamics.CRM.LookupAttributeMetadata?`$select=LogicalName,RequiredLevel&`$filter=LogicalName%20eq%20%27$($Relation.Lookup)%27")
    $lookupLogicalName = if ($attributes.Count -eq 1) { [string]$attributes[0].LogicalName } else { 'MISSING_OR_DUPLICATE' }
    $lookupRequiredLevel = if ($attributes.Count -eq 1) { [string]$attributes[0].RequiredLevel.Value } else { 'UNAVAILABLE' }
    if ($attributes.Count -ne 1 -or
        $lookupLogicalName -cne $Relation.Lookup -or
        $lookupRequiredLevel -cne 'ApplicationRequired') {
        throw "Interview Schedule lookup $($Relation.Lookup) did not reconcile (logical name: $lookupLogicalName; required level: $lookupRequiredLevel)."
    }
}

function Ensure-LookupAudit {
    param([Parameter(Mandatory)][object]$Relation)
    $path = "EntityDefinitions(LogicalName='$script:TableName')/Attributes/Microsoft.Dynamics.CRM.LookupAttributeMetadata?`$filter=LogicalName%20eq%20%27$($Relation.Lookup)%27"
    $attributes = @(Get-ODataRows -Path $path)
    if ($attributes.Count -ne 1 -or [string]$attributes[0].LogicalName -cne $Relation.Lookup) {
        throw "Interview Schedule lookup $($Relation.Lookup) identity is not unique; audit update stopped."
    }
    if ($attributes[0].IsAuditEnabled.Value -eq $true) { return }
    if ($attributes[0].IsAuditEnabled.Value -ne $false -or
        [string]$attributes[0].RequiredLevel.Value -cne 'ApplicationRequired') {
        throw "Interview Schedule lookup $($Relation.Lookup) has unexpected metadata; audit update stopped."
    }
    $body = ConvertFrom-Json -AsHashtable -InputObject (ConvertTo-Json -InputObject $attributes[0] -Depth 80)
    foreach ($key in @($body.Keys | Where-Object { $_ -like '@odata.*' })) { $body.Remove($key) }
    $body['@odata.type'] = 'Microsoft.Dynamics.CRM.LookupAttributeMetadata'
    $body.IsAuditEnabled.Value = $true
    $script:CurrentStage = "LOOKUP_AUDIT_PUT_$($Relation.Lookup)"
    Send-MetadataWrite -Method PUT `
        -Path "EntityDefinitions(LogicalName='$script:TableName')/Attributes($($attributes[0].MetadataId))" `
        -Body $body
    for ($poll = 0; $poll -lt 6; $poll++) {
        Start-Sleep -Seconds 5
        $readback = @(Get-ODataRows -Path $path)
        if ($readback.Count -ne 1 -or [string]$readback[0].LogicalName -cne $Relation.Lookup) {
            throw "Interview Schedule lookup $($Relation.Lookup) identity changed during audit readback; stop without retry."
        }
        if ($readback[0].IsAuditEnabled.Value -eq $true) { return }
        if ($readback[0].IsAuditEnabled.Value -ne $false) {
            throw "Interview Schedule lookup $($Relation.Lookup) audit readback is ambiguous; stop without retry."
        }
    }
    throw "Interview Schedule lookup $($Relation.Lookup) audit update did not reconcile after read-only polling; no retry was sent."
}

function Assert-LookupAudit {
    param([Parameter(Mandatory)][object]$Relation)
    $path = "EntityDefinitions(LogicalName='$script:TableName')/Attributes/Microsoft.Dynamics.CRM.LookupAttributeMetadata?`$select=LogicalName,IsAuditEnabled&`$filter=LogicalName%20eq%20%27$($Relation.Lookup)%27"
    $attributes = @(Get-ODataRows -Path $path)
    if ($attributes.Count -ne 1 -or
        [string]$attributes[0].LogicalName -cne $Relation.Lookup -or
        $attributes[0].IsAuditEnabled.Value -ne $true) {
        throw "Interview Schedule lookup $($Relation.Lookup) audit state did not reconcile."
    }
}

function Assert-SolutionMembership {
    param([Parameter(Mandatory)][object]$Metadata)
    $filter = [Uri]::EscapeDataString("_solutionid_value eq $($script:Solution.solutionid)")
    $components = @(Get-ODataRows -Path "solutioncomponents?`$select=componenttype,objectid,rootcomponentbehavior&`$filter=$filter")
    $roots = @($components | Where-Object {
        [string]$_.objectid -ieq [string]$Metadata.MetadataId -and [int]$_.componenttype -eq 1
    })
    if ($roots.Count -ne 1 -or [int]$roots[0].rootcomponentbehavior -ne 0) {
        throw 'Interview Schedule table is not a root component including its subcomponents in the target solution.'
    }
}

function Ensure-SolutionMembership {
    param([Parameter(Mandatory)][object]$Metadata)
    $filter = [Uri]::EscapeDataString("_solutionid_value eq $($script:Solution.solutionid)")
    $components = @(Get-ODataRows -Path "solutioncomponents?`$select=componenttype,objectid,rootcomponentbehavior&`$filter=$filter")
    $roots = @($components | Where-Object {
        [string]$_.objectid -ieq [string]$Metadata.MetadataId -and [int]$_.componenttype -eq 1
    })
    if ($roots.Count -eq 1 -and [int]$roots[0].rootcomponentbehavior -eq 0) { return }
    if ($roots.Count -ne 0 -or $Mode -cne 'Apply' -or $script:SolutionComponentDispatches -ge 1) {
        throw 'Interview Schedule solution root is missing or mismatched; no automatic repair is allowed.'
    }
    $script:SolutionComponentDispatches++
    $output = @(& pac solution add-solution-component `
        --solutionUniqueName $script:Target.SolutionName `
        --component $script:TableName `
        --componentType 1 `
        --environment $script:Target.OrganizationUrl 2>&1 | ForEach-Object { [string]$_ })
    if ($LASTEXITCODE -ne 0 -or @($output | Where-Object { $_ -match '(?i)\b(error|failed)\b' }).Count -gt 0) {
        throw 'PAC solution component add did not report success; reconcile exact solution membership before any further attempt.'
    }
    $components = @(Get-ODataRows -Path "solutioncomponents?`$select=componenttype,objectid,rootcomponentbehavior&`$filter=$filter")
    $roots = @($components | Where-Object {
        [string]$_.objectid -ieq [string]$Metadata.MetadataId -and [int]$_.componenttype -eq 1
    })
    if ($roots.Count -ne 1 -or [int]$roots[0].rootcomponentbehavior -ne 0) {
        throw 'PAC add completed without the required solution root/subcomponent behavior; stop for reconciliation.'
    }
}

function Assert-CompleteSchema {
    $metadata = Get-TableMetadata
    $state = Assert-BaseTable -Metadata $metadata
    $resultState = Assert-InterviewResultAttributes
    $relationships = @(Get-RelationshipRows)
    foreach ($relation in $script:Relations) {
        Assert-Relationship -Relation $relation -Rows $relationships
        Assert-LookupAudit -Relation $relation
    }
    Assert-SolutionMembership -Metadata $metadata
    [ordered]@{
        Outcome = 'SCHEDULING_STORAGE_PROVISIONED'
        Environment = 'VN LMV IT (sanitized)'
        Solution = $script:Target.SolutionName
        Table = $script:TableName
        EntitySetName = [string]$metadata.EntitySetName
        PrimaryIdAttribute = [string]$metadata.PrimaryIdAttribute
        PrimaryNameAttribute = [string]$metadata.PrimaryNameAttribute
        Round1ChoiceValue = [int]$state.Round1Value
        InterviewResultChoiceValues = $resultState.ChoiceValues
        Fields = @($state.Attributes | ForEach-Object { [string]$_.LogicalName } | Sort-Object)
        Relationships = @($script:Relations | ForEach-Object { [string]$_.SchemaName })
        TableRootInSolution = $true
        RootIncludesSubcomponents = $true
        WriteDispatches = [int]$script:WriteCount
        SolutionComponentAdds = [int]$script:SolutionComponentDispatches
        Retries = 0
    }
}

if ($Mode -eq 'PlanOnly') {
    Get-Plan | ConvertTo-Json -Depth 10
    return
}

Assert-TargetInput
$script:CurrentStage = 'PAC_AND_TOKEN_IDENTITY'
Initialize-Connection
$script:CurrentStage = 'SOLUTION_PUBLISHER_AND_LOOKUP_TARGETS'
Assert-SolutionPublisher
$script:CurrentStage = 'TABLE_METADATA_READ'
$table = Get-TableMetadata

if ($Mode -eq 'PreflightOnly') {
    $outcome = if ($null -eq $table) { 'SCHEDULING_STORAGE_NOT_PROVISIONED' } else { 'TABLE_EXISTS_REQUIRES_RECONCILIATION' }
    [ordered]@{
        Outcome = $outcome
        Environment = 'VN LMV IT (sanitized)'
        Solution = $script:Target.SolutionName
        Table = $script:TableName
        TableExists = ($null -ne $table)
        Writes = 0
    } | ConvertTo-Json -Depth 8
    return
}

if ($Mode -eq 'ReconcileOnly') {
    Assert-CompleteSchema | ConvertTo-Json -Depth 10
    return
}

if ($null -eq $table) {
    $script:CurrentStage = 'ENTITY_DEFINITIONS_POST'
    Send-MetadataWrite -Path 'EntityDefinitions' -Body (New-TablePayload)
    Start-Sleep -Seconds 20
    $script:CurrentStage = 'ENTITY_DEFINITIONS_READBACK'
    $table = Get-TableMetadata
    if ($null -eq $table) { throw 'Interview Schedule creation was not confirmed by readback; do not retry before reconciliation.' }
}
$null = Assert-BaseTable -Metadata $table

$script:CurrentStage = 'INTERVIEW_RESULT_ATTRIBUTE_PROVISIONING'
Ensure-InterviewResultAttributes

$relationshipRows = @(Get-RelationshipRows)
foreach ($relation in $script:Relations) {
    $script:CurrentStage = "RELATIONSHIP_READ_$($relation.SchemaName)"
    $existing = @($relationshipRows | Where-Object SchemaName -CEQ $relation.SchemaName)
    if ($existing.Count -gt 1) { throw "Duplicate relationship metadata detected for $($relation.SchemaName)." }
    if ($existing.Count -eq 1) {
        Assert-Relationship -Relation $relation -Rows $relationshipRows
        Ensure-LookupAudit -Relation $relation
        Assert-LookupAudit -Relation $relation
        continue
    }
    $script:CurrentStage = "RELATIONSHIP_POST_$($relation.SchemaName)"
    Send-MetadataWrite -Path 'RelationshipDefinitions' -Body (New-RelationshipPayload -Relation $relation)
    Start-Sleep -Seconds 5
    $script:CurrentStage = "RELATIONSHIP_READBACK_$($relation.SchemaName)"
    $relationshipRows = @(Get-RelationshipRows)
    Assert-Relationship -Relation $relation -Rows $relationshipRows
    Ensure-LookupAudit -Relation $relation
    Assert-LookupAudit -Relation $relation
}

Ensure-SolutionMembership -Metadata (Get-TableMetadata)
Assert-CompleteSchema | ConvertTo-Json -Depth 10
