#requires -Version 7.4
[CmdletBinding()]
param(
    [switch]$PlanOnly,
    [switch]$DryRun,
    [switch]$Apply,
    [string]$Confirmation,
    [string]$AuthorizationReference,
    [string]$EnvironmentName = $env:BSO_RS_ENVIRONMENT_NAME,
    [string]$OrganizationUrl = $env:BSO_RS_ORG_URL,
    [string]$ExpectedEnvironmentId = $env:BSO_RS_EXPECTED_ENVIRONMENT_ID,
    [string]$ExpectedOrganizationId = $env:BSO_RS_EXPECTED_ORG_ID
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$script:Target = [ordered]@{
    EnvironmentName = 'VN LMV IT'
    AppName = 'BSO-RS-Support'
    AppUniqueName = 'srapp'
    AppModuleId = '3709bb7c-28cd-f111-a05c-70a8a581cbfa'
    AppModuleIdUnique = '81d8d848-2e00-470c-8899-2f55f560e018'
    SolutionUniqueName = 'os_sr_bso_rs_support'
    SolutionPublisherUniqueName = 'os_bso_rs_support'
    ReferenceTableNames = @('os_sr_ta', 'os_sr_pos', 'os_sr_csrc', 'os_sr_loc')
    NavigationAreaTitle = 'Settings'
    NavigationGroupTitle = 'Administration'
    NavigationSubareas = @(
        [pscustomobject]@{ LogicalName = 'os_sr_ta'; Title = 'TA Directory'; NodeId = 'subarea_9787e9c1' }
        [pscustomobject]@{ LogicalName = 'os_sr_pos'; Title = 'Positions'; NodeId = 'subarea_02d1f8a7' }
        [pscustomobject]@{ LogicalName = 'os_sr_csrc'; Title = 'Candidate Sources'; NodeId = 'subarea_03c7b614' }
        [pscustomobject]@{ LogicalName = 'os_sr_loc'; Title = 'Locations'; NodeId = 'subarea_04e9c321' }
    )
    TableLogicalName = 'os_sr_ta'
    TableMetadataId = 'f248212e-b5cb-f111-a05a-7c1e52376817'
    TableObjectTypeCode = 11005
    MainFormId = 'e076f089-e35b-46f3-b123-9cf0463759e5'
    ActiveViewId = '2cb98672-8176-4337-af5e-d6aabcac8f2d'
    SiteMapId = '6a02d640-2ccd-f111-a05a-000d3a64b349'
    SiteMapUniqueName = 'srapp'
    SiteMapNodeIds = @{
        Area = 'area_918af8a3'
        Group = 'group_8b0502d1'
        SubArea = 'subarea_9787e9c1'
    }
}
$script:ApiRoot = $null
$script:AccessToken = $null
$script:AccessTokenExpiresOn = [DateTimeOffset]::MinValue
$script:RequestCounts = @{ GET = 0; PATCH = 0; POST = 0 }
$script:WriteResults = [System.Collections.Generic.List[object]]::new()
$script:ResolvedReferenceComponents = @()
$script:MissingAppComponentPayloads = @()
$script:TokenUserId = $null
$script:WritesStarted = $false
$script:WritesAllowed = $false
$script:LastPath = $null
$script:LastHttpStatus = $null
$script:LastErrorCode = $null
$script:LastSafeError = $null
$script:LastStage = 'Startup'

if (($PlanOnly -and ($DryRun -or $Apply)) -or ($DryRun -and $Apply)) {
    throw 'Choose exactly one of PlanOnly, DryRun, or Apply.'
}
if (-not $PlanOnly -and -not $DryRun -and -not $Apply) { $PlanOnly = $true }

function Get-PropertyValue {
    param([object]$Object, [Parameter(Mandatory = $true)][string]$Name)
    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Collections.IDictionary] -and $Object.Contains($Name)) { return $Object[$Name] }
    $property = $Object.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $null
}

function Get-AppComponentPayloads {
    param([object]$Target = $script:Target)
    $referenceComponents = Get-PropertyValue -Object $Target -Name 'ReferenceComponents'
    if ($referenceComponents) {
        return @($referenceComponents | ForEach-Object { $_.Payload })
    }
    if ([object]::ReferenceEquals($Target, $script:Target) -and $script:ResolvedReferenceComponents.Count) {
        return @($script:ResolvedReferenceComponents | ForEach-Object { $_.Payloads })
    }
    @(
        [ordered]@{
            entityid = $Target.TableMetadataId
            '@odata.type' = 'Microsoft.Dynamics.CRM.entity'
        }
        [ordered]@{
            formid = $Target.MainFormId
            '@odata.type' = 'Microsoft.Dynamics.CRM.systemform'
        }
        [ordered]@{
            savedqueryid = $Target.ActiveViewId
            '@odata.type' = 'Microsoft.Dynamics.CRM.savedquery'
        }
    )
}

function Assert-ApplyAuthorization {
    param([string]$Phrase, [string]$Reference)
    if ($Phrase -cne 'APPLY PHASE 2D IN VN LMV IT' -or [string]::IsNullOrWhiteSpace($Reference)) {
        throw 'Apply requires the exact Phase 2D confirmation phrase and a recorded authorization reference; no request was sent.'
    }
}

function Assert-AppComponentsPayload {
    param(
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Body,
        [object]$Target = $script:Target
    )
    if ([string]$Body['AppId'] -cne $Target.AppModuleId -or @($Body.Keys).Count -ne 2 -or 'Components' -notin @($Body.Keys)) {
        throw 'AddAppComponents payload does not match the fixed AppId/Components contract.'
    }
    $expected = @(Get-AppComponentPayloads -Target $Target)
    if ([object]::ReferenceEquals($Target, $script:Target) -and $script:MissingAppComponentPayloads) {
        $expected = @($script:MissingAppComponentPayloads)
    }
    $actual = @($Body['Components'])
    if ($actual.Count -ne $expected.Count) { throw 'AddAppComponents component count differs from the approved plan.' }
    for ($index = 0; $index -lt $expected.Count; $index++) {
        $item = $actual[$index]
        $expectedItem = $expected[$index]
        $keys = @($item.Keys | ForEach-Object { [string]$_ })
        if ($keys.Count -ne 2 -or '@odata.type' -notin $keys) { throw 'AddAppComponents component contains an unexpected property.' }
        foreach ($key in $expectedItem.Keys) {
            if (-not $item.Contains($key) -or [string]$item[$key] -cne [string]$expectedItem[$key]) {
                throw 'AddAppComponents component identity/type differs from the approved plan.'
            }
        }
    }
}

