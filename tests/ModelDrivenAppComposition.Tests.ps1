#requires -Version 7.4
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path $PSScriptRoot '../scripts/Configure-BsoRsModelDrivenApp.ps1'
$script:Passed = 0
$script:ExternalCalls = 0

function Assert-Test {
    param([bool]$Condition, [string]$Name)
    if (-not $Condition) { throw "FAIL: $Name" }
    $script:Passed++
}

function Assert-Rejected {
    param([scriptblock]$Action, [string]$Name, [string]$Pattern)
    $rejected = $false
    try { & $Action | Out-Null }
    catch {
        if ($Pattern -and $_.Exception.Message -notmatch $Pattern) { throw }
        $rejected = $true
    }
    Assert-Test $rejected $Name
}

function Invoke-RestMethod { $script:ExternalCalls++; throw 'Synthetic tests must not access the network.' }
function Invoke-WebRequest { $script:ExternalCalls++; throw 'Synthetic tests must not access the network.' }
function Get-AzAccessToken { $script:ExternalCalls++; throw 'Synthetic tests must not acquire tokens.' }
function pac { $script:ExternalCalls++; throw 'Synthetic tests must not invoke PAC.' }

$defaultPlan = (& $scriptPath) | ConvertFrom-Json
$explicitPlan = (& $scriptPath -PlanOnly) | ConvertFrom-Json
Assert-Test ($defaultPlan.Mode -like 'PlanOnly*' -and $explicitPlan.Mode -like 'PlanOnly*') 'PlanOnly is the default and explicit offline mode'
Assert-Test ($defaultPlan.MaximumWriteRequests -eq 2 -and $defaultPlan.OrderedWriteOperations.Count -eq 2) 'Bounded two-operation write plan'
Assert-Test (-not $defaultPlan.PublishXmlOrPublishAll -and -not $defaultPlan.RoleAndAuditChanges -and $defaultPlan.AutomaticRetries -eq 0) 'No publication, role/audit operations, or automatic retries in plan'
Assert-Test ($defaultPlan.ExistingSiteMapBinding.SiteMapUniqueName -ceq 'srapp' -and -not $defaultPlan.ExistingSiteMapBinding.AddSiteMapComponent) 'Preserve existing SiteMap unique-name binding'
Assert-Test ($defaultPlan.Target.ReferenceTables -join ',' -ceq 'os_sr_ta,os_sr_pos,os_sr_csrc,os_sr_loc') 'Plan only the four approved reference tables'
Assert-Test ($defaultPlan.ProposedNavigation.SubAreas.Count -eq 4 -and $defaultPlan.ProposedNavigation.Area -ceq 'Settings') 'Plan Settings navigation for exactly four approved subareas'
Assert-Test (-not $defaultPlan.AddAppComponentsPayload.ExactLiveIdsResolved -and $defaultPlan.LiveComponentResolutionRequired) 'PlanOnly does not fabricate live component IDs'
Assert-Test ($script:ExternalCalls -eq 0) 'PlanOnly makes no auth, PAC, or network calls'

. $scriptPath -PlanOnly
$syntheticTarget = [pscustomobject]@{
    AppModuleId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
    TableMetadataId = '11111111-1111-4111-8111-111111111111'
    MainFormId = '22222222-2222-4222-8222-222222222222'
    ActiveViewId = '33333333-3333-4333-8333-333333333333'
    SiteMapId = '44444444-4444-4444-8444-444444444444'
}
$syntheticAppRoot = [pscustomobject]@{ componenttype = 80; objectid = $syntheticTarget.AppModuleId }
$acceptedAppRoot = Assert-SingleAppModuleSolutionRoot -SolutionComponents @($syntheticAppRoot) -AppModuleId $syntheticTarget.AppModuleId
Assert-Test ($acceptedAppRoot.objectid -ceq $syntheticTarget.AppModuleId) 'Accept exactly one matching AppModule root in the target Solution'
Assert-Rejected {
    Assert-SingleAppModuleSolutionRoot -SolutionComponents @($syntheticAppRoot, $syntheticAppRoot) -AppModuleId $syntheticTarget.AppModuleId
} 'Reject duplicate AppModule roots in the target Solution' 'exactly one AppModule root'
Assert-Rejected {
    Assert-SingleAppModuleSolutionRoot -SolutionComponents @($syntheticAppRoot) -AppModuleId 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
} 'Reject a Solution AppModule root that differs from the adopted srapp' 'exactly one AppModule root'
$syntheticReference = [pscustomobject]@{
    LogicalName = 'os_sr_ta'
    TableMetadataId = $syntheticTarget.TableMetadataId
    MainForm = [pscustomobject]@{ Id = $syntheticTarget.MainFormId }
    ActiveView = [pscustomobject]@{ Id = $syntheticTarget.ActiveViewId }
}
$syntheticReferenceSolutionComponents = @(
    [pscustomobject]@{ componenttype = 1; objectid = $syntheticTarget.TableMetadataId }
)
$syntheticMembership = @(Assert-ReferenceTableSolutionMembership -SolutionComponents $syntheticReferenceSolutionComponents -ReferenceComponents @($syntheticReference))
Assert-Test ($syntheticMembership.Count -eq 1 -and $syntheticMembership[0].ComponentRole -ceq 'Table' -and $syntheticMembership[0].MatchCount -eq 1) 'Require exact table Solution membership'
Assert-Rejected {
    Assert-ReferenceTableSolutionMembership -SolutionComponents @() -ReferenceComponents @($syntheticReference)
} 'Reject missing table Solution membership' 'lacks exactly one table Solution component'
Assert-Rejected {
    Assert-ReferenceTableSolutionMembership -SolutionComponents (@($syntheticReferenceSolutionComponents) + @($syntheticReferenceSolutionComponents[0])) -ReferenceComponents @($syntheticReference)
} 'Reject duplicate table Solution membership' 'lacks exactly one table Solution component'
$syntheticExportXml = [xml]'<Root><systemform><formid>{22222222-2222-4222-8222-222222222222}</formid></systemform><savedquery><savedqueryid>{33333333-3333-4333-8333-333333333333}</savedqueryid></savedquery></Root>'
$syntheticExportForms = @(Get-ExportGuidIds -Document $syntheticExportXml -ParentName 'systemform' -IdName 'formid')
$syntheticExportViews = @(Get-ExportGuidIds -Document $syntheticExportXml -ParentName 'savedquery' -IdName 'savedqueryid')
Assert-Test ($syntheticTarget.MainFormId -in $syntheticExportForms -and $syntheticTarget.ActiveViewId -in $syntheticExportViews) 'Extract exact Main form and public view IDs from Solution XML'
$payloads = @(Get-AppComponentPayloads -Target $syntheticTarget)
Assert-Test ($payloads.Count -eq 3) 'Exactly three existing app components are planned'
$fingerprintTestPayload = @([ordered]@{
    entityid = '11111111-1111-4111-8111-111111111111'
    '@odata.type' = 'Microsoft.Dynamics.CRM.entity'
})
$fingerprintTestVector = '00d78eda60324eb2545ee0915f974209286d7bfbc49881f67f2772a4ab52e50b'
$actualFingerprint = Assert-ReferenceUiPayloadFingerprint -Payload $fingerprintTestPayload -ExpectedFingerprint $fingerprintTestVector
Assert-Test ($actualFingerprint -ceq $fingerprintTestVector) 'Compute the deterministic approved-payload SHA-256 fingerprint'
Assert-Rejected {
    Assert-ReferenceUiPayloadFingerprint -Payload $fingerprintTestPayload -ExpectedFingerprint 'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff'
} 'Reject a payload with a mismatched approved fingerprint' 'fingerprint differs'
Assert-Test ($payloads[0].'@odata.type' -ceq 'Microsoft.Dynamics.CRM.entity' -and $payloads[0].entityid -ceq $syntheticTarget.TableMetadataId) 'Entity component uses primary-key property and OData type'
Assert-Test ($payloads[1].'@odata.type' -ceq 'Microsoft.Dynamics.CRM.systemform' -and $payloads[1].formid -ceq $syntheticTarget.MainFormId) 'Form component uses primary-key property and OData type'
Assert-Test ($payloads[2].'@odata.type' -ceq 'Microsoft.Dynamics.CRM.savedquery' -and $payloads[2].savedqueryid -ceq $syntheticTarget.ActiveViewId) 'View component uses primary-key property and OData type'
Assert-Test (@($payloads | Where-Object { $_.'@odata.type' -ceq 'Microsoft.Dynamics.CRM.sitemap' }).Count -eq 0) 'Existing SiteMap binding is not duplicated in AddAppComponents'
$siteMapPayload = Get-SiteMapComponentPayload -SiteMapId $syntheticTarget.SiteMapId
$siteMapBody = [ordered]@{ AppId = $syntheticTarget.AppModuleId; Components = @($siteMapPayload) }
Assert-SiteMapAssociationPayload -Body $siteMapBody -Target $syntheticTarget
Assert-Test ($siteMapBody.Components.Count -eq 1 -and $siteMapBody.Components[0].sitemapid -ceq $syntheticTarget.SiteMapId -and
    $siteMapBody.Components[0].'@odata.type' -ceq 'Microsoft.Dynamics.CRM.sitemap') 'Build exactly one typed existing Site Map component'
