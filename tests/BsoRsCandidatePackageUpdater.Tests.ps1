#requires -Version 7.4
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Split-Path $PSScriptRoot -Parent
$updaterPath = Join-Path $root 'scripts\Update-BsoRsCandidatePluginPackage.ps1'
$manifest = Get-Content -LiteralPath (Join-Path $root 'docs\RELEASE_INPUT_MANIFEST.json') -Raw | ConvertFrom-Json
$packagePath = Join-Path $root 'solutions\pluginpackages\os_sr_cact_pkg\package\os_sr_cact_pkg.nupkg'
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) "bso-package-updater-tests-$([Guid]::NewGuid().ToString('N'))"
$passed = 0

function Assert-Test {
    param([Parameter(Mandatory)][bool]$Condition, [Parameter(Mandatory)][string]$Name)
    if (-not $Condition) { throw "FAIL: $Name" }
    $script:passed++
}

function Get-TestSha256 {
    param([Parameter(Mandatory)][string]$Value)
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData(
        [Text.Encoding]::UTF8.GetBytes($Value.ToLowerInvariant())
    )).ToLowerInvariant()
}

$planJournal = Join-Path $temporaryRoot 'plan-only-journal.json'
try {
. $updaterPath -Mode Plan -TargetProfile TEST `
    -OrganizationUrl 'https://test.invalid' `
    -ExpectedEnvironmentId '11111111-1111-4111-8111-111111111111' `
    -ExpectedOrganizationId '22222222-2222-4222-8222-222222222222' `
    -ArtifactPath $packagePath `
    -ExpectedPackageSha256 $manifest.candidateCore.packageSha256 `
    -ExpectedPackageUniqueName $manifest.candidateCore.packageUniqueName `
    -ExpectedHandlerTypeName $manifest.candidateCore.customApiHandlerTypeName `
    -JournalPath $planJournal | Out-Null

$plan = & $updaterPath -Mode Plan -TargetProfile TEST `
    -OrganizationUrl 'https://test.invalid' `
    -ExpectedEnvironmentId '11111111-1111-4111-8111-111111111111' `
    -ExpectedOrganizationId '22222222-2222-4222-8222-222222222222' `
    -ArtifactPath $packagePath `
    -ExpectedPackageSha256 $manifest.candidateCore.packageSha256 `
    -ExpectedPackageUniqueName $manifest.candidateCore.packageUniqueName `
    -ExpectedHandlerTypeName $manifest.candidateCore.customApiHandlerTypeName `
    -JournalPath $planJournal
$packageHash = (Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash.ToLowerInvariant()
Assert-Test ($plan.Result -ceq 'PACKAGE_UPDATE_PLAN_READY_NOT_DISPATCHED' -and
    $plan.PackageSha256 -ceq $packageHash -and $plan.NetworkOperations -eq 0 -and
    $plan.MaximumDispatchCount -eq 1 -and $plan.AutomaticRetries -eq 0 -and
    -not $plan.JournalWritten -and -not (Test-Path -LiteralPath $planJournal)) `
    'Plan validates the real pinned package without network or journal writes'

$badHash = & $updaterPath -Mode Plan -TargetProfile TEST `
    -OrganizationUrl 'https://test.invalid' `
    -ExpectedEnvironmentId '11111111-1111-4111-8111-111111111111' `
    -ExpectedOrganizationId '22222222-2222-4222-8222-222222222222' `
    -ArtifactPath $packagePath `
    -ExpectedPackageSha256 ('0' * 64) `
    -ExpectedPackageUniqueName $manifest.candidateCore.packageUniqueName `
    -ExpectedHandlerTypeName $manifest.candidateCore.customApiHandlerTypeName `
    -JournalPath $planJournal
Assert-Test ($badHash.Result -ceq 'DEPLOYMENT_NOT_DISPATCHED' -and
    $badHash.FailureCode -ceq 'PACKAGE_ARTIFACT_VALIDATION_FAILED' -and
    $badHash.NetworkOperations -eq 0) 'Artifact hash mismatch fails closed before dispatch'

$argumentPath = Join-Path $temporaryRoot 'cache with spaces\os_sr_cact_pkg.nupkg'
$arguments = New-PacPluginPushArguments -NormalizedOrganizationUrl 'https://test.invalid' `
    -ExistingPackageId '33333333-3333-4333-8333-333333333333' -PackageFile $argumentPath
Assert-Test ($arguments.Count -eq 12 -and $arguments[0] -ceq 'plugin' -and
    $arguments[1] -ceq 'push' -and $arguments[2] -ceq '--environment' -and
    $arguments[3] -ceq 'https://test.invalid' -and $arguments[4] -ceq '--pluginId' -and
    $arguments[6] -ceq '--pluginFile' -and $arguments[7] -ceq [IO.Path]::GetFullPath($argumentPath) -and
    $arguments[8] -ceq '--type' -and $arguments[9] -ceq 'Nuget' -and
    $arguments[10] -ceq '--configuration' -and $arguments[11] -ceq 'Release') `
    'PAC arguments remain separate values when the artifact path contains spaces'

$packageId = '33333333-3333-4333-8333-333333333333'
$packageRow = [pscustomobject]@{
    uniquename = 'os_sr_cact_pkg'
    name = 'os_sr_cact_pkg'
    version = '1.0.0'
    pluginpackageid = $packageId
}
Assert-Test ((Resolve-PackageMatch -Rows @($packageRow) -UniqueName 'os_sr_cact_pkg').pluginpackageid -ceq $packageId) `
    'Package lookup accepts exactly one matching existing record'
$ambiguousPackageResult = $null
try {
    Resolve-PackageMatch -Rows @($packageRow, $packageRow) -UniqueName 'os_sr_cact_pkg' | Out-Null
} catch { $ambiguousPackageResult = $_.Exception.Message }
Assert-Test ($ambiguousPackageResult -ceq 'PACKAGE_IDENTITY_AMBIGUOUS') `
    'Package lookup rejects duplicate existing records'

Assert-Test ((Get-PacPushClassification -ProcessStarted $false -ExitCode -1 `
    -StandardOutput '' -StandardError '') -ceq 'NOT_DISPATCHED') `
    'Unstarted PAC process is classified as not dispatched'
Assert-Test ((Get-PacPushClassification -ProcessStarted $true -ExitCode 0 `
    -StandardOutput 'Plugin package updated successfully' -StandardError '') -ceq 'PAC_SUCCESS_REPORTED') `
    'PAC success requires a successful exit and package success output'
Assert-Test ((Get-PacPushClassification -ProcessStarted $true -ExitCode 2 `
    -StandardOutput '' -StandardError 'Error: unknown command') -ceq 'PAC_CLEAR_COMMAND_REJECTION') `
    'Clear PAC command rejection is not treated as an ambiguous update'
Assert-Test ((Get-PacPushClassification -ProcessStarted $true -ExitCode 0 `
    -StandardOutput '' -StandardError '') -ceq 'PAC_RESULT_AMBIGUOUS') `
    'Uninformative PAC success remains ambiguous'

$before = [pscustomobject]@{
    PackageId = $packageId
    PackageIdFingerprint = Get-TestSha256 $packageId
    PackageCount = 4
    AssemblyId = '44444444-4444-4444-8444-444444444444'
    HandlerTypeId = '55555555-5555-4555-8555-555555555555'
    LegacyAssemblyId = '66666666-6666-4666-8666-666666666666'
    ApiMetadataSha256 = 'a' * 64
    LegacyAssemblySha256 = 'b' * 64
}
$beforeJournal = [ordered]@{
    packageRecordIdentitySha256 = $before.PackageIdFingerprint
    packageAssemblyIdentitySha256 = Get-TestSha256 $before.AssemblyId
    handlerTypeIdentitySha256 = Get-TestSha256 $before.HandlerTypeId
    apiMetadataSha256 = $before.ApiMetadataSha256
    legacyAssemblyIdentitySha256 = Get-TestSha256 $before.LegacyAssemblyId
    legacyAssemblySha256 = $before.LegacyAssemblySha256
    packageCount = $before.PackageCount
    predicates = [ordered]@{}
}
$after = [pscustomobject]@{
    PackageIdFingerprint = $before.PackageIdFingerprint
    AssemblyId = $before.AssemblyId
    HandlerTypeId = $before.HandlerTypeId
    LegacyAssemblyId = $before.LegacyAssemblyId
    PackageCount = $before.PackageCount
    ApiMetadataSha256 = $before.ApiMetadataSha256
    LegacyAssemblySha256 = $before.LegacyAssemblySha256
    OneExistingPackage = $true
    SamePackageRecord = $true
    PackageAssemblyLinked = $true
    SamePackageAssembly = $true
    ExpectedHandlerPackageBacked = $true
    SameHandlerType = $true
    CustomApiMetadataUnchanged = $true
    LegacyAssemblyUntouched = $true
    AllProtectCandidateCoreStepsInactive = $true
    NoActiveProfilerWrappers = $true
    PluginTraceLogOff = $true
    NoNewPluginPackage = $true
    ModifiedOnAdvanced = $false
    ServerPackageBytesAvailable = $false
}
Assert-Test (Test-SnapshotEquivalent -Before $before -After $after) `
    'Live snapshots reconcile package, assembly, handler, API, legacy, and safety predicates'
