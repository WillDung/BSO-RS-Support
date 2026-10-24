#requires -Version 7.4
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$runnerPath = Join-Path $root 'scripts/Provision-BsoRsCandidateChildTables.ps1'
$manifestPath = Join-Path $root 'docs/PHASE_3A_CANDIDATE_CORE_METADATA_PLAN.json'
$modelPath = Join-Path $root 'docs/DATA_MODEL.md'
$runner = Get-Content -LiteralPath $runnerPath -Raw
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$model = Get-Content -LiteralPath $modelPath -Raw
$script:Passed = 0

function Assert-Test {
    param([bool]$Condition, [string]$Name)
    if (-not $Condition) { throw "FAIL: $Name" }
    $script:Passed++
}

$tokens = $null
$parseErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile($runnerPath, [ref]$tokens, [ref]$parseErrors) | Out-Null
Assert-Test ($parseErrors.Count -eq 0) 'Child-table runner parses without diagnostics'
Assert-Test ($runner -match "MaximumRetryCount\s*=\s*0" -and
    $runner -match "AutomaticRetries\s*=\s*0") 'Automatic retry count is fixed at zero'
Assert-Test ($runner -match "MaximumWrites\s*=\s*8" -and
    $runner -match "GlobalOptionSetDefinitions" -and
    $runner -match "RelationshipDefinitions" -and
    $runner -match "/Keys") 'Write ceiling and metadata endpoint allowlist are explicit'
Assert-Test ($runner -match "CandidateWrites\s*=\s*0" -and
    $runner -match "BusinessDataWrites\s*=\s*0" -and
    $runner -match "PublicationWrites\s*=\s*0" -and
    $runner -notmatch "PublishAllXml") 'Candidate, business data, and publication remain excluded'
Assert-Test ($runner -match '\[switch\]\$RepairStatusChoiceBindings' -and
    $runner -match '\[switch\]\$RepairPreflightOnly' -and
    $runner -match "ValidateSet\('GET', 'PUT', 'POST', 'DELETE'\)" -and
    $runner -match 'MaximumWrites = 2' -and
    $runner -match 'Get-StatusChoiceAttributePath' -and
    $runner -match 'Attributes\(\$\(\$Attribute\.MetadataId\)\)' -and
    $runner -notmatch 'Attributes\(LogicalName=''os_sr_csh_(prevstat|newstat)''\)' -and
    $runner -notmatch "ValidateSet\([^\r\n]*PATCH") 'Repair mode is restricted to two in-place PUT paths and excludes PATCH'
Assert-Test ($runner -match 'statusChoiceRepairIsAuthorized' -and
    $runner -match 'statusChoiceRepairRequested' -and
    $runner -match 'RepairPreflightOnly' -and
    $runner -match 'latestResumeClassification -ceq ''PARTIAL_METADATA_STATE''' -and
    $runner -match 'remainingMetadataAuthorizationConsumed' -and
    $runner -match 'StatusChoiceRepairWriteCount -lt 2') 'Repair mode requires the consumed-scope mismatch state and enforces the two-write ceiling'
Assert-Test ($runner -match '-not \$RepairStatusChoiceBindings' -and
    $runner -match 'LastWriteOutcomeUncertain' -and
    $runner -match 'UNCERTAIN_STOPPED' -and
    $runner -match "MaximumRetryCount\s*=\s*0") 'Repair failures do not rewrite historical provisioning state or retry uncertain PUTs'
Assert-Test ($runner -match 'OptionSet,GlobalOptionSet' -and
    $runner -match 'AttributeTypeName.Value' -and
    $runner -match 'IsCustomizable.Value' -and
    $runner -match 'DefaultFormValue' -and
    $runner -match 'AttributeMetadataIdSha256' -and
    $runner -match 'CorrectedPayloadSha256') 'Typed repair preflight captures the requested attribute metadata and payload evidence'
Assert-Test ($runner -match 'IN_PLACE_CHOICE_REBIND_UNSUPPORTED_OR_REJECTED' -and
    $runner -match 'REBIND_BLOCKED_DATA_PRESENT_OR_UNKNOWN' -and
    $runner -match 'PARTIAL_METADATA_STATE' -and
    $runner -match 'HttpStatus = \$script:LastWriteHttpStatus') 'Repair reports distinguish rejection, blocked safety gate, partial state, and exact HTTP status'
