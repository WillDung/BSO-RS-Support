#requires -Version 7.4
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$EnvironmentName,
    [Parameter(Mandatory)][string]$OrganizationUrl,
    [Parameter(Mandatory)][string]$ExpectedEnvironmentId,
    [Parameter(Mandatory)][string]$ExpectedOrganizationId,
    [Parameter(Mandatory)][string]$BaselineSiteMapPath,
    [string]$EvidencePath,
    [switch]$Continue,
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$solutionUniqueName = 'os_sr_bso_rs_support'
$appUniqueName = 'srapp'
$legacyPageName = 'os_atsugground1availability_4d2f7'
$navigationId = 'subarea_cfc1d904'
$siteMapUniqueName = 'srapp'
$webResourceEntitySet = 'webresourceset'
$webResourceTypeCode = 61
$resources = @(
    [pscustomobject]@{
        Name = 'os_/bso/recruitment-dashboard.html'
        DisplayName = 'Recruitment Dashboard'
        Type = 1
        Path = Join-Path $PSScriptRoot '..\solutions\RecruitmentDashboard\WebResources\os_\bso\recruitment-dashboard.html'
        Bytes = $null
        Sha256 = $null
    }
    [pscustomobject]@{
        Name = 'os_/bso/recruitment-dashboard.js'
        DisplayName = 'Recruitment Dashboard Script'
        Type = 3
        Path = Join-Path $PSScriptRoot '..\solutions\RecruitmentDashboard\WebResources\os_\bso\recruitment-dashboard.js'
        Bytes = $null
        Sha256 = $null
    }
)

$script:ApiRoot = $null
$script:AccessToken = $null
$script:Journal = $null
$script:JournalPath = $null
$script:Counts = [ordered]@{ GET = 0; POST = 0; PATCH = 0 }

function Get-Sha256 {
    param([Parameter(Mandatory)][byte[]]$Bytes)
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes)).ToLowerInvariant()
}

function Get-XmlDocument {
    param([Parameter(Mandatory)][string]$Xml, [bool]$PreserveWhitespace = $false)
    $settings = [System.Xml.XmlReaderSettings]::new()
    $settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver = $null
    $reader = [System.Xml.XmlReader]::Create([IO.StringReader]::new($Xml), $settings)
    $document = [System.Xml.XmlDocument]::new()
    $document.PreserveWhitespace = $PreserveWhitespace
    $document.XmlResolver = $null
    try { $document.Load($reader) }
    finally { $reader.Dispose() }
    $document
}

function Get-SiteMapFingerprint {
    param([Parameter(Mandatory)][string]$Xml)
    $document = Get-XmlDocument -Xml $Xml
    function Get-NodeShape([System.Xml.XmlNode]$Node) {
        $attributes = [ordered]@{}
        foreach ($attribute in @($Node.Attributes | Sort-Object Name)) {
            $attributes[[string]$attribute.Name] = [string]$attribute.Value
        }
        $children = [System.Collections.Generic.List[object]]::new()
        foreach ($child in $Node.ChildNodes) {
            if ($child.NodeType -eq [System.Xml.XmlNodeType]::Element) {
                $children.Add((Get-NodeShape -Node $child))
            } elseif ($child.NodeType -in @([System.Xml.XmlNodeType]::Text, [System.Xml.XmlNodeType]::CDATA) -and
                -not [string]::IsNullOrWhiteSpace([string]$child.Value)) {
                $children.Add([string]$child.Value)
            }
        }
        [ordered]@{
            Name = [string]$Node.LocalName
            Namespace = [string]$Node.NamespaceURI
            Attributes = $attributes
            Children = @($children)
        }
    }
    $shape = Get-NodeShape -Node $document.DocumentElement
    $bytes = [Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $shape -Depth 50 -Compress))
    Get-Sha256 -Bytes $bytes
}

function Get-BaselineSiteMapXml {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw 'The exact live solution-exported AppModuleSiteMap.xml baseline is required.'
    }
    $export = Get-XmlDocument -Xml ([IO.File]::ReadAllText($Path))
    $nodes = @($export.SelectNodes("//*[local-name()='SiteMap']"))
    if ($nodes.Count -ne 1) {
        throw 'The exported app sitemap baseline must contain exactly one SiteMap node.'
    }
    [string]$nodes[0].OuterXml
}

