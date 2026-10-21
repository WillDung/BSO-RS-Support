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
    $property = $Object.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $null
}

function Get-AppComponentPayloads {
    param([object]$Target = $script:Target)
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

function Get-AppCompositionPlan {
    $components = @(Get-AppComponentPayloads)
    [ordered]@{
        Mode = if ($Apply) { 'Apply; explicit approval phrase required' } elseif ($DryRun) { 'DryRun; GET-only' } else { 'PlanOnly; no authentication or network' }
        Target = [ordered]@{
            EnvironmentName = $script:Target.EnvironmentName
            AppName = $script:Target.AppName
            AppUniqueName = $script:Target.AppUniqueName
            AppModuleId = $script:Target.AppModuleId
            SolutionUniqueName = $script:Target.SolutionUniqueName
            TableLogicalName = $script:Target.TableLogicalName
        }
        ExistingSiteMapBinding = [ordered]@{
            ExportElement = 'AppModuleSiteMap'
            SiteMapUniqueName = $script:Target.SiteMapUniqueName
            AssociationEvidence = 'Target Solution export contains one AppModuleSiteMap entry with SiteMapUniqueName=srapp; live Site Map unique name is srapp.'
            StandardAppModuleComponentRowObserved = $false
            AddSiteMapComponent = $false
        }
        ProposedNavigation = [ordered]@{
            Area = 'Recruitment Support'
            Group = 'Administration'
            SubArea = 'TA Directory'
            SubAreaType = 'Entity'
            EntityLogicalName = $script:Target.TableLogicalName
            PreserveExistingNodeIds = $true
        }
        AddAppComponentsPayload = [ordered]@{
            AppId = $script:Target.AppModuleId
            Components = $components
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
                Purpose = 'Add existing TA table, Main form, and public view; omit Site Map because the export binding already exists.'
                MayPublish = $false
                SeparateApprovalRequired = $true
            }
        )
        MaximumWriteRequests = 2
        AutomaticRetries = 0
        AutomaticRollbackOrDelete = $false
        PublishXmlOrPublishAll = $false
        RoleAndAuditChanges = $false
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
    if ($subAreas.Count -ne 1 -or $subAreas[0].GetAttribute('Id') -cne $ExpectedNodeIds.SubArea) {
        throw 'Site Map SubArea structure/ID differs from the verified placeholder; stop without changing unrelated navigation.'
    }

    Set-LocalizedSiteMapTitle -Node $areas[0] -Title 'Recruitment Support'
    Set-LocalizedSiteMapTitle -Node $groups[0] -Title 'Administration'
    Set-LocalizedSiteMapTitle -Node $subAreas[0] -Title 'TA Directory'
    $entity = $subAreas[0].GetAttributeNode('Entity')
    if ($entity -and $entity.Value -cne $script:Target.TableLogicalName) {
        throw 'Existing Site Map SubArea targets a different entity; stop without replacing it.'
    }
    if (-not $entity) { $subAreas[0].SetAttribute('Entity', $script:Target.TableLogicalName) }
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
    $userEmail = [regex]::Match($text, '(?m)^\s*User Email:\s*(\S+)')
    if (-not $friendlyName.Success -or -not $url.Success -or -not $orgId.Success -or -not $environmentId.Success -or -not $userEmail.Success) {
        throw 'Could not verify PAC target identity; stop without Dataverse requests.'
    }
    [pscustomobject]@{
        FriendlyName = $friendlyName.Groups[1].Value
        OrganizationUrl = $url.Groups[1].Value.TrimEnd('/')
        OrganizationId = $orgId.Groups[1].Value
        EnvironmentId = $environmentId.Groups[1].Value
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

function Get-DataverseMetadataDocument {
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
    if ($Method -eq 'GET' -and $resource -notmatch '^(WhoAmI$|appmodules\(|appmodulecomponents$|sitemaps\(|sitemaps/Microsoft\.Dynamics\.CRM\.RetrieveUnpublishedMultiple\(|solutions$|publishers\(|solutioncomponents$|EntityDefinitions\(|systemforms\(|savedqueries(\(|$)|ValidateApp\()') {
        throw 'GET blocked: endpoint is outside the app and component metadata allowlist.'
    }
    if ($Method -eq 'PATCH' -and ($resource -cne "sitemaps($($script:Target.SiteMapId))" -or
        @($Body.Keys) -ne @('sitemapxml'))) {
        throw 'PATCH blocked: only the sitemapxml field on the existing target Site Map is allowed.'
    }
    if ($Method -eq 'POST' -and $resource -cne 'AddAppComponents') {
        throw 'POST blocked: only AddAppComponents is allowed; no create, publish, or role endpoint is allowed.'
    }
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
        TimeoutSec = 90
        ErrorAction = 'Stop'
    }
    if ($null -ne $Body) {
        $request.ContentType = 'application/json; charset=utf-8'
        $request.Body = ConvertTo-Json -InputObject $Body -Depth 30 -Compress
    }
    $script:RequestCounts[$Method]++
    $script:LastPath = $resource
    if ($Method -ne 'GET') { $script:WritesStarted = $true }
    try {
        $response = Invoke-RestMethod @request
        if ($Method -ne 'GET') {
            $script:WriteResults.Add([pscustomobject]@{ Method = $Method; ApiPath = $resource; HttpStatus = 204 })
        }
        return $response
    }
    catch {
        $status = Get-HttpStatusCode -ErrorRecord $_
        $script:LastHttpStatus = $status
        $script:LastErrorCode = $null
        $script:LastSafeError = 'Dataverse rejected the request; response details omitted.'
        try {
            $errorPayload = $_.ErrorDetails.Message | ConvertFrom-Json
            $candidateCode = [string]$errorPayload.error.code
            if ($candidateCode -match '^0x[0-9a-fA-F]{8}$') { $script:LastErrorCode = $candidateCode.ToLowerInvariant() }
            $candidateMessage = [string]$errorPayload.error.message
            if ($candidateMessage -match "(?i)Could not find a property named '([A-Za-z0-9_]+)'") {
                $script:LastSafeError = "Unknown metadata property: $($Matches[1])."
            }
            elseif ($candidateMessage -match "(?i)Resource not found for the segment '([A-Za-z0-9_]+)'") {
                $script:LastSafeError = "Unknown Web API segment: $($Matches[1])."
            }
        }
        catch { }
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
                MainFormInSolutionExport = @((Get-ExportGuidIds -Document $document -ParentName 'systemform' -IdName 'formid') -contains $script:Target.MainFormId)
                ActiveViewInSolutionExport = @((Get-ExportGuidIds -Document $document -ParentName 'savedquery' -IdName 'savedqueryid') -contains $script:Target.ActiveViewId)
            }
        }
        finally { $archive.Dispose() }
    }
    finally { if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force } }
}

