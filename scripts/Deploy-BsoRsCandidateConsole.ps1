#requires -Version 7.4
[CmdletBinding()]
param(
    [switch]$Apply,
    [switch]$Continue,
    [switch]$RefreshExisting,
    [Parameter(Mandatory)][string]$EnvironmentName,
    [Parameter(Mandatory)][string]$OrganizationUrl,
    [Parameter(Mandatory)][string]$ExpectedEnvironmentId,
    [Parameter(Mandatory)][string]$ExpectedOrganizationId,
    [Parameter(Mandatory)][string]$EvidencePath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$target = [ordered]@{
    EnvironmentName = 'VN LMV IT'
    OrganizationUrl = 'https://org14938ec2.crm4.dynamics.com'
    EnvironmentId = '92e44afb-6c3a-eb1a-8154-4ed51e1e6e42'
    OrganizationId = '0706072c-54ea-f011-872b-000d3ab60060'
    SolutionUniqueName = 'os_sr_bso_rs_support'
    AppId = '3709bb7c-28cd-f111-a05c-70a8a581cbfa'
    AppUniqueName = 'srapp'
    SiteMapId = '6a02d640-2ccd-f111-a05a-000d3a64b349'
    SiteMapUniqueName = 'srapp'
    WebResourceEntitySet = 'webresourceset'
    WebResourceObjectTypeCode = 61
    NavigationId = 'subarea_bso_candidate_management'
}
$resources = @(
    [pscustomobject]@{
        Name = 'os_/bso/candidate-console.html'
        DisplayName = 'Candidate Management Console'
        Type = 1
        Path = Join-Path $PSScriptRoot '..\solutions\CandidateConsole\WebResources\os_\bso\candidate-console.html'
    }
    [pscustomobject]@{
        Name = 'os_/bso/candidate-console.css'
        DisplayName = 'Candidate Management Console Styles'
        Type = 2
        Path = Join-Path $PSScriptRoot '..\solutions\CandidateConsole\WebResources\os_\bso\candidate-console.css'
    }
    [pscustomobject]@{
        Name = 'os_/bso/candidate-console.js'
        DisplayName = 'Candidate Management Console Script'
        Type = 3
        Path = Join-Path $PSScriptRoot '..\solutions\CandidateConsole\WebResources\os_\bso\candidate-console.js'
    }
)
$script:ApiRoot = $target.OrganizationUrl + '/api/data/v9.2/'
$script:AccessToken = $null
$script:Counts = @{ GET = 0; POST = 0; PATCH = 0 }
$script:Journal = $null
$script:JournalPath = $EvidencePath
$script:RefreshContentChecks = [System.Collections.Generic.List[object]]::new()

if ($EnvironmentName -cne $target.EnvironmentName -or
    $OrganizationUrl.TrimEnd('/') -cne $target.OrganizationUrl -or
    $ExpectedEnvironmentId -ine $target.EnvironmentId -or
    $ExpectedOrganizationId -ine $target.OrganizationId -or
    -not [IO.Path]::IsPathFullyQualified($EvidencePath) -or
    ((Test-Path -LiteralPath $EvidencePath) -and -not $Continue) -or
    ($Continue -and (-not (Test-Path -LiteralPath $EvidencePath -PathType Leaf) -or $RefreshExisting)) -or
    ($RefreshExisting -and -not $Apply -and (Test-Path -LiteralPath $EvidencePath))) {
    throw 'Candidate Console target or new evidence path is not exact.'
}
foreach ($resource in $resources) {
    $resource.Path = [IO.Path]::GetFullPath($resource.Path)
    if (-not (Test-Path -LiteralPath $resource.Path -PathType Leaf)) {
        throw "Candidate Console local resource is missing: $($resource.Name)"
    }
}

function Save-Journal {
    if ($null -eq $script:Journal) { return }
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
        $uri.Authority -ine ([Uri]$target.OrganizationUrl).Authority -or
        $uri.AbsolutePath -notmatch '^/api/data/v9\.2/' -or $uri.UserInfo -or $uri.Fragment) {
        throw 'Candidate Console request is outside the verified VN LMV IT Web API.'
    }
    $headers = @{
        Authorization = "Bearer $script:AccessToken"
        Accept = 'application/json'
        'OData-Version' = '4.0'
        'OData-MaxVersion' = '4.0'
        Consistency = 'Strong'
    }
    if ($WithSolutionHeader) { $headers['MSCRM.SolutionUniqueName'] = $target.SolutionUniqueName }
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
        if ($null -eq $Body) { throw 'Candidate Console write requires an exact body.' }
        $arguments.Body = ConvertTo-Json -InputObject $Body -Depth 20 -Compress
        $arguments.ContentType = 'application/json; charset=utf-8'
        $script:Counts[$Method]++
    } else { $script:Counts.GET++ }
    try { Invoke-WebRequest @arguments }
    catch {
        if ($Method -ne 'GET') {
            throw 'Candidate Console write outcome is uncertain; stop without retry.'
        }
        throw 'Candidate Console read failed.'
    }
}

function Get-DataverseJson {
    param([string]$Path)
    $response = Invoke-DataverseRequest -Method GET -Path $Path
    if ([int]$response.StatusCode -lt 200 -or [int]$response.StatusCode -ge 300) {
        throw 'Candidate Console preflight/reconciliation GET returned an unsuccessful status.'
    }
    if ([string]::IsNullOrWhiteSpace([string]$response.Content)) { return $null }
    $response.Content | ConvertFrom-Json
}

