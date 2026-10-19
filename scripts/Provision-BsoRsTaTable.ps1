#requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$Apply,
    [switch]$PlanOnly,
    [string]$EnvironmentName = $env:BSO_RS_ENVIRONMENT_NAME,
    [string]$OrganizationUrl = $env:BSO_RS_ORG_URL,
    [string]$ExpectedEnvironmentId = $env:BSO_RS_EXPECTED_ENVIRONMENT_ID,
    [string]$ExpectedOrganizationId = $env:BSO_RS_EXPECTED_ORG_ID,
    [string]$ClientId = $env:BSO_RS_DATAVERSE_CLIENT_ID,
    [string]$MsalAssemblyPath = $env:BSO_RS_MSAL_ASSEMBLY,
    [string]$DisplayCollectionName
)

$ErrorActionPreference = 'Stop'
$script:AccessToken = $null
$script:ApiRoot = $null
$script:WritesStarted = $false
$script:MsalResolver = $null
$expectedCollectionName = 'TA Directories'
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
    [ordered]@{
        Value = 'ApplicationRequired'
        CanBeChanged = $true
        ManagedPropertyLogicalName = 'canmodifyrequirementlevelsettings'
    }
}

function New-SchemaPayloads {
    $primaryName = [ordered]@{
        '@odata.type' = 'Microsoft.Dynamics.CRM.StringAttributeMetadata'
        AttributeType = 'String'
        AttributeTypeName = [ordered]@{ Value = 'StringType' }
        SchemaName = 'os_sr_ta_nm'
        DisplayName = New-Label 'TA Name'
        RequiredLevel = New-RequiredLevel
        MaxLength = 200
        FormatName = [ordered]@{ Value = 'Text' }
        IsPrimaryName = $true
    }
    $table = [ordered]@{
        '@odata.type' = 'Microsoft.Dynamics.CRM.EntityMetadata'
        SchemaName = 'os_sr_ta'
        DisplayName = New-Label 'TA Directory'
        DisplayCollectionName = New-Label $DisplayCollectionName
        OwnershipType = 'OrganizationOwned'
        IsActivity = $false
        HasActivities = $false
        HasNotes = $false
        Attributes = @($primaryName)
    }
    $email = [ordered]@{
        '@odata.type' = 'Microsoft.Dynamics.CRM.StringAttributeMetadata'
        AttributeType = 'String'
        AttributeTypeName = [ordered]@{ Value = 'StringType' }
        SchemaName = 'os_sr_ta_eml'
        DisplayName = New-Label 'TA Email'
        RequiredLevel = New-RequiredLevel
        MaxLength = 254
        FormatName = [ordered]@{ Value = 'Email' }
    }
    [pscustomobject]@{ Table = $table; EmailColumn = $email }
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
    $message = [string]$Record.Exception.Message
    $message = $message -replace '(?i)Bearer\s+[^\s"'']+', 'Bearer [REDACTED]'
    $message = $message -replace '(?i)access[_ -]?token\s*[:=]\s*[^\s,;]+', 'access_token=[REDACTED]'
    $message = $message -replace '(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b', '[EMAIL REDACTED]'
    if ($message.Length -gt 1000) { $message = $message.Substring(0, 1000) }
    $message
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
    if (-not $name.Success -or -not $url.Success -or -not $orgId.Success -or -not $envId.Success) {
        throw 'Could not parse PAC identity response; stop without switching environments.'
    }
    if ($name.Groups[1].Value -cne 'VN LMV IT' -or
        $url.Groups[1].Value.TrimEnd('/') -cne $OrganizationUrl.TrimEnd('/') -or
        $orgId.Groups[1].Value -cne $ExpectedOrganizationId -or
        $envId.Groups[1].Value -cne $ExpectedEnvironmentId) {
        throw 'PAC active environment does not match the configured VN LMV IT target; stop without switching.'
    }
    $script:ApiRoot = $OrganizationUrl.TrimEnd('/') + '/api/data/v9.2/'
}

