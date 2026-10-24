#requires -Version 7.4
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$manifestPath = Join-Path $PSScriptRoot '../docs/PHASE_3A_CANDIDATE_CORE_METADATA_PLAN.json'
$reportPath = Join-Path $PSScriptRoot '../docs/PHASE_3A_CANDIDATE_CORE_DESIGN.md'
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$report = Get-Content -LiteralPath $reportPath -Raw
$script:Passed = 0

function Assert-Test {
    param([bool]$Condition, [string]$Name)
    if (-not $Condition) { throw "FAIL: $Name" }
    $script:Passed++
}

function Test-ProposedAutoNumberFormat {
    param([string]$Format)
    $Format -cmatch '^[A-Z0-9-]*\{SEQNUM:[1-9][0-9]*\}$' -and
        @([regex]::Matches($Format, '\{[^{}]*\}')).Count -eq 1
}

$expectedTables = @('os_sr_cand', 'os_sr_call', 'os_sr_csh')
$actualTables = @($manifest.tables | ForEach-Object { $_.logicalName })
Assert-Test ($manifest.phase -ceq '3A' -and
    $manifest.status -ceq 'CANDIDATE_TABLE_KEYS_LOOKUPS_AND_SOLUTION_MEMBERSHIP_RECONCILED') 'Phase and reconciled Candidate-only provisioning status'
Assert-Test ($manifest.provisioning.completedCandidateOnlyRun.status -ceq $manifest.status -and
    $manifest.provisioning.completedCandidateOnlyRun.authorizationConsumed -and
    $manifest.provisioning.completedCandidateOnlyRun.writeCounts.total -eq 7 -and
    $manifest.provisioning.completedCandidateOnlyRun.automaticRetries -eq 0 -and
    $manifest.provisioning.completedCandidateOnlyRun.businessDataWrites -eq 0) 'Candidate-only run record preserves the bounded write and no-data limits'
Assert-Test ($manifest.provisioning.completedCandidateOnlyRun.finalGetOnlyReconciliation.GET -eq 31 -and
    $manifest.provisioning.completedCandidateOnlyRun.finalGetOnlyReconciliation.POST -eq 0) 'Final live reconciliation is accurately recorded as GET-only'
Assert-Test ($actualTables.Count -eq 3 -and (Compare-Object $expectedTables $actualTables).Count -eq 0) 'Exactly the three requested proposed tables'
Assert-Test ($manifest.scope -contains 'os_sr_candstat' -and $manifest.scope -contains 'os_sr_callout' -and
    $manifest.scope -contains 'os_sr_cact') 'Both Choices and Custom API are in proposal scope, not extra tables'
Assert-Test ($manifest.publisherPrefix -ceq 'os' -and $manifest.projectNamespace -ceq 'sr_') 'Project prefix and namespace contract'

$candidate = $manifest.tables | Where-Object logicalName -CEQ 'os_sr_cand'
$call = $manifest.tables | Where-Object logicalName -CEQ 'os_sr_call'
$history = $manifest.tables | Where-Object logicalName -CEQ 'os_sr_csh'
Assert-Test ($candidate.ownership -ceq 'UserOwned' -and $candidate.primaryName.logicalName -ceq 'os_sr_cand_cnum') 'Candidate ownership and primary name proposal'
Assert-Test ($candidate.primaryName.type -ceq 'AutoNumber' -and $candidate.primaryName.generatedBy -ceq 'Dataverse' -and
    $candidate.primaryName.immutableAfterCreate -and -not $candidate.primaryName.containsPersonalInformation) 'Server-generated immutable nonpersonal Candidate Number'
Assert-Test (Test-ProposedAutoNumberFormat $candidate.primaryName.format) 'Candidate Number uses the supported sequence placeholder shape'
Assert-Test (-not (Test-ProposedAutoNumberFormat 'CAND-{SEQNUM:0}') -and
    -not (Test-ProposedAutoNumberFormat 'CAND-{UNSUPPORTED:8}') -and
    -not (Test-ProposedAutoNumberFormat 'CAND-{SEQNUM:8')) 'Malformed or unsupported Candidate Number placeholders are rejected'