function Get-AppCompositionPlan {
    $resolved = $script:ResolvedReferenceComponents.Count -gt 0
    $components = if ($resolved) {
        if ($script:MissingAppComponentPayloads.Count) { @($script:MissingAppComponentPayloads) } else { @(Get-AppComponentPayloads) }
    }
    else { @() }
    [ordered]@{
        Mode = if ($Apply) { 'Apply; explicit approval phrase required' } elseif ($DryRun) { 'DryRun; GET-only' } else { 'PlanOnly; no authentication or network' }
        Target = [ordered]@{
            EnvironmentName = $script:Target.EnvironmentName
            AppName = $script:Target.AppName
            AppUniqueName = $script:Target.AppUniqueName
            SolutionUniqueName = $script:Target.SolutionUniqueName
            ReferenceTables = @($script:Target.ReferenceTableNames)
        }
        ExistingSiteMapBinding = [ordered]@{
            ExportElement = 'AppModuleSiteMap'
            SiteMapUniqueName = $script:Target.SiteMapUniqueName
            AssociationEvidence = 'Target Solution export contains one AppModuleSiteMap entry with SiteMapUniqueName=srapp; live Site Map unique name is srapp.'
            StandardAppModuleComponentRowObserved = $false
            AddSiteMapComponent = $false
        }
        ProposedNavigation = [ordered]@{
            Area = $script:Target.NavigationAreaTitle
            Group = $script:Target.NavigationGroupTitle
            SubAreas = @($script:Target.NavigationSubareas | ForEach-Object {
                [ordered]@{ Title = $_.Title; EntityLogicalName = $_.LogicalName; NodeId = $_.NodeId }
            })
            PreserveExistingNodeIds = $true
        }
        AddAppComponentsPayload = [ordered]@{
            AppId = if ($resolved) { $script:Target.AppModuleId } else { '[resolved and guarded during live preflight]' }
            Components = $components
            ExactLiveIdsResolved = $resolved
        }
        OrderedWriteOperations = @(
            [ordered]@{
                Order = 1
                Method = 'PATCH'
                Target = "sitemaps($($script:Target.SiteMapId))"
                Field = 'sitemapxml'
                Purpose = 'Update existing Site Map; preserve ID and its existing AppModuleSiteMap unique-name binding.'
                MayPublish = $false
                SeparateApprovalRequired = $true
            }
            [ordered]@{
                Order = 2
                Method = 'POST'
                Target = 'AddAppComponents'
                ComponentTypes = @(1, 60, 26)
                Purpose = 'Add only the verified missing reference table, Main form, and public view components; omit Site Map because the export binding already exists.'
                MayPublish = $false
                SeparateApprovalRequired = $true
            }
        )
        MaximumWriteRequests = 2
        AutomaticRetries = 0
        AutomaticRollbackOrDelete = $false
        PublishXmlOrPublishAll = $false
        RoleAndAuditChanges = $false
        AppCreationRenameDelete = $false
        CustomPageCreation = $false
        ReferenceTables = @($script:Target.ReferenceTableNames)
        LiveComponentResolutionRequired = -not $resolved
    }
}

function Set-LocalizedSiteMapTitle {
    param(
        [Parameter(Mandatory = $true)][System.Xml.XmlElement]$Node,
        [Parameter(Mandatory = $true)][string]$Title
    )
    $titleNodes = @($Node.SelectNodes("./*[local-name()='Titles']/*[local-name()='Title'][@LCID='1033']"))
    if ($titleNodes.Count -ne 1) { throw 'Site Map must have exactly one existing LCID 1033 title per node.' }
    $titleNodes[0].SetAttribute('Title', $Title)
}

function New-ProposedSiteMapXml {
    param(
        [Parameter(Mandatory = $true)][string]$SiteMapXml,
        [hashtable]$ExpectedNodeIds = $script:Target.SiteMapNodeIds
    )
    if ([string]::IsNullOrWhiteSpace($SiteMapXml)) { throw 'Existing Site Map XML is empty.' }
    $settings = [System.Xml.XmlReaderSettings]::new()
    $settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver = $null
    $stringReader = [System.IO.StringReader]::new($SiteMapXml)
    $xmlReader = [System.Xml.XmlReader]::Create($stringReader, $settings)
    $document = [System.Xml.XmlDocument]::new()
    $document.PreserveWhitespace = $true
    $document.XmlResolver = $null
    try { $document.Load($xmlReader) }
    finally { $xmlReader.Dispose(); $stringReader.Dispose() }

    if ($document.DocumentElement.LocalName -cne 'SiteMap') { throw 'Unexpected Site Map XML root.' }
    $areas = @($document.DocumentElement.SelectNodes("./*[local-name()='Area']"))
    if ($areas.Count -ne 1 -or $areas[0].GetAttribute('Id') -cne $ExpectedNodeIds.Area) {
        throw 'Site Map Area structure/ID differs from the verified placeholder; stop without changing unrelated navigation.'
    }
    $groups = @($areas[0].SelectNodes("./*[local-name()='Group']"))
    if ($groups.Count -ne 1 -or $groups[0].GetAttribute('Id') -cne $ExpectedNodeIds.Group) {
        throw 'Site Map Group structure/ID differs from the verified placeholder; stop without changing unrelated navigation.'
    }
    $subAreas = @($groups[0].SelectNodes("./*[local-name()='SubArea']"))
    $expectedSubareas = @($script:Target.NavigationSubareas)
    if ($subAreas.Count -notin @(1, $expectedSubareas.Count) -or
        $subAreas[0].GetAttribute('Id') -cne $expectedSubareas[0].NodeId) {
        throw 'Site Map SubArea structure/ID differs from the approved baseline; stop without changing existing navigation.'
    }

    Set-LocalizedSiteMapTitle -Node $areas[0] -Title $script:Target.NavigationAreaTitle
    Set-LocalizedSiteMapTitle -Node $groups[0] -Title $script:Target.NavigationGroupTitle
    for ($index = 0; $index -lt $expectedSubareas.Count; $index++) {
        if ($index -ge $subAreas.Count) {
            $newSubarea = [System.Xml.XmlElement]$subAreas[0].CloneNode($true)
            $newSubarea.SetAttribute('Id', $expectedSubareas[$index].NodeId)
            $newSubarea.RemoveAttribute('Entity')
            $groups[0].AppendChild($newSubarea) | Out-Null
            $subAreas = @($subAreas) + @($newSubarea)
        }
        $subarea = $subAreas[$index]
        if ($subarea.GetAttribute('Id') -cne $expectedSubareas[$index].NodeId) {
            throw 'Site Map has a partial or unexpected approved SubArea sequence; stop without overwriting it.'
        }
        $entity = $subarea.GetAttributeNode('Entity')
        if ($entity -and $entity.Value -cne $expectedSubareas[$index].LogicalName) {
            throw 'Existing Site Map SubArea targets a different entity; stop without replacing it.'
        }
        $subarea.SetAttribute('Entity', $expectedSubareas[$index].LogicalName)
        Set-LocalizedSiteMapTitle -Node $subarea -Title $expectedSubareas[$index].Title
    }
    $document.OuterXml
}

function Get-PacIdentity {
    $output = @(& pac org who 2>&1 | ForEach-Object { [string]$_ })
    if ($LASTEXITCODE -ne 0) { throw 'pac org who failed; stop before Dataverse requests.' }
    $text = $output -join "`n"
    $friendlyName = [regex]::Match($text, '(?m)^\s*Friendly Name:\s*(.+?)\s*$')
    $url = [regex]::Match($text, '(?m)^\s*Org URL:\s*(\S+)')
    $orgId = [regex]::Match($text, '(?m)^\s*Org ID:\s*([0-9a-fA-F-]{36})')
    $environmentId = [regex]::Match($text, '(?m)^\s*Environment ID:\s*([0-9a-fA-F-]{36})')
    $userId = [regex]::Match($text, '(?m)^\s*User ID:\s*([0-9a-fA-F-]{36})')
    $userEmail = [regex]::Match($text, '(?m)^\s*User Email:\s*(\S+)')
    if (-not $friendlyName.Success -or -not $url.Success -or -not $orgId.Success -or -not $environmentId.Success -or -not $userId.Success -or -not $userEmail.Success) {
        throw 'Could not verify PAC target identity; stop without Dataverse requests.'
    }
    [pscustomobject]@{
        FriendlyName = $friendlyName.Groups[1].Value
        OrganizationUrl = $url.Groups[1].Value.TrimEnd('/')
        OrganizationId = $orgId.Groups[1].Value
        EnvironmentId = $environmentId.Groups[1].Value
        UserId = $userId.Groups[1].Value
        UserEmail = $userEmail.Groups[1].Value
    }
}