Assert-Test ($runner -match 'IMMEDIATE_GET_MISMATCH_STOPPED' -and
    $runner -match 'UNCERTAIN_GET_' -and
    $runner -match 'one GET reconciliation was attempted') 'A failed or mismatching immediate GET stops without another metadata update'
Assert-Test ($runner -match 'GlobalOptionSetDefinitions\(Name=' -and
    $runner -match 'Get-ChoiceOptionsForRepair -Choice \$callOutcomeAfter' -and
    $runner -match 'Get-ChoiceOptionsForRepair -Choice \$candidateStatusAfter' -and
    $runner -match 'ChoiceDefinitionWrites = 0') 'Repair reconciles both Choices without writing either Choice definition'
Assert-Test ($runner -match "Assert-ChildTableAbsent" -and
    $runner -match "Assert-InitialState" -and
    $runner -match "Assert-TableReadback" -and
    $runner -match "Assert-RelationshipsAndKeys" -and
    $runner -match 'READ_ONLY_STATUS_CHOICE_REPAIR_PREFLIGHT_PASSED') 'Preflight and exact post-write reconciliation paths are required'
Assert-Test ($runner -match 'primaryName\.maxLength' -and
    $runner -match 'MaxLength = \$primaryName\.MaxLength' -and
    $runner -match 'Primary-name String/AutoNumber definition is incomplete or outside the owner-approved contract' -and
    $runner -match '\$maxLength -ne 100' -and
    $runner -match "FormatName -cne 'Text'") 'Table payload creation requires the exact owner-approved primary-name contract'
Assert-Test ($runner -match 'Assert-PrimaryNameDefinition -Table \$Table' -and
    $runner -match 'SchemaName = \$primaryName\.SchemaName' -and
    $runner -match 'DisplayName = New-Label -Text \$primaryName\.DisplayName' -and
    $runner -match 'RequiredLevel = New-RequiredLevel' -and
    $runner -match 'IsPrimaryName = \$true' -and
    $runner -match 'AutoNumberFormat = \$primaryName\.AutoNumberFormat') 'Payload preserves primary-name schema, display, requiredness, primary-name flag, and AutoNumber format'
Assert-Test ($runner -match 'GlobalOptionSetDefinitions\(Name=' -and
    $runner -match "Update-ManifestChoiceValues" -and
    $runner.Contains('"relationships"\s*:')) 'Call Outcome Choice existence check and value freeze are wired'
Assert-Test ($runner -match "candidateCreateOrModification" -and
    $runner -match "customApiOrPlugin" -and
    $runner -match "securityOrAppChanges" -and
    $runner -match "publication") 'Manifest scope exclusions are enforced before any write'
Assert-Test ($runner -match 'AUTHORIZED_CORRECTED_CALLLOG_AND_REMAINING_CHILD_METADATA' -and
    $runner -match 'CORRECTED_CALLLOG_DISPATCHED_RECONCILIATION_PENDING' -and
    $runner -match 'CorrectedCallLogCreateDispatches -ge 1') 'Corrected authorization is specific and corrected Call Log create is limited to one dispatch'
Assert-Test ($runner -match 'ResumeRemainingScope' -and
    $runner -match 'Assert-CallLogResumeReadback' -and
    $runner.Contains("`$script:ExpectedTableCreateNames = @('os_sr_csh')") -and
    $runner -match 'remainingMetadataDispatchLimit -eq 7') 'Resume path reconciles existing Call Log and limits table creation to Status History'
$historyChoiceColumns = @((@($manifest.tables | Where-Object logicalName -CEQ 'os_sr_csh')[0]).columns |
    Where-Object { $_.type -ceq 'GlobalChoice' -and $_.target -ceq 'os_sr_candstat' })
Assert-Test ($runner.Contains('ChoiceMetadataByName[$targetName]') -and
    $runner.Contains('-ChoiceMetadataByName $choiceMetadataByName') -and
    $historyChoiceColumns.Count -eq 2 -and
    @($historyChoiceColumns | ForEach-Object displayName | Sort-Object) -join '|' -ceq 'New Status|Previous Status') 'Both intended status bindings are resolved from the current manifest'