Assert-Test ($candidate.primaryName.maxLength -eq 100) 'Candidate AutoNumber uses the owner-approved String MaxLength'
Assert-Test (@($candidate.columns | Where-Object logicalName -ceq 'os_sr_cand_eml').Count -eq 1 -and
    $candidate.columns.Where({ $_.logicalName -ceq 'os_sr_cand_eml' }).required -ceq 'Required' -and
    @($candidate.columns | Where-Object logicalName -ceq 'os_sr_cand_phn').Count -eq 1 -and
    $candidate.columns.Where({ $_.logicalName -ceq 'os_sr_cand_phn' }).required -ceq 'Optional') 'Candidate Email required and Phone optional'
Assert-Test (@($candidate.columns | Where-Object logicalName -ceq 'os_sr_cand_pos').Count -eq 1 -and
    @($candidate.columns | Where-Object logicalName -ceq 'os_sr_cand_lgcar').Count -eq 0) 'Position included and LEGO Career deferred from Candidate core'
Assert-Test ($candidate.responsibleBso -match 'ownerid' -and
    @($candidate.columns | Where-Object displayName -match 'Assigned BSO').Count -eq 0) 'Dataverse Owner represents BSO without duplicate assignment lookup'
Assert-Test ($candidate.audit.enabled -and
    $candidate.audit.columnSecurity.os_sr_cand_nm -eq $false -and
    $candidate.audit.columnSecurity.os_sr_cand_eml -eq $false -and
    $candidate.audit.columnSecurity.os_sr_cand_phn -eq $false) 'Candidate audit and contact-field security decisions'
Assert-Test ($candidate.platformColumns -contains 'ownerid' -and $candidate.platformColumns -contains 'versionnumber' -and
    $candidate.platformColumns -notcontains 'os_sr_cand_createdon') 'Use system ownership/timestamps/row version without duplicates'

$choice = $manifest.globalChoice
$expectedLabels = @(
    'Need Call Candidate',
    'Candidate Answered',
    'Waiting Manual Scheduling',
    'Round 1 Scheduled',
    'Offer Extended',
    'Candidate Failed'
)
$expectedChoicePairs = @(
    'Need Call Candidate',
    'Candidate Answered',
    'Waiting Manual Scheduling',
    'Round 1 Scheduled',
    'Offer Extended',
    'Candidate Failed'
)
$choiceLabels = @($choice.options | ForEach-Object label)
$choiceValues = @($choice.options | ForEach-Object value)
$expectedChoiceValues = @(100010000, 100010001, 100010002, 100010003, 100010004, 100010005)
Assert-Test ($choice.logicalName -ceq 'os_sr_candstat' -and
    $choice.valueStatus -match 'system-assigned' -and
    $choice.defaultValue -eq $choiceValues[0] -and $choice.valuePrefix -eq 10001) 'Choice identity, assigned prefix, and default'
Assert-Test ($choiceLabels.Count -eq 6 -and (Compare-Object $expectedLabels $choiceLabels).Count -eq 0) 'Exact six canonical status labels'
Assert-Test ($choiceValues.Count -eq 6 -and
    (Compare-Object $expectedChoiceValues $choiceValues).Count -eq 0) 'Status option values match the GET-reconciled frozen mapping'
Assert-Test (($candidate.columns | Where-Object logicalName -ceq 'os_sr_cand_stat').defaultValue -eq $choice.defaultValue) 'Candidate Status default matches the allocated Need Call Candidate value'
$callOutcomeValues = @($manifest.callOutcomeChoice.options | ForEach-Object value)
$callOutcomeUnassigned = @($callOutcomeValues | Where-Object { $null -eq $_ }).Count -eq 3
$callOutcomeFrozen = @($callOutcomeValues | Where-Object { $null -ne $_ -and [int]$_ -gt 0 } | Select-Object -Unique).Count -eq 3
Assert-Test ($manifest.callOutcomeChoice.options.Count -eq 3 -and
    ($callOutcomeUnassigned -or $callOutcomeFrozen) -and
    $manifest.callOutcomeChoice.valueStatus -match 'system-assigned|GET-reconciled and frozen') 'Call Outcome values are unassigned before provisioning or uniquely frozen after Dataverse allocation'
