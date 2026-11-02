#requires -Version 7.4
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$webRoot = Join-Path $root 'solutions\CandidateConsole\WebResources\os_\bso'
$htmlPath = Join-Path $webRoot 'candidate-console.html'
$scriptPath = Join-Path $webRoot 'candidate-console.js'
$configurationPath = Join-Path $webRoot 'candidate-console-environment.js'
$policyPath = Join-Path $webRoot 'candidate-console-policy.js'
$stylePath = Join-Path $webRoot 'candidate-console.css'
$html = Get-Content -LiteralPath $htmlPath -Raw
$script = Get-Content -LiteralPath $scriptPath -Raw
$configuration = Get-Content -LiteralPath $configurationPath -Raw
$policy = Get-Content -LiteralPath $policyPath -Raw
$style = Get-Content -LiteralPath $stylePath -Raw
$passed = 0

function Assert-Test {
    param([bool]$Condition, [string]$Name)
    if (-not $Condition) { throw "FAIL: $Name" }
    $script:passed++
}

Assert-Test ($html.Contains('id="workflow-path-badge"') -and
    $html.Contains('id="environment-mode-badge"') -and
    $html.Contains('id="real-data-badge"') -and
    $html.Contains('CANDIDATE CORE PATH') -and
    $html.Contains('PROTECTCANDIDATECORE INACTIVE — NOT PRODUCTION') -and
    $html.Contains('REAL DATA PROHIBITED')) 'Default to the Candidate Core path and retain DEV safety warnings'
Assert-Test ($html.Contains('id="dev-fallback-toggle"') -and
    $html.Contains('Enable DEV direct-write fallback for this browser session') -and
    -not $html.Contains('id="dev-fallback-toggle" type="checkbox" checked')) 'Keep direct writes behind an explicit unchecked session switch'
Assert-Test ($script -match 'function isDevConfiguration\(\) \{\r?\n\s+return isCandidateCoreEnabled\(\) && environmentPolicy\.mode === "DEV";\r?\n\s+\}\r?\n\r?\n\s+function isDevFallbackEnabled\(\)') `
    'Keep workflow path selection in the outer console scope'
Assert-Test ($configuration.Contains('mode: "UNCONFIGURED"') -and
    $configuration.Contains('candidateCoreEnabled: false') -and
    $configuration.Contains('devDirectWriteFallbackEnabled: false') -and
    $policy.Contains('actualUrl.origin.toLowerCase()') -and
    $policy.Contains('runtime.organizationId') -and
    $policy.Contains('directWriteFallbackAvailable: mode === "DEV"')) `
    'Fail closed on unconfigured settings, verify runtime identity, and make fallback DEV-only'
Assert-Test ($html.IndexOf('candidate-console-environment.js') -ge 0 -and
    $html.IndexOf('candidate-console-policy.js') -gt $html.IndexOf('candidate-console-environment.js') -and
    $html.IndexOf('candidate-console.js') -gt $html.IndexOf('candidate-console-policy.js') -and
    -not $script.Contains('DEV_ORIGIN') -and
    -not $configuration.Contains('crm4.dynamics.com')) `
    'Load environment configuration and policy before the console without embedding an environment URL'
Assert-Test ($script.Contains('fetch("/api/data/v9.2/os_sr_cact"') -and
    $script.Contains('credentials: "same-origin"') -and
    $script.Contains('body: JSON.stringify(request)') -and
    $script.Contains('c.correlation')) 'Call the fixed Candidate Core API with a same-origin JSON request and resolve CreateCandidate by its correlation'
$coreInvokeStart = $script.IndexOf('async function invokeCandidateCore')
$coreInvokeEnd = $script.IndexOf('async function resolveCreatedCandidate', $coreInvokeStart)
$coreInvoke = $script.Substring($coreInvokeStart, $coreInvokeEnd - $coreInvokeStart)
Assert-Test ($coreInvoke.Contains('const parameterNames = Object.keys(request);') -and
    $coreInvoke.Contains('CORE_API_ACTIONS.has(action)') -and
    $coreInvoke.Contains('CORE_API_PARAMETER_NAMES.has(name)') -and
    $coreInvoke.Contains('const request = { ...values, ActionType: action, CorrelationId: correlationId };')) `
    'Allow only supported actions and declared request fields; keep caller values from overriding action identity'