$extraSiteMapComponentBody = [ordered]@{ AppId = $syntheticTarget.AppModuleId; Components = @($siteMapPayload, $payloads[0]) }
Assert-Rejected { Assert-SiteMapAssociationPayload -Body $extraSiteMapComponentBody -Target $syntheticTarget } 'Reject table mixed into Site Map-only request' 'exactly one component'
$duplicateSiteMapBody = [ordered]@{ AppId = $syntheticTarget.AppModuleId; Components = @($siteMapPayload, $siteMapPayload) }
Assert-Rejected { Assert-SiteMapAssociationPayload -Body $duplicateSiteMapBody -Target $syntheticTarget } 'Reject duplicate Site Map component' 'exactly one component'
$wrongSiteMapBody = [ordered]@{ AppId = $syntheticTarget.AppModuleId; Components = @((Get-SiteMapComponentPayload -SiteMapId $syntheticTarget.TableMetadataId)) }
Assert-Rejected { Assert-SiteMapAssociationPayload -Body $wrongSiteMapBody -Target $syntheticTarget } 'Reject wrong existing Site Map ID' 'differs from the single verified existing Site Map'
$validationWithSiteMapError = Get-SiteMapValidationState -AppValidation ([pscustomobject]@{ Issues = @(
    [pscustomobject]@{ ErrorType = 'Error'; Message = 'App does not contain Site Map' },
    [pscustomobject]@{ ErrorType = 'Warning'; Message = 'App does not reference at least one entity' }
) })
Assert-Test ($validationWithSiteMapError.SiteMapErrorPresent -and $validationWithSiteMapError.OtherBlockingErrorCount -eq 0) 'Recognize exact Site Map blocker while allowing unrelated warnings'
$validationWithoutSiteMapError = Get-SiteMapValidationState -AppValidation ([pscustomobject]@{ Issues = @([pscustomobject]@{ ErrorType = 'Warning'; Message = 'No component is referenced' }) })
Assert-Test (-not $validationWithoutSiteMapError.SiteMapErrorPresent) 'Recognize when Site Map validation blocker is already absent'
$syntheticBody = [ordered]@{ AppId = $syntheticTarget.AppModuleId; Components = $payloads }
Assert-AppComponentsPayload -Body $syntheticBody -Target $syntheticTarget
Assert-Test $true 'Allow exact synthetic AppId and three approved component payloads'
$wrongAppBody = [ordered]@{ AppId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'; Components = $payloads }
Assert-Rejected { Assert-AppComponentsPayload -Body $wrongAppBody -Target $syntheticTarget } 'Reject wrong AppId' 'fixed AppId'
$extraComponentBody = [ordered]@{ AppId = $syntheticTarget.AppModuleId; Components = @($payloads) + @($payloads[0]) }
Assert-Rejected { Assert-AppComponentsPayload -Body $extraComponentBody -Target $syntheticTarget } 'Reject extra component' 'component count'

Assert-Rejected { Assert-ApplyAuthorization -Phrase 'wrong phrase' -Reference 'synthetic-approval' } 'Reject incorrect Apply phrase' 'confirmation phrase'
Assert-Rejected { Assert-ApplyAuthorization -Phrase 'APPLY PHASE 2D IN VN LMV IT' -Reference '' } 'Reject missing Apply reference' 'authorization reference'
$authorizationAccepted = $true
try { Assert-ApplyAuthorization -Phrase 'APPLY PHASE 2D IN VN LMV IT' -Reference 'synthetic-approval' } catch { $authorizationAccepted = $false }
Assert-Test $authorizationAccepted 'Accept only explicit phrase plus recorded synthetic authorization reference'
Assert-Rejected { Assert-AppValidationAllowsApply -AppValidation ([pscustomobject]@{ Issues = @([pscustomobject]@{ ErrorType = 'Error'; Message = 'Missing sitemap' }) }) } 'Block Apply on a pre-existing ValidateApp error' 'blocking error outside the approved component plan'
$warningValidationAccepted = $true
try { Assert-AppValidationAllowsApply -AppValidation ([pscustomobject]@{ Issues = @([pscustomobject]@{ ErrorType = 'Warning'; Message = 'No component is referenced' }) }) } catch { $warningValidationAccepted = $false }
Assert-Test $warningValidationAccepted 'Allow only non-blocking validation warnings through the Apply gate'
Assert-Rejected { Invoke-DataverseRequest -Method PATCH -Path 'sitemaps(synthetic-id)' -Body ([ordered]@{ sitemapxml = '<SiteMap />' }) } 'Block SiteMap PATCH without Apply' 'Write blocked'
Assert-Rejected { Invoke-DataverseRequest -Method POST -Path AddAppComponents -Body ([ordered]@{}) } 'Block AddAppComponents without Apply' 'Write blocked'
Assert-Test ($script:ExternalCalls -eq 0) 'Blocked write routes never call authentication or network'

$fixtureXml = '<SiteMap IntroducedVersion="7.0.0.0"><Area Id="area_test" ResourceId="resource_area" ShowGroups="true"><Titles><Title LCID="1033" Title="Area1"/><Title LCID="1041" Title="Area Localized"/></Titles><Group Id="group_test" ResourceId="resource_group" IsProfile="false"><Titles><Title LCID="1033" Title="Group1"/></Titles><SubArea Id="subarea_9787e9c1" Client="Web" AvailableOffline="true"><Titles><Title LCID="1033" Title="Subarea1"/></Titles></SubArea></Group></Area></SiteMap>'
$testIds = @{ Area = 'area_test'; Group = 'group_test'; SubArea = 'subarea_9787e9c1' }
$proposedXml = New-ProposedSiteMapXml -SiteMapXml $fixtureXml -ExpectedNodeIds $testIds
[xml]$proposed = $proposedXml
$area = $proposed.SelectSingleNode("//*[local-name()='Area']")
$group = $proposed.SelectSingleNode("//*[local-name()='Group']")
$subArea = $proposed.SelectSingleNode("//*[local-name()='SubArea']")
Assert-Test ($area.GetAttribute('Id') -ceq 'area_test' -and $group.GetAttribute('Id') -ceq 'group_test' -and $subArea.GetAttribute('Id') -ceq 'subarea_9787e9c1') 'Preserve existing navigation node IDs'
Assert-Test ($area.SelectSingleNode("./*[local-name()='Titles']/*[local-name()='Title'][@LCID='1033']").GetAttribute('Title') -ceq 'Settings') 'Set Area title'
Assert-Test ($area.SelectSingleNode("./*[local-name()='Titles']/*[local-name()='Title'][@LCID='1041']").GetAttribute('Title') -ceq 'Area Localized') 'Preserve unrelated localized title'
Assert-Test ($group.SelectSingleNode("./*[local-name()='Titles']/*[local-name()='Title'][@LCID='1033']").GetAttribute('Title') -ceq 'Administration') 'Set Group title'
Assert-Test ($subArea.SelectSingleNode("./*[local-name()='Titles']/*[local-name()='Title'][@LCID='1033']").GetAttribute('Title') -ceq 'TA Directory' -and $subArea.GetAttribute('Entity') -ceq 'os_sr_ta') 'Set entity SubArea title and target'
Assert-Test ($area.GetAttribute('ResourceId') -ceq 'resource_area' -and $group.GetAttribute('IsProfile') -ceq 'false' -and $subArea.GetAttribute('AvailableOffline') -ceq 'true') 'Preserve unrelated SiteMap metadata'
$allSubAreas = @($proposed.SelectNodes("//*[local-name()='SubArea']"))
Assert-Test ($allSubAreas.Count -eq 4) 'Create exactly four approved navigation entries'
Assert-Test ($allSubAreas[1].GetAttribute('Id') -ceq 'subarea_02d1f8a7' -and $allSubAreas[1].GetAttribute('Entity') -ceq 'os_sr_pos') 'Create Positions navigation entry'
Assert-Test ($allSubAreas[2].GetAttribute('Id') -ceq 'subarea_03c7b614' -and $allSubAreas[2].GetAttribute('Entity') -ceq 'os_sr_csrc') 'Create Candidate Sources navigation entry'
Assert-Test ($allSubAreas[3].GetAttribute('Id') -ceq 'subarea_04e9c321' -and $allSubAreas[3].GetAttribute('Entity') -ceq 'os_sr_loc') 'Create Locations navigation entry'
$idempotentXml = New-ProposedSiteMapXml -SiteMapXml $proposedXml -ExpectedNodeIds $testIds
Assert-Test ($idempotentXml -ceq $proposedXml) 'Four-entry SiteMap transformation is idempotent'

$extraGroupXml = $fixtureXml.Replace('</Area>', '<Group Id="unexpected"><Titles><Title LCID="1033" Title="Keep"/></Titles></Group></Area>')
Assert-Rejected { New-ProposedSiteMapXml -SiteMapXml $extraGroupXml -ExpectedNodeIds $testIds } 'Reject unexpected SiteMap groups' 'Group structure/ID'
$wrongEntityXml = $fixtureXml.Replace('<SubArea Id="subarea_9787e9c1"', '<SubArea Entity="account" Id="subarea_9787e9c1"')
Assert-Rejected { New-ProposedSiteMapXml -SiteMapXml $wrongEntityXml -ExpectedNodeIds $testIds } 'Reject conflicting existing entity target' 'different entity'
$wrongIds = @{ Area = 'wrong'; Group = 'group_test'; SubArea = 'subarea_9787e9c1' }
Assert-Rejected { New-ProposedSiteMapXml -SiteMapXml $fixtureXml -ExpectedNodeIds $wrongIds } 'Reject unexpected Area ID' 'Area structure/ID'

$script:ResolvedReferenceComponents = @(
    foreach ($table in @('os_sr_ta', 'os_sr_pos', 'os_sr_csrc', 'os_sr_loc')) {
        $ordinal = [array]::IndexOf(@('os_sr_ta', 'os_sr_pos', 'os_sr_csrc', 'os_sr_loc'), $table) + 1
        $tableId = '{0:x8}-0000-4000-8000-{1:x12}' -f $ordinal, $ordinal
        $formId = '{0:x8}-1000-4000-8000-{1:x12}' -f $ordinal, $ordinal
        $viewId = '{0:x8}-2000-4000-8000-{1:x12}' -f $ordinal, $ordinal
        [pscustomobject]@{
            LogicalName = $table
            TableMetadataId = $tableId
            MainForm = [pscustomobject]@{ Id = $formId }
            ActiveView = [pscustomobject]@{ Id = $viewId }
            Payloads = @(
                [ordered]@{ entityid = $tableId; '@odata.type' = 'Microsoft.Dynamics.CRM.entity' }
                [ordered]@{ formid = $formId; '@odata.type' = 'Microsoft.Dynamics.CRM.systemform' }
                [ordered]@{ savedqueryid = $viewId; '@odata.type' = 'Microsoft.Dynamics.CRM.savedquery' }
            )
        }
    }
)
$allExpectedPayloads = @(Get-AppComponentPayloads)
$emptyState = Assert-ComponentStateForApply -ExistingComponents @()
Assert-Test ($allExpectedPayloads.Count -eq 12 -and $emptyState.MissingCount -eq 12 -and $emptyState.NonePresent) 'Resolve all twelve table/form/view components as absent'
$firstExpected = $allExpectedPayloads[0]
$onePresent = [pscustomobject]@{ componenttype = 1; objectid = $firstExpected.entityid }
$partialState = Assert-ComponentStateForApply -ExistingComponents @($onePresent)
Assert-Test (-not $partialState.AllPresent -and $partialState.MissingCount -eq 11 -and @($partialState.ComponentStates | Where-Object State -eq 'ALREADY_PRESENT').Count -eq 1) 'Classify partial existing composition and plan only missing components'
$exactState = Assert-ComponentStateForApply -ExistingComponents @(
    foreach ($reference in $script:ResolvedReferenceComponents) {
        foreach ($payload in $reference.Payloads) {
            $componentType = switch ([string]$payload['@odata.type']) {
                'Microsoft.Dynamics.CRM.entity' { 1 }
                'Microsoft.Dynamics.CRM.systemform' { 60 }
                'Microsoft.Dynamics.CRM.savedquery' { 26 }
            }
            $key = @($payload.Keys | Where-Object { $_ -ne '@odata.type' })[0]
            [pscustomobject]@{ componenttype = $componentType; objectid = $payload[$key] }
        }
    }
)
Assert-Test ($exactState.AllPresent -and $exactState.MissingCount -eq 0) 'Recognize all twelve exact components as present'
Assert-Rejected { Assert-ComponentStateForApply -ExistingComponents @([pscustomobject]@{ componenttype = 1; objectid = 'unexpected' }) } 'Reject unexpected app component' 'Unexpected AppModule components'
$script:ResolvedReferenceComponents = @()
$script:MissingAppComponentPayloads = @()

$metadataFixture = [xml]@'
<edmx:Edmx xmlns:edmx="http://docs.oasis-open.org/odata/ns/edmx" Version="4.0">
    <edmx:DataServices>
        <Schema xmlns="http://docs.oasis-open.org/odata/ns/edm" Namespace="Microsoft.Dynamics.CRM">
            <Action Name="AddAppComponents">
                <Parameter Name="AppId" Type="Edm.Guid" Nullable="false" />
                <Parameter Name="Components" Type="Collection(mscrm.crmbaseentity)" Nullable="false" />
            </Action>
            <EntityType Name="entity" BaseType="Microsoft.Dynamics.CRM.crmbaseentity">
                <Key><PropertyRef Name="entityid" /></Key>
                <Property Name="entityid" Type="Edm.Guid" Nullable="false" />
            </EntityType>
            <EntityType Name="sitemap"><Key><PropertyRef Name="sitemapid" /></Key></EntityType>
            <EntityType Name="systemform"><Key><PropertyRef Name="formid" /></Key></EntityType>
            <EntityType Name="savedquery"><Key><PropertyRef Name="savedqueryid" /></Key></EntityType>
        </Schema>
        <Schema xmlns="http://docs.oasis-open.org/odata/ns/edm" Namespace="Microsoft.Dynamics.CRM">
            <EntityContainer Name="Organization">
                <EntitySet Name="entities" EntityType="Microsoft.Dynamics.CRM.entity" />
            </EntityContainer>
        </Schema>
    </edmx:DataServices>
</edmx:Edmx>
'@
$contract = Get-AppComponentsContract -Metadata $metadataFixture
Assert-Test ($contract.AppIdType -ceq 'Edm.Guid' -and $contract.ComponentsType -ceq 'Collection(mscrm.crmbaseentity)') 'Validate AddAppComponents parameters from OData metadata'
Assert-Test ($contract.ComponentEntityTypes.Count -eq 4) 'Validate all required component record types'
Assert-Test ($contract.EntityType.PrimaryKey -ceq 'entityid' -and
    $contract.EntityType.PrimaryKeyType -ceq 'Edm.Guid' -and
    $contract.EntityType.EntitySetName -ceq 'entities' -and
    $contract.EntityType.BaseType -ceq 'Microsoft.Dynamics.CRM.crmbaseentity') `
    'Capture live entity key, GUID type, entity set, and base type'
$wrongContract = [xml]$metadataFixture.OuterXml.Replace('PropertyRef Name="sitemapid"','PropertyRef Name="wrongid"')
Assert-Rejected { Get-AppComponentsContract -Metadata $wrongContract } 'Reject invalid SiteMap primary key contract' 'lacks expected key sitemapid'
Assert-Test ($script:ExternalCalls -eq 0) 'All PlanOnly and metadata contract tests remain offline'

$phasePlan = (& $scriptPath -PlanOnly -ReferenceUiCompositionOnly) | ConvertFrom-Json
Assert-Test ($ReferenceUiCompositionOnly -eq $false -and -not (Test-AllowsProcessExpectedUserPin)) 'Do not permit process user pinning in generic composition mode'
$ReferenceUiCompositionOnly = $true
Assert-Test (Test-AllowsProcessExpectedUserPin) 'Allow process-only expected-user pin for guarded Phase 2D.3 identity verification'
$ReferenceUiCompositionOnly = $false
$EntityIdentityDiagnosticOnly = $true
Assert-Test (Test-AllowsProcessExpectedUserPin) 'Allow process-only expected-user pin for guarded read-only identity diagnostics'
$EntityIdentityDiagnosticOnly = $false
$EntityRootRepairDiagnosticOnly = $true
Assert-Test (Test-AllowsProcessExpectedUserPin) 'Allow process-only expected-user pin for guarded Phase 2D.3G read-only diagnostics'
$EntityRootRepairDiagnosticOnly = $false
$AddTaEntityCanary = $true
Assert-Test (Test-AllowsProcessExpectedUserPin) 'Allow identity-pinned process guard for the authorized TA-only canary'
$AddTaEntityCanary = $false
Assert-Test ($phasePlan.MaximumWriteRequests -eq 2 -and $phasePlan.AutomaticRetries -eq 0) 'Phase 2D.3 plan caps writes at two and retries at zero'
Assert-Test ($phasePlan.OrderedWriteOperations[0].Method -ceq 'POST' -and
    $phasePlan.OrderedWriteOperations[0].ComponentCount -eq 12 -and
    $phasePlan.OrderedWriteOperations[1].Method -ceq 'PATCH') 'Phase 2D.3 writes components before the Site Map PATCH'
Assert-Test ($phasePlan.OrderedWriteOperations[0].ComponentTypes -join ',' -ceq '1,60,26' -and
    $phasePlan.ProposedNavigation.SubAreas.Count -eq 4) 'Phase 2D.3 limits composition to four approved table/form/view sets'
Assert-Test (($phasePlan.ProposedNavigation.SubAreas | ForEach-Object { $_.MainForm + '|' + $_.PublicView }) -join ',' -ceq
    'Information|Active TA Directories,Information|Active Positions,Information|Active Candidate Sources,Information|Active Locations') 'Plan only the four approved Main forms and public views'

$ReferenceUiCompositionOnly = $true
$script:ResolvedReferenceComponents = @(
    foreach ($table in @('os_sr_ta', 'os_sr_pos', 'os_sr_csrc', 'os_sr_loc')) {
        $ordinal = [array]::IndexOf(@('os_sr_ta', 'os_sr_pos', 'os_sr_csrc', 'os_sr_loc'), $table) + 1
        $tableId = '{0:x8}-0000-4000-8000-{1:x12}' -f $ordinal, $ordinal
        $formId = '{0:x8}-1000-4000-8000-{1:x12}' -f $ordinal, $ordinal
        $viewId = '{0:x8}-2000-4000-8000-{1:x12}' -f $ordinal, $ordinal
        [pscustomobject]@{
            LogicalName = $table
            TableMetadataId = $tableId
            MainForm = [pscustomobject]@{ Id = $formId }
            ActiveView = [pscustomobject]@{ Id = $viewId }
            Payloads = @(
                [ordered]@{ entityid = $tableId; '@odata.type' = 'Microsoft.Dynamics.CRM.entity' }
                [ordered]@{ formid = $formId; '@odata.type' = 'Microsoft.Dynamics.CRM.systemform' }
                [ordered]@{ savedqueryid = $viewId; '@odata.type' = 'Microsoft.Dynamics.CRM.savedquery' }
            )
        }
    }
)
$referencePayloads = @(Get-ReferenceUiComponentPayloads)
$referenceBody = [ordered]@{ AppId = $script:Target.AppModuleId; Components = $referencePayloads }
Assert-ReferenceUiCompositionPayload -Body $referenceBody
Assert-Test ($referenceBody.Components.Count -eq 12 -and
    @($referenceBody.Components | Where-Object { $_.'@odata.type' -ceq 'Microsoft.Dynamics.CRM.entity' }).Count -eq 4 -and
    @($referenceBody.Components | Where-Object { $_.'@odata.type' -ceq 'Microsoft.Dynamics.CRM.systemform' }).Count -eq 4 -and
    @($referenceBody.Components | Where-Object { $_.'@odata.type' -ceq 'Microsoft.Dynamics.CRM.savedquery' }).Count -eq 4) 'Payload contains exactly four tables, four forms, and four views'
$originalSecondFormId = $script:ResolvedReferenceComponents[0].Payloads[1].formid
$script:ResolvedReferenceComponents[0].Payloads[1].formid = $script:ResolvedReferenceComponents[0].Payloads[0].entityid
$duplicateIdBody = [ordered]@{ AppId = $script:Target.AppModuleId; Components = @(Get-ReferenceUiComponentPayloads) }
Assert-Rejected { Assert-ReferenceUiCompositionPayload -Body $duplicateIdBody } 'Reject duplicate IDs across component types' 'duplicate component'
$script:ResolvedReferenceComponents[0].Payloads[1].formid = $originalSecondFormId
$mixedReferenceBody = [ordered]@{ AppId = $script:Target.AppModuleId; Components = @($referencePayloads) + @((Get-SiteMapComponentPayload)) }
Assert-Rejected { Assert-ReferenceUiCompositionPayload -Body $mixedReferenceBody } 'Reject Site Map mixed into the 12 reference components' 'exactly twelve'
$shortReferenceBody = [ordered]@{ AppId = $script:Target.AppModuleId; Components = @($referencePayloads | Select-Object -First 11) }
Assert-Rejected { Assert-ReferenceUiCompositionPayload -Body $shortReferenceBody } 'Reject incomplete 11-component payload' 'exactly twelve'

$syntheticEntityRecords = [System.Collections.Generic.List[object]]::new()
$rawComposedComponents = [System.Collections.Generic.List[object]]::new()
$rawComposedComponents.Add([pscustomobject]@{
    appmodulecomponentid = 'aaaaaaaa-0000-4000-8000-000000000001'
    _appmoduleidunique_value = $script:Target.AppModuleIdUnique
    componenttype = 62
    objectid = $script:Target.SiteMapId
    isdefault = $false
    ismetadata = $false
    rootappmodulecomponentid = $null
    rootcomponentbehavior = $null
})
$entityOrdinal = 0
foreach ($reference in $script:ResolvedReferenceComponents) {
    $entityOrdinal++
    $entityId = 'bbbbbbbb-0000-4000-8000-{0:D12}' -f $entityOrdinal
    $entityComponentId = 'cccccccc-0000-4000-8000-{0:D12}' -f $entityOrdinal
    $syntheticEntityRecords.Add([pscustomobject]@{
        entityid = $entityId
        logicalname = $reference.LogicalName
        name = $reference.LogicalName
        objecttypecode = 11000 + $entityOrdinal
    })
    $rawComposedComponents.Add([pscustomobject]@{
        appmodulecomponentid = $entityComponentId
        _appmoduleidunique_value = $script:Target.AppModuleIdUnique
        componenttype = 1
        objectid = $entityId
        isdefault = $false
        ismetadata = $false
        rootappmodulecomponentid = $null
        rootcomponentbehavior = $null
    })
    foreach ($payload in @($reference.Payloads | Where-Object { $_.'@odata.type' -ne 'Microsoft.Dynamics.CRM.entity' })) {
        $componentType = if ($payload.'@odata.type' -ceq 'Microsoft.Dynamics.CRM.systemform') { 60 } else { 26 }
        $key = @($payload.Keys | Where-Object { $_ -ne '@odata.type' })[0]
        $formOrViewId = [string]$payload[$key]
        $rawComposedComponents.Add([pscustomobject]@{
            appmodulecomponentid = if ($componentType -eq 60) { 'dddddddd-0000-4000-8000-{0:D12}' -f $entityOrdinal } else { 'eeeeeeee-0000-4000-8000-{0:D12}' -f $entityOrdinal }
            _appmoduleidunique_value = $script:Target.AppModuleIdUnique
            componenttype = $componentType
            objectid = $formOrViewId
            isdefault = $false
            ismetadata = $false
            rootappmodulecomponentid = $null
            rootcomponentbehavior = $null
        })
    }
}
$composedUiComponents = @(ConvertTo-NormalizedAppModuleComponents -Components $rawComposedComponents.ToArray() `
    -EntityRecords $syntheticEntityRecords.ToArray() -ReferenceComponents $script:ResolvedReferenceComponents `
    -SiteMapId $script:Target.SiteMapId -AppModuleIdUnique $script:Target.AppModuleIdUnique)
$composedUiState = Assert-ReferenceUiComponentState -Components $composedUiComponents -RequireComposed
Assert-Test ($composedUiState.SiteMapCount -eq 1 -and $composedUiState.TableCount -eq 4 -and
    $composedUiState.MainFormCount -eq 4 -and $composedUiState.PublicViewCount -eq 4 -and
    $composedUiState.TotalComponentCount -eq 13 -and
    @($composedUiComponents | Where-Object { $_.ComponentType -eq 1 -and $_.RootClassification -eq 'UNKNOWN' }).Count -eq 4) 'Normalize distinct entity/component IDs and accept unknown root fields'
Assert-Test (@($composedUiComponents | Where-Object {
    $_.ComponentType -eq 1 -and $_.ComponentId -cne $_.ObjectId
}).Count -eq 4) 'AppModule component IDs may differ from referenced entity IDs'
$entityObjectIds = @($composedUiComponents | Where-Object { $_.ComponentType -eq 1 } | ForEach-Object { $_.ObjectId })
$metadataIds = @($script:ResolvedReferenceComponents | ForEach-Object { $_.TableMetadataId })
Assert-Test (@($entityObjectIds | Where-Object { $_ -in $metadataIds }).Count -eq 0) 'Entity IDs may differ from EntityDefinitions MetadataId'
$siteMapComponent = @($composedUiComponents | Where-Object { $_.ComponentType -eq 62 })[0]
Assert-Rejected { Assert-ReferenceUiComponentState -Components @() } 'Reject missing starting Site Map association' 'exactly the existing Site Map'
Assert-Rejected { Assert-ReferenceUiComponentState -Components (@($composedUiComponents) + @([pscustomobject]@{ ComponentType = 1; EntityLogicalName = 'os_sr_unexpected'; ObjectId = 'ffffffff-0000-4000-8000-000000000001' })) -RequireComposed } 'Reject unexpected final entity logical name' 'approved table logical name'
Assert-Rejected { Assert-ReferenceUiComponentState -Components (@($composedUiComponents) + @($siteMapComponent)) -RequireComposed } 'Reject duplicate Site Map component' 'exactly the existing Site Map'

$wrongLogicalNameRecords = @($syntheticEntityRecords.ToArray())
$wrongLogicalNameRecords[0] = [pscustomobject]@{
    entityid = $wrongLogicalNameRecords[0].entityid
    logicalname = 'os_sr_wrong'
    name = 'Wrong'
    objecttypecode = $wrongLogicalNameRecords[0].objecttypecode
}
Assert-Rejected {
    ConvertTo-NormalizedAppModuleComponents -Components $rawComposedComponents.ToArray() -EntityRecords $wrongLogicalNameRecords `
        -ReferenceComponents $script:ResolvedReferenceComponents -SiteMapId $script:Target.SiteMapId -AppModuleIdUnique $script:Target.AppModuleIdUnique
} 'Reject an unapproved entity logical name' 'unapproved table logical name'
$unresolvedEntityRecords = @($syntheticEntityRecords.ToArray() | Select-Object -Skip 1)
Assert-Rejected {
    ConvertTo-NormalizedAppModuleComponents -Components $rawComposedComponents.ToArray() -EntityRecords $unresolvedEntityRecords `
        -ReferenceComponents $script:ResolvedReferenceComponents -SiteMapId $script:Target.SiteMapId -AppModuleIdUnique $script:Target.AppModuleIdUnique
} 'Reject an unresolved entity objectid' 'did not resolve uniquely'
$duplicateLogicalNameRecords = @($syntheticEntityRecords.ToArray())
$duplicateLogicalNameRecords[1] = [pscustomobject]@{
    entityid = $duplicateLogicalNameRecords[1].entityid
    logicalname = $duplicateLogicalNameRecords[0].logicalname
    name = $duplicateLogicalNameRecords[1].name
    objecttypecode = $duplicateLogicalNameRecords[1].objecttypecode
}
Assert-Rejected {
    ConvertTo-NormalizedAppModuleComponents -Components $rawComposedComponents.ToArray() -EntityRecords $duplicateLogicalNameRecords `
        -ReferenceComponents $script:ResolvedReferenceComponents -SiteMapId $script:Target.SiteMapId -AppModuleIdUnique $script:Target.AppModuleIdUnique
} 'Reject duplicate normalized entity logical names' 'duplicate table logical name'