Assert-Test ($choiceLabels -notcontains 'Draft Created' -and $choiceLabels -notcontains 'BSO Reviewing' -and
    $choiceLabels -notcontains 'Sent to TA' -and $choiceLabels -notcontains 'TA Approval') 'No deprecated approval stages in Choice'

$expectedOutcomes = @('Answered', 'No Answer', 'Call Back Requested')
$actualOutcomes = @($manifest.callOutcomeChoice.options | ForEach-Object label)
Assert-Test ($manifest.callOutcomeChoice.logicalName -ceq 'os_sr_callout' -and
    (Compare-Object $expectedOutcomes $actualOutcomes).Count -eq 0) 'Exact approved initial call outcome taxonomy'
Assert-Test (($manifest.callOutcomeRules | Where-Object outcome -ceq 'Answered').createsStatusHistory -and
    ($manifest.callOutcomeRules | Where-Object outcome -ceq 'Answered').atomic -and
    -not ($manifest.callOutcomeRules | Where-Object outcome -ceq 'No Answer').createsStatusHistory -and
    -not ($manifest.callOutcomeRules | Where-Object outcome -ceq 'Call Back Requested').createsStatusHistory) 'Answer transitions atomically; non-answer outcomes log only'

$userRelationships = @($manifest.relationships | Where-Object parent -ceq 'systemuser')
$expectedUserRelationships = @('os_sr_usr_call_ctby', 'os_sr_usr_csh_actr')
Assert-Test ($userRelationships.Count -eq 2 -and
    (Compare-Object $expectedUserRelationships @($userRelationships | ForEach-Object schemaName)).Count -eq 0 -and
    @($manifest.relationships | ForEach-Object schemaName | Select-Object -Unique).Count -eq $manifest.relationships.Count) 'System-user relationship technical names are unique and deterministic'
Assert-Test ((@($userRelationships | Where-Object { $_.delete -cne 'Restrict' -or $_.assignShareReparent -cne 'NoCascade' }).Count -eq 0) -and
    ($manifest.tables | Where-Object logicalName -ceq 'os_sr_call').columns.Where({ $_.logicalName -ceq 'os_sr_call_ctby' }).relationship -ceq 'os_sr_usr_call_ctby' -and
    ($manifest.tables | Where-Object logicalName -ceq 'os_sr_csh').columns.Where({ $_.logicalName -ceq 'os_sr_csh_actr' }).relationship -ceq 'os_sr_usr_csh_actr') 'System-user relationships preserve lookup names and non-destructive history cascades'
Assert-Test ($manifest.provisioning.phase3B2AuthorizedContinuation.status -in @(
        'AUTHORIZED_CORRECTED_CALLLOG_AND_REMAINING_CHILD_METADATA',
        'CORRECTED_CALLLOG_DISPATCHED_RECONCILIATION_PENDING',
        'CORRECTED_CALLLOG_RECONCILED_REMAINING_SCOPE_AUTHORIZED',
        'STOPPED_AFTER_CORRECTED_CONTINUATION_REQUIRES_RECONCILIATION',
        'CALL_LOG_RECONCILED_REMAINING_SCOPE_AUTHORIZED',
        'REMAINING_SCOPE_AUTHORIZATION_CONSUMED_RECONCILIATION_PENDING',
        'STOPPED_AFTER_REMAINING_METADATA_MISMATCH_NO_FURTHER_WRITES',
        'PHASE_3B2_STORAGE_RECONCILED_AUTHORIZATION_CONSUMED'
    ) -and
    $manifest.provisioning.phase3B2AuthorizedContinuation.automaticRetries -eq 0 -and
    -not $manifest.provisioning.phase3B2AuthorizedContinuation.businessDataWrites -and
    -not $manifest.provisioning.phase3B2AuthorizedContinuation.candidateCreateOrModification -and
    $manifest.provisioning.phase3B2AuthorizedContinuation.executionOutcome.callOutcomeChoice -match 'GET-reconciled') 'Phase 3B.2 authorization disposition preserves the bounded zero-retry outcome'