Assert-Test ($coreInvoke.Contains('CANDIDATE_CORE_OPERATION_REJECTED:') -and
    $coreInvoke.Contains('CREATE_CANDIDATE:)?(INPUT_VALIDATION|REFERENCE_VALIDATION|RECEIPT_READ|CANDIDATE_CREATE|CANDIDATE_READBACK|RECEIPT_CREATE') -and
    $coreInvoke.Contains('error.operationFailure =') -and
    $script.Contains('CANDIDATE_CORE_${action}_FAILED') -and
    -not $coreInvoke.Contains('console.error(errorMessage)')) `
    'Expose only allowlisted Candidate Core stage/code diagnostics and never log raw server error text'
foreach ($action in @(
    'CreateCandidate', 'RecordCall', 'ProceedToScheduling', 'MarkRound1Scheduled',
    'RecordPass', 'RecordFail', 'RequestReschedule', 'CancelRound1'
)) {
    Assert-Test ($script.Contains("invokeCandidateCore(`"$action`"") -or
        $script.Contains("invokeCandidateCore(action")) "Route $action through Candidate Core"
}
Assert-Test ($script.Contains('if (!isDevFallbackEnabled()) return createCandidateThroughCore(event);') -and
    $script.Contains('if (!isDevFallbackEnabled()) return recordCallThroughCore(event);') -and
    $script.Contains('if (!isDevFallbackEnabled()) return createScheduleThroughCore(event);') -and
    $script.Contains('if (!isDevFallbackEnabled()) return cancelRound1ThroughCore(event);') -and
    $script.Contains('function isDevConfiguration()') -and
    $script.Contains('if (!isDevConfiguration())')) `
    'Never auto-fallback from Candidate Core; enable the retained direct-write path only by explicit DEV switch'
Assert-Test ($script.Contains('const forceSubmit = (buttonId, formId) => {') -and
    $script.Contains('form.requestSubmit();') -and
    $script.Contains('forceSubmit("create-button", "candidate-form");') -and
    $script.Contains('forceSubmit("submit-call", "call-form");') -and
    $script.Contains('forceSubmit("save-schedule", "scheduling-form");') -and
    $script.Contains('forceSubmit("confirm-cancellation", "cancellation-form");') -and
    $script.Contains('forceSubmit("save-interview-result", "interview-result-form");')) `
    'Force submit action buttons through requestSubmit so UCI click handling always reaches form submit handlers'
Assert-Test ($html.Contains('id="candidate-search"') -and
    $script.Contains('candidate[TABLES.candidate.number]') -and
    $script.Contains('candidate[TABLES.candidate.name]') -and
    $script.Contains('candidate[TABLES.candidate.email]')) 'Search by Candidate Number, Name, and Email'
Assert-Test ($html.Contains('id="candidate-status-filter"') -and
    $script.Contains('String(candidate[TABLES.candidate.status]) === status')) 'Filter the list by Candidate status'
Assert-Test ($script.Contains('&$orderby=createdon desc') -and
    $html.Contains('id="refresh-button"')) 'Load newest Candidates first and expose Refresh'
Assert-Test ($html.Contains('<th scope="col">Position</th>') -and
    $html.Contains('<th scope="col">Candidate Source</th>') -and
    $script.Contains('formatted(candidate, TABLES.candidate.position)') -and
    $script.Contains('formatted(candidate, TABLES.candidate.source)')) 'Show reference names in the Candidate list'
Assert-Test ($script.Contains('row.classList.add("selected")') -and
    $style.Contains('tr.candidate-row.selected')) 'Highlight the selected Candidate row'
Assert-Test ($html.Contains('id="call-entry-panel"') -and
    $html.Contains('id="call-form"') -and
    $html.Contains('id="call-outcome"')) 'Use the visible Record Call panel'