function Get-ProposedSiteMap {
    param([Parameter(Mandatory)][string]$Xml)
    $document = Get-XmlDocument -Xml $Xml -PreserveWhitespace $true
    $nodes = @($document.SelectNodes("//*[local-name()='SubArea'][@Id='$navigationId']"))
    if ($nodes.Count -ne 1) {
        throw 'The exact legacy availability navigation item is missing or ambiguous.'
    }
    $node = $nodes[0]
    if ($node.GetAttribute('Page') -cne $legacyPageName -or $node.HasAttribute('Url')) {
        throw 'The live availability navigation item differs from the verified baseline; no overwrite is permitted.'
    }
    $title = $node.SelectSingleNode("./*[local-name()='Titles']/*[local-name()='Title'][@LCID='1033']")
    if ($null -eq $title -or $title.GetAttribute('Title') -cne 'ATSugg - Round 1 Availability') {
        throw 'The live availability navigation title differs from the verified baseline.'
    }
    if (@($document.SelectNodes("//*[local-name()='SubArea'][@Url='$webResourceUrl']")).Count -ne 0) {
        throw 'Recruitment Dashboard navigation already exists; no duplicate is created.'
    }
    $originalFingerprint = Get-SiteMapFingerprint -Xml $document.OuterXml
    $node.RemoveAttribute('Page')
    $node.SetAttribute('Url', $webResourceUrl)
    $title.SetAttribute('Title', 'Recruitment Dashboard')
    $proposedXml = [string]$document.OuterXml

    $restored = Get-XmlDocument -Xml $proposedXml -PreserveWhitespace $true
    $restoredNode = $restored.SelectSingleNode("//*[local-name()='SubArea'][@Id='$navigationId']")
    $restoredNode.RemoveAttribute('Url')
    $restoredNode.SetAttribute('Page', $legacyPageName)
    $restoredTitle = $restoredNode.SelectSingleNode("./*[local-name()='Titles']/*[local-name()='Title'][@LCID='1033']")
    $restoredTitle.SetAttribute('Title', 'ATSugg - Round 1 Availability')
    if ((Get-SiteMapFingerprint -Xml $restored.OuterXml) -cne $originalFingerprint) {
        throw 'The proposed sitemap changes fields outside the single approved navigation item.'
    }
    $proposedXml
}

function Invoke-DataverseRequest {
    param(
        [Parameter(Mandatory)][ValidateSet('GET', 'POST', 'PATCH')][string]$Method,
        [Parameter(Mandatory)][string]$Path,
        [object]$Body,
        [switch]$WithSolutionHeader,
        [string]$ETag
    )
    $uri = [Uri]($script:ApiRoot + $Path)
    if ($uri.Scheme -cne 'https' -or
        $uri.Authority -ine ([Uri]$OrganizationUrl).Authority -or
        $uri.AbsolutePath -notmatch '^/api/data/v9\.2/' -or $uri.UserInfo -or $uri.Fragment) {
        throw 'Dataverse request is outside the explicitly verified target organization.'
    }
    $headers = @{
        Authorization = "Bearer $script:AccessToken"
        Accept = 'application/json'
        'OData-Version' = '4.0'
        'OData-MaxVersion' = '4.0'
        Consistency = 'Strong'
    }
    if ($WithSolutionHeader) { $headers['MSCRM.SolutionUniqueName'] = $solutionUniqueName }
    if ($ETag) { $headers['If-Match'] = $ETag }
    $arguments = @{
        Uri = $uri
        Method = $Method
        Headers = $headers
        MaximumRetryCount = 0
        MaximumRedirection = 0
        TimeoutSec = 120
        SkipHttpErrorCheck = $true
    }
    if ($Method -ne 'GET') {
        if ($null -eq $Body) { throw 'Dataverse write requires an exact body.' }
        $arguments.Body = ConvertTo-Json -InputObject $Body -Depth 20 -Compress
        $arguments.ContentType = 'application/json; charset=utf-8'
        $script:Counts[$Method]++
    } else {
        $script:Counts.GET++
    }
    try { Invoke-WebRequest @arguments }
    catch {
        if ($Method -ne 'GET') { throw 'Dataverse write outcome is uncertain; stop without retry.' }
        throw 'Dataverse read failed.'
    }
}

function Get-DataverseJson {
    param([Parameter(Mandatory)][string]$Path)
    $response = Invoke-DataverseRequest -Method GET -Path $Path
    if ([int]$response.StatusCode -lt 200 -or [int]$response.StatusCode -ge 300) {
        throw 'Dataverse preflight/reconciliation read returned an unsuccessful status.'
    }
    if ([string]::IsNullOrWhiteSpace([string]$response.Content)) { return $null }
    $response.Content | ConvertFrom-Json
}

function Assert-PacTarget {
    $output = @(& pac org who --json 2>&1)
    if ($LASTEXITCODE -ne 0) { throw 'PAC identity check failed; no sign-in or environment switch was attempted.' }
    $identity = ($output -join "`n") | ConvertFrom-Json
    if ([string]$identity.OrgUrl.TrimEnd('/') -cne $OrganizationUrl.TrimEnd('/') -or
        [string]$identity.EnvironmentId -ine $ExpectedEnvironmentId -or
        [string]$identity.OrgId -ine $ExpectedOrganizationId) {
        throw 'PAC identity differs from the explicitly requested target.'
    }
    $identity
}