$expectedTransitions = @(
    'Need Call Candidate|RecordCall|Candidate Answered',
    'Candidate Answered|ProceedToScheduling|Waiting Manual Scheduling',
    'Waiting Manual Scheduling|MarkRound1Scheduled|Round 1 Scheduled',
    'Round 1 Scheduled|RecordPass|Offer Extended',
    'Round 1 Scheduled|RecordFail|Candidate Failed',
    'Round 1 Scheduled|RequestReschedule|Need Call Candidate'
)
$actualTransitions = @($manifest.transitionMatrix | Where-Object allowed | ForEach-Object { "$($_.from)|$($_.action)|$($_.to)" })
Assert-Test ($actualTransitions.Count -eq 6 -and (Compare-Object $expectedTransitions $actualTransitions).Count -eq 0) 'Exact allowed transition set'
Assert-Test (($manifest.transitionMatrix | Where-Object action -CEQ 'RequestReschedule').condition -match 'Mandatory reason' -and
    ($manifest.transitionMatrix | Where-Object action -CEQ 'RequestReschedule').executionStatus -ceq 'DeferredUntilSchedulingBoundary') 'Reschedule reason is mandatory and calendar boundary is deferred'
Assert-Test ($manifest.transitionMatrix.Where({ $_.action -ceq 'MarkRound1Scheduled' }).condition -match 'future scheduler') 'No Phase 3A scheduling side effect'

Assert-Test ($call.ownership -ceq 'UserOwned' -and
    @($call.columns | Where-Object logicalName -ceq 'os_sr_call_ctby').Count -eq 1 -and
    @($call.columns | Where-Object logicalName -ceq 'os_sr_call_ctat').Count -eq 1 -and $call.audit.enabled) 'Call actor, event time, and table auditing are explicit'
Assert-Test (@($history.columns | Where-Object logicalName -ceq 'os_sr_csh_prevstat').Count -eq 1 -and
    @($history.columns | Where-Object logicalName -ceq 'os_sr_csh_newstat').Count -eq 1 -and
    @($history.columns | Where-Object logicalName -ceq 'os_sr_csh_actr').Count -eq 1 -and
    @($history.columns | Where-Object logicalName -ceq 'os_sr_csh_rsn').Count -eq 1 -and $history.audit.enabled) 'History captures states, actor, reason, and audit'
Assert-Test (@($history.columns | Where-Object logicalName -ceq 'os_sr_csh_cact').Count -eq 1 -and
    @($history.columns | Where-Object logicalName -ceq 'os_sr_csh_corid').Count -eq 1) 'History action and GUID correlation fields'

Assert-Test ($manifest.relationships.Count -eq 7 -and
    @($manifest.relationships | Where-Object { $_.delete -cne 'Restrict' -or $_.assignShareReparent -cne 'NoCascade' }).Count -eq 0) 'All proposed relationships restrict deletes and disable cascades'
Assert-Test (@($call.alternateKeys | Where-Object name -ceq 'os_sr_call_ak_cand_action').Count -eq 1 -and
    @($call.alternateKeys[0].columns | Where-Object { $_ -ceq 'os_sr_call_corid' }).Count -eq 1 -and
    @($history.alternateKeys | Where-Object name -ceq 'os_sr_csh_ak_cand_action').Count -eq 1 -and
    @($history.alternateKeys[0].columns | Where-Object { $_ -ceq 'os_sr_csh_corid' }).Count -eq 1) 'Call and History GUID correlation idempotency keys'
Assert-Test (@($candidate.alternateKeys | Where-Object name -ceq 'os_sr_cand_ak_cnum').Count -eq 1 -and
    @($candidate.alternateKeys | Where-Object name -ceq 'os_sr_cand_ak_corid').Count -eq 1) 'Candidate Number uniqueness and creation idempotency keys'