Assert-Test ($manifest.relationships.Count -eq 7 -and
    @($manifest.relationships | ForEach-Object schemaName | Select-Object -Unique).Count -eq 7) 'Seven manifest relationship schema names are unique'
Assert-Test ($model -match '`usr` = Dataverse system user' -and
    $model -match 'os_sr_usr_call_ctby' -and $model -match 'os_sr_usr_csh_actr') 'User lookup naming follows the documented publisher/project convention'
Assert-Test ($manifest.callOutcomeChoice.options.Count -eq 3 -and
    @($manifest.callOutcomeChoice.options | ForEach-Object { "$($_.label)|$($_.value)" }) -join ';' -ceq
    'Answered|100010000;No Answer|100010001;Call Back Requested|100010002') 'Call Outcome labels and frozen integer values remain exact'
Assert-Test ($manifest.globalChoice.options.Count -eq 6 -and
    @($manifest.globalChoice.options | ForEach-Object { "$($_.label)|$($_.value)" }) -join ';' -ceq
    'Need Call Candidate|100010000;Candidate Answered|100010001;Waiting Manual Scheduling|100010002;Round 1 Scheduled|100010003;Offer Extended|100010004;Candidate Failed|100010005') 'Candidate Status labels and frozen integer values remain exact'
Assert-Test ($manifest.provisioning.phase3B2AuthorizedContinuation.status -ceq 'STOPPED_AFTER_REMAINING_METADATA_MISMATCH_NO_FURTHER_WRITES' -and
    $manifest.provisioning.phase3B2AuthorizedContinuation.executionOutcome.successfulChildTableWrites -eq 2 -and
    $manifest.provisioning.phase3B2AuthorizedContinuation.automaticRetries -eq 0 -and
    $manifest.provisioning.phase3B2AuthorizedContinuation.correctedCallLogCreateDispatchLimit -eq 1 -and
    $manifest.provisioning.phase3B2AuthorizedContinuation.correctedCallLogCreateDispatches -eq 1 -and
    $manifest.provisioning.phase3B2AuthorizedContinuation.remainingMetadataDispatchLimit -eq 7 -and
    $manifest.provisioning.phase3B2AuthorizedContinuation.remainingMetadataWritesDispatched -eq 7 -and
    $manifest.provisioning.phase3B2AuthorizedContinuation.remainingMetadataAuthorizationConsumed -and
    $manifest.provisioning.phase3B2AuthorizedContinuation.lastReadOnlyReconciliation.childScopeRequests.POST -eq 0) 'Remaining authorization is consumed and the Choice binding mismatch is reconciled without a retry'
Assert-Test (@($manifest.tables | Where-Object logicalName -in @('os_sr_call', 'os_sr_csh') | Where-Object {
        $_.primaryName.type -ceq 'AutoNumber' -and $_.primaryName.storageType -ceq 'String' -and
        $_.primaryName.maxLength -eq 100 -and $_.primaryName.formatName -ceq 'Text' -and
        $_.primaryName.required -ceq 'SystemGenerated' -and
        $_.primaryName.logicalName -ceq "$($_.logicalName)_ref" -and
        $_.primaryName.displayName -in @('Call Reference', 'Transition Reference') -and
        $_.primaryName.format -in @('CALL-{SEQNUM:8}', 'HIST-{SEQNUM:8}')
    }).Count -eq 2) 'Both child primary-name definitions retain exact approved schema, display, requiredness, and AutoNumber semantics'
Assert-Test ($manifest.provisioning.phase3B2AuthorizedContinuation.latestResumeClassification -ceq 'PARTIAL_METADATA_STATE' -and
    $manifest.provisioning.phase3B2AuthorizedContinuation.latestResumeAttempt.childScopeRequests.GET -eq 17 -and
    $manifest.provisioning.phase3B2AuthorizedContinuation.latestResumeAttempt.childScopeRequests.POST -eq 0 -and
    $manifest.provisioning.phase3B2AuthorizedContinuation.latestResumeAttempt.automaticRetries -eq 0 -and
    -not $manifest.provisioning.phase3B2AuthorizedContinuation.latestResumeAttempt.correctedPayloadDispatchedThisAttempt) 'Latest resume is recorded as GET-only partial-state stop'
