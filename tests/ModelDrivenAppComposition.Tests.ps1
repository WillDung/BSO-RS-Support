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
            <EntityType Name="entity"><Key><PropertyRef Name="entityid" /></Key></EntityType>
            <EntityType Name="sitemap"><Key><PropertyRef Name="sitemapid" /></Key></EntityType>
            <EntityType Name="systemform"><Key><PropertyRef Name="formid" /></Key></EntityType>
            <EntityType Name="savedquery"><Key><PropertyRef Name="savedqueryid" /></Key></EntityType>
        </Schema>
    </edmx:DataServices>
</edmx:Edmx>
'@
$contract = Get-AppComponentsContract -Metadata $metadataFixture
Assert-Test ($contract.AppIdType -ceq 'Edm.Guid' -and $contract.ComponentsType -ceq 'Collection(mscrm.crmbaseentity)') 'Validate AddAppComponents parameters from OData metadata'
Assert-Test ($contract.ComponentEntityTypes.Count -eq 4) 'Validate all required component record types'
$wrongContract = [xml]$metadataFixture.OuterXml.Replace('PropertyRef Name="sitemapid"','PropertyRef Name="wrongid"')
Assert-Rejected { Get-AppComponentsContract -Metadata $wrongContract } 'Reject invalid SiteMap primary key contract' 'lacks expected key sitemapid'
Assert-Test ($script:ExternalCalls -eq 0) 'All PlanOnly and metadata contract tests remain offline'

$phasePlan = (& $scriptPath -PlanOnly -ReferenceUiCompositionOnly) | ConvertFrom-Json
Assert-Test ($ReferenceUiCompositionOnly -eq $false -and -not (Test-AllowsProcessExpectedUserPin)) 'Do not permit process user pinning in generic composition mode'
$ReferenceUiCompositionOnly = $true
Assert-Test (Test-AllowsProcessExpectedUserPin) 'Allow process-only expected-user pin for guarded Phase 2D.3 identity verification'
$ReferenceUiCompositionOnly = $false
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

$siteMapComponent = [pscustomobject]@{ ComponentType = 62; ObjectId = $script:Target.SiteMapId }
$startingUiState = Assert-ReferenceUiComponentState -Components @($siteMapComponent)
Assert-Test ($startingUiState.SiteMapCount -eq 1 -and $startingUiState.ReferenceComponentCount -eq 0 -and
    $startingUiState.TotalComponentCount -eq 1) 'Require existing Site Map as the only starting app component'
$composedUiComponents = @(
    $siteMapComponent
    foreach ($reference in $script:ResolvedReferenceComponents) {
        foreach ($payload in $reference.Payloads) {
            $componentType = switch ([string]$payload['@odata.type']) {
                'Microsoft.Dynamics.CRM.entity' { 1 }
                'Microsoft.Dynamics.CRM.systemform' { 60 }
                'Microsoft.Dynamics.CRM.savedquery' { 26 }
            }
            $key = @($payload.Keys | Where-Object { $_ -ne '@odata.type' })[0]
            [pscustomobject]@{ ComponentType = $componentType; ObjectId = $payload[$key] }
        }
    }
)
$composedUiState = Assert-ReferenceUiComponentState -Components $composedUiComponents -RequireComposed
Assert-Test ($composedUiState.SiteMapCount -eq 1 -and $composedUiState.TableCount -eq 4 -and
    $composedUiState.MainFormCount -eq 4 -and $composedUiState.PublicViewCount -eq 4 -and
    $composedUiState.TotalComponentCount -eq 13) 'Require exact final 13-component AppModule inventory'
Assert-Rejected { Assert-ReferenceUiComponentState -Components @() } 'Reject missing starting Site Map association' 'exactly the existing Site Map'
Assert-Rejected { Assert-ReferenceUiComponentState -Components (@($composedUiComponents) + @([pscustomobject]@{ ComponentType = 1; ObjectId = 'unexpected' })) -RequireComposed } 'Reject unexpected final AppModule component' 'Unexpected direct AppModule component'
Assert-Rejected { Assert-ReferenceUiComponentState -Components (@($composedUiComponents) + @($siteMapComponent)) -RequireComposed } 'Reject duplicate Site Map component' 'exactly the existing Site Map'

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

$script:RequestCounts = @{ GET = 0; PATCH = 0; POST = 0 }
$script:WriteResults = [System.Collections.Generic.List[object]]::new()
Assert-Rejected { Assert-ReferenceUiWriteSequence -Method PATCH } 'Reject Site Map PATCH before AddAppComponents' 'after the successful single component POST'
$script:RequestCounts.POST = 1
Assert-Rejected { Assert-ReferenceUiWriteSequence -Method PATCH } 'Reject PATCH after unsuccessful or unverified component POST' 'after the successful single component POST'
$script:WriteResults.Add([pscustomobject]@{ Method = 'POST'; HttpStatus = 204 })
Assert-ReferenceUiWriteSequence -Method PATCH
Assert-Test $true 'Allow the single Site Map PATCH only after successful AddAppComponents'
Assert-Rejected { Assert-ReferenceUiWriteSequence -Method POST } 'Reject second AddAppComponents operation' 'one AddAppComponents POST'
$script:RequestCounts.PATCH = 1
Assert-Rejected { Assert-ReferenceUiWriteSequence -Method PATCH } 'Reject second Site Map PATCH' 'after the successful single component POST'
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

Assert-Test ($script:ExternalCalls -eq 0) 'All Phase 2D.3 regression coverage remains synthetic and offline'

Write-Output "PASS: $script:Passed synthetic app-composition assertions; no authentication, API calls, PAC export, or Apply invocation."