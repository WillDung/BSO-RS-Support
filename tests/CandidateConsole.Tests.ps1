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
    -not $html.Contains('PROTECTCANDIDATECORE') -and
    -not $script.Contains('PROTECTCANDIDATECORE')) 'Default to the Candidate Core path without the obsolete ProtectCandidateCore diagnostic'
Assert-Test (-not $html.Contains('REAL-DATA MODE') -and -not $script.Contains('REAL-DATA MODE') -and
    -not $script.Contains('REAL DATA NOT APPROVED') -and
    $script.Contains('? environmentPolicy.mode') -and
    $script.Contains('"PRODUCTION CONFIGURATION"') -and
    $script.Contains('"SYNTHETIC DATA ONLY"')) 'Label the environment mode neutrally without implying real-data authorization'
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
    $policy.Contains('directWriteFallbackAvailable: candidateOperationMode !== "SingleUserDev"') -and
    $policy.Contains('mode === "DEV" && configuration.devDirectWriteFallbackEnabled')) `
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
$coreInvokeStart = $script.IndexOf('async function sendCandidateCoreRequest')
$coreInvokeEnd = $script.IndexOf('async function invokeCandidateCore', $coreInvokeStart)
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
    'CreateCandidate', 'UpdateCandidate', 'RecordCall', 'ProceedToScheduling', 'MarkRound1Scheduled',
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
    $script.Contains('forceSubmit("save-candidate-profile", "edit-candidate-form");') -and
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
    $html.Contains('<th scope="col">Assigned TA</th>') -and
    $script.Contains('formatted(candidate, TABLES.candidate.position)') -and
    $script.Contains('formatted(candidate, TABLES.candidate.source)') -and
    $script.Contains('formatted(candidate, TABLES.candidate.assignedTa)')) 'Show Candidate reference names in the list'
Assert-Test ($html.Contains('id="candidate-cv-url"') -and
    $html.Contains('id="candidate-assigned-ta"') -and
    $html.Contains('id="edit-candidate-form"') -and
    $html.Contains('id="edit-candidate-cv-url"') -and
    $html.Contains('id="edit-candidate-assigned-ta"') -and
    $script.Contains('"CandidateCvUrl"') -and $script.Contains('"AssignedTaId"') -and
    $script.Contains('invokeCandidateCore("UpdateCandidate", inputs, newCorrelationId())') -and
    $script.Contains('addDetailLink(details, "Candidate CV URL"') -and
    $script.Contains('getLookupName("os_sr_ta", candidate[TABLES.candidate.assignedTa])')) `
    'Create, view, and update Candidate CV URL and Assigned TA only through Candidate Core'
