#requires -Version 7.4
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$runtimePath = Join-Path $root 'scripts\Test-BsoRsCandidateCoreRuntime.ps1'
$runtime = Get-Content -Raw $runtimePath
$pluginPath = Join-Path $root 'solutions\CandidateCore\DataversePlugin.cs'
$plugin = Get-Content -Raw $pluginPath
$operation = Get-Content -Raw (Join-Path $root 'solutions\CandidateCore\Operation.cs')
$operationTests = Get-Content -Raw (Join-Path $root 'tests\CandidateCore\Program.cs')
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
    $runtime -match 'MaximumRedirection = 0' -and $runtime -match 'expectedActionCalls = 8') 'Only bounded Custom API calls with zero retries'
Assert-Test ($runtime -match 'FileMode\]::CreateNew' -and $runtime -match 'phase3d-r-runtime-' -and
    $runtime -match 'phase3d-r4b-owner-authorized-package-runtime' -and
    $runtime -match 'one-shot runtime authorization consumed') 'Authorization-specific one-shot lock preserves prior consumed lock'
Assert-Test ($runtime -match "\`$name = '\[SYNTHETIC-E2E\]" -and
    $runtime -match '\[SYNTHETIC-E2E\] Candidate Core Acceptance' -and
    $runtime -match '@example\.invalid' -and $runtime -notmatch '@example\.com') 'Fixture identity is unmistakably synthetic and reserved'
Assert-Test ($runtime -match 'Get-Count -EntitySet' -and
    $runtime -match 'Zero-row safety gate failed' -and
    $runtime.IndexOf('Zero-row safety gate failed') -lt $runtime.IndexOf('Invoke-Action -Body $create')) 'Zero-row check precedes first business API invocation'
Assert-Test ($runtime -match 'CreateCandidate' -and $runtime -match 'STALE_EXPECTED_STATUS' -and
    $runtime -match 'RecordCall no-answer replay' -and
    $runtime -match 'RecordCall no-answer conflict') 'Replay, conflict, and stale-state checks are wired'
Assert-Test ($runtime -match 'os_sr_cand_cnum' -and $runtime.Contains('CAND-[0-9]{8}')) 'Candidate AutoNumber is checked against the approved format'
Assert-Test ($runtime -match 'SCHEDULER_DEPENDENCY_UNAVAILABLE' -and
    $runtime -match "Action = 'RecordPass'; LiveResult = 'NOT_APPLICABLE_CURRENT_STATE'" -and
    $runtime -match "Action = 'RecordFail'; LiveResult = 'NOT_APPLICABLE_CURRENT_STATE'" -and
    $runtime -match "Action = 'RequestReschedule'; LiveResult = 'NOT_APPLICABLE_CURRENT_STATE'" -and
    $runtime -notmatch 'Invoke-Action -Body \$body -ExpectedFailure \$deferred') 'Deferred evidence actions stay fail-closed without impossible-state live calls'
Assert-Test ($runtime -notmatch 'UpdateCandidate|RecordCall answered replay|RecordCall answered conflict' -and
    $runtime -match 'expectedCounts\.Receipts = 2' -and $runtime -match 'expectedCounts\.Receipts = 3' -and
    $runtime -match 'expectedCounts\.Receipts = 4' -and $runtime -match "'UNEXPECTED_INPUT'") 'Eight-call matrix has exact receipt counts and captures unexpected-input rejection'
Assert-Test ($runtime -match 'TotalBusinessRecordWrites = 9' -and
    $runtime -match 'RetainedCandidate = \$true' -and $runtime -match 'RecordIdsPersisted = \$false') 'Expected effects are bounded and record IDs are not persisted'
Assert-Test ($runtime -match 'CandidateWrites = 1; CallLogWrites = 2; StatusHistoryWrites = 2; ReceiptWrites = 4' -and
    $runtime -match 'MaximumApiDispatches = \$expectedActionCalls') 'Runtime result matches the nine-row effect budget'
Assert-Test ($runtime -match 'AuditSettingWrites = 0' -and $runtime -match 'PublishXml = 0' -and
    $runtime -notmatch 'Invoke-RuntimeRequest -Method (PUT|PATCH|DELETE)') 'No audit, app, or metadata mutation path exists'
Assert-Test ($runtime -match 'ExpectedHandlerPackageUniqueName' -and
    $runtime -match 'Assert-PackageBackedHandler' -and
    $runtime -match 'Runtime Apply requires the reconciled package-backed handler identity') 'Runtime apply requires the package-backed handler chain'
Assert-Test ($runtime -match 'CandidateIdSha256' -and $runtime -match 'ActorIdSha256' -and
    $runtime -match 'PayloadSha256' -and $runtime -notmatch 'CandidateEmail = .*journal') 'Evidence stores hashes, not raw identifiers or candidate fields'
Assert-Test ($plugin -match 'if \(!context\.IsInTransaction \|\| context\.UserId != context\.InitiatingUserId\)' -and
    $plugin -notmatch 'isauditenabled|AUDIT_ACTIVATION_PENDING') 'Server keeps transaction/caller guard without organization-audit blocker'
Assert-Test ($operation -match 'void RequireTransaction\(\)' -and
    $operation -notmatch 'RequireTransactionAndAudit|AUDIT_ACTIVATION_PENDING') 'Engine gate reflects transaction-only runtime requirement'
$engineTests = Get-Content -Raw (Join-Path $root 'tests\CandidateCore\Program.cs')
Assert-Test ($engineTests -match 'SCHEDULER_DEPENDENCY_UNAVAILABLE' -and
    $engineTests -match 'RESULT_OR_CANCELLATION_DEPENDENCY_UNAVAILABLE' -and
    $engineTests -match 'Transition\(action, ActionRequest.Waiting, null\), "INVALID_TRANSITION"') 'Offline suite verifies evidence fail-closed behavior at scheduled and current states'
Assert-Test ($operation -match 'Action == "CreateCandidate" && input\.TryGetValue\("CandidateId", out var createTarget\)' -and
    $operationTests -match 'Optional null CandidateId accepted on create' -and
    $operationTests -match 'Optional empty CandidateId accepted on create' -and
    $operationTests -match 'Request\(createWithNullCandidateId\), "UNEXPECTED_INPUT"' -and
    $operationTests -match 'INVALID_CANDIDATEID' -and
    $operationTests -match 'Invalid CreateCandidate input has no business mutation' -and
    $operationTests -match 'Organization audit inactive permits valid Candidate creation') 'CreateCandidate optional target handling and safety regressions are covered'

"PASS: $script:Passed synthetic Phase 3D runtime-runner contract assertions; no authentication/network."