Assert-Test ($html.Contains('Changed On / Created On') -and
    $script.Contains('history[h.changedAt] || history.createdon')) 'Show Status History time with Created On fallback'
Assert-Test ($html.Contains('data-action disabled') -and
    $script.Contains('if (busy || !selectedCandidate) return;')) 'Prevent call submission without a selection or during a request'
Assert-Test ($script.Contains('function isSyntheticInput(name, email)') -and
    $script.Contains('name.startsWith("[SYNTHETIC-E2E]")') -and
    $script.Contains('environmentPolicy.syntheticDataOnly && !isSyntheticInput(candidateName, candidateEmail)') -and
    $script.Contains('(!environmentPolicy.syntheticDataOnly || isSyntheticCandidateMarkers(candidate))') -and
    $script.Contains('\.invalid')) 'Apply the configured synthetic-only gate to candidate input and reads'
Assert-Test ($script.Contains('waitingManualScheduling: 100010002') -and
    $script.Contains('current[c.status] !== STATUS.answered') -and
    $script.Contains('[c.status]: STATUS.waitingManualScheduling')) 'Gate the explicit Answered-to-Waiting transition'
Assert-Test ($script.Contains('[history.previous]: STATUS.answered') -and
    $script.Contains('[history.current]: STATUS.waitingManualScheduling')) 'Record the Waiting transition in Status History'
Assert-Test ($html.Contains('id="schedule-round1-button"') -and
    $script.Contains('candidate[TABLES.candidate.status] === STATUS.waitingManualScheduling') -and
    $script.Contains('$("scheduling-panel").hidden = true;')) 'Expose Schedule Round 1 only from Waiting Manual Scheduling and close stale drafts on selection changes'