function Assert-TargetInputs {
    if ($EnvironmentName -cne $script:Target.EnvironmentName -or
        [string]::IsNullOrWhiteSpace($OrganizationUrl) -or
        [string]::IsNullOrWhiteSpace($ExpectedEnvironmentId) -or
        [string]::IsNullOrWhiteSpace($ExpectedOrganizationId)) {
        throw 'DryRun/Apply requires process-scoped target configuration matching VN LMV IT; no environment switch is attempted.'
    }
    $uri = [Uri]$OrganizationUrl
    if ($uri.Scheme -cne 'https' -or $uri.AbsolutePath -ne '/' -or $uri.Query -or $uri.Fragment) {
        throw 'Organization URL must be an HTTPS origin.'
    }
    $pac = Get-PacIdentity
    if ($pac.FriendlyName -cne $script:Target.EnvironmentName -or
        $pac.OrganizationUrl -cne $uri.AbsoluteUri.TrimEnd('/') -or
        $pac.EnvironmentId -cne $ExpectedEnvironmentId -or
        $pac.OrganizationId -cne $ExpectedOrganizationId) {
        throw 'PAC identity does not match configured VN LMV IT target; stop without switching environments.'
    }
    $expectedUserId = [Environment]::GetEnvironmentVariable('BSO_RS_EXPECTED_USER_ID', 'Process')
    $expectedUserGuid = [guid]::Empty
    if (-not [guid]::TryParse($expectedUserId, [ref]$expectedUserGuid) -or
        $expectedUserGuid.ToString() -ine $pac.UserId) {
        throw 'Process-scoped expected-user guard is missing or differs from PAC; stop without Dataverse requests.'
    }
    $script:ApiRoot = $uri.AbsoluteUri.TrimEnd('/') + '/api/data/v9.2/'
    $pac
}

function Get-ValidatedAccessToken {
    Import-Module Az.Accounts -ErrorAction Stop
    $context = Get-AzContext -ErrorAction Stop
    if ($null -eq $context -or $context.Account.Type -ne 'User' -or $context.Account.Id -ine $script:PacIdentity.UserEmail) {
        throw 'Existing Az user context does not match PAC identity; no sign-in or context switch attempted.'
    }
    $tokenResult = $null
    $secureToken = $null
    $tokenText = $null
    try {
        $tokenResult = Get-AzAccessToken -ResourceUrl $OrganizationUrl -AsSecureString -ErrorAction Stop
        $secureToken = $tokenResult.Token
        if ($secureToken -isnot [Security.SecureString]) { throw 'Secure Dataverse access token unavailable.' }
        $tokenText = ConvertFrom-SecureString -SecureString $secureToken -AsPlainText
        $parts = $tokenText.Split('.')
        if ($parts.Count -ne 3) { throw 'Dataverse token validation failed.' }
        $payload = $parts[1].Replace('-', '+').Replace('_', '/')
        switch ($payload.Length % 4) { 2 { $payload += '==' } 3 { $payload += '=' } }
        $claims = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload)) | ConvertFrom-Json
        $expires = [DateTimeOffset]::FromUnixTimeSeconds([long]$claims.exp)
        if ($claims.tid -cne $context.Tenant.Id -or
            ([Uri]$claims.aud).Authority -ine ([Uri]$OrganizationUrl).Authority -or
            'user_impersonation' -notin @(([string]$claims.scp -split '\s+')) -or
            $expires -le [DateTimeOffset]::UtcNow) {
            throw 'Dataverse token tenant, audience, scope, or expiry validation failed.'
        }
        $script:AccessTokenExpiresOn = $expires
        $tokenText
    }
    finally {
        $tokenResult = $null
        $secureToken = $null
        $tokenText = $null
        $parts = $null
        $payload = $null
        $claims = $null
    }
}

function Get-HttpStatusCode {
    param([System.Management.Automation.ErrorRecord]$ErrorRecord)
    try { return [int]$ErrorRecord.Exception.Response.StatusCode } catch { return $null }
}

function Ensure-DataverseAccessToken {
    $refreshBefore = [DateTimeOffset]::UtcNow.AddMinutes(5)
    if ([string]::IsNullOrWhiteSpace($script:AccessToken) -or $script:AccessTokenExpiresOn -le $refreshBefore) {
        $script:AccessToken = Get-ValidatedAccessToken
    }
    if ([string]::IsNullOrWhiteSpace($script:AccessToken) -or $script:AccessTokenExpiresOn -le [DateTimeOffset]::UtcNow) {
        throw 'A valid Dataverse token is unavailable; no request was sent.'
    }
}

function Get-DataverseMetadataDocument {
    Ensure-DataverseAccessToken
    $uri = [Uri]::new([Uri]$script:ApiRoot, '$metadata')
    if ($uri.Scheme -cne 'https' -or $uri.Authority -ine ([Uri]$OrganizationUrl).Authority) {
        throw 'Metadata request is outside the verified organization origin.'
    }
    $headers = @{
        Authorization = 'Bearer ' + $script:AccessToken
        Accept = 'application/xml'
        'OData-MaxVersion' = '4.0'
        'OData-Version' = '4.0'
    }
    $script:RequestCounts.GET++
    try {
        $response = Invoke-WebRequest -Method GET -Uri $uri.AbsoluteUri -Headers $headers -MaximumRedirection 0 -SkipHeaderValidation -TimeoutSec 90 -ErrorAction Stop
        [xml]$response.Content
    }
    catch {
        $status = Get-HttpStatusCode -ErrorRecord $_
        $script:LastHttpStatus = $status
        $script:LastPath = '$metadata'
        throw "Dataverse metadata GET failed (HTTP $status); raw response omitted."
    }
    finally { $headers = $null }
}

function Get-AppComponentsContract {
    param([Parameter(Mandatory = $true)][xml]$Metadata)
    $schema = $Metadata.SelectSingleNode("//*[local-name()='Schema' and @Namespace='Microsoft.Dynamics.CRM']")
    if (-not $schema) { throw 'Dataverse OData metadata lacks the Microsoft.Dynamics.CRM schema.' }
    $action = $schema.SelectSingleNode("./*[local-name()='Action' and @Name='AddAppComponents']")
    if (-not $action) { throw 'AddAppComponents is absent from live OData metadata.' }
    $appIdParameter = $action.SelectSingleNode("./*[local-name()='Parameter' and @Name='AppId']")
    $componentsParameter = $action.SelectSingleNode("./*[local-name()='Parameter' and @Name='Components']")
    if (-not $appIdParameter -or $appIdParameter.GetAttribute('Type') -cne 'Edm.Guid' -or
        -not $componentsParameter -or $componentsParameter.GetAttribute('Nullable') -cne 'false' -or
        $componentsParameter.GetAttribute('Type') -notmatch '^Collection\([^)]*crmbaseentity\)$') {
        throw 'AddAppComponents live parameter contract differs from the documented contract.'
    }
    $expected = @(
        [pscustomobject]@{ Name = 'entity'; Key = 'entityid' }
        [pscustomobject]@{ Name = 'sitemap'; Key = 'sitemapid' }
        [pscustomobject]@{ Name = 'systemform'; Key = 'formid' }
        [pscustomobject]@{ Name = 'savedquery'; Key = 'savedqueryid' }
    )
    $verified = foreach ($item in $expected) {
        $type = $schema.SelectSingleNode("./*[local-name()='EntityType' and @Name='$($item.Name)']")
        if (-not $type) { throw "Component entity type $($item.Name) is absent from live OData metadata." }
        $keys = @($type.SelectNodes("./*[local-name()='Key']/*[local-name()='PropertyRef']") | ForEach-Object { $_.GetAttribute('Name') })
        if ($item.Key -notin $keys) { throw "Component entity type $($item.Name) lacks expected key $($item.Key)." }
        [pscustomobject]@{ EntityType = "Microsoft.Dynamics.CRM.$($item.Name)"; PrimaryKey = $item.Key }
    }
    [pscustomobject]@{
        Action = 'Microsoft.Dynamics.CRM.AddAppComponents'
        AppIdType = $appIdParameter.GetAttribute('Type')
        ComponentsType = $componentsParameter.GetAttribute('Type')
        ComponentEntityTypes = $verified
    }
}

