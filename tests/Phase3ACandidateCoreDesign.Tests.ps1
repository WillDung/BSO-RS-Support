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
Assert-Test ($manifest.scope -contains 'os_sr_candstat' -and $manifest.scope -contains 'os_sr_cact') 'Choice and Custom API are contracts, not extra tables'
Assert-Test ($manifest.publisherPrefix -ceq 'os' -and $manifest.projectNamespace -ceq 'sr_') 'Project prefix and namespace contract'

$candidate = $manifest.tables | Where-Object logicalName -CEQ 'os_sr_cand'
$call = $manifest.tables | Where-Object logicalName -CEQ 'os_sr_call'
$history = $manifest.tables | Where-Object logicalName -CEQ 'os_sr_csh'
Assert-Test ($candidate.ownership -ceq 'UserOwned' -and $candidate.primaryName.logicalName -ceq 'os_sr_cand_cnum') 'Candidate ownership and primary name proposal'
Assert-Test ($candidate.primaryName.type -ceq 'String' -and $candidate.primaryName.required -ceq 'Required') 'Candidate Number required proposal'
Assert-Test (@($candidate.columns | Where-Object logicalName -ceq 'os_sr_cand_eml').Count -eq 1 -and
    @($candidate.columns | Where-Object logicalName -ceq 'os_sr_cand_phn').Count -eq 1) 'Candidate email and phone remain separate fields'
Assert-Test (@($candidate.columns | Where-Object logicalName -ceq 'os_sr_cand_lgcar').Count -eq 1 -and
    $candidate.columns.Where({ $_.logicalName -ceq 'os_sr_cand_lgcar' }).target -ceq 'os_sr_lgcar') 'LEGO Career relationship target is explicit'
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
Assert-Test (($manifest.transitionMatrix | Where-Object action -CEQ 'RequestReschedule').condition -match 'cancellation/reconciliation evidence') 'Reschedule requires evidence'
Assert-Test ($manifest.transitionMatrix.Where({ $_.action -ceq 'MarkRound1Scheduled' }).condition -match 'future scheduler') 'No Phase 3A scheduling side effect'

Assert-Test ($call.ownership -ceq 'UserOwned' -and
    @($call.columns | Where-Object logicalName -ceq 'os_sr_call_ctby').Count -eq 1 -and
    @($call.columns | Where-Object logicalName -ceq 'os_sr_call_ctat').Count -eq 1) 'Call actor and event time are explicit'
Assert-Test (@($history.columns | Where-Object logicalName -ceq 'os_sr_csh_prevstat').Count -eq 1 -and
    @($history.columns | Where-Object logicalName -ceq 'os_sr_csh_newstat').Count -eq 1 -and
    @($history.columns | Where-Object logicalName -ceq 'os_sr_csh_actr').Count -eq 1) 'History captures both states and actor'
Assert-Test (@($history.columns | Where-Object logicalName -ceq 'os_sr_csh_cact').Count -eq 1 -and
    @($history.columns | Where-Object logicalName -ceq 'os_sr_csh_actkey').Count -eq 1) 'History action and idempotency fields'

Assert-Test ($manifest.relationships.Count -eq 6 -and
    @($manifest.relationships | Where-Object { $_.delete -cne 'Restrict' -or $_.assignShareReparent -cne 'NoCascade' }).Count -eq 0) 'All proposed relationships restrict deletes and disable cascades'
Assert-Test (@($call.alternateKeys | Where-Object name -ceq 'os_sr_call_ak_cand_action').Count -eq 1 -and
    @($history.alternateKeys | Where-Object name -ceq 'os_sr_csh_ak_cand_action').Count -eq 1) 'Call and History idempotency keys'
Assert-Test (@($candidate.alternateKeys | Where-Object name -ceq 'os_sr_cand_ak_cnum').Count -eq 1) 'Candidate Number alternate key proposal'

$api = $manifest.customApi
Assert-Test ($api.uniqueName -ceq 'os_sr_cact' -and $api.implementation -match 'Synchronous') 'Server operation name and synchronous implementation proposal'
Assert-Test (($api.inputs -join '|') -match 'CandidateId: Guid' -and
    ($api.inputs -join '|') -match 'ExpectedStatus: Integer' -and
    ($api.inputs -join '|') -match 'IdempotencyKey') 'Operation inputs include candidate, expected state, and idempotency'
Assert-Test (($api.rules -join '|') -match 'atomic' -and ($api.rules -join '|') -match 'authenticated initiating user') 'Operation requires transaction and authenticated actor'
Assert-Test (-not $manifest.provisioning.authorized -and $manifest.provisioning.maximumTenantWrites -eq 0 -and
    $manifest.testSafety.tenantRequests -eq 0 -and $manifest.testSafety.tenantWrites -eq 0) 'Manifest prohibits tenant writes and records zero operations'
Assert-Test ($manifest.unresolvedDecisions.Count -ge 7 -and $report -match 'BLOCKED_PRODUCT_DECISION') 'Open product/security decisions block readiness'

$hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([IO.File]::ReadAllBytes((Resolve-Path $manifestPath)))).ToLowerInvariant()
$fingerprintMatch = [regex]::Match($report, '(?m)^Local manifest SHA-256: \*\*([0-9a-f]{64})\*\*')
Assert-Test ($fingerprintMatch.Success -and $fingerprintMatch.Groups[1].Value -ceq $hash) 'Report fingerprint matches exact proposal manifest bytes'

Write-Output "PASS: $script:Passed synthetic Phase 3A design assertions; no authentication, network, PAC, or tenant calls."
