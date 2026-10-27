#requires -Version 7.4
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$runtimePath = Join-Path $root 'scripts\Test-BsoRsCandidateCoreRuntime.ps1'
$sdkTestPath = Join-Path $root 'tests\CandidateCoreSdk\Program.cs'
$sdkProjectPath = Join-Path $root 'tests\CandidateCoreSdk\CandidateCoreSdk.Tests.csproj'
$runtime = Get-Content -Raw $runtimePath
$sdkTests = Get-Content -Raw $sdkTestPath
$sdkProject = Get-Content -Raw $sdkProjectPath
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
    $runtime -match 'phase3d-r4m-owner-authorized-marker-propagation-runtime' -and
    $runtime -notmatch 'phase3d-r4k-owner-authorized-package-runtime' -and
    $runtime -notmatch 'phase3d-r4j-owner-authorized-package-runtime' -and
    $runtime -notmatch 'phase3d-r4i-owner-authorized-package-runtime' -and
    $runtime -notmatch 'phase3d-r4g-owner-authorized-package-runtime' -and
    $runtime -notmatch 'phase3d-r4f-owner-authorized-package-runtime' -and
    $runtime -notmatch 'phase3d-r4e-owner-authorized-package-runtime' -and
    $runtime -notmatch 'phase3d-r4d-owner-authorized-package-runtime' -and
    $runtime -match 'one-shot runtime authorization consumed') 'R4L has a distinct one-shot lock from all prior consumed authorizations'
Assert-Test ($runtime -match "\`$name = '\[SYNTHETIC-E2E\]" -and
    $runtime -match '\[SYNTHETIC-E2E\] Candidate Core Acceptance' -and
    $runtime -match '@example\.invalid' -and $runtime -notmatch '@example\.com') 'Fixture identity is unmistakably synthetic and reserved'
$createRequest = [regex]::Match($runtime, '(?s)\$create = \[ordered\]@\{(?<body>.*?)\n\s*\}')
Assert-Test ($createRequest.Success -and
    $createRequest.Groups['body'].Value -match 'ActionType = ''CreateCandidate''' -and
    $createRequest.Groups['body'].Value -match 'CorrelationId' -and
    $createRequest.Groups['body'].Value -match 'CandidateName' -and
    $createRequest.Groups['body'].Value -match 'CandidateEmail' -and
    $createRequest.Groups['body'].Value -notmatch 'CandidateId|ExpectedStatus|PositionId|CandidateSourceId') `
    'CreateCandidate request builder omits optional Guid inputs'
Assert-Test ($sdkProject -match 'CandidateCorePackage\\CandidateCore\.Package\.csproj' -and
    $sdkProject -notmatch 'solutions\\CandidateCore\\CandidateCore\.csproj') `
    'SDK adapter harness references the unsigned package source, not the legacy signed project'
Assert-Test ($sdkTests -match 'normalizes .* absent-equivalent to no lookup' -and
    $sdkTests -match 'preserves valid .* reference' -and
    $sdkTests -match 'rejected before any create' -and
    $sdkTests -match 'accepts null CandidateId' -and
    $sdkTests -match 'accepts empty CandidateId' -and
    $sdkTests -match 'does not parse its non-applicable CandidateId input' -and
    $sdkTests -match 'minimalCreate\.Input\.Count == 5 && saturatedCreate\.Input\.Count == 13' -and
    $sdkTests -match 'saturated CreateCandidate fingerprint equals its minimal applicable-input fingerprint' -and
    $sdkTests -match 'UpdateCandidate accepts matching ExpectedStatus' -and
    $sdkTests -match 'UpdateCandidate rejects stale ExpectedStatus') `
    'SDK adapter tests cover operation projection, saturated CreateCandidate inputs, optional GUIDs, and existing-record validation'
Assert-Test ($runtime -match 'Get-Count -EntitySet' -and
    $runtime -match 'Zero-row safety gate failed' -and
    $runtime.IndexOf('Zero-row safety gate failed') -lt $runtime.IndexOf('Invoke-Action -Body $create')) 'Zero-row check precedes first business API invocation'
Assert-Test ($runtime -match 'UNEXPECTED_INPUT:\(SDK_ADAPTER\|ACTION_REQUEST\)' -and
    $runtime -match 'return \$unexpectedInput\.Value') 'Runtime parser preserves sanitized unexpected-input origin and parameter category'
Assert-Test ($runtime -match 'DATAVERSE_OPERATION_REJECTED:\(CC_\[A-Z_\]\+\):0x' -and
    $runtime -match 'CANDIDATE_CORE_FAILURE:\(CC_\[A-Z_\]\+\)' -and
    $runtime -match 'DIRECT_WRITE_GUARD_REJECTED:\(CANDIDATE_CREATE') 'Runtime parser preserves safe service stage and guard categories'
Assert-Test ($runtime -match 'VerifiedAncestorApply' -and
    $runtime -match 'phase3d-owner-authorized-verified-ancestor-runtime' -and
    $runtime -match 'TRACE_SETTING_BASELINE_DRIFT' -and
    $runtime -match 'Active Candidate Core Profiler wrapper blocks acceptance' -and
    $runtime -match 'CreateCandidate receipt did not reconcile before the runtime matrix') `
    'Verified-ancestor authorization is distinct, trace-off gated and reconciles creation before the matrix'
