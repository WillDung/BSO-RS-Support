#requires -Version 7.4
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Split-Path $PSScriptRoot -Parent
$docs = Join-Path $root 'docs'
$solutions = Join-Path $root 'solutions'
$inventory = Get-Content -LiteralPath (Join-Path $docs 'SOLUTION_COMPONENT_INVENTORY.json') -Raw | ConvertFrom-Json
$manifest = Get-Content -LiteralPath (Join-Path $solutions 'Other\Solution.xml') -Raw
[xml]$solutionXml = $manifest
$roots = @($solutionXml.SelectNodes('//*[local-name()="RootComponent"]'))
$importContract = Get-Content -LiteralPath (Join-Path $docs 'SOLUTION_IMPORT_CONTRACT.json') -Raw | ConvertFrom-Json
$updaterContract = Get-Content -LiteralPath (Join-Path $docs 'RELEASE_UPDATER_CONTRACT.json') -Raw | ConvertFrom-Json
$releaseInputs = Get-Content -LiteralPath (Join-Path $docs 'RELEASE_INPUT_MANIFEST.json') -Raw | ConvertFrom-Json
$rollback = Get-Content -LiteralPath (Join-Path $docs 'ROLLBACK_MANIFEST.json') -Raw | ConvertFrom-Json
$canonicalSourceModule = Join-Path $root 'scripts\BsoRsCanonicalSourceFingerprint.psm1'
Import-Module $canonicalSourceModule -Force
$targetAuthorizationModule = Join-Path $root 'scripts\BsoRsTestTargetAuthorization.psm1'
$passed = 0

function Assert-Test {
    param([bool]$Condition, [string]$Name)
    if (-not $Condition) { throw "FAIL: $Name" }
    $script:passed++
}

Assert-Test ($inventory.rootComponentCount -eq 72 -and
    $inventory.countSemantics.preCleanupExportRoots -eq 72 -and
    $inventory.countSemantics.authoredCanonicalRoots -eq 20 -and
    $inventory.countSemantics.generatedReleaseRoots -eq 1 -and
    $inventory.countSemantics.expectedLiveAndExportReleaseRoots -eq 21 -and
    $inventory.countSemantics.excludedRoots -eq 51 -and $roots.Count -eq 20) `
    'Reconcile the pre-cleanup 72 roots to 20 authored, one generated, and 51 excluded roots'
$canonicalCounts = @{}
foreach ($group in $roots | Group-Object { $_.GetAttribute('type') }) {
    $canonicalCounts[$group.Name] = $group.Count
}
Assert-Test ($canonicalCounts['1'] -eq 10 -and $canonicalCounts['9'] -eq 2 -and
    $canonicalCounts['20'] -eq 1 -and $canonicalCounts['61'] -eq 5 -and
    $canonicalCounts['62'] -eq 1 -and $canonicalCounts['80'] -eq 1) `
    'Verify the canonical root count by component class'