Assert-Test ($script.Contains('(scheduleMode === "reschedule"' ) -and
    $script.Contains('? !canManageSchedule()') -and
    $script -match '\$\("cancellation-panel"\)\.hidden = true;\r?\n\s+setBusy\(false\);\r?\n\s+\$\("scheduling-panel"\)\.scrollIntoView') `
    'Recompute Save Schedule availability when opening a draft and use pending active schedule eligibility for rescheduling'
Assert-Test ($html.Contains('id="scheduling-candidate"') -and
    $html.Contains('id="scheduling-ta"') -and
    $html.Contains('id="scheduling-date"') -and
    $html.Contains('id="scheduling-time"') -and
    $html.Contains('id="scheduling-end-time"') -and
    $html.Contains('id="scheduling-location"') -and
    $html.Contains('id="scheduling-notes"')) 'Provide the compact Round 1 scheduling draft fields'
Assert-Test ($html.Contains('id="schedule-history-rows"') -and
    $html.Contains('<th>Date/Time</th>') -and
    $script.Contains('function renderSchedulingDetails') -and
    $html.Contains('<th>Scheduling Status</th>') -and
    $html.Contains('<th>Status Changed At</th>') -and
    $html.Contains('<th>Cancellation / Reschedule Reason</th>') -and
    $script.Contains('&$orderby=createdon desc')) 'Show all Round 1 schedule history newest-first'
Assert-Test ($html.Contains('id="save-schedule"') -and
    $html.Contains('Manual schedule evidence only. No calendar availability check or calendar booking is performed.') -and
    $script.Contains('round1: 100000000') -and
    $script.Contains('round1Scheduled: 100010003')) 'Use the reconciled schedule round and Candidate status values without implying calendar booking'
Assert-Test ($script.Contains('loadLookupOptions("os_sr_ta", "scheduling-ta"') -and
    $script.Contains('loadLookupOptions("os_sr_loc", "scheduling-location"') -and
    $script.Contains('label.startsWith("[DEV]")')) 'Load only active synthetic TA and Location lookup choices'
Assert-Test ($script.Contains('getActiveSyntheticReference("os_sr_ta"') -and
    $script.Contains('getActiveSyntheticReference("os_sr_loc"') -and
    $script.Contains('reference.statecode !== 0')) 'Revalidate both active [DEV] references before persistence'
$scheduleStart = $script.IndexOf('async function createSchedule(event)')
$scheduleEnd = $script.IndexOf('async function loadTableMetadata', $scheduleStart)
$scheduleFlow = $script.Substring($scheduleStart, $scheduleEnd - $scheduleStart)
$scheduleCreateIndex = $scheduleFlow.IndexOf('createRecord(interview.logicalName')
$scheduleReadbackIndex = $scheduleFlow.IndexOf('retrieveRecord(', $scheduleCreateIndex)
$candidateUpdateIndex = $scheduleFlow.IndexOf('updateRecord(c.logicalName', $scheduleReadbackIndex)
$historyCreateIndex = $scheduleFlow.IndexOf('createRecord(history.logicalName', $candidateUpdateIndex)
Assert-Test ($scheduleStart -ge 0 -and $scheduleEnd -gt $scheduleStart -and
    $scheduleCreateIndex -ge 0 -and $scheduleReadbackIndex -gt $scheduleCreateIndex -and
    $candidateUpdateIndex -gt $scheduleReadbackIndex -and
    $historyCreateIndex -gt $candidateUpdateIndex -and
    $scheduleFlow.Contains('[c.status]: STATUS.round1Scheduled')) 'Persist and read back schedule before Candidate status and Status History'
Assert-Test ($script.Contains('scheduleRetryBlockedCandidateId') -and
    $script.Contains('Round 1 schedule state changed or is ambiguous') -and
    $script.Contains('No compensation or retry was performed')) 'Block duplicate submissions and report nontransactional partial failures without compensation'
Assert-Test (-not $script.Contains('WebApi.deleteRecord') -and
    -not $script.Contains('PublishAllXml')) 'Do not compensate by deleting persisted schedules or publish globally'
Assert-Test (-not $html.Contains('id="candidate-status"') -and
    -not $html.Contains('<dialog') -and
    -not $html.Contains('call-dialog')) 'Expose no arbitrary status editor or call debug dialog'
Assert-Test ($html.Contains('id="record-interview-result-button"') -and
    $html.Contains('id="interview-result-form"') -and
    $html.Contains('<option value="100000001">Pass</option>') -and
    $html.Contains('<option value="100000002">Fail</option>') -and
    $html.Contains('id="interview-result-notes"') -and
    -not $html.Contains('<option value="100000000">Pending</option>')) 'Offer exactly Pass and Fail with optional notes'
Assert-Test ($script.Contains('offerExtended: 100010004') -and
    $script.Contains('candidateFailed: 100010005') -and
    $script.Contains('pending: 100000000') -and
    $script.Contains('pass: 100000001') -and
    $script.Contains('fail: 100000002')) 'Use status and result values reconciled from authoritative Choice metadata'
Assert-Test ($script.Contains('activeSchedules.length === 1') -and
    $script.Contains('selectedCandidate[TABLES.candidate.status] === STATUS.round1Scheduled') -and
    $script.Contains('isPendingInterviewResult(selectedSchedule)') -and
    $script.Contains('resultRetryBlockedCandidateId !== candidateId')) 'Show result action only for one persisted Round 1 schedule with Pending or unset result'
$resultStart = $script.IndexOf('async function recordInterviewResult(event)')
$resultEnd = $script.IndexOf('async function createSchedule(event)', $resultStart)
$resultFlow = $script.Substring($resultStart, $resultEnd - $resultStart)
$candidateReadIndex = $resultFlow.IndexOf('const current = await xrm().WebApi.retrieveRecord')
$scheduleVerifyIndex = $resultFlow.IndexOf('const schedules = await findRound1Schedules', $candidateReadIndex)
$scheduleUpdateIndex = $resultFlow.IndexOf('updateRecord(interview.logicalName', $scheduleVerifyIndex)
$resultReadbackIndex = $resultFlow.IndexOf('const saved = await xrm().WebApi.retrieveRecord', $scheduleUpdateIndex)
$candidateUpdateIndex = $resultFlow.IndexOf('updateRecord(c.logicalName', $resultReadbackIndex)
$resultHistoryIndex = $resultFlow.IndexOf('createRecord(history.logicalName', $candidateUpdateIndex)
Assert-Test ($resultStart -ge 0 -and $resultEnd -gt $resultStart -and
    $candidateReadIndex -ge 0 -and $scheduleVerifyIndex -gt $candidateReadIndex -and
    $scheduleUpdateIndex -gt $scheduleVerifyIndex -and
    $resultReadbackIndex -gt $scheduleUpdateIndex -and
    $candidateUpdateIndex -gt $resultReadbackIndex -and
    $resultHistoryIndex -gt $candidateUpdateIndex -and
    $resultFlow.Contains('STATUS.offerExtended') -and
    $resultFlow.Contains('STATUS.candidateFailed')) 'Persist and read back result before the exact Pass/Fail Candidate transition and Status History'
Assert-Test ($resultFlow.Contains('Math.floor(savedRecordedAt / 1000) === Math.floor(expectedRecordedAt / 1000)') -and
    $resultFlow.Contains('Number.isFinite(savedRecordedAt)') -and
    $resultFlow.Contains('failedReadbackChecks.join("_").toUpperCase()')) 'Compare User Local result timestamps at Dataverse second precision and log only failed check names'
Assert-Test ($resultFlow.Contains('resultRetryBlockedCandidateId = candidateId') -and
    $resultFlow.Contains('Interview result was persisted, but the Candidate status update failed or is uncertain') -and
    $resultFlow.Contains('Status History creation failed or is uncertain') -and
    -not $resultFlow.Contains('WebApi.deleteRecord')) 'Preserve partial result writes, refresh, warn safely, and never retry or compensate'
Assert-Test ($script.Contains('RecordRound1Pass') -and
    $script.Contains('RecordRound1Fail') -and
    $script.Contains('!canRecordInterviewResult()')) 'Record distinct Pass/Fail history operations and protect against duplicate submission'
Assert-Test ($html.Contains('id="reschedule-round1-button"') -and
    $html.Contains('id="cancel-round1-button"') -and
    $html.Contains('id="scheduling-reason"') -and
    $html.Contains('id="cancellation-reason"') -and
    $html.Contains('maxlength="1000" required') -and
    $script.Contains('canManageSchedule()') -and
    $script.Contains('isPendingInterviewResult(selectedSchedule)')) 'Gate reschedule and cancellation to one active pending schedule and require reason fields'
$rescheduleStart = $script.IndexOf('async function rescheduleRound1()')
$rescheduleEnd = $script.IndexOf('async function cancelRound1(event)', $rescheduleStart)
$rescheduleFlow = $script.Substring($rescheduleStart, $rescheduleEnd - $rescheduleStart)
$oldScheduleUpdateIndex = $rescheduleFlow.IndexOf('updateRecord(interview.logicalName')
$oldScheduleReadbackIndex = $rescheduleFlow.IndexOf('const superseded = await xrm().WebApi.retrieveRecord', $oldScheduleUpdateIndex)
$proposalCreateIndex = $rescheduleFlow.IndexOf('createRecord(interview.logicalName', $oldScheduleReadbackIndex)
$proposalReadbackIndex = $rescheduleFlow.IndexOf('const proposal = await xrm().WebApi.retrieveRecord', $proposalCreateIndex)
$rescheduleCandidateUpdateIndex = $rescheduleFlow.IndexOf('updateRecord(c.logicalName', $proposalReadbackIndex)
$rescheduleHistoryIndex = $rescheduleFlow.IndexOf('createRecord(history.logicalName', $rescheduleCandidateUpdateIndex)
Assert-Test ($oldScheduleUpdateIndex -ge 0 -and
    $oldScheduleReadbackIndex -gt $oldScheduleUpdateIndex -and
    $proposalCreateIndex -gt $oldScheduleReadbackIndex -and
    $proposalReadbackIndex -gt $proposalCreateIndex -and
    $rescheduleCandidateUpdateIndex -gt $proposalReadbackIndex -and
    $rescheduleHistoryIndex -gt $rescheduleCandidateUpdateIndex -and
    $rescheduleFlow.Contains('[interview.status]: SCHEDULE_STATUS.superseded') -and
    $rescheduleFlow.Contains('[c.status]: STATUS.needCall') -and
    $rescheduleFlow.Contains('[interview.status]: SCHEDULE_STATUS.proposed')) 'Preserve/supersede old schedule and read back a Proposed replacement before returning Candidate to Need Call'
$cancelStart = $script.IndexOf('async function cancelRound1(event)')
$cancelEnd = $script.IndexOf('async function loadTableMetadata', $cancelStart)
$cancelFlow = $script.Substring($cancelStart, $cancelEnd - $cancelStart)
$cancelUpdateIndex = $cancelFlow.IndexOf('updateRecord(interview.logicalName')
$cancelReadbackIndex = $cancelFlow.IndexOf('const cancelled = await xrm().WebApi.retrieveRecord', $cancelUpdateIndex)
$cancelCandidateUpdateIndex = $cancelFlow.IndexOf('updateRecord(c.logicalName', $cancelReadbackIndex)
$cancelHistoryIndex = $cancelFlow.IndexOf('createRecord(history.logicalName', $cancelCandidateUpdateIndex)
Assert-Test ($cancelUpdateIndex -ge 0 -and $cancelReadbackIndex -gt $cancelUpdateIndex -and
    $cancelCandidateUpdateIndex -gt $cancelReadbackIndex -and
    $cancelHistoryIndex -gt $cancelCandidateUpdateIndex -and
    $cancelFlow.Contains('[interview.status]: SCHEDULE_STATUS.cancelled') -and
    $cancelFlow.Contains('[c.status]: STATUS.needCall') -and
    $cancelFlow.Contains('Cancellation Reason')) 'Read back cancellation before Candidate transition and Status History'
Assert-Test ($script.Contains('scheduleRows.filter(isActiveSchedule).length === 1') -and
    $script.Contains('!scheduleRows.some((row) => row[TABLES.interview.status] === SCHEDULE_STATUS.proposed)') -and
    $script.Contains('SCHEDULE_STATUS.proposed') -and
    $script.Contains('function isKnownScheduleState') -and
    $script.Contains('scheduleStatusLabel')) 'Fail closed on ambiguous schedule states and promote only a Proposed replacement after re-contact'
Assert-Test (-not $script.Contains('WebApi.deleteRecord') -and
    $script.Contains('Do not retry blindly') -and
    $script.Contains('No compensation or retry was performed')) 'Preserve schedule history and report partial writes without retry or compensation'

$deploymentPath = Join-Path $root 'scripts\Deploy-BsoRsCandidateConsole.ps1'
$deployment = Get-Content -LiteralPath $deploymentPath -Raw
$publishCalls = [regex]::Matches($deployment, "Invoke-DataverseRequest -Method POST -Path 'PublishXml'")
$publishedReadbacks = [regex]::Matches($deployment, 'Assert-PublishedWebResourceReadback')
Assert-Test ($publishCalls.Count -eq 3 -and
    $publishedReadbacks.Count -eq 3 -and
    $publishedReadbacks[1].Index -gt $publishCalls[0].Index -and
    $publishedReadbacks[2].Index -gt $publishCalls[1].Index -and
    $deployment.Contains('PUBLISHED_GET_RECONCILED') -and
    $deployment.Contains('PUBLISH_ACCEPTED_RECONCILIATION_FAILED')) `
    'Require exact published-resource GET reconciliation after each scoped PublishXml'