$identityContract = [pscustomobject]@{ EntitySet = 'entities'; PrimaryKey = 'entityid' }
$resolverComponent = [pscustomobject]@{ componenttype = 1; objectid = 'bbbbbbbb-0000-4000-8000-000000000001' }
$resolverEntity = [pscustomobject]@{
    entityid = $resolverComponent.objectid
    logicalname = 'os_sr_ta'
    name = 'TA Directory'
    objecttypecode = 11005
}
$originalDataverseRequest = (Get-Command Invoke-DataverseRequest -CommandType Function).ScriptBlock
$script:EntityResolverRequests = [System.Collections.Generic.List[object]]::new()
$script:EntityResolverResponseRows = @($resolverEntity)
$script:EntityResolverFailure = $false
Set-Item -Path Function:Invoke-DataverseRequest -Value {
    param([string]$Method, [string]$Path, [object]$Body, [string]$ETag)
    $script:EntityResolverRequests.Add([pscustomobject]@{ Method = $Method; Path = $Path; Body = $Body })
    if ($script:EntityResolverFailure) { throw 'Synthetic HTTP 400 from entities collection.' }
    [pscustomobject]@{ value = @($script:EntityResolverResponseRows) }
}
try {
    $resolvedEntity = @(Get-AppModuleEntityRecords -Components @($resolverComponent) -IdentityContract $identityContract)
    Assert-Test ($resolvedEntity.Count -eq 1 -and $resolvedEntity[0].logicalname -ceq 'os_sr_ta') 'Resolve one entity record through entities RetrieveMultiple'
    Assert-Test ($script:EntityResolverRequests.Count -eq 1 -and
        $script:EntityResolverRequests[0].Method -ceq 'GET' -and
        $script:EntityResolverRequests[0].Path -match '^entities\?') 'Use GET on the entities collection, not entity-by-ID'
    $decodedEntityPath = [Uri]::UnescapeDataString([string]$script:EntityResolverRequests[0].Path)
    Assert-Test ($decodedEntityPath -match '\$filter=entityid eq bbbbbbbb-0000-4000-8000-000000000001') 'Filter entities by the validated component objectid'
    Assert-Test ($decodedEntityPath -match '\$select=entityid,logicalname,name,objecttypecode') 'Select entity identity and required display/type fields'
    Assert-Test (@($script:EntityResolverRequests | Where-Object Method -ne 'GET').Count -eq 0) 'Entity resolution issues no writes'
    Assert-Test ($resolvedEntity[0].logicalname -cne [string]$script:ResolvedReferenceComponents[0].TableMetadataId) 'Normalize through logicalname without MetadataId fallback'

    $script:EntityResolverResponseRows = @()
    Assert-Rejected {
        Get-AppModuleEntityRecords -Components @($resolverComponent) -IdentityContract $identityContract
    } 'Fail closed when entity RetrieveMultiple returns zero rows' 'exactly one is required'
    $script:EntityResolverResponseRows = @($resolverEntity, $resolverEntity)
    Assert-Rejected {
        Get-AppModuleEntityRecords -Components @($resolverComponent) -IdentityContract $identityContract
    } 'Fail closed when entity RetrieveMultiple returns multiple rows' 'exactly one is required'
    $script:EntityResolverFailure = $true
    Assert-Rejected {
        Get-AppModuleEntityRecords -Components @($resolverComponent) -IdentityContract $identityContract
    } 'Fail closed on entities collection HTTP 400' 'Synthetic HTTP 400'
    Assert-Test (@($script:EntityResolverRequests | Where-Object Method -ne 'GET').Count -eq 0) 'Resolver failure paths remain GET-only'
}
finally {
    Set-Item -Path Function:Invoke-DataverseRequest -Value $originalDataverseRequest
}

