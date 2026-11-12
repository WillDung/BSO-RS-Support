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

$devPlan = & $updaterPath -Mode Plan -TargetProfile DEV `
    -DevelopmentSourceAheadOfFrozenRelease `
    -ExpectedEnvironmentDisplayName 'VN LMV IT' `
    -OrganizationUrl 'https://test.invalid' `
    -ExpectedEnvironmentId '11111111-1111-4111-8111-111111111111' `
    -ExpectedOrganizationId '22222222-2222-4222-8222-222222222222' `
    -ArtifactPath $packagePath `
    -ExpectedPackageSha256 $manifest.candidateCore.packageSha256 `
    -ExpectedAssemblySha256 $manifest.candidateCore.embeddedAssemblySha256 `
    -ExpectedPackageUniqueName $manifest.candidateCore.packageUniqueName `
    -ExpectedHandlerTypeName $manifest.candidateCore.customApiHandlerTypeName `
    -JournalPath $planJournal
Assert-Test ($devPlan.Result -ceq 'PACKAGE_UPDATE_PLAN_READY_NOT_DISPATCHED' -and
    $devPlan.NetworkOperations -eq 0 -and $devPlan.DispatchCount -eq 0 -and
    -not $devPlan.JournalWritten) `
    'Explicit DEV source-ahead planning remains offline and cannot dispatch'

$devMissingOptIn = & $updaterPath -Mode Plan -TargetProfile DEV `
    -ExpectedEnvironmentDisplayName 'VN LMV IT' `
    -OrganizationUrl 'https://test.invalid' `
    -ExpectedEnvironmentId '11111111-1111-4111-8111-111111111111' `
    -ExpectedOrganizationId '22222222-2222-4222-8222-222222222222' `
    -ArtifactPath $packagePath `
    -ExpectedPackageSha256 $manifest.candidateCore.packageSha256 `
    -ExpectedAssemblySha256 $manifest.candidateCore.embeddedAssemblySha256 `
    -ExpectedPackageUniqueName $manifest.candidateCore.packageUniqueName `
    -ExpectedHandlerTypeName $manifest.candidateCore.customApiHandlerTypeName `
    -JournalPath $planJournal
Assert-Test ($devMissingOptIn.FailureCode -ceq 'PACKAGE_DEVELOPMENT_SOURCE_AUTHORIZATION_REQUIRED' -and
    $devMissingOptIn.NetworkOperations -eq 0) `
    'DEV source-ahead deployment is blocked without explicit recovery-only opt-in'

$expectedBsoPrivileges = Get-RolePrivilegeMapFromXml `
    -Path (Join-Path $root 'solutions\Roles\BSO-RS Support - BSO.xml') `
    -ExpectedRoleName 'BSO-RS Support - BSO'
$expectedReferencePrivileges = Get-RolePrivilegeMapFromXml `
    -Path (Join-Path $root 'solutions\Roles\BSO-RS Support - Reference Admin.xml') `
    -ExpectedRoleName 'BSO-RS Support - Reference Admin'
Assert-Test ($expectedBsoPrivileges.Count -eq 60 -and
    $expectedReferencePrivileges.Count -eq 20 -and
    -not ($expectedBsoPrivileges.ContainsKey('prvCreateos_sr_cand')) -and
    -not ($expectedBsoPrivileges.ContainsKey('prvWriteos_sr_cand'))) `
    'Local security baselines retain denied BSO direct-write privileges and bounded Reference Admin scope'
$alteredBsoPrivileges = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal)
foreach ($key in $expectedBsoPrivileges.Keys) { $alteredBsoPrivileges.Add($key, $expectedBsoPrivileges[$key]) }
$alteredBsoPrivileges['prvReados_sr_cand'] = 'Local'
Assert-Test ((Test-RolePrivilegeMapEqual -Expected $expectedBsoPrivileges -Actual $expectedBsoPrivileges) -and
    -not (Test-RolePrivilegeMapEqual -Expected $expectedBsoPrivileges -Actual $alteredBsoPrivileges)) `
    'Role definition reconciliation detects privilege-depth drift'

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

$legacyTopology = [pscustomobject]@{
    OneExistingPackage = $true
    ExpectedPluginTypeSetExact = $true
    PackageAssemblyLinked = $true
    RegisteredPackageVersionUnchanged = $true
    ExpectedHandlerPackageBacked = $true
    CustomApiMetadataUnchanged = $true
    LegacyAssemblyUntouched = $true
    AllProtectCandidateCoreStepsInactive = $true
    ProtectCandidateCoreStepCount = 49
    NoActiveLegacyHandlers = $true
    NoActiveCandidateCoreProfilerWrappers = $true
    PluginTraceLogOff = $true
    NoNewPluginPackage = $true
}
$legacyPreflightResult = $null
try { Assert-PreflightTopology -Snapshot $legacyTopology; $legacyPreflightResult = 'PASS' }
catch { $legacyPreflightResult = $_.Exception.Message }
Assert-Test ($legacyPreflightResult -ceq 'PASS') `
    'Legacy guard topology is gated by inactivity, not a fixed 62-step count'