Assert-Test ($manifest.provisioning.phase3B2AuthorizedContinuation.latestStatusChoiceBindingRepair.status -ceq 'STOPPED_AFTER_FIRST_UPDATE_READBACK_MISMATCH' -and
    $manifest.provisioning.phase3B2AuthorizedContinuation.latestStatusChoiceBindingRepair.previousStatusColumn.updateDispatches -eq 1 -and
    $manifest.provisioning.phase3B2AuthorizedContinuation.latestStatusChoiceBindingRepair.newStatusColumn.updateDispatches -eq 0 -and
    $manifest.provisioning.phase3B2AuthorizedContinuation.latestStatusChoiceBindingRepair.automaticRetries -eq 0 -and
    $manifest.provisioning.phase3B2AuthorizedContinuation.latestStatusChoiceBindingRepair.finalBindings.os_sr_csh_prevstat -ceq 'os_sr_callout' -and
    $manifest.provisioning.phase3B2AuthorizedContinuation.latestStatusChoiceBindingRepair.finalBindings.os_sr_csh_newstat -ceq 'os_sr_callout') 'Repair ledger records one unreconciled Previous Status PUT, no New Status write, and the verified final bindings'
Assert-Test ($manifest.provisioning.phase3B2AuthorizedContinuation.primaryNameTechnicalNormalization.ownerApprovedMaxLength -eq 100 -and
    $manifest.provisioning.phase3B2AuthorizedContinuation.primaryNameTechnicalNormalization.formatName -ceq 'Text' -and
    -not $manifest.provisioning.phase3B2AuthorizedContinuation.primaryNameTechnicalNormalization.schemaDisplayRequirednessAndProductSemanticsChanged) 'Primary-name normalization is technical-only and does not change product or schema semantics'