Assert-Test (@($inventory.countSemantics.generatedRootsByType | Where-Object {
    $_.type -eq 91 -and $_.count -eq 1
}).Count -eq 1 -and @($inventory.countSemantics.excludedRootsByType | Where-Object {
    $_.type -eq 91 -and $_.count -eq 1
}).Count -eq 1 -and @($inventory.countSemantics.excludedRootsByType | Where-Object {
    $_.type -eq 92 -and $_.count -eq 50
}).Count -eq 1) 'Separate the generated assembly root from the excluded rollback assembly and guard steps'
Assert-Test ($inventory.liveMembershipReconciliation.rootPartition.preCleanupLiveRoots -eq 72 -and
    $inventory.liveMembershipReconciliation.rootPartition.authoredCanonicalRoots -eq 20 -and
    $inventory.liveMembershipReconciliation.rootPartition.generatedReleaseRoots -eq 1 -and
    $inventory.liveMembershipReconciliation.rootPartition.expectedReleaseRoots -eq 21 -and
    $inventory.liveMembershipReconciliation.rootPartition.excludedRoots -eq 51 -and
    $inventory.liveMembershipReconciliation.rootPartition.duplicateRoots -eq 0 -and
    $inventory.liveMembershipReconciliation.rootPartition.missingRoots -eq 0 -and
    $inventory.liveMembershipReconciliation.rootPartition.misclassifiedRoots -eq 0 -and
    $inventory.liveMembershipReconciliation.rootPartition.postCleanupLiveRoots -eq 21 -and
    $inventory.liveMembershipReconciliation.rootPartition.postCleanupExcludedRootsRemaining -eq 0 -and
    $inventory.liveMembershipReconciliation.postCleanupComponentHierarchy.solutionComponentRows -eq 47 -and
    $inventory.liveMembershipReconciliation.postCleanupComponentHierarchy.rootRows -eq 21 -and
    $inventory.liveMembershipReconciliation.postCleanupComponentHierarchy.nonRootRows -eq 26 -and
    $inventory.liveMembershipReconciliation.postCleanupComponentHierarchy.releaseRootIdentityMatch -eq $true -and
    $inventory.liveMembershipReconciliation.postCleanupComponentHierarchy.releaseRootIdentitySetSha256 -ceq
        'ffde0fe088d87120aa29caf11de156537f19abf9627695d95306eea040c530e4' -and
    $inventory.liveMembershipReconciliation.generatedReleaseRoot.packageIdLinkVerified -eq $true -and
    $inventory.liveMembershipReconciliation.generatedReleaseRoot.packageUniqueName -ceq 'os_sr_cact_pkg' -and
    $inventory.liveMembershipReconciliation.proposedMembershipRemovalSet.rootRemovals -eq 51 -and
    $inventory.liveMembershipReconciliation.proposedMembershipRemovalSet.packageGeneratedAssemblyRemoval -eq $false) `
    'Track the verified generated root and keep it outside the exact 51-root removal set'
Assert-Test ($inventory.liveMembershipReconciliation.nonRootSolutionMemberships.excluded.customApi -eq 1 -and
    $inventory.liveMembershipReconciliation.nonRootSolutionMemberships.excluded.requestParameters -eq 12 -and
    $inventory.liveMembershipReconciliation.nonRootSolutionMemberships.excluded.responseProperties -eq 2 -and
    $inventory.liveMembershipReconciliation.nonRootSolutionMemberships.excluded.membershipCount -eq 15 -and
    $inventory.liveMembershipReconciliation.nonRootSolutionMemberships.excluded.removedFromSolutionMembership -eq $true -and
    $inventory.liveMembershipReconciliation.nonRootSolutionMemberships.excluded.componentRecordsRetained -eq $true) `
    'Keep the removed temporary DEV Custom API group distinct from its retained component records'

$requiredEntities = @(
    'os_sr_cand', 'os_sr_call', 'os_sr_csh', 'os_sr_intv', 'os_sr_oprc',
    'os_sr_pos', 'os_sr_csrc', 'os_sr_ta', 'os_sr_loc', 'systemuser'
)
foreach ($entityName in $requiredEntities) {
    $entityPath = Join-Path $solutions "Entities\$entityName\Entity.xml"
    Assert-Test (Test-Path -LiteralPath $entityPath -PathType Leaf) "Canonical entity source exists: $entityName"
}
$expectedKeys = @{
    os_sr_cand = @('os_sr_cand_ak_cnum', 'os_sr_cand_ak_corid')
    os_sr_call = @('os_sr_call_ak_cand_action')
    os_sr_csh = @('os_sr_csh_ak_cand_action')
    os_sr_oprc = @('os_sr_oprc_ak_corid')
}
foreach ($entityName in $expectedKeys.Keys) {
    [xml]$entityDocument = Get-Content -LiteralPath (Join-Path $solutions "Entities\$entityName\Entity.xml") -Raw
    $keys = @($entityDocument.SelectNodes('//*[local-name()="EntityKey"]'))
    $keyNames = @($keys | ForEach-Object { $_.SelectSingleNode('./*[local-name()="Name"]').InnerText })
    Assert-Test (@(Compare-Object $expectedKeys[$entityName] $keyNames).Count -eq 0 -and
        @($keys | Where-Object { $_.SelectNodes('./*[local-name()="EntityKeyAttributes"]/*[local-name()="AttributeName"]').Count -eq 0 }).Count -eq 0) `
        "Required alternate keys and key columns are present for $entityName"
}
foreach ($entityName in @(
    'os_sr_cand', 'os_sr_call', 'os_sr_csh', 'os_sr_intv', 'os_sr_oprc',
    'os_sr_pos', 'os_sr_csrc', 'os_sr_ta', 'os_sr_loc'
)) {
    $entityRoot = Join-Path $solutions "Entities\$entityName"
    Assert-Test (@(Get-ChildItem -LiteralPath (Join-Path $entityRoot 'FormXml') -Filter '*.xml' -File -Recurse).Count -gt 0 -and
        @(Get-ChildItem -LiteralPath (Join-Path $entityRoot 'SavedQueries') -Filter '*.xml' -File -Recurse).Count -gt 0) `
        "Required forms and views are present for $entityName"
}
Assert-Test ((Test-Path -LiteralPath (Join-Path $solutions 'Other\Relationships.xml') -PathType Leaf) -and
    @(Get-ChildItem -LiteralPath (Join-Path $solutions 'OptionSets') -Filter '*.xml' -File).Count -eq 2 -and
    (Test-Path -LiteralPath (Join-Path $solutions 'Roles\BSO-RS Support - BSO.xml') -PathType Leaf)) `
    'Relationships, choices, and BSO security-role definition are canonical source'
Assert-Test ((Test-Path -LiteralPath (Join-Path $solutions 'AppModules\srapp\AppModule.xml') -PathType Leaf) -and
    (Test-Path -LiteralPath (Join-Path $solutions 'AppModuleSiteMaps\srapp\AppModuleSiteMap.xml') -PathType Leaf)) `
    'srapp and its Site Map are canonical source'