function Get-TargetSnapshot {
    $script:LastStage = 'Verify PAC target'
    $script:PacIdentity = Assert-TargetInputs
    $script:AccessToken = Get-ValidatedAccessToken
    $script:LastStage = 'Verify Dataverse organization'
    $who = Invoke-DataverseRequest -Method GET -Path 'WhoAmI'
    if ([string]$who.OrganizationId -cne $ExpectedOrganizationId) { throw 'WhoAmI organization does not match expected organization.' }

    $script:LastStage = 'Verify project Solution and Publisher'
    $solutionRows = @(Get-ODataRows -Path (New-CollectionPath -EntitySet 'solutions' -Select 'solutionid,uniquename,friendlyname,ismanaged,_publisherid_value' -Filter "uniquename eq '$($script:Target.SolutionUniqueName)'"))
    if ($solutionRows.Count -ne 1) { throw 'Target Solution is missing or not unique.' }
    $solution = $solutionRows[0]
    $solutionPublisher = Invoke-DataverseRequest -Method GET -Path "publishers($($solution._publisherid_value))?%24select=publisherid,uniquename,customizationprefix"
    if ($solutionPublisher.uniquename -cne 'os_bso_rs_support' -or $solutionPublisher.customizationprefix -cne 'os') { throw 'Target Solution Publisher does not match the approved project Publisher.' }

    $script:LastStage = 'Read unpublished AppModule'
    $app = Invoke-DataverseRequest -Method GET -Path "appmodules($($script:Target.AppModuleId))/Microsoft.Dynamics.CRM.RetrieveUnpublished()?%24select=appmoduleid,appmoduleidunique,name,uniquename,componentstate,statecode,statuscode,solutionid,publishedon,_publisherid_value"
    if ($app.appmoduleid -cne $script:Target.AppModuleId -or $app.uniquename -cne $script:Target.AppUniqueName -or $app.name -cne $script:Target.AppName) { throw 'Adopted AppModule identity mismatch.' }
    if ([int]$app.statecode -ne 0 -or [int]$app.componentstate -ne 1) { throw 'AppModule is not Active and Unpublished; stop.' }

    $script:LastStage = 'Read existing Site Map'
    $siteMap = Invoke-DataverseRequest -Method GET -Path "sitemaps($($script:Target.SiteMapId))?%24select=sitemapid,sitemapname,sitemapnameunique,isappaware,componentstate,ismanaged,sitemapxml"
    if ($siteMap.sitemapid -cne $script:Target.SiteMapId -or $siteMap.sitemapnameunique -cne $script:Target.SiteMapUniqueName -or -not $siteMap.isappaware) { throw 'Target Site Map identity mismatch.' }

    $script:LastStage = 'Read TA table metadata'
    $entity = Invoke-DataverseRequest -Method GET -Path "EntityDefinitions(LogicalName='$($script:Target.TableLogicalName)')?%24select=LogicalName,MetadataId,ObjectTypeCode,EntitySetName"
    if ($entity.MetadataId -cne $script:Target.TableMetadataId -or [int]$entity.ObjectTypeCode -ne $script:Target.TableObjectTypeCode) { throw 'Target TA table identity mismatch.' }
    $script:LastStage = 'Read TA Main form'
    $form = Invoke-DataverseRequest -Method GET -Path "systemforms($($script:Target.MainFormId))?%24select=formid,name,objecttypecode,type,formactivationstate,componentstate,ismanaged,publishedon"
    $script:LastStage = 'Validate TA Main form'
    if ($form.formid -cne $script:Target.MainFormId -or $form.name -cne 'Information' -or [int]$form.type -ne 2 -or [string]$form.objecttypecode -notin @($script:Target.TableLogicalName,[string]$script:Target.TableObjectTypeCode) -or [int]$form.formactivationstate -ne 1 -or [int]$form.componentstate -ne 0) { throw 'TA Main form identity/state mismatch.' }
    $script:LastStage = 'Read TA public view'
    $view = Invoke-DataverseRequest -Method GET -Path "savedqueries($($script:Target.ActiveViewId))?%24select=savedqueryid,name,returnedtypecode,querytype,isprivate,statecode,componentstate,ismanaged"
    $script:LastStage = 'Validate TA public view'
    if ($view.savedqueryid -cne $script:Target.ActiveViewId -or $view.name -cne 'Active TA Directories' -or [int]$view.querytype -ne 0 -or $view.isprivate -or [string]$view.returnedtypecode -notin @($script:Target.TableLogicalName,[string]$script:Target.TableObjectTypeCode) -or [int]$view.statecode -ne 0 -or [int]$view.componentstate -ne 0) { throw 'TA public view identity/state mismatch.' }

    $script:LastStage = 'Read Solution component membership'
    $solutionComponents = @(Get-ODataRows -Path (New-CollectionPath -EntitySet 'solutioncomponents' -Select 'solutioncomponentid,componenttype,objectid,rootsolutioncomponentid,rootcomponentbehavior,ismetadata,_solutionid_value' -Filter "_solutionid_value eq $($solution.solutionid)"))
    $appRoot = @($solutionComponents | Where-Object { [int]$_.componenttype -eq 80 -and $_.objectid -ceq $script:Target.AppModuleId })
    $siteMapRoot = @($solutionComponents | Where-Object { [int]$_.componenttype -eq 62 -and $_.objectid -ceq $script:Target.SiteMapId })
    $tableRoot = @($solutionComponents | Where-Object { [int]$_.componenttype -eq 1 -and $_.objectid -ceq $script:Target.TableMetadataId })
    if ($appRoot.Count -ne 1 -or $siteMapRoot.Count -ne 1 -or $tableRoot.Count -ne 1) { throw 'App, Site Map, or TA Solution root membership mismatch.' }

    $script:LastStage = 'Read AppModule components'
    $components = @(Get-ODataRows -Path (New-CollectionPath -EntitySet 'appmodulecomponents' -Select 'appmodulecomponentid,_appmoduleidunique_value,componenttype,objectid,isdefault,ismetadata,rootappmodulecomponentid,rootcomponentbehavior' -Filter "_appmoduleidunique_value eq $($script:Target.AppModuleIdUnique)"))
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
    $script:LastStage = 'Verify exported form, view, and table'
    if (-not $export.MainFormInSolutionExport) { $script:LastSafeError = 'Main form ID was not matched in exported Solution XML.'; throw 'Target Solution export is missing the verified Main form.' }
    if (-not $export.ActiveViewInSolutionExport) { $script:LastSafeError = 'Active public view ID was not matched in exported Solution XML.'; throw 'Target Solution export is missing the verified Active view.' }
    [pscustomobject]@{
        AppModule = [pscustomobject]@{
            Id = $app.appmoduleid
            IdUnique = $app.appmoduleidunique
            Name = $app.name
            UniqueName = $app.uniquename
            StateCode = $app.statecode
            StatusCode = $app.statuscode
            ComponentState = $app.componentstate
            PublishedOn = Get-PropertyValue -Object $app -Name 'publishedon'
            PublisherLookupStatus = if ($app.PSObject.Properties['_publisherid_value']) { 'Returned; verify separately' } else { 'UNKNOWN' }
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
        Table = [pscustomobject]@{ LogicalName = $entity.LogicalName; MetadataId = $entity.MetadataId; ObjectTypeCode = $entity.ObjectTypeCode; EntitySetName = $entity.EntitySetName }
        MainForm = [pscustomobject]@{ Id = $form.formid; Name = $form.name; ObjectTypeCode = $form.objecttypecode; Type = $form.type; ActivationState = $form.formactivationstate; ComponentState = $form.componentstate }
        ActiveView = [pscustomobject]@{ Id = $view.savedqueryid; Name = $view.name; ReturnedTypeCode = $view.returnedtypecode; QueryType = $view.querytype; IsPrivate = $view.isprivate; StateCode = $view.statecode; ComponentState = $view.componentstate }
        SolutionComponents = @($solutionComponents | ForEach-Object { [pscustomobject]@{ ComponentType = $_.componenttype; ObjectId = $_.objectid; RootComponentId = $_.rootsolutioncomponentid; RootComponentBehavior = $_.rootcomponentbehavior } })
        AppComponents = @($components | ForEach-Object { [pscustomobject]@{ ComponentId = $_.appmodulecomponentid; ComponentType = $_.componenttype; ObjectId = $_.objectid; IsMetadata = $_.ismetadata } })
        AppModuleSiteMapBinding = $export.AppModuleSiteMapEntries
        SolutionExport = $export
        AddAppComponentsContract = $componentContract
        RequestCounts = [ordered]@{} + $script:RequestCounts
    }
}

function Get-ExpectedComponentKeys {
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
    $matches = foreach ($item in $expected) { @($ExistingComponents | Where-Object { [int]$_.componenttype -eq $item.ComponentType -and $_.objectid -ceq $item.ObjectId }).Count }
    if (@($matches | Where-Object { $_ -gt 0 }).Count -gt 0 -and @($matches | Where-Object { $_ -eq 0 }).Count -gt 0) {
        throw 'Partial expected AppModule component state detected; preserve and reconcile manually before Apply.'
    }
    [pscustomobject]@{ AllPresent = (@($matches | Where-Object { $_ -gt 0 }).Count -eq $expected.Count); NonePresent = (@($matches | Where-Object { $_ -gt 0 }).Count -eq 0) }
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
        if (-not $draft -or [int]$draft.componentstate -ne 1 -or $draft.sitemapxml -cne $Snapshot.ProposedSiteMapXml) {
            throw 'Site Map PATCH did not read back as the expected Unpublished layer; stop without rollback or retry.'
        }
    }
    if ($state.NonePresent) {
        $body = [ordered]@{ AppId = $script:Target.AppModuleId; Components = @(Get-AppComponentPayloads) }
        Invoke-DataverseRequest -Method POST -Path 'AddAppComponents' -Body $body | Out-Null
        $components = @(Get-ODataRows -Path (New-CollectionPath -EntitySet 'appmodulecomponents' -Select 'appmodulecomponentid,_appmoduleidunique_value,componenttype,objectid,isdefault,ismetadata,rootappmodulecomponentid,rootcomponentbehavior' -Filter "_appmoduleidunique_value eq $($script:Target.AppModuleIdUnique)"))
        $afterState = Assert-ComponentStateForApply -ExistingComponents $components
        if (-not $afterState.AllPresent) { throw 'AddAppComponents read-back is incomplete; preserve partial state and reconcile manually.' }
    }
    $postSnapshot = Get-TargetSnapshot
    $postState = Assert-ComponentStateForApply -ExistingComponents $postSnapshot.AppComponents
    if (-not $postState.AllPresent -or $postSnapshot.SiteMapNeedsUpdate -or
        $postSnapshot.AppModule.UniqueName -cne $script:Target.AppUniqueName -or
        [int]$postSnapshot.AppModule.StateCode -ne 0 -or [int]$postSnapshot.AppModule.ComponentState -ne 1) {
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
    $componentState = Assert-ComponentStateForApply -ExistingComponents $snapshot.AppComponents
    $result = [ordered]@{
        Mode = if ($DryRun) { 'DryRun; GET-only' } else { 'Apply; explicitly gated' }
        Plan = $plan
        Preflight = $snapshot
        ComponentState = $componentState
        PlannedWriteCount = [int]$snapshot.SiteMapNeedsUpdate + [int]$componentState.NonePresent
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