$payloadFunction = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($runnerPath, [ref]$tokens, [ref]$parseErrors)
$payloadFunction = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -ceq 'New-StatusChoiceBindingUpdatePayload' }, $true)
if ($null -eq $payloadFunction) { throw 'FAIL: Full-metadata PUT payload helper is missing.' }
$script:ChoiceName = 'os_sr_callout'
$script:RepairAllowedColumns = @('os_sr_csh_prevstat', 'os_sr_csh_newstat')
Invoke-Expression $payloadFunction.Extent.Text
$pathFunction = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -ceq 'Get-StatusChoiceAttributePath' }, $true)
if ($null -eq $pathFunction) { throw 'FAIL: MetadataId-targeted repair path helper is missing.' }
Invoke-Expression $pathFunction.Extent.Text
$preservationFunction = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -ceq 'Get-StatusChoicePreservationFingerprint' }, $true)
if ($null -eq $preservationFunction) { throw 'FAIL: Preservation fingerprint helper is missing.' }
Invoke-Expression $preservationFunction.Extent.Text
$hashFunction = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -ceq 'Get-Sha256' }, $true)
if ($null -eq $hashFunction) { throw 'FAIL: SHA-256 helper is missing.' }
Invoke-Expression $hashFunction.Extent.Text
$sourceMetadata = [pscustomobject]@{
    '@odata.type' = 'Microsoft.Dynamics.CRM.PicklistAttributeMetadata'
    '@odata.context' = 'synthetic-context'
    LogicalName = 'os_sr_csh_prevstat'
    SchemaName = 'os_sr_csh_prevstat'
    MetadataId = '00000000-0000-0000-0000-000000000011'
    AttributeType = 'Picklist'
    AttributeTypeName = [pscustomobject]@{ Value = 'PicklistType' }
    DisplayName = [pscustomobject]@{
        LocalizedLabels = @([pscustomobject]@{ Label = 'Previous Status'; LanguageCode = 1033 })
    }
    RequiredLevel = [pscustomobject]@{ Value = 'ApplicationRequired'; CanBeChanged = $true }
    DefaultFormValue = 100010000
    IsPrimaryName = $false
    IsManaged = $false
    IsCustomizable = [pscustomobject]@{ Value = $true; CanBeChanged = $true }
    GlobalOptionSet = [pscustomobject]@{
        Name = 'os_sr_callout'
        MetadataId = '00000000-0000-0000-0000-000000000012'
    }
    OptionSet = [pscustomobject]@{
        Name = 'os_sr_callout'
        MetadataId = '00000000-0000-0000-0000-000000000012'
    }
}
$updatePayload = New-StatusChoiceBindingUpdatePayload -Attribute $sourceMetadata `
    -TargetMetadataId '00000000-0000-0000-0000-000000000013'
$updatePath = Get-StatusChoiceAttributePath -Attribute $sourceMetadata
Assert-Test ($updatePayload.LogicalName -ceq $sourceMetadata.LogicalName -and
    $updatePayload.SchemaName -ceq $sourceMetadata.SchemaName -and
    $updatePayload.MetadataId -ceq $sourceMetadata.MetadataId -and
    $updatePayload.DisplayName.LocalizedLabels[0].Label -ceq 'Previous Status' -and
    $updatePayload.RequiredLevel.Value -ceq 'ApplicationRequired' -and
    $updatePayload.DefaultFormValue -eq 100010000 -and
    $updatePayload.IsPrimaryName -eq $false -and
    $updatePayload.'GlobalOptionSet@odata.bind' -ceq '/GlobalOptionSetDefinitions(00000000-0000-0000-0000-000000000013)' -and
    -not $updatePayload.ContainsKey('GlobalOptionSet') -and
    -not $updatePayload.ContainsKey('OptionSet') -and
    -not $updatePayload.ContainsKey('@odata.context')) 'In-place PUT changes only the intended binding and preserves writable definition metadata'
Assert-Test ($updatePath -ceq "EntityDefinitions(LogicalName='os_sr_csh')/Attributes(00000000-0000-0000-0000-000000000011)" -and
    $updatePath -notmatch 'Attributes\(LogicalName=') 'Update targets the exact existing Attribute MetadataId rather than a LogicalName alternate key'
$sourceFingerprint = Get-StatusChoicePreservationFingerprint -Attribute $sourceMetadata
$changedBinding = $sourceMetadata | ConvertTo-Json -Depth 10 | ConvertFrom-Json
$changedBinding.GlobalOptionSet.Name = 'os_sr_candstat'
$changedBinding.GlobalOptionSet.MetadataId = '00000000-0000-0000-0000-000000000013'
$changedBinding.OptionSet.Name = 'os_sr_candstat'
$changedBinding.OptionSet.MetadataId = '00000000-0000-0000-0000-000000000013'
Assert-Test ($sourceFingerprint -ceq (Get-StatusChoicePreservationFingerprint -Attribute $changedBinding)) 'Preservation fingerprint excludes only the intended Choice binding navigation properties'
$changedBinding.RequiredLevel.Value = 'None'
Assert-Test ($sourceFingerprint -cne (Get-StatusChoicePreservationFingerprint -Attribute $changedBinding)) 'Preservation fingerprint detects an unintended requiredness change'
$repairFunction = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -ceq 'Invoke-StatusChoiceBindingRepair' }, $true)
if ($null -eq $repairFunction) { throw 'FAIL: Guarded repair sequence is missing.' }
$repairSource = $repairFunction.Extent.Text
$rowCountIndex = $repairSource.IndexOf('Get-CandidateStatusHistoryRowCount')
$putIndex = $repairSource.IndexOf('Invoke-DataverseRequest -Method PUT')
Assert-Test ($rowCountIndex -ge 0 -and $putIndex -gt $rowCountIndex) 'Zero-row count is rechecked before the first authorized metadata update'

foreach ($name in @('Get-ReplacementLabel', 'Get-ReplacementPreservedProperties',
    'New-StatusChoiceReplacementPayload', 'New-AttributePayload', 'New-RequiredLevel', 'New-Label', 'Get-Required',
    'Assert-NoAttributeDeleteDependencies', 'Assert-ReplacementDispatch')) {
    $definition = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -ceq $name }, $true)
    if ($null -eq $definition) { throw "FAIL: Replacement helper $name is missing." }
    Invoke-Expression $definition.Extent.Text
}
# Only the metadata validator is stubbed; payload construction remains the real implementation.
function Assert-StatusChoiceColumn {}
$sourceMetadata | Add-Member -NotePropertyMembers @{
    Description = [pscustomobject]@{ LocalizedLabels = @([pscustomobject]@{ Label = ''; LanguageCode = 1033 }) }
    IsAuditEnabled = [pscustomobject]@{ Value = $true }
    IsSecured = $false
    IsValidForAdvancedFind = [pscustomobject]@{ Value = $true }
}
$choice = [pscustomobject]@{
    Name = 'os_sr_candstat'; IsGlobal = $true; MetadataId = '00000000-0000-0000-0000-000000000013'
}
$replacementPayload = New-StatusChoiceReplacementPayload -Attribute $sourceMetadata `
    -Column $historyChoiceColumns[0] -Choice $choice