function Invoke-DataverseRequest {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('GET', 'PATCH', 'POST')][string]$Method,
        [Parameter(Mandatory = $true)][string]$Path,
        [object]$Body,
        [string]$ETag
    )
    if ($Method -ne 'GET' -and (-not $Apply -or -not $script:WritesAllowed)) {
        throw 'Write blocked; explicit Apply authorization gate is required.'
    }
    $uri = [Uri]::new([Uri]$script:ApiRoot, $Path)
    if ($uri.Scheme -cne 'https' -or $uri.Authority -ine ([Uri]$OrganizationUrl).Authority -or
        $uri.AbsolutePath -notmatch '^/api/data/v9\.2/' -or $uri.UserInfo -or $uri.Fragment) {
        throw 'Dataverse request path is outside the verified organization origin.'
    }
    $resource = [Uri]::UnescapeDataString($uri.AbsolutePath.Substring('/api/data/v9.2/'.Length))
    if ($Method -eq 'GET' -and $resource -notmatch '^(WhoAmI$|appmodules\(|appmodulecomponents$|sitemaps\(|sitemaps/Microsoft\.Dynamics\.CRM\.RetrieveUnpublishedMultiple\(|solutions$|publishers\(|solutioncomponents$|EntityDefinitions\(|systemforms(\(|$)|savedqueries(\(|$)|roles\(|RetrieveRequiredComponents\(|ValidateApp\()') {
        throw 'GET blocked: endpoint is outside the app and component metadata allowlist.'
    }
    if ($Method -eq 'PATCH' -and ($resource -cne "sitemaps($($script:Target.SiteMapId))" -or
        @($Body.Keys) -ne @('sitemapxml'))) {
        throw 'PATCH blocked: only the sitemapxml field on the existing target Site Map is allowed.'
    }
    if ($Method -eq 'POST' -and $resource -cne 'AddAppComponents') {
        throw 'POST blocked: only AddAppComponents is allowed; no create, publish, or role endpoint is allowed.'
    }
    if ($Method -eq 'POST') { Assert-AppComponentsPayload -Body $Body }
    Ensure-DataverseAccessToken
    $headers = @{
        Authorization = 'Bearer ' + $script:AccessToken
        Accept = 'application/json'
        'OData-MaxVersion' = '4.0'
        'OData-Version' = '4.0'
        'If-None-Match' = 'null'
    }
    if ($Method -eq 'PATCH') {
        if ([string]::IsNullOrWhiteSpace($ETag)) { throw 'PATCH requires the preflight ETag.' }
        $headers['If-Match'] = $ETag
    }
    $request = @{
        Method = $Method
        Uri = $uri.AbsoluteUri
        Headers = $headers
        MaximumRedirection = 0
        SkipHeaderValidation = $true
        SkipHttpErrorCheck = $true
        StatusCodeVariable = 'responseStatusCode'
        TimeoutSec = 90
        MaximumRetryCount = 0
        ErrorAction = 'Stop'
    }
    if ($null -ne $Body) {
        $request.ContentType = 'application/json; charset=utf-8'
        $request.Body = ConvertTo-Json -InputObject $Body -Depth 30 -Compress
    }
    $responseStatusCode = 0
    $script:LastHttpStatus = $null
    $script:LastErrorCode = $null
    $script:LastSafeError = $null
    $script:RequestCounts[$Method]++
    $script:LastPath = $resource
    if ($Method -ne 'GET') { $script:WritesStarted = $true }
    try {
        $response = Invoke-RestMethod @request
        $status = [int]$responseStatusCode
        $script:LastHttpStatus = if ($status -ge 100 -and $status -le 599) { $status } else { $null }
        if ($status -lt 200 -or $status -ge 300) {
            $errorObject = Get-PropertyValue -Object $response -Name 'error'
            $errorCode = [string](Get-PropertyValue -Object $errorObject -Name 'code')
            if ($errorCode -match '^0x[0-9a-fA-F]{8}$') { $script:LastErrorCode = $errorCode.ToLowerInvariant() }
            $script:LastSafeError = "Dataverse returned HTTP $status; response body omitted."
            throw 'Dataverse request returned a non-success status.'
        }
        if ($Method -ne 'GET') {
            $script:WriteResults.Add([pscustomobject]@{ Method = $Method; ApiPath = $resource; HttpStatus = $status })
        }
        return $response
    }
    catch {
        $status = Get-HttpStatusCode -ErrorRecord $_
        if ($status) { $script:LastHttpStatus = $status }
        if (-not $script:LastSafeError) { $script:LastSafeError = 'Dataverse request failed; response details omitted.' }
        if ($Method -ne 'GET') { $script:WritesStarted = $true }
        throw "Dataverse $Method failed at approved metadata path (HTTP $status); reconcile with GET before any retry. Raw response omitted."
    }
}

function New-CollectionPath {
    param([string]$EntitySet, [string]$Select, [string]$Filter)
    $path = $EntitySet + '?%24select=' + [Uri]::EscapeDataString($Select) + '&%24top=5000'
    if ($Filter) { $path += '&%24filter=' + [Uri]::EscapeDataString($Filter) }
    $path
}

function Get-ODataRows {
    param([Parameter(Mandatory = $true)][string]$Path)
    $rows = [System.Collections.Generic.List[object]]::new()
    $next = $Path
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    while ($next) {
        $response = Invoke-DataverseRequest -Method GET -Path $next
        foreach ($row in @((Get-PropertyValue -Object $response -Name 'value'))) { $rows.Add($row) }
        $nextProperty = $response.PSObject.Properties['@odata.nextLink']
        $next = if ($nextProperty) { [string]$nextProperty.Value } else { '' }
        if ($next -and -not $seen.Add($next)) { throw 'Repeated OData next link; stop inventory read.' }
    }
    $rows.ToArray()
}

function Get-UnpublishedSiteMap {
    $path = "sitemaps/Microsoft.Dynamics.CRM.RetrieveUnpublishedMultiple()?%24select=sitemapid,sitemapname,sitemapnameunique,componentstate,sitemapxml&%24filter=sitemapid%20eq%20$($script:Target.SiteMapId)"
    $rows = @(Get-ODataRows -Path $path)
    if ($rows.Count -gt 1) { throw 'Multiple unpublished target Site Map rows were returned.' }
    if ($rows.Count -eq 0) { return $null }
    $rows[0]
}

function Get-ExportGuidIds {
    param([xml]$Document, [string]$ParentName, [string]$IdName)
    $ids = [System.Collections.Generic.List[string]]::new()
    foreach ($node in $Document.SelectNodes("//*[local-name()='$ParentName']")) {
        $idNode = $node.SelectSingleNode(".//*[local-name()='$IdName']")
        if ($idNode) { $ids.Add(([string]$idNode.InnerText).Trim('{}').ToLowerInvariant()) }
    }
    $ids.ToArray()
}

