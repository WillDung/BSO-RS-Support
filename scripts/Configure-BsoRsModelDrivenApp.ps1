#requires -Version 7.4
[CmdletBinding()]
param(
    [switch]$PlanOnly,
    [switch]$DryRun,
    [switch]$Apply,
    [switch]$SiteMapAssociationOnly,
    [switch]$ReferenceUiCompositionOnly,
    [switch]$EntityIdentityDiagnosticOnly,
    [switch]$EntityRootRepairDiagnosticOnly,
    [switch]$RemoveWrongSystemEntityRoots,
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
        [pscustomobject]@{ LogicalName = 'os_sr_ta'; Title = 'TA Directory'; NodeId = 'subarea_9787e9c1'; FormName = 'Information'; ViewName = 'Active TA Directories' }
        [pscustomobject]@{ LogicalName = 'os_sr_pos'; Title = 'Positions'; NodeId = 'subarea_02d1f8a7'; FormName = 'Information'; ViewName = 'Active Positions' }
        [pscustomobject]@{ LogicalName = 'os_sr_csrc'; Title = 'Candidate Sources'; NodeId = 'subarea_03c7b614'; FormName = 'Information'; ViewName = 'Active Candidate Sources' }
        [pscustomobject]@{ LogicalName = 'os_sr_loc'; Title = 'Locations'; NodeId = 'subarea_04e9c321'; FormName = 'Information'; ViewName = 'Active Locations' }
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
$script:ApprovedReferenceUiPayloadFingerprint = 'ac66583cc589e1da351cf95025e3a902d8aa54484e9e68f1ba10ee6569269a50'
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
$script:LastRequestId = $null
$script:LastCorrelationId = $null
$script:LastStage = 'Startup'
$script:ExpectedUserGuardNeedsPin = $false
$script:EntityResolutionDiagnostics = @()
$script:EntityResolutionClassification = 'NOT_RUN'
$script:RetrieveAppComponentsEvidence = $null
$script:EntityRootRepairEvidence = $null
$script:FirstFailingPredicate = $null
$script:IdentityContractFailurePredicate = $null
$script:PayloadFingerprintDiagnostic = $null
$script:SystemEntityIdForRemoval = $null
$script:CurrentRawAppComponents = @()
$script:RemovalDispatchResult = $null

if (($PlanOnly -and ($DryRun -or $Apply -or $SiteMapAssociationOnly)) -or
    ($DryRun -and $Apply) -or
    ($SiteMapAssociationOnly -and $ReferenceUiCompositionOnly) -or
    (($EntityIdentityDiagnosticOnly -or $EntityRootRepairDiagnosticOnly -or $RemoveWrongSystemEntityRoots) -and
        ($PlanOnly -or $DryRun -or $Apply -or $SiteMapAssociationOnly -or $ReferenceUiCompositionOnly -or
            ($EntityIdentityDiagnosticOnly -and $EntityRootRepairDiagnosticOnly) -or
            ($RemoveWrongSystemEntityRoots -and ($EntityIdentityDiagnosticOnly -or $EntityRootRepairDiagnosticOnly)))) -or
    ($SiteMapAssociationOnly -and -not ($DryRun -or $Apply))) {
    throw 'Choose exactly one supported execution mode.'
}
if (-not $PlanOnly -and -not $DryRun -and -not $Apply -and
    -not $EntityIdentityDiagnosticOnly -and -not $EntityRootRepairDiagnosticOnly -and
    -not $RemoveWrongSystemEntityRoots) { $PlanOnly = $true }

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

function Assert-ReferenceUiPayloadFingerprint {
    param(
        [Parameter(Mandatory = $true)][object[]]$Payload,
        [string]$ExpectedFingerprint = $script:ApprovedReferenceUiPayloadFingerprint
    )
    $actualFingerprint = Get-PayloadFingerprint -Payload $Payload
    if ($actualFingerprint -cne $ExpectedFingerprint) {
        throw 'Reference UI component payload fingerprint differs from the explicitly approved set.'
    }
    $actualFingerprint
}

function Get-PayloadFingerprint {
    param([Parameter(Mandatory = $true)][object[]]$Payload)
    $json = ConvertTo-Json -InputObject @($Payload) -Depth 10 -Compress
    [Convert]::ToHexString(
        [System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes($json))
    ).ToLowerInvariant()
}

function Assert-ApplyAuthorization {
    param([string]$Phrase, [string]$Reference)
    $expectedPhrase = if ($SiteMapAssociationOnly) {
        'APPLY PHASE 2D.2 IN VN LMV IT'
    }
    elseif ($ReferenceUiCompositionOnly) {
        'APPLY PHASE 2D.3 IN VN LMV IT'
    }
    else {
        'APPLY PHASE 2D IN VN LMV IT'
    }
    if ($Phrase -cne $expectedPhrase -or [string]::IsNullOrWhiteSpace($Reference)) {
        throw 'Apply requires the exact phase-specific confirmation phrase and a recorded authorization reference; no request was sent.'
    }
}

function Get-SiteMapComponentPayload {
    param([string]$SiteMapId = $script:Target.SiteMapId)
    [ordered]@{
        sitemapid = $SiteMapId
        '@odata.type' = 'Microsoft.Dynamics.CRM.sitemap'
    }
}

function Assert-SiteMapAssociationPayload {
    param(
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Body,
        [object]$Target = $script:Target
    )
    $expectedKeys = @('AppId', 'Components')
    $actualBodyKeys = @($Body.Keys | Sort-Object)
    $sortedExpectedKeys = @($expectedKeys | Sort-Object)
    if ([string]$Body['AppId'] -cne $Target.AppModuleId -or
        ($actualBodyKeys -join ',') -cne ($sortedExpectedKeys -join ',')) {
        throw 'Site Map AddAppComponents request must contain only the fixed AppId and Components fields.'
    }
    $components = @($Body['Components'])
    if ($components.Count -ne 1) { throw 'Site Map association must contain exactly one component.' }
    $component = $components[0]
    $keys = @($component.Keys | ForEach-Object { [string]$_ } | Sort-Object)
    if (($keys -join ',') -cne '@odata.type,sitemapid' -or
        [string]$component['@odata.type'] -cne 'Microsoft.Dynamics.CRM.sitemap' -or
        ([string]$component['sitemapid']).Trim('{}') -ine ([string]$Target.SiteMapId).Trim('{}')) {
        throw 'Site Map association payload differs from the single verified existing Site Map.'
    }
}

function Get-SiteMapValidationState {
    param([object]$AppValidation)
    $matchingErrors = @($AppValidation.Issues | Where-Object {
        $_.ErrorType -ceq 'Error' -and $_.Message -ceq 'App does not contain Site Map'
    })
    [pscustomobject]@{
        SiteMapErrorPresent = ($matchingErrors.Count -eq 1)
        SiteMapErrorCount = $matchingErrors.Count
        OtherBlockingErrorCount = @($AppValidation.Issues | Where-Object {
            $_.ErrorType -ceq 'Error' -and $_.Message -cne 'App does not contain Site Map'
        }).Count
    }
}

function Get-ReferenceUiValidationState {
    param([object]$AppValidation)
    $issues = @($AppValidation.Issues)
    $validationFailed = $AppValidation.PSObject.Properties['ValidationSuccess'] -and
        $AppValidation.ValidationSuccess -eq $false
    $unresolvedRequiredComponents = @($issues | ForEach-Object {
        @(Get-PropertyValue -Object $_ -Name 'RequiredComponents' | Where-Object {
            (Get-PropertyValue -Object $_ -Name 'ResolutionStatus') -cne 'SATISFIED'
        })
    }).Count
    [pscustomobject]@{
        ValidationSuccess = if ($AppValidation.PSObject.Properties['ValidationSuccess']) { $AppValidation.ValidationSuccess } else { $null }
        SiteMapErrorCount = @($issues | Where-Object {
            $_.ErrorType -ceq 'Error' -and $_.Message -ceq 'App does not contain Site Map'
        }).Count
        EntityReferenceWarningCount = @($issues | Where-Object {
            $_.Message -ceq 'App does not reference at least one entity'
        }).Count
        BlockingErrorCount = @($issues | Where-Object { $_.ErrorType -ceq 'Error' }).Count + [int]$validationFailed
        UnresolvedRequiredComponentCount = $unresolvedRequiredComponents
        WarningCount = @($issues | Where-Object { $_.ErrorType -ceq 'Warning' }).Count
        FormViewSelectionWarningCount = @($issues | Where-Object {
            (Get-PropertyValue -Object $_ -Name 'Classification') -ceq 'NON_BLOCKING_FUNCTIONAL_WARNING'
        }).Count
        Issues = $issues
    }
}

function Assert-ApprovedAppRoles {
    param([object[]]$Roles)
    $expectedNames = @('System Administrator', 'System Customizer')
    $actualNames = @($Roles | ForEach-Object { [string]$_.Name } | Sort-Object)
    if ($actualNames.Count -ne $expectedNames.Count -or
        ($actualNames -join '|') -cne (($expectedNames | Sort-Object) -join '|')) {
        throw 'App role associations differ from the approved System Administrator and System Customizer set.'
    }
}

function Get-ReferenceUiComponentPayloads {
    if ($script:ResolvedReferenceComponents.Count -ne 4) {
        throw 'Reference UI composition requires exactly four freshly resolved reference tables.'
    }
    $payloads = @($script:ResolvedReferenceComponents | ForEach-Object { $_.Payloads })
    if ($payloads.Count -ne 12) { throw 'Reference UI composition requires exactly twelve resolved table/form/view components.' }
    $payloads
}

function Assert-ReferenceUiCompositionPayload {
    param(
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Body,
        [object]$Target = $script:Target
    )
    if ([string]$Body['AppId'] -cne $Target.AppModuleId -or
        @($Body.Keys).Count -ne 2 -or 'Components' -notin @($Body.Keys)) {
        throw 'Reference UI AddAppComponents payload does not match the fixed AppId/Components contract.'
    }
    $expected = @(Get-ReferenceUiComponentPayloads)
    $actual = @($Body['Components'])
    if ($actual.Count -ne 12) { throw 'Reference UI AddAppComponents must contain exactly twelve components.' }
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    for ($index = 0; $index -lt $expected.Count; $index++) {
        $item = $actual[$index]
        $expectedItem = $expected[$index]
        $keys = @($item.Keys | ForEach-Object { [string]$_ } | Sort-Object)
        if (($keys -join ',') -cne (($expectedItem.Keys | ForEach-Object { [string]$_ } | Sort-Object) -join ',')) {
            throw 'Reference UI component contains an unexpected property.'
        }
        foreach ($key in $expectedItem.Keys) {
            if ([string]$item[$key] -cne [string]$expectedItem[$key]) {
                throw 'Reference UI component identity/type differs from the freshly resolved approved set.'
            }
        }
        $componentKey = [string](@($item.Keys | Where-Object { $_ -ne '@odata.type' } | ForEach-Object { $item[$_] })[0])
        if (-not $seen.Add($componentKey)) { throw 'Reference UI AddAppComponents contains a duplicate component.' }
        if ([string]$item['@odata.type'] -notin @(
            'Microsoft.Dynamics.CRM.entity',
            'Microsoft.Dynamics.CRM.systemform',
            'Microsoft.Dynamics.CRM.savedquery'
        )) {
            throw 'Reference UI AddAppComponents contains a component type outside the approved table/form/view set.'
        }
    }
}

function Assert-ReferenceUiComponentState {
    param(
        [object[]]$Components,
        [switch]$RequireComposed
    )
    $expected = @(Get-ExpectedComponentKeys)
    if ($expected.Count -ne 12) { throw 'Resolved reference component set is not exactly twelve.' }
    $siteMaps = @($Components | Where-Object { [int]$_.ComponentType -eq 62 })
    $expectedSiteMaps = @($siteMaps | Where-Object {
        ([string]$_.ObjectId).Trim('{}') -ieq $script:Target.SiteMapId
    })
    if ($siteMaps.Count -ne 1 -or $expectedSiteMaps.Count -ne 1) {
        throw 'Direct AppModule inventory must contain exactly the existing Site Map component.'
    }
    $referenceTables = @($script:ResolvedReferenceComponents)
    if ($referenceTables.Count -ne 4 -or
        @($referenceTables.LogicalName | Select-Object -Unique).Count -ne 4) {
        throw 'Resolved reference table logical names are missing or duplicated.'
    }
    $entityComponents = @($Components | Where-Object { [int]$_.ComponentType -eq 1 })
    $forms = @($Components | Where-Object { [int]$_.ComponentType -eq 60 })
    $views = @($Components | Where-Object { [int]$_.ComponentType -eq 26 })
    $matchedTables = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($component in $entityComponents) {
        $logicalName = [string]$component.EntityLogicalName
        if ([string]::IsNullOrWhiteSpace($logicalName) -or
            $logicalName -notin @($referenceTables | ForEach-Object { [string]$_.LogicalName })) {
            throw 'Entity component did not resolve to an approved table logical name.'
        }
        if (-not $matchedTables.Add($logicalName)) {
            throw 'Duplicate entity component logical name exists.'
        }
    }
    if ($matchedTables.Count -ne 4 -or $entityComponents.Count -ne 4) {
        throw 'Entity components do not resolve exactly once to all four approved table logical names.'
    }
    foreach ($reference in $referenceTables) {
        $formId = ConvertTo-NormalizedGuid -Value ([string]$reference.MainForm.Id)
        $viewId = ConvertTo-NormalizedGuid -Value ([string]$reference.ActiveView.Id)
        $formMatches = @($forms | Where-Object {
            (ConvertTo-NormalizedGuid -Value ([string]$_.ObjectId)) -ceq $formId -and
            $_.ParentLogicalName -ceq $reference.LogicalName
        })
        $viewMatches = @($views | Where-Object {
            (ConvertTo-NormalizedGuid -Value ([string]$_.ObjectId)) -ceq $viewId -and
            $_.ParentLogicalName -ceq $reference.LogicalName
        })
        if ($formMatches.Count -ne 1 -or $viewMatches.Count -ne 1) {
            throw 'AppModule form/view components do not match the approved IDs and parent table identities.'
        }
    }
    if ($forms.Count -ne 4 -or $views.Count -ne 4 -or
        $Components.Count -ne 13 -or @($Components | Where-Object { [int]$_.ComponentType -notin @(1, 26, 60, 62) }).Count -ne 0) {
        throw 'Direct AppModule inventory contains a missing or unintended component.'
    }
    [pscustomobject]@{
        SiteMapCount = 1
        TableCount = $entityComponents.Count
        MainFormCount = $forms.Count
        PublicViewCount = $views.Count
        ReferenceComponentCount = $entityComponents.Count + $forms.Count + $views.Count
        TotalComponentCount = $Components.Count
        Composed = $true
    }
}

function Assert-ReferenceUiWriteSequence {
    param([ValidateSet('POST', 'PATCH')][string]$Method)
    if ($Method -eq 'POST') {
        throw 'Phase 2D.3D forbids AddAppComponents and all POST operations.'
    }
    if ($script:RequestCounts.POST -ne 0 -or $script:RequestCounts.PATCH -ne 0 -or
        $script:WriteResults.Count -ne 0) {
        throw 'Phase 2D.3D permits one Site Map PATCH only, with no prior writes.'
    }
}

function Get-SiteMapSemanticNavigation {
    param([Parameter(Mandatory = $true)][string]$SiteMapXml)
    $settings = [System.Xml.XmlReaderSettings]::new()
    $settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver = $null
    $stringReader = [System.IO.StringReader]::new($SiteMapXml)
    $xmlReader = [System.Xml.XmlReader]::Create($stringReader, $settings)
    $document = [System.Xml.XmlDocument]::new()
    $document.XmlResolver = $null
    try { $document.Load($xmlReader) }
    finally { $xmlReader.Dispose(); $stringReader.Dispose() }
    $areas = @($document.DocumentElement.SelectNodes("./*[local-name()='Area']"))
    $navigation = foreach ($area in $areas) {
        $groups = @($area.SelectNodes("./*[local-name()='Group']"))
        foreach ($group in $groups) {
            foreach ($subarea in @($group.SelectNodes("./*[local-name()='SubArea']"))) {
                [pscustomobject]@{
                    AreaId = $area.GetAttribute('Id')
                    AreaTitle = [string]$area.SelectSingleNode("./*[local-name()='Titles']/*[local-name()='Title'][@LCID='1033']").GetAttribute('Title')
                    GroupId = $group.GetAttribute('Id')
                    GroupTitle = [string]$group.SelectSingleNode("./*[local-name()='Titles']/*[local-name()='Title'][@LCID='1033']").GetAttribute('Title')
                    SubAreaId = $subarea.GetAttribute('Id')
                    Title = [string]$subarea.SelectSingleNode("./*[local-name()='Titles']/*[local-name()='Title'][@LCID='1033']").GetAttribute('Title')
                    Entity = $subarea.GetAttribute('Entity')
                }
            }
        }
    }
    @($navigation)
}

function Assert-SiteMapSemanticNodePreservation {
    param(
        [object[]]$Before,
        [object[]]$After
    )
    $beforeIds = @($Before | ForEach-Object { "$($_.AreaId)|$($_.GroupId)|$($_.SubAreaId)" } | Select-Object -Unique)
    $afterIds = @($After | ForEach-Object { "$($_.AreaId)|$($_.GroupId)|$($_.SubAreaId)" } | Select-Object -Unique)
    if ($beforeIds.Count -eq 0 -or @($beforeIds | Where-Object { $_ -notin $afterIds }).Count -gt 0) {
        throw 'Site Map semantic delta removes or fails to preserve an existing Area, Group, or SubArea identity.'
    }
}

function Assert-SiteMapHasNoDuplicateNavigationIds {
    param([Parameter(Mandatory = $true)][string]$SiteMapXml)
    $settings = [System.Xml.XmlReaderSettings]::new()
    $settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver = $null
    $stringReader = [System.IO.StringReader]::new($SiteMapXml)
    $xmlReader = [System.Xml.XmlReader]::Create($stringReader, $settings)
    $document = [System.Xml.XmlDocument]::new()
    $document.XmlResolver = $null
    try { $document.Load($xmlReader) }
    finally { $xmlReader.Dispose(); $stringReader.Dispose() }
    $allIds = [System.Collections.Generic.List[string]]::new()
    foreach ($nodeName in @('Area', 'Group', 'SubArea')) {
        $ids = @($document.SelectNodes("//*[local-name()='$nodeName']") | ForEach-Object { $_.GetAttribute('Id') } | Where-Object { $_ })
        if (@($ids | Select-Object -Unique).Count -ne $ids.Count) {
            throw "Site Map contains duplicate $nodeName IDs."
        }
        foreach ($id in $ids) { $allIds.Add([string]$id) }
    }
    if (@($allIds | Select-Object -Unique).Count -ne $allIds.Count) { throw 'Site Map contains duplicate navigation IDs across node types.' }
}

function Get-SiteMapDirectComponentState {
    param([object[]]$Components)
    $siteMapComponents = @($Components | Where-Object { [int]$_.ComponentType -eq 62 })
    $expected = @($siteMapComponents | Where-Object {
        ([string]$_.ObjectId).Trim('{}') -ieq $script:Target.SiteMapId
    })
    $otherComponents = @($Components | Where-Object {
        [int]$_.ComponentType -ne 62 -or ([string]$_.ObjectId).Trim('{}') -ine $script:Target.SiteMapId
    })
    if ($siteMapComponents.Count -gt 1 -or $expected.Count -gt 1) {
        throw 'Unexpected or duplicate Site Map AppModule components exist; stop without writing.'
    }
    [pscustomobject]@{
        SiteMapPresent = ($expected.Count -eq 1)
        SiteMapCount = $expected.Count
        OtherComponentCount = $otherComponents.Count
        Components = @($Components)
    }
}

function Assert-SiteMapOnlyComponentSet {
    param([object[]]$Components)
    $state = Get-SiteMapDirectComponentState -Components $Components
    if ($state.OtherComponentCount -ne 0) {
        throw 'Unexpected non-Site Map AppModule component exists; stop without adding or changing components.'
    }
    $state
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
            AssociationEvidence = if ($ReferenceUiCompositionOnly) {
                'Phase 2D.2 verified the direct Site Map component on srapp; Phase 2D.3 preserves it.'
            }
            else {
                'Target Solution export contains one AppModuleSiteMap entry with SiteMapUniqueName=srapp; live Site Map unique name is srapp.'
            }
            StandardAppModuleComponentRowObserved = [bool]$ReferenceUiCompositionOnly
            AddSiteMapComponent = $false
        }
        ProposedNavigation = [ordered]@{
            Area = $script:Target.NavigationAreaTitle
            Group = $script:Target.NavigationGroupTitle
            SubAreas = @($script:Target.NavigationSubareas | ForEach-Object {
                [ordered]@{ Title = $_.Title; EntityLogicalName = $_.LogicalName; NodeId = $_.NodeId; MainForm = $_.FormName; PublicView = $_.ViewName }
            })
            PreserveExistingNodeIds = $true
        }
        AddAppComponentsPayload = [ordered]@{
            AppId = if ($resolved) { $script:Target.AppModuleId } else { '[resolved and guarded during live preflight]' }
            Components = $components
            ExactLiveIdsResolved = $resolved
        }
        OrderedWriteOperations = if ($ReferenceUiCompositionOnly) {
            @(
                [ordered]@{
                    Order = 1
                    Method = 'POST'
                    Target = 'AddAppComponents'
                    ComponentTypes = @(1, 60, 26)
                    ComponentCount = 12
                    Purpose = 'Add exactly the freshly verified four tables, four Main forms, and four public views to the existing srapp.'
                    MayPublish = $false
                }
                [ordered]@{
                    Order = 2
                    Method = 'PATCH'
                    Target = "sitemaps($($script:Target.SiteMapId))"
                    Field = 'sitemapxml'
                    Purpose = 'After exact component reconciliation and intermediate ValidateApp, update only the existing Site Map using If-Match.'
                    MayPublish = $false
                }
            )
        }
        else {
            @(
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
        }
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
    Assert-SiteMapHasNoDuplicateNavigationIds -SiteMapXml $document.OuterXml
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
    $proposedXml = $document.OuterXml
    Assert-SiteMapHasNoDuplicateNavigationIds -SiteMapXml $proposedXml
    $proposedXml
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

function Test-AllowsProcessExpectedUserPin {
    [bool]($SiteMapAssociationOnly -or $ReferenceUiCompositionOnly -or $EntityIdentityDiagnosticOnly -or
        $EntityRootRepairDiagnosticOnly -or $RemoveWrongSystemEntityRoots)
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
    if ([string]::IsNullOrWhiteSpace($expectedUserId) -and (Test-AllowsProcessExpectedUserPin)) {
        $script:ExpectedUserGuardNeedsPin = $true
    }
    elseif (-not [guid]::TryParse($expectedUserId, [ref]$expectedUserGuid) -or
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

function Get-SanitizedResponseGuidHeader {
    param([object]$Headers, [string[]]$Names)
    if ($null -eq $Headers) { return $null }
    foreach ($name in $Names) {
        $value = $null
        if ($Headers -is [System.Collections.IDictionary]) {
            $headerKey = @($Headers.Keys | Where-Object { [string]$_ -ieq $name } | Select-Object -First 1)
            if ($headerKey.Count -eq 1) { $value = [string]$Headers[$headerKey[0]] }
        }
        elseif ($Headers -is [System.Net.WebHeaderCollection]) {
            $value = [string]$Headers[$name]
        }
        $parsed = [guid]::Empty
        if ([guid]::TryParse($value, [ref]$parsed)) { return $parsed.ToString('D').ToLowerInvariant() }
    }
    $null
}

function Invoke-DataverseRequest {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('GET', 'PATCH', 'POST')][string]$Method,
        [Parameter(Mandatory = $true)][string]$Path,
        [object]$Body,
        [string]$ETag
    )
    if ($Method -ne 'GET' -and
        (-not ($Apply -or $RemoveWrongSystemEntityRoots) -or -not $script:WritesAllowed)) {
        throw 'Write blocked; explicit Apply authorization gate is required.'
    }
    $uri = [Uri]::new([Uri]$script:ApiRoot, $Path)
    if ($uri.Scheme -cne 'https' -or $uri.Authority -ine ([Uri]$OrganizationUrl).Authority -or
        $uri.AbsolutePath -notmatch '^/api/data/v9\.2/' -or $uri.UserInfo -or $uri.Fragment) {
        throw 'Dataverse request path is outside the verified organization origin.'
    }
    $resource = [Uri]::UnescapeDataString($uri.AbsolutePath.Substring('/api/data/v9.2/'.Length))
    if ($Method -eq 'GET' -and $resource -notmatch '^(WhoAmI$|appmodules(\(|$)|appmodulecomponents$|entities$|sitemaps(\(|$)|sitemaps/Microsoft\.Dynamics\.CRM\.RetrieveUnpublishedMultiple\(|solutions$|publishers\(|solutioncomponents$|EntityDefinitions\(|systemforms(\(|$)|savedqueries(\(|$)|roles\(|RetrieveRequiredComponents\(|RetrieveAppComponents\(|ValidateApp\()') {
        throw 'GET blocked: endpoint is outside the app and component metadata allowlist.'
    }
    if ($Method -eq 'PATCH' -and ($resource -cne "sitemaps($($script:Target.SiteMapId))" -or
        @($Body.Keys) -ne @('sitemapxml'))) {
        throw 'PATCH blocked: only the sitemapxml field on the existing target Site Map is allowed.'
    }
    if ($ReferenceUiCompositionOnly -and $Method -in @('POST', 'PATCH')) {
        Assert-ReferenceUiWriteSequence -Method $Method
    }
    if ($Method -eq 'POST' -and $RemoveWrongSystemEntityRoots) {
        if ($resource -cne 'RemoveAppComponents' -or $script:RequestCounts.POST -ne 0 -or
            $script:RequestCounts.PATCH -ne 0 -or $script:WriteResults.Count -ne 0) {
            throw 'Only one RemoveAppComponents POST is permitted in this mode; all other writes are blocked.'
        }
        Assert-RemoveWrongSystemEntityPayload -Body $Body -AppId $script:Target.AppModuleId `
            -SystemEntityId $script:SystemEntityIdForRemoval
    }
    elseif ($Method -eq 'POST' -and $resource -cne 'AddAppComponents') {
        throw 'POST blocked: only AddAppComponents is allowed; no create, publish, or role endpoint is allowed.'
    }
    if ($Method -eq 'POST' -and -not $RemoveWrongSystemEntityRoots) {
        if ($SiteMapAssociationOnly) { Assert-SiteMapAssociationPayload -Body $Body }
        elseif ($ReferenceUiCompositionOnly) { Assert-ReferenceUiCompositionPayload -Body $Body }
        else { Assert-AppComponentsPayload -Body $Body }
    }
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
        ResponseHeadersVariable = 'responseHeaders'
        TimeoutSec = 90
        MaximumRetryCount = 0
        ErrorAction = 'Stop'
    }
    if ($null -ne $Body) {
        $request.ContentType = 'application/json; charset=utf-8'
        $request.Body = ConvertTo-Json -InputObject $Body -Depth 30 -Compress
    }
    $responseStatusCode = 0
    $responseHeaders = $null
    $script:LastHttpStatus = $null
    $script:LastErrorCode = $null
    $script:LastSafeError = $null
    $script:LastRequestId = $null
    $script:LastCorrelationId = $null
    $script:RequestCounts[$Method]++
    $script:LastPath = $resource
    if ($Method -ne 'GET') { $script:WritesStarted = $true }
    try {
        $response = Invoke-RestMethod @request
        $script:LastRequestId = Get-SanitizedResponseGuidHeader -Headers $responseHeaders `
            -Names @('x-ms-service-request-id', 'req_id', 'x-ms-request-id')
        $script:LastCorrelationId = Get-SanitizedResponseGuidHeader -Headers $responseHeaders `
            -Names @('x-ms-correlation-request-id', 'correlationid', 'x-ms-correlation-id')
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
        $script:LastRequestId = Get-SanitizedResponseGuidHeader -Headers $responseHeaders `
            -Names @('x-ms-service-request-id', 'req_id', 'x-ms-request-id')
        $script:LastCorrelationId = Get-SanitizedResponseGuidHeader -Headers $responseHeaders `
            -Names @('x-ms-correlation-request-id', 'correlationid', 'x-ms-correlation-id')
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

        $script:LastStage = "Resolve approved $($navigation.FormName) Main form for $logicalName"
        $forms = @(Get-ODataRows -Path (New-CollectionPath -EntitySet 'systemforms' -Select 'formid,name,objecttypecode,type,formactivationstate,componentstate,ismanaged,isdefault,publishedon' -Filter "objecttypecode eq '$logicalName' and name eq '$($navigation.FormName)' and type eq 2 and formactivationstate eq 1 and componentstate eq 0"))
        if ($forms.Count -ne 1) { throw "Reference table $logicalName does not have exactly one active, published $($navigation.FormName) Main form." }
        if ([string]$forms[0].name -cne [string]$navigation.FormName -or
            [string]$forms[0].objecttypecode -cne $logicalName -or [int]$forms[0].type -ne 2 -or
            [int]$forms[0].formactivationstate -ne 1 -or [int]$forms[0].componentstate -ne 0) {
            throw "Reference table $logicalName resolved Main form has invalid identity or state."
        }
        $formGuid = [guid]::Empty
        if (-not [guid]::TryParse([string]$forms[0].formid, [ref]$formGuid)) { throw "Reference table $logicalName resolved Main form ID is invalid." }

        $script:LastStage = "Resolve approved public active $($navigation.ViewName) view for $logicalName"
        $views = @(Get-ODataRows -Path (New-CollectionPath -EntitySet 'savedqueries' -Select 'savedqueryid,name,returnedtypecode,querytype,isprivate,statecode,componentstate,ismanaged,isdefault' -Filter "returnedtypecode eq '$logicalName' and name eq '$($navigation.ViewName)' and querytype eq 0 and isprivate eq false and statecode eq 0 and componentstate eq 0"))
        if ($views.Count -ne 1) { throw "Reference table $logicalName does not have exactly one public, active $($navigation.ViewName) view." }
        if ([string]$views[0].name -cne [string]$navigation.ViewName -or
            [string]$views[0].returnedtypecode -cne $logicalName -or [int]$views[0].querytype -ne 0 -or
            [bool]$views[0].isprivate -or [int]$views[0].statecode -ne 0 -or [int]$views[0].componentstate -ne 0) {
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

function Assert-SingleAppModuleSolutionRoot {
    param(
        [Parameter(Mandatory = $true)][object[]]$SolutionComponents,
        [Parameter(Mandatory = $true)][string]$AppModuleId
    )
    $appRoots = @($SolutionComponents | Where-Object { [int]$_.componenttype -eq 80 })
    $matchingRoots = @($appRoots | Where-Object { ([string]$_.objectid).Trim('{}') -ieq $AppModuleId.Trim('{}') })
    if ($appRoots.Count -ne 1 -or $matchingRoots.Count -ne 1) {
        throw 'The target Solution must contain exactly one AppModule root, matching the adopted srapp.'
    }
    $matchingRoots[0]
}

function Assert-ReferenceTableSolutionMembership {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$SolutionComponents,
        [Parameter(Mandatory = $true)][object[]]$ReferenceComponents
    )
    $membership = [System.Collections.Generic.List[object]]::new()
    foreach ($reference in $ReferenceComponents) {
        $matches = @($SolutionComponents | Where-Object {
            [int]$_.componenttype -eq 1 -and
            ([string]$_.objectid).Trim('{}') -ieq ([string]$reference.TableMetadataId).Trim('{}')
        })
        if ($matches.Count -ne 1) {
            throw "Reference table $($reference.LogicalName) lacks exactly one table Solution component."
        }
        $membership.Add([pscustomobject]@{
            LogicalName = $reference.LogicalName
            ComponentRole = 'Table'
            ComponentType = 1
            MatchCount = $matches.Count
        })
    }
    $membership.ToArray()
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

function ConvertTo-NormalizedGuid {
    param([Parameter(Mandatory = $true)][string]$Value)
    $parsed = [guid]::Empty
    if (-not [guid]::TryParse($Value.Trim('{}'), [ref]$parsed)) {
        throw 'A Dataverse component identity is not a valid GUID.'
    }
    $parsed.ToString('D').ToLowerInvariant()
}

function Assert-AppModuleEntityIdentityContract {
    param([Parameter(Mandatory = $true)][xml]$Metadata)
    $entitySet = $Metadata.SelectSingleNode("//*[local-name()='EntitySet' and @Name='entities']")
    $entityType = $Metadata.SelectSingleNode("//*[local-name()='EntityType' and @Name='entity']")
    if (-not $entitySet) {
        $script:IdentityContractFailurePredicate = 'ENTITIES_ENTITYSET_PRESENT'
        throw 'Dataverse metadata does not expose the expected entities entity set.'
    }
    if ($entitySet.GetAttribute('EntityType') -cne 'Microsoft.Dynamics.CRM.entity') {
        $script:IdentityContractFailurePredicate = 'ENTITIES_ENTITYSET_TYPE_IS_ENTITY'
        throw 'Dataverse metadata does not expose the expected entities entity set.'
    }
    if (-not $entityType) {
        $script:IdentityContractFailurePredicate = 'ENTITY_ENTITYTYPE_PRESENT'
        throw 'Dataverse metadata does not expose the expected entities entity set.'
    }
    $keys = @($entityType.SelectNodes("./*[local-name()='Key']/*[local-name()='PropertyRef']") |
        ForEach-Object { $_.GetAttribute('Name') })
    $properties = @($entityType.SelectNodes("./*[local-name()='Property']") |
        ForEach-Object { $_.GetAttribute('Name') })
    if ($keys.Count -ne 1 -or $keys[0] -cne 'entityid') {
        $script:IdentityContractFailurePredicate = 'ENTITY_PRIMARY_KEY_IS_ENTITYID'
        throw 'Dataverse entity metadata lacks the expected entityid/logicalname identity contract.'
    }
    if (@('entityid', 'logicalname', 'name', 'objecttypecode' | Where-Object { $_ -notin $properties }).Count -gt 0) {
        $script:IdentityContractFailurePredicate = 'ENTITY_REQUIRED_PROPERTIES_PRESENT'
        throw 'Dataverse entity metadata lacks the expected entityid/logicalname identity contract.'
    }
    [pscustomobject]@{ EntitySet = 'entities'; PrimaryKey = 'entityid' }
}

function ConvertTo-NormalizedAppModuleComponents {
    param(
        [Parameter(Mandatory = $true)][object[]]$Components,
        [Parameter(Mandatory = $true)][object[]]$EntityRecords,
        [Parameter(Mandatory = $true)][object[]]$ReferenceComponents,
        [Parameter(Mandatory = $true)][string]$SiteMapId,
        [Parameter(Mandatory = $true)][string]$AppModuleIdUnique
    )
    $expectedNames = @($ReferenceComponents | ForEach-Object { [string]$_.LogicalName })
    if ($expectedNames.Count -ne 4 -or @($expectedNames | Select-Object -Unique).Count -ne 4) {
        throw 'Reference entity normalization requires four unique approved table logical names.'
    }
    $normalized = [System.Collections.Generic.List[object]]::new()
    $seenEntityNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($component in $Components) {
        $componentType = [int]$component.componenttype
        $objectId = [string]$component.objectid
        $logicalName = $null
        $parentLogicalName = $null
        if ($componentType -eq 1) {
            $entityId = ConvertTo-NormalizedGuid -Value $objectId
            $entityMatches = @($EntityRecords | Where-Object {
                (ConvertTo-NormalizedGuid -Value ([string]$_.entityid)) -ceq $entityId
            })
            if ($entityMatches.Count -ne 1) {
                throw 'An AppModule entity objectid did not resolve uniquely through entities.entityid.'
            }
            $logicalName = [string]$entityMatches[0].logicalname
            if ($logicalName -notin $expectedNames) {
                throw 'An AppModule entity component resolves to an unapproved table logical name.'
            }
            if (-not $seenEntityNames.Add($logicalName)) {
                throw 'AppModule entity components resolve to a duplicate table logical name.'
            }
        }
        elseif ($componentType -in @(26, 60)) {
            $assetId = ConvertTo-NormalizedGuid -Value $objectId
            $assetMatches = foreach ($reference in $ReferenceComponents) {
                $approvedId = if ($componentType -eq 60) { $reference.MainForm.Id } else { $reference.ActiveView.Id }
                if ((ConvertTo-NormalizedGuid -Value ([string]$approvedId)) -ceq $assetId) {
                    $reference
                }
            }
            if (@($assetMatches).Count -eq 1) { $parentLogicalName = [string]@($assetMatches)[0].LogicalName }
        }
        $appModuleComponentId = ConvertTo-NormalizedGuid -Value ([string]$component.appmodulecomponentid)
        $rootComponentId = [string]$component.rootappmodulecomponentid
        $rootClassification = 'UNKNOWN'
        if (-not [string]::IsNullOrWhiteSpace($rootComponentId) -and $rootComponentId -ne [guid]::Empty.ToString()) {
            $normalizedRootId = ConvertTo-NormalizedGuid -Value $rootComponentId
            $rootMatches = @($Components | Where-Object {
                (ConvertTo-NormalizedGuid -Value ([string]$_.appmodulecomponentid)) -ceq $normalizedRootId
            })
            if ($rootMatches.Count -eq 1) {
                $rootClassification = if ($normalizedRootId -ceq $appModuleComponentId) {
                    'DIRECT_ROOT_COMPONENT'
                }
                else {
                    'SUBCOMPONENT'
                }
            }
        }
        $normalized.Add([pscustomobject]@{
            ComponentId = $appModuleComponentId
            ComponentType = $componentType
            ObjectId = $objectId
            EntityLogicalName = $logicalName
            ParentLogicalName = $parentLogicalName
            IsMetadata = $component.ismetadata
            IsDefault = $component.isdefault
            RootAppModuleComponentId = $component.rootappmodulecomponentid
            RootComponentBehavior = $component.rootcomponentbehavior
            RootClassification = $rootClassification
            AppAssociationMatches = (ConvertTo-NormalizedGuid -Value ([string]$component._appmoduleidunique_value)) -ceq
                (ConvertTo-NormalizedGuid -Value $AppModuleIdUnique)
        })
    }
    $normalized.ToArray()
}

function Get-AppModuleEntityRecords {
    param(
        [Parameter(Mandatory = $true)][object[]]$Components,
        [Parameter(Mandatory = $true)][object]$IdentityContract
    )
    if ($IdentityContract.EntitySet -cne 'entities' -or $IdentityContract.PrimaryKey -cne 'entityid') {
        throw 'AppModule entity resolution contract is not verified.'
    }
    $records = [System.Collections.Generic.List[object]]::new()
    foreach ($component in @($Components | Where-Object { [int]$_.componenttype -eq 1 })) {
        $entityId = ConvertTo-NormalizedGuid -Value ([string]$component.objectid)
        $filter = 'entityid eq ' + $entityId
        $path = New-CollectionPath -EntitySet $IdentityContract.EntitySet `
            -Select 'entityid,logicalname,name,objecttypecode' -Filter $filter
        $matches = @(Get-ODataRows -Path $path)
        if ($matches.Count -ne 1) {
            throw "An AppModule entity objectid resolved to $($matches.Count) entities rows; exactly one is required."
        }
        $record = $matches[0]
        if ((ConvertTo-NormalizedGuid -Value ([string]$record.entityid)) -cne $entityId -or
            [string]::IsNullOrWhiteSpace([string]$record.logicalname)) {
            throw 'An AppModule entity component did not resolve to its exact entities record.'
        }
        $records.Add($record)
    }
    $records.ToArray()
}

function Get-EntityResolutionDiagnosticRows {
    param(
        [Parameter(Mandatory = $true)][object[]]$Components,
        [Parameter(Mandatory = $true)][object[]]$ReferenceComponents
    )
    $entityComponents = @($Components | Where-Object { [int]$_.componenttype -eq 1 })
    $diagnostics = [System.Collections.Generic.List[object]]::new()
    $payloadIdsByName = @{}
    foreach ($reference in $ReferenceComponents) {
        $entityPayload = @($reference.Payloads | Where-Object {
            $_.'@odata.type' -ceq 'Microsoft.Dynamics.CRM.entity'
        })
        if ($entityPayload.Count -eq 1) {
            $payloadIdsByName[[string]$reference.LogicalName] = [string]$entityPayload[0].entityid
        }
    }
    for ($index = 0; $index -lt $entityComponents.Count; $index++) {
        $component = $entityComponents[$index]
        $alias = 'EntityComponent{0}' -f ($index + 1)
        $objectId = [string](Get-PropertyValue -Object $component -Name 'objectid')
        $componentId = [string](Get-PropertyValue -Object $component -Name 'appmodulecomponentid')
        $associatedAppIdUnique = [string](Get-PropertyValue -Object $component -Name '_appmoduleidunique_value')
        $parsedAssociatedAppIdUnique = [guid]::Empty
        $appAssociationMatches = [guid]::TryParse($associatedAppIdUnique.Trim('{}'), [ref]$parsedAssociatedAppIdUnique) -and
            $parsedAssociatedAppIdUnique.ToString('D').ToLowerInvariant() -ceq
                (ConvertTo-NormalizedGuid -Value $script:Target.AppModuleIdUnique)
        $parsedObjectId = [guid]::Empty
        $isValidGuid = -not [string]::IsNullOrWhiteSpace($objectId) -and
            [guid]::TryParse($objectId.Trim('{}'), [ref]$parsedObjectId)
        $recordCount = $null
        $httpStatus = $null
        $logicalNames = @()
        $entityIdMatches = @()
        $failureCategory = $null
        $normalizedLogicalName = $null
        $predicateName = 'ENTITY_OBJECTID_RESOLVED_UNIQUELY'
        $predicateResult = $false
        $payloadEntityIdPresent = $false
        $objectIdEqualsPayloadId = $null
        $payloadIdEqualsEntityId = $null
        $innerExceptionCategory = $null
        if (-not $isValidGuid) {
            $recordCount = 0
            $failureCategory = if ([string]::IsNullOrWhiteSpace($objectId)) { 'OBJECTID_MISSING' } else { 'OBJECTID_INVALID_GUID' }
            $predicateName = 'OBJECTID_IS_VALID_GUID'
        }
        else {
            $validatedObjectId = $parsedObjectId.ToString('D').ToLowerInvariant()
            $filter = 'entityid eq ' + $validatedObjectId
            $path = New-CollectionPath -EntitySet 'entities' -Select 'entityid,logicalname,name,objecttypecode' -Filter $filter
            $matches = @()
            $querySucceeded = $false
            try {
                $matches = @(Get-ODataRows -Path $path)
                $httpStatus = $script:LastHttpStatus
                if ($null -eq $httpStatus) { $httpStatus = 200 }
                $querySucceeded = $true
            }
            catch {
                $httpStatus = $script:LastHttpStatus
                $failureCategory = if ($httpStatus -and $httpStatus -ge 400) { 'ENTITY_QUERY_HTTP_FAILURE' } else { 'ENTITY_QUERY_FAILURE' }
                $predicateName = 'ENTITIES_RETRIEVEMULTIPLE_SUCCEEDED'
                $innerExceptionCategory = $_.Exception.GetType().Name
            }
            if ($querySucceeded) {
                $recordCount = $matches.Count
                try {
                    $logicalNames = @($matches | ForEach-Object { [string](Get-PropertyValue -Object $_ -Name 'logicalname') })
                    $entityIdMatches = @($matches | ForEach-Object {
                        $returnedEntityId = [string](Get-PropertyValue -Object $_ -Name 'entityid')
                        $parsedReturnedId = [guid]::Empty
                        [guid]::TryParse($returnedEntityId.Trim('{}'), [ref]$parsedReturnedId) -and
                            $parsedReturnedId.ToString('D').ToLowerInvariant() -ceq $validatedObjectId
                    })
                    if ($matches.Count -eq 0) {
                        $failureCategory = 'ENTITY_OBJECTID_NOT_RESOLVED'
                        $predicateName = 'ENTITY_OBJECTID_RESOLVED_UNIQUELY'
                    }
                    elseif ($matches.Count -gt 1) {
                        $failureCategory = 'ENTITY_OBJECTID_AMBIGUOUS'
                        $predicateName = 'ENTITY_OBJECTID_RESOLVED_UNIQUELY'
                    }
                    elseif (-not $entityIdMatches[0]) {
                        $failureCategory = 'ENTITYID_MATCHES_QUERY'
                        $predicateName = 'ENTITYID_EQUALS_QUERIED_OBJECTID'
                    }
                    else {
                        $normalizedLogicalName = $logicalNames[0]
                        $payloadEntityIdPresent = $payloadIdsByName.ContainsKey($normalizedLogicalName)
                        if ($payloadEntityIdPresent) {
                            $payloadId = ConvertTo-NormalizedGuid -Value $payloadIdsByName[$normalizedLogicalName]
                            $objectIdEqualsPayloadId = $validatedObjectId -ceq $payloadId
                            $payloadIdEqualsEntityId = $entityIdMatches[0]
                        }
                        if ($normalizedLogicalName -notin $script:Target.ReferenceTableNames) {
                            $failureCategory = 'ENTITY_LOGICALNAME_UNEXPECTED'
                            $predicateName = 'ENTITY_LOGICALNAME_IS_APPROVED'
                        }
                        else {
                            $predicateResult = $true
                        }
                    }
                }
                catch {
                    $failureCategory = 'ENTITY_RESPONSE_PREDICATE_EVALUATION_FAILED'
                    $predicateName = 'ENTITY_RESPONSE_IS_WELL_FORMED'
                    $recordCount = $matches.Count
                    $logicalNames = @()
                    $entityIdMatches = @()
                    $innerExceptionCategory = $_.Exception.GetType().Name
                }
            }
        }
        if (-not $predicateResult -and -not $script:FirstFailingPredicate) {
            $script:FirstFailingPredicate = if ($failureCategory) { $failureCategory } else { $predicateName }
        }
        $diagnostics.Add([pscustomobject]@{
            Alias = $alias
            ComponentType = [int]$component.componenttype
            ObjectIdPresent = -not [string]::IsNullOrWhiteSpace($objectId)
            ObjectIdSyntacticallyValidGuid = [bool]$isValidGuid
            AppModuleComponentIdPresent = -not [string]::IsNullOrWhiteSpace($componentId)
            RootAppModuleComponentIdPresent = -not [string]::IsNullOrWhiteSpace([string](Get-PropertyValue -Object $component -Name 'rootappmodulecomponentid'))
            RootComponentBehavior = Get-PropertyValue -Object $component -Name 'rootcomponentbehavior'
            IsDefault = Get-PropertyValue -Object $component -Name 'isdefault'
            IsMetadata = Get-PropertyValue -Object $component -Name 'ismetadata'
            AppAssociationMatches = $appAssociationMatches
            HttpStatus = $httpStatus
            ReturnedRowCount = $recordCount
            ReturnedLogicalNames = $logicalNames
            EntityIdMatchesQueriedObjectId = $entityIdMatches
            NormalizedLogicalName = $normalizedLogicalName
            PayloadEntityIdPresent = $payloadEntityIdPresent
            ObjectIdEqualsPayloadEntityId = $objectIdEqualsPayloadId
            PayloadEntityIdEqualsEntityId = $payloadIdEqualsEntityId
            PredicateName = $predicateName
            PredicateResult = $predicateResult
            FailureCategory = $failureCategory
            InnerExceptionCategory = $innerExceptionCategory
        })
    }
    $result = $diagnostics.ToArray()
    if ($entityComponents.Count -ne 4) {
        if (-not $script:FirstFailingPredicate) { $script:FirstFailingPredicate = 'ENTITY_COMPONENT_COUNT_IS_FOUR' }
    }
    foreach ($diagnostic in $result) {
        if ($diagnostic.PredicateResult -and
            @($result | Where-Object { $_.NormalizedLogicalName -ceq $diagnostic.NormalizedLogicalName }).Count -gt 1) {
            $diagnostic.PredicateName = 'ENTITY_LOGICALNAME_IS_UNIQUE'
            $diagnostic.PredicateResult = $false
            $diagnostic.FailureCategory = 'ENTITY_LOGICALNAME_DUPLICATE'
            if (-not $script:FirstFailingPredicate) { $script:FirstFailingPredicate = $diagnostic.FailureCategory }
        }
    }
    $resolvedNames = @($result | Where-Object PredicateResult | ForEach-Object { $_.NormalizedLogicalName })
    foreach ($expectedName in $script:Target.ReferenceTableNames) {
        if (@($resolvedNames | Where-Object { $_ -ceq $expectedName }).Count -ne 1 -and
            -not $script:FirstFailingPredicate) {
            $script:FirstFailingPredicate = 'APPROVED_ENTITY_LOGICALNAME_SET_IS_EXACT'
        }
    }
    $result
}

function Get-EntityResolutionAggregateClassification {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Diagnostics)
    $failureCategories = @($Diagnostics | Where-Object { -not $_.PredicateResult } |
        ForEach-Object { [string]$_.FailureCategory } | Where-Object { $_ } | Select-Object -Unique)
    if ($Diagnostics.Count -eq 4 -and @($Diagnostics | Where-Object { $_.PredicateResult }).Count -eq 4 -and
        @($Diagnostics.NormalizedLogicalName | Select-Object -Unique).Count -eq 4) {
        return 'ENTITYID_MAPPING_CONFIRMED'
    }
    if ($failureCategories.Count -gt 1) { return 'ENTITY_MAPPING_MIXED' }
    if ($failureCategories -contains 'ENTITY_OBJECTID_AMBIGUOUS') { return 'ENTITY_MAPPING_AMBIGUOUS' }
    if ($failureCategories -contains 'ENTITY_OBJECTID_NOT_RESOLVED') { return 'OBJECTID_NOT_ENTITYID' }
    if ($failureCategories -contains 'ENTITY_LOGICALNAME_UNEXPECTED') { return 'ENTITY_MAPPING_WRONG_LOGICALNAME' }
    if ($failureCategories -contains 'ENTITY_LOGICALNAME_DUPLICATE') { return 'ENTITY_MAPPING_DUPLICATE_LOGICALNAME' }
    if ($failureCategories.Count -gt 0) { return $failureCategories[0] }
    'UNKNOWN'
}

function Get-EntityRowsByLogicalName {
    param([Parameter(Mandatory = $true)][string]$LogicalName)
    $escapedName = $LogicalName.Replace("'", "''")
    $path = New-CollectionPath -EntitySet 'entities' `
        -Select 'entityid,logicalname,name,objecttypecode,componentstate' `
        -Filter "logicalname eq '$escapedName'"
    @(Get-ODataRows -Path $path)
}

function Get-EntityDefinitionByLogicalName {
    param([Parameter(Mandatory = $true)][string]$LogicalName)
    $escapedName = $LogicalName.Replace("'", "''")
    Invoke-DataverseRequest -Method GET `
        -Path "EntityDefinitions(LogicalName='$escapedName')?%24select=MetadataId,LogicalName,ObjectTypeCode"
}

function Get-RemoveAppComponentsContract {
    param([Parameter(Mandatory = $true)][xml]$Metadata)
    $action = $Metadata.SelectSingleNode("//*[local-name()='Action' and @Name='RemoveAppComponents']")
    if (-not $action) { return [pscustomobject]@{ Found = $false; Valid = $false; AppIdType = $null; ComponentsType = $null } }
    $parameters = @{}
    foreach ($parameter in $action.SelectNodes("./*[local-name()='Parameter']")) {
        $parameters[$parameter.GetAttribute('Name')] = $parameter.GetAttribute('Type')
    }
    [pscustomobject]@{
        Found = $true
        AppIdType = $parameters['AppId']
        ComponentsType = $parameters['Components']
        Valid = $parameters['AppId'] -ceq 'Edm.Guid' -and
            $parameters['Components'] -ceq 'Collection(mscrm.crmbaseentity)'
    }
}

function Get-NormalizedGuidCandidates {
    param([object[]]$Rows, [string]$PropertyName)
    $values = [System.Collections.Generic.List[string]]::new()
    foreach ($row in $Rows) {
        $value = [string](Get-PropertyValue -Object $row -Name $PropertyName)
        $parsed = [guid]::Empty
        if ([guid]::TryParse($value.Trim('{}'), [ref]$parsed)) {
            $values.Add($parsed.ToString('D').ToLowerInvariant())
        }
    }
    @($values | Select-Object -Unique)
}

function Test-GuidValueMatchesAny {
    param([string]$Value, [string[]]$Candidates)
    $parsed = [guid]::Empty
    if ([string]::IsNullOrWhiteSpace($Value) -or -not [guid]::TryParse($Value.Trim('{}'), [ref]$parsed)) {
        return $false
    }
    $normalized = $parsed.ToString('D').ToLowerInvariant()
    foreach ($candidate in $Candidates) {
        $parsedCandidate = [guid]::Empty
        if ([guid]::TryParse(([string]$candidate).Trim('{}'), [ref]$parsedCandidate) -and
            $parsedCandidate.ToString('D').ToLowerInvariant() -ceq $normalized) {
            return $true
        }
    }
    $false
}

function Get-DirectReferenceUiAssociationEvidence {
    param(
        [Parameter(Mandatory = $true)][object[]]$Components,
        [Parameter(Mandatory = $true)][object[]]$ReferenceComponents,
        [Parameter(Mandatory = $true)][string]$SiteMapId,
        [Parameter(Mandatory = $true)][string]$AppModuleIdUnique
    )
    $associationMatches = @($Components | Where-Object {
        Test-GuidValueMatchesAny -Value ([string](Get-PropertyValue -Object $_ -Name '_appmoduleidunique_value')) `
            -Candidates @($AppModuleIdUnique)
    })
    $siteMaps = @($Components | Where-Object { [int]$_.componenttype -eq 62 })
    $siteMapMatches = @($siteMaps | Where-Object {
        [int]$_.componenttype -eq 62 -and
        (Test-GuidValueMatchesAny -Value ([string]$_.objectid) -Candidates @($SiteMapId))
    })
    $assets = [System.Collections.Generic.List[object]]::new()
    foreach ($reference in $ReferenceComponents) {
        $formMatches = @($Components | Where-Object {
            [int]$_.componenttype -eq 60 -and
            (Test-GuidValueMatchesAny -Value ([string]$_.objectid) -Candidates @([string]$reference.MainForm.Id))
        })
        $viewMatches = @($Components | Where-Object {
            [int]$_.componenttype -eq 26 -and
            (Test-GuidValueMatchesAny -Value ([string]$_.objectid) -Candidates @([string]$reference.ActiveView.Id))
        })
        $assets.Add([pscustomobject]@{
            LogicalName = $reference.LogicalName
            MainFormPresentDirectly = $formMatches.Count -eq 1
            MainFormDirectMatchCount = $formMatches.Count
            ActiveViewPresentDirectly = $viewMatches.Count -eq 1
            ActiveViewDirectMatchCount = $viewMatches.Count
        })
    }
    [pscustomobject]@{
        SiteMapCount = $siteMaps.Count
        IntendedSiteMapDirectMatchCount = $siteMapMatches.Count
        IntendedSiteMapPresentDirectly = $siteMapMatches.Count -eq 1
        AppAssociationMatchesForEveryComponent = $associationMatches.Count -eq $Components.Count
        Assets = $assets.ToArray()
    }
}