Assert-Test ($script.Contains('"ProfileFieldMask"') -and
    $script.Contains('const PROFILE_FIELD_ORDER = [') -and
    $script.Contains('canonicalProfileFieldMask(changedProfileFields)') -and
    $script.Contains('changedProfileFields.add(inputName);')) `
    'Declare and send the explicit changed-profile field mask through Candidate Core'
Assert-Test ($script.Contains('row.classList.add("selected")') -and
    $style.Contains('tr.candidate-row.selected')) 'Highlight the selected Candidate row'
Assert-Test ($html.Contains('id="call-entry-panel"') -and
    $html.Contains('id="call-form"') -and
    $html.Contains('id="call-outcome"')) 'Use the visible Record Call panel'
Assert-Test ($script -match 'function canRecordCall\(status\) \{\r?\n\s+return status === STATUS\.needCall;\r?\n\s+\}' -and
    $script.Contains('call.hidden = !canRecordCall(candidate[TABLES.candidate.status]);') -and
    $script.Contains('$("call-entry-panel").hidden = !callAllowed;') -and
    $script.Contains('$("submit-call").disabled = busy || !callAllowed;') -and
    $script.Contains('(!selectedCandidate || !canRecordCall(selectedCandidate[TABLES.candidate.status]))') -and
    ([regex]::Matches($script, 'if \(!canRecordCall\(').Count -eq 2) -and
    -not $script.Contains('const terminal = [STATUS.offerExtended, STATUS.candidateFailed]')) `
    'Gate every Record Call surface on the Need Call Candidate state only'
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
Assert-Test ($script.Contains('loadLookupOptions("os_sr_ta"') -and
    $script.Contains('"candidate-assigned-ta"') -and
    $script.Contains('"scheduling-ta"') -and
    $script.Contains('loadLookupOptions("os_sr_loc", "scheduling-location"') -and
    $script.Contains('SINGLE_USER_DEV_REFERENCE_SCOPE_KEYS') -and
    $script.Contains('getSingleUserDevReferenceId(tableName).toLowerCase()') -and
    $script.Contains('select.value = expectedId') -and
    $script.Contains('readSingleUserDevRecords(tableLogicalName)') -and
    $script.Contains('Loading options...') -and
    $script.Contains('Options unavailable; use Refresh reference options to retry') -and
    $script.Contains('No active ${REFERENCE_OPTION_LABELS[tableName] || "reference"} records found') -and
    $script.Contains('isReferenceAllowedByDataMode(label)') -and
    $script.Contains('policy.allowsReference(label, environmentPolicy.syntheticDataOnly)')) `
    'Load active reference choices, pin SingleUserDev selections to approved profile IDs, and show lookup loading/error/empty states'
Assert-Test ($html.Contains('id="candidate-data-mode"') -and
    $html.Contains('value="NORMAL"') -and
    $html.Contains('id="refresh-references"') -and
    $script.Contains('let referenceMode = "CONFIGURED";') -and
    $script.Contains('NORMAL_CANDIDATE_OPERATION_NOT_AUTHORIZED') -and
    $script.Contains('CANDIDATE_WORKSPACE_NOT_READY') -and
    $script.Contains('async function readNormalReferenceRecords') -and
    $script.Contains('referenceMode === "NORMAL") return filter;') -and
    $script.Contains('Promise.allSettled') -and
    $script.Contains('previousValues[index]')) `
    'Keep normal references explicitly selected, native permission-bound, refreshable and isolated from unauthorized Candidate operations'