function Get-SolutionExportSummary {
    $zipPath = Join-Path $env:TEMP ('bso-rs-2dp-'+[guid]::NewGuid().ToString('N')+'.zip')
    try {
        $script:LastStage = 'Run PAC Solution export'
        $pacOutput = @(& pac solution export --name $script:Target.SolutionUniqueName --environment $OrganizationUrl --path $zipPath --managed false 2>&1 | ForEach-Object { [string]$_ })
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $zipPath)) { throw 'Read-only Solution export failed; output details omitted.' }
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $script:LastStage = 'Open PAC Solution export archive'
        $archive = [IO.Compression.ZipFile]::OpenRead($zipPath)
        try {
            $entry = $archive.GetEntry('customizations.xml')
            if (-not $entry) { throw 'Solution export did not contain customizations.xml.' }
            $stream = $entry.Open()
            $reader = [IO.StreamReader]::new($stream)
            $script:LastStage = 'Parse PAC Solution customization XML'
            try { [xml]$document = $reader.ReadToEnd() }
            finally { $reader.Dispose(); $stream.Dispose() }
            $script:LastStage = 'Extract AppModuleSiteMaps and component IDs'
            $siteMapNames = [System.Collections.Generic.List[string]]::new()
            foreach ($entryNode in $document.SelectNodes("//*[local-name()='AppModuleSiteMaps']/*[local-name()='AppModuleSiteMap']")) {
                $nameNode = $entryNode.SelectSingleNode("./*[local-name()='SiteMapUniqueName']")
                if ($nameNode) { $siteMapNames.Add([string]$nameNode.InnerText) }
            }
            [pscustomobject]@{
                AppModuleSiteMapEntries = $siteMapNames.ToArray()
                TableIds = @(Get-ExportGuidIds -Document $document -ParentName 'Entity' -IdName 'MetadataId')
                MainFormIds = @(Get-ExportGuidIds -Document $document -ParentName 'systemform' -IdName 'formid')
                ActiveViewIds = @(Get-ExportGuidIds -Document $document -ParentName 'savedquery' -IdName 'savedqueryid')
            }
        }
        finally { $archive.Dispose() }
    }
    finally { if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force } }
}

function Get-ReferenceComponentInventory {
    $inventory = [System.Collections.Generic.List[object]]::new()
    foreach ($navigation in $script:Target.NavigationSubareas) {
        $logicalName = [string]$navigation.LogicalName
        $script:LastStage = "Resolve $logicalName table"
        $entity = Invoke-DataverseRequest -Method GET -Path "EntityDefinitions(LogicalName='$logicalName')?%24select=LogicalName,MetadataId,ObjectTypeCode,EntitySetName"
        $tableMetadataGuid = [guid]::Empty
        if ($entity.LogicalName -cne $logicalName -or -not [guid]::TryParse([string]$entity.MetadataId, [ref]$tableMetadataGuid)) {
            throw "Reference table $logicalName metadata identity is invalid."
        }

        $script:LastStage = "Resolve unique active default Main form for $logicalName"
        $forms = @(Get-ODataRows -Path (New-CollectionPath -EntitySet 'systemforms' -Select 'formid,name,objecttypecode,type,formactivationstate,componentstate,ismanaged,isdefault,publishedon' -Filter "objecttypecode eq '$logicalName' and type eq 2 and formactivationstate eq 1 and componentstate eq 0"))
        if ($forms.Count -eq 0) { throw "Reference table $logicalName has no active, published Main form." }
        if ($forms.Count -gt 1) {
            $defaultForms = @($forms | Where-Object { $_.isdefault -eq $true })
            if ($defaultForms.Count -ne 1) { throw "Reference table $logicalName has ambiguous active Main forms." }
            $forms = $defaultForms
        }
        if ([string]$forms[0].objecttypecode -cne $logicalName -or [int]$forms[0].type -ne 2 -or [int]$forms[0].formactivationstate -ne 1 -or [int]$forms[0].componentstate -ne 0) {
            throw "Reference table $logicalName resolved Main form has invalid identity or state."
        }
        $formGuid = [guid]::Empty
        if (-not [guid]::TryParse([string]$forms[0].formid, [ref]$formGuid)) { throw "Reference table $logicalName resolved Main form ID is invalid." }

        $script:LastStage = "Resolve unique public active default view for $logicalName"
        $views = @(Get-ODataRows -Path (New-CollectionPath -EntitySet 'savedqueries' -Select 'savedqueryid,name,returnedtypecode,querytype,isprivate,statecode,componentstate,ismanaged,isdefault' -Filter "returnedtypecode eq '$logicalName' and querytype eq 0 and isprivate eq false and statecode eq 0 and componentstate eq 0"))
        if ($views.Count -eq 0) { throw "Reference table $logicalName has no public, active view." }
        if ($views.Count -gt 1) {
            $defaultViews = @($views | Where-Object { $_.isdefault -eq $true })
            if ($defaultViews.Count -ne 1) { throw "Reference table $logicalName has ambiguous public, active views." }
            $views = $defaultViews
        }
        if ([string]$views[0].returnedtypecode -cne $logicalName -or [int]$views[0].querytype -ne 0 -or [bool]$views[0].isprivate -or [int]$views[0].statecode -ne 0 -or [int]$views[0].componentstate -ne 0) {
            throw "Reference table $logicalName resolved public view has invalid identity or state."
        }
        $viewGuid = [guid]::Empty
        if (-not [guid]::TryParse([string]$views[0].savedqueryid, [ref]$viewGuid)) { throw "Reference table $logicalName resolved public view ID is invalid." }

        $payloads = @(
            [ordered]@{ entityid = [string]$entity.MetadataId; '@odata.type' = 'Microsoft.Dynamics.CRM.entity' }
            [ordered]@{ formid = [string]$forms[0].formid; '@odata.type' = 'Microsoft.Dynamics.CRM.systemform' }
            [ordered]@{ savedqueryid = [string]$views[0].savedqueryid; '@odata.type' = 'Microsoft.Dynamics.CRM.savedquery' }
        )
        $inventory.Add([pscustomobject]@{
            LogicalName = $logicalName
            Title = [string]$navigation.Title
            TableMetadataId = [string]$entity.MetadataId
            ObjectTypeCode = $entity.ObjectTypeCode
            EntitySetName = $entity.EntitySetName
            MainForm = [pscustomobject]@{ Id = [string]$forms[0].formid; Name = [string]$forms[0].name; ObjectTypeCode = $forms[0].objecttypecode; IsDefault = [bool]$forms[0].isdefault; Type = $forms[0].type; ActivationState = $forms[0].formactivationstate; ComponentState = $forms[0].componentstate }
            ActiveView = [pscustomobject]@{ Id = [string]$views[0].savedqueryid; Name = [string]$views[0].name; ReturnedTypeCode = $views[0].returnedtypecode; IsDefault = [bool]$views[0].isdefault; QueryType = $views[0].querytype; IsPrivate = $views[0].isprivate; StateCode = $views[0].statecode; ComponentState = $views[0].componentstate }
            Payloads = $payloads
        })
    }
    $inventory.ToArray()
}