function Get-EntityRootRepairPlan {
    param(
        [Parameter(Mandatory = $true)][object[]]$Components,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$SystemEntityIds,
        [Parameter(Mandatory = $true)][object[]]$ReferenceIdentityEvidence,
        [Parameter(Mandatory = $true)][bool]$OriginalPayloadFingerprintMatches,
        [Parameter(Mandatory = $true)][bool]$RemoveActionContractValid,
        [Parameter(Mandatory = $true)][string]$AppId
    )
    $entityComponents = @($Components | Where-Object { [int]$_.componenttype -eq 1 })
    $componentRecordIds = @(Get-NormalizedGuidCandidates -Rows $entityComponents -PropertyName 'appmodulecomponentid')
    $objectIds = @(Get-NormalizedGuidCandidates -Rows $entityComponents -PropertyName 'objectid')
    $componentRecordsDistinct = $entityComponents.Count -eq 4 -and $componentRecordIds.Count -eq 4
    $objectIdsDistinct = $entityComponents.Count -eq 4 -and $objectIds.Count -eq 4
    $objectIdsDuplicated = $objectIds.Count -lt $entityComponents.Count
    $allObjectIdsEqual = $entityComponents.Count -gt 0 -and $objectIds.Count -eq 1
    $referenceByName = @{}
    foreach ($reference in $ReferenceIdentityEvidence) {
        $referenceByName[[string]$reference.LogicalName] = $reference
    }
    $systemIds = @($SystemEntityIds | Where-Object { $_ } | Select-Object -Unique)
    $mappingRows = [System.Collections.Generic.List[object]]::new()
    $currentRootMatchesSystem = 0
    $currentRootMatchesProjectId = 0
    $currentRootMatchesProject = 0
    $currentRootMatchesAnyProjectId = 0
    for ($index = 0; $index -lt $entityComponents.Count; $index++) {
        $component = $entityComponents[$index]
        $objectId = [string](Get-PropertyValue -Object $component -Name 'objectid')
        $row = [ordered]@{
            Alias = 'CurrentEntityComponent{0}' -f ([char](65 + $index))
            ComponentRecordIdPresent = -not [string]::IsNullOrWhiteSpace([string](Get-PropertyValue -Object $component -Name 'appmodulecomponentid'))
            ObjectIdPresent = -not [string]::IsNullOrWhiteSpace($objectId)
            IsDefault = Get-PropertyValue -Object $component -Name 'isdefault'
            IsMetadata = Get-PropertyValue -Object $component -Name 'ismetadata'
            RootAppModuleComponentIdPresent = -not [string]::IsNullOrWhiteSpace([string](Get-PropertyValue -Object $component -Name 'rootappmodulecomponentid'))
            RootComponentBehavior = Get-PropertyValue -Object $component -Name 'rootcomponentbehavior'
            ObjectIdEqualsSystemEntityId = Test-GuidValueMatchesAny -Value $objectId -Candidates $systemIds
        }
        if ($row.ObjectIdEqualsSystemEntityId) { $currentRootMatchesSystem++ }
        $payloadIdMatchCount = 0
        foreach ($logicalName in @('os_sr_ta', 'os_sr_pos', 'os_sr_csrc', 'os_sr_loc')) {
            $evidence = $referenceByName[$logicalName]
            $metadataMatch = $false
            $entitiesMatch = $false
            $payloadMetadataMatch = $false
            $payloadEntitiesMatch = $false
            if ($evidence) {
                $metadataMatch = Test-GuidValueMatchesAny -Value $objectId -Candidates @([string]$evidence.MetadataId)
                $entitiesMatch = Test-GuidValueMatchesAny -Value $objectId -Candidates @([string]$evidence.EntityId)
                $payloadMetadataMatch = Test-GuidValueMatchesAny -Value ([string]$evidence.PayloadEntityId) -Candidates @([string]$evidence.MetadataId)
                $payloadEntitiesMatch = Test-GuidValueMatchesAny -Value ([string]$evidence.PayloadEntityId) -Candidates @([string]$evidence.EntityId)
            }
            if ($metadataMatch -or $entitiesMatch) {
                $currentRootMatchesProject++
                $currentRootMatchesAnyProjectId++
            }
            if ($metadataMatch -or $entitiesMatch) { $row[$logicalName] = $true } else { $row[$logicalName] = $false }
            $row["PayloadMatches${logicalName}MetadataId"] = $payloadMetadataMatch
            $row["PayloadMatches${logicalName}EntityId"] = $payloadEntitiesMatch
            if ($payloadMetadataMatch -or $payloadEntitiesMatch) { $payloadIdMatchCount++ }
        }
        $row.PayloadMatchesAnyApprovedTableId = $payloadIdMatchCount -gt 0
        $row.PayloadIdEqualsCurrentObjectId = $false
        foreach ($evidence in $ReferenceIdentityEvidence) {
            if (Test-GuidValueMatchesAny -Value ([string]$evidence.PayloadEntityId) -Candidates @($objectId)) {
                $row.PayloadIdEqualsCurrentObjectId = $true
                break
            }
        }
        $mappingRows.Add([pscustomobject]$row)
    }

    $referenceIdentityComplete = $ReferenceIdentityEvidence.Count -eq 4 -and @(
        $ReferenceIdentityEvidence | Where-Object {
            -not $_.MetadataFound -or -not $_.EntityTableIdentityUnambiguous -or
            -not $_.LogicalNamesAgree -or -not $_.MetadataIdEqualsEntityId -or
            ($null -ne $_.ObjectTypeCodesAgree -and -not $_.ObjectTypeCodesAgree)
        }
    ).Count -eq 0
    $tableRootCounts = @{}
    foreach ($logicalName in @('os_sr_ta', 'os_sr_pos', 'os_sr_csrc', 'os_sr_loc')) {
        $tableRootCounts[$logicalName] = @(
            $mappingRows | Where-Object { $_.$logicalName }
        ).Count
    }
    $eachProjectRootExactlyOnce = $referenceIdentityComplete -and
        @($tableRootCounts.Values | Where-Object { $_ -ne 1 }).Count -eq 0
    $systemMatchesAll = $entityComponents.Count -eq 4 -and $currentRootMatchesSystem -eq 4
    if ($systemMatchesAll -and $currentRootMatchesProjectId -eq 0) {
        $rootClassification = 'WRONG_SYSTEM_ENTITY_ROOTS_CONFIRMED'
    }
    elseif ($eachProjectRootExactlyOnce -and $currentRootMatchesSystem -eq 0) {
        $rootClassification = 'CORRECT_PROJECT_TABLE_ROOTS'
    }
    elseif (($currentRootMatchesSystem + $currentRootMatchesProjectId) -gt 0 -and
        -not ($systemMatchesAll -or $eachProjectRootExactlyOnce)) {
        $rootClassification = 'MIXED_ROOT_STATE'
    }
    else {
        $rootClassification = 'UNKNOWN'
    }

    $payloadSource = 'ENTITYDEFINITIONS_METADATA_ID'
    $payloadSourceMatchesCurrentRoots = $mappingRows.Count -eq 4 -and
        @($mappingRows | Where-Object {
            -not $_.ObjectIdEqualsSystemEntityId -or -not $_.PayloadIdEqualsCurrentObjectId
        }).Count -eq 0
    $originalPayloadRootCause = if (-not $OriginalPayloadFingerprintMatches) {
        'ORIGINAL_PAYLOAD_FINGERPRINT_NOT_REPRODUCED'
    }
    elseif ($payloadSourceMatchesCurrentRoots) {
        'ENTITYDEFINITIONS_METADATA_ID_MATCHES_CURRENT_SYSTEM_ROOTS'
    }
    else {
        'NOT_ESTABLISHED_BY_AVAILABLE_PAYLOAD_AND_ROOT_EVIDENCE'
    }

    $removePayload = @()
    $addPayload = @()
    $removeFingerprint = $null
    $addFingerprint = $null
    $removeRequestBodyFingerprint = $null
    $addRequestBodyFingerprint = $null
    $removeSemanticsKnownForObservedMultiplicity = -not $objectIdsDuplicated
    $repairPlanStatus = 'NOT_APPLICABLE'
    if ($rootClassification -eq 'WRONG_SYSTEM_ENTITY_ROOTS_CONFIRMED') {
        $uniqueWrongIds = @($entityComponents | ForEach-Object {
            ConvertTo-NormalizedGuid -Value ([string]$_.objectid)
        } | Select-Object -Unique)
        $removePayload = @($uniqueWrongIds | ForEach-Object {
            [ordered]@{ entityid = $_; '@odata.type' = 'Microsoft.Dynamics.CRM.entity' }
        })
        if ($referenceIdentityComplete) {
            $addPayload = @($ReferenceIdentityEvidence | Sort-Object {
                [array]::IndexOf(@('os_sr_ta', 'os_sr_pos', 'os_sr_csrc', 'os_sr_loc'), $_.LogicalName)
            } | ForEach-Object {
                [ordered]@{ entityid = [string]$_.EntityId; '@odata.type' = 'Microsoft.Dynamics.CRM.entity' }
            })
        }
        if ($removePayload.Count -gt 0) {
            $removeFingerprint = Get-PayloadFingerprint -Payload $removePayload
        }
        if ($addPayload.Count -eq 4) {
            $addFingerprint = Get-PayloadFingerprint -Payload $addPayload
        }
        if ($removePayload.Count -gt 0) {
            $removeRequestBodyFingerprint = Get-PayloadFingerprint -Payload @(
                [ordered]@{ AppId = $AppId; Components = @($removePayload) }
            )
        }
        if ($addPayload.Count -eq 4) {
            $addRequestBodyFingerprint = Get-PayloadFingerprint -Payload @(
                [ordered]@{ AppId = $AppId; Components = @($addPayload) }
            )
        }
        $repairPlanStatus = if ($referenceIdentityComplete -and $objectIdsDistinct -and
            $removePayload.Count -eq 4 -and $addPayload.Count -eq 4 -and
            $RemoveActionContractValid -and
            $OriginalPayloadFingerprintMatches -and
            $originalPayloadRootCause -eq 'ENTITYDEFINITIONS_METADATA_ID_MATCHES_CURRENT_SYSTEM_ROOTS') {
            'READY'
        }
        else {
            'AMBIGUOUS'
        }
    }
    [pscustomobject]@{
        CurrentEntityComponentCount = $entityComponents.Count
        AllComponentRecordIdsDistinct = $componentRecordsDistinct
        AllObjectIdsDistinct = $objectIdsDistinct
        SomeObjectIdsDuplicate = $objectIdsDuplicated
        AllObjectIdsEqual = $allObjectIdsEqual
        CurrentComponents = $mappingRows.ToArray()
        SystemEntityUniqueIdCount = $systemIds.Count
        ReferenceIdentityComplete = $referenceIdentityComplete
        ProjectTableRootCounts = $tableRootCounts
        RootClassification = $rootClassification
        OriginalPayloadIdSource = $payloadSource
        OriginalPayloadFingerprintMatchesApproved = $OriginalPayloadFingerprintMatches
        OriginalPayloadRootCause = $originalPayloadRootCause
        RemovePayload = @($removePayload | ForEach-Object {
            [pscustomobject]@{
                ODataType = Get-PropertyValue -Object $_ -Name '@odata.type'
                EntityIdPresent = -not [string]::IsNullOrWhiteSpace([string](Get-PropertyValue -Object $_ -Name 'entityid'))
            }
        })
        RemovePayloadCount = $removePayload.Count
        RemovePayloadFingerprint = $removeFingerprint
        RemoveRequestBodyFingerprint = $removeRequestBodyFingerprint
        RemoveSemanticsKnownForObservedMultiplicity = $removeSemanticsKnownForObservedMultiplicity
        AddPayload = @($ReferenceIdentityEvidence | Sort-Object {
            [array]::IndexOf(@('os_sr_ta', 'os_sr_pos', 'os_sr_csrc', 'os_sr_loc'), $_.LogicalName)
        } | ForEach-Object {
            [pscustomobject]@{
                LogicalName = $_.LogicalName
                ODataType = 'Microsoft.Dynamics.CRM.entity'
                EntityIdPresent = -not [string]::IsNullOrWhiteSpace([string]$_.EntityId)
            }
        })
        AddPayloadCount = $addPayload.Count
        AddPayloadFingerprint = $addFingerprint
        AddRequestBodyFingerprint = $addRequestBodyFingerprint
        RemoveActionContractValid = $RemoveActionContractValid
        AddPayloadContainsOnlyEntityComponents = @($addPayload | Where-Object {
            $_.'@odata.type' -cne 'Microsoft.Dynamics.CRM.entity' -or @($_.Keys | Where-Object { $_ -ne '@odata.type' }) -join ',' -cne 'entityid'
        }).Count -eq 0
        RepairPlanStatus = $repairPlanStatus
        ExpectedDirectComponentCountsAfterRepair = [pscustomobject]@{
            SiteMap = 1; Entity = 4; Form = 4; View = 4; Total = 13
        }
        NavigationChangePlanned = $false
        PublishPlanned = $false
    }
}

