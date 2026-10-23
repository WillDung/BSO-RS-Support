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

$expectedTables = @('os_sr_cand', 'os_sr_call', 'os_sr_csh')
$actualTables = @($manifest.tables | ForEach-Object { $_.logicalName })
Assert-Test ($manifest.phase -ceq '3A' -and $manifest.status -ceq 'PROPOSAL_NOT_AUTHORIZED') 'Phase and non-authorized proposal status'
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
    '100010000|Need Call Candidate',
    '100010001|Candidate Answered',
    '100010002|Waiting Manual Scheduling',
    '100010003|Round 1 Scheduled',
    '100010004|Offer Extended',
    '100010005|Candidate Failed'
)
$choiceLabels = @($choice.options | ForEach-Object label)
$choiceValues = @($choice.options | ForEach-Object value)
$choicePairs = @($choice.options | ForEach-Object { "$($_.value)|$($_.label)" })
Assert-Test ($choice.logicalName -ceq 'os_sr_candstat' -and $choice.defaultValue -eq 100010000) 'Choice identity and default'
Assert-Test ($choiceLabels.Count -eq 6 -and (Compare-Object $expectedLabels $choiceLabels).Count -eq 0) 'Exact six canonical status labels'
Assert-Test ($choiceValues.Count -eq 6 -and @($choiceValues | Select-Object -Unique).Count -eq 6 -and
    (Compare-Object $expectedChoicePairs $choicePairs).Count -eq 0) 'Exact stable status integer/label mapping'
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

Assert-Test ($manifest.relationships.Count -eq 5 -and
    @($manifest.relationships | Where-Object { $_.delete -cne 'Restrict' -or $_.assignShareReparent -cne 'NoCascade' }).Count -eq 0) 'All proposed relationships restrict deletes and disable cascades'
Assert-Test (@($call.alternateKeys | Where-Object name -ceq 'os_sr_call_ak_cand_action').Count -eq 1 -and
    @($call.alternateKeys[0].columns | Where-Object { $_ -ceq 'os_sr_call_corid' }).Count -eq 1 -and
    @($history.alternateKeys | Where-Object name -ceq 'os_sr_csh_ak_cand_action').Count -eq 1 -and
    @($history.alternateKeys[0].columns | Where-Object { $_ -ceq 'os_sr_csh_corid' }).Count -eq 1) 'Call and History GUID correlation idempotency keys'
Assert-Test (@($candidate.alternateKeys | Where-Object name -ceq 'os_sr_cand_ak_cnum').Count -eq 1 -and
    @($candidate.alternateKeys | Where-Object name -ceq 'os_sr_cand_ak_corid').Count -eq 1) 'Candidate Number uniqueness and creation idempotency keys'

$api = $manifest.customApi
Assert-Test ($api.uniqueName -ceq 'os_sr_cact' -and $api.implementation -match 'Synchronous') 'Server operation name and synchronous implementation proposal'
Assert-Test (($api.inputs -join '|') -match 'CandidateId: Guid' -and
    ($api.inputs -join '|') -match 'ExpectedStatus: Integer' -and
    ($api.inputs -join '|') -match 'CorrelationId: Guid, caller-generated and required') 'Operation inputs include Candidate, expected state, and required caller GUID'
Assert-Test (($api.rules -join '|') -match 'atomic' -and ($api.rules -join '|') -match 'authenticated initiating user') 'Operation requires transaction and authenticated actor'
Assert-Test (($api.rules -join '|') -match 'UpdateCandidate uses replacement values' -and
    ($api.rules -join '|') -match 'identical replay is a no-op') 'Candidate edit replays are replacement-value idempotent without duplicate side effects'
Assert-Test (-not $manifest.provisioning.authorized -and $manifest.provisioning.maximumTenantWrites -eq 0 -and
    $manifest.testSafety.tenantRequests -eq 0 -and $manifest.testSafety.tenantWrites -eq 0) 'Manifest prohibits tenant writes and records zero operations'
Assert-Test ($manifest.unresolvedDecisions.Count -eq 0 -and $manifest.externalPrerequisites.Count -ge 4 -and
    $report -match 'BLOCKED_EXTERNAL_AUDIT_AND_API_PRIVILEGE_PREREQUISITES') 'Owner decisions are closed; external audit/security gates remain'

$hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([IO.File]::ReadAllBytes((Resolve-Path $manifestPath)))).ToLowerInvariant()
$fingerprintMatch = [regex]::Match($report, '(?m)^Local manifest SHA-256: \*\*([0-9a-f]{64})\*\*')
Assert-Test ($fingerprintMatch.Success -and $fingerprintMatch.Groups[1].Value -ceq $hash) 'Report fingerprint matches exact proposal manifest bytes'

Write-Output "PASS: $script:Passed synthetic Phase 3A design assertions; no authentication, network, PAC, or tenant calls."
