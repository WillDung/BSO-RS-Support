#requires -Version 7.4
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$scriptPath = Join-Path $root 'scripts\Test-BsoRsCandidateCorePhase5A.ps1'
$source = Get-Content -LiteralPath $scriptPath -Raw
$script:Passed = 0

function Assert-Test([bool]$Condition, [string]$Name) {
    if (-not $Condition) { throw "FAIL: $Name" }
    $script:Passed++
}

$tokens = $null
$errors = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile(
    $scriptPath, [ref]$tokens, [ref]$errors
)
Assert-Test ($errors.Count -eq 0) 'Phase 5A runtime runner parses'
Assert-Test ($source -match "ValidateSet\('PlanOnly', 'Apply'\)" -and
    $source -match "EnvironmentName -cne 'VN LMV IT'" -and
    $source -match "https://org14938ec2\.crm4\.dynamics\.com") `
    'Runtime runner is pinned to VN LMV IT'
Assert-Test ($source -match "ExpectedDispatches = 27" -and
    $source -match 'MaximumReads = 180' -and
    $source -match 'DispatchCount -ne \$script:ExpectedDispatches') `
    'Runtime API dispatch and read budgets are fixed'
Assert-Test ($source -match "'os_sr_cact'" -and
    $source -match "-Method POST" -and
    $source -match 'MaximumRetryCount 0' -and
    $source -match 'MaximumRedirection 0' -and
    $source -match 'UNCERTAIN_OUTCOME_NO_RETRY') `
    'Only the Custom API is written and network retries are disabled'
Assert-Test ($source -match 'prvReados_sr_cand' -and
    $source -match 'CORRELATION_CONFLICT' -and
    $source -match 'STALE_EXPECTED_STATUS') `
    'Live privilege, conflicting replay, and stale-status contracts are asserted'
Assert-Test ($source -match 'example\.invalid' -and
    $source -match 'StartsWith\(''\[DEV\]''' -and
    $source -match "filter = 'statecode eq 0'" -and
    $source -match '%24top=5000') `
    'Fixtures use .invalid addresses and active DEV-prefixed references only'
Assert-Test ($source -match 'RecordCall' -and
    $source -match 'ProceedToScheduling' -and
    $source -match 'MarkRound1Scheduled' -and
    $source -match 'RecordPass' -and $source -match 'RecordFail' -and
    $source -match 'RequestReschedule' -and $source -match 'CancelRound1') `
    'The supported Candidate Core workflow is included'
Assert-Test ($source -match "Outcome = 'PHASE_5A_CANDIDATE_CORE_RUNTIME_MATRIX_PASSED'" -and
    $source -match 'OperationReceipts = \$allReceipts.Count' -and
    $source -match "State -eq 'EXPECTED_REJECTION'") `
    'The runner requires durable record reconciliation and journals the outcome'
Assert-Test ($source -notmatch 'ProtectCandidateCore|DIRECT_WRITE_GUARD_REJECTED|pac admin assign-user|PublishAllXml') `
    'Runtime acceptance does not diagnose guards, assign roles, or publish'

Write-Output "PASS: $script:Passed offline Phase 5A runtime-runner assertions; no authentication/network."