function Get-EntityRootRepairEvidence {
    param(
        [Parameter(Mandatory = $true)][object[]]$Components,
        [Parameter(Mandatory = $true)][object[]]$ReferenceComponents,
        [Parameter(Mandatory = $true)][bool]$OriginalPayloadFingerprintMatches,
        [Parameter(Mandatory = $true)][xml]$Metadata
    )
    $logicalNames = @('entity') + @('os_sr_ta', 'os_sr_pos', 'os_sr_csrc', 'os_sr_loc')
    $entityRowsByName = @{}
    foreach ($logicalName in $logicalNames) {
        $script:LastStage = "Resolve entities table row for $logicalName"
        $entityRowsByName[$logicalName] = @(Get-EntityRowsByLogicalName -LogicalName $logicalName)
    }
    $referenceEvidence = [System.Collections.Generic.List[object]]::new()
    foreach ($reference in $ReferenceComponents) {
        $logicalName = [string]$reference.LogicalName
        $script:LastStage = "Resolve EntityDefinitions metadata for $logicalName"
        $entityDefinitionMetadata = Get-EntityDefinitionByLogicalName -LogicalName $logicalName
        $entityRows = @($entityRowsByName[$logicalName])
        $entityIds = @(Get-NormalizedGuidCandidates -Rows $entityRows -PropertyName 'entityid')
        $metadataId = [string](Get-PropertyValue -Object $entityDefinitionMetadata -Name 'MetadataId')
        $payload = @($reference.Payloads | Where-Object {
            $_.'@odata.type' -ceq 'Microsoft.Dynamics.CRM.entity'
        })
        $payloadEntityId = if ($payload.Count -eq 1) { [string]$payload[0].entityid } else { $null }
        $metadataLogicalName = [string](Get-PropertyValue -Object $entityDefinitionMetadata -Name 'LogicalName')
        $entityLogicalNames = @($entityRows | ForEach-Object { [string](Get-PropertyValue -Object $_ -Name 'logicalname') } | Select-Object -Unique)
        $metadataObjectTypeCode = Get-PropertyValue -Object $entityDefinitionMetadata -Name 'ObjectTypeCode'
        $entityObjectTypeCodes = @($entityRows | ForEach-Object { Get-PropertyValue -Object $_ -Name 'objecttypecode' } | Where-Object { $null -ne $_ } | Select-Object -Unique)
        $metadataEvidence = [pscustomobject]@{
            LogicalName = $logicalName
            MetadataFound = $metadataLogicalName -ceq $logicalName -and
                -not [string]::IsNullOrWhiteSpace($metadataId)
            MetadataLogicalNameMatches = $metadataLogicalName -ceq $logicalName
            MetadataObjectTypeCode = $metadataObjectTypeCode
            EntityTableRowCount = $entityRows.Count
            EntityTableLogicalNames = $entityLogicalNames
            EntityTableLogicalNamesAgree = $entityLogicalNames.Count -eq 1 -and $entityLogicalNames[0] -ceq $logicalName
            EntityTableUniqueIdCount = $entityIds.Count
            EntityTableObjectTypeCodes = $entityObjectTypeCodes
            EntityTableComponentStates = @($entityRows | ForEach-Object { Get-PropertyValue -Object $_ -Name 'componentstate' } | Select-Object -Unique)
            EntityId = if ($entityIds.Count -eq 1) { $entityIds[0] } else { $null }
            EntityTableIdentityUnambiguous = $entityIds.Count -eq 1 -and
                $entityLogicalNames.Count -eq 1 -and $entityLogicalNames[0] -ceq $logicalName
            LogicalNamesAgree = $metadataLogicalName -ceq $logicalName -and
                $entityLogicalNames.Count -eq 1 -and $entityLogicalNames[0] -ceq $logicalName
            ObjectTypeCodesAgree = if ($null -eq $metadataObjectTypeCode -or $entityObjectTypeCodes.Count -eq 0) {
                $null
            }
            else {
                $entityObjectTypeCodes.Count -eq 1 -and [string]$entityObjectTypeCodes[0] -ceq [string]$metadataObjectTypeCode
            }
            MetadataIdEqualsEntityId = Test-GuidValueMatchesAny -Value $metadataId -Candidates $entityIds
            MetadataId = $metadataId
            PayloadEntityId = $payloadEntityId
            PayloadMatchesMetadataId = Test-GuidValueMatchesAny -Value $payloadEntityId -Candidates @($metadataId)
            PayloadMatchesEntityId = Test-GuidValueMatchesAny -Value $payloadEntityId -Candidates $entityIds
        }
        $referenceEvidence.Add($metadataEvidence)
    }
    $systemEntityIds = @(Get-NormalizedGuidCandidates -Rows @($entityRowsByName['entity']) -PropertyName 'entityid')
    if ($entityRowsByName['entity'].Count -eq 1 -and $systemEntityIds.Count -eq 1) {
        $script:SystemEntityIdForRemoval = $systemEntityIds[0]
    }
    else {
        $script:SystemEntityIdForRemoval = $null
    }
    $removeContract = Get-RemoveAppComponentsContract -Metadata $Metadata
    $plan = Get-EntityRootRepairPlan -Components $Components -SystemEntityIds $systemEntityIds `
        -ReferenceIdentityEvidence $referenceEvidence.ToArray() `
        -OriginalPayloadFingerprintMatches $OriginalPayloadFingerprintMatches `
        -RemoveActionContractValid ([bool]$removeContract.Valid) `
        -AppId $script:Target.AppModuleId
    $appEntityObjectIds = @(Get-NormalizedGuidCandidates -Rows @($Components | Where-Object {
        [int]$_.componenttype -eq 1
    }) -PropertyName 'objectid')
    $referencePayloads = @($ReferenceComponents | ForEach-Object { $_.Payloads })
    [pscustomobject]@{
        SystemEntity = [pscustomobject]@{
            RowCount = @($entityRowsByName['entity']).Count
            LogicalNames = @($entityRowsByName['entity'] | ForEach-Object { [string]$_.logicalname } | Select-Object -Unique)
            UniqueIdCount = $systemEntityIds.Count
            ObjectTypeCodes = @($entityRowsByName['entity'] | ForEach-Object { $_.objecttypecode } | Where-Object { $null -ne $_ } | Select-Object -Unique)
            ComponentStates = @($entityRowsByName['entity'] | ForEach-Object { $_.componentstate } | Select-Object -Unique)
        }
        ApprovedTables = @($referenceEvidence | ForEach-Object {
            [pscustomobject]@{
                LogicalName = $_.LogicalName
                MetadataSurfaceFound = $_.MetadataFound
                EntityTableSurfaceFound = ($_.EntityTableRowCount -gt 0)
                EntityTableRowCount = $_.EntityTableRowCount
                EntityTableIdentityUnambiguous = $_.EntityTableIdentityUnambiguous
                LogicalNamesAgree = $_.LogicalNamesAgree
                MetadataObjectTypeCode = $_.MetadataObjectTypeCode
                EntityObjectTypeCodes = $_.EntityTableObjectTypeCodes
                ObjectTypeCodesAgree = $_.ObjectTypeCodesAgree
                EntityComponentStates = $_.EntityTableComponentStates
                MetadataIdEqualsEntityId = $_.MetadataIdEqualsEntityId
                PayloadEntityIdMatchesMetadataId = $_.PayloadMatchesMetadataId
                PayloadEntityIdMatchesEntityId = $_.PayloadMatchesEntityId
                PayloadEntityIdMatchesCurrentAppObjectId = Test-GuidValueMatchesAny `
                    -Value ([string]$_.PayloadEntityId) -Candidates $appEntityObjectIds
                PayloadEntityIdMatchesSystemEntityId = Test-GuidValueMatchesAny `
                    -Value ([string]$_.PayloadEntityId) -Candidates $systemEntityIds
            }
        })
        RemoveAppComponentsContract = $removeContract
        OriginalPayloadComponentCounts = [pscustomobject]@{
            Entity = @($referencePayloads | Where-Object { $_.'@odata.type' -ceq 'Microsoft.Dynamics.CRM.entity' }).Count
            Form = @($referencePayloads | Where-Object { $_.'@odata.type' -ceq 'Microsoft.Dynamics.CRM.systemform' }).Count
            View = @($referencePayloads | Where-Object { $_.'@odata.type' -ceq 'Microsoft.Dynamics.CRM.savedquery' }).Count
            Total = $referencePayloads.Count
        }
        Plan = $plan
    }
}