$legacyTopology.ExpectedPluginTypeSetExact = $false
$wrongTypeSetPreflight = $null
try { Assert-PreflightTopology -Snapshot $legacyTopology; $wrongTypeSetPreflight = 'PASS' }
catch { $wrongTypeSetPreflight = $_.Exception.Message }
$legacyTopology.ExpectedPluginTypeSetExact = $true
$legacyTopology.RegisteredPackageVersionUnchanged = $false
$wrongPackageVersionPreflight = $null
try { Assert-PreflightTopology -Snapshot $legacyTopology; $wrongPackageVersionPreflight = 'PASS' }
catch { $wrongPackageVersionPreflight = $_.Exception.Message }
$legacyTopology.RegisteredPackageVersionUnchanged = $true
Assert-Test ($wrongTypeSetPreflight -ceq 'PACKAGE_TOPOLOGY_PREFLIGHT_FAILED' -and
    $wrongPackageVersionPreflight -ceq 'PACKAGE_TOPOLOGY_PREFLIGHT_FAILED') `
    'Preflight rejects plugin-type and registered-package-version drift'
$legacyTopology.NoActiveLegacyHandlers = $false
$activeLegacyPreflight = $null
try { Assert-PreflightTopology -Snapshot $legacyTopology; $activeLegacyPreflight = 'PASS' }
catch { $activeLegacyPreflight = $_.Exception.Message }
Assert-Test ($activeLegacyPreflight -ceq 'PACKAGE_TOPOLOGY_PREFLIGHT_FAILED') `
    'Unexpected active signed rollback handler blocks the preflight'

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
    ExpectedPluginTypeSetExact = $true
    OneExistingPackage = $true
    SamePackageRecord = $true
    PackageAssemblyLinked = $true
    SamePackageAssembly = $true
    ExpectedHandlerPackageBacked = $true
    SameHandlerType = $true
    CustomApiMetadataUnchanged = $true
    LegacyAssemblyUntouched = $true
    AllProtectCandidateCoreStepsInactive = $true
    NoActiveLegacyHandlers = $true
    NoActiveCandidateCoreProfilerWrappers = $true
    PluginTraceLogOff = $true
    NoNewPluginPackage = $true
    RegisteredPackageVersionUnchanged = $true
    AssemblyVersionUpdated = $true
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
$apiParameterId = '33333333-3333-4333-8333-333333333333'
$apiPlanPath = Join-Path $temporaryRoot 'approved-profile-mask-api-plan.json'
$maskContract = @((Get-Content -LiteralPath (Join-Path $root 'docs\PHASE_3C_API_CONTRACT.json') -Raw |
    ConvertFrom-Json).inputs | Where-Object name -CEQ 'ProfileFieldMask')