$publishOnlyStart = $deployment.IndexOf('        if ($PublishOnly) {')
$publishOnlyNextRefresh = $deployment.IndexOf(
    "        foreach (`$resource in `$resources) {`r`n            `$entry = @(`$script:Journal.Dispatches | Where-Object Name -CEQ `$resource.Name)[0]`r`n            `$matches = @(`$existing.value | Where-Object name -CEQ `$resource.Name)",
    $publishOnlyStart
)
$publishOnlyBlock = if ($publishOnlyStart -ge 0 -and $publishOnlyNextRefresh -gt $publishOnlyStart) {
    $deployment.Substring($publishOnlyStart, $publishOnlyNextRefresh - $publishOnlyStart)
} else { '' }
Assert-Test ($deployment.Contains('[switch]$PublishOnly') -and
    $deployment.Contains('($PublishOnly -and (-not $Apply -or -not $RefreshExisting -or -not $ReleaseNeutralProfile') -and
    $deployment.Contains("'os_/bso/candidate-console-environment.js' = '58e03dc262b790b7431f34ca5554422fc86f0d62f6e8b6160805a6b2d906335c'") -and
    $deployment.Contains("'os_/bso/candidate-console.html' = '1fe0782fd56432eca75959e412bc15e109b51818eeae4251846bcb8bbe61dbd9'") -and
    $publishOnlyBlock -and
    -not $publishOnlyBlock.Contains('-Method PATCH') -and
    $publishOnlyBlock.Contains('$state.Source -cne ''Unpublished''') -and
    $publishOnlyBlock.Contains('CANDIDATE_CONSOLE_SOURCE_CONTENT_DRIFT') -and
    $publishOnlyBlock.Contains('MANAGED_ARTIFACT_SOURCE_QUALIFICATION_FAILED:UNEXPECTED_UNPUBLISHED_RESOURCE') -and
    $publishOnlyBlock.Contains('Stop-PublishOnlyPreflight') -and
    $publishOnlyBlock.Contains('TargetedResourceCount = $resources.Count') -and
    $publishOnlyBlock.Contains('$assetName.Substring($assetName.LastIndexOf(''/'') + 1)') -and
    $publishOnlyBlock.Contains('ResourcePatchCount = $script:Counts.PATCH') -and
    $publishOnlyBlock.Contains('CANDIDATE_CONSOLE_PUBLICATION_OUTCOME_AMBIGUOUS') -and
    $publishOnlyBlock.Contains('CANDIDATE_CONSOLE_SOURCE_BASELINE_RECONCILED')) `
    'Require exact accepted hashes and source publication mismatch before a zero-PATCH scoped publish with GET-only reconciliation'
$resourceSelection = $deployment.IndexOf('$resources = @($allResources | Where-Object { $RefreshResourceNames -ccontains $_.Name })')
$publishLabel = $deployment.IndexOf('$publishLabel = "srapp + $($resources.Count) exact web resources scoped PublishXml"')
Assert-Test ($deployment.Contains('[string[]]$RefreshResourceNames = @()') -and
    $deployment.Contains('if ($Continue -or (-not $RefreshExisting -and -not $CreateNewResources))') -and
    $resourceSelection -ge 0 -and $publishLabel -gt $resourceSelection -and
    $deployment.Contains('$publishEntry = @($script:Journal.Dispatches | Where-Object Name -CEQ $publishLabel)[0]') -and
    $deployment.Contains('foreach ($resourceId in $script:Journal.ResourceIds)')) `
    'Allow exact existing-resource refreshes and scope PublishXml to only selected web resources'