function Import-MsalAssembly {
    if ([string]::IsNullOrWhiteSpace($MsalAssemblyPath) -or
        -not (Test-Path -LiteralPath $MsalAssemblyPath -PathType Leaf)) {
        throw 'Set BSO_RS_MSAL_ASSEMBLY to an IT-approved Microsoft.Identity.Client.dll. No PAC token cache or browser session is used.'
    }
    $script:MsalDirectory = Split-Path -Parent $MsalAssemblyPath
    $script:MsalResolver = [System.ResolveEventHandler]{
        param($resolveSender, $resolveEventArgs)
        $fileName = (($resolveEventArgs.Name -split ',')[0]) + '.dll'
        $candidatePath = Join-Path $script:MsalDirectory $fileName
        if (Test-Path -LiteralPath $candidatePath -PathType Leaf) {
            return [System.Reflection.Assembly]::LoadFrom($candidatePath)
        }
        return $null
    }
    [AppDomain]::CurrentDomain.add_AssemblyResolve($script:MsalResolver)
    Add-Type -Path $MsalAssemblyPath
}

function Get-InteractiveAccessToken {
    if ([string]::IsNullOrWhiteSpace($ClientId)) {
        throw 'Set BSO_RS_DATAVERSE_CLIENT_ID to the IT-approved public-client app registration Client ID.'
    }
    Import-MsalAssembly
    $builder = [Microsoft.Identity.Client.PublicClientApplicationBuilder]::Create($ClientId)
    $builder = $builder.WithAuthority('https://login.microsoftonline.com/organizations')
    $builder = $builder.WithRedirectUri('http://localhost')
    $application = $builder.Build()
    $scope = $OrganizationUrl.TrimEnd('/') + '/user_impersonation'
    $request = $application.AcquireTokenInteractive([string[]]@($scope))
    $request = $request.WithPrompt([Microsoft.Identity.Client.Prompt]::SelectAccount)
    # MSAL's default cache is process-memory only here; the script configures no persistence.
    $result = $request.ExecuteAsync().GetAwaiter().GetResult()
    $script:AccessToken = $result.AccessToken
}

function Invoke-DataverseRequest {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('GET', 'POST')][string]$Method,
        [Parameter(Mandatory = $true)][string]$Path,
        [object]$Body,
        [switch]$WithSolutionHeader
    )
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
        $parsedRequestUri.AbsolutePath -notmatch '^/api/data/v9\.2/') {
        throw 'Dataverse request URL is outside the verified organization API origin.'
    }
    $request = @{
        Method = $Method
        Uri = $requestUri
        Headers = $headers
        TimeoutSec = 120
        ErrorAction = 'Stop'
    }
    if ($PSBoundParameters.ContainsKey('Body')) {
        $request.ContentType = 'application/json; charset=utf-8'
        $request.Body = ConvertTo-Json -InputObject $Body -Depth 40 -Compress
    }
    Invoke-RestMethod @request
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
    $path = "EntityDefinitions(LogicalName='os_sr_ta')?`$select=LogicalName,SchemaName,MetadataId,OwnershipType,PrimaryIdAttribute,PrimaryNameAttribute,DisplayName,DisplayCollectionName,IsAuditEnabled,IsDuplicateDetectionEnabled&`$expand=Attributes(`$select=LogicalName,SchemaName,MetadataId,DisplayName,AttributeType,AttributeTypeName,IsPrimaryName,RequiredLevel,MaxLength,FormatName,IsCustomAttribute,IsAuditEnabled)"
    Invoke-DataverseRequest -Method GET -Path $path
}

function Get-TableMetadataIfPresent {
    $filter = [Uri]::EscapeDataString("LogicalName eq 'os_sr_ta'")
    $tableMatches = Get-ODataList -Path "EntityDefinitions?`$select=LogicalName,MetadataId&`$filter=$filter"
    if ($tableMatches.Count -eq 0) { return $null }
    if ($tableMatches.Count -ne 1) { throw 'Multiple os_sr_ta table definitions found.' }
    Get-EntityMetadata
}

function Get-ProjectEntityNames {
    $path = "EntityDefinitions?`$select=LogicalName&`$filter=startswith(LogicalName,'os_sr_')"
    @(Get-ODataList -Path $path | ForEach-Object { $_.LogicalName })
}