Assert-Test (Test-SnapshotEquivalent -Before $beforeJournal -After $after) `
    'Persisted sanitized fingerprints support restart reconciliation without raw record IDs'
$after.LegacyAssemblyId = '77777777-7777-4777-8777-777777777777'
Assert-Test (-not (Test-SnapshotEquivalent -Before $beforeJournal -After $after)) `
    'Restart reconciliation rejects a changed legacy assembly identity'
$after.LegacyAssemblyId = $before.LegacyAssemblyId

New-Item -ItemType Directory -Path $temporaryRoot -Force | Out-Null
$successJournalPath = Join-Path $temporaryRoot 'success.json'
$successJournal = New-PackageUpdaterJournal -Profile TEST -UniqueName 'os_sr_cact_pkg' `
    -ArtifactSha256 $packageHash -EnvironmentId '11111111-1111-4111-8111-111111111111' `
    -OrganizationId '22222222-2222-4222-8222-222222222222'
$successJournal.packageRecordIdentitySha256 = $before.PackageIdFingerprint
$successJournal.preflightTopology = $beforeJournal
$script:SnapshotForReconcile = $after
$script:DispatchCount = 0
$script:ReadRequestCount = 2
$dispatchCalls = 0
$reconcileCalls = 0
$successState = Invoke-OneShotDispatchStateMachine -Path $successJournalPath -Journal $successJournal `
    -Dispatch {
        $script:DispatchCount++
        $script:dispatchCalls++
        [pscustomobject]@{ Classification = 'PAC_SUCCESS_REPORTED' }
    } -Reconcile {
        $script:reconcileCalls++
        $script:SnapshotForReconcile
    }
$savedSuccess = Get-Content -LiteralPath $successJournalPath -Raw | ConvertFrom-Json
Assert-Test ($successState.Result -ceq 'DEPLOYMENT_CONFIRMED' -and
    $successState.DispatchCount -eq 1 -and $successState.RetryCount -eq 0 -and
    $successState.NetworkOperations -eq 3 -and $script:dispatchCalls -eq 1 -and
    $script:reconcileCalls -eq 1 -and $savedSuccess.dispatchState -ceq 'RECONCILED') `
    'One reserved dispatch reconciles once and confirms only an equivalent topology'