Assert-Test ($deployment.Contains('[switch]$CreateNewResources') -and
    $deployment.Contains('New-resource creation is restricted to the two exact Candidate Console configuration resources.') -and
    $deployment.Contains('$environmentConfiguration.environmentId -ine $target.EnvironmentId') -and
    $deployment.Contains('Generated environment files must remain outside the repository.') -and
    $deployment.Contains('[string]$EnvironmentHtmlPath') -and
    $deployment.Contains('Generated HTML differs from the checked-in source except for the verified environment cache token.') -and
    $deployment.Contains('candidate-console-environment.js') -and
    $deployment.Contains('candidate-console-policy.js')) `
    'Restrict creation to the two configuration resources and verify the external DEV configuration before dispatch'
Assert-Test ($deployment.Contains('[switch]$ReleaseNeutralProfile') -and
    $deployment.Contains('Release-neutral refresh is restricted to the existing environment configuration and matching HTML resources.') -and
    $deployment.Contains("if (`$ReleaseNeutralProfile -and -not `$PublishOnly -and `$effective.Source -cne 'Published' -and") -and
    $deployment.Contains('Release-neutral source baseline contains an unpublished resource; stop without refresh.') -and
    $deployment.Contains('EffectiveSource -cne ''Published'' -or -not $_.PublishedMatchesEffective') -and
    $deployment.Contains('CANDIDATE_CONSOLE_SOURCE_BASELINE_UNRECONCILED') -and
    $deployment.Contains('$environmentConfiguration.mode -cne ''UNCONFIGURED''') -and
    $deployment.Contains('$environmentConfiguration.candidateCoreEnabled -ne $false') -and
    $deployment.Contains('$environmentConfiguration.syntheticDataOnly -ne $true') -and
    $deployment.Contains('$environmentConfiguration.devDirectWriteFallbackEnabled -ne $false') -and
    $deployment.Contains('$environmentConfiguration.diagnosticsMode -cne ''OFF''')) `
    'Permit only the exact fail-closed release-neutral configuration and HTML refresh'
Assert-Test ($deployment.Contains('[string]$BaselineSnapshotPath') -and
    $deployment.Contains('Baseline snapshot capture requires a new external path and a read-only release-neutral existing-resource preflight.') -and
    $deployment.Contains('PublishedContentBase64 = [Convert]::ToBase64String($publishedBytes)') -and
    $deployment.Contains('EffectiveContentBase64 = [Convert]::ToBase64String($remoteBytes)') -and
    $deployment.Contains('EffectiveSource -cne ''Published'' -or -not $_.PublishedMatchesEffective') -and
    $deployment.Contains('CANDIDATE_CONSOLE_SOURCE_BASELINE_UNRECONCILED') -and
    $deployment.Contains('BaselineVersionsMatch = $baselineVersionsMatch')) `
    'Capture exact published and effective resource bytes outside the repository and block on version drift'