$runtimeAst = [System.Management.Automation.Language.Parser]::ParseFile($runtimePath, [ref]$tokens, [ref]$errors)
$parser = @($runtimeAst.EndBlock.Statements | Where-Object {
    $_ -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $_.Name -ceq 'Get-RuntimeErrorCode'
})[0]
. ([scriptblock]::Create($parser.Extent.Text))
$safeGuard = 'DIRECT_WRITE_GUARD_REJECTED:UNSUPPORTED_GUARD_REGISTRATION:CC_CREATE_CANDIDATE:0x80040265'
Assert-Test ((Get-RuntimeErrorCode "HTTP 400; $safeGuard") -ceq $safeGuard) `
    'Exact live unsupported-registration category is retained without fault text'
$registrationMismatch = 'DIRECT_WRITE_GUARD_REJECTED:GUARD_REGISTRATION_CONTEXT_MISMATCH:CC_CREATE_CANDIDATE:0x80040265'
Assert-Test ((Get-RuntimeErrorCode "HTTP 400; $registrationMismatch") -ceq $registrationMismatch) `
    'Registration/runtime consistency rejection is retained without raw values'
Assert-Test ($runtime -match 'R4OWriteContextApply' -and
    $runtime -match 'phase3d-r4o-owner-authorized-write-context-runtime') `
    'R4O continuation cannot reuse consumed marker or verified-ancestor runtime locks'
Assert-Test ($runtime -match 'R4OServerRegistrationApply' -and
    $runtime -match 'phase3d-r4o-server-registration-classifier-runtime') `
    'Registration-backed classifier uses a distinct R4O one-shot authorization'
Assert-Test ($runtime -match 'function Get-GuardRegistrationInventory' -and
    $runtime -match 'function Get-RegisteredWriteCode' -and
    $runtime -match 'GUARD_REGISTRATION_INVENTORY_UNRESOLVED' -and
    $runtime -match 'ResolvedCount = \$rows.Count' -and
    $runtime -match 'Create\|os_sr_cand.*CANDIDATE_CREATE' -and
    $runtime -match 'sdkmessagefilterid' -and
    $runtime -match 'PackageId = \$packageId\.ToLowerInvariant\(\)' -and
    $runtime -match 'PackageModifiedOn = \[string\]\$package\.modifiedon') `
    'Live preflight derives every canonical write from SDK message/filter registration metadata'
Assert-Test ($plugin -match 'ResolveGuardRegistration' -and
    $plugin -match 'context\.OwningExtension' -and
    $plugin -match 'RegisteredWriteCode\(messageName, entityName\)' -and
    $plugin -match 'UNSUPPORTED_GUARD_REGISTRATION' -and
    $plugin -match 'GUARD_REGISTRATION_CONTEXT_MISMATCH' -and
    $plugin -notmatch 'OTHER_PROTECTED_WRITE|SafeOperation\(') `
    'Protected write classification uses server-owned registration, not runtime shape inference'
Assert-Test ($runtime -match 'CreateCandidate' -and $runtime -match 'STALE_EXPECTED_STATUS' -and
    $runtime -match 'RecordCall no-answer replay' -and
    $runtime -match 'RecordCall no-answer conflict' -and
    $runtime.IndexOf('$stale = [ordered]@{') -gt $runtime.IndexOf("ActionType = 'ProceedToScheduling'") -and
    $runtime -match 'Assert-NoEffect \x27Stale-state rejection\x27 100010002') 'Replay, conflict, and post-transition stale-state checks are wired'
Assert-Test ($runtime -notmatch 'EXPECTED_STATUS_NOT_APPLICABLE' -and
    $runtime -match "'CreateCandidate' \{ 'CREATECANDIDATE_RUNTIME_FAILURE' \}" -and
    $operation -match 'if \(Action != "CreateCandidate"\)' -and
    $operation -match 'Action == "CreateCandidate" && \(pair.Key == "ExpectedStatus" \|\| pair.Key == "CandidateId"\)') 'CreateCandidate ignores non-applicable state inputs while retaining existing-record runtime validation'