function Get-AppModuleRoleSnapshot {
    $dependencyPath = "RetrieveRequiredComponents(ObjectId=$($script:Target.AppModuleId),ComponentType=80)"
    $dependencies = Invoke-DataverseRequest -Method GET -Path $dependencyPath
    $required = @(Get-PropertyValue -Object $dependencies -Name 'value')
    $roleDependencies = @($required | Where-Object { [int]$_.requiredcomponenttype -eq 20 })
    $roles = [System.Collections.Generic.List[object]]::new()
    foreach ($dependency in $roleDependencies) {
        $roleId = ([string]$dependency.requiredcomponentobjectid).Trim('{}')
        $roleGuid = [guid]::Empty
        if (-not [guid]::TryParse($roleId, [ref]$roleGuid)) { throw 'AppModule role dependency has an invalid component ID.' }
        $role = Invoke-DataverseRequest -Method GET -Path "roles($($roleGuid.ToString()))?%24select=roleid,name,ismanaged"
        if (([string]$role.roleid).Trim('{}') -ine $roleGuid.ToString() -or [string]::IsNullOrWhiteSpace([string]$role.name)) {
            throw 'AppModule role dependency did not resolve to an exact role record.'
        }
        $roles.Add([pscustomobject]@{
            RoleId = $roleGuid.ToString().ToLowerInvariant()
            Name = [string]$role.name
            IsManaged = [bool]$role.ismanaged
        })
    }
    if ($roles.Count -ne $roleDependencies.Count -or
        @($roles | Select-Object -ExpandProperty RoleId -Unique).Count -ne $roles.Count) {
        throw 'AppModule role dependency inventory is ambiguous or duplicated.'
    }
    @($roles | Sort-Object RoleId)
}