function Initialize-DelegatedToken {
    param([Parameter(Mandatory)]$PacIdentity)
    if (-not (Get-Module -ListAvailable -Name Az.Accounts)) {
        throw 'Existing Az.Accounts module is required; no sign-in or module installation was attempted.'
    }
    Import-Module Az.Accounts -ErrorAction Stop
    $context = Get-AzContext -ErrorAction Stop
    if ($null -eq $context -or $context.Account.Type -ne 'User' -or
        $context.Account.Id -ine [string]$PacIdentity.UserEmail) {
        throw 'Existing Az.Accounts identity does not match PAC; no login or context switch was attempted.'
    }
    $tokenResult = Get-AzAccessToken -ResourceUrl $OrganizationUrl -AsSecureString -ErrorAction Stop
    if ($tokenResult.Token -isnot [Security.SecureString]) {
        throw 'Az.Accounts did not return a secure Dataverse token.'
    }
    $script:AccessToken = ConvertFrom-SecureString -SecureString $tokenResult.Token -AsPlainText
    $parts = $script:AccessToken.Split('.')
    if ($parts.Count -ne 3) { throw 'Dataverse credential was not a JWT.' }
    $payload = $parts[1].Replace('-', '+').Replace('_', '/')
    switch ($payload.Length % 4) { 2 { $payload += '==' } 3 { $payload += '=' } }
    $claims = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload)) | ConvertFrom-Json
    $audience = [Uri]([string]$claims.aud)
    if ($claims.tid -ine $context.Tenant.Id -or
        $audience.Authority -ine ([Uri]$OrganizationUrl).Authority -or
        'user_impersonation' -notin @(([string]$claims.scp) -split '\s+') -or
        [DateTimeOffset]::FromUnixTimeSeconds([long]$claims.exp) -le [DateTimeOffset]::UtcNow) {
        throw 'Dataverse credential audience, tenant, delegated scope, or expiry is invalid.'
    }
    $who = Get-DataverseJson -Path 'WhoAmI'
    if ([string]$who.UserId -ine [string]$PacIdentity.UserId -or
        [string]$who.OrganizationId -ine $ExpectedOrganizationId) {
        throw 'Dataverse WhoAmI differs from PAC identity or the explicitly requested organization.'
    }
}

function Save-Journal {
    if ($null -eq $script:Journal) { return }
    $script:Journal.RequestCounts = $script:Counts
    $temporaryPath = $script:JournalPath + '.tmp'
    [IO.File]::WriteAllText(
        $temporaryPath,
        (ConvertTo-Json -InputObject $script:Journal -Depth 20),
        [Text.UTF8Encoding]::new($false)
    )
    if (Test-Path -LiteralPath $script:JournalPath) {
        [IO.File]::Move($temporaryPath, $script:JournalPath, $true)
    } else {
        [IO.File]::Move($temporaryPath, $script:JournalPath)
    }
}

function Get-ResourceRowsByName {
    param([Parameter(Mandatory)][string]$Name)
    $filter = [Uri]::EscapeDataString("name eq '$Name'")
    $published = Get-DataverseJson -Path (
        "${webResourceEntitySet}?%24select=webresourceid,name&%24filter=$filter"
    )
    $drafts = Get-DataverseJson -Path (
        "$webResourceEntitySet/Microsoft.Dynamics.CRM.RetrieveUnpublishedMultiple()?" +
        "%24select=webresourceid,name,componentstate&%24filter=$filter"
    )
    $rows = @(@($published.value) + @($drafts.value))
    foreach ($row in $rows) {
        if ([string]::IsNullOrWhiteSpace([string]$row.webresourceid)) {
            throw "A WebResource row for the requested name has no identity: $Name."
        }
    }
    @($rows | Group-Object -Property webresourceid | ForEach-Object { $_.Group[0] })
}

function Assert-ResourceAbsent {
    foreach ($resource in $resources) {
        if (@(Get-ResourceRowsByName -Name $resource.Name).Count -ne 0) {
            throw "A WebResource with the intended Dashboard name already exists: $($resource.Name)."
        }
    }
}