Assert-Test ($operationTests -match 'ignores ExpectedStatus value and excludes it from the fingerprint' -and
    $operationTests -match 'arbitrary ExpectedStatus representations' -and
    $operationTests -match 'non-integer ExpectedStatus wrapper values') 'Offline tests cover default, valid, arbitrary, and wrapped CreateCandidate ExpectedStatus values'
Assert-Test ($runtime -match 'os_sr_cand_cnum' -and $runtime.Contains('CAND-[0-9]{8}')) 'Candidate AutoNumber is checked against the approved format'
Assert-Test ($runtime -match 'SCHEDULER_DEPENDENCY_UNAVAILABLE' -and
    $runtime -match "Action = 'MarkRound1Scheduled'; LiveResult = 'VERIFIED_FAIL_CLOSED_LIVE'" -and
    $runtime -match "Action = 'RecordPass'; LiveResult = 'NOT_APPLICABLE_CURRENT_STATE'" -and
    $runtime -match "Action = 'RecordFail'; LiveResult = 'NOT_APPLICABLE_CURRENT_STATE'" -and
    $runtime -match "Action = 'RequestReschedule'; LiveResult = 'NOT_APPLICABLE_CURRENT_STATE'" -and
    $runtime -notmatch 'Invoke-Action -Body \$body -ExpectedFailure \$deferred') 'Scheduling guard is verified live and impossible-state actions remain explicitly deferred'
Assert-Test ($runtime -notmatch "ActionType = 'UpdateCandidate'|RecordCall answered replay|RecordCall answered conflict" -and
    $runtime -match 'expectedCounts\.Receipts = 2' -and $runtime -match 'expectedCounts\.Receipts = 3' -and
    $runtime -match 'expectedCounts\.Receipts = 4' -and
    $runtime -match 'os_sr_oprc_corid.*Count -ne 4' -and
    $runtime -match "'UNEXPECTED_INPUT'") 'Eight-call matrix has exact receipt cardinality and captures unexpected-input rejection'
Assert-Test ($runtime -match 'TotalBusinessRecordWrites = 9' -and
    $runtime -match 'RetainedCandidate = \$true' -and $runtime -match 'RecordIdsPersisted = \$false') 'Expected effects are bounded and record IDs are not persisted'
Assert-Test ($runtime -match 'CandidateWrites = 1; CallLogWrites = 2; StatusHistoryWrites = 2; ReceiptWrites = 4' -and
    $runtime -match 'MaximumApiDispatches = \$expectedActionCalls') 'Runtime result matches the nine-row effect budget'
Assert-Test ($runtime -match 'AuditSettingWrites = 0' -and $runtime -match 'PublishXml = 0' -and
    $runtime -notmatch 'Invoke-RuntimeRequest -Method (PUT|PATCH|DELETE)') 'No audit, app, or metadata mutation path exists'
Assert-Test ($runtime -match 'ExpectedHandlerPackageUniqueName' -and
    $runtime -match 'Assert-PackageBackedHandler' -and
    $runtime -match 'RequirePackageGuardSteps' -and
    $runtime -match 'Assert-PackageGuardSteps' -and
    $runtime -match 'Candidate Core guard steps are not all mapped to the package-backed guard type' -and
    $runtime -match 'Runtime Apply requires the reconciled package-backed handler identity' -and
    $runtime -match 'Runtime package assembly does not contain exactly the approved handler and guard types' -and
    $runtime -match 'PackageCount = \$packagesByName.Count' -and
    $runtime -match 'Runtime Custom API contract or GUID logical-entity metadata differs from the approved contract' -and
    $runtime -match 'customapirequestparameters' -and $runtime -match 'customapiresponseproperties' -and
    $runtime -match 'RequestParameters = @\(\$inputs') 'Runtime preflight reconciles package types and the complete live Custom API contract'
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
    $operationTests -match 'Request\(createWithNullCandidateId\), "UNEXPECTED_INPUT:ACTION_REQUEST:CandidateId"' -and
    $operationTests -match 'INVALID_CANDIDATEID' -and
    $operationTests -match 'Invalid CreateCandidate input has no business mutation' -and
    $operationTests -match 'Organization audit inactive permits valid Candidate creation') 'CreateCandidate optional target handling and safety regressions are covered'
Assert-Test ($runtime -match 'function Assert-NoEffect \{\s*param\(\[string\]\$Checkpoint, \[int\]\$ExpectedStatus\)' -and
    $runtime -notmatch 'script:expectedStatus' -and
    $runtime -match 'SchedulingEvidenceChecks = \$schedulingEvidenceChecks') 'No-effect checks receive explicit state and scheduling evidence is reported'

"PASS: $script:Passed synthetic Phase 3D runtime-runner contract assertions; no authentication/network."