$apiPlan = [ordered]@{
    EnvironmentName = 'VN LMV IT'
    OrganizationUrl = 'https://test.invalid'
    ExpectedEnvironmentId = '11111111-1111-4111-8111-111111111111'
    ExpectedOrganizationId = '22222222-2222-4222-8222-222222222222'
    SolutionUniqueName = $manifest.solution.uniqueName
    ApiUniqueName = 'os_sr_cact'
    ApiId = '44444444-4444-4444-8444-444444444444'
    ExpectedMissingNames = @('ProfileFieldMask')
    AutomaticRetries = 0
    MaximumPostDispatches = 1
    Writes = @([ordered]@{
        Id = $apiParameterId
        Name = 'ProfileFieldMask'
        Type = [int]$maskContract[0].type
        IsOptional = [bool]$maskContract[0].optional
        Body = [ordered]@{
            customapirequestparameterid = $apiParameterId
            uniquename = 'ProfileFieldMask'
            type = [int]$maskContract[0].type
            isoptional = [bool]$maskContract[0].optional
        }
    })
}
$apiPlan | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $apiPlanPath
$ExpectedDevelopmentApiPlanPath = $apiPlanPath
$ExpectedDevelopmentApiPlanSha256 = (Get-FileHash -LiteralPath $apiPlanPath -Algorithm SHA256).Hash.ToLowerInvariant()
$apiPlanReadback = Get-ApprovedDevelopmentApiParameterPlan -Baseline ([pscustomobject]@{
    Api = [pscustomobject]@{ customapiid = $apiPlan.ApiId }
})
Assert-Test ($apiPlanReadback.Writes.Count -eq 1 -and
    $apiPlanReadback.Writes[0].Name -ceq 'ProfileFieldMask') `
    'DEV package gate accepts only a hash-pinned single ProfileFieldMask API plan'
$baselineMembershipLines = @(
    '60|aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa|0',
    '1|bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb|0'
)
$addedMaskMembership = '61|33333333-3333-4333-8333-333333333333|0'
Assert-Test (Test-ApprovedDevelopmentMembershipDelta -BaselineLines $baselineMembershipLines `
    -CurrentLines @($baselineMembershipLines + $addedMaskMembership) `
    -ApiParameterId $apiParameterId -ApiParameterPresent $true) `
    'DEV package gate permits the exact plan-pinned API parameter membership delta'
Assert-Test (-not (Test-ApprovedDevelopmentMembershipDelta -BaselineLines $baselineMembershipLines `
    -CurrentLines @($baselineMembershipLines + '61|55555555-5555-4555-8555-555555555555|0') `
    -ApiParameterId $apiParameterId -ApiParameterPresent $true) -and
    -not (Test-ApprovedDevelopmentMembershipDelta -BaselineLines $baselineMembershipLines `
        -CurrentLines @($baselineMembershipLines | Select-Object -First 1) `
        -ApiParameterId $apiParameterId -ApiParameterPresent $false)) `
    'DEV package gate rejects unrelated membership additions and missing baseline members'
$ExpectedDevelopmentApiPlanSha256 = ('0' * 64)
$invalidApiPlanFailure = $null
try {
    Get-ApprovedDevelopmentApiParameterPlan -Baseline ([pscustomobject]@{
        Api = [pscustomobject]@{ customapiid = $apiPlan.ApiId }
    }) | Out-Null
} catch { $invalidApiPlanFailure = $_.Exception.Message }
Assert-Test ($invalidApiPlanFailure -ceq 'PACKAGE_TOPOLOGY_PREFLIGHT_FAILED') `
    'DEV package gate rejects a changed API plan fingerprint'
