#requires -Version 7.4
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$runtimePath = Join-Path $root 'scripts\Test-BsoRsCandidateCoreRuntime.ps1'
$runtime = Get-Content -Raw $runtimePath
$pluginPath = Join-Path $root 'solutions\CandidateCore\DataversePlugin.cs'
$plugin = Get-Content -Raw $pluginPath
$operation = Get-Content -Raw (Join-Path $root 'solutions\CandidateCore\Operation.cs')
$script:Passed = 0

function Assert-Test([bool]$Condition, [string]$Name) {
    if (-not $Condition) { throw "FAIL: $Name" }
    $script:Passed++
}

$tokens = $null
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile($runtimePath, [ref]$tokens, [ref]$errors) > $null
Assert-Test ($errors.Count -eq 0) 'Synthetic runtime runner parses'
Assert-Test ($runtime -match "ValidateSet\('GET', 'POST'\)" -and
    $runtime -match "Path -cne 'os_sr_cact'" -and $runtime -match 'MaximumRetryCount = 0' -and
    $runtime -match 'MaximumRedirection = 0' -and $runtime -match 'expectedActionCalls = 21') 'Only bounded Custom API calls with zero retries'
Assert-Test ($runtime -match 'FileMode\]::CreateNew' -and $runtime -match 'phase3d-runtime-' -and
    $runtime -match 'one-shot runtime authorization consumed') 'One-shot local execution lock prevents reruns'
Assert-Test ($runtime -match "CandidateName = '\[SYNTHETIC-E2E\]" -and
    $runtime -match '@example\.invalid' -and $runtime -notmatch '@example\.com') 'Fixture identity is unmistakably synthetic and reserved'
Assert-Test ($runtime -match 'Get-Count -EntitySet' -and
    $runtime -match 'Zero-row safety gate failed' -and
    $runtime.IndexOf('Zero-row safety gate failed') -lt $runtime.IndexOf('Invoke-Action -Body $create')) 'Zero-row check precedes first business API invocation'
Assert-Test ($runtime -match 'CreateCandidate replay' -and $runtime -match 'CreateCandidate conflict' -and
    $runtime -match 'STALE_EXPECTED_STATUS' -and $runtime -match 'UpdateCandidate conflict') 'Replay, conflict, and stale-state checks are wired'
Assert-Test ($runtime -match 'os_sr_cand_cnum' -and $runtime.Contains('CAND-[0-9]{8}')) 'Candidate AutoNumber is checked against the approved format'
Assert-Test ($runtime -match 'SCHEDULER_DEPENDENCY_UNAVAILABLE' -and
    $runtime -match "Action = 'RecordPass'; Expected = 'INVALID_TRANSITION'" -and
    $runtime -match "Action = 'RecordFail'; Expected = 'INVALID_TRANSITION'" -and
    $runtime -match "Action = 'RequestReschedule'; Expected = 'INVALID_TRANSITION'") 'Unimplemented evidence-dependent actions remain fail-closed'
Assert-Test ($runtime -match 'TotalBusinessRecordWrites = 13' -and
    $runtime -match 'RetainedCandidate = \$true' -and $runtime -match 'RecordIdsPersisted = \$false') 'Expected effects are bounded and record IDs are not persisted'
Assert-Test ($runtime -match 'AuditSettingWrites = 0' -and $runtime -match 'PublishXml = 0' -and
    $runtime -notmatch 'Invoke-RuntimeRequest -Method (PUT|PATCH|DELETE)') 'No audit, app, or metadata mutation path exists'
Assert-Test ($runtime -match 'CandidateIdSha256' -and $runtime -match 'ActorIdSha256' -and
    $runtime -match 'PayloadSha256' -and $runtime -notmatch 'CandidateEmail = .*journal') 'Evidence stores hashes, not raw identifiers or candidate fields'
Assert-Test ($plugin -match 'if \(!context\.IsInTransaction \|\| context\.UserId != context\.InitiatingUserId\)' -and
    $plugin -notmatch 'isauditenabled|AUDIT_ACTIVATION_PENDING') 'Server keeps transaction/caller guard without organization-audit blocker'
Assert-Test ($operation -match 'void RequireTransaction\(\)' -and
    $operation -notmatch 'RequireTransactionAndAudit|AUDIT_ACTIVATION_PENDING') 'Engine gate reflects transaction-only runtime requirement'

"PASS: $script:Passed synthetic Phase 3D runtime-runner contract assertions; no authentication/network."