$script:ProbeRequests = [System.Collections.Generic.List[object]]::new()
$script:ProbeResponses = @{}
$script:LastHttpStatus = $null
Set-Item -Path Function:Invoke-DataverseRequest -Value {
    param([string]$Method, [string]$Path, [object]$Body, [string]$ETag)
    $script:ProbeRequests.Add([pscustomobject]@{ Method = $Method; Path = $Path })
    $decoded = [Uri]::UnescapeDataString($Path)
    $idMatch = [regex]::Match($decoded, '\$filter=entityid eq ([0-9a-fA-F-]{36})')
    if (-not $idMatch.Success) { throw 'Synthetic resolver did not receive entityid filter.' }
    $id = $idMatch.Groups[1].Value.ToLowerInvariant()
    $response = $script:ProbeResponses[$id]
    $script:LastHttpStatus = if ($response.Contains('Status')) { $response.Status } else { 200 }
    if ($response.Contains('Throw') -and $response.Throw) { throw 'Synthetic HTTP 400 from entities RetrieveMultiple.' }
    @{ value = @($response.Rows) }
}
try {
    $probeComponents = @($rawComposedComponents.ToArray() | Where-Object { $_.componenttype -eq 1 })
    $probeIds = @($probeComponents | ForEach-Object { $_.objectid })
    $script:ProbeResponses = @{}
    for ($index = 0; $index -lt $probeComponents.Count; $index++) {
        $entity = $syntheticEntityRecords[$index]
        $script:ProbeResponses[$probeIds[$index].ToLowerInvariant()] = @{
            Status = 200
            Rows = @([pscustomobject]@{
                entityid = $probeIds[$index]
                logicalname = $entity.logicalname
                name = $entity.name
                objecttypecode = $entity.objecttypecode
            })
        }
    }
    $script:FirstFailingPredicate = $null
    $orderedProbes = @(Get-EntityResolutionDiagnosticRows -Components @($probeComponents[3], $probeComponents[2], $probeComponents[1], $probeComponents[0]) `
        -ReferenceComponents $script:ResolvedReferenceComponents)
    Assert-Test (@($orderedProbes | Where-Object PredicateResult).Count -eq 4 -and
        (Get-EntityResolutionAggregateClassification -Diagnostics $orderedProbes) -ceq 'ENTITYID_MAPPING_CONFIRMED') 'Accept exactly four approved logical names in any component order'
    Assert-Test ($orderedProbes[0].Alias -ceq 'EntityComponent1' -and
        $orderedProbes[0].NormalizedLogicalName -ceq 'os_sr_loc') 'Keep stable component aliases independent of expected table order'

    $firstProbeId = $probeIds[0].ToLowerInvariant()
    $script:ProbeResponses[$firstProbeId] = @{ Status = 200; Rows = @() }
    $script:FirstFailingPredicate = $null
    $zeroProbe = @(Get-EntityResolutionDiagnosticRows -Components $probeComponents -ReferenceComponents $script:ResolvedReferenceComponents)
    Assert-Test ($zeroProbe[0].HttpStatus -eq 200 -and $zeroProbe[0].ReturnedRowCount -eq 0 -and
        -not $zeroProbe[0].PredicateResult -and $zeroProbe[0].FailureCategory -ceq 'ENTITY_OBJECTID_NOT_RESOLVED' -and
        (Get-EntityResolutionAggregateClassification -Diagnostics $zeroProbe) -ceq 'OBJECTID_NOT_ENTITYID') 'HTTP 200 with zero rows remains an unresolved identity'
    $script:EntityResolutionDiagnostics = $zeroProbe
    try { throw 'Synthetic outer wrapper test.' } catch {
        $safeStopped = New-SafeStoppedExecutionSummary -ErrorRecord $_
    }
    Assert-Test ($safeStopped.FirstFailingPredicate -ceq 'ENTITY_OBJECTID_NOT_RESOLVED' -and
        $safeStopped.EntityResolutionDiagnostics[0].FailureCategory -ceq 'ENTITY_OBJECTID_NOT_RESOLVED') 'Preserve exact inner entity predicate through sanitized wrapper'

    $script:ProbeResponses[$firstProbeId] = @{ Status = 200; Rows = @(
        [pscustomobject]@{ entityid = $probeIds[0]; logicalname = 'os_sr_ta'; name = 'TA'; objecttypecode = 1 }
        [pscustomobject]@{ entityid = $probeIds[0]; logicalname = 'os_sr_ta'; name = 'TA'; objecttypecode = 1 }
    ) }
    $script:FirstFailingPredicate = $null
    $multipleProbes = @(Get-EntityResolutionDiagnosticRows -Components $probeComponents -ReferenceComponents $script:ResolvedReferenceComponents)
    Assert-Test ($multipleProbes[0].ReturnedRowCount -eq 2 -and
        $multipleProbes[0].FailureCategory -ceq 'ENTITY_OBJECTID_AMBIGUOUS' -and
        (Get-EntityResolutionAggregateClassification -Diagnostics $multipleProbes) -ceq 'ENTITY_MAPPING_AMBIGUOUS') 'Classify multiple entities rows as ambiguous'

    $script:ProbeResponses[$firstProbeId] = @{ Status = 200; Rows = @(
        [pscustomobject]@{ entityid = $probeIds[0]; logicalname = 'account'; name = 'Account'; objecttypecode = 1 }
    ) }
    $script:FirstFailingPredicate = $null
    $wrongNameProbes = @(Get-EntityResolutionDiagnosticRows -Components $probeComponents -ReferenceComponents $script:ResolvedReferenceComponents)
    Assert-Test ($wrongNameProbes[0].FailureCategory -ceq 'ENTITY_LOGICALNAME_UNEXPECTED' -and
        (Get-EntityResolutionAggregateClassification -Diagnostics $wrongNameProbes) -ceq 'ENTITY_MAPPING_WRONG_LOGICALNAME') 'Reject resolved but unapproved logical name'

    $script:ProbeResponses = @{}
    for ($index = 0; $index -lt $probeComponents.Count; $index++) {
        $entity = $syntheticEntityRecords[$index]
        $name = if ($index -eq 1) { 'os_sr_ta' } else { $entity.logicalname }
        $script:ProbeResponses[$probeIds[$index].ToLowerInvariant()] = @{
            Status = 200
            Rows = @([pscustomobject]@{
                entityid = $probeIds[$index]
                logicalname = $name
                name = $name
                objecttypecode = $entity.objecttypecode
            })
        }
    }
    $script:FirstFailingPredicate = $null
    $duplicateProbes = @(Get-EntityResolutionDiagnosticRows -Components $probeComponents -ReferenceComponents $script:ResolvedReferenceComponents)
    Assert-Test (@($duplicateProbes | Where-Object FailureCategory -eq 'ENTITY_LOGICALNAME_DUPLICATE').Count -eq 2 -and
        (Get-EntityResolutionAggregateClassification -Diagnostics $duplicateProbes) -ceq 'ENTITY_MAPPING_DUPLICATE_LOGICALNAME') 'Reject duplicate normalized logical names'

    foreach ($invalidObjectId in @($null, 'not-a-guid')) {
        $invalidComponent = [pscustomobject]@{ componenttype = 1; objectid = $invalidObjectId; appmodulecomponentid = $null }
        $beforeRequestCount = $script:ProbeRequests.Count
        $script:FirstFailingPredicate = $null
        $invalidProbe = @(Get-EntityResolutionDiagnosticRows -Components @($invalidComponent) -ReferenceComponents $script:ResolvedReferenceComponents)
        Assert-Test (-not $invalidProbe[0].ObjectIdSyntacticallyValidGuid -and
            $script:ProbeRequests.Count -eq $beforeRequestCount -and
            $invalidProbe[0].FailureCategory -in @('OBJECTID_MISSING', 'OBJECTID_INVALID_GUID')) 'Reject missing or malformed objectid without issuing a request'
    }

    $script:ProbeResponses[$firstProbeId] = @{ Status = 400; Rows = @(); Throw = $true }
    $script:FirstFailingPredicate = $null
    $httpFailureProbe = @(Get-EntityResolutionDiagnosticRows -Components @($probeComponents[0]) -ReferenceComponents $script:ResolvedReferenceComponents)
    Assert-Test ($httpFailureProbe[0].HttpStatus -eq 400 -and
        $httpFailureProbe[0].FailureCategory -ceq 'ENTITY_QUERY_HTTP_FAILURE' -and
        -not $httpFailureProbe[0].PredicateResult) 'Treat HTTP error as failure regardless of HTTP-stage reporting'
    Assert-Test (@($script:ProbeRequests | Where-Object Method -ne 'GET').Count -eq 0) 'All diagnostic identity probes are GET-only'
}
finally {
    Set-Item -Path Function:Invoke-DataverseRequest -Value $originalDataverseRequest
}

$originalGetODataRows = (Get-Command Get-ODataRows -CommandType Function).ScriptBlock
$script:EntityRowsRequestPaths = [System.Collections.Generic.List[string]]::new()
Set-Item -Path Function:Get-ODataRows -Value {
    param([string]$Path)
    $script:EntityRowsRequestPaths.Add($Path)
    @([pscustomobject]@{
        entityid = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
        logicalname = 'entity'
        name = 'Entity'
        objecttypecode = 1
        componentstate = 0
    })
}
$originalDataverseRequestForRootTests = (Get-Command Invoke-DataverseRequest -CommandType Function).ScriptBlock
$script:EntityDefinitionRequests = [System.Collections.Generic.List[object]]::new()
Set-Item -Path Function:Invoke-DataverseRequest -Value {
    param([string]$Method, [string]$Path, [object]$Body, [string]$ETag)
    $script:EntityDefinitionRequests.Add([pscustomobject]@{ Method = $Method; Path = $Path })
    [pscustomobject]@{ MetadataId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'; LogicalName = 'os_sr_ta'; ObjectTypeCode = 11005 }
}
try {
    $entityTableRows = @(Get-EntityRowsByLogicalName -LogicalName 'entity')
    Assert-Test ($entityTableRows.Count -eq 1 -and $entityTableRows[0].componentstate -eq 0) 'Read entity table identity including component state'
    $entityRowsPath = [Uri]::UnescapeDataString($script:EntityRowsRequestPaths[0])
    Assert-Test ($entityRowsPath -match '\$filter=logicalname eq ''entity''' -and
        $entityRowsPath -match '\$select=entityid,logicalname,name,objecttypecode,componentstate') 'Filter entities by logical name and retain componentstate'
    $metadataRow = Get-EntityDefinitionByLogicalName -LogicalName 'os_sr_ta'
    Assert-Test ($metadataRow.LogicalName -ceq 'os_sr_ta' -and
        $script:EntityDefinitionRequests[0].Method -ceq 'GET' -and
        [Uri]::UnescapeDataString($script:EntityDefinitionRequests[0].Path) -match "EntityDefinitions\(LogicalName='os_sr_ta'\).*MetadataId,LogicalName,ObjectTypeCode") 'Read EntityDefinitions metadata identity with an explicit GET'
    Assert-Test (@(Get-NormalizedGuidCandidates -Rows @($metadataRow) -PropertyName 'MetadataId').Count -eq 1 -and
        -not (Test-GuidValueMatchesAny -Value $metadataRow.MetadataId -Candidates @('cccccccc-cccc-4ccc-8ccc-cccccccccccc'))) 'Validate and compare MetadataId without exposing its value'
}
finally {
    Set-Item -Path Function:Get-ODataRows -Value $originalGetODataRows
    Set-Item -Path Function:Invoke-DataverseRequest -Value $originalDataverseRequestForRootTests
}

$rootRepairReferences = @(
    foreach ($reference in $script:ResolvedReferenceComponents) {
        [pscustomobject]@{
            LogicalName = $reference.LogicalName
            MetadataFound = $true
            EntityTableIdentityUnambiguous = $true
            LogicalNamesAgree = $true
            MetadataIdEqualsEntityId = $true
            ObjectTypeCodesAgree = $true
            MetadataId = $reference.TableMetadataId
            EntityId = $reference.TableMetadataId
            PayloadEntityId = $reference.TableMetadataId
        }
    }
)
$repairSystemEntityId = 'ffffffff-ffff-4fff-8fff-ffffffffffff'
$wrongSystemRoots = @(
    for ($index = 0; $index -lt 4; $index++) {
        [pscustomobject]@{
            appmodulecomponentid = '{0:x8}-3000-4000-8000-{1:x12}' -f ($index + 1), ($index + 1)
            componenttype = 1
            objectid = $repairSystemEntityId
            ismetadata = $false
            isdefault = $false
            rootappmodulecomponentid = $null
            rootcomponentbehavior = $null
        }
    }
)
$wrongSystemPlan = Get-EntityRootRepairPlan -Components $wrongSystemRoots `
    -SystemEntityIds @($repairSystemEntityId) -ReferenceIdentityEvidence $rootRepairReferences `
    -OriginalPayloadFingerprintMatches $true -RemoveActionContractValid $true -AppId $script:Target.AppModuleId
Assert-Test ($wrongSystemPlan.RootClassification -ceq 'WRONG_SYSTEM_ENTITY_ROOTS_CONFIRMED' -and
    $wrongSystemPlan.AllComponentRecordIdsDistinct -and -not $wrongSystemPlan.AllObjectIdsDistinct -and
    $wrongSystemPlan.SomeObjectIdsDuplicate -and $wrongSystemPlan.AllObjectIdsEqual) 'Confirm four wrong system roots and detect duplicate object references'
Assert-Test ($wrongSystemPlan.RemovePayloadCount -eq 1 -and
    -not $wrongSystemPlan.RemoveSemanticsKnownForObservedMultiplicity -and
    $wrongSystemPlan.RepairPlanStatus -ceq 'AMBIGUOUS') 'Do not guess RemoveAppComponents behavior for duplicate wrong roots'
Assert-Test ($wrongSystemPlan.AddPayloadCount -eq 4 -and
    $wrongSystemPlan.AddPayloadContainsOnlyEntityComponents -and
    @($wrongSystemPlan.AddPayload | Where-Object { $_.ODataType -ne 'Microsoft.Dynamics.CRM.entity' }).Count -eq 0) 'Build only four typed entity references for the proposed Add repair'
Assert-Test ($wrongSystemPlan.AddPayloadFingerprint -ceq (Get-PayloadFingerprint -Payload @(
    $rootRepairReferences | Sort-Object { [array]::IndexOf(@('os_sr_ta', 'os_sr_pos', 'os_sr_csrc', 'os_sr_loc'), $_.LogicalName) } |
        ForEach-Object { [ordered]@{ entityid = $_.EntityId; '@odata.type' = 'Microsoft.Dynamics.CRM.entity' } }
))) 'Fingerprint the deterministic four-table AddAppComponents repair payload'
Assert-Test ($wrongSystemPlan.RemovePayloadFingerprint -ceq (Get-PayloadFingerprint -Payload @(
    [ordered]@{ entityid = $repairSystemEntityId; '@odata.type' = 'Microsoft.Dynamics.CRM.entity' }
))) 'Fingerprint one unique typed removal reference for a duplicate wrong root'
Assert-Test ($wrongSystemPlan.RemovePayloadFingerprint -match '^[0-9a-f]{64}$' -and
    $wrongSystemPlan.AddPayloadFingerprint -match '^[0-9a-f]{64}$' -and
    $wrongSystemPlan.RemoveRequestBodyFingerprint -match '^[0-9a-f]{64}$' -and
    $wrongSystemPlan.AddRequestBodyFingerprint -match '^[0-9a-f]{64}$' -and
    $wrongSystemPlan.OriginalPayloadIdSource -ceq 'ENTITYDEFINITIONS_METADATA_ID' -and
    $wrongSystemPlan.OriginalPayloadRootCause -ceq 'NOT_ESTABLISHED_BY_AVAILABLE_PAYLOAD_AND_ROOT_EVIDENCE') 'Fingerprint repair payloads while preserving unresolved original root cause'
$zeroEntityRootPlan = Get-EntityRootRepairPlan -Components @(
    [pscustomobject]@{ componenttype = 62; objectid = $script:Target.SiteMapId }
    [pscustomobject]@{ componenttype = 60; objectid = $script:ResolvedReferenceComponents[0].MainForm.Id }
    [pscustomobject]@{ componenttype = 26; objectid = $script:ResolvedReferenceComponents[0].ActiveView.Id }
) -SystemEntityIds @() -ReferenceIdentityEvidence $rootRepairReferences `
    -OriginalPayloadFingerprintMatches $true -RemoveActionContractValid $true -AppId $script:Target.AppModuleId
Assert-Test ($zeroEntityRootPlan.CurrentEntityComponentCount -eq 0 -and
    $zeroEntityRootPlan.RootClassification -ceq 'UNKNOWN' -and
    $zeroEntityRootPlan.RemovePayloadCount -eq 0) 'Reconcile a zero-entity interim app inventory without inventing a system entity identity'
Assert-Test ((Get-EntityResolutionAggregateClassification -Diagnostics @()) -ceq 'UNKNOWN') `
    'Classify an empty entity-resolution inventory without rejecting the interim zero-root state'
$safeRootDiagnostic = $wrongSystemPlan | ConvertTo-Json -Depth 10 -Compress
Assert-Test ($safeRootDiagnostic -notmatch '[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}' -and
    $safeRootDiagnostic -match 'WRONG_SYSTEM_ENTITY_ROOTS_CONFIRMED') 'Retain sanitized root classification without raw GUIDs'
$wrongRootsWithProtectedComponents = @($wrongSystemRoots) + @(
    [pscustomobject]@{ componenttype = 62; objectid = $script:Target.SiteMapId }
    [pscustomobject]@{ componenttype = 60; objectid = $script:ResolvedReferenceComponents[0].MainForm.Id }
    [pscustomobject]@{ componenttype = 26; objectid = $script:ResolvedReferenceComponents[0].ActiveView.Id }
)
$protectedComponentPlan = Get-EntityRootRepairPlan -Components $wrongRootsWithProtectedComponents `
    -SystemEntityIds @($repairSystemEntityId) -ReferenceIdentityEvidence $rootRepairReferences `
    -OriginalPayloadFingerprintMatches $true -RemoveActionContractValid $true -AppId $script:Target.AppModuleId
Assert-Test ($protectedComponentPlan.RemovePayloadCount -eq 1 -and
    $protectedComponentPlan.AddPayloadCount -eq 4 -and
    @($protectedComponentPlan.RemovePayload | Where-Object ODataType -ne 'Microsoft.Dynamics.CRM.entity').Count -eq 0) 'Exclude Site Map, form, and view records from repair payloads'

$correctProjectRoots = @(
    for ($index = 0; $index -lt 4; $index++) {
        [pscustomobject]@{
            appmodulecomponentid = '{0:x8}-4000-4000-8000-{1:x12}' -f ($index + 1), ($index + 1)
            componenttype = 1
            objectid = $rootRepairReferences[$index].EntityId
        }
    }
)
$correctRootPlan = Get-EntityRootRepairPlan -Components $correctProjectRoots `
    -SystemEntityIds @($repairSystemEntityId) -ReferenceIdentityEvidence $rootRepairReferences `
    -OriginalPayloadFingerprintMatches $true -RemoveActionContractValid $true -AppId $script:Target.AppModuleId
Assert-Test ($correctRootPlan.RootClassification -ceq 'CORRECT_PROJECT_TABLE_ROOTS' -and
    $correctRootPlan.AllObjectIdsDistinct) 'Resolve four exact project table roots using matching EntityDefinitions and entities IDs'
$mixedRoots = @($correctProjectRoots[0], $correctProjectRoots[1]) + @(
    $wrongSystemRoots[2], $wrongSystemRoots[3]
)
$mixedRootPlan = Get-EntityRootRepairPlan -Components $mixedRoots `
    -SystemEntityIds @($repairSystemEntityId) -ReferenceIdentityEvidence $rootRepairReferences `
    -OriginalPayloadFingerprintMatches $true -RemoveActionContractValid $true -AppId $script:Target.AppModuleId
Assert-Test ($mixedRootPlan.RootClassification -ceq 'MIXED_ROOT_STATE') 'Classify mixed system and project entity roots'
$differentMetadataEvidence = @($rootRepairReferences)
$differentMetadataEvidence[0] = [pscustomobject]@{
    LogicalName = $rootRepairReferences[0].LogicalName
    MetadataFound = $true
    EntityTableIdentityUnambiguous = $true
    LogicalNamesAgree = $true
    MetadataIdEqualsEntityId = $false
    ObjectTypeCodesAgree = $true
    MetadataId = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee'
    EntityId = $rootRepairReferences[0].EntityId
    PayloadEntityId = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee'
}
$unverifiedIdPlan = Get-EntityRootRepairPlan -Components $wrongSystemRoots `
    -SystemEntityIds @($repairSystemEntityId) -ReferenceIdentityEvidence $differentMetadataEvidence `
    -OriginalPayloadFingerprintMatches $true -RemoveActionContractValid $true -AppId $script:Target.AppModuleId
Assert-Test (-not $unverifiedIdPlan.ReferenceIdentityComplete -and
    $unverifiedIdPlan.RepairPlanStatus -ceq 'AMBIGUOUS') 'Block repair when MetadataId and entities entityid differ'
$removeContractMetadata = [xml]@'
<edmx:Edmx xmlns:edmx="http://docs.oasis-open.org/odata/ns/edmx" Version="4.0">
  <edmx:DataServices>
    <Schema xmlns="http://docs.oasis-open.org/odata/ns/edm" Namespace="Microsoft.Dynamics.CRM">
      <Action Name="RemoveAppComponents">
        <Parameter Name="AppId" Type="Edm.Guid" Nullable="false" />
        <Parameter Name="Components" Type="Collection(mscrm.crmbaseentity)" Nullable="false" />
      </Action>
    </Schema>
  </edmx:DataServices>
</edmx:Edmx>
'@
$removeActionContract = Get-RemoveAppComponentsContract -Metadata $removeContractMetadata
Assert-Test ($removeActionContract.Valid -and $removeActionContract.ComponentsType -ceq 'Collection(mscrm.crmbaseentity)') 'Verify RemoveAppComponents accepts typed component collections'
$systemEntityIdForRemoval = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee'
$removeWrongEntityBody = New-RemoveWrongSystemEntityPayload -AppId $script:Target.AppModuleId `
    -SystemEntityId $systemEntityIdForRemoval
Assert-Test ($removeWrongEntityBody.AppId -ceq $script:Target.AppModuleId -and
    $removeWrongEntityBody.Components.Count -eq 1 -and
    $removeWrongEntityBody.Components[0].entityid -ceq $systemEntityIdForRemoval -and
    $removeWrongEntityBody.Components[0]['@odata.type'] -ceq 'Microsoft.Dynamics.CRM.entity') 'Build exactly one system-entity typed RemoveAppComponents component'
Assert-Test (@($removeWrongEntityBody.Components[0].Keys | Where-Object {
    $_ -match 'appmodulecomponentid|formid|savedqueryid|sitemapid'
}).Count -eq 0) 'Removal payload excludes appmodulecomponent rows and protected component IDs'
Assert-Test (@($rootRepairReferences | Where-Object {
    (ConvertTo-NormalizedGuid -Value $_.EntityId) -ceq (ConvertTo-NormalizedGuid -Value $removeWrongEntityBody.Components[0].entityid)
}).Count -eq 0) 'Removal payload cannot target any approved project table ID'
$singleRemoveFingerprint = Get-PayloadFingerprint -Payload @($removeWrongEntityBody)
Assert-Test ($singleRemoveFingerprint -match '^[0-9a-f]{64}$' -and
    $singleRemoveFingerprint -ceq (Get-PayloadFingerprint -Payload @(
        New-RemoveWrongSystemEntityPayload -AppId $script:Target.AppModuleId -SystemEntityId $systemEntityIdForRemoval
    ))) 'Single logical remove payload fingerprint is deterministic'
Assert-Rejected {
    $invalidRemoveBody = [ordered]@{
        AppId = $script:Target.AppModuleId
        Components = @($removeWrongEntityBody.Components[0], $removeWrongEntityBody.Components[0])
    }
    Assert-RemoveWrongSystemEntityPayload -Body $invalidRemoveBody -AppId $script:Target.AppModuleId `
        -SystemEntityId $systemEntityIdForRemoval
} 'Reject more than one RemoveAppComponents component' 'exactly one component'
Assert-Rejected {
    $invalidRemoveBody = [ordered]@{
        AppId = $script:Target.AppModuleId
        Components = @([ordered]@{
            entityid = $rootRepairReferences[0].EntityId
            '@odata.type' = 'Microsoft.Dynamics.CRM.entity'
        })
    }
    Assert-RemoveWrongSystemEntityPayload -Body $invalidRemoveBody -AppId $script:Target.AppModuleId `
        -SystemEntityId $systemEntityIdForRemoval
} 'Reject a project table ID in the remove payload' 'only the verified system entity reference'

$protectedRoleFixtures = @(
    [pscustomobject]@{ Name = 'System Administrator'; IsManaged = $true }
    [pscustomobject]@{ Name = 'System Customizer'; IsManaged = $true }
)
$protectedAssetFixtures = @(
    [pscustomobject]@{ MainFormPresentDirectly = $true; MainFormDirectMatchCount = 1; ActiveViewPresentDirectly = $true; ActiveViewDirectMatchCount = 1 }
    [pscustomobject]@{ MainFormPresentDirectly = $true; MainFormDirectMatchCount = 1; ActiveViewPresentDirectly = $true; ActiveViewDirectMatchCount = 1 }
    [pscustomobject]@{ MainFormPresentDirectly = $true; MainFormDirectMatchCount = 1; ActiveViewPresentDirectly = $true; ActiveViewDirectMatchCount = 1 }
    [pscustomobject]@{ MainFormPresentDirectly = $true; MainFormDirectMatchCount = 1; ActiveViewPresentDirectly = $true; ActiveViewDirectMatchCount = 1 }
)
$removalBeforeFixture = [pscustomobject]@{
    SiteMap = [pscustomobject]@{ Id = 'sitemap-id'; UniqueName = 'srapp'; SitemapXml = '<SiteMap />'; ComponentState = 0 }
    AppModule = [pscustomobject]@{ UniqueName = 'srapp'; StateCode = 0; ComponentState = 1 }
    AppModuleRoles = $protectedRoleFixtures
}
$removalAfterFullFixture = [pscustomobject]@{
    SiteMap = [pscustomobject]@{ Id = 'sitemap-id'; UniqueName = 'srapp'; SitemapXml = '<SiteMap />'; ComponentState = 0 }
    AppModule = [pscustomobject]@{ UniqueName = 'srapp'; StateCode = 0; ComponentState = 1 }
    AppModuleRoles = $protectedRoleFixtures
    DirectReferenceUiAssociationEvidence = [pscustomobject]@{
        IntendedSiteMapPresentDirectly = $true; SiteMapCount = 1; AppAssociationMatchesForEveryComponent = $true
        Assets = $protectedAssetFixtures
    }
    RawAppComponentTypeCounts = [pscustomobject]@{ SiteMap = 1; Entity = 0; Form = 4; View = 4; Other = 0; Total = 9 }
    EntityRootRepairEvidence = [pscustomobject]@{ Plan = [pscustomobject]@{
        CurrentComponents = @(); ProjectTableRootCounts = @{ os_sr_ta = 0; os_sr_pos = 0; os_sr_csrc = 0; os_sr_loc = 0 }
    } }
}
Assert-Test ((Get-WrongSystemEntityRemovalClassification -Before $removalBeforeFixture `
    -After $removalAfterFullFixture -WriteStatus 204 -WriteDispatched $true) -ceq 'WRONG_ROOTS_FULLY_REMOVED') `
    'Reconcile complete duplicate-root removal while preserving protected components'
$removalAfterPartialFixture = $removalAfterFullFixture.PSObject.Copy()
$removalAfterPartialFixture.RawAppComponentTypeCounts = [pscustomobject]@{ SiteMap = 1; Entity = 2; Form = 4; View = 4; Other = 0; Total = 11 }
$removalAfterPartialFixture.EntityRootRepairEvidence = [pscustomobject]@{ Plan = [pscustomobject]@{
    CurrentComponents = @(
        [pscustomobject]@{ ObjectIdEqualsSystemEntityId = $true }
        [pscustomobject]@{ ObjectIdEqualsSystemEntityId = $true }
    )
    ProjectTableRootCounts = @{ os_sr_ta = 0; os_sr_pos = 0; os_sr_csrc = 0; os_sr_loc = 0 }
} }
Assert-Test ((Get-WrongSystemEntityRemovalClassification -Before $removalBeforeFixture `
    -After $removalAfterPartialFixture -WriteStatus 204 -WriteDispatched $true) -ceq 'WRONG_ROOTS_PARTIALLY_REMOVED') `
    'Classify partial duplicate-root removal without retry'
$removalAfterUnchangedFixture = $removalAfterFullFixture.PSObject.Copy()
$removalAfterUnchangedFixture.RawAppComponentTypeCounts = [pscustomobject]@{ SiteMap = 1; Entity = 4; Form = 4; View = 4; Other = 0; Total = 13 }
$removalAfterUnchangedFixture.EntityRootRepairEvidence = [pscustomobject]@{ Plan = [pscustomobject]@{
    CurrentComponents = @(
        [pscustomobject]@{ ObjectIdEqualsSystemEntityId = $true }
        [pscustomobject]@{ ObjectIdEqualsSystemEntityId = $true }
        [pscustomobject]@{ ObjectIdEqualsSystemEntityId = $true }
        [pscustomobject]@{ ObjectIdEqualsSystemEntityId = $true }
    )
    ProjectTableRootCounts = @{ os_sr_ta = 0; os_sr_pos = 0; os_sr_csrc = 0; os_sr_loc = 0 }
} }
Assert-Test ((Get-WrongSystemEntityRemovalClassification -Before $removalBeforeFixture `
    -After $removalAfterUnchangedFixture -WriteStatus 204 -WriteDispatched $true) -ceq 'WRONG_ROOTS_NOT_REMOVED') `
    'Classify a successful but non-effective single logical remove'
$removalAfterProtectedChangeFixture = $removalAfterFullFixture.PSObject.Copy()
$removalAfterProtectedChangeFixture.SiteMap = [pscustomobject]@{
    Id = 'sitemap-id'; UniqueName = 'srapp'; SitemapXml = '<SiteMap changed="true" />'; ComponentState = 0
}
Assert-Test ((Get-WrongSystemEntityRemovalClassification -Before $removalBeforeFixture `
    -After $removalAfterProtectedChangeFixture -WriteStatus 204 -WriteDispatched $true) -ceq 'PROTECTED_COMPONENT_CHANGED') `
    'Classify any protected Site Map change as a stop condition'
$removalAfterProtectedFormChangeFixture = $removalAfterFullFixture.PSObject.Copy()
$protectedAssetsChanged = @($protectedAssetFixtures | ForEach-Object { $_.PSObject.Copy() })
$protectedAssetsChanged[0].MainFormPresentDirectly = $false
$removalAfterProtectedFormChangeFixture.DirectReferenceUiAssociationEvidence = [pscustomobject]@{
    IntendedSiteMapPresentDirectly = $true; SiteMapCount = 1; AppAssociationMatchesForEveryComponent = $true
    Assets = $protectedAssetsChanged
}
Assert-Test ((Get-WrongSystemEntityRemovalClassification -Before $removalBeforeFixture `
    -After $removalAfterProtectedFormChangeFixture -WriteStatus 204 -WriteDispatched $true) -ceq 'PROTECTED_COMPONENT_CHANGED') `
    'Classify a missing protected form as a stop condition'
Assert-Test ((Get-WrongSystemEntityRemovalClassification -Before $removalBeforeFixture `
    -After $removalAfterUnchangedFixture -WriteStatus 401 -WriteDispatched $true) -ceq 'FAILED_AUTH') `
    'Classify an unauthorized single removal without retry'
Assert-Test ((Get-WrongSystemEntityRemovalClassification -Before $removalBeforeFixture `
    -After $removalAfterUnchangedFixture -WriteStatus 403 -WriteDispatched $true) -ceq 'FAILED_AUTHZ') `
    'Classify a forbidden single removal without retry'
Assert-Test ((Get-WrongSystemEntityRemovalClassification -Before $removalBeforeFixture `
    -After $removalAfterUnchangedFixture -WriteStatus 429 -WriteDispatched $true) -ceq 'UNCERTAIN') `
    'Classify throttled removal as uncertain without retry'
$script:RequestCounts = @{ GET = 0; PATCH = 0; POST = 0 }
$script:WriteResults.Clear()
$script:WritesStarted = $false
Assert-RemoveWrongSystemEntityWriteSequence
$script:RequestCounts.POST = 1
Assert-Rejected { Assert-RemoveWrongSystemEntityWriteSequence } 'Block every second logical RemoveAppComponents attempt' 'exactly one RemoveAppComponents POST'
$script:RequestCounts.POST = 0
$script:WritesStarted = $true
Assert-Rejected { Assert-RemoveWrongSystemEntityWriteSequence } 'Block removal after any dispatched write' 'no prior write'
$script:WritesStarted = $false

$rootRepairAssetComponents = @(
    [pscustomobject]@{
        appmodulecomponentid = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee'
        _appmoduleidunique_value = $script:Target.AppModuleIdUnique
        componenttype = 62
        objectid = $script:Target.SiteMapId
    }
    foreach ($reference in $script:ResolvedReferenceComponents) {
        [pscustomobject]@{
            appmodulecomponentid = $reference.MainForm.Id
            _appmoduleidunique_value = $script:Target.AppModuleIdUnique
            componenttype = 60
            objectid = $reference.MainForm.Id
        }
        [pscustomobject]@{
            appmodulecomponentid = $reference.ActiveView.Id
            _appmoduleidunique_value = $script:Target.AppModuleIdUnique
            componenttype = 26
            objectid = $reference.ActiveView.Id
        }
    }
)
$assetEvidence = Get-DirectReferenceUiAssociationEvidence -Components $rootRepairAssetComponents `
    -ReferenceComponents $script:ResolvedReferenceComponents -SiteMapId $script:Target.SiteMapId `
    -AppModuleIdUnique $script:Target.AppModuleIdUnique
Assert-Test ($assetEvidence.IntendedSiteMapPresentDirectly -and
    $assetEvidence.AppAssociationMatchesForEveryComponent -and
    @($assetEvidence.Assets | Where-Object { -not $_.MainFormPresentDirectly -or -not $_.ActiveViewPresentDirectly }).Count -eq 0) 'Verify all approved forms, views, Site Map, and app associations directly'

$originalGetODataRowsForRootEvidence = (Get-Command Get-ODataRows -CommandType Function).ScriptBlock
$originalDataverseRequestForEntityMetadata = (Get-Command Invoke-DataverseRequest -CommandType Function).ScriptBlock
$script:RootEvidenceGetPaths = [System.Collections.Generic.List[string]]::new()
$script:RootEvidenceMetadataPaths = [System.Collections.Generic.List[string]]::new()
Set-Item -Path Function:Get-ODataRows -Value {
    param([string]$Path)
    $script:RootEvidenceGetPaths.Add($Path)
    $decodedPath = [Uri]::UnescapeDataString($Path)
    $logicalMatch = [regex]::Match($decodedPath, '\$filter=logicalname eq ''([^'']+)''')
    if (-not $logicalMatch.Success) { throw 'Synthetic entity query must filter by logicalname.' }
    $logicalName = $logicalMatch.Groups[1].Value
    if ($logicalName -ceq 'entity') {
        return @(
            [pscustomobject]@{
                entityid = $repairSystemEntityId; logicalname = 'entity'; name = 'Entity'
                objecttypecode = 1; componentstate = 0
            }
            [pscustomobject]@{
                entityid = $repairSystemEntityId; logicalname = 'entity'; name = 'Entity'
                objecttypecode = 1; componentstate = 1
            }
        )
    }
    $tableEvidence = @($rootRepairReferences | Where-Object LogicalName -CEQ $logicalName)
    if ($tableEvidence.Count -ne 1) { throw 'Synthetic logical name was not approved.' }
    $reference = @($script:ResolvedReferenceComponents | Where-Object LogicalName -CEQ $logicalName)[0]
    @([pscustomobject]@{
        entityid = $tableEvidence[0].EntityId
        logicalname = $logicalName
        name = $logicalName
        objecttypecode = 11005 + [array]::IndexOf(@('os_sr_ta', 'os_sr_pos', 'os_sr_csrc', 'os_sr_loc'), $logicalName)
        componentstate = 0
    })
}
Set-Item -Path Function:Invoke-DataverseRequest -Value {
    param([string]$Method, [string]$Path, [object]$Body, [string]$ETag)
    $script:RootEvidenceMetadataPaths.Add($Path)
    if ($Method -cne 'GET') { throw 'Synthetic root evidence is GET-only.' }
    $logicalMatch = [regex]::Match($Path, "EntityDefinitions\(LogicalName='([^']+)'\)")
    if (-not $logicalMatch.Success) { throw 'Unexpected synthetic metadata route.' }
    $logicalName = $logicalMatch.Groups[1].Value
    $reference = @($rootRepairReferences | Where-Object LogicalName -CEQ $logicalName)[0]
    [pscustomobject]@{
        MetadataId = $reference.MetadataId
        LogicalName = $logicalName
        ObjectTypeCode = 11005 + [array]::IndexOf(@('os_sr_ta', 'os_sr_pos', 'os_sr_csrc', 'os_sr_loc'), $logicalName)
    }
}
try {
    $rootEvidence = Get-EntityRootRepairEvidence -Components $wrongSystemRoots `
        -ReferenceComponents $script:ResolvedReferenceComponents `
        -OriginalPayloadFingerprintMatches $true -Metadata $removeContractMetadata
    Assert-Test (@($rootEvidence.ApprovedTables | Where-Object {
        -not $_.MetadataSurfaceFound -or -not $_.EntityTableSurfaceFound -or
        -not $_.LogicalNamesAgree -or -not $_.MetadataIdEqualsEntityId -or
        ($null -ne $_.ObjectTypeCodesAgree -and -not $_.ObjectTypeCodesAgree)
    }).Count -eq 0) 'Prove matching EntityDefinitions and entities table IDs for every intended logical name'
    Assert-Test ($rootEvidence.SystemEntity.RowCount -eq 2 -and
        $rootEvidence.SystemEntity.ComponentStates.Count -eq 2 -and
        $rootEvidence.SystemEntity.UniqueIdCount -eq 1) 'Preserve duplicate system entity layers and their componentstate values'
    Assert-Test ($rootEvidence.Plan.RootClassification -ceq 'WRONG_SYSTEM_ENTITY_ROOTS_CONFIRMED' -and
        $rootEvidence.RemoveAppComponentsContract.Valid) 'Safely retain confirmed wrong-root classification and supported removal contract'
    Assert-Test ($script:RootEvidenceGetPaths.Count -eq 5 -and $script:RootEvidenceMetadataPaths.Count -eq 4) 'Resolve system entity and four tables over both read-only identity surfaces'
}
finally {
    Set-Item -Path Function:Get-ODataRows -Value $originalGetODataRowsForRootEvidence
    Set-Item -Path Function:Invoke-DataverseRequest -Value $originalDataverseRequestForEntityMetadata
}

$approvedRoles = @(
    [pscustomobject]@{ Name = 'System Administrator'; RoleId = '11111111-1111-4111-8111-111111111111' }
    [pscustomobject]@{ Name = 'System Customizer'; RoleId = '22222222-2222-4222-8222-222222222222' }
)
Assert-ApprovedAppRoles -Roles $approvedRoles
Assert-Test $true 'Accept only the approved existing app-role associations'
$extraRoles = @($approvedRoles) + @([pscustomobject]@{ Name = 'Unexpected Role' })
Assert-Rejected { Assert-ApprovedAppRoles -Roles $extraRoles } 'Reject unexpected app role association' 'differ from the approved'

$beforeUiValidation = Get-ReferenceUiValidationState -AppValidation ([pscustomobject]@{ Issues = @(
    [pscustomobject]@{ ErrorType = 'Warning'; Message = 'App does not reference at least one entity' }
) })
Assert-Test ($beforeUiValidation.EntityReferenceWarningCount -eq 1 -and $beforeUiValidation.BlockingErrorCount -eq 0) 'Recognize expected pre-composition entity warning'
$afterUiValidation = Get-ReferenceUiValidationState -AppValidation ([pscustomobject]@{ Issues = @() })
Assert-Test ($afterUiValidation.SiteMapErrorCount -eq 0 -and $afterUiValidation.EntityReferenceWarningCount -eq 0 -and
    $afterUiValidation.BlockingErrorCount -eq 0) 'Recognize clean intermediate and final ValidateApp state'
$blockedUiValidation = Get-ReferenceUiValidationState -AppValidation ([pscustomobject]@{ Issues = @(
    [pscustomobject]@{ ErrorType = 'Error'; Message = 'Unexpected validation blocker' }
) })
Assert-Test ($blockedUiValidation.BlockingErrorCount -eq 1) 'Detect blocking ValidateApp error before Site Map PATCH'
$warningSummaries = @(ConvertTo-SafeValidationIssueSummaries -Issues @(
    [pscustomobject]@{
        ErrorType = 'Warning'
        CRMErrorCode = 0
        Message = $null
        RequiredComponents = @([pscustomobject]@{
            DisplayName = 'TA Directory'
            SchemaName = 'os_sr_ta'
            ComponentType = 1
            ComponentId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
        })
    }
    [pscustomobject]@{
        ErrorType = 'Warning'
        CRMErrorCode = -2147155691
        Message = 'Entity does not reference a form or view.'
        RequiredComponents = @()
    }
) -NormalizedComponents $composedUiComponents)
$warningState = Get-ReferenceUiValidationState -AppValidation ([pscustomobject]@{
    ValidationSuccess = $true
    Issues = $warningSummaries
})
Assert-Test ($warningState.WarningCount -eq 2 -and $warningState.UnresolvedRequiredComponentCount -eq 0 -and
    $warningState.FormViewSelectionWarningCount -eq 1 -and
    $warningSummaries[0].RequiredComponents[0].ResolutionStatus -ceq 'SATISFIED') 'Classify satisfied code-0 and non-blocking form/view warnings'
$missingWarning = @(ConvertTo-SafeValidationIssueSummaries -Issues @(
    [pscustomobject]@{
        ErrorType = 'Warning'
        CRMErrorCode = -2147155691
        RequiredComponents = @([pscustomobject]@{
            SchemaName = 'os_sr_missing'
            ComponentType = 1
            ComponentId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
        })
    }
) -NormalizedComponents $composedUiComponents)
$missingWarningState = Get-ReferenceUiValidationState -AppValidation ([pscustomobject]@{
    ValidationSuccess = $true
    Issues = $missingWarning
})
Assert-Test ($missingWarningState.UnresolvedRequiredComponentCount -eq 1 -and
    $missingWarning[0].Classification -ceq 'UNRESOLVED_REQUIRED_COMPONENT') 'Block on genuinely missing required entity'
$failedValidationState = Get-ReferenceUiValidationState -AppValidation ([pscustomobject]@{
    ValidationSuccess = $false
    Issues = @()
})
Assert-Test ($failedValidationState.BlockingErrorCount -eq 1) 'Treat ValidationSuccess false as a blocking condition'

$script:RequestCounts = @{ GET = 0; PATCH = 0; POST = 0 }
$script:WriteResults = [System.Collections.Generic.List[object]]::new()
Assert-Rejected { Assert-ReferenceUiWriteSequence -Method POST } 'Reject AddAppComponents in Phase 2D.3D' 'forbids AddAppComponents'
Assert-ReferenceUiWriteSequence -Method PATCH
Assert-Test $true 'Allow one Site Map PATCH without AddAppComponents'
$script:RequestCounts.PATCH = 1
Assert-Rejected { Assert-ReferenceUiWriteSequence -Method PATCH } 'Reject second Site Map PATCH' 'one Site Map PATCH'
$script:RequestCounts = @{ GET = 0; PATCH = 0; POST = 0 }
$script:WriteResults = [System.Collections.Generic.List[object]]::new()

$beforeNavigation = @(Get-SiteMapSemanticNavigation -SiteMapXml $fixtureXml)
$afterNavigation = @(Get-SiteMapSemanticNavigation -SiteMapXml $proposedXml)
Assert-Test ($beforeNavigation.Count -eq 1 -and $afterNavigation.Count -eq 4 -and
    $afterNavigation[0].Entity -ceq 'os_sr_ta' -and $afterNavigation[3].Entity -ceq 'os_sr_loc') 'Produce semantic before/after navigation for review'
Assert-SiteMapSemanticNodePreservation -Before $beforeNavigation -After $afterNavigation
Assert-Test $true 'Preserve all existing Site Map Area, Group, and SubArea identities'
$removedNavigation = @([pscustomobject]@{
    AreaId = $afterNavigation[0].AreaId
    GroupId = $afterNavigation[0].GroupId
    SubAreaId = 'unexpected-replacement'
})
Assert-Rejected { Assert-SiteMapSemanticNodePreservation -Before $beforeNavigation -After $removedNavigation } 'Reject semantic delta deleting an existing node ID' 'removes or fails to preserve'
$duplicateIdsXml = $fixtureXml.Replace('</Group>', '<SubArea Id="subarea_9787e9c1"><Titles><Title LCID="1033" Title="Duplicate"/></Titles></SubArea></Group>')
Assert-Rejected { Assert-SiteMapHasNoDuplicateNavigationIds -SiteMapXml $duplicateIdsXml } 'Reject duplicate Site Map navigation IDs' 'duplicate SubArea IDs'

$taCanaryId = '11111111-aaaa-4bbb-8ccc-111111111111'
$systemEntityCanaryId = '99999999-aaaa-4bbb-8ccc-999999999999'
$otherTableCanaryId = '22222222-aaaa-4bbb-8ccc-222222222222'
$taCanaryBody = New-TACanaryPayload -AppId $script:Target.AppModuleId `
    -TaEntityId $taCanaryId -SystemEntityId $systemEntityCanaryId
Assert-Test ($taCanaryBody.Keys.Count -eq 2 -and @($taCanaryBody.Components).Count -eq 1 -and
    $taCanaryBody.Components[0].entityid -ceq $taCanaryId -and
    $taCanaryBody.Components[0]['@odata.type'] -ceq 'Microsoft.Dynamics.CRM.entity') `
    'Build exactly one typed TA entity canary payload'
Assert-Rejected {
    New-TACanaryPayload -AppId $script:Target.AppModuleId `
        -TaEntityId $systemEntityCanaryId -SystemEntityId $systemEntityCanaryId
} 'Reject system entity as the TA canary identity' 'must not match the system entity'
Assert-Rejected {
    Assert-TACanaryPayloadObject -Body $taCanaryBody -AppId $script:Target.AppModuleId `
        -TaEntityId $otherTableCanaryId -SystemEntityId $systemEntityCanaryId
} 'Reject a wrong approved table identity in the TA canary' 'freshly verified os_sr_ta'
$nullEntityCanaryBody = [ordered]@{
    AppId = $script:Target.AppModuleId
    Components = @([ordered]@{ entityid = $null; '@odata.type' = 'Microsoft.Dynamics.CRM.entity' })
}
Assert-Rejected {
    Assert-TACanaryPayloadObject -Body $nullEntityCanaryBody -AppId $script:Target.AppModuleId `
        -TaEntityId $taCanaryId -SystemEntityId $systemEntityCanaryId
} 'Reject a null TA entityid' 'freshly verified os_sr_ta'
$missingEntityCanaryBody = [ordered]@{
    AppId = $script:Target.AppModuleId
    Components = @([ordered]@{ '@odata.type' = 'Microsoft.Dynamics.CRM.entity' })
}
Assert-Rejected {
    Assert-TACanaryPayloadObject -Body $missingEntityCanaryBody -AppId $script:Target.AppModuleId `
        -TaEntityId $taCanaryId -SystemEntityId $systemEntityCanaryId
} 'Reject a missing TA entityid' 'freshly verified os_sr_ta'
$multipleEntityCanaryBody = [ordered]@{
    AppId = $script:Target.AppModuleId
    Components = @($taCanaryBody.Components[0], $taCanaryBody.Components[0])
}
Assert-Rejected {
    Assert-TACanaryPayloadObject -Body $multipleEntityCanaryBody -AppId $script:Target.AppModuleId `
        -TaEntityId $taCanaryId -SystemEntityId $systemEntityCanaryId
} 'Reject multiple component entries in the TA canary' 'exactly one AppId and one component'
$extraEntityCanaryBody = [ordered]@{
    AppId = $script:Target.AppModuleId
    Components = @([ordered]@{
        entityid = $taCanaryId
        systementityid = $systemEntityCanaryId
        '@odata.type' = 'Microsoft.Dynamics.CRM.entity'
    })
}
Assert-Rejected {
    Assert-TACanaryPayloadObject -Body $extraEntityCanaryBody -AppId $script:Target.AppModuleId `
        -TaEntityId $taCanaryId -SystemEntityId $systemEntityCanaryId
} 'Reject an additional entity identity property' 'only the freshly verified'
$taCanaryWireRequest = New-TACanaryWireRequest -Body $taCanaryBody `
    -TaEntityId $taCanaryId -SystemEntityId $systemEntityCanaryId
$taCanaryWireEvidence = Get-TACanaryWireBodyEvidence -Bytes $taCanaryWireRequest.BodyBytes `
    -AppId $script:Target.AppModuleId -TaEntityId $taCanaryId -SystemEntityId $systemEntityCanaryId
Assert-Test ($taCanaryWireEvidence.EntityId -ceq $taCanaryId -and
    $taCanaryWireEvidence.ODataType -ceq 'Microsoft.Dynamics.CRM.entity' -and
    $taCanaryWireEvidence.ComponentCount -eq 1) 'Strictly parse final serialized TA JSON and confirm the intended entityid'
Assert-Test ($taCanaryWireRequest.SemanticFingerprint -match '^[0-9a-f]{64}$' -and
    $taCanaryWireEvidence.SemanticFingerprint -ceq $taCanaryWireRequest.SemanticFingerprint) `
    'Check the semantic payload fingerprint against final parsed JSON'
Assert-Test ($taCanaryWireRequest.SerializedBodySha256 -match '^[0-9a-f]{64}$' -and
    $taCanaryWireEvidence.SerializedBodySha256 -ceq $taCanaryWireRequest.SerializedBodySha256) `
    'Fingerprint the exact serialized UTF-8 request body'
Assert-Rejected {
    Assert-TACanaryWireRequest -Bytes $taCanaryWireRequest.BodyBytes `
        -ExpectedSemanticFingerprint ('0' * 64) `
        -ExpectedSerializedBodySha256 $taCanaryWireRequest.SerializedBodySha256 `
        -TaEntityId $taCanaryId -SystemEntityId $systemEntityCanaryId
} 'Reject a changed semantic payload fingerprint' 'fingerprints changed'
Assert-Rejected {
    Assert-TACanaryWireRequest -Bytes $taCanaryWireRequest.BodyBytes `
        -ExpectedSemanticFingerprint $taCanaryWireRequest.SemanticFingerprint `
        -ExpectedSerializedBodySha256 ('0' * 64) `
        -TaEntityId $taCanaryId -SystemEntityId $systemEntityCanaryId
} 'Reject a changed serialized-body fingerprint' 'fingerprints changed'
Assert-Rejected {
    Get-TACanaryWireBodyEvidence -Bytes ([System.Text.Encoding]::UTF8.GetBytes(
        '{"AppId":"' + $script:Target.AppModuleId + '","AppId":"' + $script:Target.AppModuleId +
        '","Components":[{"entityid":"' + $taCanaryId + '","@odata.type":"Microsoft.Dynamics.CRM.entity"}]}'
    )) -AppId $script:Target.AppModuleId -TaEntityId $taCanaryId -SystemEntityId $systemEntityCanaryId
} 'Reject duplicate top-level JSON keys in final wire body' 'only one AppId'
Assert-Rejected {
    Get-TACanaryWireBodyEvidence -Bytes ([System.Text.Encoding]::UTF8.GetBytes(
        '{"AppId":"' + $script:Target.AppModuleId + '","Components":[{"entityid":"' + $taCanaryId +
        '","entityid":"' + $taCanaryId + '","@odata.type":"Microsoft.Dynamics.CRM.entity"}]}'
    )) -AppId $script:Target.AppModuleId -TaEntityId $taCanaryId -SystemEntityId $systemEntityCanaryId
} 'Reject duplicate component JSON keys in final wire body' 'duplicate.*unexpected identity properties'
Assert-Rejected {
    $systemWire = [System.Text.Encoding]::UTF8.GetBytes(
        '{"AppId":"' + $script:Target.AppModuleId + '","Components":[{"entityid":"' +
        $systemEntityCanaryId + '","@odata.type":"Microsoft.Dynamics.CRM.entity"}]}'
    )
    Get-TACanaryWireBodyEvidence -Bytes $systemWire -AppId $script:Target.AppModuleId `
        -TaEntityId $taCanaryId -SystemEntityId $systemEntityCanaryId
} 'Reject system entity identity in final JSON bytes' 'differs from the verified TA'

$canaryRoleFixtures = @(
    [pscustomobject]@{ Name = 'System Administrator'; RoleId = 'role-admin' }
    [pscustomobject]@{ Name = 'System Customizer'; RoleId = 'role-customizer' }
)
$canaryAssetFixtures = @(
    foreach ($name in @('os_sr_ta', 'os_sr_pos', 'os_sr_csrc', 'os_sr_loc')) {
        [pscustomobject]@{
            LogicalName = $name
            MainFormPresentDirectly = $true; MainFormDirectMatchCount = 1
            ActiveViewPresentDirectly = $true; ActiveViewDirectMatchCount = 1
        }
    }
)
$canaryReferenceFixtures = @(
    foreach ($index in 1..4) {
        [pscustomobject]@{
            LogicalName = @('os_sr_ta', 'os_sr_pos', 'os_sr_csrc', 'os_sr_loc')[$index - 1]
            TableMetadataId = @(
                $taCanaryId
                '33333333-aaaa-4bbb-8ccc-333333333333'
                '44444444-aaaa-4bbb-8ccc-444444444444'
                '55555555-aaaa-4bbb-8ccc-555555555555'
            )[$index - 1]
            EntitySetName = "synthetic_$index"
            MainForm = [pscustomobject]@{ Id = "form-$index" }
            ActiveView = [pscustomobject]@{ Id = "view-$index" }
            Payloads = @(
                [ordered]@{ entityid = @(
                    $taCanaryId
                    '33333333-aaaa-4bbb-8ccc-333333333333'
                    '44444444-aaaa-4bbb-8ccc-444444444444'
                    '55555555-aaaa-4bbb-8ccc-555555555555'
                )[$index - 1]; '@odata.type' = 'Microsoft.Dynamics.CRM.entity' }
                [ordered]@{ formid = "form-$index"; '@odata.type' = 'Microsoft.Dynamics.CRM.systemform' }
                [ordered]@{ savedqueryid = "view-$index"; '@odata.type' = 'Microsoft.Dynamics.CRM.savedquery' }
            )
        }
    }
)
$canaryBeforeFixture = [pscustomobject]@{
    AppModule = [pscustomobject]@{
        Id = 'app-id'; IdUnique = 'app-unique'; UniqueName = 'srapp'; StateCode = 0; ComponentState = 1
    }
    SiteMap = [pscustomobject]@{ Id = 'sitemap-id'; UniqueName = 'srapp'; SitemapXml = '<SiteMap />' }
    SiteMapNavigationBefore = @([pscustomobject]@{ AreaId = 'area'; GroupId = 'group'; SubAreaId = 'placeholder' })
    AppModuleRoles = $canaryRoleFixtures
    ReferenceComponents = $canaryReferenceFixtures
}
$canaryAfterFixture = [pscustomobject]@{
    AppModule = [pscustomobject]@{
        Id = 'app-id'; IdUnique = 'app-unique'; UniqueName = 'srapp'; StateCode = 0; ComponentState = 1
    }
    SiteMap = [pscustomobject]@{ Id = 'sitemap-id'; UniqueName = 'srapp'; SitemapXml = '<SiteMap />' }
    SiteMapNavigationBefore = @([pscustomobject]@{ AreaId = 'area'; GroupId = 'group'; SubAreaId = 'placeholder' })
    AppModuleRoles = $canaryRoleFixtures
    ReferenceComponents = $canaryReferenceFixtures
    DirectReferenceUiAssociationEvidence = [pscustomobject]@{
        IntendedSiteMapPresentDirectly = $true
        AppAssociationMatchesForEveryComponent = $true
        Assets = $canaryAssetFixtures
    }
    RawAppComponentTypeCounts = [pscustomobject]@{
        SiteMap = 1; Entity = 1; Form = 4; View = 4; Other = 0; Total = 10
    }
    EntityResolutionDiagnostics = @([pscustomobject]@{
        ReturnedRowCount = 1; NormalizedLogicalName = 'os_sr_ta'; AppAssociationMatches = $true
        EntityIdMatchesQueriedObjectId = @($true)
        ObjectIdEqualsPayloadEntityId = $true; PayloadEntityIdEqualsEntityId = $true
    })
    EntityRootRepairEvidence = [pscustomobject]@{
        SystemEntity = [pscustomobject]@{ EntityId = $systemEntityCanaryId }
        ApprovedTables = @([pscustomobject]@{
            LogicalName = 'os_sr_ta'; MetadataSurfaceFound = $true
            EntityTableSurfaceFound = $true; EntityTableRowCount = 1
            EntityTableIdentityUnambiguous = $true; EntityId = $taCanaryId; MetadataId = $taCanaryId
            LogicalNamesAgree = $true; MetadataIdEqualsEntityId = $true
            PayloadEntityIdMatchesMetadataId = $true; PayloadEntityIdMatchesEntityId = $true
            MetadataObjectTypeCode = 11005; EntityObjectTypeCodes = @(11005); ObjectTypeCodesAgree = $true
        })
        Plan = [pscustomobject]@{ ProjectTableRootCounts = @{ os_sr_ta = 1; os_sr_pos = 0; os_sr_csrc = 0; os_sr_loc = 0 } }
    }
    AppValidation = [pscustomobject]@{
        ValidationSuccess = $true; BlockingErrorCount = 0; Issues = @()
    }
}
$script:SystemEntityIdForRemoval = $systemEntityCanaryId
$forensicsSnapshot = $canaryAfterFixture.PSObject.Copy()
$forensicsSnapshot | Add-Member -NotePropertyName AddAppComponentsContract -NotePropertyValue ([pscustomobject]@{
    Action = 'Microsoft.Dynamics.CRM.AddAppComponents'
    AppIdType = 'Edm.Guid'
    ComponentsType = 'Collection(mscrm.crmbaseentity)'
    EntityType = [pscustomobject]@{
        Name = 'Microsoft.Dynamics.CRM.entity'
        BaseType = 'Microsoft.Dynamics.CRM.crmbaseentity'
        PrimaryKey = 'entityid'
        PrimaryKeyType = 'Edm.Guid'
        EntitySetName = 'entities'
        EntitySetType = 'Microsoft.Dynamics.CRM.entity'
    }
})
$forensicsSnapshot.EntityResolutionDiagnostics = @([pscustomobject]@{
    ReturnedRowCount = 1; NormalizedLogicalName = 'entity'; AppAssociationMatches = $true
    EntityIdMatchesQueriedObjectId = @($true)
})
$forensicsSnapshot | Add-Member -NotePropertyName RequestCounts -NotePropertyValue ([ordered]@{ GET = 0; POST = 0; PATCH = 0 })
$canaryForensics = Get-AddAppComponentsForensics -Snapshot $forensicsSnapshot
Assert-Test ($canaryForensics.CurrentStateClassification -ceq 'WRONG_SYSTEM_ENTITY_ROOT_CURRENT') `
    'Recognize the current ten-component wrong-canary-root state'
Assert-Test ($canaryForensics.RawBuilder.AllStagesEqual -and
    @($canaryForensics.RawBuilder.Stages).Count -eq 7 -and
    @($canaryForensics.RawBuilder.Stages | Where-Object { $_.Sha256 -notmatch '^[0-9a-f]{64}$' }).Count -eq 0) `
    'Prove TA identity survives every reconstructed raw body stage with sanitized hashes'
Assert-Test ($canaryForensics.RawBuilder.ComponentCount -eq 1 -and
    $canaryForensics.RawBuilder.ODataType -ceq 'Microsoft.Dynamics.CRM.entity' -and
    $canaryForensics.RawBuilder.NoAdditionalIdentityProperties -and
    $canaryForensics.RawBuilder.NoDuplicatePropertyNames -and
    $canaryForensics.RawBuilder.TypeCoercionDetected -eq $false -and
    $canaryForensics.RawBuilder.ObjectReplacementDetected -eq $false) `
    'Reconstruct the exact one-component raw JSON contract locally without dispatch'
Assert-Test ($canaryForensics.SerializerComparison.SameOrderedDictionaryConstruction -and
    $canaryForensics.SerializerComparison.SamePropertyInsertionPattern -and
    -not $canaryForensics.SerializerComparison.SameJsonDepth -and
    $canaryForensics.SerializerComparison.CanaryJsonDepth -eq 10 -and
    $canaryForensics.SerializerComparison.ExistingAddComponentsJsonDepth -eq 30 -and
    $canaryForensics.SerializerComparison.CustomConverterUsed -eq $false) `
    'Compare entity, form, and view object and serializer behavior'
Assert-Test ($canaryForensics.Sdk.Available -and
    $canaryForensics.Sdk.RequestType -ceq 'Microsoft.Crm.Sdk.Messages.AddAppComponentsRequest' -and
    $canaryForensics.Sdk.ComponentsType -ceq 'Microsoft.Xrm.Sdk.EntityReferenceCollection' -and
    $canaryForensics.Sdk.ComponentCount -eq 1 -and
    $canaryForensics.Sdk.LogicalName -ceq 'os_sr_ta' -and
    $canaryForensics.Sdk.ComponentIdMatchesTaMetadataId -and
    $canaryForensics.Sdk.AppIdMatchesSrapp -and
    $canaryForensics.Sdk.ExecuteCalls -eq 0) `
    'Construct one real SDK EntityReferenceCollection and AddAppComponentsRequest without Execute'
Assert-Test ($canaryForensics.RawSdkComparison -ceq 'CONTRACTS_SEMANTICALLY_EQUIVALENT' -and
    $canaryForensics.RootCauseClassification -ceq 'RAW_WEBAPI_ENTITY_REFERENCE_UNTRUSTED' -and
    $canaryForensics.Decision -ceq 'SDK_PIVOT_RECOMMENDED') `
    'Recommend the SDK pivot only for equivalent raw semantics and the wrong current root'
Assert-Test (@($canaryForensics.WriteCounts.Values | Where-Object { $_ -ne 0 }).Count -eq 0 -and
    -not $canaryForensics.FutureSdkCanary.CurrentRunExecutesSdkRequest) `
    'Forensics construction reports zero writes and never executes the SDK request'
$forensicsAst = (Get-Command Get-AddAppComponentsForensics -CommandType Function).ScriptBlock.Ast
$sdkConstructionAst = (Get-Command New-TACanarySdkRequest -CommandType Function).ScriptBlock.Ast
$executeCalls = @($forensicsAst.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and
        $node.Member.Value -ieq 'Execute'
}, $true)) + @($sdkConstructionAst.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and
        $node.Member.Value -ieq 'Execute'
}, $true))
Assert-Test ($executeCalls.Count -eq 0) 'Diagnostic and SDK construction helpers contain no Execute invocation'
$sdkRequestFixture = New-TACanarySdkRequest -AppId $script:Target.AppModuleId `
    -TaLogicalName 'os_sr_ta' -TaMetadataId $taCanaryId `
    -SystemEntityMetadataId $systemEntityCanaryId
$sdkRequestEvidence = Assert-SdkTaEntityCanaryRequest -Request $sdkRequestFixture.Request `
    -TaMetadataId $taCanaryId -SystemEntityMetadataId $systemEntityCanaryId
Assert-Test ($sdkRequestEvidence.ComponentCount -eq 1 -and
    $sdkRequestEvidence.LogicalName -ceq 'os_sr_ta' -and
    $sdkRequestEvidence.ComponentIdAlias -ceq 'os_sr_ta.MetadataId' -and
    $sdkRequestEvidence.ComponentIdMatchesTaMetadataId -and
    $sdkRequestEvidence.ComponentIdDiffersFromSystemMetadataId -and
    $sdkRequestEvidence.AppIdAlias -ceq 'srapp' -and
    $sdkRequestEvidence.Fingerprint -match '^[0-9a-f]{64}$') `
    'Fingerprint one os_sr_ta SDK EntityReference using MetadataId and safe aliases only'
Assert-Rejected {
    $sdkRequestFixture.Request.Components[0].Id = [guid]$systemEntityCanaryId
    Assert-SdkTaEntityCanaryRequest -Request $sdkRequestFixture.Request `
        -TaMetadataId $taCanaryId -SystemEntityMetadataId $systemEntityCanaryId
} 'Reject the system entity MetadataId as the TA SDK component ID' 'freshly verified TA MetadataId'
$sdkRequestFixture = New-TACanarySdkRequest -AppId $script:Target.AppModuleId `
    -TaLogicalName 'os_sr_ta' -TaMetadataId $taCanaryId `
    -SystemEntityMetadataId $systemEntityCanaryId
Assert-Rejected {
    $sdkRequestFixture.Request.Components[0].LogicalName = 'entity'
    Assert-SdkTaEntityCanaryRequest -Request $sdkRequestFixture.Request `
        -TaMetadataId $taCanaryId -SystemEntityMetadataId $systemEntityCanaryId
} 'Reproduce and reject EntityReference(entity, TA MetadataId) from Phase 2D.3K' 'exactly one os_sr_ta reference'
Assert-Rejected {
    New-TACanarySdkRequest -AppId $script:Target.AppModuleId `
        -TaLogicalName 'entity' -TaMetadataId $taCanaryId `
        -SystemEntityMetadataId $systemEntityCanaryId
} 'Reject system logical name before SDK request construction' 'os_sr_ta logical name'
Assert-Rejected {
    New-TACanarySdkRequest -AppId $script:Target.AppModuleId `
        -TaLogicalName 'os_sr_ta' -TaMetadataId $systemEntityCanaryId `
        -SystemEntityMetadataId $systemEntityCanaryId
} 'Reject system MetadataId before SDK request construction' 'distinct, valid TA/system'
$sdkRequestFixture = New-TACanarySdkRequest -AppId $script:Target.AppModuleId `
    -TaLogicalName 'os_sr_ta' -TaMetadataId $taCanaryId `
    -SystemEntityMetadataId $systemEntityCanaryId
$dependencyFixtureRoot = Join-Path $env:TEMP "bso-sr-sdk-dependency-$([guid]::NewGuid().ToString('N'))"
try {
    $standardDiPath = Join-Path $dependencyFixtureRoot `
        'microsoft.extensions.dependencyinjection\3.1.9\lib\netstandard2.0\Microsoft.Extensions.DependencyInjection.dll'
    $frameworkDiPath = Join-Path $dependencyFixtureRoot `
        'microsoft.extensions.dependencyinjection\3.1.9\lib\net461\Microsoft.Extensions.DependencyInjection.dll'
    $loggingAbstractionsPath = Join-Path $dependencyFixtureRoot `
        'microsoft.extensions.logging.abstractions\3.1.9\lib\netstandard2.0\Microsoft.Extensions.Logging.Abstractions.dll'
    $loggingPath = Join-Path $dependencyFixtureRoot `
        'microsoft.extensions.logging\3.1.9\lib\netcoreapp3.1\Microsoft.Extensions.Logging.dll'
    foreach ($path in @($standardDiPath, $frameworkDiPath, $loggingAbstractionsPath, $loggingPath)) {
        $directory = Split-Path -Parent $path
        if (-not (Test-Path -LiteralPath $directory)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }
        New-Item -ItemType File -Path $path -Force | Out-Null
    }
    $dependencyReferences = @(
        [System.Reflection.AssemblyName]::new(
            'Microsoft.Extensions.DependencyInjection, Version=3.1.9.0, Culture=neutral, PublicKeyToken=adb9793829ddae60'
        ),
        [System.Reflection.AssemblyName]::new(
            'Microsoft.Extensions.Logging.Abstractions, Version=3.1.9.0, Culture=neutral, PublicKeyToken=adb9793829ddae60'
        )
    )
    $dependencyPaths = @(Get-TACanaryServiceClientDependencyAssemblyPaths `
        -AssemblyReferences $dependencyReferences -PackageRoot $dependencyFixtureRoot)
    Assert-Test ($dependencyPaths.Count -eq 3 -and
        $dependencyPaths -contains $standardDiPath -and
        $dependencyPaths -notcontains $frameworkDiPath -and
        $dependencyPaths -contains $loggingAbstractionsPath -and
        $dependencyPaths -contains $loggingPath) `
        'Resolve exact SDK dependency versions and prefer compatible assets, including transitive Microsoft.Extensions assemblies'
    Assert-Rejected {
        Get-TACanaryServiceClientDependencyAssemblyPaths `
            -AssemblyReferences @([System.Reflection.AssemblyName]::new(
                'Microsoft.Extensions.Http, Version=3.1.9.0, Culture=neutral, PublicKeyToken=adb9793829ddae60'
            )) -PackageRoot $dependencyFixtureRoot
    } 'Fail closed when an exact ServiceClient dependency asset is missing' 'exact package asset missing'
    Assert-Rejected {
        Get-TACanaryServiceClientDependencyAssemblyPaths -AssemblyReferences @(
            [System.Reflection.AssemblyName]::new(
                'Microsoft.Extensions.DependencyInjection, Version=3.1.9.0, Culture=neutral, PublicKeyToken=adb9793829ddae60'
            ),
            [System.Reflection.AssemblyName]::new(
                'Microsoft.Extensions.Logging.Abstractions, Version=3.1.8.0, Culture=neutral, PublicKeyToken=adb9793829ddae60'
            )
        ) -PackageRoot $dependencyFixtureRoot
    } 'Fail closed when ServiceClient dependency versions are mixed' 'do not share one package version'
}
finally {
    if (Test-Path -LiteralPath $dependencyFixtureRoot) {
        Remove-Item -LiteralPath $dependencyFixtureRoot -Recurse -Force
    }
}
$retryClientFixture = [pscustomobject]@{
    MaxRetryCount = 5; IsReady = $true; ExecuteCalls = 0; LastError = ''; LastException = $null
    SessionTrackingId = $null
}
Assert-Test ((Set-SdkClientNoRetries -Client $retryClientFixture) -eq 0 -and
    $retryClientFixture.MaxRetryCount -eq 0) 'Set ServiceClient MaxRetryCount to zero'
$retryClientFixture | Add-Member -MemberType ScriptMethod -Name Execute -Value {
    param($request)
    $this.ExecuteCalls++
    [pscustomobject]@{ Response = 'synthetic' }
}
$script:SdkExecuteCount = 0
$sdkExecuteResult = Invoke-SdkTaEntityCanaryExecuteOnce -Client $retryClientFixture `
    -Request $sdkRequestFixture.Request -TaMetadataId $taCanaryId `
    -SystemEntityMetadataId $systemEntityCanaryId -ExpectedFingerprint $sdkRequestEvidence.Fingerprint
Assert-Test ($sdkExecuteResult.Attempted -and $sdkExecuteResult.Succeeded -and
    $retryClientFixture.ExecuteCalls -eq 1 -and $script:SdkExecuteCount -eq 1) `
    'Execute the SDK request exactly once after validating zero retries and request shape'
Assert-Rejected {
    Invoke-SdkTaEntityCanaryExecuteOnce -Client $retryClientFixture `
        -Request $sdkRequestFixture.Request -TaMetadataId $taCanaryId `
        -SystemEntityMetadataId $systemEntityCanaryId -ExpectedFingerprint $sdkRequestEvidence.Fingerprint
} 'Block a second SDK Execute attempt' 'no prior Execute'
Assert-Test ($retryClientFixture.ExecuteCalls -eq 1) 'Second Execute guard does not call ServiceClient again'
$retryClientFixture.ExecuteCalls = 0
$retryClientFixture | Add-Member -MemberType ScriptMethod -Name Execute -Value {
    $this.ExecuteCalls++
    throw 'synthetic SDK failure'
} -Force
$script:SdkExecuteCount = 0
$sdkExceptionResult = Invoke-SdkTaEntityCanaryExecuteOnce -Client $retryClientFixture `
    -Request $sdkRequestFixture.Request -TaMetadataId $taCanaryId `
    -SystemEntityMetadataId $systemEntityCanaryId -ExpectedFingerprint $sdkRequestEvidence.Fingerprint
Assert-Test (-not $sdkExceptionResult.Succeeded -and $sdkExceptionResult.Attempted -and
    $retryClientFixture.ExecuteCalls -eq 1 -and $script:SdkExecuteCount -eq 1) `
    'SDK exception path records one attempt and never retries'
$script:SdkExecuteCount = 0
$sdkModeWas = $SdkTaEntityCanary
$organizationUrlWas = $OrganizationUrl
$apiRootWas = $script:ApiRoot
$writesAllowedWas = $script:WritesAllowed
$requestCountsWas = $script:RequestCounts
try {
    $SdkTaEntityCanary = $true
    $OrganizationUrl = 'https://org.synthetic.crm.dynamics.com/'
    $script:ApiRoot = $OrganizationUrl + 'api/data/v9.2/'
    $script:WritesAllowed = $true
    Assert-Rejected {
        Invoke-DataverseRequest -Method POST -Path 'AddAppComponents' -Body ([ordered]@{})
    } 'Block raw AddAppComponents in the SDK TA canary mode' 'only one RemoveAppComponents POST'
}
finally {
    $SdkTaEntityCanary = $sdkModeWas
    $OrganizationUrl = $organizationUrlWas
    $script:ApiRoot = $apiRootWas
    $script:WritesAllowed = $writesAllowedWas
    $script:RequestCounts = $requestCountsWas
}
Assert-Test ($script:ExternalCalls -eq 0) 'Blocked raw AddAppComponents guard makes no token or network call'
$sdkOutcomeProtected = [pscustomobject]@{
    SiteMapUnchanged = $true; ComponentAssociationsIntact = $true; FormsAndViewsUnchanged = $true
    RolesUnchanged = $true; AppActiveUnpublished = $true
}
Assert-Test ((Get-SdkTaEntityCanaryOutcome -Before $canaryBeforeFixture -After $canaryAfterFixture `
    -ProtectedState $sdkOutcomeProtected -ExecuteResult ([pscustomobject]@{ Succeeded = $true; HttpStatus = $null })) -ceq
    'CORRECT_LOGICALNAME_CANARY_VERIFIED') 'Reconcile one SDK TA root by the entities logical-name identity chain'
$sdkWrongRootFixture = $canaryAfterFixture.PSObject.Copy()
$sdkWrongRootFixture.EntityResolutionDiagnostics = @([pscustomobject]@{
    ReturnedRowCount = 1; NormalizedLogicalName = 'entity'; EntityIdMatchesQueriedObjectId = @($true)
    AppAssociationMatches = $true
})
Assert-Test ((Get-SdkTaEntityCanaryOutcome -Before $canaryBeforeFixture -After $sdkWrongRootFixture `
    -ProtectedState $sdkOutcomeProtected -ExecuteResult ([pscustomobject]@{ Succeeded = $true; HttpStatus = $null })) -ceq
    'SYSTEM_ENTITY_ROOT_RECREATED') 'Classify a recreated system entity root without automatic removal'
$sdkWrongEntityFixture = $canaryAfterFixture.PSObject.Copy()
$sdkWrongEntityFixture.EntityResolutionDiagnostics = @([pscustomobject]@{
    ReturnedRowCount = 1; NormalizedLogicalName = 'os_sr_pos'; EntityIdMatchesQueriedObjectId = @($true)
    AppAssociationMatches = $true
})
Assert-Test ((Get-SdkTaEntityCanaryOutcome -Before $canaryBeforeFixture -After $sdkWrongEntityFixture `
    -ProtectedState $sdkOutcomeProtected -ExecuteResult ([pscustomobject]@{ Succeeded = $true; HttpStatus = $null })) -ceq
    'WRONG_ENTITY_ROOT_CREATED') 'Classify any non-TA table root'
$sdkMultipleRootsFixture = $canaryAfterFixture.PSObject.Copy()
$sdkMultipleRootsFixture.RawAppComponentTypeCounts = [pscustomobject]@{
    SiteMap = 1; Entity = 2; Form = 4; View = 4; Other = 0; Total = 11
}
Assert-Test ((Get-SdkTaEntityCanaryOutcome -Before $canaryBeforeFixture -After $sdkMultipleRootsFixture `
    -ProtectedState $sdkOutcomeProtected -ExecuteResult ([pscustomobject]@{ Succeeded = $true; HttpStatus = $null })) -ceq
    'MULTIPLE_ROOTS_CREATED') 'Classify duplicate SDK entity roots'
$sdkNoRootFixture = $canaryAfterFixture.PSObject.Copy()
$sdkNoRootFixture.RawAppComponentTypeCounts = [pscustomobject]@{
    SiteMap = 1; Entity = 0; Form = 4; View = 4; Other = 0; Total = 9
}
$sdkNoRootFixture.EntityResolutionDiagnostics = @()
Assert-Test ((Get-SdkTaEntityCanaryOutcome -Before $canaryBeforeFixture -After $sdkNoRootFixture `
    -ProtectedState $sdkOutcomeProtected -ExecuteResult ([pscustomobject]@{ Succeeded = $true; HttpStatus = $null })) -ceq
    'NO_ROOT_CREATED') 'Classify a completed SDK Execute without a root'
Assert-Test ((Get-SdkTaEntityCanaryOutcome -Before $canaryBeforeFixture -After $sdkNoRootFixture `
    -ProtectedState $sdkOutcomeProtected -ExecuteResult ([pscustomobject]@{ HttpStatus = 401 })) -ceq
    'SDK_FAILED_AUTH') 'Classify SDK authentication failure'
$sdkSequenceText = (Get-Command Invoke-SdkTaEntityCanary -CommandType Function).ScriptBlock.Ast.Extent.Text
$removeSequenceIndex = $sdkSequenceText.IndexOf('Invoke-SdkTaEntityCanaryRemoval', [StringComparison]::Ordinal)
$cleanSequenceIndex = $sdkSequenceText.IndexOf('Assert-SdkTaEntityCanaryCleanState', [StringComparison]::Ordinal)
$executeSequenceIndex = $sdkSequenceText.IndexOf('Invoke-SdkTaEntityCanaryExecuteOnce', [StringComparison]::Ordinal)
Assert-Test ($removeSequenceIndex -ge 0 -and $removeSequenceIndex -lt $cleanSequenceIndex -and
    $cleanSequenceIndex -lt $executeSequenceIndex) `
    'Require RemoveAppComponents reconciliation to clean nine components before SDK Execute'
$canaryPreflightFixture = [pscustomobject]@{
    IdentityChecks = [pscustomobject]@{
        PacIdentityAvailable = $true; AzIdentityAvailable = $true; DataverseIdentityAvailable = $true
        PacAzWhoAmIMatch = $true; ExpectedUserConfigured = $true; ExpectedUserMatch = $true
    }
    Solution = [pscustomobject]@{ UniqueName = 'os_sr_bso_rs_support'; IsManaged = $false }
    SolutionPublisher = [pscustomobject]@{ UniqueName = 'os_bso_rs_support'; CustomizationPrefix = 'os' }
    AddAppComponentsContract = [pscustomobject]@{
        Action = 'Microsoft.Dynamics.CRM.AddAppComponents'; AppIdType = 'Edm.Guid'
        ComponentsType = 'Collection(mscrm.crmbaseentity)'
        ComponentEntityTypes = @([pscustomobject]@{
            EntityType = 'Microsoft.Dynamics.CRM.entity'; PrimaryKey = 'entityid'
        })
    }
    AppModule = [pscustomobject]@{
        Id = $script:Target.AppModuleId; IdUnique = $script:Target.AppModuleIdUnique
        Name = 'BSO-RS-Support'; UniqueName = 'srapp'; StateCode = 0; ComponentState = 1
    }
    SiteMap = [pscustomobject]@{
        Id = $script:Target.SiteMapId; UniqueName = 'srapp'; IsAppAware = $true
    }
    SiteMapNavigationBefore = @([pscustomobject]@{
        AreaTitle = 'Area1'; GroupTitle = 'Group1'; Title = 'Subarea1'; Entity = $null
    })
    RawAppComponentTypeCounts = [pscustomobject]@{
        SiteMap = 1; Entity = 0; Form = 4; View = 4; Other = 0; Total = 9
    }
    ReferenceComponents = $canaryReferenceFixtures
    DirectReferenceUiAssociationEvidence = [pscustomobject]@{
        IntendedSiteMapPresentDirectly = $true; SiteMapCount = 1
        AppAssociationMatchesForEveryComponent = $true; Assets = $canaryAssetFixtures
    }
    AppModuleRoles = $canaryRoleFixtures
    AppValidation = [pscustomobject]@{ ValidationSuccess = $true; BlockingErrorCount = 0 }
    EntityRootRepairEvidence = [pscustomobject]@{
        SystemEntity = [pscustomobject]@{
            RowCount = 1; UniqueIdCount = 1; LogicalNames = @('entity')
        }
        ApprovedTables = @([pscustomobject]@{
            LogicalName = 'os_sr_ta'; MetadataSurfaceFound = $true
            EntityTableSurfaceFound = $true; EntityTableRowCount = 1
            EntityTableIdentityUnambiguous = $true; EntityId = $taCanaryId; MetadataId = $taCanaryId
            LogicalNamesAgree = $true; MetadataIdEqualsEntityId = $true
            PayloadEntityIdMatchesMetadataId = $true; PayloadEntityIdMatchesEntityId = $true
            MetadataObjectTypeCode = 11005; EntityObjectTypeCodes = @(11005); ObjectTypeCodesAgree = $true
        })
    }
}
$canaryPreflightIdentity = Assert-TACanaryPreflight -Snapshot $canaryPreflightFixture
Assert-Test ($canaryPreflightIdentity.TaEntityId -ceq $taCanaryId -and
    $canaryPreflightIdentity.SystemEntityId -ceq $systemEntityCanaryId) `
    'Pass exact nine-component, identity, role, app, Site Map and TA metadata preflight'
$originalGetEntityDefinitionByLogicalNameForSdk = (Get-Command Get-EntityDefinitionByLogicalName -CommandType Function).ScriptBlock
$originalGetEntityRowsByLogicalNameForSdk = (Get-Command Get-EntityRowsByLogicalName -CommandType Function).ScriptBlock
$script:SdkMetadataLookupNames = [System.Collections.Generic.List[string]]::new()
Set-Item -Path Function:Get-EntityDefinitionByLogicalName -Value {
    param([string]$LogicalName)
    $script:SdkMetadataLookupNames.Add("metadata:$LogicalName")
    if ($LogicalName -ceq 'os_sr_ta') {
        return [pscustomobject]@{
            MetadataId = $taCanaryId; LogicalName = 'os_sr_ta'; ObjectTypeCode = 11005
        }
    }
    [pscustomobject]@{
        MetadataId = $systemEntityCanaryId; LogicalName = 'entity'; ObjectTypeCode = 1
    }
}
Set-Item -Path Function:Get-EntityRowsByLogicalName -Value {
    param([string]$LogicalName)
    $script:SdkMetadataLookupNames.Add("entities:$LogicalName")
    if ($LogicalName -ceq 'os_sr_ta') {
        return @([pscustomobject]@{
            entityid = $taCanaryId; logicalname = 'os_sr_ta'; objecttypecode = 11005
        })
    }
    @([pscustomobject]@{
        entityid = $systemEntityCanaryId; logicalname = 'entity'; objecttypecode = 1
    })
}
try {
    $sdkMetadataIdentity = Get-SdkTaCanaryMetadataIdentity -Snapshot $canaryPreflightFixture
    Assert-Test ($sdkMetadataIdentity.TaLogicalName -ceq 'os_sr_ta' -and
        $sdkMetadataIdentity.TaMetadataId -ceq $taCanaryId -and
        $sdkMetadataIdentity.TaEntityId -ceq $taCanaryId -and
        $sdkMetadataIdentity.TaObjectTypeCode -eq 11005 -and
        $sdkMetadataIdentity.SystemLogicalName -ceq 'entity' -and
        $sdkMetadataIdentity.SystemMetadataId -ceq $systemEntityCanaryId -and
        $sdkMetadataIdentity.SystemEntityId -ceq $systemEntityCanaryId -and
        $sdkMetadataIdentity.TaMetadataId -cne $sdkMetadataIdentity.SystemMetadataId) `
        'Resolve fresh TA/system MetadataId and entities identity from both GET-only surfaces'
    Assert-Test ($script:SdkMetadataLookupNames.Count -eq 4 -and
        @($script:SdkMetadataLookupNames | Where-Object { $_ -ceq 'metadata:os_sr_ta' }).Count -eq 1 -and
        @($script:SdkMetadataLookupNames | Where-Object { $_ -ceq 'metadata:entity' }).Count -eq 1 -and
        @($script:SdkMetadataLookupNames | Where-Object { $_ -ceq 'entities:os_sr_ta' }).Count -eq 1 -and
        @($script:SdkMetadataLookupNames | Where-Object { $_ -ceq 'entities:entity' }).Count -eq 1) `
        'Resolve both logical tables from EntityDefinitions and entities exactly once'
    Set-Item -Path Function:Get-EntityDefinitionByLogicalName -Value {
        param([string]$LogicalName)
        if ($LogicalName -ceq 'os_sr_ta') {
            return [pscustomobject]@{
                MetadataId = $otherTableCanaryId; LogicalName = 'os_sr_ta'; ObjectTypeCode = 11005
            }
        }
        [pscustomobject]@{
            MetadataId = $systemEntityCanaryId; LogicalName = 'entity'; ObjectTypeCode = 1
        }
    }
    Assert-Rejected {
        Get-SdkTaCanaryMetadataIdentity -Snapshot $canaryPreflightFixture
    } 'Reject MetadataId disagreement with the approved TA table identity' 'do not agree'
}
finally {
    Set-Item -Path Function:Get-EntityDefinitionByLogicalName -Value $originalGetEntityDefinitionByLogicalNameForSdk
    Set-Item -Path Function:Get-EntityRowsByLogicalName -Value $originalGetEntityRowsByLogicalNameForSdk
}
$sdkWrongRootPreflightFixture = $canaryPreflightFixture.PSObject.Copy()
$sdkWrongRootPreflightFixture.SiteMap = [pscustomobject]@{
    Id = $script:Target.SiteMapId; UniqueName = 'srapp'; IsAppAware = $true
    ComponentState = 0; SitemapXml = '<SiteMap />'
}
$sdkWrongRootPreflightFixture.RawAppComponentTypeCounts = [pscustomobject]@{
    SiteMap = 1; Entity = 1; Form = 4; View = 4; Other = 0; Total = 10
}
$sdkWrongRootPreflightFixture | Add-Member -NotePropertyName EntityResolutionDiagnostics -Force -NotePropertyValue @([pscustomobject]@{
    ReturnedRowCount = 1; NormalizedLogicalName = 'entity'
    EntityIdMatchesQueriedObjectId = @($true); AppAssociationMatches = $true
})
$sdkWrongRootPreflightFixture.EntityRootRepairEvidence = [pscustomobject]@{
    RemoveAppComponentsContract = [pscustomobject]@{ Valid = $true }
    SystemEntity = [pscustomobject]@{
        RowCount = 1; UniqueIdCount = 1; LogicalNames = @('entity')
    }
    ApprovedTables = @(
        foreach ($name in @('os_sr_ta', 'os_sr_pos', 'os_sr_csrc', 'os_sr_loc')) {
            $reference = @($canaryReferenceFixtures | Where-Object LogicalName -ceq $name)[0]
            [pscustomobject]@{
                LogicalName = $name; MetadataSurfaceFound = $true; EntityTableSurfaceFound = $true
                EntityTableRowCount = 1; EntityTableIdentityUnambiguous = $true
                LogicalNamesAgree = $true; MetadataIdEqualsEntityId = $true
                EntityId = $reference.TableMetadataId; MetadataId = $reference.TableMetadataId
                PayloadEntityIdMatchesMetadataId = $true; PayloadEntityIdMatchesEntityId = $true
                MetadataObjectTypeCode = 11005; EntityObjectTypeCodes = @(11005); ObjectTypeCodesAgree = $true
            }
        }
    )
    Plan = [pscustomobject]@{
        CurrentComponents = @([pscustomobject]@{
            ObjectIdEqualsSystemEntityId = $true; os_sr_ta = $false; os_sr_pos = $false
            os_sr_csrc = $false; os_sr_loc = $false
        })
        ProjectTableRootCounts = @{ os_sr_ta = 0; os_sr_pos = 0; os_sr_csrc = 0; os_sr_loc = 0 }
    }
}
$sdkWrongRootIdentity = Assert-SdkTaEntityCanaryWrongRootPreflight -Snapshot $sdkWrongRootPreflightFixture
Assert-Test ($sdkWrongRootIdentity.TaEntityId -ceq $taCanaryId -and
    $sdkWrongRootIdentity.SystemEntityId -ceq $systemEntityCanaryId) `
    'Require exactly one verified system entity root before the one logical removal'
$sdkUnexpectedWrongRootFixture = $sdkWrongRootPreflightFixture.PSObject.Copy()
$sdkUnexpectedWrongRootFixture.EntityResolutionDiagnostics = @([pscustomobject]@{
    ReturnedRowCount = 1; NormalizedLogicalName = 'os_sr_pos'
    EntityIdMatchesQueriedObjectId = @($true); AppAssociationMatches = $true
})
Assert-Rejected {
    Assert-SdkTaEntityCanaryWrongRootPreflight -Snapshot $sdkUnexpectedWrongRootFixture
} 'Stop removal if the root is not system entity' 'one verified system entity root'
$sdkCleanStateFixture = $canaryPreflightFixture.PSObject.Copy()
$sdkCleanStateFixture.SiteMap = [pscustomobject]@{
    Id = $script:Target.SiteMapId; UniqueName = 'srapp'; IsAppAware = $true
    ComponentState = 0; SitemapXml = '<SiteMap />'
}
$sdkCleanStateFixture.RawAppComponentTypeCounts = [pscustomobject]@{
    SiteMap = 1; Entity = 0; Form = 4; View = 4; Other = 0; Total = 9
}
$sdkCleanStateFixture | Add-Member -NotePropertyName EntityResolutionDiagnostics -Force -NotePropertyValue @()
$sdkCleanStateFixture.EntityRootRepairEvidence = [pscustomobject]@{
    SystemEntity = [pscustomobject]@{
        RowCount = 1; UniqueIdCount = 1; LogicalNames = @('entity')
    }
    ApprovedTables = $sdkWrongRootPreflightFixture.EntityRootRepairEvidence.ApprovedTables
    Plan = [pscustomobject]@{
        ProjectTableRootCounts = @{ os_sr_ta = 0; os_sr_pos = 0; os_sr_csrc = 0; os_sr_loc = 0 }
    }
}
$sdkCleanState = Assert-SdkTaEntityCanaryCleanState -Before $sdkWrongRootPreflightFixture -After $sdkCleanStateFixture
Assert-Test ($sdkCleanState.Identity.TaEntityId -ceq $taCanaryId -and
    $sdkCleanState.ProtectedState.SiteMapUnchanged -and
    $sdkCleanState.ProtectedState.FormsAndViewsUnchanged -and
    $sdkCleanState.ProtectedState.RolesUnchanged) `
    'Require exact clean nine-component reconciliation with all protected assets unchanged before SDK Add'
$changedCanaryBaseline = $canaryPreflightFixture.PSObject.Copy()
$changedCanaryBaseline.RawAppComponentTypeCounts = [pscustomobject]@{
    SiteMap = 1; Entity = 1; Form = 4; View = 4; Other = 0; Total = 10
}
Assert-Rejected {
    Assert-TACanaryPreflight -Snapshot $changedCanaryBaseline
} 'Stop canary when an entity root already exists' 'STATE_CHANGED'
$canaryProtected = Get-TACanaryProtectedStateUnchanged -Before $canaryBeforeFixture -After $canaryAfterFixture
$canaryVerifiedIdentity = Get-TACanaryTableIdentity -Snapshot $canaryAfterFixture
$canaryVerifiedOutcome = Get-TACanaryOutcome -Before $canaryBeforeFixture -After $canaryAfterFixture `
    -ProtectedState $canaryProtected -WriteStatus 204
Assert-Test ($canaryVerifiedOutcome -ceq 'CANARY_ROOT_VERIFIED') `
    "Verify the one TA root and unchanged protected state ($canaryVerifiedOutcome)"
$wrongSystemCanary = $canaryAfterFixture.PSObject.Copy()
$wrongSystemCanary.EntityResolutionDiagnostics = @([pscustomobject]@{
    ReturnedRowCount = 1; NormalizedLogicalName = 'entity'; AppAssociationMatches = $true
    EntityIdMatchesQueriedObjectId = @($true)
})
Assert-Test ((Get-TACanaryOutcome -Before $canaryBeforeFixture -After $wrongSystemCanary `
    -ProtectedState $canaryProtected -WriteStatus 204) -ceq 'WRONG_SYSTEM_ENTITY_ROOT_RECREATED') `
    'Classify a re-created system entity root'
$wrongTableCanary = $canaryAfterFixture.PSObject.Copy()
$wrongTableCanary.EntityResolutionDiagnostics = @([pscustomobject]@{
    ReturnedRowCount = 1; NormalizedLogicalName = 'os_sr_pos'; AppAssociationMatches = $true
    EntityIdMatchesQueriedObjectId = @($true)
})
Assert-Test ((Get-TACanaryOutcome -Before $canaryBeforeFixture -After $wrongTableCanary `
    -ProtectedState $canaryProtected -WriteStatus 204) -ceq 'WRONG_ENTITY_ROOT_CREATED') `
    'Classify a different project table root'
$multipleCanary = $canaryAfterFixture.PSObject.Copy()
$multipleCanary.RawAppComponentTypeCounts = [pscustomobject]@{
    SiteMap = 1; Entity = 2; Form = 4; View = 4; Other = 0; Total = 11
}
Assert-Test ((Get-TACanaryOutcome -Before $canaryBeforeFixture -After $multipleCanary `
    -ProtectedState $canaryProtected -WriteStatus 204) -ceq 'DUPLICATE_OR_MULTIPLE_ROOTS_CREATED') `
    'Classify multiple entity roots without repair'
$noRootCanary = $canaryAfterFixture.PSObject.Copy()
$noRootCanary.RawAppComponentTypeCounts = [pscustomobject]@{
    SiteMap = 1; Entity = 0; Form = 4; View = 4; Other = 0; Total = 9
}
$noRootCanary.EntityResolutionDiagnostics = @()
Assert-Test ((Get-TACanaryOutcome -Before $canaryBeforeFixture -After $noRootCanary `
    -ProtectedState $canaryProtected -WriteStatus 204) -ceq 'NO_ENTITY_ROOT_CREATED') `
    'Classify a completed canary POST with no root'
Assert-Test ((Get-TACanaryOutcome -Before $canaryBeforeFixture -After $canaryAfterFixture `
    -ProtectedState $canaryProtected -WriteStatus 401) -ceq 'FAILED_AUTH') 'Classify unauthorized canary write'
Assert-Test ((Get-TACanaryOutcome -Before $canaryBeforeFixture -After $canaryAfterFixture `
    -ProtectedState $canaryProtected -WriteStatus 403) -ceq 'FAILED_AUTHZ') 'Classify forbidden canary write'
$changedCanaryProtected = $canaryProtected.PSObject.Copy()
$changedCanaryProtected.SiteMapUnchanged = $false
Assert-Test ((Get-TACanaryOutcome -Before $canaryBeforeFixture -After $canaryAfterFixture `
    -ProtectedState $changedCanaryProtected -WriteStatus 204) -ceq 'PROTECTED_COMPONENT_CHANGED') `
    'Stop if protected Site Map state changes'
$changedFormAfterCanary = $canaryAfterFixture.PSObject.Copy()
$changedFormAssets = @($canaryAssetFixtures | ForEach-Object { $_.PSObject.Copy() })
$changedFormAssets[0].MainFormPresentDirectly = $false
$changedFormAfterCanary.DirectReferenceUiAssociationEvidence = [pscustomobject]@{
    IntendedSiteMapPresentDirectly = $true; AppAssociationMatchesForEveryComponent = $true
    Assets = $changedFormAssets
}
$changedFormProtected = Get-TACanaryProtectedStateUnchanged -Before $canaryBeforeFixture `
    -After $changedFormAfterCanary
Assert-Test ((Get-TACanaryOutcome -Before $canaryBeforeFixture -After $changedFormAfterCanary `
    -ProtectedState $changedFormProtected -WriteStatus 204) -ceq 'PROTECTED_COMPONENT_CHANGED') `
    'Stop if a protected form disappears'
$changedViewAfterCanary = $canaryAfterFixture.PSObject.Copy()
$changedViewAssets = @($canaryAssetFixtures | ForEach-Object { $_.PSObject.Copy() })
$changedViewAssets[0].ActiveViewPresentDirectly = $false
$changedViewAfterCanary.DirectReferenceUiAssociationEvidence = [pscustomobject]@{
    IntendedSiteMapPresentDirectly = $true; AppAssociationMatchesForEveryComponent = $true
    Assets = $changedViewAssets
}
$changedViewProtected = Get-TACanaryProtectedStateUnchanged -Before $canaryBeforeFixture `
    -After $changedViewAfterCanary
Assert-Test ((Get-TACanaryOutcome -Before $canaryBeforeFixture -After $changedViewAfterCanary `
    -ProtectedState $changedViewProtected -WriteStatus 204) -ceq 'PROTECTED_COMPONENT_CHANGED') `
    'Stop if a protected public view disappears'
$changedRoleAfterCanary = $canaryAfterFixture.PSObject.Copy()
$changedRoleAfterCanary.AppModuleRoles = @([pscustomobject]@{ Name = 'System Administrator'; RoleId = 'changed' })
$changedRoleProtected = Get-TACanaryProtectedStateUnchanged -Before $canaryBeforeFixture `
    -After $changedRoleAfterCanary
Assert-Test ((Get-TACanaryOutcome -Before $canaryBeforeFixture -After $changedRoleAfterCanary `
    -ProtectedState $changedRoleProtected -WriteStatus 204) -ceq 'PROTECTED_COMPONENT_CHANGED') `
    'Stop if the app role association changes'
$script:RequestCounts = @{ GET = 0; PATCH = 0; POST = 0 }
$script:WriteResults = [System.Collections.Generic.List[object]]::new()
$script:WritesStarted = $false
Assert-TACanaryWriteSequence
$script:RequestCounts.POST = 1
Assert-Rejected { Assert-TACanaryWriteSequence } 'Block every second canary POST' 'exactly one AddAppComponents POST'
$script:RequestCounts = @{ GET = 0; PATCH = 0; POST = 0 }
$script:WritesStarted = $false

$originalDataverseRequestForCanaryDispatch = (Get-Command Invoke-DataverseRequest -CommandType Function).ScriptBlock
$originalInvokeRestMethodForCanaryDispatch = (Get-Command Invoke-RestMethod -CommandType Function).ScriptBlock
$savedCanaryDispatchState = @{
    AddTaEntityCanary = $AddTaEntityCanary
    ReferenceUiCompositionOnly = $ReferenceUiCompositionOnly
    ApiRoot = $script:ApiRoot
    OrganizationUrl = $OrganizationUrl
    AccessToken = $script:AccessToken
    AccessTokenExpiresOn = $script:AccessTokenExpiresOn
    WritesAllowed = $script:WritesAllowed
    WritesStarted = $script:WritesStarted
    RequestCounts = $script:RequestCounts
    WriteResults = $script:WriteResults
    CanaryFinalRequest = $script:TACanaryFinalRequest
}
$AddTaEntityCanary = $true
$ReferenceUiCompositionOnly = $false
$script:ApiRoot = 'https://synthetic.crm.dynamics.com/api/data/v9.2/'
$OrganizationUrl = 'https://synthetic.crm.dynamics.com/'
$script:AccessToken = 'synthetic'
$script:AccessTokenExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1)
$script:WritesAllowed = $true
$script:WritesStarted = $false
$script:RequestCounts = @{ GET = 0; PATCH = 0; POST = 0 }
$script:WriteResults = [System.Collections.Generic.List[object]]::new()
$script:TACanaryFinalRequest = $taCanaryWireRequest
$taCanaryBody.Components[0].entityid = $otherTableCanaryId
Set-Item -Path Function:Invoke-RestMethod -Value {
    param(
        [string]$Method, [string]$Uri, [hashtable]$Headers, [int]$MaximumRedirection,
        [switch]$SkipHeaderValidation, [switch]$SkipHttpErrorCheck, [string]$StatusCodeVariable,
        [string]$ResponseHeadersVariable, [int]$TimeoutSec, [int]$MaximumRetryCount,
        [string]$ErrorAction, [string]$ContentType, [byte[]]$Body
    )
    $script:CapturedCanaryDispatchBody = [byte[]]$Body.Clone()
    Set-Variable -Name $StatusCodeVariable -Value 204 -Scope 1
    Set-Variable -Name $ResponseHeadersVariable -Value @{} -Scope 1
    $null
}
try {
    $dispatchResult = Invoke-DataverseRequest -Method POST -Path 'AddAppComponents' `
        -SerializedBodyBytes $taCanaryWireRequest.BodyBytes `
        -ExpectedSemanticFingerprint $taCanaryWireRequest.SemanticFingerprint `
        -ExpectedSerializedBodySha256 $taCanaryWireRequest.SerializedBodySha256
    Assert-Test ($script:RequestCounts.POST -eq 1 -and $script:WriteResults.Count -eq 1 -and
        $script:LastHttpStatus -eq 204) 'Dispatch exactly one canary write through the validated body path'
    Assert-Test ($script:CapturedCanaryDispatchBody.Length -eq $taCanaryWireRequest.BodyBytes.Length -and
        [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($script:CapturedCanaryDispatchBody)).ToLowerInvariant() -ceq
            $taCanaryWireRequest.SerializedBodySha256) 'HTTP dispatcher receives byte-for-byte the fingerprinted UTF-8 body'
    Assert-Test ($taCanaryBody.Components[0].entityid -ceq $otherTableCanaryId -and
        $script:CapturedCanaryDispatchBody.Length -gt 0 -and
        (Get-TACanaryWireBodyEvidence -Bytes $script:CapturedCanaryDispatchBody `
            -AppId $script:Target.AppModuleId -TaEntityId $taCanaryId `
            -SystemEntityId $systemEntityCanaryId).EntityId -ceq $taCanaryId) `
        'Do not regenerate the dispatched body from a mutated source object after fingerprinting'
    Assert-Rejected { Assert-TACanaryWriteSequence } 'Reject any repeated canary write after dispatch' 'exactly one AddAppComponents POST'
    Assert-Rejected {
        Invoke-DataverseRequest -Method PATCH -Path "sitemaps($($script:Target.SiteMapId))" `
            -Body ([ordered]@{ sitemapxml = '<SiteMap />' })
    } 'Block Site Map PATCH in TA canary mode' 'only one AddAppComponents POST'
    Assert-Rejected {
        Invoke-DataverseRequest -Method POST -Path 'RemoveAppComponents' `
            -SerializedBodyBytes $taCanaryWireRequest.BodyBytes `
            -ExpectedSemanticFingerprint $taCanaryWireRequest.SemanticFingerprint `
            -ExpectedSerializedBodySha256 $taCanaryWireRequest.SerializedBodySha256
    } 'Block RemoveAppComponents in TA canary mode' 'only one AddAppComponents POST'
    Assert-Rejected {
        Invoke-DataverseRequest -Method POST -Path 'PublishXml' `
            -SerializedBodyBytes $taCanaryWireRequest.BodyBytes `
            -ExpectedSemanticFingerprint $taCanaryWireRequest.SemanticFingerprint `
            -ExpectedSerializedBodySha256 $taCanaryWireRequest.SerializedBodySha256
    } 'Block PublishXml and every other POST in TA canary mode' 'only one AddAppComponents POST'
}
finally {
    Set-Item -Path Function:Invoke-DataverseRequest -Value $originalDataverseRequestForCanaryDispatch
    Set-Item -Path Function:Invoke-RestMethod -Value $originalInvokeRestMethodForCanaryDispatch
    $AddTaEntityCanary = $savedCanaryDispatchState.AddTaEntityCanary
    $ReferenceUiCompositionOnly = $savedCanaryDispatchState.ReferenceUiCompositionOnly
    $script:ApiRoot = $savedCanaryDispatchState.ApiRoot
    $OrganizationUrl = $savedCanaryDispatchState.OrganizationUrl
    $script:AccessToken = $savedCanaryDispatchState.AccessToken
    $script:AccessTokenExpiresOn = $savedCanaryDispatchState.AccessTokenExpiresOn
    $script:WritesAllowed = $savedCanaryDispatchState.WritesAllowed
    $script:WritesStarted = $savedCanaryDispatchState.WritesStarted
    $script:RequestCounts = $savedCanaryDispatchState.RequestCounts
    $script:WriteResults = $savedCanaryDispatchState.WriteResults
    $script:TACanaryFinalRequest = $savedCanaryDispatchState.CanaryFinalRequest
}

Assert-Test ($script:ExternalCalls -eq 0) 'All Phase 2D.3 regression coverage remains synthetic and offline'

Write-Output "PASS: $script:Passed synthetic app-composition assertions; no authentication, API calls, PAC export, or Apply invocation."