Assert-Test ($replacementPayload.'GlobalOptionSet@odata.bind' -ceq '/GlobalOptionSetDefinitions(00000000-0000-0000-0000-000000000013)' -and
    -not $replacementPayload.Contains('Options') -and -not $replacementPayload.Contains('OptionSet') -and
    -not $replacementPayload.Contains('MetadataId')) 'Replacement creates a binding to the approved global Choice without defining options or reusing the deleted MetadataId'
Assert-Test ($replacementPayload.LogicalName -ceq $sourceMetadata.LogicalName -and
    $replacementPayload.DisplayName.LocalizedLabels[0].Label -ceq 'Previous Status' -and
    $replacementPayload.RequiredLevel.Value -ceq 'ApplicationRequired' -and
    $replacementPayload.DefaultFormValue -eq 100010000 -and
    $replacementPayload.IsAuditEnabled.Value -eq $true -and -not $replacementPayload.IsSecured) 'Replacement payload preserves labels, default, audit, security, and requiredness'
$script:dependencyResponse = [pscustomobject]@{ value = @() }
function Invoke-DataverseRequest { $script:dependencyResponse }
Assert-NoAttributeDeleteDependencies -MetadataId '00000000-0000-0000-0000-000000000011'
Assert-Test $true 'Empty deletion-dependency collection passes'
foreach ($response in @(
    [pscustomobject]@{ value = @([pscustomobject]@{ dependentcomponenttype = 60 }) },
    [pscustomobject]@{ other = @() },
    [pscustomobject]@{ value = $null },
    [pscustomobject]@{ value = @(); '@odata.nextLink' = 'synthetic-next-page' }
)) {
    $script:dependencyResponse = $response
    $blocked = $false
    try { Assert-NoAttributeDeleteDependencies -MetadataId '00000000-0000-0000-0000-000000000011' }
    catch { $blocked = $true }
    Assert-Test $blocked 'Blocking, malformed, null, or paged dependency results fail closed'
}
$replacementDefinition = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -ceq 'Invoke-StatusChoiceColumnReplacement' }, $true)
$replacementSource = $replacementDefinition.Extent.Text
Assert-Test ($replacementSource -match "foreach \(\`$method in @\('DELETE', 'POST'\)\)" -and
    $replacementSource -notmatch 'Method PUT' -and
    $replacementSource -match 'FileMode\]::CreateNew' -and
    $runner -match 'Save-ReplacementJournal\s+\$script:WriteStages.Add') 'Replacement order is delete then create with durable reservation before dispatch and no in-place update'
Assert-Test ($replacementSource.IndexOf('Get-CandidateStatusHistoryRowCount') -lt $replacementSource.IndexOf('Invoke-DataverseRequest -Method DELETE') -and
    $replacementSource.IndexOf('Assert-NoAttributeDeleteDependencies') -lt $replacementSource.IndexOf('Invoke-DataverseRequest -Method DELETE') -and
    $replacementSource -match 'if \(\$null -ne \$dispatchFailure\) \{ throw \$dispatchFailure \}') 'Zero-row and dependency gates precede deletion; even reconciled failed dispatches stop'
