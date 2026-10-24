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
Assert-Test ($runner -match "Assert-ChildTableAbsent" -and
    $runner -match "Assert-InitialState" -and
    $runner -match "Assert-TableReadback" -and
    $runner -match "Assert-RelationshipsAndKeys") 'Preflight and exact post-write reconciliation paths are required'
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
    $historyChoiceColumns.Count -eq 2) 'Each Choice attribute binds to its own manifest target'
Assert-Test ($manifest.relationships.Count -eq 7 -and
    @($manifest.relationships | ForEach-Object schemaName | Select-Object -Unique).Count -eq 7) 'Seven manifest relationship schema names are unique'
Assert-Test ($model -match '`usr` = Dataverse system user' -and
    $model -match 'os_sr_usr_call_ctby' -and $model -match 'os_sr_usr_csh_actr') 'User lookup naming follows the documented publisher/project convention'
Assert-Test ($manifest.callOutcomeChoice.options.Count -eq 3 -and
    @($manifest.callOutcomeChoice.options | ForEach-Object label) -join '|' -ceq 'Answered|No Answer|Call Back Requested') 'Call Outcome taxonomy remains exact'
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
Assert-Test ($manifest.provisioning.phase3B2AuthorizedContinuation.primaryNameTechnicalNormalization.ownerApprovedMaxLength -eq 100 -and
    $manifest.provisioning.phase3B2AuthorizedContinuation.primaryNameTechnicalNormalization.formatName -ceq 'Text' -and
    -not $manifest.provisioning.phase3B2AuthorizedContinuation.primaryNameTechnicalNormalization.schemaDisplayRequirednessAndProductSemanticsChanged) 'Primary-name normalization is technical-only and does not change product or schema semantics'

Write-Output "PASS: $script:Passed synthetic Phase 3B.2 provisioning assertions; no authentication, network, PAC, or tenant calls."