Assert-Test ((Test-HasFileStoreSourceLabel -Labels @('File Store', 'File Store')) -and
    -not (Test-HasFileStoreSourceLabel -Labels @('Database'))) `
    'Package assembly source check accepts duplicate localized File Store labels only'
$profilerTypeId = '55555555-5555-4555-8555-555555555555'
$unrelatedProfilerStep = [pscustomobject]@{
    name = "CustomApi 'msdyn_ContentGenerationSemanticProfiler' implementation"
    _eventhandler_value = $profilerTypeId
}
$candidateProfilerStep = [pscustomobject]@{
    name = "CustomApi 'os_sr_cact' implementation"
    _eventhandler_value = $profilerTypeId
}
Assert-Test (-not (Test-IsCandidateCoreProfilerStep -Step $unrelatedProfilerStep `
        -ProfilerTypeIds @($profilerTypeId)) -and
    (Test-IsCandidateCoreProfilerStep -Step $candidateProfilerStep `
        -ProfilerTypeIds @($profilerTypeId))) `
    'Profiler safety gate is scoped to Candidate Core rather than unrelated platform plugins'
$originalUriGet = (Get-Item Function:\Invoke-DataverseUriGet).ScriptBlock
try {
    Set-Item Function:\Invoke-DataverseUriGet -Value {
        [pscustomobject]@{ value = @([pscustomobject]@{ id = 'synthetic-row' }) }
    }
    $script:ApiRoot = 'https://org.invalid/api/data/v9.2/'
    $rowsWithoutNextLink = @(Get-DataverseRows -Path 'syntheticrows')
    Assert-Test ($rowsWithoutNextLink.Count -eq 1 -and $rowsWithoutNextLink[0].id -ceq 'synthetic-row') `
        'Read-only paging accepts a single-page response without an optional nextLink'
} finally {
    Set-Item Function:\Invoke-DataverseUriGet -Value $originalUriGet
}

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

$utcModifiedOn = [DateTimeOffset]::new(2026, 11, 4, 5, 44, 7, [TimeSpan]::Zero)
$offsetModifiedOn = [DateTimeOffset]::new(2026, 11, 4, 12, 44, 7, [TimeSpan]::FromHours(7))
$laterModifiedOn = $utcModifiedOn.AddSeconds(1)
Assert-Test (Test-PackageModifiedOnMatchesBaseline `
    -CurrentModifiedOn $utcModifiedOn -BaselineModifiedOn $offsetModifiedOn) `
    'Package timestamp baseline compares equivalent instants across offsets'
Assert-Test (-not (Test-PackageModifiedOnMatchesBaseline `
    -CurrentModifiedOn $laterModifiedOn -BaselineModifiedOn $utcModifiedOn)) `
    'Package timestamp baseline still detects a genuinely advanced timestamp'

 $updaterSource = Get-Content -LiteralPath $updaterPath -Raw
Assert-Test ($updaterSource.Contains('$start.ArgumentList.Add($argument)') -and
    -not $updaterSource.Contains('Invoke-Expression') -and
    -not $updaterSource.Contains('PublishAllXml') -and
    $updaterSource.Contains('$ExecutablePath help') -and
    -not $updaterSource.Contains('$ExecutablePath --version') -and
    $updaterSource.Contains("dispatchState -cnotin @('OUTCOME_AMBIGUOUS', 'DISPATCH_RESERVED')") -and
    $updaterSource.Contains("PSObject.Properties['ModifiedOn']") -and
    $updaterSource.Contains('ModifiedOn = $PackageRow.modifiedon') -and
    -not $updaterSource.Contains('ModifiedOn = [string]$PackageRow.modifiedon') -and
    -not $updaterSource.Contains('[string]$Before.ModifiedOn') -and
    $updaterSource.Contains("Manifest.releaseTooling.pacCliVersion") -and
    $updaterSource.Contains('-ExpectedPluginTypes (Get-ManifestExpectedPluginTypes)') -and
    $updaterSource.Contains('RegisteredPackageVersionUnchanged') -and
    $updaterSource.Contains("CommandType -ne 'Application'")) `
    'Updater uses structured PAC arguments, pinned CLI version, and restart-safe read-only journal reconciliation'