Assert-Test (-not ($savedSuccess | ConvertTo-Json -Depth 20 | Select-String -Quiet $packageId)) `
    'Dispatch journal stores no raw package record identity'
Assert-Test (-not ($savedSuccess | ConvertTo-Json -Depth 20 | Select-String -Quiet '11111111-1111-4111-8111-111111111111|22222222-2222-4222-8222-222222222222')) `
    'Dispatch journal stores no target environment or organization identifiers'

$ambiguousJournalPath = Join-Path $temporaryRoot 'ambiguous.json'
$ambiguousJournal = New-PackageUpdaterJournal -Profile TEST -UniqueName 'os_sr_cact_pkg' `
    -ArtifactSha256 $packageHash -EnvironmentId '11111111-1111-4111-8111-111111111111' `
    -OrganizationId '22222222-2222-4222-8222-222222222222'
$ambiguousJournal.packageRecordIdentitySha256 = $before.PackageIdFingerprint
$ambiguousJournal.preflightTopology = $beforeJournal
$script:DispatchCount = 0
$reconcileCalls = 0
$ambiguousState = Invoke-OneShotDispatchStateMachine -Path $ambiguousJournalPath -Journal $ambiguousJournal `
    -Dispatch {
        $script:DispatchCount++
        [pscustomobject]@{ Classification = 'PAC_RESULT_AMBIGUOUS' }
    } -Reconcile { throw 'must not run' }
$savedAmbiguous = Get-Content -LiteralPath $ambiguousJournalPath -Raw | ConvertFrom-Json
Assert-Test ($ambiguousState.Result -ceq 'DEPLOYMENT_OUTCOME_AMBIGUOUS_REQUIRES_RECONCILIATION' -and
    $savedAmbiguous.dispatchState -ceq 'OUTCOME_AMBIGUOUS' -and
    $script:reconcileCalls -eq 0 -and -not (Test-JournalCanReserveDispatch -Journal $savedAmbiguous)) `
    'Ambiguous dispatch is never resent or reconciled inline'