Assert-Test ($script.Contains('getActiveReference("os_sr_ta"') -and
    $script.Contains('getActiveReference("os_sr_loc"') -and
    $script.Contains('reference.statecode !== 0') -and
    $script.Contains('!isReferenceAllowedByDataMode(reference[metadata.PrimaryNameAttribute])')) `
    'Revalidate active TA and Location references against the same configured data policy before persistence'
$scheduleStart = $script.IndexOf('async function createSchedule(event)')
$scheduleEnd = $script.IndexOf('async function loadTableMetadata', $scheduleStart)
$scheduleFlow = $script.Substring($scheduleStart, $scheduleEnd - $scheduleStart)
$scheduleCreateIndex = $scheduleFlow.IndexOf('createRecord(interview.logicalName')
$scheduleReadbackIndex = $scheduleFlow.IndexOf('const saved = await retrieveInterviewRecord(', [Math]::Max(0, $scheduleCreateIndex))
$candidateUpdateIndex = $scheduleFlow.IndexOf('updateRecord(c.logicalName', [Math]::Max(0, $scheduleReadbackIndex))
$historyCreateIndex = $scheduleFlow.IndexOf('createRecord(history.logicalName', [Math]::Max(0, $candidateUpdateIndex))
Assert-Test ($scheduleStart -ge 0 -and $scheduleEnd -gt $scheduleStart -and
    $scheduleCreateIndex -ge 0 -and $scheduleReadbackIndex -gt $scheduleCreateIndex -and
    $candidateUpdateIndex -gt $scheduleReadbackIndex -and
    $historyCreateIndex -gt $candidateUpdateIndex -and
    $scheduleFlow.Contains('[c.status]: STATUS.round1Scheduled')) 'Persist and read back schedule before Candidate status and Status History'
Assert-Test ($script.Contains('async function retrieveInterviewRecord(recordId, candidateId, select, expectedReferences)') -and
    $script.Contains('return xrm().WebApi.retrieveRecord(interview.logicalName, recordId, select);') -and
    $script.Contains('return retrieveScopedSingle(interview.logicalName, select, filter);') -and
    $script.Contains('async function retrieveCandidateRecord(candidateId, select)')) `
    'Retain non-synthetic readback while routing synthetic schedule and Candidate readbacks through scoped queries'
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
$candidateReadIndex = $resultFlow.IndexOf('const current = await retrieveCandidateRecord(')
$scheduleVerifyIndex = $resultFlow.IndexOf('const schedules = await findRound1Schedules', [Math]::Max(0, $candidateReadIndex))
$scheduleUpdateIndex = $resultFlow.IndexOf('updateRecord(interview.logicalName', [Math]::Max(0, $scheduleVerifyIndex))
$resultReadbackIndex = $resultFlow.IndexOf('const saved = await retrieveInterviewRecord(', [Math]::Max(0, $scheduleUpdateIndex))
$candidateUpdateIndex = $resultFlow.IndexOf('updateRecord(c.logicalName', [Math]::Max(0, $resultReadbackIndex))
$resultHistoryIndex = $resultFlow.IndexOf('createRecord(history.logicalName', [Math]::Max(0, $candidateUpdateIndex))
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
$oldScheduleReadbackIndex = $rescheduleFlow.IndexOf('const superseded = await retrieveInterviewRecord(', [Math]::Max(0, $oldScheduleUpdateIndex))
$proposalCreateIndex = $rescheduleFlow.IndexOf('createRecord(interview.logicalName', [Math]::Max(0, $oldScheduleReadbackIndex))
$proposalReadbackIndex = $rescheduleFlow.IndexOf('const proposal = await retrieveInterviewRecord(', [Math]::Max(0, $proposalCreateIndex))
$rescheduleCandidateUpdateIndex = $rescheduleFlow.IndexOf('updateRecord(c.logicalName', [Math]::Max(0, $proposalReadbackIndex))
$rescheduleHistoryIndex = $rescheduleFlow.IndexOf('createRecord(history.logicalName', [Math]::Max(0, $rescheduleCandidateUpdateIndex))
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
$cancelReadbackIndex = $cancelFlow.IndexOf('const cancelled = await retrieveInterviewRecord(', [Math]::Max(0, $cancelUpdateIndex))
$cancelCandidateUpdateIndex = $cancelFlow.IndexOf('updateRecord(c.logicalName', [Math]::Max(0, $cancelReadbackIndex))
$cancelHistoryIndex = $cancelFlow.IndexOf('createRecord(history.logicalName', [Math]::Max(0, $cancelCandidateUpdateIndex))
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
$deploymentTokens = $null
$deploymentParseErrors = $null
$deploymentAst = [System.Management.Automation.Language.Parser]::ParseFile(
    $deploymentPath,
    [ref]$deploymentTokens,
    [ref]$deploymentParseErrors
)
$layerHelperAst = $deploymentAst.Find({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -eq 'Test-WebResourceLayerEquivalence'
}, $true)
$definitionHelperAst = $deploymentAst.Find({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -eq 'Test-WebResourceDefinitionEquivalence'
}, $true)
$publishXmlHelperAst = $deploymentAst.Find({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -eq 'New-CandidateConsolePublishParameterXml'
}, $true)
if ($null -eq $layerHelperAst -or $null -eq $definitionHelperAst -or
    $null -eq $publishXmlHelperAst) {
    throw 'Candidate Console publication helpers are missing.'
}
. ([scriptblock]::Create($layerHelperAst.Extent.Text))
. ([scriptblock]::Create($definitionHelperAst.Extent.Text))
. ([scriptblock]::Create($publishXmlHelperAst.Extent.Text))
$approvedHash = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
$otherHash = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
$matchingLayers = Test-WebResourceLayerEquivalence `
    -PublishedSha256 $approvedHash -CurrentSha256 $approvedHash `
    -EffectiveSha256 $approvedHash -ExpectedSha256 $approvedHash