function Get-EffectiveWebResource {
    param([Parameter(Mandatory)][string]$ResourceId)
    $drafts = Get-DataverseJson -Path (
        "$($target.WebResourceEntitySet)/Microsoft.Dynamics.CRM.RetrieveUnpublishedMultiple()?" +
        "%24select=webresourceid,name,displayname,webresourcetype,content&" +
        "%24filter=webresourceid%20eq%20$ResourceId"
    )
    $draftRows = @($drafts.value | Where-Object {
        [string]$_.webresourceid -ieq $ResourceId
    })
    if ($draftRows.Count -gt 1) {
        throw 'Unpublished Candidate Console web resource is ambiguous.'
    }
    if ($draftRows.Count -eq 1) {
        return [pscustomobject]@{ Source = 'Unpublished'; Row = $draftRows[0] }
    }
    $published = Get-DataverseJson -Path (
        "$($target.WebResourceEntitySet)($ResourceId)?" +
        "%24select=webresourceid,name,displayname,webresourcetype,content"
    )
    [pscustomobject]@{ Source = 'Published'; Row = $published }
}

function Assert-PacTarget {
    $output = @(& pac org who --json 2>&1)
    if ($LASTEXITCODE -ne 0) { throw 'PAC identity check failed; no sign-in or environment switch was attempted.' }
    $identity = ($output -join "`n") | ConvertFrom-Json
    if ([string]$identity.OrgUrl.TrimEnd('/') -cne $target.OrganizationUrl -or
        [string]$identity.EnvironmentId -ine $target.EnvironmentId -or
        [string]$identity.OrgId -ine $target.OrganizationId) {
        throw 'PAC identity differs from the fixed Candidate Console target.'
    }
    $identity
}

function Assert-SiteMapNode {
    param([string]$Xml)
    $settings = [System.Xml.XmlReaderSettings]::new()
    $settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver = $null
    $reader = [System.Xml.XmlReader]::Create([IO.StringReader]::new($Xml), $settings)
    $document = [System.Xml.XmlDocument]::new()
    $document.PreserveWhitespace = $true
    $document.XmlResolver = $null
    try { $document.Load($reader) }
    finally { $reader.Dispose() }
    $areas = @($document.DocumentElement.SelectNodes("./*[local-name()='Area']"))
    if ($areas.Count -ne 1 -or $areas[0].GetAttribute('Id') -cne 'area_918af8a3') {
        throw 'srapp sitemap Area differs from the confirmed one-Area baseline.'
    }
    $groups = @($areas[0].SelectNodes("./*[local-name()='Group']"))
    if ($groups.Count -ne 1 -or $groups[0].GetAttribute('Id') -cne 'group_8b0502d1') {
        throw 'srapp sitemap group differs from the confirmed Administration group.'
    }
    $group = $groups[0]
    $subareas = @($group.SelectNodes("./*[local-name()='SubArea']"))
    $ids = @($document.SelectNodes("//*[local-name()='SubArea']") | ForEach-Object {
        $_.GetAttribute('Id')
    })
    if ($ids -contains $target.NavigationId) {
        throw 'Candidate Management navigation ID already exists; no overwrite is permitted.'
    }
    if ($subareas.Count -ne 4) {
        throw 'srapp sitemap SubArea count differs from the four-page baseline.'
    }
    $titles = @($subareas | ForEach-Object {
        $title = $_.SelectSingleNode("./*[local-name()='Titles']/*[local-name()='Title'][@LCID='1033']")
        if ($title) { $title.GetAttribute('Title') } else { '' }
    })
    if ([string]::Join('|', $titles) -cne 'TA Directory|Positions|Candidate Sources|Locations') {
        throw 'Existing srapp navigation differs from the verified four-page baseline.'
    }
    $template = $subareas[0]
    $newNode = [System.Xml.XmlElement]$template.CloneNode($true)
    $newNode.SetAttribute('Id', $target.NavigationId)
    $newNode.RemoveAttribute('Entity')
    $newNode.RemoveAttribute('FormId')
    $newNode.RemoveAttribute('ViewId')
    $newNode.SetAttribute('Url', '$webresource:os_/bso/candidate-console.html')
    $newTitle = $newNode.SelectSingleNode("./*[local-name()='Titles']/*[local-name()='Title'][@LCID='1033']")
    if ($null -eq $newTitle) { throw 'Sitemap clone has no English navigation title.' }
    $newTitle.SetAttribute('Title', 'Candidate Management')
    $group.AppendChild($newNode) | Out-Null
    [pscustomobject]@{ Document = $document; Xml = $document.OuterXml; NewNode = $newNode }
}