Assert-Test ($runner -match '\$Method -eq ''DELETE'' -and -not \$ReplaceStatusChoiceColumns' -and
    $runner -match '\$ReplacementPreflightOnly -and \$Method -cne ''GET''' -and
    $runner -match '\$index -ge 4' -and $runner -match '\$hash -cne \$step.PayloadSha256') 'DELETE is isolated from other modes and replacement has a four-dispatch exact-payload ceiling'

foreach ($name in @('Invoke-StatusChoiceColumnReplacement', 'Save-ReplacementJournal')) {
    $definition = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -ceq $name }, $true)
    Invoke-Expression $definition.Extent.Text
}
function Get-ManifestHash { 'synthetic-manifest' }
function Get-MetadataIdFingerprint { param([string]$MetadataId) $MetadataId }
function Get-SanitizedFailureMessage { param([string]$Message) $Message }
function Assert-StatusChoiceRepairPreflight { $script:syntheticPreflight }
function Get-StatusChoiceAttribute { param([string]$LogicalName) $script:syntheticAttributes[$LogicalName] }
function Assert-StatusChoiceColumn {
    param($Attribute, $ManifestColumn, $ExpectedChoiceName, $ExpectedChoice)
    if ($Attribute.GlobalOptionSet.Name -cne $ExpectedChoiceName) { throw 'Synthetic binding mismatch.' }
}
function Get-CandidateStatusHistoryRowCount {
    if ($script:scenario -ceq 'rows') { return 1 }
    0
}
function Assert-NoAttributeDeleteDependencies {
    if ($script:scenario -ceq 'dependencies') { throw 'Synthetic dependency blocks deletion.' }
}
function Get-OptionalMetadata {
    param([string]$Path)
    if ($Path -like 'GlobalOptionSetDefinitions*') {
        if ($Path -like '*os_sr_callout*') { return $script:RepairWrongChoice }
        return $choice
    }
    $matched = [regex]::Match($Path, "Attributes\(LogicalName='([^']+)'\)")
    $script:syntheticAttributes[$matched.Groups[1].Value]
}
function Get-ChoiceOptionsForRepair {}
function Assert-TableReadback {}
function Assert-RelationshipsAndKeys {}
function Invoke-DataverseRequest {
    param($Method, $Path, $Body, [switch]$WithSolutionHeader)
    if ($Method -ceq 'GET') {
        return [pscustomobject]@{ organizationid = $ExpectedOrganizationId; isauditenabled = $false }
    }
    Assert-ReplacementDispatch -Method $Method -Path $Path -Body $Body -WithSolutionHeader:$WithSolutionHeader
    $script:RequestCounts[$Method]++
    $script:LastWriteHttpStatus = 204
    $name = $script:ReplacementPlan[$script:WriteStages.Count - 1].LogicalName
    if ($Method -ceq 'DELETE') {
        $script:syntheticAttributes.Remove($name)
        if ($script:scenario -ceq 'uncertain-delete') {
            $script:LastWriteOutcomeUncertain = $true
            throw 'Synthetic uncertain delete; no resend.'
        }
    } else {
        if ($script:scenario -ceq 'create-failure') {
            $script:LastWriteHttpStatus = 400
            throw 'Synthetic definite create failure.'
        }
        $created = $script:syntheticPreflight.Attributes[$name] | ConvertTo-Json -Depth 30 | ConvertFrom-Json
        $created.MetadataId = if ($name -ceq 'os_sr_csh_prevstat') {
            '00000000-0000-0000-0000-000000000021'
        } else { '00000000-0000-0000-0000-000000000022' }
        if ($script:scenario -cne 'binding-mismatch') { $created.GlobalOptionSet = $choice }
        $script:syntheticAttributes[$name] = $created
    }
}
$ReplaceStatusChoiceColumns = $true
$script:ExpectedManifestSha256 = 'synthetic-manifest'
$script:ExpectedUserId = 'synthetic-user'
$ExpectedOrganizationId = '00000000-0000-0000-0000-000000000031'
$candidateResult = [pscustomobject]@{ Requests = [pscustomobject]@{ GET = 31 } }
$script:CandidateRunner = {
    $global:LASTEXITCODE = 0
    '{"Result":"CANDIDATE_TABLE_KEYS_LOOKUPS_AND_SOLUTION_MEMBERSHIP_RECONCILED","Requests":{"POST":0,"GET":31}}'
}
$oldUserGuard = [Environment]::GetEnvironmentVariable('BSO_RS_EXPECTED_USER_ID', 'Process')
try {
    [Environment]::SetEnvironmentVariable('BSO_RS_EXPECTED_USER_ID', 'synthetic-user', 'Process')
    foreach ($script:scenario in @('success', 'rows', 'dependencies', 'uncertain-delete', 'create-failure', 'binding-mismatch')) {
        $ReplacementEvidencePath = Join-Path ([IO.Path]::GetTempPath()) ("bso-synthetic-replacement-" + [Guid]::NewGuid().ToString('N') + '.json')
        try {
            $script:WriteStages = [System.Collections.Generic.List[string]]::new()
            $script:WriteHashes = [System.Collections.Generic.List[object]]::new()
            $script:RequestCounts = @{ GET = 0; POST = 0; PUT = 0; DELETE = 0 }
            $script:ReplacementJournal = $null
            $script:RepairWrongChoice = $sourceMetadata.GlobalOptionSet
            $attributes = @{}
            foreach ($column in $historyChoiceColumns) {
                $attribute = $sourceMetadata | ConvertTo-Json -Depth 30 | ConvertFrom-Json
                $attribute.LogicalName = [string]$column.logicalName
                $attribute.SchemaName = [string]$column.logicalName
                $attribute.DisplayName.LocalizedLabels[0].Label = [string]$column.displayName
                $attributes[[string]$column.logicalName] = $attribute
            }
            $script:syntheticPreflight = [pscustomobject]@{
                Columns = @($historyChoiceColumns | Sort-Object { if ($_.displayName -ceq 'Previous Status') { 0 } else { 1 } })
                Attributes = $attributes
                CandidateStatusChoice = $choice
                CallOutcomeChoice = $script:RepairWrongChoice
                Table = [pscustomobject]@{ EntitySetName = 'synthetic_history'; PrimaryIdAttribute = 'synthetic_id' }
            }
            $script:RepairAllowedColumns = @($script:syntheticPreflight.Columns.logicalName)
            $script:syntheticAttributes = $attributes.Clone()
            $stopped = $false
            try { $result = Invoke-StatusChoiceColumnReplacement -Manifest $manifest }
            catch { $stopped = $true }
            if ($script:scenario -ceq 'success') {
                Assert-Test (-not $stopped -and $result.Result -ceq 'CANDIDATE_CORE_STORAGE_PROVISIONED_AUDIT_ACTIVATION_PENDING' -and
                    ($script:WriteStages -join '|') -ceq 'DELETE os_sr_csh_prevstat|POST os_sr_csh_prevstat|DELETE os_sr_csh_newstat|POST os_sr_csh_newstat') 'Synthetic replacement completes in the exact four-dispatch order'
                $reuseBlocked = $false
                try { $null = Invoke-StatusChoiceColumnReplacement -Manifest $manifest }
                catch { $reuseBlocked = $true }
                Assert-Test ($reuseBlocked -and $script:WriteStages.Count -eq 4) 'A consumed evidence journal cannot be reused for another dispatch'
            } else {
                $expectedWrites = switch ($script:scenario) {
                    'rows' { 0 }; 'dependencies' { 0 }; 'uncertain-delete' { 1 }; default { 2 }
                }
                Assert-Test ($stopped -and $script:WriteStages.Count -eq $expectedWrites) "Synthetic $($script:scenario) stops at the required boundary without a resend or New Status write"
            }
        } finally {
            if (Test-Path -LiteralPath $ReplacementEvidencePath) { Remove-Item -LiteralPath $ReplacementEvidencePath }
        }
    }
} finally {
    [Environment]::SetEnvironmentVariable('BSO_RS_EXPECTED_USER_ID', $oldUserGuard, 'Process')
}

Write-Output "PASS: $script:Passed synthetic Phase 3B.2 provisioning assertions; no authentication, network, PAC, or tenant calls."