$currentPublishedOnly = Test-WebResourceDefinitionEquivalence `
    -PublishedSha256 $approvedHash -CurrentSha256 $approvedHash -ExpectedSha256 $approvedHash
$componentStateOneEvidence = [pscustomobject]@{
    ComponentState = 1
    Sha256 = $approvedHash
}
$componentStateOneLayers = Test-WebResourceLayerEquivalence `
    -PublishedSha256 $approvedHash -CurrentSha256 $componentStateOneEvidence.Sha256 `
    -EffectiveSha256 $approvedHash -ExpectedSha256 $approvedHash
$publishedCurrentMismatch = Test-WebResourceLayerEquivalence `
    -PublishedSha256 $otherHash -CurrentSha256 $approvedHash `
    -EffectiveSha256 $approvedHash -ExpectedSha256 $approvedHash
$effectivePublishedMismatch = Test-WebResourceLayerEquivalence `
    -PublishedSha256 $approvedHash -CurrentSha256 $approvedHash `
    -EffectiveSha256 $otherHash -ExpectedSha256 $approvedHash
$missingEffectiveEvidence = Test-WebResourceLayerEquivalence `
    -PublishedSha256 $approvedHash -CurrentSha256 $approvedHash `
    -EffectiveSha256 $null -ExpectedSha256 $approvedHash
$missingPublishedEvidence = Test-WebResourceLayerEquivalence `
    -PublishedSha256 $null -CurrentSha256 $approvedHash `
    -EffectiveSha256 $approvedHash -ExpectedSha256 $approvedHash
Assert-Test ($matchingLayers.IsReconciled -and
    -not $currentPublishedOnly.PSObject.Properties['EffectiveEvidencePresent'] -and
    -not $publishedCurrentMismatch.IsReconciled -and
    -not $effectivePublishedMismatch.IsReconciled -and
    -not $missingEffectiveEvidence.IsReconciled -and
    -not $missingPublishedEvidence.IsReconciled) `
    'Require published, current, effective, and expected hashes to match; missing evidence fails closed'
Assert-Test ($currentPublishedOnly.IsReconciled -and
    $componentStateOneEvidence.ComponentState -eq 1 -and
    $componentStateOneLayers.IsReconciled -and
    $deployment.Contains('CurrentComponentState = $current.Row.componentstate') -and
    -not $layerHelperAst.Extent.Text.Contains('componentstate')) `
    'Do not treat RetrieveUnpublished existence or componentstate alone as a publication failure'
$publishWebResourceId = '11111111-1111-1111-1111-111111111111'
$secondPublishWebResourceId = '55555555-5555-5555-5555-555555555555'
$publishWebResourceIdUnique = '22222222-2222-2222-2222-222222222222'
$publishSolutionComponentId = '33333333-3333-3333-3333-333333333333'
$parameterXml = New-CandidateConsolePublishParameterXml `
    -WebResourceIds @($publishWebResourceId, $secondPublishWebResourceId)