function ConvertTo-SafeValidationIssueSummaries {
    param([object[]]$Issues)
    @($Issues | ForEach-Object {
        $message = [string](Get-PropertyValue -Object $_ -Name 'Message')
        $message = [regex]::Replace($message, '[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}', '[GUID]')
        $message = [regex]::Replace($message, 'https?://\S+', '[URL]')
        $message = [regex]::Replace($message, '[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}', '[EMAIL]', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        [pscustomobject]@{
            ErrorType = [string](Get-PropertyValue -Object $_ -Name 'ErrorType')
            Message = $message
            ErrorCode = [string](Get-PropertyValue -Object $_ -Name 'CRMErrorCode')
        }
    })
}

function Assert-AppValidationAllowsApply {
    param([Parameter(Mandatory = $true)][object]$AppValidation)
    if (@($AppValidation.Issues | Where-Object { $_.ErrorType -ceq 'Error' }).Count -gt 0) {
        throw 'ValidateApp reported an existing blocking error outside the approved component plan; stop before writes.'
    }
}

function Get-TargetSnapshot {
    $script:LastStage = 'Verify PAC target'
    $script:PacIdentity = Assert-TargetInputs
    $script:AccessToken = Get-ValidatedAccessToken
    $script:LastStage = 'Verify Dataverse organization'
    $who = Invoke-DataverseRequest -Method GET -Path 'WhoAmI'
    if ([string]$who.OrganizationId -cne $ExpectedOrganizationId -or
        [string]$who.UserId -ine $script:PacIdentity.UserId -or
        [string]$who.UserId -ine [string]([Environment]::GetEnvironmentVariable('BSO_RS_EXPECTED_USER_ID', 'Process'))) {
        throw 'Dataverse WhoAmI identity does not match PAC and the process-scoped expected-user guard.'
    }

    $script:LastStage = 'Verify project Solution and Publisher'
    $solutionRows = @(Get-ODataRows -Path (New-CollectionPath -EntitySet 'solutions' -Select 'solutionid,uniquename,friendlyname,ismanaged,_publisherid_value' -Filter "uniquename eq '$($script:Target.SolutionUniqueName)'"))
    if ($solutionRows.Count -ne 1) { throw 'Target Solution is missing or not unique.' }
    $solution = $solutionRows[0]
    $solutionPublisher = Invoke-DataverseRequest -Method GET -Path "publishers($($solution._publisherid_value))?%24select=publisherid,uniquename,customizationprefix"
    if ([bool]$solution.ismanaged -or $solutionPublisher.uniquename -cne 'os_bso_rs_support' -or $solutionPublisher.customizationprefix -cne 'os') { throw 'Target Solution must be unmanaged and linked to the approved project Publisher.' }

    $script:LastStage = 'Read unpublished AppModule'
    $app = Invoke-DataverseRequest -Method GET -Path "appmodules($($script:Target.AppModuleId))/Microsoft.Dynamics.CRM.RetrieveUnpublished()?%24select=appmoduleid,appmoduleidunique,name,uniquename,componentstate,statecode,statuscode,solutionid,publishedon,_publisherid_value"
    if ($app.appmoduleid -cne $script:Target.AppModuleId -or $app.uniquename -cne $script:Target.AppUniqueName -or $app.name -cne $script:Target.AppName) { throw 'Adopted AppModule identity mismatch.' }
    if ([int]$app.statecode -ne 0 -or [int]$app.componentstate -ne 1) { throw 'AppModule is not Active and Unpublished; stop.' }

    $script:LastStage = 'Read existing Site Map'
    $siteMap = Invoke-DataverseRequest -Method GET -Path "sitemaps($($script:Target.SiteMapId))?%24select=sitemapid,sitemapname,sitemapnameunique,isappaware,componentstate,ismanaged,sitemapxml"
    if ($siteMap.sitemapid -cne $script:Target.SiteMapId -or $siteMap.sitemapnameunique -cne $script:Target.SiteMapUniqueName -or -not $siteMap.isappaware) { throw 'Target Site Map identity mismatch.' }

    $script:LastStage = 'Resolve all approved reference-table components'
    $referenceComponents = @(Get-ReferenceComponentInventory)
    $script:ResolvedReferenceComponents = $referenceComponents

    $script:LastStage = 'Read Solution component membership'
    $solutionComponents = @(Get-ODataRows -Path (New-CollectionPath -EntitySet 'solutioncomponents' -Select 'solutioncomponentid,componenttype,objectid,rootsolutioncomponentid,rootcomponentbehavior,ismetadata,_solutionid_value' -Filter "_solutionid_value eq $($solution.solutionid)"))
    $appRoot = @($solutionComponents | Where-Object { [int]$_.componenttype -eq 80 -and $_.objectid -ceq $script:Target.AppModuleId })
    $siteMapRoot = @($solutionComponents | Where-Object { [int]$_.componenttype -eq 62 -and $_.objectid -ceq $script:Target.SiteMapId })
    if ($appRoot.Count -ne 1 -or $siteMapRoot.Count -ne 1) { throw 'App or Site Map Solution root membership mismatch.' }
    foreach ($reference in $referenceComponents) {
        $entityRoot = @($solutionComponents | Where-Object { [int]$_.componenttype -eq 1 -and ([string]$_.objectid).Trim('{}') -ieq $reference.TableMetadataId })
        if ($entityRoot.Count -ne 1) { throw "Reference table $($reference.LogicalName) lacks exact project Solution root membership." }
    }

    $script:LastStage = 'Read AppModule components'
    $components = @(Get-ODataRows -Path (New-CollectionPath -EntitySet 'appmodulecomponents' -Select 'appmodulecomponentid,_appmoduleidunique_value,componenttype,objectid,isdefault,ismetadata,rootappmodulecomponentid,rootcomponentbehavior' -Filter "_appmoduleidunique_value eq $($script:Target.AppModuleIdUnique)"))
    $roleSnapshot = @(Get-AppModuleRoleSnapshot)
    $script:LastStage = 'Inspect unpublished Site Map layer'
    $siteMapDraft = Get-UnpublishedSiteMap
    $sourceXml = if ($siteMapDraft -and $siteMapDraft.sitemapxml) { [string]$siteMapDraft.sitemapxml } else { [string]$siteMap.sitemapxml }
    $proposedXml = New-ProposedSiteMapXml -SiteMapXml $sourceXml
    $script:LastStage = 'Validate AddAppComponents OData contract'
    $componentContract = Get-AppComponentsContract -Metadata (Get-DataverseMetadataDocument)
    $script:LastStage = 'Export and verify Solution associations'
    $export = Get-SolutionExportSummary
    $script:LastStage = 'Verify exported Site Map binding'
    if (@($export.AppModuleSiteMapEntries | Where-Object { $_ -ceq $script:Target.SiteMapUniqueName }).Count -ne 1) { throw 'Target Solution export lacks the unique-name AppModuleSiteMap binding.' }
    $script:LastStage = 'Verify all reference components in Solution export'
    foreach ($reference in $referenceComponents) {
        if ($reference.MainForm.Id.Trim('{}').ToLowerInvariant() -notin $export.MainFormIds -or
            $reference.ActiveView.Id.Trim('{}').ToLowerInvariant() -notin $export.ActiveViewIds) {
            throw "Solution export does not contain the exact table, Main form, and public view for $($reference.LogicalName)."
        }
    }
    $script:LastStage = 'Read current app dependency validation'
    $validation = Invoke-DataverseRequest -Method GET -Path "ValidateApp(AppModuleId=$($script:Target.AppModuleId))"
    $validationResponse = Get-PropertyValue -Object $validation -Name 'AppValidationResponse'
    $validationIssues = @(Get-PropertyValue -Object $validationResponse -Name 'ValidationIssueList')
    $validationIssueSummaries = @(ConvertTo-SafeValidationIssueSummaries -Issues $validationIssues)
    [pscustomobject]@{
        AppModule = [pscustomobject]@{
            Id = $app.appmoduleid
            IdUnique = $app.appmoduleidunique
            Name = $app.name
            UniqueName = $app.uniquename
            StateCode = $app.statecode
            StatusCode = $app.statuscode
            ComponentState = $app.componentstate
            PublicationState = if ([int]$app.componentstate -eq 1) { 'UNPUBLISHED_DRAFT' } else { 'PUBLISHED' }
            PublishedOn = Get-PropertyValue -Object $app -Name 'publishedon'
            PublisherLookupStatus = if ($app.PSObject.Properties['_publisherid_value']) { 'Returned; verify separately' } else { 'UNKNOWN' }
        }
        IdentityChecks = [pscustomobject]@{
            PacIdentityAvailable = $true
            AzIdentityAvailable = $true
            DataverseIdentityAvailable = $true
            PacAzWhoAmIMatch = $true
            ExpectedUserConfigured = $true
            ExpectedUserMatch = $true
        }
        AppModulePublisher = if ($app.PSObject.Properties['_publisherid_value']) { 'returned' } else { 'UNKNOWN' }
        Solution = [pscustomobject]@{ UniqueName = $solution.uniquename; FriendlyName = $solution.friendlyname; IsManaged = $solution.ismanaged }
        SolutionPublisher = [pscustomobject]@{ UniqueName = $solutionPublisher.uniquename; CustomizationPrefix = $solutionPublisher.customizationprefix }
        SiteMap = [pscustomobject]@{
            Id = $siteMap.sitemapid
            Name = $siteMap.sitemapname
            UniqueName = $siteMap.sitemapnameunique
            IsAppAware = $siteMap.isappaware
            ComponentState = $siteMap.componentstate
            ETag = $siteMap.'@odata.etag'
            SitemapXml = $siteMap.sitemapxml
        }
        SiteMapUnpublishedQuery = if ($siteMapDraft) { [pscustomobject]@{ ComponentState = $siteMapDraft.componentstate; IsUnpublishedLayer = ([int]$siteMapDraft.componentstate -eq 1) } } else { $null }
        ProposedSiteMapXml = $proposedXml
        SiteMapNeedsUpdate = ($sourceXml -cne $proposedXml)
        ReferenceComponents = $referenceComponents
        SolutionComponents = @($solutionComponents | ForEach-Object { [pscustomobject]@{ ComponentType = $_.componenttype; ObjectId = $_.objectid; RootComponentId = $_.rootsolutioncomponentid; RootComponentBehavior = $_.rootcomponentbehavior } })
        AppComponents = @($components | ForEach-Object { [pscustomobject]@{ ComponentId = $_.appmodulecomponentid; ComponentType = $_.componenttype; ObjectId = $_.objectid; IsMetadata = $_.ismetadata } })
        AppModuleRoles = $roleSnapshot
        AppValidation = [pscustomobject]@{
            ValidationSuccess = Get-PropertyValue -Object $validationResponse -Name 'ValidationSuccess'
            IssueCount = $validationIssues.Count
            BlockingErrorCount = @($validationIssueSummaries | Where-Object { $_.ErrorType -ceq 'Error' }).Count
            Issues = $validationIssueSummaries
        }
        AppModuleSiteMapBinding = $export.AppModuleSiteMapEntries
        SolutionExport = $export
        AddAppComponentsContract = $componentContract
        RequestCounts = [ordered]@{} + $script:RequestCounts
    }
}

function Get-ExpectedComponentKeys {
    if ($script:ResolvedReferenceComponents.Count) {
        foreach ($reference in $script:ResolvedReferenceComponents) {
            foreach ($payload in $reference.Payloads) {
                $type = switch ([string]$payload['@odata.type']) {
                    'Microsoft.Dynamics.CRM.entity' { 1; break }
                    'Microsoft.Dynamics.CRM.systemform' { 60; break }
                    'Microsoft.Dynamics.CRM.savedquery' { 26; break }
                    default { throw 'Unsupported app component type in resolved composition plan.' }
                }
                $id = @($payload.Keys | Where-Object { $_ -ne '@odata.type' })[0]
                [pscustomobject]@{ ComponentType = $type; ObjectId = [string]$payload[$id]; Payload = $payload; LogicalName = $reference.LogicalName }
            }
        }
        return
    }
    @(
        [pscustomobject]@{ ComponentType = 1; ObjectId = $script:Target.TableMetadataId }
        [pscustomobject]@{ ComponentType = 60; ObjectId = $script:Target.MainFormId }
        [pscustomobject]@{ ComponentType = 26; ObjectId = $script:Target.ActiveViewId }
    )
}

function Assert-ComponentStateForApply {
    param([object[]]$ExistingComponents)
    $expected = @(Get-ExpectedComponentKeys)
    $unexpected = @($ExistingComponents | Where-Object {
        $match = $false
        foreach ($item in $expected) { if ([int]$_.componenttype -eq $item.ComponentType -and $_.objectid -ceq $item.ObjectId) { $match = $true } }
        if (-not $match -and ([int]$_.componenttype -ne 62 -or $_.objectid -cne $script:Target.SiteMapId)) { $true }
    })
    if ($unexpected.Count) { throw 'Unexpected AppModule components exist; stop for manual reconciliation.' }
    $states = [System.Collections.Generic.List[object]]::new()
    $missing = [System.Collections.Generic.List[object]]::new()
    foreach ($item in $expected) {
        $matches = @($ExistingComponents | Where-Object {
            [int]$_.componenttype -eq $item.ComponentType -and ([string]$_.objectid).Trim('{}') -ieq ([string]$item.ObjectId).Trim('{}')
        })
        if ($matches.Count -gt 1) { throw 'Duplicate expected AppModule component rows exist; stop for manual reconciliation.' }
        $present = $matches.Count -eq 1
        $states.Add([pscustomobject]@{
            LogicalName = $item.LogicalName
            ComponentType = $item.ComponentType
            ObjectId = $item.ObjectId
            State = if ($present) { 'ALREADY_PRESENT' } else { 'ABSENT' }
        })
        if (-not $present) { $missing.Add($item.Payload) }
    }
    $script:MissingAppComponentPayloads = $missing.ToArray()
    [pscustomobject]@{
        AllPresent = $missing.Count -eq 0
        NonePresent = $states.Count -eq $missing.Count
        MissingCount = $missing.Count
        MissingPayloads = $missing.ToArray()
        ComponentStates = $states.ToArray()
    }
}

function Invoke-ApplySequence {
    param([object]$Snapshot)
    $state = Assert-ComponentStateForApply -ExistingComponents $Snapshot.AppComponents
    $components = @($Snapshot.AppComponents)
    if ($Snapshot.SiteMapNeedsUpdate) {
        $etag = [string]$Snapshot.SiteMap.ETag
        if ([string]::IsNullOrWhiteSpace($etag)) { throw 'Site Map preflight ETag is missing; stop before writes.' }
        Invoke-DataverseRequest -Method PATCH -Path "sitemaps($($script:Target.SiteMapId))" -Body ([ordered]@{ sitemapxml = $Snapshot.ProposedSiteMapXml }) -ETag $etag | Out-Null
        $draft = Get-UnpublishedSiteMap
        $published = Invoke-DataverseRequest -Method GET -Path "sitemaps($($script:Target.SiteMapId))?%24select=sitemapid,sitemapnameunique,componentstate,sitemapxml"
        if (-not $draft -or [int]$draft.componentstate -ne 1 -or $draft.sitemapxml -cne $Snapshot.ProposedSiteMapXml -or
            $published.sitemapxml -cne $Snapshot.SiteMap.SitemapXml) {
            throw 'Site Map PATCH did not read back as the expected Unpublished layer; stop without rollback or retry.'
        }
    }
    if ($state.MissingCount -gt 0) {
        $body = [ordered]@{ AppId = $script:Target.AppModuleId; Components = @($state.MissingPayloads) }
        Invoke-DataverseRequest -Method POST -Path 'AddAppComponents' -Body $body | Out-Null
        $components = @(Get-ODataRows -Path (New-CollectionPath -EntitySet 'appmodulecomponents' -Select 'appmodulecomponentid,_appmoduleidunique_value,componenttype,objectid,isdefault,ismetadata,rootappmodulecomponentid,rootcomponentbehavior' -Filter "_appmoduleidunique_value eq $($script:Target.AppModuleIdUnique)"))
        $afterState = Assert-ComponentStateForApply -ExistingComponents $components
        if (-not $afterState.AllPresent) { throw 'AddAppComponents read-back is incomplete; preserve partial state and reconcile manually.' }
    }
    $postSnapshot = Get-TargetSnapshot
    $postState = Assert-ComponentStateForApply -ExistingComponents $postSnapshot.AppComponents
    if (-not $postState.AllPresent -or $postSnapshot.SiteMapNeedsUpdate -or
        $postSnapshot.AppModule.UniqueName -cne $script:Target.AppUniqueName -or
        $postSnapshot.AppModule.Id -cne $Snapshot.AppModule.Id -or
        [int]$postSnapshot.AppModule.StateCode -ne 0 -or [int]$postSnapshot.AppModule.ComponentState -ne 1 -or
        (ConvertTo-Json -InputObject @($postSnapshot.AppModuleRoles) -Compress) -cne (ConvertTo-Json -InputObject @($Snapshot.AppModuleRoles) -Compress)) {
        throw 'Independent post-write GET verification failed; preserve partial state and reconcile manually.'
    }
    $appAfter = $postSnapshot.AppModule
    $components = @($postSnapshot.AppComponents)
    $validation = Invoke-DataverseRequest -Method GET -Path "ValidateApp(AppModuleId=$($script:Target.AppModuleId))"
    $validationResponse = Get-PropertyValue -Object $validation -Name 'AppValidationResponse'
    $validationSuccess = Get-PropertyValue -Object $validationResponse -Name 'ValidationSuccess'
    if ($validationSuccess -ne $true) {
        $issues = @(Get-PropertyValue -Object $validationResponse -Name 'ValidationIssueList')
        $script:LastSafeError = "ValidateApp did not succeed; issue count=$($issues.Count). No publish or rollback was attempted."
        throw 'ValidateApp reported validation issues; preserve current state and reconcile.'
    }
    [pscustomobject]@{
        AppModule = $appAfter
        AppComponents = $components
        SiteMap = $postSnapshot.SiteMap
        AppModuleSiteMapBinding = $postSnapshot.AppModuleSiteMapBinding
        Validation = $validation
        PublicationState = 'Unpublished; no publish endpoint is implemented'
        RoleChanges = 0
        AuditChanges = 0
        WriteResults = $script:WriteResults.ToArray()
        RequestCounts = [ordered]@{} + $script:RequestCounts
    }
}

function Invoke-Main {
    $plan = Get-AppCompositionPlan
    if ($PlanOnly) {
        Write-Output ($plan | ConvertTo-Json -Depth 20 -Compress)
        return
    }
    if ($Apply) {
        if ($Confirmation -cne 'APPLY PHASE 2D IN VN LMV IT' -or [string]::IsNullOrWhiteSpace($AuthorizationReference)) {
            throw 'Apply requires the exact Phase 2D confirmation phrase and a recorded authorization reference; no request was sent.'
        }
    }
    $snapshot = Get-TargetSnapshot
    if ($Apply) { Assert-AppValidationAllowsApply -AppValidation $snapshot.AppValidation }
    $componentState = Assert-ComponentStateForApply -ExistingComponents $snapshot.AppComponents
    $plan = Get-AppCompositionPlan
    $result = [ordered]@{
        Mode = if ($DryRun) { 'DryRun; GET-only' } else { 'Apply; explicitly gated' }
        Plan = $plan
        Preflight = $snapshot
        ComponentState = $componentState
        PlannedWriteCount = [int]$snapshot.SiteMapNeedsUpdate + [int]($componentState.MissingCount -gt 0)
        WritesMayHaveOccurred = $script:WritesStarted
    }
    if ($DryRun) {
        Write-Output ($result | ConvertTo-Json -Depth 30 -Compress)
        return
    }
    $script:WritesAllowed = $true
    $applied = Invoke-ApplySequence -Snapshot $snapshot
    $result.Status = 'Verified'
    $result.PostWriteReadBack = $applied
    $result.WritesMayHaveOccurred = $script:WritesStarted
    Write-Output ($result | ConvertTo-Json -Depth 30 -Compress)
}

if ($MyInvocation.InvocationName -ne '.') {
    try { Invoke-Main }
    catch {
        [ordered]@{
            Status = 'Stopped'
            Error = 'Operation stopped; raw exception omitted. Do not retry. Reconcile with GET before recovery.'
            ExceptionType = $_.Exception.GetType().Name
            FailedCommand = if ($_.Exception -is [System.Management.Automation.CommandNotFoundException]) { $_.Exception.CommandName } else { $null }
            Stage = $script:LastStage
            LastApiPath = $script:LastPath
            HttpStatus = $script:LastHttpStatus
            DataverseErrorCode = $script:LastErrorCode
            SafeError = $script:LastSafeError
            WritesMayHaveOccurred = $script:WritesStarted
            WriteResults = $script:WriteResults.ToArray()
            RequestCounts = $script:RequestCounts
        } | ConvertTo-Json -Depth 12 -Compress | Write-Output
        exit 1
    }
    finally {
        $script:AccessToken = $null
        $script:AccessTokenExpiresOn = [DateTimeOffset]::MinValue
        $script:WritesAllowed = $false
    }
}