function Assert-ExistingSiteMapNode {
    param([string]$Xml)
    $settings = [System.Xml.XmlReaderSettings]::new()
    $settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver = $null
    $reader = [System.Xml.XmlReader]::Create([IO.StringReader]::new($Xml), $settings)
    $document = [System.Xml.XmlDocument]::new()
    $document.XmlResolver = $null
    try { $document.Load($reader) }
    finally { $reader.Dispose() }
    $areas = @($document.DocumentElement.SelectNodes("./*[local-name()='Area']"))
    if ($areas.Count -ne 1 -or $areas[0].GetAttribute('Id') -cne 'area_918af8a3') {
        throw 'srapp sitemap Area differs from the confirmed one-Area baseline.'
    }
    $groups = @($areas[0].SelectNodes("./*[local-name()='Group']"))
    if ($groups.Count -ne 1 -or $groups[0].GetAttribute('Id') -cne 'group_8b0502d1') {
        throw 'srapp sitemap group differs from the confirmed Administration group.'
    }
    $subareas = @($groups[0].SelectNodes("./*[local-name()='SubArea']"))
    $candidateNodes = @($document.SelectNodes("//*[local-name()='SubArea'][@Id='$($target.NavigationId)']"))
    $candidateTitle = if ($candidateNodes.Count -eq 1) {
        $candidateNodes[0].SelectSingleNode("./*[local-name()='Titles']/*[local-name()='Title'][@LCID='1033']")
    }
    if ($subareas.Count -ne 5 -or $candidateNodes.Count -ne 1 -or
        $candidateNodes[0].GetAttribute('Url') -cne '$webresource:os_/bso/candidate-console.html' -or
        $null -eq $candidateTitle -or $candidateTitle.GetAttribute('Title') -cne 'Candidate Management') {
        throw 'Existing Candidate Management sitemap navigation is missing or differs from the expected web resource.'
    }
    $existingTitles = @($subareas | Where-Object { $_.GetAttribute('Id') -cne $target.NavigationId } | ForEach-Object {
        $title = $_.SelectSingleNode("./*[local-name()='Titles']/*[local-name()='Title'][@LCID='1033']")
        if ($title) { $title.GetAttribute('Title') } else { '' }
    })
    if ([string]::Join('|', $existingTitles) -cne 'TA Directory|Positions|Candidate Sources|Locations') {
        throw 'Existing srapp navigation differs from the verified four-page baseline.'
    }
    $document
}

function Get-SiteMapSemanticFingerprint {
    param([string]$Xml)
    $settings = [System.Xml.XmlReaderSettings]::new()
    $settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver = $null
    $reader = [System.Xml.XmlReader]::Create([IO.StringReader]::new($Xml), $settings)
    $document = [System.Xml.XmlDocument]::new()
    $document.PreserveWhitespace = $false
    $document.XmlResolver = $null
    try { $document.Load($reader) }
    finally { $reader.Dispose() }
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
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
}

function Assert-UnpublishedSiteMap {
    param([string]$ExpectedXml)
    $drafts = Get-DataverseJson -Path (
        "sitemaps/Microsoft.Dynamics.CRM.RetrieveUnpublishedMultiple()?" +
        "%24select=sitemapid,sitemapnameunique,componentstate,sitemapxml&" +
        "%24filter=sitemapid%20eq%20$($target.SiteMapId)"
    )
    $draftRows = @($drafts.value | Where-Object {
        [string]$_.sitemapid -ieq $target.SiteMapId -and
        [string]$_.sitemapnameunique -ceq $target.SiteMapUniqueName -and
        [int]$_.componentstate -eq 1
    })
    if ($draftRows.Count -ne 1 -or
        (Get-SiteMapSemanticFingerprint -Xml ([string]$draftRows[0].sitemapxml)) -cne
        (Get-SiteMapSemanticFingerprint -Xml $ExpectedXml)) {
        throw 'Unpublished srapp sitemap differs semantically from the exact scoped Candidate Management change.'
    }
}

function Write-DispatchState {
    param([string]$Name, [string]$State, [string]$HttpStatus)
    $entry = @($script:Journal.Dispatches | Where-Object Name -CEQ $Name)
    if ($entry.Count -ne 1) { throw 'Candidate Console dispatch journal entry is ambiguous.' }
    $entry[0].State = $State
    $entry[0].HttpStatus = $HttpStatus
    Save-Journal
}