function Reconcile-ExistingResource {
    param(
        [Parameter(Mandatory)][object]$Resource,
        [Parameter(Mandatory)][string]$SolutionId
    )
    $rows = @(Get-ResourceRowsByName -Name $Resource.Name)
    if ($rows.Count -ne 1) {
        throw "The accepted Dashboard create is missing or ambiguous: $($Resource.Name)."
    }
    $resourceId = [string]$rows[0].webresourceid
    $readback = Get-DataverseJson -Path (
        "${webResourceEntitySet}($resourceId)?%24select=webresourceid,name,displayname,webresourcetype,content"
    )
    $membership = Get-SolutionMembership -SolutionId $SolutionId -ObjectId $resourceId
    if ([string]$readback.webresourceid -ine $resourceId -or
        [string]$readback.name -cne $Resource.Name -or
        [string]$readback.displayname -cne $Resource.DisplayName -or
        [int]$readback.webresourcetype -ne $Resource.Type -or
        [string]$readback.content -cne [Convert]::ToBase64String($Resource.Bytes) -or
        @($membership.value | Where-Object { [int]$_.componenttype -eq $webResourceTypeCode }).Count -ne 1) {
        throw "The accepted Dashboard create does not match source and solution membership: $($Resource.Name)."
    }
    $resourceId
}

function Assert-ContinuationJournal {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw 'Continue requires the existing deployment evidence file.'
    }
    $journal = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    $expectedNames = @(
        'os_/bso/recruitment-dashboard.html',
        'os_/bso/recruitment-dashboard.js',
        'srapp sitemap ETag patch',
        'scoped Dashboard PublishXml'
    )
    $htmlState = [string]$journal.Dispatches[0].State
    $htmlId = [string]$journal.Dispatches[0].WebResourceId
    $journalIds = @($journal.WebResourceIds | ForEach-Object { [string]$_ })
    $htmlIdentityMatches = if ($htmlState -ceq 'CREATE_ACCEPTED') {
        [string]::IsNullOrWhiteSpace($htmlId) -and $journalIds.Count -eq 0
    } elseif ($htmlState -ceq 'GET_RECONCILED') {
        $htmlId -match '^[0-9a-fA-F-]{36}$' -and
        $journalIds.Count -eq 1 -and $journalIds[0] -ieq $htmlId
    } else {
        $false
    }
    if ([string]$journal.Result -cne 'DISPATCHING' -or
        [string]$journal.Environment -cne $EnvironmentName -or
        [string]$journal.Solution -cne $solutionUniqueName -or
        [string]$journal.App -cne $appUniqueName -or
        @($journal.Dispatches | ForEach-Object { [string]$_.Name }).Count -ne $expectedNames.Count -or
        [string]::Join('|', @($journal.Dispatches | ForEach-Object { [string]$_.Name })) -cne
        [string]::Join('|', $expectedNames) -or
        -not $htmlIdentityMatches -or
        [string]$journal.Dispatches[0].HttpStatus -cne '204' -or
        [string]$journal.Dispatches[0].Sha256 -cne $resources[0].Sha256 -or
        [string]$journal.Dispatches[1].State -cne 'PLANNED' -or
        [string]$journal.Dispatches[1].Sha256 -cne $resources[1].Sha256 -or
        [string]$journal.Dispatches[2].State -cne 'PLANNED' -or
        [string]$journal.Dispatches[3].State -cne 'PLANNED' -or
        @($journal.WebResourceIds).Count -ne 0) {
        throw 'Continue accepts only the captured HTML-create-accepted, no-sitemap/no-publish journal state.'
    }
    $journal
}

function Resume-AcceptedResource {
    param([Parameter(Mandatory)][object]$Solution)
    if ([string]$script:Journal.SitemapId -ine [string]$siteMap.sitemapid) {
        throw 'Continuation journal sitemap identity differs from the live sitemap.'
    }
    if (@(Get-ResourceRowsByName -Name $resources[1].Name).Count -ne 0) {
        throw 'The remaining Dashboard resource exists without an accepted create in this journal.'
    }
    $resourceId = Reconcile-ExistingResource -Resource $resources[0] -SolutionId ([string]$Solution.solutionid)
    $script:Journal.WebResourceIds = @($resourceId)
    $script:Journal.Dispatches[0].WebResourceId = $resourceId
    Write-DispatchState -Name $resources[0].Name -State 'GET_RECONCILED'
}

function Get-SolutionMembership {
    param(
        [Parameter(Mandatory)][string]$SolutionId,
        [Parameter(Mandatory)][string]$ObjectId
    )
    Get-DataverseJson -Path (
        "solutioncomponents?%24select=objectid,componenttype&" +
        "%24filter=_solutionid_value%20eq%20$SolutionId%20and%20objectid%20eq%20$ObjectId"
    )
}