function New-RemoveWrongSystemEntityPayload {
    param(
        [Parameter(Mandatory = $true)][string]$AppId,
        [Parameter(Mandatory = $true)][string]$SystemEntityId
    )
    $body = [ordered]@{
        AppId = $AppId
        Components = @(
            [ordered]@{
                entityid = ConvertTo-NormalizedGuid -Value $SystemEntityId
                '@odata.type' = 'Microsoft.Dynamics.CRM.entity'
            }
        )
    }
    Assert-RemoveWrongSystemEntityPayload -Body $body -AppId $AppId -SystemEntityId $SystemEntityId
    $body
}

function Assert-RemoveWrongSystemEntityPayload {
    param(
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Body,
        [Parameter(Mandatory = $true)][string]$AppId,
        [Parameter(Mandatory = $true)][string]$SystemEntityId
    )
    if ([string]$Body.AppId -cne $AppId -or @($Body.Keys).Count -ne 2 -or
        @($Body.Components).Count -ne 1) {
        throw 'RemoveAppComponents must target the existing AppId with exactly one component.'
    }
    $component = @($Body.Components)[0]
    $keys = @($component.Keys | ForEach-Object { [string]$_ } | Sort-Object)
    if (($keys -join ',') -cne '@odata.type,entityid' -or
        [string]$component['@odata.type'] -cne 'Microsoft.Dynamics.CRM.entity' -or
        (ConvertTo-NormalizedGuid -Value ([string]$component.entityid)) -cne
            (ConvertTo-NormalizedGuid -Value $SystemEntityId)) {
        throw 'RemoveAppComponents must contain only the verified system entity reference.'
    }
}