$expectedParameterXml = "<importexportxml><webresources><webresource>$publishWebResourceId</webresource><webresource>$secondPublishWebResourceId</webresource></webresources></importexportxml>"
$parameterXmlDocument = [xml]$parameterXml
$publishedResourceNodes = @($parameterXmlDocument.SelectNodes('/importexportxml/webresources/webresource'))
$nonWebResourceNodes = @($parameterXmlDocument.SelectNodes('//appmodules|//sitemaps|//sitemap'))
$wrongIdentityRejected = $false
try {
    [void](New-CandidateConsolePublishParameterXml `
        -WebResourceIds @('not-a-webresource-guid'))
} catch {
    $wrongIdentityRejected = $true
}
Assert-Test ($parameterXml -ceq $expectedParameterXml -and
    $publishedResourceNodes.Count -eq 2 -and
    $nonWebResourceNodes.Count -eq 0 -and
    -not $parameterXml.Contains($publishWebResourceIdUnique) -and
    -not $parameterXml.Contains($publishSolutionComponentId) -and
    $wrongIdentityRejected -and
    $deployment.Contains('$resourceId = [string]$matches[0].webresourceid') -and
    -not $deployment.Contains('$resourceId = [string]$matches[0].webresourceidunique') -and
    $deployment.Contains('$script:Journal.ParameterXml = $parameterXml') -and
    -not $deployment.Contains('-AppModuleId $target.AppId')) `
    'Build and journal WebResource-only PublishXml with exactly the selected resource IDs'
$publishCalls = [regex]::Matches($deployment, "Invoke-DataverseRequest -Method POST -Path 'PublishXml'")
$publishedReadbacks = [regex]::Matches($deployment, 'Assert-PublishedWebResourceReadback')
Assert-Test ($publishCalls.Count -eq 3 -and
    $publishedReadbacks.Count -eq 3 -and
    $publishedReadbacks[1].Index -gt $publishCalls[0].Index -and
    $publishedReadbacks[2].Index -gt $publishCalls[1].Index -and
    $deployment.Contains('PUBLISHED_GET_RECONCILED') -and
    $deployment.Contains('PUBLISH_ACCEPTED_RECONCILIATION_FAILED')) `
    'Require exact published-resource GET reconciliation after each scoped PublishXml'
$publishOnlyWork = $deployment.IndexOf('$publishResourceIds =')
$publishOnlyStart = $deployment.LastIndexOf('        if ($PublishOnly) {', $publishOnlyWork)
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
    $deployment.Contains("'os_/bso/candidate-console.html' = 'f28b26fa4b7c72ce7cd3fa08d9f25d831334633f0e411fe715d5aa4c7393ef79'") -and
    $deployment.Contains("'docs\SOLUTION_COMPONENT_INVENTORY.json'") -and
    $deployment.Contains("'docs\RELEASE_INPUT_MANIFEST.json'") -and
    $deployment.Contains("'solutions\Other\Solution.xml'") -and
    $deployment.Contains("'solutions\WebResources\os_\bso'") -and
    $deployment.Contains("'candidate-console*.data.xml'") -and
    $deployment.Contains('$canonicalCandidateConsoleNames.Count -ne 5') -and
    $deployment.Contains('CANDIDATE_CONSOLE_RESOURCE_INVENTORY_DRIFT') -and
    $deployment.Contains('Publish-only mode does not accept replacement content or a baseline snapshot path.') -and
    $deployment.Contains('if (-not ($PublishOnly -or $ReconcilePublishOnly) -and ($hasEnvironmentResource -or $hasHtmlResource))') -and
    $deployment.Contains('$runtimeCandidateConsoleNames') -and
    $deployment.Contains('Get-ChildItem -LiteralPath') -and
    $publishOnlyBlock -and
    -not $publishOnlyBlock.Contains('-Method PATCH') -and
    $publishOnlyBlock.Contains('$definitionEquivalence.IsReconciled') -and
    $publishOnlyBlock.Contains('EFFECTIVE_CONTENT_UNVERIFIED') -and
    $publishOnlyBlock.Contains('$publishResourceIds.Add($resourceId)') -and
    $publishOnlyBlock.Contains('CANDIDATE_CONSOLE_SOURCE_CONTENT_DRIFT:$($resource.Name)') -and
    $publishOnlyBlock.Contains('Stop-PublishOnlyPreflight') -and
    $publishOnlyBlock.Contains('TargetedResourceCount = $resources.Count') -and
    $publishOnlyBlock.Contains('ResourcePatchCount = $script:Counts.PATCH') -and
    $publishOnlyBlock.Contains('ResourcePostCount = 0') -and
    $publishOnlyBlock.Contains('$script:Counts.POST -ne [int]$publishAttempted') -and
    $publishOnlyBlock.Contains('PublishXmlCount = [int]$publishAttempted') -and
    $publishOnlyBlock.Contains('CANDIDATE_CONSOLE_PUBLICATION_OUTCOME_AMBIGUOUS') -and
    $publishOnlyBlock.Contains('CANDIDATE_CONSOLE_FULL_PUBLICATION_SET_RECONCILED') -and
    $publishOnlyBlock.Contains('$script:Journal.PrePublishHashes[$resource.Name] -cne $state.CurrentSha256') -and
    $publishOnlyBlock.Contains('SolutionMembershipFingerprintBefore = $solutionMembershipHashBefore') -and
    $publishOnlyBlock.Contains('$solutionMembershipHashAfter -cne $solutionMembershipHashBefore') -and
    $publishOnlyBlock.Contains('$runtimeCandidateConsoleNamesAfter') -and
    $publishOnlyBlock.Contains('SolutionMembershipUnchanged = $true') -and
    $publishOnlyBlock.Contains('SiteMapPatchCount = 0')) `
    'Inspect and pin the complete Candidate Console set, publish only matching unpublished resources once, then reconcile every hash'
$publishOnlyPostCalls = [regex]::Matches(
    $publishOnlyBlock,
    "Invoke-DataverseRequest -Method POST -Path 'PublishXml'"
)
$hashGateIndex = $publishOnlyBlock.IndexOf('if ($state.CurrentSha256 -cne $expectedHash)')
$publishDispatchIndex = $publishOnlyBlock.IndexOf("Invoke-DataverseRequest -Method POST -Path 'PublishXml'")
Assert-Test ($publishOnlyPostCalls.Count -eq 1 -and
    $hashGateIndex -ge 0 -and $publishDispatchIndex -gt $hashGateIndex -and
    $publishOnlyBlock.Contains('CANDIDATE_CONSOLE_PUBLICATION_OUTCOME_AMBIGUOUS') -and
    $publishOnlyBlock.Contains('AMBIGUOUS_RESPONSE_GET_RECONCILED') -and
    $publishOnlyBlock.Contains('ResourcePostCount = 0') -and
    $publishOnlyBlock.Contains('$script:Counts.POST -ne [int]$publishAttempted')) `
    'Reserve at most one PublishXml after integrity gates and reconcile ambiguous outcomes without retry'
$reconcileAnchor = $deployment.IndexOf('$navMember =')
$reconcileStart = $deployment.IndexOf('    if ($ReconcilePublishOnly) {', $reconcileAnchor)
$reconcileStop = $deployment.IndexOf('    if (-not $Apply -and -not $Continue) {', $reconcileStart)
$reconcileBlock = if ($reconcileStart -ge 0 -and $reconcileStop -gt $reconcileStart) {
    $deployment.Substring($reconcileStart, $reconcileStop - $reconcileStart)
} else { '' }
Assert-Test ($deployment.Contains('[switch]$ReconcilePublishOnly') -and
    $deployment.Contains('Read-only publication reconciliation requires the exact five-resource set and an existing journal.') -and
    $reconcileBlock -and
    -not $reconcileBlock.Contains('Invoke-DataverseRequest -Method POST') -and
    -not $reconcileBlock.Contains('Invoke-DataverseRequest -Method PATCH') -and
    $reconcileBlock.Contains('GET_ONLY') -and
    $reconcileBlock.Contains('Add-Member -NotePropertyName ReadOnlyReconciliation') -and
    $reconcileBlock.Contains('$script:Journal.PrePublishHashes.PSObject.Properties[') -and
    $reconcileBlock.Contains('EFFECTIVE_EVIDENCE_MISSING:$($resource.Name)') -and
    $reconcileBlock.Contains('HASH_MISMATCH:$($resource.Name)') -and
    $reconcileBlock.Contains('GET_RECONCILED_AFTER_AMBIGUOUS_RESPONSE') -and
    $reconcileBlock.Contains('CANDIDATE_CONSOLE_PUBLICATION_OUTCOME_AMBIGUOUS')) `
    'Provide a read-only reconciliation path that never retries the reserved ambiguous publication'
$resourceSelection = $deployment.IndexOf('$resources = @($allResources | Where-Object { $RefreshResourceNames -ccontains $_.Name })')
$publishLabel = $deployment.IndexOf('$publishLabel = "$($resources.Count) exact web resources scoped PublishXml"')
Assert-Test ($deployment.Contains('[string[]]$RefreshResourceNames = @()') -and
    $deployment.Contains('if ($Continue -or (-not $RefreshExisting -and -not $CreateNewResources))') -and
    $deployment.Contains('$RefreshResourceNames.Count -ne 5') -and
    $deployment.Contains('$selectedResourceNames') -and
    $resourceSelection -ge 0 -and $publishLabel -gt $resourceSelection -and
    $deployment.Contains('$publishEntry = @($script:Journal.Dispatches | Where-Object Name -CEQ $publishLabel)[0]') -and
    $deployment.Contains('foreach ($resourceId in $script:Journal.ResourceIds)')) `
    'Require the complete five-resource selection and scope PublishXml to only pending canonical web resources'
Assert-Test ($deployment.Contains('[switch]$CreateNewResources') -and
    $deployment.Contains('New-resource creation is restricted to the two exact Candidate Console configuration resources.') -and
    $deployment.Contains('$environmentConfiguration.environmentId -ine $target.EnvironmentId') -and
    $deployment.Contains('$environmentConfiguration.candidateOperationMode -notin @('''', ''BsoSynthetic'', ''SingleUserDev'')') -and
    $deployment.Contains('$null -ne $environmentConfiguration.PSObject.Properties[''availabilityEnabled'']') -and
    $deployment.Contains('Generated environment files must remain outside the repository.') -and
    $deployment.Contains('[string]$EnvironmentHtmlPath') -and
    $deployment.Contains('Generated HTML differs from the checked-in source except for the verified environment cache token.') -and
    $deployment.Contains('candidate-console-environment.js') -and
    $deployment.Contains('candidate-console-policy.js')) `
    'Restrict creation to the two configuration resources and verify the external DEV configuration before dispatch'
Assert-Test ($deployment.Contains('[switch]$ReleaseNeutralProfile') -and
    $deployment.Contains('Release-neutral refresh is restricted to the existing environment configuration and matching HTML resources.') -and
    $deployment.Contains('if ($ReleaseNeutralProfile -and -not $PublishOnly -and -not $ReconcilePublishOnly)') -and
    $deployment.Contains("if (`$ReleaseNeutralProfile -and -not `$PublishOnly -and -not `$ReconcilePublishOnly -and") -and
    $deployment.Contains('Release-neutral source baseline published/current bytes do not match the accepted baseline.') -and
    $deployment.Contains('-not $_.PublishedMatchesCurrent') -and
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
$deployment.Contains('CurrentContentBase64 = [Convert]::ToBase64String($remoteBytes)') -and
$deployment.Contains('PublishedMatchesCurrent') -and
    $deployment.Contains('CANDIDATE_CONSOLE_SOURCE_BASELINE_UNRECONCILED') -and
    $deployment.Contains('BaselineVersionsMatch = $baselineVersionsMatch')) `
    'Capture exact published and effective resource bytes outside the repository and block on version drift'
Assert-Test ($deployment.Contains('"%24select=webresourceid,name,displayname,webresourcetype,content,componentstate,modifiedon"') -and
    $deployment.Contains('PublishedComponentState = $published.componentstate') -and
    $deployment.Contains('PublishedModifiedOn = $published.modifiedon')) `
    'Select every published baseline property that the StrictMode snapshot reads'
Assert-Test ($deployment.Contains('$publishedMatchesCurrent = $null') -and
    -not $deployment.Contains('$publishedMatchesEffective')) `
    'Initialize the published/current comparison for refreshes without a baseline snapshot'
Assert-Test ($deployment.Contains('CANDIDATE_CONSOLE_CONFIG_RESOURCES_PREFLIGHT_READY') -and
    $deployment.Contains('if (-not $Continue -and -not $CreateNewResources -and -not $RefreshExisting)') -and
    $deployment.Contains('NOT_REQUIRED_EXISTING_NAVIGATION_RECONCILED') -and
    $deployment.Contains('Assert-PublishedWebResourceReadback')) `
    'Create only the selected configuration resources, preserve the sitemap, and reconcile published bytes'
Assert-Test ($deployment.Contains('if (-not $Continue -and -not $CreateNewResources -and -not $RefreshExisting)') -and
    $deployment.Contains('if ($CreateNewResources -or $RefreshExisting)') -and
    $deployment.Contains('PublishXmlScope = "$($resources.Count) exact web resources"') -and
    $deployment.Contains('PublishAllXml = 0') -and
    $deployment.Contains('AutomaticRetries = 0') -and
    -not $deployment.Contains("-Path 'PublishAllXml'") -and
    -not $deployment.Contains('-Path "PublishAllXml"')) `
    'Refresh selected WebResources only, with no app/sitemap publication, global publish, or retry'
Assert-Test ($deployment.Contains('[switch]$DevelopmentSourceAhead') -and
    $deployment.Contains("'os_/bso/candidate-console.html' = 'fdd9fc9ee3fec019b21806e9beb9bc1c5ee21777b47bcfcd8eeac4d827228bcb'") -and
    $deployment.Contains("'os_/bso/candidate-console-policy.js' = '8f9308f512fde32c4059963b3559ca788b766b5895cb46989c0f48a7e983c684'") -and
    $deployment.Contains("'os_/bso/candidate-console.js' = '672292a5acb0011dec256df536f42087c8e5eff1a42a226318fedbfdf5a9bcae'") -and
    $deployment.Contains('Development source-ahead refresh requires the exact reviewed HTML/policy/JavaScript set and matching external DEV configuration.') -and
    $deployment.Contains('[string]::IsNullOrWhiteSpace($EnvironmentConfigurationPath)') -and
    $deployment.Contains('[string]::IsNullOrWhiteSpace($EnvironmentHtmlPath)') -and
    $deployment.Contains('$null -ne $environmentConfiguration.PSObject.Properties[''availabilityEnabled'']') -and
    $deployment.Contains('$RefreshResourceNames.Count -ne $allowedDevelopmentNames.Count') -and
    $deployment.Contains('CANDIDATE_CONSOLE_DEV_SOURCE_AHEAD_PREFLIGHT_READY') -and
    $deployment.Contains('CANDIDATE_CONSOLE_DEV_SOURCE_AHEAD_REFRESHED') -and
    $deployment.Contains('PublishXmlScope = "$($resources.Count) exact web resources"') -and
    $deployment.Contains('SiteMapPatchCount = 0') -and
    $deployment.Contains('AutomaticRetries = 0') -and
    $deployment.Contains('$_.Name -cne ''candidate-console-availability.js''') -and
    -not $deployment.Contains("Invoke-DataverseRequest -Method POST -Path 'PublishAllXml'") -and
    -not $deployment.Contains('PublishXmlCount = 0')) `
    'DEV source-ahead path pins only the reviewed HTML, policy, and JavaScript with scoped publication'
$sourceAheadUnchangedStart = $deployment.IndexOf('$developmentSourceAheadUnchangedNames = @(')
$sourceAheadUnchangedEnd = $deployment.IndexOf(')', $sourceAheadUnchangedStart)
$sourceAheadUnchangedBlock = if ($sourceAheadUnchangedStart -ge 0 -and
    $sourceAheadUnchangedEnd -gt $sourceAheadUnchangedStart) {
    $deployment.Substring($sourceAheadUnchangedStart, $sourceAheadUnchangedEnd - $sourceAheadUnchangedStart)
} else { '' }
Assert-Test ($deployment.Contains('$developmentSourceAheadUnchangedNames = @(') -and
    $sourceAheadUnchangedBlock.Contains("'os_/bso/candidate-console-environment.js'") -and
    -not $sourceAheadUnchangedBlock.Contains("'os_/bso/candidate-console-policy.js'") -and
    $deployment.Contains('Get-ExactWebResourceState') -and
    $deployment.Contains('SelectedForRefresh = $false') -and
    $deployment.Contains('[string]$configurationHash') -and
    $deployment.Contains('unchangedMembershipCount -ne 1') -and
    $deployment.Contains('CANDIDATE_CONSOLE_SOURCE_BASELINE_UNRECONCILED')) `
    'DEV source-ahead preflight proves the unselected live environment configuration before publication'

$hash = (Get-FileHash -LiteralPath $scriptPath -Algorithm SHA256).Hash.ToLowerInvariant()
$version = [regex]::Match($html, 'candidate-console\.js\?v=([0-9a-f]+)')
Assert-Test ($version.Success -and $hash.StartsWith($version.Groups[1].Value)) 'Keep the script cache version tied to its content'
$resourceVersions = @(
    @{ Path = $policyPath; Name = 'candidate-console-policy.js' }
)
foreach ($resource in $resourceVersions) {
    $resourceHash = (Get-FileHash -LiteralPath $resource.Path -Algorithm SHA256).Hash.ToLowerInvariant()
    $resourceVersion = [regex]::Match($html, "$([regex]::Escape($resource.Name))\?v=([0-9a-f]+)")
    Assert-Test ($resourceVersion.Success -and $resourceHash.StartsWith($resourceVersion.Groups[1].Value)) `
        "Keep $($resource.Name) cache version tied to its content"
}
$environmentVersion = [regex]::Match($html, 'candidate-console-environment\.js\?v=([0-9a-f]{12})')
Assert-Test ($environmentVersion.Success -and $configuration.Contains('mode: "UNCONFIGURED"')) `
    'Keep the checked-in disabled environment template separate from the externally bound cache version'

$siteMapPath = Join-Path $root 'solutions\AppModuleSiteMaps\srapp\AppModuleSiteMap.xml'
$siteMapXml = [xml](Get-Content -LiteralPath $siteMapPath -Raw)
$siteMapSubAreas = @($siteMapXml.AppModuleSiteMap.SiteMap.Area.Group.SubArea)
$siteMapTitles = @($siteMapSubAreas | ForEach-Object { $_.Titles.Title.Title })
Assert-Test ($siteMapSubAreas.Count -eq 5 -and
    $siteMapSubAreas[0].Id -ceq 'subarea_bso_candidate_management' -and
    $siteMapSubAreas[0].Url -ceq '$webresource:os_/bso/candidate-console.html' -and
    [string]::Join('|', $siteMapTitles) -ceq 'Candidate Management|TA Directory|Positions|Candidate Sources|Locations') `
    'Open srapp on Candidate Management first while preserving every reference page'

Write-Output "Candidate Console static checks passed: $passed"