function Assert-DraftSiteMap {
    param([Parameter(Mandatory)][string]$ExpectedXml, [Parameter(Mandatory)][string]$SiteMapId)
    $drafts = Get-DataverseJson -Path (
        "sitemaps/Microsoft.Dynamics.CRM.RetrieveUnpublishedMultiple()?" +
        "%24select=sitemapid,sitemapnameunique,componentstate,sitemapxml&" +
        "%24filter=sitemapid%20eq%20$SiteMapId"
    )
    $rows = @($drafts.value | Where-Object {
        [string]$_.sitemapid -ieq $SiteMapId -and
        [string]$_.sitemapnameunique -ceq $siteMapUniqueName -and
        [int]$_.componentstate -eq 1
    })
    if ($rows.Count -ne 1 -or
        (Get-SiteMapFingerprint -Xml ([string]$rows[0].sitemapxml)) -cne
        (Get-SiteMapFingerprint -Xml $ExpectedXml)) {
        throw 'Unpublished srapp sitemap differs from the exact Dashboard navigation change.'
    }
}

function Write-DispatchState {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$State, [string]$HttpStatus)
    $entries = @($script:Journal.Dispatches | Where-Object Name -CEQ $Name)
    if ($entries.Count -ne 1) { throw 'Deployment journal entry is missing or ambiguous.' }
    $entries[0].State = $State
    if ($PSBoundParameters.ContainsKey('HttpStatus')) {
        $entries[0].HttpStatus = $HttpStatus
    }
    Save-Journal
}

