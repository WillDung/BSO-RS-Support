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
    $html.Contains('PROTECTCANDIDATECORE DISABLED — NOT PRODUCTION')) 'Keep both prominent DEV safety banners'
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
    $html.Contains('id="scheduling-location"') -and
    $html.Contains('id="scheduling-notes"')) 'Provide the compact Round 1 scheduling draft fields'
Assert-Test ($html.Contains('id="save-schedule"') -and
    $html.Contains('type="submit" data-action disabled') -and
    $html.Contains('SCHEDULING_STORAGE_NOT_PROVISIONED') -and
    $script.Contains('SCHEDULING_STORAGE_NOT_PROVISIONED. No schedule was saved') -and
    $script.Contains('button.id === "save-schedule"')) 'Keep scheduling persistence and status advancement fail-closed without storage'
Assert-Test ($script.Contains('loadLookupOptions("os_sr_ta", "scheduling-ta"') -and
    $script.Contains('loadLookupOptions("os_sr_loc", "scheduling-location"') -and
    $script.Contains('label.startsWith("[DEV]")')) 'Load only active synthetic TA and Location lookup choices'
Assert-Test (-not $script.Contains('[c.status]: STATUS.round1Scheduled')) 'Do not advance Candidate status without durable schedule evidence'
Assert-Test (-not $html.Contains('id="candidate-status"') -and
    -not $html.Contains('<dialog') -and
    -not $html.Contains('call-dialog')) 'Expose no arbitrary status editor or call debug dialog'

$hash = (Get-FileHash -LiteralPath $scriptPath -Algorithm SHA256).Hash.ToLowerInvariant()
$version = [regex]::Match($html, 'candidate-console\.js\?v=([0-9a-f]+)')
Assert-Test ($version.Success -and $hash.StartsWith($version.Groups[1].Value)) 'Keep the script cache version tied to its content'

Write-Output "Candidate Console static checks passed: $passed"