$preflightStart = $updaterSource.IndexOf("if (`$Mode -ceq 'Preflight') {")
$preflightEnd = $updaterSource.IndexOf("if (`$Mode -ceq 'Reconcile') {", $preflightStart)
$preflightBlock = if ($preflightStart -ge 0 -and $preflightEnd -gt $preflightStart) {
    $updaterSource.Substring($preflightStart, $preflightEnd - $preflightStart)
} else { '' }
Assert-Test ($updaterSource.Contains("RequestedMode -eq 'Preflight' -and `$TargetProfile -cne 'DEV'") -and
    $updaterSource.Contains('ExpectedDevelopmentBaselinePath') -and
    $updaterSource.Contains('ExpectedDevelopmentApiPlanPath') -and
    $updaterSource.Contains('ExpectedDevelopmentApiPlanSha256') -and
    $updaterSource.Contains('SolutionMembershipMatchesApprovedPlan') -and
    $updaterSource.Contains('Test-ApprovedDevelopmentMembershipDelta') -and
    $updaterSource.Contains('PACKAGE_MODIFIED_SINCE_BASELINE') -and
    $updaterSource.Contains('NoActiveCandidateCoreProfilerWrappers') -and
    $updaterSource.Contains('BsoProtectedDirectCreateWriteAbsent') -and
    $updaterSource.Contains('ReferenceAdminRoleUnassigned') -and
    $updaterSource.Contains('$guardSteps.Count -eq 62') -eq $false -and
    $preflightBlock -and
    -not $preflightBlock.Contains('Write-NewJournal') -and
    -not $preflightBlock.Contains('Invoke-PacPluginPush') -and
    -not $preflightBlock.Contains('Invoke-OneShotDispatchStateMachine')) `
    'DEV preflight compares exact recorded topology and roles without a 62-step gate or dispatch path'

$patchManifest = Get-Content -LiteralPath (Join-Path $root 'docs\CANDIDATE_CORE_1.0.8_RELEASE_MANIFEST.json') -Raw |
    ConvertFrom-Json
$script:Manifest = $patchManifest
$script:Manifest.patchDeployment.securityBaselineSha256 = 'a' * 64
$AssemblyOnlyPatch = $true
$patchPrivileges = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal)
foreach ($key in $expectedBsoPrivileges.Keys) { $patchPrivileges.Add($key, $expectedBsoPrivileges[$key]) }
foreach ($key in @('prvCreateos_sr_avq', 'prvReados_sr_avq', 'prvAppendos_sr_avq')) {
    $patchPrivileges.Add($key, 'Basic')
}
foreach ($key in @('prvAppendToos_sr_ta', 'prvAppendToos_sr_loc')) { $patchPrivileges.Add($key, 'Global') }
$patchSecurity = [pscustomobject]@{
    Sha256 = 'a' * 64
    Roles = @(
        [pscustomobject]@{ State = [pscustomobject]@{ Privileges = $patchPrivileges } },
        [pscustomobject]@{ State = [pscustomobject]@{ Privileges = $expectedReferencePrivileges } }
    )
}
Assert-UnchangedPatchSecurity -Snapshot $patchSecurity
Assert-Test ($patchPrivileges.Count -eq 65) 'Patch admits only the exact approved Availability privilege delta'
$patchSecurity.Sha256 = 'b' * 64
$failure = $null
try { Assert-UnchangedPatchSecurity -Snapshot $patchSecurity } catch { $failure = $_.Exception.Message }
Assert-Test ($failure -ceq 'PACKAGE_SECURITY_BASELINE_CHANGED') 'Patch rejects role or principal baseline fingerprint drift'
$patchSecurity.Sha256 = 'a' * 64
$patchPrivileges['prvAppendToos_sr_loc'] = 'Basic'
$failure = $null
try { Assert-UnchangedPatchSecurity -Snapshot $patchSecurity } catch { $failure = $_.Exception.Message }
Assert-Test ($failure -ceq 'PACKAGE_SECURITY_PREFLIGHT_FAILED') 'Patch rejects Availability privilege-depth changes'
$patchPrivileges['prvAppendToos_sr_loc'] = 'Global'
$patchPrivileges.Add('prvWriteos_sr_cand', 'Basic')
$failure = $null
try { Assert-UnchangedPatchSecurity -Snapshot $patchSecurity } catch { $failure = $_.Exception.Message }
Assert-Test ($failure -ceq 'PACKAGE_SECURITY_PREFLIGHT_FAILED') 'Patch rejects direct Candidate writes'
$patchPrivileges.Remove('prvWriteos_sr_cand') | Out-Null

$beforeJournal | Add-Member -NotePropertyName securityBaselineSha256 -NotePropertyValue ('a' * 64)
$after | Add-Member -NotePropertyName SecurityBaselineSha256 -NotePropertyValue ('a' * 64)
$after | Add-Member -NotePropertyName SecurityBaselineUnchanged -NotePropertyValue $true
Assert-Test (Test-SnapshotEquivalent -Before $beforeJournal -After $after) 'Patch reconciliation retains exact security fingerprint'
$after.SecurityBaselineSha256 = 'b' * 64
Assert-Test (-not (Test-SnapshotEquivalent -Before $beforeJournal -After $after)) 'Patch reconciliation rejects security assignment drift'
$after.SecurityBaselineSha256 = 'a' * 64
$after.SecurityBaselineUnchanged = $false
Assert-Test (-not (Test-SnapshotEquivalent -Before $beforeJournal -After $after)) 'Patch cannot confirm without unchanged-security proof'
$after.SecurityBaselineUnchanged = $true

$script:Manifest = Get-Content -LiteralPath (Join-Path $root 'docs\RELEASE_INPUT_MANIFEST.json') -Raw | ConvertFrom-Json
$failure = $null
try { Assert-ReconcileJournal -Journal $savedAmbiguous } catch { $failure = $_.Exception.Message }
Assert-Test ($failure -ceq 'PACKAGE_DISPATCH_JOURNAL_NOT_RECONCILABLE') 'Patch cannot reinterpret an ordinary dispatch journal'
$patchJournal = $savedAmbiguous | ConvertTo-Json -Depth 20 | ConvertFrom-Json
$patchJournal | Add-Member -NotePropertyName assemblyOnlyPatch -NotePropertyValue $true
$patchJournal.preflightTopology | Add-Member -NotePropertyName securityBaselineSha256 -NotePropertyValue ('a' * 64)
$script:Manifest | Add-Member -NotePropertyName patchDeployment -NotePropertyValue $patchManifest.patchDeployment -Force
Assert-ReconcileJournal -Journal $patchJournal
Assert-Test ($patchJournal.dispatchCount -eq 1) 'Patch journal remains target/artifact/security bound with one dispatch'
$AssemblyOnlyPatch = $false
$failure = $null
try { Assert-ReconcileJournal -Journal $patchJournal } catch { $failure = $_.Exception.Message }
Assert-Test ($failure -ceq 'PACKAGE_DISPATCH_JOURNAL_NOT_RECONCILABLE') 'Ordinary mode cannot reinterpret a patch journal'

$AssemblyOnlyPatch = $true
$ExpectedDevelopmentBaselinePath = Join-Path $temporaryRoot 'patch-baseline.json'
[IO.File]::WriteAllText($ExpectedDevelopmentBaselinePath, (
    ConvertTo-Json @{ Package = @{ pluginpackageid = $packageId } }))
$failure = $null
try {
    Invoke-PacPluginPush -Executable 'must-not-start' -Arguments @('admin', 'assign-user') | Out-Null
} catch { $failure = $_.Exception.Message }
Assert-Test ($failure -ceq 'PACKAGE_SECURITY_METADATA_WRITE_PROHIBITED') 'Patch rejects security-write PAC commands before starting a process'

$TargetProfile = 'DEV'
$DevelopmentSourceAheadOfFrozenRelease = $true
$ExpectedEnvironmentDisplayName = 'VN LMV IT'
$ExpectedAssemblySha256 = $manifest.candidateCore.embeddedAssemblySha256
$ReleaseManifestPath = 'synthetic-manifest.json'
$RollbackArtifactPath = 'synthetic-rollback.nupkg'
$script:Manifest | Add-Member -NotePropertyName customApi -NotePropertyValue $patchManifest.customApi -Force
Assert-UpdaterInputs -RequestedMode Plan
Assert-Test $true 'Explicit DEV no-change manifest and rollback authorize the narrow patch path'
$script:Manifest.patchDeployment.securityMetadataWrites = 1
$failure = $null
try { Assert-UpdaterInputs -RequestedMode Plan } catch { $failure = $_.Exception.Message }
Assert-Test ($failure -ceq 'PACKAGE_ASSEMBLY_ONLY_AUTHORIZATION_REQUIRED') 'Patch manifest cannot authorize security metadata writes'
$script:Manifest.patchDeployment.securityMetadataWrites = 0
$script:Manifest.patchDeployment.allowedMutations = @('EXISTING_PLUGINPACKAGE_CONTENT', 'ROLE')
$failure = $null
try { Assert-UpdaterInputs -RequestedMode Plan } catch { $failure = $_.Exception.Message }
Assert-Test ($failure -ceq 'PACKAGE_ASSEMBLY_ONLY_AUTHORIZATION_REQUIRED') 'Patch manifest cannot authorize additional mutation types'
$script:Manifest.patchDeployment.allowedMutations = @('EXISTING_PLUGINPACKAGE_CONTENT')
$RollbackArtifactPath = ''
$failure = $null
try { Assert-UpdaterInputs -RequestedMode Plan } catch { $failure = $_.Exception.Message }
Assert-Test ($failure -ceq 'PACKAGE_ASSEMBLY_ONLY_AUTHORIZATION_REQUIRED') 'Patch authorization requires the rollback artifact even in Plan'

"BsoRsCandidatePackageUpdater.Tests.ps1: $passed assertions passed."
} finally {
    if (Test-Path -LiteralPath $temporaryRoot -PathType Container) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}