Assert-Test ($deployment.Contains('CANDIDATE_CONSOLE_CONFIG_RESOURCES_PREFLIGHT_READY') -and
    $deployment.Contains('if (-not $Continue -and -not $CreateNewResources -and -not $RefreshExisting)') -and
    $deployment.Contains('NOT_REQUIRED_EXISTING_NAVIGATION_RECONCILED') -and
    $deployment.Contains('Assert-PublishedWebResourceReadback')) `
    'Create only the selected configuration resources, preserve the sitemap, and reconcile published bytes'
Assert-Test ($deployment.Contains('if (-not $Continue -and -not $CreateNewResources -and -not $RefreshExisting)') -and
    $deployment.Contains('if ($CreateNewResources -or $RefreshExisting)') -and
    $deployment.Contains('PublishXmlIncludesOnlyTargetAppAndSelectedWebResources = $true') -and
    $deployment.Contains('$publishLabel = "srapp + $($resources.Count) exact web resources scoped PublishXml"')) `
    'Refresh exact web resources without PATCHing the sitemap and publish only selected resources with srapp'

$hash = (Get-FileHash -LiteralPath $scriptPath -Algorithm SHA256).Hash.ToLowerInvariant()
$version = [regex]::Match($html, 'candidate-console\.js\?v=([0-9a-f]+)')
Assert-Test ($version.Success -and $hash.StartsWith($version.Groups[1].Value)) 'Keep the script cache version tied to its content'
$resourceVersions = @(
    @{ Path = $configurationPath; Name = 'candidate-console-environment.js' },
    @{ Path = $policyPath; Name = 'candidate-console-policy.js' }
)
foreach ($resource in $resourceVersions) {
    $resourceHash = (Get-FileHash -LiteralPath $resource.Path -Algorithm SHA256).Hash.ToLowerInvariant()
    $resourceVersion = [regex]::Match($html, "$([regex]::Escape($resource.Name))\?v=([0-9a-f]+)")
    Assert-Test ($resourceVersion.Success -and $resourceHash.StartsWith($resourceVersion.Groups[1].Value)) `
        "Keep $($resource.Name) cache version tied to its content"
}

Write-Output "Candidate Console static checks passed: $passed"