function Get-SolutionMembership {
    param([string]$SolutionId, [string]$ObjectId, [int]$ComponentType)
    $filter = [Uri]::EscapeDataString("_solutionid_value eq $SolutionId and objectid eq $ObjectId and componenttype eq $ComponentType")
    @(Get-ODataList -Path "solutioncomponents?`$select=solutioncomponentid,componenttype,objectid,_solutionid_value&`$filter=$filter")
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
    if ($who.OrganizationId -ne $ExpectedOrganizationId) { throw 'WhoAmI organization mismatch; stop without writes.' }
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
    if ($projectTables.Count -gt 0) { throw ('Project table metadata already exists: ' + ($projectTables -join ', ') + '. Stop for reconciliation.') }
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
    }
}

function Assert-TableMetadata {
    param([Parameter(Mandatory = $true)][object]$Metadata)
    if ($Metadata.LogicalName -cne 'os_sr_ta' -or $Metadata.SchemaName -cne 'os_sr_ta' -or
        $Metadata.OwnershipType -cne 'OrganizationOwned' -or $Metadata.PrimaryNameAttribute -cne 'os_sr_ta_nm' -or
        $Metadata.PrimaryIdAttribute -cne 'os_sr_taid' -or
        $Metadata.DisplayName.UserLocalizedLabel.Label -cne 'TA Directory' -or
        $Metadata.DisplayCollectionName.UserLocalizedLabel.Label -cne $DisplayCollectionName) {
        throw 'Table schema, display labels, ownership, primary-name, or primary-GUID validation failed.'
    }
    $attrs = @($Metadata.Attributes)
    $primary = @($attrs | Where-Object { $_.LogicalName -ceq 'os_sr_ta_nm' })
    $email = @($attrs | Where-Object { $_.LogicalName -ceq 'os_sr_ta_eml' })
    if ($primary.Count -ne 1 -or $primary[0].DisplayName.UserLocalizedLabel.Label -cne 'TA Name' -or
        $primary[0].IsPrimaryName -ne $true -or $primary[0].AttributeType -cne 'String' -or
        $primary[0].FormatName.Value -cne 'Text' -or $primary[0].MaxLength -ne 200 -or
        $primary[0].RequiredLevel.Value -cne 'ApplicationRequired') { throw 'TA Name metadata mismatch.' }
    if ($email.Count -ne 1 -or $email[0].DisplayName.UserLocalizedLabel.Label -cne 'TA Email' -or
        $email[0].AttributeType -cne 'String' -or $email[0].FormatName.Value -cne 'Email' -or
        $email[0].MaxLength -ne 254 -or $email[0].RequiredLevel.Value -cne 'ApplicationRequired') { throw 'TA Email metadata mismatch.' }
    foreach ($sys in @('statecode','statuscode')) {
        if (@($attrs | Where-Object { $_.LogicalName -ceq $sys }).Count -ne 1) { throw "System field $sys missing." }
    }
    $custom = @($attrs | Where-Object { $_.IsCustomAttribute -eq $true } | ForEach-Object { $_.LogicalName })
    $expected = @('os_sr_taid','os_sr_ta_nm','os_sr_ta_eml')
    if (@($custom | Where-Object { $_ -notin $expected }).Count -gt 0 -or @($expected | Where-Object { $_ -notin $custom }).Count -gt 0) {
        throw 'Unexpected or missing custom column metadata.'
    }
    if ($Metadata.IsAuditEnabled.Value -ne $false -or $Metadata.IsDuplicateDetectionEnabled.Value -ne $false) {
        throw 'Audit or duplicate-detection option is enabled unexpectedly.'
    }
    if (@(Get-ODataList -Path "EntityDefinitions(LogicalName='os_sr_ta')/Keys?`$select=LogicalName,KeyAttributes").Count -ne 0) {
        throw 'Alternate key exists unexpectedly.'
    }
}