$webRoot = Join-Path $solutions 'CandidateConsole\WebResources\os_\bso'
foreach ($fileName in @(
    'candidate-console.html', 'candidate-console.js', 'candidate-console.css',
    'candidate-console-environment.js', 'candidate-console-policy.js'
)) {
    Assert-Test (Test-Path -LiteralPath (Join-Path $webRoot $fileName) -PathType Leaf) `
        "Candidate Console source exists: $fileName"
}
Assert-Test ((Get-ChildItem -LiteralPath (Join-Path $solutions 'customapis\os_sr_cact') -Recurse -File).Count -eq 24 -and
    (Test-Path -LiteralPath (Join-Path $solutions 'pluginpackages\os_sr_cact_pkg\pluginpackage.xml') -PathType Leaf) -and
    (Test-Path -LiteralPath (Join-Path $solutions 'pluginpackages\os_sr_cact_pkg\package\os_sr_cact_pkg.nupkg') -PathType Leaf)) `
    'Candidate Core API metadata and package-backed handler artifact are retained'
Assert-Test (@($inventory.requiredCapabilityDisposition | Where-Object {
    $_.classification -notin @('CANONICAL_SOURCE', 'GENERATED_FROM_CANONICAL_SOURCE',
        'DEPLOYMENT_TIME_CONFIGURATION', 'ROLLBACK_ONLY', 'EXTERNAL_DEPENDENCY')
}).Count -eq 0 -and $inventory.requiredCapabilityDisposition.Count -ge 10) `
    'Every required capability has an explicit source/deployment/rollback/dependency classification'

Assert-Test ($releaseInputs.status -ceq 'FROZEN_OFFLINE_SOURCE_INPUTS_NOT_A_RELEASE_APPROVAL' -and
    $releaseInputs.solution.uniqueName -ceq 'os_sr_bso_rs_support' -and
    $releaseInputs.solution.version -ceq '1.0.0.0' -and
    $releaseInputs.solution.packageType -ceq 'Managed' -and
    $releaseInputs.canonicalSource.rootComponentCount -eq 20 -and
    $releaseInputs.releaseRootModel.authoredCanonicalRootCount -eq 20 -and
    $releaseInputs.releaseRootModel.generatedPackageRootCount -eq 1 -and
    $releaseInputs.releaseRootModel.expectedLiveAndExportReleaseRootCount -eq 21 -and
    $releaseInputs.releaseRootModel.excludedPreCleanupRootCount -eq 51 -and
    $releaseInputs.releaseRootModel.postCleanupLiveRootCount -eq 21 -and
    $releaseInputs.releaseRootModel.postCleanupExcludedRootCount -eq 0 -and
    $releaseInputs.releaseRootModel.postCleanupSolutionComponentRows -eq 47 -and
    $releaseInputs.releaseRootModel.removedExcludedRootMembershipCount -eq 51 -and
    $releaseInputs.releaseRootModel.removedTemporaryDevMembershipCount -eq 15 -and
    $releaseInputs.releaseRootModel.generatedPackageAssemblyRoot.componentType -eq 91 -and
    $releaseInputs.releaseRootModel.generatedPackageAssemblyRoot.objectId -ceq
        'd71c6048-4fd0-f111-a05a-002248a1ba20' -and
    $releaseInputs.releaseRootModel.generatedPackageAssemblyRoot.packageUniqueName -ceq 'os_sr_cact_pkg' -and
    $releaseInputs.candidateCore.packageUniqueName -ceq 'os_sr_cact_pkg' -and
    $releaseInputs.candidateCore.customApiHandlerTypeName -ceq 'os_sr_cact.ApplyCandidateAction' -and
    $releaseInputs.candidateCore.protectCandidateCoreDisposition -ceq 'ALL_50_STEPS_INACTIVE_AND_EXCLUDED') `
    'Freeze exact release identity, source inventory, package topology, and guard disposition'
Assert-Test ($releaseInputs.devOriginReviewArtifact.disposition -ceq 'DEV_ORIGIN_REVIEW_ARTIFACT_NOT_RELEASEABLE' -and
    $releaseInputs.devOriginReviewArtifact.selectableForTestOrProduction -eq $false -and
    $importContract.artifact.devOriginReviewArtifactAllowed -eq $false) `
    'Explicitly reject the DEV-origin managed review archive from every release path'
Assert-Test ($null -eq $releaseInputs.targetEvidence.testUrl -and
    $null -eq $releaseInputs.targetEvidence.testEnvironmentId -and
    $null -eq $releaseInputs.targetEvidence.testOrganizationId -and
    $null -eq $releaseInputs.targetEvidence.productionUrl -and
    $null -eq $releaseInputs.targetEvidence.userIdentities -and
    $null -eq $releaseInputs.targetEvidence.secrets) `
    'Do not freeze target identifiers, user identities, secrets, or local evidence paths'

function Get-FileSha256 {
    param([Parameter(Mandatory)][string]$Path)
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
function Get-Fingerprint {
    param([Parameter(Mandatory)][string[]]$Lines)
    [Array]::Sort($Lines, [StringComparer]::Ordinal)
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData(
        [Text.UTF8Encoding]::new($false).GetBytes(($Lines -join "`n"))
    )).ToLowerInvariant()
}
$sourceInventory = Get-BsoRsCanonicalSourceInventory -RepositoryRoot $root
$rootFingerprintLines = foreach ($rootComponent in $roots) {
    '{0}|{1}|{2}' -f $rootComponent.GetAttribute('type'),
        $rootComponent.GetAttribute('id'), $rootComponent.GetAttribute('schemaName')
}
$releaseToolPaths = @(
    $releaseInputs.releaseTooling.builder,
    $releaseInputs.releaseTooling.testRehearsalGate,
    $releaseInputs.releaseTooling.solutionImportGate,
    $releaseInputs.releaseTooling.configurationGenerator,
    $releaseInputs.releaseTooling.inventoryGenerator,
    $releaseInputs.releaseTooling.packageUpdater,
    $releaseInputs.releaseTooling.canonicalSourceFingerprintTool,
    $releaseInputs.releaseTooling.testTargetAuthorizationValidator
)
$releaseToolLines = foreach ($relativeTool in $releaseToolPaths) {
    $fullToolPath = Join-Path $docs ($relativeTool.Replace('/', '\'))
    "$relativeTool|$(Get-FileSha256 -Path $fullToolPath)"
}
Assert-Test ($sourceInventory.FileCount -eq $releaseInputs.canonicalSource.sourceFileCount -and
    $sourceInventory.Algorithm -ceq $releaseInputs.canonicalSource.sourceFingerprintAlgorithm -and
    $sourceInventory.Fingerprint -ceq $releaseInputs.canonicalSource.sourceFingerprint -and
    (Get-Fingerprint -Lines $rootFingerprintLines) -ceq $releaseInputs.canonicalSource.rootComponentFingerprint -and
    (Get-FileSha256 -Path (Join-Path $solutions 'Other\Solution.xml')) -ceq
        $releaseInputs.canonicalSource.rootManifestSha256) `
    'Verify the frozen canonical source and root-component fingerprints'
Assert-Test ((Get-FileSha256 -Path (Join-Path $solutions 'release-profiles.json')) -ceq
    $releaseInputs.environmentPolicy.portableProfileSourceSha256 -and
    (Get-FileSha256 -Path (Join-Path $solutions 'pluginpackages\os_sr_cact_pkg\package\os_sr_cact_pkg.nupkg')) -ceq
        $releaseInputs.candidateCore.packageSha256 -and
    (Get-FileSha256 -Path (Join-Path $root 'scripts\Update-BsoRsCandidatePluginPackage.ps1')) -ceq
        $releaseInputs.releaseTooling.packageUpdaterSha256 -and
    (Get-FileSha256 -Path (Join-Path $root 'scripts\BsoRsCanonicalSourceFingerprint.psm1')) -ceq
        $releaseInputs.releaseTooling.canonicalSourceFingerprintToolSha256 -and
    (Get-FileSha256 -Path (Join-Path $root 'scripts\BsoRsTestTargetAuthorization.psm1')) -ceq
        $releaseInputs.releaseTooling.testTargetAuthorizationValidatorSha256 -and
    (Get-Fingerprint -Lines $releaseToolLines) -ceq $releaseInputs.releaseTooling.toolFingerprint) `
    'Verify pinned environment-policy, package, and release-tooling inputs'
foreach ($resource in $releaseInputs.candidateConsole.PSObject.Properties) {
    $resourcePath = Join-Path $webRoot $resource.Name
    Assert-Test ((Get-FileSha256 -Path $resourcePath) -ceq $resource.Value) `
        "Verify frozen Candidate Console resource hash: $($resource.Name)"
}

Assert-Test ($updaterContract.status -ceq 'OFFLINE_DISPATCHER_IMPLEMENTED_NOT_EXECUTED' -and
    $updaterContract.target.pacWhoAmIAgreementRequired -eq $true -and
    $updaterContract.target.approvedTestTargetEvidenceRequired -eq $true -and
    $updaterContract.package.exactExistingPackageLookupRequired -eq $true -and
    $updaterContract.package.createAllowed -eq $false -and
    $updaterContract.package.modifiedOnRequired -eq $false -and
    $updaterContract.package.serverReadablePackageBytesRequired -eq $false -and
    $updaterContract.dispatch.automaticRetries -eq 0 -and
    $updaterContract.dispatch.ambiguousOutcomeStopsBeforeAnyResend -eq $true -and
    $updaterContract.dispatch.signingKeyPathAllowed -eq $false -and
    $updaterContract.dispatch.legacyAssemblyWriteAllowed -eq $false -and
    $updaterContract.dispatch.protectCandidateCoreMutationAllowed -eq $false) `
    'Verify the one-shot package-updater contract and zero-retry target gates'
$legacyPackageScript = Get-Content -LiteralPath (Join-Path $root 'scripts\Deploy-BsoRsCandidatePluginPackage.ps1') -Raw
Assert-Test ($legacyPackageScript -match "Invoke-PackageRequest -Method POST -Path 'pluginpackages'" -and
    $legacyPackageScript -notmatch "Invoke-PackageRequest -Method PATCH -Path 'pluginpackages'|Method = 'PATCH'\s+Path = 'pluginpackages'") `
    'Diagnose the legacy package-create path rather than treating it as an updater'
Assert-Test ($updaterContract.offlineValidation.classification -ceq 'PACKAGE_RELEASE_UPDATER_OFFLINE_READY_IMPLEMENTED' -and
    $updaterContract.offlineValidation.dispatcherImplemented -eq $true -and
    $updaterContract.offlineValidation.packagePushPerformed -eq $false -and
    (Test-Path -LiteralPath (Join-Path $root 'scripts\Update-BsoRsCandidatePluginPackage.ps1')) -and
    (Test-Path -LiteralPath (Join-Path $root 'tests\BsoRsCandidatePackageUpdater.Tests.ps1'))) `
    'Distinguish local updater implementation from any live package update'

Assert-Test ($importContract.import.publishAllXml -eq $false -and
    $importContract.import.forceOverwrite -eq $false -and
    $importContract.import.dependencyBypass -eq $false -and
    $importContract.import.retriesOnAmbiguousWrite -eq 0 -and
    $importContract.import.postImportReadOnlyReconciliationMandatory -eq $true) `
    'Require no PublishAllXml, blind overwrite, dependency bypass, or ambiguous retry'
Assert-Test ($importContract.boundedTestRehearsal.productionGovernanceGatesApply -eq $false -and
    $importContract.boundedTestRehearsal.realDataAllowed -eq $false -and
    $releaseInputs.releaseConstraints.boundedTestRehearsalAuthorized -eq $true -and
    $releaseInputs.releaseConstraints.testDeploymentIdentityUseApproved -eq $true -and
    $releaseInputs.releaseConstraints.testRecoveryProcedureApproved -eq $true -and
    $releaseInputs.releaseConstraints.productionOperationsAuthorized -eq $false) `
    'Separate bounded Test authorization from Production-only gates and real-data restrictions'
$testGatePath = Join-Path $root 'scripts\Test-BsoRsTestRehearsalGate.ps1'
$importGatePath = Join-Path $root 'scripts\Test-BsoRsSolutionImportGate.ps1'
$testGateSource = Get-Content -LiteralPath $testGatePath -Raw
$importGateSource = Get-Content -LiteralPath $importGatePath -Raw
Assert-Test ($testGateSource -notmatch '\bpac\b|Invoke-WebRequest|Invoke-RestMethod|solution import' -and
    $importGateSource -notmatch '\bpac\b|Invoke-WebRequest|Invoke-RestMethod|solution import') `
    'Offline Test and import gates contain no connection or import execution path'

$authorizationEvidencePath = Join-Path ([IO.Path]::GetTempPath()) "bso-rs-target-authorization-$([Guid]::NewGuid().ToString('N')).json"
$authorizationEvidence = [ordered]@{
    purpose = 'BSO-RS-Support Test rehearsal'
    targetDisplayName = 'LMV BI DEV'
    authorizationScope = 'BOUNDED_TEST_REHEARSAL'
    syntheticDataPermitted = $true
    productionOperationsProhibited = $true
    unrelatedEnvironmentResourcesProhibited = $true
    approvalSource = 'Explicit owner instruction in current project/session'
    approvalStatus = 'APPROVED'
}
try {
    [IO.File]::WriteAllText(
        $authorizationEvidencePath,
        (ConvertTo-Json -InputObject $authorizationEvidence -Depth 4),
        [Text.UTF8Encoding]::new($false)
    )
    $authorizedTestResult = & $testGatePath -TestTargetAuthorizationEvidencePath $authorizationEvidencePath
    Assert-Test ($authorizedTestResult.Result -ceq 'TEST_TARGET_APPROVAL_EVIDENCE_SATISFIED' -and
        $authorizedTestResult.Gate -ceq 'TEST_RELEASE_READINESS_EVIDENCE_REQUIRED' -and
        $authorizedTestResult.NetworkOperations -eq 0 -and
        $authorizedTestResult.Imports -eq 0 -and
        $authorizedTestResult.RequiredNextEvidence -contains 'APPROVED_TEST_MANAGED_ARTIFACT') `
        'Recognize owner authorization while keeping release artifact and recovery gates distinct'

    $authorizedImportResult = & $importGatePath -Mode TEST `
        -TestTargetAuthorizationEvidencePath $authorizationEvidencePath
    Assert-Test ($authorizedImportResult.Result -ceq 'TEST_TARGET_APPROVAL_EVIDENCE_SATISFIED' -and
        $authorizedImportResult.Gate -ceq 'TEST_RELEASE_READINESS_EVIDENCE_REQUIRED' -and
        $authorizedImportResult.NetworkOperations -eq 0 -and
        $authorizedImportResult.Imports -eq 0) `
        'Do not label the owner authorization missing when the import gate lacks separate release evidence'

    $managedArtifactPath = Join-Path ([IO.Path]::GetTempPath()) "bso-rs-test-artifact-hash-fixture-$([Guid]::NewGuid().ToString('N')).txt"
    $testApprovalPath = Join-Path ([IO.Path]::GetTempPath()) "bso-rs-test-approval-$([Guid]::NewGuid().ToString('N')).json"
    $testApprovalArtifactBytes = [Text.Encoding]::UTF8.GetBytes('synthetic hash fixture; not a solution package')
    [IO.File]::WriteAllBytes($managedArtifactPath, $testApprovalArtifactBytes)
    $testApproval = [ordered]@{
        mode = 'TEST'
        environmentDisplayName = 'LMV BI DEV'
        region = 'EMEA'
        environmentId = '11111111-1111-4111-8111-111111111111'
        organizationId = '22222222-2222-4222-8222-222222222222'
        organizationUrl = 'https://test.example.invalid'
        isProductionBusinessRuntime = $false
        ownerApproved = $true
        importApproved = $true
        authorizedDeploymentIdentityApproved = $true
        pacWhoAmIAgreement = $true
        dataverseWhoAmIAgreement = $true
        targetIdentityVerified = $true
        candidateCoreEnabled = $true
        syntheticDataOnly = $true
        devDirectWriteFallbackEnabled = $false
        diagnosticsMode = 'OFF'
        solutionUniqueName = 'os_sr_bso_rs_support'
        solutionVersion = '1.0.0.0'
        artifactOrigin = 'APPROVED_TEST_BUILD'
        artifactReleaseable = $true
        managedArtifactSha256 = (Get-FileHash -LiteralPath $managedArtifactPath -Algorithm SHA256).Hash.ToLowerInvariant()
        releaseApprovalEvidencePresent = $false
        backupRecoveryGateComplete = $true
        rollbackCleanupOwnerApproved = $true
    }
    try {
        [IO.File]::WriteAllText(
            $testApprovalPath,
            (ConvertTo-Json -InputObject $testApproval -Depth 4),
            [Text.UTF8Encoding]::new($false)
        )
        $testImportReady = & $importGatePath -Mode TEST `
            -TestTargetAuthorizationEvidencePath $authorizationEvidencePath `
            -ApprovalEvidencePath $testApprovalPath `
            -ManagedArtifactPath $managedArtifactPath
        Assert-Test ($testImportReady.Result -ceq 'TEST_IMPORT_PREFLIGHT_READY_NOT_EXECUTED' -and
            $testImportReady.NetworkOperations -eq 0 -and
            $testImportReady.Imports -eq 0) `
            'Allow bounded synthetic Test import without Production governance, migration, or BSO identity approvals'

        [IO.File]::WriteAllText(
            $testApprovalPath,
            (ConvertTo-Json -InputObject $testApproval -Depth 4),
            [Text.UTF8Encoding]::new($false)
        )
        $testRehearsalReady = & $testGatePath `
            -TestTargetAuthorizationEvidencePath $authorizationEvidencePath `
            -TestApprovalEvidencePath $testApprovalPath `
            -ManagedArtifactPath $managedArtifactPath
        Assert-Test ($testRehearsalReady.Result -ceq 'TEST_REHEARSAL_PREFLIGHT_READY_NOT_EXECUTED' -and
            $testRehearsalReady.NetworkOperations -eq 0 -and
            $testRehearsalReady.Imports -eq 0 -and
            $testRehearsalReady.RuntimeTests -eq 0) `
            'Keep clean BSO test identity selection after managed topology reconciliation'

        $testApproval.testEnvironmentPolicyStatus = 'PROHIBITED'
        $testApproval.testEnvironmentPolicyEvidenceVerified = $true
        [IO.File]::WriteAllText(
            $testApprovalPath,
            (ConvertTo-Json -InputObject $testApproval -Depth 4),
            [Text.UTF8Encoding]::new($false)
        )
        $testPolicyRejected = $false
        try {
            $null = & $importGatePath -Mode TEST `
                -TestTargetAuthorizationEvidencePath $authorizationEvidencePath `
                -ApprovalEvidencePath $testApprovalPath `
                -ManagedArtifactPath $managedArtifactPath
        } catch {
            $testPolicyRejected = $_.Exception.Message -like '*does not satisfy the explicit target, artifact, and release gates*'
        }
        Assert-Test $testPolicyRejected 'Block Test import only when verified environment policy prohibits synthetic operation'

        $testApproval.mode = 'PROD'
        $testApproval.isProductionBusinessRuntime = $true
        $testApproval.productionApprovalEvidencePresent = $true
        [IO.File]::WriteAllText(
            $testApprovalPath,
            (ConvertTo-Json -InputObject $testApproval -Depth 4),
            [Text.UTF8Encoding]::new($false)
        )
        $productionGateRejected = $false
        try {
            $null = & $importGatePath -Mode PROD `
                -ApprovalEvidencePath $testApprovalPath `
                -ManagedArtifactPath $managedArtifactPath
        } catch {
            $productionGateRejected = $_.Exception.Message -like '*does not satisfy the explicit target, artifact, and release gates*'
        }
        Assert-Test $productionGateRejected 'Continue requiring separate Production security, governance, and migration approvals'
    } finally {
        foreach ($path in @($testApprovalPath, $managedArtifactPath)) {
            if (Test-Path -LiteralPath $path) {
                Remove-Item -LiteralPath $path -Force
            }
        }
    }
} finally {
    if (Test-Path -LiteralPath $authorizationEvidencePath) {
        Remove-Item -LiteralPath $authorizationEvidencePath -Force
    }
}

$missingTestResult = & $testGatePath
Assert-Test ($missingTestResult.Result -ceq 'TEST_REHEARSAL_RUNNER_READY_TARGET_REQUIRED' -and
    $missingTestResult.Gate -ceq 'TEST_TARGET_APPROVAL_REQUIRED' -and
    $missingTestResult.NetworkOperations -eq 0 -and $missingTestResult.Imports -eq 0) `
    'Fail closed without Test approval evidence and report target-required readiness'
Assert-Test ($testGateSource -match "artifactOrigin -cnotin @\('CANONICAL_SOURCE', 'APPROVED_TEST_BUILD'\)" -and
    $importGateSource -match "artifactOrigin -cin @\('CANONICAL_SOURCE', 'APPROVED_TEST_BUILD'\)") `
    'Reject DEV-origin and unknown artifact provenance in both release gates'

$missingImportResult = & $importGatePath -Mode TEST
Assert-Test ($missingImportResult.Result -ceq 'TEST_TARGET_APPROVAL_REQUIRED' -and
    $missingImportResult.NetworkOperations -eq 0 -and $missingImportResult.Imports -eq 0) `
    'Refuse Solution import preflight without target evidence'
$missingProductionImportResult = & $importGatePath -Mode PROD
Assert-Test ($missingProductionImportResult.Result -ceq 'PRODUCTION_APPROVAL_REQUIRED' -and
    $missingProductionImportResult.NetworkOperations -eq 0 -and
    $missingProductionImportResult.Imports -eq 0) `
    'Require separate Production approval without connecting or importing'

Assert-Test ($rollback.rollbackPlan.offlinePlanStatus -ceq 'ROLLBACK_PLAN_OFFLINE_READY' -and
    $rollback.rollbackPlan.runtimeRollbackStatus -ceq 'ROLLBACK_EVIDENCE_REQUIRED_BEFORE_IMPORT' -and
    $rollback.rollbackPlan.evidence.runtimeRecoveryRehearsed -eq $false -and
    @($rollback.rollbackPlan.decisionTree | Where-Object { $_.ifFalse -match '^STOP' }).Count -eq
    $rollback.rollbackPlan.decisionTree.Count) `
    'Require every rollback predicate to stop before recovery when evidence is missing'

Write-Output "BSO-RS production-readiness offline checks passed: $passed"
[pscustomobject]@{
    SourceInventory = 'SOLUTION_COMPONENT_COUNT_SEMANTICS_RECONCILED_AND_MEMBERSHIP_CLEANUP_VERIFIED'
    PortableConfiguration = 'PORTABLE_ENVIRONMENT_CONFIGURATION_OFFLINE_VERIFIED'
    ManagedArtifact = 'MANAGED_RELEASE_ARTIFACT_REQUIRES_APPROVED_TEST_REHEARSAL'
    PackageUpdater = 'PACKAGE_RELEASE_UPDATER_OFFLINE_READY_IMPLEMENTED'
    PackageUpdaterDispatcher = 'IMPLEMENTED_NOT_EXECUTED'
    RemainingBlockers = 'EXTERNAL_GATES_ONLY'
    SolutionImportGate = 'SOLUTION_IMPORT_GATE_OFFLINE_READY'
    TestRehearsal = 'TEST_RELEASE_READINESS_EVIDENCE_REQUIRED'
    RollbackPlan = 'ROLLBACK_PLAN_OFFLINE_READY'
    TestTarget = 'TEST_TARGET_APPROVAL_EVIDENCE_SATISFIED'
    ClosedTechnicalBlocker = 'PKG-001'
}