$webResourceUrl = '$webresource:os_/bso/recruitment-dashboard.html'
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
foreach ($resource in $resources) {
    $resource.Path = [IO.Path]::GetFullPath($resource.Path)
    if (-not $resource.Path.StartsWith($repositoryRoot, [StringComparison]::OrdinalIgnoreCase) -or
        -not (Test-Path -LiteralPath $resource.Path -PathType Leaf)) {
        throw "Dashboard source is missing or outside the repository: $($resource.Name)"
    }
    $resource.Bytes = [IO.File]::ReadAllBytes($resource.Path)
    $resource.Sha256 = Get-Sha256 -Bytes $resource.Bytes
}
if ([string]::IsNullOrWhiteSpace($EvidencePath) -and $Apply) {
    throw 'Apply requires an evidence path outside the source tree.'
}
if ($Continue -and -not $Apply) {
    throw 'Continue is available only with Apply.'
}
if ($Apply) {
    $resolvedEvidence = [IO.Path]::GetFullPath($EvidencePath)
    if ($resolvedEvidence.StartsWith($repositoryRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'EvidencePath must be outside the repository.'
    }
    $evidenceParent = Split-Path -Parent $resolvedEvidence
    if (-not (Test-Path -LiteralPath $evidenceParent -PathType Container)) {
        throw 'Evidence parent directory must already exist.'
    }
    if ($Continue) {
        if (-not (Test-Path -LiteralPath $resolvedEvidence -PathType Leaf)) {
            throw 'Continue requires the existing deployment evidence file.'
        }
        $script:Journal = Assert-ContinuationJournal -Path $resolvedEvidence
        $script:Counts.GET = [int]$script:Journal.RequestCounts.GET
        $script:Counts.POST = [int]$script:Journal.RequestCounts.POST
        $script:Counts.PATCH = [int]$script:Journal.RequestCounts.PATCH
    } elseif (Test-Path -LiteralPath $resolvedEvidence) {
        throw 'EvidencePath must be a new file for a fresh deployment.'
    }
    $script:JournalPath = $resolvedEvidence
}
$OrganizationUrl = $OrganizationUrl.TrimEnd('/')
$organizationUri = [Uri]$OrganizationUrl
if ($organizationUri.Scheme -cne 'https' -or
    $organizationUri.AbsolutePath -ne '/' -or
    $organizationUri.Query -or $organizationUri.UserInfo -or $organizationUri.Fragment) {
    throw 'OrganizationUrl must be the exact HTTPS organization origin.'
}
$script:ApiRoot = $OrganizationUrl + '/api/data/v9.2/'

$baselineXml = Get-BaselineSiteMapXml -Path $BaselineSiteMapPath
$pac = Assert-PacTarget
Initialize-DelegatedToken -PacIdentity $pac
$solutionRows = Get-DataverseJson -Path (
    "solutions?%24select=solutionid,uniquename,version,_publisherid_value&" +
    "%24filter=uniquename%20eq%20'$solutionUniqueName'"
)
if (@($solutionRows.value | Where-Object uniquename -CEQ $solutionUniqueName).Count -ne 1) {
    throw 'Expected existing unmanaged solution is missing or duplicated.'
}
$solution = @($solutionRows.value | Where-Object uniquename -CEQ $solutionUniqueName)[0]
if ([string]$solution.version -cne '1.0.0.1') {
    throw 'Live project solution version differs from the reconciled source baseline.'
}
$publisher = Get-DataverseJson -Path "publishers($($solution._publisherid_value))?%24select=publisherid,customizationprefix"
if ([string]$publisher.customizationprefix -cne 'os') {
    throw 'Live project solution publisher prefix differs from the approved os prefix.'
}
$appRows = Get-DataverseJson -Path (
    "appmodules?%24select=appmoduleid,uniquename,name,statecode,componentstate&" +
    "%24filter=uniquename%20eq%20'$appUniqueName'"
)
if (@($appRows.value | Where-Object uniquename -CEQ $appUniqueName).Count -ne 1) {
    throw 'Expected srapp model-driven app is missing or duplicated.'
}
$app = @($appRows.value | Where-Object uniquename -CEQ $appUniqueName)[0]
if ([string]$app.name -cne 'BSO-RS-Support' -or
    [int]$app.statecode -ne 0 -or [int]$app.componentstate -ne 0) {
    throw 'The exact BSO-RS-Support app is not active and published.'
}
$siteMapRows = Get-DataverseJson -Path (
    "sitemaps?%24select=sitemapid,sitemapnameunique,isappaware,componentstate,sitemapxml&" +
    "%24filter=sitemapnameunique%20eq%20'$siteMapUniqueName'"
)
if (@($siteMapRows.value | Where-Object sitemapnameunique -CEQ $siteMapUniqueName).Count -ne 1) {
    throw 'Expected srapp sitemap is missing or duplicated.'
}
$siteMap = @($siteMapRows.value | Where-Object sitemapnameunique -CEQ $siteMapUniqueName)[0]
if (-not $siteMap.isappaware -or [int]$siteMap.componentstate -ne 0 -or
    (Get-SiteMapFingerprint -Xml ([string]$siteMap.sitemapxml)) -cne
    (Get-SiteMapFingerprint -Xml $baselineXml)) {
    throw 'Live published sitemap differs from the exact latest solution-exported baseline.'
}
$proposedSiteMapXml = Get-ProposedSiteMap -Xml ([string]$siteMap.sitemapxml)

$sitemapMembership = Get-SolutionMembership -SolutionId ([string]$solution.solutionid) -ObjectId ([string]$siteMap.sitemapid)
if (@($sitemapMembership.value | Where-Object { [int]$_.componenttype -eq 62 }).Count -ne 1) {
    throw 'The srapp sitemap is not an exact member of the existing project solution.'
}
$appMembership = Get-SolutionMembership -SolutionId ([string]$solution.solutionid) -ObjectId ([string]$app.appmoduleid)
if (@($appMembership.value | Where-Object { [int]$_.componenttype -eq 80 }).Count -ne 1) {
    throw 'The srapp app module is not an exact member of the existing project solution.'
}
if ($Continue) {
    Resume-AcceptedResource -Solution $solution
} else {
    Assert-ResourceAbsent
}

$plan = [ordered]@{
    Result = if ($Apply) { 'PREFLIGHT_PASSED_APPLY_AUTHORIZED' } else { 'PREFLIGHT_PASSED_NO_WRITES' }
    Environment = $EnvironmentName
    Solution = $solutionUniqueName
    App = $appUniqueName
    Navigation = 'Replace only the verified ATSugg availability menu entry with Recruitment Dashboard.'
    Resources = @($resources | ForEach-Object {
        [ordered]@{ Name = $_.Name; Type = $_.Type; Sha256 = $_.Sha256 }
    })
    ReadOnlyPreflightRequests = $script:Counts.GET
    WriteRequests = 0
}
if (-not $Apply) {
    $plan | ConvertTo-Json -Depth 8
    return
}

if (-not $Continue) {
    $script:Journal = [ordered]@{
        Result = 'DISPATCHING'
        Environment = $EnvironmentName
        Solution = $solutionUniqueName
        App = $appUniqueName
        WebResourceIds = @()
        SitemapId = [string]$siteMap.sitemapid
        Dispatches = [System.Collections.Generic.List[object]]::new()
        RequestCounts = $script:Counts
        AutomaticRetries = 0
    }
    foreach ($resource in $resources) {
        $script:Journal.Dispatches.Add([ordered]@{
            Name = $resource.Name
            State = 'PLANNED'
            HttpStatus = $null
            WebResourceId = $null
            Sha256 = $resource.Sha256
        })
    }
    $script:Journal.Dispatches.Add([ordered]@{
        Name = 'srapp sitemap ETag patch'
        State = 'PLANNED'
        HttpStatus = $null
        WebResourceId = [string]$siteMap.sitemapid
    })
    $script:Journal.Dispatches.Add([ordered]@{
        Name = 'scoped Dashboard PublishXml'
        State = 'PLANNED'
        HttpStatus = $null
        WebResourceId = [string]$app.appmoduleid
    })
    $journalStream = [IO.File]::Open($script:JournalPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    $journalStream.Dispose()
    Save-Journal
}

$createdIds = [System.Collections.Generic.List[string]]::new()
foreach ($resource in $resources) {
    $entry = @($script:Journal.Dispatches | Where-Object Name -CEQ $resource.Name)[0]
    if ($entry.State -eq 'GET_RECONCILED') {
        if ([string]$entry.WebResourceId -notmatch '^[0-9a-fA-F-]{36}$') {
            throw "Reconciled Dashboard WebResource ID is invalid: $($resource.Name)."
        }
        $createdIds.Add([string]$entry.WebResourceId)
        continue
    }
    if ($entry.State -cne 'PLANNED') {
        throw "Dashboard WebResource is not in a fresh dispatch state: $($resource.Name)."
    }
    Write-DispatchState -Name $resource.Name -State 'DISPATCH_RESERVED'
    $payload = [ordered]@{
        name = $resource.Name
        displayname = $resource.DisplayName
        description = if ($resource.Type -eq 1) {
            'Read-only Recruitment Dashboard. Does not perform booking or Candidate/Schedule writes.'
        } else {
            'Read-only Recruitment Dashboard queries and rendering.'
        }
        webresourcetype = $resource.Type
        content = [Convert]::ToBase64String($resource.Bytes)
    }
    $response = Invoke-DataverseRequest -Method POST -Path $webResourceEntitySet `
        -Body $payload -WithSolutionHeader
    if ([int]$response.StatusCode -notin @(201, 204)) {
        Write-DispatchState -Name $resource.Name -State 'UNCERTAIN_OR_REJECTED' -HttpStatus ([string]$response.StatusCode)
        throw "Dashboard WebResource creation failed or is uncertain: $($resource.Name). Stop without retry."
    }
    Write-DispatchState -Name $resource.Name -State 'CREATE_ACCEPTED' -HttpStatus ([string]$response.StatusCode)
    $filter = [Uri]::EscapeDataString("name eq '$($resource.Name)'")
    $matches = Get-DataverseJson -Path "${webResourceEntitySet}?%24select=webresourceid,name&%24filter=$filter"
    $rows = @($matches.value | Where-Object name -CEQ $resource.Name)
    if ($rows.Count -ne 1) {
        Write-DispatchState -Name $resource.Name -State 'CREATE_RECONCILIATION_FAILED'
        throw "Dashboard WebResource identity is missing or ambiguous: $($resource.Name). Stop without retry."
    }
    $resourceId = [string]$rows[0].webresourceid
    $readback = Get-DataverseJson -Path (
        "$webResourceEntitySet($resourceId)?%24select=webresourceid,name,displayname,webresourcetype,content"
    )
    $membership = Get-SolutionMembership -SolutionId ([string]$solution.solutionid) -ObjectId $resourceId
    if ([string]$readback.name -cne $resource.Name -or
        [string]$readback.displayname -cne $resource.DisplayName -or
        [int]$readback.webresourcetype -ne $resource.Type -or
        [string]$readback.content -cne [Convert]::ToBase64String($resource.Bytes) -or
        @($membership.value | Where-Object { [int]$_.componenttype -eq $webResourceTypeCode }).Count -ne 1) {
        Write-DispatchState -Name $resource.Name -State 'CREATE_RECONCILIATION_FAILED'
        throw "Dashboard resource content or solution membership differs: $($resource.Name)."
    }
    $createdIds.Add($resourceId)
    $script:Journal.WebResourceIds = @($createdIds)
    $entry = @($script:Journal.Dispatches | Where-Object Name -CEQ $resource.Name)[0]
    $entry.WebResourceId = $resourceId
    Write-DispatchState -Name $resource.Name -State 'GET_RECONCILED'
}

$freshSiteMapResponse = Invoke-DataverseRequest -Method GET -Path (
    "sitemaps($($siteMap.sitemapid))?%24select=sitemapid,sitemapnameunique,isappaware,componentstate,sitemapxml"
)
if ([int]$freshSiteMapResponse.StatusCode -lt 200 -or [int]$freshSiteMapResponse.StatusCode -ge 300) {
    throw 'Fresh pre-patch sitemap reconciliation failed; dashboard resources remain unpublished.'
}
$freshSiteMap = $freshSiteMapResponse.Content | ConvertFrom-Json
$freshEtag = [string]$freshSiteMapResponse.Headers['ETag']
if ([string]::IsNullOrWhiteSpace($freshEtag) -or
    [string]$freshSiteMap.sitemapnameunique -cne $siteMapUniqueName -or
    [int]$freshSiteMap.componentstate -ne 0 -or
    (Get-SiteMapFingerprint -Xml ([string]$freshSiteMap.sitemapxml)) -cne
    (Get-SiteMapFingerprint -Xml $baselineXml)) {
    throw 'Live sitemap changed after preflight; stop before sitemap patch and publication.'
}

Write-DispatchState -Name 'srapp sitemap ETag patch' -State 'DISPATCH_RESERVED'
$patch = Invoke-DataverseRequest -Method PATCH -Path "sitemaps($($siteMap.sitemapid))" `
    -Body ([ordered]@{ sitemapxml = $proposedSiteMapXml }) -ETag $freshEtag
if ([int]$patch.StatusCode -lt 200 -or [int]$patch.StatusCode -ge 300) {
    Write-DispatchState -Name 'srapp sitemap ETag patch' -State 'REJECTED_OR_UNCERTAIN' -HttpStatus ([string]$patch.StatusCode)
    throw 'Sitemap PATCH failed or is uncertain; stop without retry or publication.'
}
Write-DispatchState -Name 'srapp sitemap ETag patch' -State 'PATCH_ACCEPTED' -HttpStatus ([string]$patch.StatusCode)
Assert-DraftSiteMap -ExpectedXml $proposedSiteMapXml -SiteMapId ([string]$siteMap.sitemapid)
Write-DispatchState -Name 'srapp sitemap ETag patch' -State 'DRAFT_GET_RECONCILED'

$publishXml = '<importexportxml><webresources>' +
    (($createdIds | ForEach-Object { "<webresource>$_</webresource>" }) -join '') +
    '</webresources><appmodules><appmodule>' + [string]$app.appmoduleid +
    '</appmodule></appmodules></importexportxml>'
Write-DispatchState -Name 'scoped Dashboard PublishXml' -State 'DISPATCH_RESERVED'
$publish = Invoke-DataverseRequest -Method POST -Path 'PublishXml' `
    -Body ([ordered]@{ ParameterXml = $publishXml })
if ([int]$publish.StatusCode -lt 200 -or [int]$publish.StatusCode -ge 300) {
    Write-DispatchState -Name 'scoped Dashboard PublishXml' -State 'REJECTED_OR_UNCERTAIN' -HttpStatus ([string]$publish.StatusCode)
    throw 'Scoped PublishXml failed or is uncertain; stop without retry.'
}
Write-DispatchState -Name 'scoped Dashboard PublishXml' -State 'PUBLISH_ACCEPTED' -HttpStatus ([string]$publish.StatusCode)

foreach ($resource in $resources) {
    $entry = @($script:Journal.Dispatches | Where-Object Name -CEQ $resource.Name)[0]
    $readback = Get-DataverseJson -Path (
        "$webResourceEntitySet($($entry.WebResourceId))?%24select=webresourceid,name,displayname,webresourcetype,content"
    )
    if ([string]$readback.webresourceid -ine [string]$entry.WebResourceId -or
        [string]$readback.name -cne $resource.Name -or
        [string]$readback.displayname -cne $resource.DisplayName -or
        [int]$readback.webresourcetype -ne $resource.Type -or
        [string]$readback.content -cne [Convert]::ToBase64String($resource.Bytes)) {
        Write-DispatchState -Name $resource.Name -State 'PUBLISHED_GET_RECONCILIATION_FAILED'
        throw "Published Dashboard WebResource differs from source: $($resource.Name)."
    }
    Write-DispatchState -Name $resource.Name -State 'PUBLISHED_GET_RECONCILED'
}
$publishedSiteMap = Get-DataverseJson -Path (
    "sitemaps($($siteMap.sitemapid))?%24select=sitemapnameunique,componentstate,sitemapxml"
)
if ([string]$publishedSiteMap.sitemapnameunique -cne $siteMapUniqueName -or
    [int]$publishedSiteMap.componentstate -ne 0 -or
    (Get-SiteMapFingerprint -Xml ([string]$publishedSiteMap.sitemapxml)) -cne
    (Get-SiteMapFingerprint -Xml $proposedSiteMapXml)) {
    throw 'Published srapp sitemap does not match the exact Dashboard navigation change.'
}
Write-DispatchState -Name 'srapp sitemap ETag patch' -State 'PUBLISHED_GET_RECONCILED'
$script:Journal.Result = 'RECRUITMENT_DASHBOARD_DEPLOYED'
$script:Journal.RequestCounts = $script:Counts
$script:Journal.AutomaticRetries = 0
Save-Journal
[ordered]@{
    Result = $script:Journal.Result
    Environment = $EnvironmentName
    Solution = $solutionUniqueName
    App = $appUniqueName
    Resources = @($resources | ForEach-Object Name)
    SitemapPatchCount = 1
    PublishXmlCount = 1
    PublishXmlScope = 'Exactly two Dashboard WebResources and srapp'
    AutomaticRetries = 0
    EvidencePath = $script:JournalPath
} | ConvertTo-Json -Depth 8
