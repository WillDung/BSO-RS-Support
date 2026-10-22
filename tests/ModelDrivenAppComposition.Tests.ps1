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
}
$payloads = @(Get-AppComponentPayloads -Target $syntheticTarget)
Assert-Test ($payloads.Count -eq 3) 'Exactly three existing app components are planned'
Assert-Test ($payloads[0].'@odata.type' -ceq 'Microsoft.Dynamics.CRM.entity' -and $payloads[0].entityid -ceq $syntheticTarget.TableMetadataId) 'Entity component uses primary-key property and OData type'
Assert-Test ($payloads[1].'@odata.type' -ceq 'Microsoft.Dynamics.CRM.systemform' -and $payloads[1].formid -ceq $syntheticTarget.MainFormId) 'Form component uses primary-key property and OData type'
Assert-Test ($payloads[2].'@odata.type' -ceq 'Microsoft.Dynamics.CRM.savedquery' -and $payloads[2].savedqueryid -ceq $syntheticTarget.ActiveViewId) 'View component uses primary-key property and OData type'
Assert-Test (@($payloads | Where-Object { $_.'@odata.type' -ceq 'Microsoft.Dynamics.CRM.sitemap' }).Count -eq 0) 'Existing SiteMap binding is not duplicated in AddAppComponents'
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

Write-Output "PASS: $script:Passed synthetic app-composition assertions; no authentication, API calls, PAC export, or Apply invocation."