function Assert-WrongSystemEntityRemovalPreflight {
    param([Parameter(Mandatory = $true)][object]$Snapshot)
    $counts = $Snapshot.RawAppComponentTypeCounts
    $plan = $Snapshot.EntityRootRepairEvidence.Plan
    $association = $Snapshot.DirectReferenceUiAssociationEvidence
    if ($counts.SiteMap -ne 1 -or $counts.Entity -ne 4 -or $counts.Form -ne 4 -or
        $counts.View -ne 4 -or $counts.Other -ne 0 -or $counts.Total -ne 13) {
        throw 'STATE_CHANGED: direct app component counts differ from the authorized baseline.'
    }
    if ($plan.RootClassification -cne 'WRONG_SYSTEM_ENTITY_ROOTS_CONFIRMED' -or
        -not $plan.AllComponentRecordIdsDistinct -or -not $plan.AllObjectIdsEqual -or
        @($plan.ProjectTableRootCounts.Values | Where-Object { $_ -ne 0 }).Count -gt 0 -or
        @($plan.CurrentComponents | Where-Object {
            -not $_.ObjectIdEqualsSystemEntityId -or
            $_.os_sr_ta -or $_.os_sr_pos -or $_.os_sr_csrc -or $_.os_sr_loc
        }).Count -ne 0) {
        throw 'STATE_CHANGED: current entity roots do not exactly match the confirmed wrong system-entity state.'
    }
    $system = $Snapshot.EntityRootRepairEvidence.SystemEntity
    if ($system.RowCount -ne 1 -or $system.UniqueIdCount -ne 1 -or
        @($system.LogicalNames).Count -ne 1 -or $system.LogicalNames[0] -cne 'entity' -or
        [string]::IsNullOrWhiteSpace($script:SystemEntityIdForRemoval)) {
        throw 'FAILED_VALIDATION: the system entity identity is missing or ambiguous.'
    }
    if (-not $Snapshot.EntityRootRepairEvidence.RemoveAppComponentsContract.Valid -or
        -not $Snapshot.EntityRootRepairEvidence.Plan.ReferenceIdentityComplete -or
        $Snapshot.ReferencePayloadFingerprint -cne $script:ApprovedReferenceUiPayloadFingerprint) {
        throw 'FAILED_VALIDATION: supported action contract, approved project IDs, or payload source did not validate.'
    }
    if ($Snapshot.AppModule.UniqueName -cne $script:Target.AppUniqueName -or
        $Snapshot.AppModule.Name -cne $script:Target.AppName -or
        [int]$Snapshot.AppModule.StateCode -ne 0 -or [int]$Snapshot.AppModule.ComponentState -ne 1 -or
        $Snapshot.Solution.UniqueName -cne $script:Target.SolutionUniqueName -or
        [bool]$Snapshot.Solution.IsManaged -or
        $Snapshot.SolutionPublisher.UniqueName -cne $script:Target.SolutionPublisherUniqueName -or
        $Snapshot.SolutionPublisher.CustomizationPrefix -cne 'os') {
        throw 'STATE_CHANGED: target Solution, Publisher, or adopted app identity/state changed.'
    }
    if ($Snapshot.SiteMap.Id -cne $script:Target.SiteMapId -or
        $Snapshot.SiteMap.UniqueName -cne $script:Target.SiteMapUniqueName -or
        -not $Snapshot.SiteMap.IsAppAware -or [int]$Snapshot.SiteMap.ComponentState -ne 0 -or
        -not $association.IntendedSiteMapPresentDirectly -or
        $association.SiteMapCount -ne 1 -or
        -not $association.AppAssociationMatchesForEveryComponent) {
        throw 'STATE_CHANGED: the existing Site Map or direct app association changed.'
    }
    $navigation = @($Snapshot.SiteMapNavigationBefore)
    if ($navigation.Count -ne 1 -or $navigation[0].AreaTitle -cne 'Area1' -or
        $navigation[0].GroupTitle -cne 'Group1' -or $navigation[0].Title -cne 'Subarea1' -or
        -not [string]::IsNullOrWhiteSpace([string]$navigation[0].Entity)) {
        throw 'STATE_CHANGED: Site Map is not the verified placeholder navigation.'
    }
    foreach ($asset in @($association.Assets)) {
        if (-not $asset.MainFormPresentDirectly -or $asset.MainFormDirectMatchCount -ne 1 -or
            -not $asset.ActiveViewPresentDirectly -or $asset.ActiveViewDirectMatchCount -ne 1) {
            throw 'PROTECTED_COMPONENT_CHANGED: an approved Main form or public view is missing or duplicated.'
        }
    }
    Assert-ApprovedAppRoles -Roles $Snapshot.AppModuleRoles
    if ($Snapshot.AppModuleRoles.Count -ne 2) {
        throw 'PROTECTED_COMPONENT_CHANGED: app role associations differ from the protected baseline.'
    }
}

function Get-WrongSystemEntityRemovalClassification {
    param(
        [Parameter(Mandatory = $true)][object]$Before,
        [Parameter(Mandatory = $true)][object]$After,
        [Nullable[int]]$WriteStatus,
        [bool]$WriteDispatched
    )
    $beforeRoles = ConvertTo-Json -InputObject @($Before.AppModuleRoles | Select-Object Name, IsManaged | Sort-Object Name) -Compress
    $afterRoles = ConvertTo-Json -InputObject @($After.AppModuleRoles | Select-Object Name, IsManaged | Sort-Object Name) -Compress
    $protectedChanged = $Before.SiteMap.Id -cne $After.SiteMap.Id -or
        $Before.SiteMap.UniqueName -cne $After.SiteMap.UniqueName -or
        $Before.SiteMap.SitemapXml -cne $After.SiteMap.SitemapXml -or
        [int]$Before.SiteMap.ComponentState -ne [int]$After.SiteMap.ComponentState -or
        $beforeRoles -cne $afterRoles -or
        @($After.DirectReferenceUiAssociationEvidence.Assets | Where-Object {
            -not $_.MainFormPresentDirectly -or $_.MainFormDirectMatchCount -ne 1 -or
            -not $_.ActiveViewPresentDirectly -or $_.ActiveViewDirectMatchCount -ne 1
        }).Count -gt 0 -or
        [int]$After.RawAppComponentTypeCounts.SiteMap -ne 1 -or
        [int]$After.RawAppComponentTypeCounts.Form -ne 4 -or
        [int]$After.RawAppComponentTypeCounts.View -ne 4 -or
        [int]$After.RawAppComponentTypeCounts.Other -ne 0 -or
        -not $After.DirectReferenceUiAssociationEvidence.IntendedSiteMapPresentDirectly -or
        $After.DirectReferenceUiAssociationEvidence.SiteMapCount -ne 1 -or
        -not $After.DirectReferenceUiAssociationEvidence.AppAssociationMatchesForEveryComponent -or
        $After.AppModule.UniqueName -cne $Before.AppModule.UniqueName -or
        [int]$After.AppModule.StateCode -ne [int]$Before.AppModule.StateCode -or
        [int]$After.AppModule.ComponentState -ne [int]$Before.AppModule.ComponentState
    if ($protectedChanged) { return 'PROTECTED_COMPONENT_CHANGED' }
    if ($WriteStatus -eq 401) { return 'FAILED_AUTH' }
    if ($WriteStatus -eq 403) { return 'FAILED_AUTHZ' }
    if ($WriteStatus -eq 429 -or $WriteStatus -ge 500) { return 'UNCERTAIN' }
    if ($WriteStatus -ge 400 -and $WriteStatus -lt 500) { return 'FAILED_VALIDATION' }
    $remaining = [int]$After.RawAppComponentTypeCounts.Entity
    $wrongRemaining = @($After.EntityRootRepairEvidence.Plan.CurrentComponents |
        Where-Object ObjectIdEqualsSystemEntityId).Count
    if ($WriteDispatched -and $null -eq $WriteStatus) { return 'UNCERTAIN' }
    if ($remaining -eq 0 -and $wrongRemaining -eq 0 -and
        [int]$After.RawAppComponentTypeCounts.Total -eq 9) { return 'WRONG_ROOTS_FULLY_REMOVED' }
    if ($remaining -gt 0 -and $remaining -lt 4 -and $wrongRemaining -eq $remaining) {
        return 'WRONG_ROOTS_PARTIALLY_REMOVED'
    }
    if ($remaining -eq 4 -and $wrongRemaining -eq 4 -and $WriteStatus -ge 200 -and $WriteStatus -lt 300) {
        return 'WRONG_ROOTS_NOT_REMOVED'
    }
    'UNCERTAIN'
}

function Assert-RemoveWrongSystemEntityWriteSequence {
    if ($script:RequestCounts.POST -ne 0 -or $script:RequestCounts.PATCH -ne 0 -or
        $script:WriteResults.Count -ne 0 -or $script:WritesStarted) {
        throw 'Removal mode permits exactly one RemoveAppComponents POST and no prior write.'
    }
}