Assert-ReconcileJournal -Journal $savedAmbiguous
Assert-Test ($savedAmbiguous.targetEnvironmentIdentitySha256 -ceq
    (Get-TargetIdentityFingerprint -Identifier $ExpectedEnvironmentId) -and
    $savedAmbiguous.targetOrganizationIdentitySha256 -ceq
        (Get-TargetIdentityFingerprint -Identifier $ExpectedOrganizationId)) `
    'Journal target binding uses one-way identity fingerprints'
$reservedJournal = $savedAmbiguous | ConvertTo-Json -Depth 20 | ConvertFrom-Json
$reservedJournal.dispatchState = 'DISPATCH_RESERVED'
Assert-ReconcileJournal -Journal $reservedJournal
$wrongTargetJournal = $savedAmbiguous | ConvertTo-Json -Depth 20 | ConvertFrom-Json
$wrongTargetJournal.targetEnvironmentIdentitySha256 = 'f' * 64
$wrongTargetFailure = $null
try { Assert-ReconcileJournal -Journal $wrongTargetJournal }
catch { $wrongTargetFailure = $_.Exception.Message }
Assert-Test ($wrongTargetFailure -ceq 'PACKAGE_DISPATCH_JOURNAL_NOT_RECONCILABLE') `
    'Reconciliation rejects a journal bound to a different target before any live reads'
$reusedJournalFailure = $null
try {
    Invoke-OneShotDispatchStateMachine -Path $ambiguousJournalPath -Journal $ambiguousJournal `
        -Dispatch { throw 'must not run' } -Reconcile { throw 'must not run' } | Out-Null
} catch { $reusedJournalFailure = $_.Exception.Message }
Assert-Test ($reusedJournalFailure -ceq 'PACKAGE_DISPATCH_JOURNAL_ALREADY_EXISTS') `
    'Existing one-shot journal prevents dispatch reuse'

 $updaterSource = Get-Content -LiteralPath $updaterPath -Raw
Assert-Test ($updaterSource.Contains('$start.ArgumentList.Add($argument)') -and
    -not $updaterSource.Contains('Invoke-Expression') -and
    -not $updaterSource.Contains('PublishAllXml') -and
    $updaterSource.Contains("dispatchState -cnotin @('OUTCOME_AMBIGUOUS', 'DISPATCH_RESERVED')") -and
    $updaterSource.Contains("PSObject.Properties['ModifiedOn']") -and
    $updaterSource.Contains("Manifest.releaseTooling.pacCliVersion") -and
    $updaterSource.Contains("CommandType -ne 'Application'")) `
    'Updater uses structured PAC arguments, pinned CLI version, and restart-safe read-only journal reconciliation'

"BsoRsCandidatePackageUpdater.Tests.ps1: $passed assertions passed."
} finally {
    if (Test-Path -LiteralPath $temporaryRoot -PathType Container) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}