function Get-ReconciliationSummary {
    try {
        $table = Get-TableMetadataIfPresent
        if (-not $table) { return 'No os_sr_ta table metadata found by read-only reconciliation. Do not retry automatically.' }
        $emailFound = @($table.Attributes | Where-Object { $_.LogicalName -ceq 'os_sr_ta_eml' }).Count -eq 1
        return [ordered]@{
            TableFound = $true
            LogicalName = $table.LogicalName
            OwnershipType = $table.OwnershipType
            PrimaryName = $table.PrimaryNameAttribute
            PrimaryGuid = $table.PrimaryIdAttribute
            EmailColumnFound = $emailFound
            Recovery = 'Stop; do not retry, delete, rename, or recreate. Inspect metadata and obtain explicit recovery approval.'
        }
    }
    catch { return 'Read-only reconciliation failed; state is uncertain. Do not retry, delete, or recreate.' }
}

function Show-Plan {
    param([Parameter(Mandatory = $true)][object]$Payloads)
    $preview = [ordered]@{
        Mode = if ($PlanOnly) { 'PlanOnly; no authentication/network calls' } elseif ($Apply) { 'Apply requested; preflight and typed confirmation required' } else { 'DryRun; interactive auth and GET-only preflight' }
        Environment = if ($EnvironmentName) { $EnvironmentName } else { 'NOT SUPPLIED' }
        OrganizationUrl = if ($OrganizationUrl) { $OrganizationUrl.TrimEnd('/') } else { 'NOT SUPPLIED' }
        ExpectedEnvironmentId = if ($ExpectedEnvironmentId) { $ExpectedEnvironmentId } else { 'NOT SUPPLIED' }
        ExpectedOrganizationId = if ($ExpectedOrganizationId) { $ExpectedOrganizationId } else { 'NOT SUPPLIED' }
        SolutionUniqueName = 'os_sr_bso_rs_support'
        PublisherUniqueName = 'os_bso_rs_support'
        PublisherPrefix = 'os'
        TableSchemaName = $Payloads.Table.SchemaName
        OwnershipType = $Payloads.Table.OwnershipType
        TableDisplayName = 'TA Directory'
        DisplayCollectionName = $DisplayCollectionName
        DisplayCollectionNameStatus = if ($collectionNameWasExplicit) { 'Explicit input' } else { 'Derived proposal; explicitly approve before Apply' }
        PrimaryNameSchemaName = $Payloads.Table.Attributes[0].SchemaName
        PrimaryNameDataType = 'String/Text'
        PrimaryNameMaxLength = 200
        PrimaryNameRequiredLevel = 'ApplicationRequired'
        PrimaryGuidLogicalName = 'os_sr_taid (expected from platform)'
        AdditionalColumnSchemaName = $Payloads.EmailColumn.SchemaName
        AdditionalColumnFormatName = 'Email'
        AdditionalColumnMaxLength = 254
        AdditionalColumnRequiredLevel = 'ApplicationRequired'
        AlternateKeys = 'None'
        DuplicateDetection = 'None'
        AuditChanges = 'None; do not set audit properties and compare environment flags after Apply.'
        DataRowOperations = 'None; script contains no data-table requests.'
        ApiOperations = @(
            'GET WhoAmI, Organization, Publisher, Solution, EntityDefinitions, audit flags',
            'POST EntityDefinitions with MSCRM.SolutionUniqueName: table and primary name',
            'POST EntityDefinitions(...)/Attributes with MSCRM.SolutionUniqueName: TA Email',
            'POST PublishXml: publish only os_sr_ta metadata',
            'GET EntityDefinitions, Keys, solutioncomponents, Organization: independent read-back'
        )
        TablePayload = $Payloads.Table
        EmailColumnPayload = $Payloads.EmailColumn
    }
    Write-Output ($preview | ConvertTo-Json -Depth 40 -Compress)
}

