#requires -Version 7.4
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$webRoot = Join-Path $root 'solutions\CandidateConsole\WebResources\os_\bso'
$htmlPath = Join-Path $webRoot 'candidate-console.html'
$scriptPath = Join-Path $webRoot 'candidate-console.js'
$stylePath = Join-Path $webRoot 'candidate-console.css'
$html = Get-Content -LiteralPath $htmlPath -Raw
$script = Get-Content -LiteralPath $scriptPath -Raw
$style = Get-Content -LiteralPath $stylePath -Raw
$passed = 0

function Assert-Test {
    param([bool]$Condition, [string]$Name)
    if (-not $Condition) { throw "FAIL: $Name" }
    $script:passed++
}

Assert-Test ($html.Contains('VN LMV IT — DEV DIRECT WRITE') -and
    $html.Contains('PROTECTCANDIDATECORE DISABLED — NOT PRODUCTION') -and
    $html.Contains('REAL DATA PROHIBITED')) 'Keep prominent DEV safety and synthetic-only warnings'
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
Assert-Test ($script.Contains('candidateName.startsWith("[SYNTHETIC-E2E]")') -and
    $script.Contains('\.invalid')) 'Keep the synthetic name and reserved email write gates'
Assert-Test ($script.Contains('waitingManualScheduling: 100010002') -and
    $script.Contains('current[c.status] !== STATUS.answered') -and
    $script.Contains('[c.status]: STATUS.waitingManualScheduling')) 'Gate the explicit Answered-to-Waiting transition'
Assert-Test ($script.Contains('[history.previous]: STATUS.answered') -and
    $script.Contains('[history.current]: STATUS.waitingManualScheduling')) 'Record the Waiting transition in Status History'
Assert-Test ($html.Contains('id="schedule-round1-button"') -and
    $script.Contains('candidate[TABLES.candidate.status] === STATUS.waitingManualScheduling') -and
    $script.Contains('$("scheduling-panel").hidden = true;')) 'Expose Schedule Round 1 only from Waiting Manual Scheduling and close stale drafts on selection changes'
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
    $script.Contains('Multiple Round 1 schedule rows exist')) 'Show the latest persisted schedule and flag duplicate rows'
Assert-Test ($html.Contains('id="save-schedule"') -and
    $html.Contains('DEV-only persistence. No calendar availability check or calendar booking is performed.') -and
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
    $script.Contains('A Round 1 schedule already exists') -and
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
Assert-Test ($script.Contains('rows.length === 1') -and
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
Assert-Test ($resultFlow.Contains('resultRetryBlockedCandidateId = candidateId') -and
    $resultFlow.Contains('Interview result was persisted, but the Candidate status update failed or is uncertain') -and
    $resultFlow.Contains('Status History creation failed or is uncertain') -and
    -not $resultFlow.Contains('WebApi.deleteRecord')) 'Preserve partial result writes, refresh, warn safely, and never retry or compensate'
Assert-Test ($script.Contains('RecordRound1Pass') -and
    $script.Contains('RecordRound1Fail') -and
    $script.Contains('!canRecordInterviewResult()')) 'Record distinct Pass/Fail history operations and protect against duplicate submission'

$hash = (Get-FileHash -LiteralPath $scriptPath -Algorithm SHA256).Hash.ToLowerInvariant()
$version = [regex]::Match($html, 'candidate-console\.js\?v=([0-9a-f]+)')
Assert-Test ($version.Success -and $hash.StartsWith($version.Groups[1].Value)) 'Keep the script cache version tied to its content'

Write-Output "Candidate Console static checks passed: $passed"