function Get-RetrieveAppComponentsSafeSummary {
    param([object]$Response)
    $summaries = [System.Collections.Generic.List[object]]::new()
    $visited = [System.Collections.Generic.HashSet[int]]::new()
    $walk = {
        param([object]$Value)
        if ($null -eq $Value -or $Value -is [string] -or $Value.GetType().IsValueType) { return }
        $identity = [System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($Value)
        if (-not $visited.Add($identity)) { return }
        if ($Value -is [System.Collections.IDictionary]) {
            $properties = @($Value.Keys | ForEach-Object { [string]$_ })
            $logicalName = if ($Value.Contains('logicalname')) { [string]$Value['logicalname'] } else { $null }
            $name = if ($Value.Contains('name')) { [string]$Value['name'] } else { $null }
            $typeName = if ($Value.Contains('@odata.type')) { [string]$Value['@odata.type'] } else { $null }
            if ($logicalName -or $typeName -or @($properties | Where-Object { $_ -match '^(entityid|formid|savedqueryid|sitemapid|componenttype)$' }).Count) {
                $summaries.Add([pscustomobject]@{
                    ODataType = $typeName
                    AvailablePrimaryKeyFields = @($properties | Where-Object { $_ -in @('entityid', 'formid', 'savedqueryid', 'sitemapid') })
                    ComponentType = if ($Value.Contains('componenttype')) { $Value['componenttype'] } else { $null }
                    LogicalName = $logicalName
                    Name = $name
                    EntityIdPresent = $Value.Contains('entityid')
                    FormIdPresent = $Value.Contains('formid')
                    SavedQueryIdPresent = $Value.Contains('savedqueryid')
                    SiteMapIdPresent = $Value.Contains('sitemapid')
                })
            }
            foreach ($key in $Value.Keys) { & $walk $Value[$key] }
        }
        elseif ($Value -is [System.Collections.IEnumerable]) {
            foreach ($item in $Value) { & $walk $item }
        }
        else {
            $properties = @($Value.PSObject.Properties | ForEach-Object { $_.Name })
            $logicalName = [string](Get-PropertyValue -Object $Value -Name 'logicalname')
            $typeName = [string](Get-PropertyValue -Object $Value -Name '@odata.type')
            if ($logicalName -or $typeName -or @($properties | Where-Object { $_ -match '^(entityid|formid|savedqueryid|sitemapid|componenttype)$' }).Count) {
                $summaries.Add([pscustomobject]@{
                    ODataType = $typeName
                    AvailablePrimaryKeyFields = @($properties | Where-Object { $_ -in @('entityid', 'formid', 'savedqueryid', 'sitemapid') })
                    ComponentType = Get-PropertyValue -Object $Value -Name 'componenttype'
                    LogicalName = $logicalName
                    Name = [string](Get-PropertyValue -Object $Value -Name 'name')
                    EntityIdPresent = $properties -contains 'entityid'
                    FormIdPresent = $properties -contains 'formid'
                    SavedQueryIdPresent = $properties -contains 'savedqueryid'
                    SiteMapIdPresent = $properties -contains 'sitemapid'
                })
            }
            foreach ($property in $Value.PSObject.Properties) { & $walk $property.Value }
        }
    }
    & $walk $Response
    $summaries.ToArray()
}

function New-SafeStoppedExecutionSummary {
    param([Parameter(Mandatory = $true)][System.Management.Automation.ErrorRecord]$ErrorRecord)
    [ordered]@{
        Status = 'Stopped'
        Error = 'Operation stopped; raw exception omitted. Do not retry. Reconcile with GET before recovery.'
        ExceptionType = $ErrorRecord.Exception.GetType().Name
        FailedParameterName = if ($ErrorRecord.Exception.PSObject.Properties['ParameterName']) { [string]$ErrorRecord.Exception.ParameterName } else { $null }
        FailureLine = if ($ErrorRecord.InvocationInfo.ScriptLineNumber -gt 0) { $ErrorRecord.InvocationInfo.ScriptLineNumber } else { $null }
        FailedCommand = if ($ErrorRecord.Exception -is [System.Management.Automation.CommandNotFoundException]) { $ErrorRecord.Exception.CommandName } else { $null }
        Stage = $script:LastStage
        LastApiPath = if ($EntityRootRepairDiagnosticOnly) { '[SUPPRESSED]' } else { $script:LastPath }
        HttpStatus = $script:LastHttpStatus
        DataverseErrorCode = $script:LastErrorCode
        SafeError = $script:LastSafeError
        FirstFailingPredicate = $script:FirstFailingPredicate
        InnerExceptionCategory = if ($ErrorRecord.Exception.InnerException) { $ErrorRecord.Exception.InnerException.GetType().Name } else { $ErrorRecord.Exception.GetType().Name }
        EntityIdentityContractFailurePredicate = $script:IdentityContractFailurePredicate
        EntityResolutionDiagnostics = @($script:EntityResolutionDiagnostics)
        EntityResolutionClassification = $script:EntityResolutionClassification
        RetrieveAppComponentsEvidence = $script:RetrieveAppComponentsEvidence
        EntityRootRepairEvidence = $script:EntityRootRepairEvidence
        ReferencePayloadFingerprint = $script:PayloadFingerprintDiagnostic
        SafeExpectedValue = if ($script:FirstFailingPredicate) { 'Exactly one entity row per valid objectid; approved logical names exactly once' } else { $null }
        SafeObservedCategory = if ($script:EntityResolutionDiagnostics.Count) { @($script:EntityResolutionDiagnostics | ForEach-Object { $_.FailureCategory } | Where-Object { $_ }) -join ',' } else { $null }
        WritesMayHaveOccurred = $script:WritesStarted
        WriteResults = $script:WriteResults.ToArray()
        RequestCounts = [ordered]@{} + $script:RequestCounts
    }
}

function ConvertTo-SafeValidationIssueSummaries {
    param(
        [object[]]$Issues,
        [object[]]$NormalizedComponents = @()
    )
    @($Issues | ForEach-Object {
        $message = [string](Get-PropertyValue -Object $_ -Name 'Message')
        $message = [regex]::Replace($message, '[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}', '[GUID]')
        $message = [regex]::Replace($message, 'https?://\S+', '[URL]')
        $message = [regex]::Replace($message, '[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}', '[EMAIL]', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        $requiredComponents = @(Get-PropertyValue -Object $_ -Name 'RequiredComponents')
        $requiredSummaries = @($requiredComponents | ForEach-Object {
            $requiredType = Get-PropertyValue -Object $_ -Name 'ComponentType'
            $schemaName = [string](Get-PropertyValue -Object $_ -Name 'SchemaName')
            $resolutionStatus = 'UNRESOLVED'
            if ([int]$requiredType -eq 1 -and -not [string]::IsNullOrWhiteSpace($schemaName)) {
                $entityMatches = @($NormalizedComponents | Where-Object {
                    [int]$_.ComponentType -eq 1 -and $_.EntityLogicalName -ceq $schemaName
                })
                if ($entityMatches.Count -eq 1) { $resolutionStatus = 'SATISFIED' }
                elseif ($entityMatches.Count -gt 1) { $resolutionStatus = 'AMBIGUOUS' }
                else { $resolutionStatus = 'MISSING' }
            }
            [pscustomobject]@{
                DisplayName = Get-PropertyValue -Object $_ -Name 'DisplayName'
                SchemaName = $schemaName
                ComponentType = $requiredType
                ParentEntityName = Get-PropertyValue -Object $_ -Name 'ParentEntityName'
                ComponentIdPresent = -not [string]::IsNullOrWhiteSpace([string](Get-PropertyValue -Object $_ -Name 'ComponentId'))
                ResolutionStatus = $resolutionStatus
            }
        })
        $errorType = [string](Get-PropertyValue -Object $_ -Name 'ErrorType')
        $errorCode = [string](Get-PropertyValue -Object $_ -Name 'CRMErrorCode')
        $classification = if ($errorType -ceq 'Error') {
            'BLOCKING'
        }
        elseif (@($requiredSummaries | Where-Object { $_.ResolutionStatus -cne 'SATISFIED' }).Count -gt 0) {
            'UNRESOLVED_REQUIRED_COMPONENT'
        }
        elseif ($errorCode -ceq '-2147155691') {
            'NON_BLOCKING_FUNCTIONAL_WARNING'
        }
        elseif ($errorType -ceq 'Warning' -and $requiredSummaries.Count -gt 0) {
            'SATISFIED_NON_BLOCKING_WARNING'
        }
        else {
            'NON_BLOCKING_WARNING'
        }
        [pscustomobject]@{
            ErrorType = $errorType
            Message = $message
            ErrorCode = $errorCode
            DisplayName = Get-PropertyValue -Object $_ -Name 'DisplayName'
            ComponentType = Get-PropertyValue -Object $_ -Name 'ComponentType'
            ComponentSubType = Get-PropertyValue -Object $_ -Name 'ComponentSubType'
            ParentEntityName = Get-PropertyValue -Object $_ -Name 'ParentEntityName'
            ComponentIdPresent = -not [string]::IsNullOrWhiteSpace([string](Get-PropertyValue -Object $_ -Name 'ComponentId'))
            ParentEntityIdPresent = -not [string]::IsNullOrWhiteSpace([string](Get-PropertyValue -Object $_ -Name 'ParentEntityId'))
            RequiredComponents = $requiredSummaries
            Classification = $classification
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
    if ([string]$who.OrganizationId -cne $ExpectedOrganizationId -or [string]$who.UserId -ine $script:PacIdentity.UserId) {
        throw 'Dataverse WhoAmI identity does not match PAC and the expected organization.'
    }
    if ($script:ExpectedUserGuardNeedsPin) {
        [Environment]::SetEnvironmentVariable('BSO_RS_EXPECTED_USER_ID', [string]$who.UserId, 'Process')
        $script:ExpectedUserGuardNeedsPin = $false
    }
    if ([string]$who.UserId -ine [string]([Environment]::GetEnvironmentVariable('BSO_RS_EXPECTED_USER_ID', 'Process'))) {
        throw 'Dataverse WhoAmI identity does not match the process-scoped expected-user guard.'
    }

    $script:LastStage = 'Verify project Solution and Publisher'
    $solutionRows = @(Get-ODataRows -Path (New-CollectionPath -EntitySet 'solutions' -Select 'solutionid,uniquename,friendlyname,ismanaged,_publisherid_value' -Filter "uniquename eq '$($script:Target.SolutionUniqueName)'"))
    if ($solutionRows.Count -ne 1) { throw 'Target Solution is missing or not unique.' }
    $solution = $solutionRows[0]
    $solutionPublisher = Invoke-DataverseRequest -Method GET -Path "publishers($($solution._publisherid_value))?%24select=publisherid,uniquename,customizationprefix"
    if ([bool]$solution.ismanaged -or $solutionPublisher.uniquename -cne 'os_bso_rs_support' -or $solutionPublisher.customizationprefix -cne 'os') { throw 'Target Solution must be unmanaged and linked to the approved project Publisher.' }

    $script:LastStage = 'Read unpublished AppModule'
    $matchingApps = @(Get-ODataRows -Path (New-CollectionPath -EntitySet 'appmodules' -Select 'appmoduleid,appmoduleidunique,name,uniquename,statecode,componentstate' -Filter "uniquename eq '$($script:Target.AppUniqueName)'"))
    if ($matchingApps.Count -gt 1 -or
        ($matchingApps.Count -eq 1 -and $matchingApps[0].appmoduleid -cne $script:Target.AppModuleId)) {
        throw 'The published AppModule collection returned duplicate or conflicting srapp records.'
    }
    $app = Invoke-DataverseRequest -Method GET -Path "appmodules($($script:Target.AppModuleId))/Microsoft.Dynamics.CRM.RetrieveUnpublished()?%24select=appmoduleid,appmoduleidunique,name,uniquename,componentstate,statecode,statuscode,solutionid,publishedon,_publisherid_value"
    if ($app.appmoduleid -cne $script:Target.AppModuleId -or $app.appmoduleidunique -cne $script:Target.AppModuleIdUnique -or
        $app.uniquename -cne $script:Target.AppUniqueName -or $app.name -cne $script:Target.AppName) { throw 'Adopted AppModule identity mismatch.' }
    if ([int]$app.statecode -ne 0 -or [int]$app.componentstate -ne 1) { throw 'AppModule is not Active and Unpublished; stop.' }

    $script:LastStage = 'Read existing Site Map'
    $matchingSiteMaps = @(Get-ODataRows -Path (New-CollectionPath -EntitySet 'sitemaps' -Select 'sitemapid,sitemapnameunique,isappaware,componentstate' -Filter "sitemapnameunique eq '$($script:Target.SiteMapUniqueName)'"))
    if ($matchingSiteMaps.Count -ne 1 -or $matchingSiteMaps[0].sitemapid -cne $script:Target.SiteMapId) {
        throw 'The intended Site Map unique name does not resolve to exactly one existing record.'
    }
    $siteMap = Invoke-DataverseRequest -Method GET -Path "sitemaps($($script:Target.SiteMapId))?%24select=sitemapid,sitemapname,sitemapnameunique,isappaware,componentstate,ismanaged,sitemapxml"
    if ($siteMap.sitemapid -cne $script:Target.SiteMapId -or $siteMap.sitemapnameunique -cne $script:Target.SiteMapUniqueName -or -not $siteMap.isappaware) { throw 'Target Site Map identity mismatch.' }

    $script:LastStage = 'Resolve all approved reference-table components'
    $referenceComponents = @(Get-ReferenceComponentInventory)
    $script:ResolvedReferenceComponents = $referenceComponents

    $script:LastStage = 'Read Solution component membership'
    $solutionComponents = @(Get-ODataRows -Path (New-CollectionPath -EntitySet 'solutioncomponents' -Select 'solutioncomponentid,componenttype,objectid,rootsolutioncomponentid,rootcomponentbehavior,ismetadata,_solutionid_value' -Filter "_solutionid_value eq $($solution.solutionid)"))
    $appRoot = Assert-SingleAppModuleSolutionRoot -SolutionComponents $solutionComponents -AppModuleId $script:Target.AppModuleId
    $siteMapRoots = @($solutionComponents | Where-Object { [int]$_.componenttype -eq 62 })
    $siteMapRoot = @($siteMapRoots | Where-Object { ([string]$_.objectid).Trim('{}') -ieq $script:Target.SiteMapId })
    if ($siteMapRoots.Count -ne 1 -or $siteMapRoot.Count -ne 1) {
        throw 'App or unique existing Site Map Solution root membership mismatch.'
    }
    $referenceSolutionMembership = @(Assert-ReferenceTableSolutionMembership -SolutionComponents $solutionComponents -ReferenceComponents $referenceComponents)
    foreach ($reference in $referenceComponents) {
        $reference | Add-Member -NotePropertyName SolutionMembership -NotePropertyValue @(
            $referenceSolutionMembership | Where-Object { $_.LogicalName -ceq $reference.LogicalName }
        ) -Force
    }

    $script:LastStage = 'Read AppModule components'
    $rawComponents = @(Get-ODataRows -Path (New-CollectionPath -EntitySet 'appmodulecomponents' -Select 'appmodulecomponentid,_appmoduleidunique_value,componenttype,objectid,isdefault,ismetadata,rootappmodulecomponentid,rootcomponentbehavior' -Filter "_appmoduleidunique_value eq $($script:Target.AppModuleIdUnique)"))
    $directReferenceUiAssociationEvidence = Get-DirectReferenceUiAssociationEvidence `
        -Components $rawComponents -ReferenceComponents $referenceComponents `
        -SiteMapId $script:Target.SiteMapId -AppModuleIdUnique $script:Target.AppModuleIdUnique
    $script:LastStage = 'Verify AppModule entity identity contract'
    $metadata = Get-DataverseMetadataDocument
    $identityContract = $null
    $identityContractCheck = 'NOT_RUN'
    try {
        $identityContract = Assert-AppModuleEntityIdentityContract -Metadata $metadata
        $identityContractCheck = 'PASS'
    }
    catch {
        $identityContractCheck = 'FAIL'
        if (-not $script:FirstFailingPredicate) {
            $script:FirstFailingPredicate = if ($script:IdentityContractFailurePredicate) {
                $script:IdentityContractFailurePredicate
            }
            else {
                'ENTITIES_METADATA_IDENTITY_CONTRACT'
            }
        }
    }
    if ($EntityIdentityDiagnosticOnly -or $EntityRootRepairDiagnosticOnly -or $RemoveWrongSystemEntityRoots) {
        $script:EntityResolutionDiagnostics = @(Get-EntityResolutionDiagnosticRows -Components $rawComponents -ReferenceComponents $referenceComponents)
        $script:EntityResolutionClassification = Get-EntityResolutionAggregateClassification -Diagnostics $script:EntityResolutionDiagnostics
        $payloadsForFingerprint = @($referenceComponents | ForEach-Object { $_.Payloads })
        try {
            $script:PayloadFingerprintDiagnostic = Assert-ReferenceUiPayloadFingerprint -Payload $payloadsForFingerprint
        }
        catch {
            $script:PayloadFingerprintDiagnostic = 'MISMATCH'
            if (-not $script:FirstFailingPredicate) { $script:FirstFailingPredicate = 'REFERENCE_PAYLOAD_FINGERPRINT_MATCHES_APPROVED' }
        }
        if ($EntityRootRepairDiagnosticOnly -or $RemoveWrongSystemEntityRoots) {
            $script:LastStage = 'Build guarded entity-root reconciliation evidence'
            $script:EntityRootRepairEvidence = Get-EntityRootRepairEvidence -Components $rawComponents `
                -ReferenceComponents $referenceComponents `
                -OriginalPayloadFingerprintMatches ($script:PayloadFingerprintDiagnostic -ceq $script:ApprovedReferenceUiPayloadFingerprint) `
                -Metadata $metadata
        }
        $retrieveAppComponents = $null
        $retrieveAppComponentsStatus = $null
        try {
            $retrieveAppComponents = Invoke-DataverseRequest -Method GET -Path "RetrieveAppComponents(AppModuleId=$($script:Target.AppModuleId))"
            $retrieveAppComponentsStatus = if ($script:LastHttpStatus) { $script:LastHttpStatus } else { 200 }
        }
        catch {
            $retrieveAppComponentsStatus = $script:LastHttpStatus
        }
        $script:RetrieveAppComponentsEvidence = [pscustomobject]@{
            HttpStatus = $retrieveAppComponentsStatus
            RequestSucceeded = ($null -ne $retrieveAppComponents -and $retrieveAppComponentsStatus -ge 200 -and $retrieveAppComponentsStatus -lt 300)
            Availability = if ($retrieveAppComponentsStatus -eq 404) {
                'RETRIEVE_APP_COMPONENTS_UNAVAILABLE_FOR_CURRENT_UNPUBLISHED_APP'
            }
            elseif ($null -eq $retrieveAppComponentsStatus) {
                'UNKNOWN'
            }
            else {
                'RESPONDED'
            }
            Components = if ($retrieveAppComponents) { @(Get-RetrieveAppComponentsSafeSummary -Response $retrieveAppComponents) } else { @() }
        }
        $components = @()
        $entityRecords = @()
    }
    else {
        if (-not $identityContract) { throw 'AppModule entity identity metadata contract could not be verified.' }
        $entityRecords = @(Get-AppModuleEntityRecords -Components $rawComponents -IdentityContract $identityContract)
        $components = @(ConvertTo-NormalizedAppModuleComponents -Components $rawComponents -EntityRecords $entityRecords `
            -ReferenceComponents $referenceComponents -SiteMapId $script:Target.SiteMapId -AppModuleIdUnique $script:Target.AppModuleIdUnique)
    }
    $roleSnapshot = @(Get-AppModuleRoleSnapshot)
    $script:LastStage = 'Inspect unpublished Site Map layer'
    $siteMapDraft = Get-UnpublishedSiteMap
    $sourceXml = if ($siteMapDraft -and $siteMapDraft.sitemapxml) { [string]$siteMapDraft.sitemapxml } else { [string]$siteMap.sitemapxml }
    $proposedXml = New-ProposedSiteMapXml -SiteMapXml $sourceXml
    $script:LastStage = 'Validate AddAppComponents OData contract'
    $componentContract = Get-AppComponentsContract -Metadata $metadata
    $script:LastStage = 'Export and verify Solution associations'
    $export = Get-SolutionExportSummary
    $script:LastStage = 'Verify exported Site Map binding'
    if ($export.AppModuleSiteMapEntries.Count -ne 1 -or
        $export.AppModuleSiteMapEntries[0] -cne $script:Target.SiteMapUniqueName) {
        throw 'Target Solution export must contain exactly the srapp AppModuleSiteMap binding.'
    }
    $script:LastStage = 'Verify all reference components in Solution export'
    foreach ($reference in $referenceComponents) {
        if ($reference.MainForm.Id.Trim('{}').ToLowerInvariant() -notin $export.MainFormIds -or
            $reference.ActiveView.Id.Trim('{}').ToLowerInvariant() -notin $export.ActiveViewIds) {
            throw "Solution export does not contain the exact Main form and public view for $($reference.LogicalName)."
        }
    }
    if ($ReferenceUiCompositionOnly -or $EntityRootRepairDiagnosticOnly -or $RemoveWrongSystemEntityRoots) {
        Assert-ApprovedAppRoles -Roles $roleSnapshot
    }
    $script:LastStage = 'Read current app dependency validation'
    $validation = Invoke-DataverseRequest -Method GET -Path "ValidateApp(AppModuleId=$($script:Target.AppModuleId))"
    $validationResponse = Get-PropertyValue -Object $validation -Name 'AppValidationResponse'
    $validationIssues = @(Get-PropertyValue -Object $validationResponse -Name 'ValidationIssueList')
    $validationIssueSummaries = @(ConvertTo-SafeValidationIssueSummaries -Issues $validationIssues -NormalizedComponents $components)
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
        AppModuleCollectionMatchCount = $matchingApps.Count
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
        SiteMapSourceXml = $sourceXml
        ProposedSiteMapXml = $proposedXml
        SiteMapNeedsUpdate = ($sourceXml -cne $proposedXml)
        SiteMapNavigationBefore = @(Get-SiteMapSemanticNavigation -SiteMapXml $sourceXml)
        SiteMapNavigationAfter = @(Get-SiteMapSemanticNavigation -SiteMapXml $proposedXml)
        ReferenceComponents = $referenceComponents
        SolutionComponents = @($solutionComponents | ForEach-Object { [pscustomobject]@{ ComponentType = $_.componenttype; ObjectId = $_.objectid; RootComponentId = $_.rootsolutioncomponentid; RootComponentBehavior = $_.rootcomponentbehavior } })
        SolutionAppModuleRootCount = 1
        AppComponents = $components
        DirectReferenceUiAssociationEvidence = $directReferenceUiAssociationEvidence
        RawAppComponentTypeCounts = [ordered]@{
            SiteMap = @($rawComponents | Where-Object { [int]$_.componenttype -eq 62 }).Count
            Entity = @($rawComponents | Where-Object { [int]$_.componenttype -eq 1 }).Count
            Form = @($rawComponents | Where-Object { [int]$_.componenttype -eq 60 }).Count
            View = @($rawComponents | Where-Object { [int]$_.componenttype -eq 26 }).Count
            Other = @($rawComponents | Where-Object { [int]$_.componenttype -notin @(1, 26, 60, 62) }).Count
            Total = $rawComponents.Count
        }
        EntityIdentityContractMetadataCheck = $identityContractCheck
        EntityIdentityContractFailurePredicate = $script:IdentityContractFailurePredicate
        EntityResolutionDiagnostics = @($script:EntityResolutionDiagnostics)
        EntityResolutionClassification = $script:EntityResolutionClassification
        RetrieveAppComponentsEvidence = $script:RetrieveAppComponentsEvidence
        EntityRootRepairEvidence = $script:EntityRootRepairEvidence
        ReferencePayloadFingerprint = $script:PayloadFingerprintDiagnostic
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

function Invoke-SiteMapAssociationOnly {
    param([Parameter(Mandatory = $true)][object]$Snapshot)

    $beforeState = Assert-SiteMapOnlyComponentSet -Components $Snapshot.AppComponents
    $validationState = Get-SiteMapValidationState -AppValidation $Snapshot.AppValidation
    if ($Snapshot.SiteMap.UniqueName -cne $script:Target.SiteMapUniqueName -or
        -not $Snapshot.SiteMap.IsAppAware) {
        throw 'Existing Site Map identity failed the integrity guard.'
    }
    if ($Snapshot.AppModule.UniqueName -cne $script:Target.AppUniqueName -or
        $Snapshot.AppModule.Name -cne $script:Target.AppName -or
        [int]$Snapshot.AppModule.StateCode -ne 0 -or [int]$Snapshot.AppModule.ComponentState -ne 1) {
        throw 'Existing srapp identity or unpublished state changed; stop.'
    }

    if (-not $validationState.SiteMapErrorPresent) {
        if ($beforeState.SiteMapPresent -and $validationState.OtherBlockingErrorCount -eq 0) {
            return [pscustomobject]@{
                Status = 'ALREADY_ASSOCIATED'
                Preflight = $Snapshot
                SiteMapComponent = $beforeState
                RequestCounts = [ordered]@{} + $script:RequestCounts
                WriteResults = @()
            }
        }
        throw 'Current ValidateApp state does not show the exact Site Map blocker; stop without writing.'
    }
    if ($validationState.OtherBlockingErrorCount -gt 0) {
        throw 'ValidateApp returned an additional blocking error; stop before the authorized association.'
    }
    if ($beforeState.SiteMapPresent) {
        throw 'Site Map component is already present while ValidateApp still reports it missing; stop for reconciliation.'
    }

    $payload = Get-SiteMapComponentPayload -SiteMapId ([string]$Snapshot.SiteMap.Id)
    $body = [ordered]@{ AppId = [string]$Snapshot.AppModule.Id; Components = @($payload) }
    Assert-SiteMapAssociationPayload -Body $body

    if ($DryRun) {
        return [pscustomobject]@{
            Status = 'READY_TO_ASSOCIATE_SITE_MAP'
            Preflight = $Snapshot
            SiteMapComponent = $beforeState
            AddAppComponentsPayload = $body
            RequestCounts = [ordered]@{} + $script:RequestCounts
            WriteResults = @()
        }
    }

    $script:WritesAllowed = $true
    Invoke-DataverseRequest -Method POST -Path 'AddAppComponents' -Body $body | Out-Null
    $script:WritesAllowed = $false

    $after = Get-TargetSnapshot
    $afterState = Assert-SiteMapOnlyComponentSet -Components $after.AppComponents
    $afterValidationState = Get-SiteMapValidationState -AppValidation $after.AppValidation
    $appUnchanged = $after.AppModule.Id -ceq $Snapshot.AppModule.Id -and
        $after.AppModule.UniqueName -ceq $Snapshot.AppModule.UniqueName -and
        $after.AppModule.Name -ceq $Snapshot.AppModule.Name -and
        [int]$after.AppModule.StateCode -eq [int]$Snapshot.AppModule.StateCode -and
        [int]$after.AppModule.ComponentState -eq [int]$Snapshot.AppModule.ComponentState
    $siteMapUnchanged = $after.SiteMap.Id -ceq $Snapshot.SiteMap.Id -and
        $after.SiteMap.UniqueName -ceq $Snapshot.SiteMap.UniqueName -and
        $after.SiteMap.SitemapXml -ceq $Snapshot.SiteMap.SitemapXml -and
        [int]$after.SiteMap.ComponentState -eq [int]$Snapshot.SiteMap.ComponentState
    $rolesUnchanged = (ConvertTo-Json -InputObject @($after.AppModuleRoles) -Compress) -ceq
        (ConvertTo-Json -InputObject @($Snapshot.AppModuleRoles) -Compress)

    if (-not $appUnchanged -or -not $siteMapUnchanged -or -not $rolesUnchanged -or
        -not $afterState.SiteMapPresent -or $afterState.OtherComponentCount -ne 0) {
        throw 'Post-association GET reconciliation found changed or unintended app/Site Map state; stop without retry.'
    }
    if ($afterValidationState.SiteMapErrorPresent -or $afterValidationState.OtherBlockingErrorCount -gt 0) {
        throw 'Post-association ValidateApp did not clear the Site Map error or returned another blocking error.'
    }

    [pscustomobject]@{
        Status = 'VERIFIED_SITEMAP_ASSOCIATED'
        Preflight = $Snapshot
        PostWrite = $after
        SiteMapComponent = $afterState
        PostValidation = $after.AppValidation
        PublicationState = 'Unpublished; no publish endpoint invoked'
        RoleChanges = 0
        RetryCount = 0
        WriteResults = $script:WriteResults.ToArray()
        RequestCounts = [ordered]@{} + $script:RequestCounts
    }
}

function Invoke-ReferenceUiComposition {
    param([object]$Snapshot)
    $componentState = Assert-ReferenceUiComponentState -Components $Snapshot.AppComponents -RequireComposed
    $startingValidation = Get-ReferenceUiValidationState -AppValidation $Snapshot.AppValidation
    Assert-SiteMapSemanticNodePreservation -Before $Snapshot.SiteMapNavigationBefore -After $Snapshot.SiteMapNavigationAfter
    Assert-SiteMapHasNoDuplicateNavigationIds -SiteMapXml $Snapshot.ProposedSiteMapXml
    if ($startingValidation.ValidationSuccess -eq $false -or $startingValidation.SiteMapErrorCount -ne 0 -or
        $startingValidation.BlockingErrorCount -ne 0 -or $startingValidation.UnresolvedRequiredComponentCount -ne 0) {
        throw 'Pre-PATCH ValidateApp has a blocking error or unresolved required component.'
    }
    if ($Snapshot.AppModule.UniqueName -cne $script:Target.AppUniqueName -or
        $Snapshot.AppModule.Name -cne $script:Target.AppName -or
        [int]$Snapshot.AppModule.StateCode -ne 0 -or [int]$Snapshot.AppModule.ComponentState -ne 1) {
        throw 'The adopted srapp identity must remain Active and Unpublished.'
    }
    if ($Snapshot.SiteMap.UniqueName -cne $script:Target.SiteMapUniqueName -or
        -not $Snapshot.SiteMap.IsAppAware -or [int]$Snapshot.SiteMap.ComponentState -ne 0) {
        throw 'The existing Site Map identity/publication state differs from the verified Phase 2D.2 baseline.'
    }
    if (-not $Snapshot.SiteMapNeedsUpdate -and
        @($Snapshot.SiteMapNavigationAfter | Where-Object {
            $_.Title -in @('TA Directory', 'Positions', 'Candidate Sources', 'Locations') -and $_.Entity
        }).Count -ne 4) {
        throw 'Site Map reports no update is needed but the exact approved four-entry navigation is not present.'
    }
    if ($Snapshot.SiteMapNeedsUpdate -and [string]::IsNullOrWhiteSpace([string]$Snapshot.SiteMap.ETag)) {
        throw 'Existing Site Map ETag is missing; stop before any write.'
    }
    Assert-ApprovedAppRoles -Roles $Snapshot.AppModuleRoles
    $expectedRoleSnapshot = ConvertTo-Json -InputObject @($Snapshot.AppModuleRoles) -Compress

    if ($DryRun) {
        return [pscustomobject]@{
            Status = 'READY_FOR_SITEMAP_PATCH'
            Preflight = $Snapshot
            ComponentState = $componentState
            ValidationState = $startingValidation
            SiteMapSemanticDiff = [pscustomobject]@{
                Before = @($Snapshot.SiteMapNavigationBefore)
                After = @($Snapshot.SiteMapNavigationAfter)
                PatchRequired = [bool]$Snapshot.SiteMapNeedsUpdate
            }
            RequestCounts = [ordered]@{} + $script:RequestCounts
            WriteResults = @()
            RetryCount = 0
        }
    }

    if (-not $Snapshot.SiteMapNeedsUpdate) {
        throw 'The Site Map already matches the approved navigation; no PATCH is required.'
    }
    $script:LastStage = 'Fresh GET-only pre-PATCH gate'
    $fresh = Get-TargetSnapshot
    $freshComponents = Assert-ReferenceUiComponentState -Components $fresh.AppComponents -RequireComposed
    $freshValidation = Get-ReferenceUiValidationState -AppValidation $fresh.AppValidation
    $appUnchanged = $fresh.AppModule.Id -ceq $Snapshot.AppModule.Id -and
        $fresh.AppModule.IdUnique -ceq $Snapshot.AppModule.IdUnique -and
        $fresh.AppModule.UniqueName -ceq $script:Target.AppUniqueName -and
        $fresh.AppModule.Name -ceq $script:Target.AppName -and
        [int]$fresh.AppModule.StateCode -eq 0 -and [int]$fresh.AppModule.ComponentState -eq 1
    $rolesUnchanged = (ConvertTo-Json -InputObject @($fresh.AppModuleRoles) -Compress) -ceq $expectedRoleSnapshot
    if (-not $appUnchanged -or -not $rolesUnchanged -or
        $fresh.SiteMap.Id -cne $Snapshot.SiteMap.Id -or
        $fresh.SiteMap.UniqueName -cne $script:Target.SiteMapUniqueName -or
        -not $fresh.SiteMap.IsAppAware -or [int]$fresh.SiteMap.ComponentState -ne 0 -or
        $freshComponents.SiteMapCount -ne 1 -or
        $freshValidation.ValidationSuccess -eq $false -or $freshValidation.SiteMapErrorCount -ne 0 -or
        $freshValidation.BlockingErrorCount -ne 0 -or $freshValidation.UnresolvedRequiredComponentCount -ne 0) {
        throw 'Fresh pre-PATCH identity, composition, role, Site Map, or ValidateApp gate failed.'
    }
    Assert-SiteMapSemanticNodePreservation -Before $fresh.SiteMapNavigationBefore -After $fresh.SiteMapNavigationAfter
    Assert-SiteMapHasNoDuplicateNavigationIds -SiteMapXml $fresh.ProposedSiteMapXml
    if (-not $fresh.SiteMapNeedsUpdate -or [string]::IsNullOrWhiteSpace([string]$fresh.SiteMap.ETag)) {
        throw 'Fresh Site Map XML or ETag does not support the single authorized PATCH.'
    }

    $script:WritesAllowed = $true
    try {
        $script:LastStage = 'PATCH existing Site Map with fresh If-Match'
        Invoke-DataverseRequest -Method PATCH -Path "sitemaps($($script:Target.SiteMapId))" `
            -Body ([ordered]@{ sitemapxml = $fresh.ProposedSiteMapXml }) -ETag ([string]$fresh.SiteMap.ETag) | Out-Null
    }
    finally {
        $script:WritesAllowed = $false
    }

    $script:LastStage = 'GET-only post-PATCH reconciliation'
    $final = Get-TargetSnapshot
    $finalComponents = Assert-ReferenceUiComponentState -Components $final.AppComponents -RequireComposed
    $finalValidation = Get-ReferenceUiValidationState -AppValidation $final.AppValidation
    $finalRolesUnchanged = (ConvertTo-Json -InputObject @($final.AppModuleRoles) -Compress) -ceq $expectedRoleSnapshot
    $finalAppUnchanged = $final.AppModule.Id -ceq $Snapshot.AppModule.Id -and
        $final.AppModule.UniqueName -ceq $script:Target.AppUniqueName -and
        [int]$final.AppModule.StateCode -eq 0 -and [int]$final.AppModule.ComponentState -eq 1
    $finalNavigation = @($final.SiteMapNavigationBefore)
    Assert-SiteMapHasNoDuplicateNavigationIds -SiteMapXml $final.SiteMapSourceXml
    if ($finalNavigation.Count -ne 4 -or $final.SiteMapSourceXml -cne $fresh.ProposedSiteMapXml) {
        throw 'Post-PATCH Site Map read-back does not contain the exact transformed XML/navigation.'
    }
    for ($index = 0; $index -lt $script:Target.NavigationSubareas.Count; $index++) {
        $expectedNavigation = $script:Target.NavigationSubareas[$index]
        $actualNavigation = $finalNavigation[$index]
        if ($actualNavigation.AreaId -cne $script:Target.SiteMapNodeIds.Area -or
            $actualNavigation.AreaTitle -cne $script:Target.NavigationAreaTitle -or
            $actualNavigation.GroupId -cne $script:Target.SiteMapNodeIds.Group -or
            $actualNavigation.GroupTitle -cne $script:Target.NavigationGroupTitle -or
            $actualNavigation.SubAreaId -cne $expectedNavigation.NodeId -or
            $actualNavigation.Title -cne $expectedNavigation.Title -or
            $actualNavigation.Entity -cne $expectedNavigation.LogicalName) {
            throw 'Post-PATCH Site Map navigation differs from the approved four-table navigation.'
        }
    }
    Assert-SiteMapSemanticNodePreservation -Before $fresh.SiteMapNavigationBefore -After $finalNavigation
    $publishedLayerUnchanged = $final.SiteMap.SitemapXml -ceq $fresh.SiteMap.SitemapXml
    if (-not $finalAppUnchanged -or -not $finalRolesUnchanged -or -not $publishedLayerUnchanged -or
        $finalValidation.ValidationSuccess -eq $false -or $finalValidation.SiteMapErrorCount -ne 0 -or
        $finalValidation.BlockingErrorCount -ne 0 -or $finalValidation.UnresolvedRequiredComponentCount -ne 0) {
        throw 'Post-PATCH AppModule, role, Site Map, or ValidateApp reconciliation failed.'
    }

    [pscustomobject]@{
        Status = if ($finalValidation.FormViewSelectionWarningCount -gt 0) {
            'VERIFIED_COMPOSED_UNPUBLISHED_WITH_WARNINGS'
        }
        else {
            'VERIFIED_COMPOSED_UNPUBLISHED'
        }
        Preflight = $Snapshot
        FreshPrePatch = [pscustomobject]@{
            ComponentState = $freshComponents
            ValidationState = $freshValidation
            RolesUnchanged = $rolesUnchanged
            AppRemainsUnpublished = $appUnchanged
        }
        SiteMapSemanticDiff = [pscustomobject]@{
            Before = @($fresh.SiteMapNavigationBefore)
            After = $finalNavigation
            PreservedExistingNodeIds = $true
            PatchApplied = $true
        }
        FinalAppModule = $final.AppModule
        FinalSiteMap = [pscustomobject]@{
            Id = $final.SiteMap.Id
            UniqueName = $final.SiteMap.UniqueName
            ComponentState = $final.SiteMap.ComponentState
            PublishedLayerUnchanged = $publishedLayerUnchanged
            UnpublishedLayerContainsProposedNavigation = $final.SiteMapSourceXml -ceq $fresh.ProposedSiteMapXml
            DirectAssociationPresent = $finalComponents.SiteMapCount -eq 1
        }
        FinalComponentState = $finalComponents
        FinalValidation = $final.AppValidation
        RoleAssociations = @($final.AppModuleRoles | ForEach-Object { $_.Name })
        PublicationState = 'srapp remains Active/Unpublished; no publish operation invoked'
        RoleChanges = 0
        RetryCount = 0
        WriteResults = $script:WriteResults.ToArray()
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

function Invoke-RemoveWrongSystemEntityRoots {
    param([Parameter(Mandatory = $true)][object]$Preflight)

    try {
        Assert-WrongSystemEntityRemovalPreflight -Snapshot $Preflight
        Assert-RemoveWrongSystemEntityWriteSequence
    }
    catch {
        $classification = if ($_.Exception.Message -like 'STATE_CHANGED:*') {
            'STATE_CHANGED'
        }
        else {
            'FAILED_VALIDATION'
        }
        return [pscustomobject]@{
            Status = $classification
            WriteDispatched = $false
            WriteMayHaveOccurred = $false
            RequestCounts = [ordered]@{} + $script:RequestCounts
            RetryCount = 0
            SafeError = $_.Exception.Message
        }
    }

    $body = New-RemoveWrongSystemEntityPayload -AppId $script:Target.AppModuleId `
        -SystemEntityId $script:SystemEntityIdForRemoval
    $payloadFingerprint = Get-PayloadFingerprint -Payload @($body)
    $script:RemovalDispatchResult = [pscustomobject]@{
        Dispatched = $false
        HttpStatus = $null
        ErrorCode = $null
        RequestId = $null
        CorrelationId = $null
        SafeError = $null
    }
    $script:LastStage = 'Revalidate single RemoveAppComponents payload fingerprint'
    if ($payloadFingerprint -notmatch '^[0-9a-f]{64}$') {
        throw 'RemoveAppComponents request fingerprint is invalid; no request sent.'
    }
    Assert-RemoveWrongSystemEntityPayload -Body $body -AppId $script:Target.AppModuleId `
        -SystemEntityId $script:SystemEntityIdForRemoval
    Assert-RemoveWrongSystemEntityWriteSequence

    $script:WritesAllowed = $true
    try {
        $script:LastStage = 'Dispatch the one authorized RemoveAppComponents request'
        Invoke-DataverseRequest -Method POST -Path 'RemoveAppComponents' -Body $body | Out-Null
        $script:RemovalDispatchResult.Dispatched = $true
        $script:RemovalDispatchResult.HttpStatus = $script:LastHttpStatus
    }
    catch {
        $script:RemovalDispatchResult.Dispatched = $script:RequestCounts.POST -eq 1
        $script:RemovalDispatchResult.HttpStatus = $script:LastHttpStatus
        $script:RemovalDispatchResult.ErrorCode = $script:LastErrorCode
        $script:RemovalDispatchResult.RequestId = $script:LastRequestId
        $script:RemovalDispatchResult.CorrelationId = $script:LastCorrelationId
        $script:RemovalDispatchResult.SafeError = $script:LastSafeError
    }
    finally {
        $script:WritesAllowed = $false
    }
    if ($null -eq $script:RemovalDispatchResult.RequestId) {
        $script:RemovalDispatchResult.RequestId = $script:LastRequestId
        $script:RemovalDispatchResult.CorrelationId = $script:LastCorrelationId
    }

    $script:LastStage = 'GET-only reconciliation after the single remove attempt'
    try {
        $after = Get-TargetSnapshot
    }
    catch {
        return [pscustomobject]@{
            Status = 'UNCERTAIN'
            PreRemovalInventory = $Preflight.RawAppComponentTypeCounts
            PostRemovalInventory = $null
            WriteResult = $script:RemovalDispatchResult
            RemovePayload = [pscustomobject]@{
                ComponentCount = @($body.Components).Count
                ODataType = [string]$body.Components[0]['@odata.type']
                EntityIdPresent = -not [string]::IsNullOrWhiteSpace([string]$body.Components[0].entityid)
                Fingerprint = $payloadFingerprint
            }
            ReconciliationError = 'Post-write GET reconciliation failed; raw details omitted.'
            RequestCounts = [ordered]@{} + $script:RequestCounts
            RetryCount = 0
            WritesMayHaveOccurred = $script:WritesStarted
        }
    }

    $outcome = Get-WrongSystemEntityRemovalClassification -Before $Preflight -After $after `
        -WriteStatus $script:RemovalDispatchResult.HttpStatus -WriteDispatched $script:RemovalDispatchResult.Dispatched
    [pscustomobject]@{
        Status = $outcome
        WriteDispatched = $script:RemovalDispatchResult.Dispatched
        WriteMayHaveOccurred = $script:WritesStarted
        PreRemovalInventory = $Preflight.RawAppComponentTypeCounts
        PostRemovalInventory = $after.RawAppComponentTypeCounts
        RemainingEntityClassification = [pscustomobject]@{
            TotalEntityRows = [int]$after.RawAppComponentTypeCounts.Entity
            WrongSystemEntityRows = @($after.EntityRootRepairEvidence.Plan.CurrentComponents |
                Where-Object ObjectIdEqualsSystemEntityId).Count
            ProjectTableRoots = $after.EntityRootRepairEvidence.Plan.ProjectTableRootCounts
        }
        RemovePayload = [pscustomobject]@{
            ComponentCount = @($body.Components).Count
            ODataType = [string]$body.Components[0]['@odata.type']
            EntityIdPresent = -not [string]::IsNullOrWhiteSpace([string]$body.Components[0].entityid)
            Fingerprint = $payloadFingerprint
        }
        WriteResult = $script:RemovalDispatchResult
        ProtectedComponents = [pscustomobject]@{
            SiteMapPresent = $after.DirectReferenceUiAssociationEvidence.IntendedSiteMapPresentDirectly
            SiteMapXmlUnchanged = $after.SiteMap.SitemapXml -ceq $Preflight.SiteMap.SitemapXml
            FormsAndViewsPresent = @($after.DirectReferenceUiAssociationEvidence.Assets | Where-Object {
                -not $_.MainFormPresentDirectly -or $_.MainFormDirectMatchCount -ne 1 -or
                -not $_.ActiveViewPresentDirectly -or $_.ActiveViewDirectMatchCount -ne 1
            }).Count -eq 0
        }
        ValidateApp = [pscustomobject]@{
            ValidationSuccess = $after.AppValidation.ValidationSuccess
            BlockingErrors = $after.AppValidation.BlockingErrorCount
            Warnings = @($after.AppValidation.Issues)
            RequiredComponents = @($after.AppValidation.Issues | ForEach-Object { $_.RequiredComponents })
        }
        Roles = @($after.AppModuleRoles | ForEach-Object { $_.Name })
        AppState = [pscustomobject]@{
            UniqueName = $after.AppModule.UniqueName
            Active = ([int]$after.AppModule.StateCode -eq 0)
            Unpublished = ([int]$after.AppModule.ComponentState -eq 1)
        }
        SiteMapNavigation = @($after.SiteMapNavigationBefore | ForEach-Object {
            [pscustomobject]@{ Area = $_.AreaTitle; Group = $_.GroupTitle; Title = $_.Title; Entity = $_.Entity }
        })
        RequestCounts = [ordered]@{} + $script:RequestCounts
        RetryCount = 0
        PublishXml = 0
        AppPublish = 0
        RoleChanges = 0
        WritesMayHaveOccurred = $script:WritesStarted
    }
}

function Invoke-Main {
    $plan = Get-AppCompositionPlan
    if ($PlanOnly) {
        Write-Output ($plan | ConvertTo-Json -Depth 20 -Compress)
        return
    }
    if ($Apply) { Assert-ApplyAuthorization -Phrase $Confirmation -Reference $AuthorizationReference }
    $snapshot = Get-TargetSnapshot
    if ($RemoveWrongSystemEntityRoots) {
        $result = Invoke-RemoveWrongSystemEntityRoots -Preflight $snapshot
        Write-Output ($result | ConvertTo-Json -Depth 30 -Compress)
        return
    }
    if ($EntityRootRepairDiagnosticOnly) {
        $rootRepairPlan = $snapshot.EntityRootRepairEvidence.Plan
        $referenceAssets = @($snapshot.ReferenceComponents | ForEach-Object {
            $referenceAsset = $_
            $directAsset = @($snapshot.DirectReferenceUiAssociationEvidence.Assets |
                Where-Object { $_.LogicalName -ceq $referenceAsset.LogicalName } | Select-Object -First 1)
            [pscustomobject]@{
                LogicalName = $referenceAsset.LogicalName
                MainFormName = $referenceAsset.MainForm.Name
                MainFormType = $referenceAsset.MainForm.Type
                MainFormState = $referenceAsset.MainForm.ActivationState
                MainFormComponentState = $referenceAsset.MainForm.ComponentState
                PublicViewName = $referenceAsset.ActiveView.Name
                PublicView = -not [bool]$referenceAsset.ActiveView.IsPrivate
                ViewState = $referenceAsset.ActiveView.StateCode
                ViewComponentState = $referenceAsset.ActiveView.ComponentState
                DirectFormPresent = if ($directAsset.Count -eq 1) { $directAsset[0].MainFormPresentDirectly } else { $false }
                DirectViewPresent = if ($directAsset.Count -eq 1) { $directAsset[0].ActiveViewPresentDirectly } else { $false }
            }
        })
        $assetInventoryValid = $referenceAssets.Count -eq 4 -and @(
            $referenceAssets | Where-Object {
                -not $_.DirectFormPresent -or -not $_.DirectViewPresent -or
                $_.MainFormName -cne 'Information' -or [int]$_.MainFormType -ne 2 -or
                [int]$_.MainFormState -ne 1 -or [int]$_.MainFormComponentState -ne 0 -or
                -not $_.PublicView -or [int]$_.ViewState -ne 0 -or [int]$_.ViewComponentState -ne 0
            }
        ).Count -eq 0
        $directInventoryValid = $snapshot.RawAppComponentTypeCounts.Total -eq 13 -and
            $snapshot.RawAppComponentTypeCounts.SiteMap -eq 1 -and
            $snapshot.RawAppComponentTypeCounts.Entity -eq 4 -and
            $snapshot.RawAppComponentTypeCounts.Form -eq 4 -and
            $snapshot.RawAppComponentTypeCounts.View -eq 4 -and
            $snapshot.RawAppComponentTypeCounts.Other -eq 0 -and
            $snapshot.DirectReferenceUiAssociationEvidence.AppAssociationMatchesForEveryComponent
        $siteMapAssociationValid = $snapshot.DirectReferenceUiAssociationEvidence.IntendedSiteMapPresentDirectly -and
            $snapshot.SiteMap.UniqueName -ceq $script:Target.SiteMapUniqueName -and
            [bool]$snapshot.SiteMap.IsAppAware
        $appStateValid = $snapshot.AppModule.UniqueName -ceq $script:Target.AppUniqueName -and
            $snapshot.AppModule.Name -ceq $script:Target.AppName -and
            [int]$snapshot.AppModule.StateCode -eq 0 -and [int]$snapshot.AppModule.ComponentState -eq 1
        $validationHasNoBlockers = $snapshot.AppValidation.ValidationSuccess -eq $true -and
            $snapshot.AppValidation.BlockingErrorCount -eq 0
        $allRepairPreconditions = $directInventoryValid -and $assetInventoryValid -and
            $siteMapAssociationValid -and $appStateValid -and $validationHasNoBlockers
        $zeroEntityRootState = $snapshot.RawAppComponentTypeCounts.Total -eq 9 -and
            $snapshot.RawAppComponentTypeCounts.SiteMap -eq 1 -and
            $snapshot.RawAppComponentTypeCounts.Entity -eq 0 -and
            $snapshot.RawAppComponentTypeCounts.Form -eq 4 -and
            $snapshot.RawAppComponentTypeCounts.View -eq 4 -and
            $snapshot.RawAppComponentTypeCounts.Other -eq 0 -and
            $snapshot.DirectReferenceUiAssociationEvidence.AppAssociationMatchesForEveryComponent -and
            @($rootRepairPlan.ProjectTableRootCounts.Values | Where-Object { $_ -ne 0 }).Count -eq 0 -and
            $assetInventoryValid -and $siteMapAssociationValid -and $appStateValid -and $validationHasNoBlockers
        $finalClassification = if ($zeroEntityRootState) {
            'ZERO_ENTITY_ROOTS_CURRENTLY'
        }
        elseif ($rootRepairPlan.RootClassification -eq 'WRONG_SYSTEM_ENTITY_ROOTS_CONFIRMED') {
            if ($rootRepairPlan.RepairPlanStatus -eq 'READY' -and $allRepairPreconditions) {
                'REPAIR_PLAN_READY'
            }
            else {
                'WRONG_ROOTS_CONFIRMED_REPAIR_AMBIGUOUS'
            }
        }
        elseif ($rootRepairPlan.RootClassification -eq 'CORRECT_PROJECT_TABLE_ROOTS') {
            'CURRENT_ROOTS_ACTUALLY_CORRECT'
        }
        elseif ($rootRepairPlan.RootClassification -eq 'MIXED_ROOT_STATE') {
            'MIXED_ROOT_STATE'
        }
        else {
            'BLOCKED_IDENTITY_EVIDENCE'
        }
        Write-Output ([ordered]@{
            Status = 'ENTITY_ROOT_REPAIR_DIAGNOSTIC_COMPLETE_NO_WRITE'
            EnvironmentGuards = [pscustomobject]@{
                TargetMatched = $true
                EnvironmentNameMatched = $true
                OrganizationMatched = $true
            }
            IdentityChecks = $snapshot.IdentityChecks
            Solution = [pscustomobject]@{
                UniqueName = $snapshot.Solution.UniqueName
                Unmanaged = -not [bool]$snapshot.Solution.IsManaged
                Publisher = $snapshot.SolutionPublisher.UniqueName
                Prefix = $snapshot.SolutionPublisher.CustomizationPrefix
            }
            AppModule = [pscustomobject]@{
                Name = $snapshot.AppModule.Name
                UniqueName = $snapshot.AppModule.UniqueName
                Active = [int]$snapshot.AppModule.StateCode -eq 0
                Unpublished = [int]$snapshot.AppModule.ComponentState -eq 1
            }
            DirectComponentCounts = $snapshot.RawAppComponentTypeCounts
            DirectAssociation = $snapshot.DirectReferenceUiAssociationEvidence
            PreflightGates = [pscustomobject]@{
                DirectInventoryValid = $directInventoryValid
                ReferenceAssetsValid = $assetInventoryValid
                SiteMapAssociationValid = $siteMapAssociationValid
                AppStateValid = $appStateValid
                ValidateAppNoBlockingErrors = $validationHasNoBlockers
                AllRepairPreconditions = $allRepairPreconditions
            }
            Roles = @($snapshot.AppModuleRoles | ForEach-Object { $_.Name })
            SiteMap = [pscustomobject]@{
                UniqueName = $snapshot.SiteMap.UniqueName
                AppAware = [bool]$snapshot.SiteMap.IsAppAware
                ComponentState = $snapshot.SiteMap.ComponentState
                ETagPresent = -not [string]::IsNullOrWhiteSpace([string]$snapshot.SiteMap.ETag)
                NavigationBefore = @($snapshot.SiteMapNavigationBefore | ForEach-Object {
                    [pscustomobject]@{ Area = $_.AreaTitle; Group = $_.GroupTitle; Title = $_.Title; Entity = $_.Entity }
                })
                ProposedNavigationAfter = @($snapshot.SiteMapNavigationAfter | ForEach-Object {
                    [pscustomobject]@{ Area = $_.AreaTitle; Group = $_.GroupTitle; Title = $_.Title; Entity = $_.Entity }
                })
                ProposedUpdateNeeded = [bool]$snapshot.SiteMapNeedsUpdate
            }
            EntityResolution = @($snapshot.EntityResolutionDiagnostics)
            EntityResolutionClassification = $snapshot.EntityResolutionClassification
            FirstFailingPredicate = $script:FirstFailingPredicate
            OriginalPayloadFingerprint = $snapshot.ReferencePayloadFingerprint
            RootRepairEvidence = $snapshot.EntityRootRepairEvidence
            FinalClassification = $finalClassification
            ValidateApp = [pscustomobject]@{
                Calls = 1
                ValidationSuccess = $snapshot.AppValidation.ValidationSuccess
                BlockingErrors = $snapshot.AppValidation.BlockingErrorCount
                Warnings = @($snapshot.AppValidation.Issues)
            }
            RetrieveAppComponents = $snapshot.RetrieveAppComponentsEvidence
            ReferenceAssets = $referenceAssets
            RequestCounts = [ordered]@{} + $script:RequestCounts
            RetryCount = 0
            WriteResults = @()
            WritesMayHaveOccurred = $script:WritesStarted
        } | ConvertTo-Json -Depth 40 -Compress)
        return
    }
    if ($EntityIdentityDiagnosticOnly) {
        Write-Output ([ordered]@{
            Status = 'DIAGNOSTIC_COMPLETE_NO_WRITE'
            Preflight = $snapshot
            FirstFailingPredicate = $script:FirstFailingPredicate
            RequestCounts = [ordered]@{} + $script:RequestCounts
            RetryCount = 0
            WritesMayHaveOccurred = $script:WritesStarted
        } | ConvertTo-Json -Depth 40 -Compress)
        return
    }
    if ($SiteMapAssociationOnly) {
        $result = Invoke-SiteMapAssociationOnly -Snapshot $snapshot
        $result | Add-Member -NotePropertyName Mode -NotePropertyValue $(if ($Apply) { 'Site Map association Apply' } else { 'Site Map association DryRun; GET-only' })
        Write-Output ($result | ConvertTo-Json -Depth 30 -Compress)
        return
    }
    if ($ReferenceUiCompositionOnly) {
        $result = Invoke-ReferenceUiComposition -Snapshot $snapshot
        $result | Add-Member -NotePropertyName Mode -NotePropertyValue $(if ($Apply) { 'Phase 2D.3 Apply; two-write maximum; no publish' } else { 'Phase 2D.3 DryRun; GET-only' })
        Write-Output ($result | ConvertTo-Json -Depth 30 -Compress)
        return
    }
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
        New-SafeStoppedExecutionSummary -ErrorRecord $_ | ConvertTo-Json -Depth 20 -Compress | Write-Output
        exit 1
    }
    finally {
        $script:AccessToken = $null
        $script:AccessTokenExpiresOn = [DateTimeOffset]::MinValue
        $script:WritesAllowed = $false
    }
}