try {
    if ($Apply -and $PlanOnly) { throw 'Use either -Apply or -PlanOnly, not both.' }
    if ($Apply -and -not $collectionNameWasExplicit) { throw 'Apply requires explicit -DisplayCollectionName because the schema does not specify a plural label.' }
    $payloads = New-SchemaPayloads
    Show-Plan -Payloads $payloads
    if ($PlanOnly) { return }

    $preflight = Get-Preflight
    if (-not $Apply) {
        Write-Result -Stage 'Preflight' -Status 'DryRunPassed' -Details ([ordered]@{
            OrganizationId = $preflight.OrganizationId
            PublisherUniqueName = 'os_bso_rs_support'
            PublisherPrefix = $preflight.PublisherPrefix
            SolutionUniqueName = $preflight.SolutionUniqueName
            TableAbsent = $true
            ProjectTablesAbsent = $true
            AuditStateUnchanged = $true
            WritesPerformed = 0
        })
        return
    }

    $confirmationPhrase = "CREATE os_sr_ta IN VN LMV IT WITH COLLECTION $DisplayCollectionName"
    $confirmation = Read-Host "Type '$confirmationPhrase' to authorize metadata writes"
    if ($confirmation -cne $confirmationPhrase) { throw 'Apply confirmation did not match; no writes performed.' }

    $script:WritesStarted = $true
    Invoke-DataverseRequest -Method POST -Path 'EntityDefinitions' -Body $payloads.Table -WithSolutionHeader | Out-Null
    $tableAfterCreate = Get-EntityMetadata
    if ($tableAfterCreate.OwnershipType -cne 'OrganizationOwned' -or $tableAfterCreate.PrimaryNameAttribute -cne 'os_sr_ta_nm' -or
        $tableAfterCreate.PrimaryIdAttribute -cne 'os_sr_taid') { throw 'Table metadata mismatch after create; stop without repair.' }

    $script:WritesStarted = $true
    Invoke-DataverseRequest -Method POST -Path "EntityDefinitions(LogicalName='os_sr_ta')/Attributes" -Body $payloads.EmailColumn -WithSolutionHeader | Out-Null
    $script:WritesStarted = $true
    Invoke-DataverseRequest -Method POST -Path 'PublishXml' -Body ([ordered]@{ ParameterXml = '<importexportxml><entities><entity>os_sr_ta</entity></entities></importexportxml>' }) | Out-Null

    $finalMetadata = Get-EntityMetadata
    Assert-TableMetadata -Metadata $finalMetadata
    $entityMembership = @(Get-SolutionMembership -SolutionId $preflight.SolutionId -ObjectId $finalMetadata.MetadataId -ComponentType 1)
    $emailMetadata = @($finalMetadata.Attributes | Where-Object { $_.LogicalName -ceq 'os_sr_ta_eml' })[0]
    $emailMembership = @(Get-SolutionMembership -SolutionId $preflight.SolutionId -ObjectId $emailMetadata.MetadataId -ComponentType 2)
    if ($entityMembership.Count -ne 1 -or $emailMembership.Count -ne 1) { throw 'Solution membership verification failed.' }
    $auditAfter = Get-AuditState
    if (($auditAfter | ConvertTo-Json -Compress) -cne ($preflight.Audit | ConvertTo-Json -Compress)) { throw 'Environment audit settings changed during execution.' }
    $projectTablesAfter = @(Get-ProjectEntityNames)
    if ($projectTablesAfter.Count -ne 1 -or $projectTablesAfter[0] -cne 'os_sr_ta') { throw 'Unexpected project table metadata exists.' }
    Write-Result -Stage 'Complete' -Status 'Verified' -Details ([ordered]@{
        TableLogicalName = $finalMetadata.LogicalName
        OwnershipType = $finalMetadata.OwnershipType
        PrimaryName = $finalMetadata.PrimaryNameAttribute
        PrimaryGuid = $finalMetadata.PrimaryIdAttribute
        CustomColumns = @('os_sr_ta_nm', 'os_sr_ta_eml')
        TableAndEmailSolutionMembershipVerified = $true
        AlternateKeys = 0
        ProjectTables = $projectTablesAfter
        DataRowsCreated = 0
        AuditSettingsUnchanged = $true
    })
}
catch {
    $reconciliation = if ($script:WritesStarted) { Get-ReconciliationSummary } else { 'No metadata write was started.' }
    Write-Result -Stage 'PreflightOrExecution' -Status 'Stopped' -Details ([ordered]@{
        Error = Get-SafeErrorMessage $_
        WritesMayHaveOccurred = $script:WritesStarted
        Reconciliation = $reconciliation
    })
    exit 1
}
finally {
    $script:AccessToken = $null
    if ($script:MsalResolver) { [AppDomain]::CurrentDomain.remove_AssemblyResolve($script:MsalResolver) }
}