$candidateReferenceRelationships = @($manifest.relationships | Where-Object {
    $_.child -ceq 'os_sr_cand' -and $_.parent -in @('os_sr_pos','os_sr_csrc','os_sr_ta')
})
Assert-Test (@($manifest.tables | Where-Object logicalName -ceq 'os_sr_cand').Count -eq 1 -and
    $candidateReferenceRelationships.Count -eq 3 -and
    @($manifest.relationships | Where-Object { $_.child -ceq 'os_sr_cand' -and $_.parent -in @('os_sr_call','os_sr_csh') }).Count -eq 0) 'Candidate-only projection excludes child activity tables and keeps only existing reference lookups'
$candidateOnlyProjection = [ordered]@{
    proposalType = 'Candidate-only schema proposal; non-dispatchable'
    solutionUniqueName = $manifest.solutionUniqueName
    publisherPrefix = $manifest.publisherPrefix
    projectNamespace = $manifest.projectNamespace
    table = $candidate
    statusChoice = $choice
    candidateReferenceRelationships = $candidateReferenceRelationships
    excluded = @('os_sr_call','os_sr_csh','os_sr_callout','os_sr_cact','plug-in','roles','app navigation','business records')
}
$candidateOnlyJson = ConvertTo-Json -InputObject $candidateOnlyProjection -Depth 80 -Compress
$candidateOnlyHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($candidateOnlyJson))).ToLowerInvariant()
Assert-Test ($candidateOnlyHash -ceq '7168980f2d13d8e406a25854fef3dafad118673e1c5661fb9461e52f41b4f7d8') 'Candidate-only local proposal projection fingerprint is deterministic'

$api = $manifest.customApi
Assert-Test ($api.uniqueName -ceq 'os_sr_cact' -and $api.implementation -match 'Synchronous') 'Server operation name and synchronous implementation proposal'
Assert-Test ($api.PSObject.Properties.Name -notcontains 'executePrivilegeName') 'Custom API ExecutePrivilegeName is not guessed before Candidate table privilege exists'
Assert-Test (($api.inputs -join '|') -match 'CandidateId: Guid' -and
    ($api.inputs -join '|') -match 'ExpectedStatus: Integer' -and
    ($api.inputs -join '|') -match 'CorrelationId: Guid, caller-generated and required') 'Operation inputs include Candidate, expected state, and required caller GUID'
Assert-Test (($api.rules -join '|') -match 'atomic' -and ($api.rules -join '|') -match 'authenticated initiating user') 'Operation requires transaction and authenticated actor'
Assert-Test (($api.rules -join '|') -match 'UpdateCandidate uses replacement values' -and
    ($api.rules -join '|') -match 'identical replay is a no-op') 'Candidate edit replays are replacement-value idempotent without duplicate side effects'
Assert-Test (-not $manifest.provisioning.authorized -and $manifest.provisioning.maximumTenantWrites -eq 7 -and
    $manifest.testSafety.tenantRequests -eq 0 -and $manifest.testSafety.tenantWrites -eq 0) 'Manifest records the consumed write authorization and keeps offline tests tenant-free'
Assert-Test ($manifest.unresolvedDecisions.Count -eq 0 -and $manifest.externalPrerequisites.Count -ge 4 -and
    $report -match 'BLOCKED_STATUS_HISTORY_CHOICE_BINDING_MISMATCH_AND_EXTERNAL_AUDIT_API_PRIVILEGE_PREREQUISITES') 'Owner decisions are closed; schema, audit, and security gates remain'

$hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([IO.File]::ReadAllBytes((Resolve-Path $manifestPath)))).ToLowerInvariant()
$fingerprintMatch = [regex]::Match($report, '(?m)^Local manifest SHA-256: \*\*([0-9a-f]{64})\*\*')
Assert-Test ($fingerprintMatch.Success -and $fingerprintMatch.Groups[1].Value -ceq $hash) 'Report fingerprint matches exact proposal manifest bytes'

Write-Output "PASS: $script:Passed synthetic Phase 3A design assertions; no authentication, network, PAC, or tenant calls."
