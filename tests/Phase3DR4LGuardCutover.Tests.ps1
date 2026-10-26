#requires -Version 7.4
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$guardPath = Join-Path $root 'scripts\Cutover-BsoRsCandidateCoreGuards.ps1'
$runtimePath = Join-Path $root 'scripts\Test-BsoRsCandidateCoreRuntime.ps1'
$guard = Get-Content -LiteralPath $guardPath -Raw
$runtime = Get-Content -LiteralPath $runtimePath -Raw
$script:Passed = 0

function Assert-Test([bool]$Condition, [string]$Name) {
    if (-not $Condition) { throw "FAIL: $Name" }
    $script:Passed++
}

foreach ($path in @($guardPath, $runtimePath)) {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors) > $null
    Assert-Test ($errors.Count -eq 0) "PowerShell parses: $(Split-Path $path -Leaf)"
}

Assert-Test ($guard -match "ValidateSet\('Preflight', 'Apply', 'Continue', 'Reconcile', 'Rollback'\)" -and
    $guard.Contains('[string]$Mode = ''Preflight''') -and
    $guard -match "EnvironmentName -cne 'VN LMV IT'" -and
    $guard -match '\[Uri\]\$OrganizationUrl' -and
    $guard -match 'Assert-PacIdentity') `
    'Guard migration defaults to read-only preflight and pins the owner-approved environment'
Assert-Test ($guard -match "ValidateSet\('GET', 'PATCH'\)" -and
    $guard -match 'MaximumRetryCount = 0' -and $guard -match 'MaximumRedirection = 0' -and
    $guard -match 'Only a journaled SDK message processing step EventHandler PATCH is permitted' -and
    $guard -match "Body.Count -ne 1" -and
    $guard -match 'sdkmessageprocessingsteps\\\(') `
    'Only one-shot, no-retry SDK step EventHandler PATCHes are supported'
Assert-Test ($guard -match "FileMode\]::CreateNew" -and
    $guard -match 'DISPATCH_RESERVED' -and
    $guard -match 'UNCERTAIN_WRITE_OUTCOME' -and
    $guard -match 'GET_RECONCILED' -and
    $guard -match 'RollbackMapSha256') `
    'Dispatch reservation, reconciliation, and durable rollback-map pins are enforced'
Assert-Test ($guard -match "Mode -ceq 'Continue'" -and
    $guard -match 'ExpectedPriorDispatchSha256' -and
    $guard -match 'R4L_GUARD_STEP_CUTOVER_CONTINUATION' -and
    $guard -match 'RECONCILIATION_FAILED' -and
    $guard -match 'plannedEntries.Count -ne \(\[int\]\$plan.StepCount - 1\)' -and
    $guard -match 'Fresh topology does not match the one completed step and untouched continuation baseline') `
    'Continuation is pinned to one exact reconciled prior step and cannot redispatch it'
Assert-Test ($guard.Contains('function Get-ContinuationProgress') -and
    $guard.Contains('GUARD_STEP_DISPATCH_PROGRESS_RECONCILED') -and
    $guard.Contains('Fresh live handler assignment differs from per-step dispatch evidence.') -and
    $guard.Contains('Counts.PATCH -ne $priorGet.Count') -and
    $guard.Contains('ReservedButUndispatchedGuardSteps = $progress.ReservedButUndispatchedGuardSteps') -and
    $guard.Contains('Pending continuation step count differs from the journal-aware live reconciliation.')) `
    'Journal-aware reconciliation proves each prior handler and excludes reserved-but-unsent entries from retries'
Assert-Test ($guard.Contains('ExpectedConfigurationSha256 = $_.ConfigurationSha256') -and
    $guard.Contains('ExpectedConfigurationSha256 = $planned.ConfigurationSha256') -and
    -not $guard.Contains('ExpectedConfigurationSha256 = [string]$_.ConfigurationSha256')) `
    'Nullable unsecure-configuration fingerprints remain null in dispatch journals'
Assert-Test ($guard -match "pluginpackages\?" -and
    $guard -match 'os_sr_cact\.ApplyCandidateAction' -and
    $guard -match 'os_sr_cact\.ProtectCandidateCore' -and
    $guard -match 'customapis\?' -and
    $guard -match 'CreateCandidateApiHandlerTypeId' -and
    $guard -match 'assert-RuntimePreflight' -and
    $guard -match 'FreshZeroRowCounts') `
    'Preflight reconciles existing package types, Custom API handler, and zero-row runtime gate'
Assert-Test ($guard -match 'Get-GuardStepSnapshot' -and
    $guard -match 'ProtectedPropertiesSha256' -and
    $guard -match 'ConfigurationSha256' -and
    $guard -match 'SecureConfigurationId' -and
    $guard -match 'SolutionMemberships' -and
    $guard -match 'READ_AFTER_UNCERTAIN_WRITE' -and
    $guard -notmatch 'sdkmessageprocessingstepsecureconfigs\(') `
    'Protected step properties and secure-config relationship are retained without reading secure config contents'
Assert-Test ($guard -match 'current approved message/table coverage' -and
    $guard -match 'primaryobjecttypecode' -and
    $guard -match 'iscustomprocessingstepallowed' -and
    $guard -match 'Required direct-write guard hook unavailable' -and
    $guard -match 'Project Solution membership') `
    'Guard step inventory and project Solution membership must match the approved coverage'
Assert-Test ($guard -match 'Not all Candidate Core guard steps are package-backed after cutover' -and
    $guard -match 'GUARD_STEP_CUTOVER_ROLLED_BACK' -and
    $guard -match 'Prior rollback attempt is unresolved; no rollback PATCH may be repeated' -and
    $guard -match 'AutomaticRetries = 0') `
    'Post-cutover verification and exact non-repeating rollback are enforced'
Assert-Test ($runtime -match 'phase3d-r4l-owner-authorized-guard-cutover-runtime' -and
    $runtime -match 'RequirePackageGuardSteps' -and
    $runtime -match 'ExpectedGuardStepCount' -and
    $runtime -match 'Assert-PackageGuardSteps' -and
    $runtime -match 'Candidate Core guard steps are not all mapped to the package-backed guard type') `
    'R4L runtime authorization is distinct and runtime apply can require exact package guard topology'
Assert-Test ($guard -notmatch "Invoke-GuardRequest -Method '(POST|PUT|DELETE)'|ValidateSet\([^)]*(POST|PUT|DELETE)" -and
    $guard -notmatch 'PublishXml|pluginpackages\([^)]+\).*PATCH|customapis\([^)]+\).*PATCH') `
    'Guard migration has no package, API, schema, security, or publication write path'

"PASS: $script:Passed Phase 3D-R4L guard-cutover contract assertions; no authentication/network."