try {
    if ($Continue) {
        $script:Journal = Get-Content -LiteralPath $EvidencePath -Raw | ConvertFrom-Json
        $journalNames = @($script:Journal.Dispatches | ForEach-Object { [string]$_.Name })
        $expectedJournalNames = @($resources | ForEach-Object { [string]$_.Name }) + 'srapp sitemap + scoped PublishXml'
        if ($script:Journal.Result -cne 'DISPATCHING' -or
            [string]$script:Journal.Environment -cne $target.EnvironmentName -or
            [string]$script:Journal.AppUniqueName -cne $target.AppUniqueName -or
            [string]$script:Journal.SolutionUniqueName -cne $target.SolutionUniqueName -or
            [string]::Join('|', $journalNames) -cne [string]::Join('|', $expectedJournalNames) -or
            $script:Journal.SiteMapPatch -notin @('NOT_DISPATCHED', 'RECONCILIATION_FAILED') -or
            $script:Journal.PublishXml -cne 'NOT_DISPATCHED') {
            throw 'Retained Candidate Console journal is not an exact resumable partial deployment.'
        }
    }
    $pac = Assert-PacTarget
    if (-not (Get-Module -ListAvailable -Name Az.Accounts)) {
        throw 'Existing Az.Accounts module is required; no login or module installation attempted.'
    }
    Import-Module Az.Accounts -ErrorAction Stop
    $context = Get-AzContext -ErrorAction Stop
    if ($null -eq $context -or $context.Account.Type -ne 'User' -or
        $context.Account.Id -ine [string]$pac.UserEmail) {
        throw 'Existing Az.Accounts identity does not match PAC; no login or context switch attempted.'
    }
    $tokenResult = Get-AzAccessToken -ResourceUrl $target.OrganizationUrl -AsSecureString -ErrorAction Stop
    if ($tokenResult.Token -isnot [Security.SecureString]) {
        throw 'Az.Accounts did not return a secure Dataverse token.'
    }
    $script:AccessToken = ConvertFrom-SecureString -SecureString $tokenResult.Token -AsPlainText
    $jwtParts = $script:AccessToken.Split('.')
    if ($jwtParts.Count -ne 3) { throw 'Dataverse credential was not a JWT.' }
    $jwtPayload = $jwtParts[1].Replace('-', '+').Replace('_', '/')
    switch ($jwtPayload.Length % 4) { 2 { $jwtPayload += '==' } 3 { $jwtPayload += '=' } }
    $claims = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($jwtPayload)) | ConvertFrom-Json
    $audience = [Uri]([string]$claims.aud)
    if ($claims.tid -ine $context.Tenant.Id -or
        $audience.Authority -ine ([Uri]$target.OrganizationUrl).Authority -or
        'user_impersonation' -notin @(([string]$claims.scp) -split '\s+') -or
        [DateTimeOffset]::FromUnixTimeSeconds([long]$claims.exp) -le [DateTimeOffset]::UtcNow) {
        throw 'Dataverse credential audience, tenant, delegated scope, or expiry is invalid.'
    }
    $who = Get-DataverseJson -Path 'WhoAmI'
    if ([string]$who.UserId -ine [string]$pac.UserId -or
        [string]$who.OrganizationId -ine $target.OrganizationId) {
        throw 'Dataverse WhoAmI differs from PAC identity or expected organization.'
    }
    $solutionRows = Get-DataverseJson -Path "solutions?%24select=solutionid,uniquename,_publisherid_value&%24filter=uniquename eq '$($target.SolutionUniqueName)'"
    if (@($solutionRows.value).Count -ne 1) { throw 'Expected existing project Solution is absent or duplicated.' }
    $publisher = Get-DataverseJson -Path "publishers($($solutionRows.value[0]._publisherid_value))?%24select=publisherid,customizationprefix"
    if ($publisher.customizationprefix -cne 'os') { throw 'Existing project Solution Publisher prefix differs from os.' }
    $appRows = Get-DataverseJson -Path "appmodules?%24select=appmoduleid,uniquename,name,statecode,componentstate&%24filter=uniquename eq '$($target.AppUniqueName)'"
    if (@($appRows.value).Count -ne 1 -or
        [string]$appRows.value[0].appmoduleid -ine $target.AppId -or
        [string]$appRows.value[0].name -cne 'BSO-RS-Support' -or
        [int]$appRows.value[0].statecode -ne 0) {
        throw 'Existing srapp identity or active state differs from the approved app.'
    }
    $siteMap = Get-DataverseJson -Path "sitemaps($($target.SiteMapId))?%24select=sitemapid,sitemapnameunique,isappaware,componentstate,sitemapxml"
    if ([string]$siteMap.sitemapnameunique -cne $target.SiteMapUniqueName -or
        -not $siteMap.isappaware -or [int]$siteMap.componentstate -ne 0) {
        throw 'Existing srapp Site Map identity or published state is not exact.'
    }
    $siteMapResponse = Invoke-DataverseRequest -Method GET -Path "sitemaps($($target.SiteMapId))?%24select=sitemapid,sitemapnameunique,isappaware,componentstate,sitemapxml"
    $etag = [string]$siteMapResponse.Headers['ETag']
    if ([string]::IsNullOrWhiteSpace($etag)) { throw 'Fresh Site Map ETag is unavailable.' }
    $proposed = if ($RefreshExisting) {
        Assert-ExistingSiteMapNode -Xml ([string]$siteMap.sitemapxml)
    } else {
        Assert-SiteMapNode -Xml ([string]$siteMap.sitemapxml)
    }

    $nameFilter = [string]::Join(' or ', @($resources | ForEach-Object {
        "name eq '$($_.Name)'"
    }))
    $existing = Get-DataverseJson -Path "$($target.WebResourceEntitySet)?%24select=webresourceid,name&%24filter=$([Uri]::EscapeDataString($nameFilter))"
    if ($RefreshExisting) {
        if (@($existing.value).Count -ne $resources.Count -or
            @($existing.value | Where-Object { $_.name -notin @($resources | ForEach-Object Name) }).Count -ne 0) {
            throw 'Refresh requires exactly the three existing Candidate Console web resources.'
        }
        foreach ($resource in $resources) {
            $matches = @($existing.value | Where-Object name -CEQ $resource.Name)
            if ($matches.Count -ne 1) { throw "Refresh resource identity is missing or ambiguous: $($resource.Name)" }
            $resourceId = [string]$matches[0].webresourceid
            $effective = Get-EffectiveWebResource -ResourceId $resourceId
            $readback = $effective.Row
            $membership = Get-DataverseJson -Path "solutioncomponents?%24select=objectid,componenttype&%24filter=_solutionid_value eq $($solutionRows.value[0].solutionid) and objectid eq $resourceId"
            if ([string]$readback.name -cne $resource.Name -or
                [string]$readback.displayname -cne $resource.DisplayName -or
                [int]$readback.webresourcetype -ne $resource.Type -or
                @($membership.value | Where-Object {
                    [int]$_.componenttype -eq $target.WebResourceObjectTypeCode -and
                    [string]$_.objectid -ieq $resourceId
                }).Count -ne 1) {
                throw "Existing resource identity or Solution membership differs: $($resource.Name)"
            }
            try { $remoteBytes = [Convert]::FromBase64String([string]$readback.content) }
            catch { throw "Existing resource content is not valid base64: $($resource.Name)" }
            $localBytes = [IO.File]::ReadAllBytes($resource.Path)
            $remoteHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($remoteBytes)).ToLowerInvariant()
            $localHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($localBytes)).ToLowerInvariant()
            $script:RefreshContentChecks.Add([ordered]@{
                Name = $resource.Name
                Source = $effective.Source
                ContentMatchesLocal = $remoteHash -ceq $localHash
                LocalSha256 = $localHash
                RemoteSha256 = $remoteHash
            })
        }
    } else {
        if ((-not $Continue -and @($existing.value).Count -ne 0) -or
            ($Continue -and @($existing.value | Where-Object { $_.name -notin @($resources | ForEach-Object Name) }).Count -ne 0)) {
            throw 'One or more exact Candidate Console web resource names already exist; no overwrite permitted.'
        }
        if ($Continue -and @($existing.value).Count -ne $resources.Count) {
            throw 'Continuation requires all three already-created web resources; no missing resource is recreated.'
        }
    }
    $memberships = Get-DataverseJson -Path "solutioncomponents?%24select=objectid,componenttype&%24filter=_solutionid_value eq $($solutionRows.value[0].solutionid)"
    $navMember = @($memberships.value | Where-Object {
        [int]$_.componenttype -eq 62 -and [string]$_.objectid -ieq $target.SiteMapId
    })
    if ($navMember.Count -ne 1) {
        throw 'Existing srapp Site Map is not an exact member of the project Solution.'
    }

    if (-not $Apply -and -not $Continue) {
        if ($RefreshExisting) {
            [ordered]@{
                Result = 'CANDIDATE_CONSOLE_REFRESH_PREFLIGHT_READY'
                Environment = $target.EnvironmentName
                AppUniqueName = $target.AppUniqueName
                SolutionUniqueName = $target.SolutionUniqueName
                ExistingNavigation = 'Candidate Management -> $webresource:os_/bso/candidate-console.html'
                ResourceNames = @($resources | ForEach-Object Name)
                ResourceCountExisting = @($existing.value).Count
                ContentChecks = @($script:RefreshContentChecks)
                Writes = 0
                AutomaticRetries = 0
            } | ConvertTo-Json -Depth 8
            return
        }
        [ordered]@{
            Result = 'CANDIDATE_CONSOLE_DEPLOYMENT_PREFLIGHT_READY'
            Environment = $target.EnvironmentName
            AppUniqueName = $target.AppUniqueName
            SolutionUniqueName = $target.SolutionUniqueName
            ExistingNavigationCount = 4
            ProposedNavigationTitle = 'Candidate Management'
            ResourceNames = @($resources | ForEach-Object Name)
            ResourceCountExisting = @($existing.value).Count
            Writes = 0
            AutomaticRetries = 0
        } | ConvertTo-Json -Depth 8
        return
    }

    if ($RefreshExisting) {
        $parent = Split-Path -Parent $EvidencePath
        if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
            throw 'Candidate Console evidence parent directory must already exist.'
        }
        $journalStream = [IO.File]::Open($EvidencePath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $journalStream.Dispose()
        $script:Journal = [ordered]@{
            Result = 'DISPATCHING'
            Environment = $target.EnvironmentName
            AppUniqueName = $target.AppUniqueName
            SolutionUniqueName = $target.SolutionUniqueName
            Dispatches = [System.Collections.Generic.List[object]]::new()
            ResourceIds = @()
            SiteMapPatch = 'NOT_DISPATCHED'
            PublishXml = 'NOT_DISPATCHED'
            RequestCounts = $script:Counts
            AutomaticRetries = 0
        }
        foreach ($resource in $resources) {
            $script:Journal.Dispatches.Add([ordered]@{
                Name = $resource.Name
                State = 'PLANNED'
                HttpStatus = $null
                WebResourceId = $null
            })
        }
        $script:Journal.Dispatches.Add([ordered]@{
            Name = 'srapp + three web resources scoped PublishXml'
            State = 'PLANNED'
            HttpStatus = $null
            WebResourceId = $null
        })
        Save-Journal

        foreach ($resource in $resources) {
            $entry = @($script:Journal.Dispatches | Where-Object Name -CEQ $resource.Name)[0]
            $matches = @($existing.value | Where-Object name -CEQ $resource.Name)
            if ($matches.Count -ne 1) { throw "Refresh resource identity changed after preflight: $($resource.Name)" }
            $resourceId = [string]$matches[0].webresourceid
            $expectedContent = [Convert]::ToBase64String([IO.File]::ReadAllBytes($resource.Path))
            $readResponse = Invoke-DataverseRequest -Method GET `
                -Path "$($target.WebResourceEntitySet)($resourceId)?%24select=webresourceid,name,displayname,webresourcetype,content"
            if ([int]$readResponse.StatusCode -lt 200 -or [int]$readResponse.StatusCode -ge 300) {
                throw "Refresh resource GET failed: $($resource.Name)"
            }
            $etag = [string]$readResponse.Headers['ETag']
            if ([string]::IsNullOrWhiteSpace($etag)) {
                throw "Refresh resource ETag is unavailable: $($resource.Name)"
            }
            $readback = (Get-EffectiveWebResource -ResourceId $resourceId).Row
            if ([string]$readback.name -cne $resource.Name -or
                [string]$readback.displayname -cne $resource.DisplayName -or
                [int]$readback.webresourcetype -ne $resource.Type) {
                throw "Refresh resource identity changed after preflight: $($resource.Name)"
            }
            $entry.WebResourceId = $resourceId
            if ([string]$readback.content -ceq $expectedContent) {
                $entry.State = 'GET_RECONCILED_UNCHANGED'
            } else {
                $entry.State = 'DISPATCH_RESERVED'
                Save-Journal
                $patch = Invoke-DataverseRequest -Method PATCH `
                    -Path "$($target.WebResourceEntitySet)($resourceId)" `
                    -Body ([ordered]@{ content = $expectedContent }) -ETag $etag -WithSolutionHeader
                $entry.HttpStatus = [int]$patch.StatusCode
                if ([int]$patch.StatusCode -lt 200 -or [int]$patch.StatusCode -ge 300) {
                    $entry.State = "REJECTED_OR_UNCERTAIN:$($patch.StatusCode)"
                    Save-Journal
                    throw "Refresh resource PATCH failed or is uncertain: $($resource.Name); no retry."
                }
                $entry.State = 'PATCH_ACKNOWLEDGED'
                Save-Journal
                $readback = (Get-EffectiveWebResource -ResourceId $resourceId).Row
                if ([string]$readback.name -cne $resource.Name -or
                    [string]$readback.displayname -cne $resource.DisplayName -or
                    [int]$readback.webresourcetype -ne $resource.Type -or
                    [string]$readback.content -cne $expectedContent) {
                    throw "Refresh resource PATCH readback mismatch: $($resource.Name); stop without retry."
                }
                $entry.State = 'GET_RECONCILED'
            }
            $script:Journal.ResourceIds = @($script:Journal.ResourceIds) + $resourceId
            Save-Journal
        }

        $webresourceXml = [System.Text.StringBuilder]::new()
        [void]$webresourceXml.Append('<webresources>')
        foreach ($resourceId in $script:Journal.ResourceIds) {
            [void]$webresourceXml.Append("<webresource>$resourceId</webresource>")
        }
        [void]$webresourceXml.Append('</webresources>')
        $parameterXml = "<importexportxml>$($webresourceXml.ToString())<appmodules><appmodule>$($target.AppId)</appmodule></appmodules></importexportxml>"
        $publishEntry = @($script:Journal.Dispatches | Where-Object Name -CEQ 'srapp + three web resources scoped PublishXml')[0]
        $publishEntry.State = 'DISPATCH_RESERVED'
        $script:Journal.PublishXml = 'DISPATCH_RESERVED'
        Save-Journal
        $publish = Invoke-DataverseRequest -Method POST -Path 'PublishXml' `
            -Body ([ordered]@{ ParameterXml = $parameterXml })
        $publishEntry.HttpStatus = [int]$publish.StatusCode
        if ([int]$publish.StatusCode -lt 200 -or [int]$publish.StatusCode -ge 300) {
            $publishEntry.State = "REJECTED_OR_UNCERTAIN:$($publish.StatusCode)"
            $script:Journal.PublishXml = "REJECTED_OR_UNCERTAIN:$($publish.StatusCode)"
            Save-Journal
            throw 'Scoped srapp/webresource PublishXml failed or is uncertain; stop without retry.'
        }
        $publishEntry.State = "ACCEPTED:$($publish.StatusCode)"
        $script:Journal.PublishXml = "ACCEPTED:$($publish.StatusCode)"
        $script:Journal.Result = 'CANDIDATE_CONSOLE_REFRESHED'
        Save-Journal
        [ordered]@{
            Result = 'CANDIDATE_CONSOLE_REFRESHED'
            Environment = $target.EnvironmentName
            AppUniqueName = $target.AppUniqueName
            SolutionUniqueName = $target.SolutionUniqueName
            Resources = @($resources | ForEach-Object Name)
            WebResourcePatchCount = $script:Counts.PATCH
            SitemapPatchCount = 0
            PublishXmlCount = 1
            PublishXmlScope = 'srapp + three exact web resources'
            AutomaticRetries = 0
            EvidencePath = $EvidencePath
        } | ConvertTo-Json -Depth 8
        return
    }

    if ($Continue) {
        foreach ($resource in $resources) {
            $entry = @($script:Journal.Dispatches | Where-Object Name -CEQ $resource.Name)
            $matches = @($existing.value | Where-Object name -CEQ $resource.Name)
            if ($entry.Count -ne 1 -or $entry[0].State -notin @('GET_RECONCILED', 'UNCERTAIN_OR_REJECTED') -or
                $matches.Count -ne 1) {
                throw "Continuation resource inventory is not exact: $($resource.Name)"
            }
            $resourceId = [string]$matches[0].webresourceid
            $readback = Get-DataverseJson -Path "$($target.WebResourceEntitySet)($resourceId)?%24select=webresourceid,name,displayname,webresourcetype,content"
            $membership = Get-DataverseJson -Path "solutioncomponents?%24select=objectid,componenttype&%24filter=_solutionid_value eq $($solutionRows.value[0].solutionid) and objectid eq $resourceId"
            if ([string]$readback.name -cne $resource.Name -or
                [string]$readback.displayname -cne $resource.DisplayName -or
                [int]$readback.webresourcetype -ne $resource.Type -or
                [string]$readback.content -cne [Convert]::ToBase64String([IO.File]::ReadAllBytes($resource.Path)) -or
                @($membership.value | Where-Object { [int]$_.componenttype -eq $target.WebResourceObjectTypeCode }).Count -ne 1) {
                throw "Continuation resource content or Solution membership differs: $($resource.Name)"
            }
            $entry[0].State = 'GET_RECONCILED'
            $entry[0].WebResourceId = $resourceId
            $createdIdsForJournal = @($script:Journal.ResourceIds)
            if ($resourceId -notin $createdIdsForJournal) {
                $script:Journal.ResourceIds = @($createdIdsForJournal) + $resourceId
            }
        }
        Save-Journal
        Assert-UnpublishedSiteMap -ExpectedXml $proposed.Xml
        $script:Journal.SiteMapPatch = 'GET_RECONCILED_DRAFT'
        Save-Journal
    }

    if (-not $Continue) {
      $parent = Split-Path -Parent $EvidencePath
      if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
          throw 'Candidate Console evidence parent directory must already exist.'
      }
      $journalStream = [IO.File]::Open($EvidencePath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
      $journalStream.Dispose()
      $script:Journal = [ordered]@{
        Result = 'DISPATCHING'
        Environment = $target.EnvironmentName
        AppUniqueName = $target.AppUniqueName
        SolutionUniqueName = $target.SolutionUniqueName
        Dispatches = [System.Collections.Generic.List[object]]::new()
        ResourceIds = @()
        SiteMapPatch = 'NOT_DISPATCHED'
        PublishXml = 'NOT_DISPATCHED'
        RequestCounts = $script:Counts
        AutomaticRetries = 0
      }
      foreach ($resource in $resources) {
        $script:Journal.Dispatches.Add([ordered]@{
            Name = $resource.Name
            State = 'PLANNED'
            HttpStatus = $null
            WebResourceId = $null
        })
      }
      $script:Journal.Dispatches.Add([ordered]@{
        Name = 'srapp sitemap + scoped PublishXml'
        State = 'PLANNED'
        HttpStatus = $null
        WebResourceId = $null
      })
      Save-Journal
    }

    $createdIds = [System.Collections.Generic.List[string]]::new()
    if ($Continue) {
        foreach ($id in @($script:Journal.ResourceIds)) {
            if ([string]$id -notmatch '^[0-9a-fA-F-]{36}$') { throw 'Journal contains an invalid existing web resource ID.' }
            $createdIds.Add([string]$id)
        }
    }
    foreach ($resource in $resources) {
        $entry = @($script:Journal.Dispatches | Where-Object Name -CEQ $resource.Name)[0]
        if ($entry.State -eq 'GET_RECONCILED') { continue }
        if ($Continue -and $resource.Name -ceq 'os_/bso/candidate-console.html') {
            $matches = @($existing.value | Where-Object name -CEQ $resource.Name)
            if ($matches.Count -ne 1 -or $entry.State -cne 'UNCERTAIN_OR_REJECTED') {
                throw 'Only the exact previously accepted HTML resource may be reconciled in continuation.'
            }
            $existingId = [string]$matches[0].webresourceid
            $bytes = [IO.File]::ReadAllBytes($resource.Path)
            $readback = Get-DataverseJson -Path "$($target.WebResourceEntitySet)($existingId)?%24select=webresourceid,name,displayname,webresourcetype,content"
            $membership = Get-DataverseJson -Path "solutioncomponents?%24select=objectid,componenttype&%24filter=_solutionid_value eq $($solutionRows.value[0].solutionid) and objectid eq $existingId"
            if ([string]$readback.name -cne $resource.Name -or
                [string]$readback.displayname -cne $resource.DisplayName -or
                [int]$readback.webresourcetype -ne $resource.Type -or
                [string]$readback.content -cne [Convert]::ToBase64String($bytes) -or
                @($membership.value | Where-Object { [int]$_.componenttype -eq $target.WebResourceObjectTypeCode }).Count -ne 1) {
                throw 'Previously accepted HTML web resource does not reconcile exactly.'
            }
            $entry.State = 'GET_RECONCILED'
            $entry.HttpStatus = 204
            $entry.WebResourceId = $existingId
            $createdIds.Add($existingId)
            $script:Journal.ResourceIds = @($createdIds)
            Save-Journal
            continue
        }
        if ($entry.State -cne 'PLANNED') { throw 'Candidate Console web resource dispatch is not fresh.' }
        $entry.State = 'DISPATCH_RESERVED'
        Save-Journal
        $bytes = [IO.File]::ReadAllBytes($resource.Path)
        $payload = [ordered]@{
            name = $resource.Name
            displayname = $resource.DisplayName
            description = 'VN LMV IT DEV Candidate Management console. Business writes use os_sr_cact.'
            webresourcetype = $resource.Type
            content = [Convert]::ToBase64String($bytes)
        }
        $response = Invoke-DataverseRequest -Method POST -Path $target.WebResourceEntitySet `
            -Body $payload -WithSolutionHeader
        if ([int]$response.StatusCode -notin @(201, 204)) {
            $entry.State = 'UNCERTAIN_OR_REJECTED'
            $entry.HttpStatus = [int]$response.StatusCode
            Save-Journal
            throw "Candidate Console resource create failed or is uncertain: $($resource.Name)"
        }
        $created = if ([string]::IsNullOrWhiteSpace([string]$response.Content)) { $null } else {
            $response.Content | ConvertFrom-Json
        }
        $resourceId = if ($created -and $created.webresourceid) { [string]$created.webresourceid } else { $null }
        if (-not $resourceId) {
            $createdRows = Get-DataverseJson -Path "$($target.WebResourceEntitySet)?%24select=webresourceid,name&%24filter=name eq '$($resource.Name)'"
            if (@($createdRows.value).Count -eq 1) {
                $resourceId = [string]$createdRows.value[0].webresourceid
            }
        }
        if ($resourceId -notmatch '^[0-9a-fA-F-]{36}$') {
            $entry.State = 'UNCERTAIN_OR_REJECTED'
            $entry.HttpStatus = [int]$response.StatusCode
            Save-Journal
            throw "Candidate Console create returned no valid resource identity: $($resource.Name)"
        }
        $entry.State = 'CREATE_ACCEPTED'
        $entry.HttpStatus = [int]$response.StatusCode
        $entry.WebResourceId = $resourceId
        $createdIds.Add($resourceId)
        $script:Journal.ResourceIds = @($createdIds)
        Save-Journal
        $readback = Get-DataverseJson -Path "$($target.WebResourceEntitySet)($resourceId)?%24select=webresourceid,name,displayname,webresourcetype,content"
        $membership = Get-DataverseJson -Path "solutioncomponents?%24select=objectid,componenttype&%24filter=_solutionid_value eq $($solutionRows.value[0].solutionid) and objectid eq $resourceId"
        $expectedContent = [Convert]::ToBase64String($bytes)
        if ([string]$readback.name -cne $resource.Name -or
            [string]$readback.displayname -cne $resource.DisplayName -or
            [int]$readback.webresourcetype -ne $resource.Type -or
            [string]$readback.content -cne $expectedContent -or
            @($membership.value | Where-Object { [int]$_.componenttype -eq $target.WebResourceObjectTypeCode }).Count -ne 1) {
            $entry.State = 'RECONCILIATION_FAILED'
            Save-Journal
            throw "Candidate Console web resource or Solution membership did not reconcile: $($resource.Name)"
        }
        $entry.State = 'GET_RECONCILED'
        Save-Journal
    }

    $lastEntry = @($script:Journal.Dispatches | Where-Object Name -CEQ 'srapp sitemap + scoped PublishXml')[0]
    if (-not $Continue) {
      $lastEntry.State = 'DISPATCH_RESERVED'
      $script:Journal.SiteMapPatch = 'DISPATCH_RESERVED'
      Save-Journal
      $patch = Invoke-DataverseRequest -Method PATCH -Path "sitemaps($($target.SiteMapId))" `
          -Body ([ordered]@{ sitemapxml = $proposed.Xml }) -ETag $etag
      if ([int]$patch.StatusCode -lt 200 -or [int]$patch.StatusCode -ge 300) {
        $script:Journal.SiteMapPatch = "REJECTED_OR_UNCERTAIN:$($patch.StatusCode)"
        Save-Journal
        throw 'Candidate Management sitemap update failed or is uncertain; stop without retry.'
      }
      $script:Journal.SiteMapPatch = "ACCEPTED:$($patch.StatusCode)"
      Save-Journal
      Assert-UnpublishedSiteMap -ExpectedXml $proposed.Xml
      $script:Journal.SiteMapPatch = 'GET_RECONCILED_DRAFT'
      Save-Journal
    }

    $webresourceXml = [System.Text.StringBuilder]::new()
    [void]$webresourceXml.Append('<webresources>')
    foreach ($resourceId in $createdIds) {
        [void]$webresourceXml.Append("<webresource>$resourceId</webresource>")
    }
    [void]$webresourceXml.Append('</webresources>')
    $parameterXml = "<importexportxml>$($webresourceXml.ToString())<appmodules><appmodule>$($target.AppId)</appmodule></appmodules></importexportxml>"
    $script:Journal.PublishXml = 'DISPATCH_RESERVED'
    Save-Journal
    $publish = Invoke-DataverseRequest -Method POST -Path 'PublishXml' `
        -Body ([ordered]@{ ParameterXml = $parameterXml })
    if ([int]$publish.StatusCode -lt 200 -or [int]$publish.StatusCode -ge 300) {
        $script:Journal.PublishXml = "REJECTED_OR_UNCERTAIN:$($publish.StatusCode)"
        Save-Journal
        throw 'Scoped srapp/webresource PublishXml failed or is uncertain; stop without retry.'
    }
    $script:Journal.PublishXml = "ACCEPTED:$($publish.StatusCode)"
    Save-Journal
    $publishedSiteMap = Get-DataverseJson -Path "sitemaps($($target.SiteMapId))?%24select=sitemapnameunique,sitemapxml,componentstate"
    if ([string]$publishedSiteMap.sitemapxml -cne $proposed.Xml -or
        [string]$publishedSiteMap.sitemapnameunique -cne $target.SiteMapUniqueName) {
        $script:Journal.Result = 'PUBLISH_ACCEPTED_RECONCILIATION_FAILED'
        Save-Journal
        throw 'Scoped publication returned success but the srapp sitemap readback differs.'
    }
    $lastEntry.State = 'GET_RECONCILED'
    $lastEntry.HttpStatus = [int]$publish.StatusCode
    $script:Journal.Result = 'CANDIDATE_CONSOLE_SCOPED_PUBLISH_RECONCILED'
    $script:Journal.RequestCounts = $script:Counts
    Save-Journal
    [ordered]@{
        Result = [string]$script:Journal.Result
        Environment = $target.EnvironmentName
        AppUniqueName = $target.AppUniqueName
        NavigationTitle = 'Candidate Management'
        WebResourceNames = @($resources | ForEach-Object Name)
        WebResourceCount = $createdIds.Count
        SiteMapPatchCount = $script:Counts.PATCH
        PublishXmlCount = 1
        PublishXmlIncludesOnlyTargetAppAndThreeWebResources = $true
        PublishAllXml = 0
        AutomaticRetries = 0
        RequestCounts = $script:Counts
        EvidencePath = $EvidencePath
    } | ConvertTo-Json -Depth 8
}
finally {
    $script:AccessToken = $null
}
