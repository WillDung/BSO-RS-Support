#requires -Version 7.4
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Split-Path $PSScriptRoot -Parent
$solutions = Join-Path $root 'solutions'
$docs = Join-Path $root 'docs'
$profilesPath = Join-Path $solutions 'release-profiles.json'
$inventoryPath = Join-Path $docs 'SOLUTION_COMPONENT_INVENTORY.json'
$artifactPath = Join-Path $docs 'RELEASE_ARTIFACTS.json'
$rollbackPath = Join-Path $docs 'ROLLBACK_MANIFEST.json'
$updaterPath = Join-Path $docs 'RELEASE_UPDATER_CONTRACT.json'
$solutionManifestPath = Join-Path $solutions 'Other\Solution.xml'
$buildPath = Join-Path $root 'scripts\Build-BsoRsPortableSolution.ps1'
$gatePath = Join-Path $root 'scripts\Test-BsoRsTestRehearsalGate.ps1'
$solutionManifest = [xml][IO.File]::ReadAllText($solutionManifestPath)
$roots = @($solutionManifest.SelectNodes('//*[local-name()="RootComponent"]'))
$passed = 0

function Assert-Test {
    param([bool]$Condition, [string]$Name)
    if (-not $Condition) { throw "FAIL: $Name" }
    $script:passed++
}

function Get-RootKey {
    param([string]$Type, [string]$Id, [string]$SchemaName)
    if (-not [string]::IsNullOrWhiteSpace($Id)) {
        return '{0}|id:{1}' -f $Type, $Id.Trim('{}').ToLowerInvariant()
    }
    if (-not [string]::IsNullOrWhiteSpace($SchemaName)) {
        return '{0}|name:{1}' -f $Type, $SchemaName.ToLowerInvariant()
    }
    throw 'A Solution root must have an identity or schema name.'
}

$profiles = Get-Content -LiteralPath $profilesPath -Raw | ConvertFrom-Json
Assert-Test ($profiles.profiles.PSObject.Properties.Name -join ',' -ceq 'DEV,TEST,PROD') `
    'Portable profiles define DEV, TEST, and PROD'
foreach ($profileName in @('DEV', 'TEST', 'PROD')) {
    $profile = $profiles.profiles.$profileName
    Assert-Test ($null -eq $profile.organizationUrl -and
        $null -eq $profile.environmentId -and
        $null -eq $profile.organizationId -and
        $profile.candidateCoreEnabled -eq $true -and
        $profile.syntheticDataOnly -eq $true -and
        $profile.devDirectWriteFallbackEnabled -eq $false -and
        $profile.diagnosticsMode -ceq 'OFF') "Profile $profileName has no invented target and fails closed"
}

$inventory = Get-Content -LiteralPath $inventoryPath -Raw | ConvertFrom-Json
Assert-Test ($inventory.rootComponentCount -eq 72 -and $inventory.components.Count -eq 72) `
    'Inventory maps all 72 export root components'
$authoredRootKeys = [string[]]@($roots | ForEach-Object {
    Get-RootKey -Type $_.GetAttribute('type') -Id $_.GetAttribute('id') `
        -SchemaName $_.GetAttribute('schemaName')
})
[xml]$referenceRole = Get-Content -Raw -LiteralPath (Join-Path $solutions 'Roles\BSO-RS Support - Reference Admin.xml')
$referenceRoleKey = Get-RootKey -Type '20' -Id $referenceRole.Role.id
$frozenAuthoredRootKeys = [string[]]@($authoredRootKeys | Where-Object { $_ -cne $referenceRoleKey })
Assert-Test ($authoredRootKeys.Count -eq 21 -and
    @($authoredRootKeys | Where-Object { $_ -ceq $referenceRoleKey }).Count -eq 1 -and
    $frozenAuthoredRootKeys.Count -eq 20) `
    'P0 adds only the exported Reference Admin role root; frozen release remains twenty authored roots'
$referencePrivileges = @($referenceRole.Role.RolePrivileges.RolePrivilege)
$expectedReferencePrivileges = @(
    foreach ($table in 'os_sr_ta', 'os_sr_pos', 'os_sr_csrc', 'os_sr_loc') {
        foreach ($operation in 'Create', 'Read', 'Write', 'Append', 'AppendTo') { "prv$operation$table" }
    }
)
Assert-Test ($referenceRole.Role.IsAutoAssigned -eq '0' -and $referencePrivileges.Count -eq 20 -and
    @($referencePrivileges | Where-Object { $_.name -notin $expectedReferencePrivileges -or $_.level -cne 'Global' }).Count -eq 0 -and
    @($expectedReferencePrivileges | Where-Object { $_ -notin $referencePrivileges.name }).Count -eq 0) `
    'Reference Admin has exactly twenty global four-table privileges and no Core, Delete, SharePoint, or admin grants'
$apiContract = Get-Content -Raw -LiteralPath (Join-Path $docs 'PHASE_3C_API_CONTRACT.json') | ConvertFrom-Json
$requestMetadata = @(Get-ChildItem -LiteralPath (Join-Path $solutions 'customapis\os_sr_cact\customapirequestparameters') -Recurse -Filter '*.xml' |
    ForEach-Object { ([xml](Get-Content -Raw -LiteralPath $_.FullName)).customapirequestparameter })
Assert-Test ($requestMetadata.Count -eq 21 -and @($requestMetadata.uniquename | Select-Object -Unique).Count -eq 21 -and
    @($apiContract.inputs | Where-Object {
        $contractParameter = $_
        $match = @($requestMetadata | Where-Object { $_.uniquename -ceq $contractParameter.name })
        $match.Count -ne 1 -or [int]$match[0].type -ne $contractParameter.type -or
            [bool][int]$match[0].isoptional -ne $contractParameter.optional
    }).Count -eq 0 -and
    (Get-ChildItem -LiteralPath (Join-Path $solutions 'customapis\os_sr_cact\customapiresponseproperties') -Recurse -Filter '*.xml').Count -eq 5) `
    'Actual exported API source matches all twenty declared inputs and retains five responses without duplicates'
$generatedAssembly = @($inventory.components | Where-Object {
    $_.type -eq 91 -and $_.disposition -ceq 'GENERATED_FROM_CANONICAL_SOURCE'
})
Assert-Test ($generatedAssembly.Count -eq 1 -and
    $generatedAssembly[0].id -ceq 'd71c6048-4fd0-f111-a05a-002248a1ba20' -and
    $generatedAssembly[0].name -match 'PublicKeyToken=null') `
    'Identify the exact unsigned package-generated PluginAssembly root'
function Test-ExpectedReleaseRootSet {
    param([string[]]$RootKeys, [string[]]$AuthoredKeys, [string]$GeneratedRootKey)
    $expectedKeys = [string[]]@($AuthoredKeys + $GeneratedRootKey)
    if ($RootKeys.Count -ne 21 -or @($RootKeys | Select-Object -Unique).Count -ne 21) {
        return $false
    }
    return @(Compare-Object -ReferenceObject $expectedKeys -DifferenceObject $RootKeys).Count -eq 0
}
$expectedGeneratedRootKey = Get-RootKey -Type ([string]$generatedAssembly[0].type) `
    -Id ([string]$generatedAssembly[0].id) -SchemaName ([string]$generatedAssembly[0].schemaName)
Assert-Test (Test-ExpectedReleaseRootSet `
    -RootKeys ([string[]]@($frozenAuthoredRootKeys + $expectedGeneratedRootKey)) `
    -AuthoredKeys $frozenAuthoredRootKeys -GeneratedRootKey $expectedGeneratedRootKey) `
    'Accept exactly 20 authored roots plus the one expected package-generated root'
Assert-Test (-not (Test-ExpectedReleaseRootSet `
    -RootKeys ([string[]]@($frozenAuthoredRootKeys + '91|id:11111111-1111-1111-1111-111111111111')) `
    -AuthoredKeys $frozenAuthoredRootKeys -GeneratedRootKey $expectedGeneratedRootKey)) `
    'Reject a different 21st root even when the artifact root count is 21'
$expectedCounts = @{
    '1' = 10
    '9' = 2
    '20' = 1
    '61' = 5
    '62' = 1
    '80' = 1
    '91' = 2
    '92' = 50
}
foreach ($componentType in $expectedCounts.Keys) {
    $count = @($inventory.components | Where-Object { $_.type -eq [int]$componentType }).Count
    Assert-Test ($count -eq $expectedCounts[$componentType]) "Inventory maps component type $componentType"
}
Assert-Test ($inventory.releaseDisposition.authoredCanonicalRoots -eq 20 -and
    $inventory.releaseDisposition.generatedPackageAssemblyRoots -eq 1 -and
    $inventory.releaseDisposition.expectedLiveAndExportReleaseRoots -eq 21 -and
    $inventory.releaseDisposition.excludedInactiveProtectCandidateCoreSteps -eq 50 -and
    $inventory.releaseDisposition.excludedSignedRollbackAssembly -eq 1 -and
    $inventory.releaseDisposition.excludedRoots -eq 51 -and
    @($inventory.components | Where-Object {
        $_.disposition -eq 'RETAINED_SOURCE'
    }).Count -eq 20 -and
    @($inventory.components | Where-Object {
        $_.disposition -eq 'GENERATED_FROM_CANONICAL_SOURCE'
    }).Count -eq 1 -and
    @($inventory.components | Where-Object {
        $_.disposition -in @('ROLLBACK_ONLY_SIGNED_ASSEMBLY_NOT_RETAINED',
            'INACTIVE_PROTECTCANDIDATECORE_GUARD_EXCLUDED_FROM_RELEASE')
    }).Count -eq 51) `
    'Inventory separates 20 authored, one generated, and 51 excluded roots'
Assert-Test ($inventory.additionalSourceAreas.customApiFilesInExport -eq 39 -and
    $inventory.additionalSourceAreas.retainedCandidateCoreApiFiles -eq 24 -and
    $inventory.additionalSourceAreas.excludedTemporaryDevApiFiles -eq 15 -and
    $inventory.additionalSourceAreas.entityMetadataFiles -eq 110 -and
    $inventory.additionalSourceAreas.webResourceMetadataFiles -eq 5) `
    'Inventory reconciles API, entity metadata, and web-resource detail files'
Assert-Test (@($inventory.components | Where-Object {
    $_.type -eq 92 -and $_.disposition -ceq 'INACTIVE_PROTECTCANDIDATECORE_GUARD_EXCLUDED_FROM_RELEASE'
}).Count -eq 50) 'All 50 guard registrations are explicitly classified as excluded'

$artifact = Get-Content -LiteralPath $artifactPath -Raw | ConvertFrom-Json
$rollback = Get-Content -LiteralPath $rollbackPath -Raw | ConvertFrom-Json
$updater = Get-Content -LiteralPath $updaterPath -Raw | ConvertFrom-Json
$gateSource = Get-Content -LiteralPath $gatePath -Raw
Assert-Test ($artifact.activeCandidateCore.packageSha256 -ceq
    'dbf6087203508c8a0016fede8bea2c77a3734a9e294b407197faa08235203b91' -and
    $artifact.activeCandidateCore.assemblySha256 -ceq
    '05e983e86290bb70ba82b73177c21dc3a1d87fd14f0d4aeea39af062ed0a721a' -and
    $artifact.activeCandidateCore.publicKeyToken -eq $null) 'Accepted unsigned package and assembly hashes are pinned'
Assert-Test ($artifact.activeCandidateCore.source -ceq
    '../solutions/pluginpackages/os_sr_cact_pkg/package/os_sr_cact_pkg.nupkg' -and
    (Test-Path -LiteralPath (Join-Path $solutions 'pluginpackages\os_sr_cact_pkg\pluginpackage.xml'))) `
    'The existing package component and metadata are retained as the pinned solution payload'
Assert-Test ($rollback.status -ceq 'ROLLBACK_ONLY_NOT_ACTIVE' -and
    $rollback.mutationAllowed -eq $false -and $rollback.activationAllowed -eq $false -and
    $rollback.sha256 -ceq
    '089deb40816e7fd6d80d117ba3894b5d5dadbcf65ac8111e25bb0520ff6feb85') `
    'Signed rollback assembly is hash-pinned and prohibited from activation or mutation'
Assert-Test ($updater.status -ceq 'OFFLINE_DISPATCHER_IMPLEMENTED_NOT_EXECUTED' -and
    $updater.target.mode -ceq 'TEST_OR_PROD' -and
    @($updater.target.supportedModes) -contains 'TEST' -and
    @($updater.target.supportedModes) -contains 'PROD' -and
    $null -eq $updater.target.organizationUrl -and
    $null -eq $updater.target.environmentId -and
    $null -eq $updater.target.organizationId -and
    $updater.package.createAllowed -eq $false -and
    $updater.dispatch.maximumPackageUpdates -eq 1 -and
    $updater.dispatch.automaticRetries -eq 0 -and
    $updater.ambiguousOutcome.automaticResendAllowed -eq $false -and
    $updater.ambiguousOutcome.reconciliationMode -ceq 'GET_ONLY' -and
    $updater.ambiguousOutcome.inconclusiveClassification -ceq 'READ_ONLY_RECONCILIATION_COMPLETE_OUTCOME_STILL_AMBIGUOUS' -and
    $updater.offlineValidation.classification -ceq 'PACKAGE_RELEASE_UPDATER_OFFLINE_READY_IMPLEMENTED' -and
    $updater.offlineValidation.dispatcherImplemented -eq $true -and
    $updater.offlineValidation.packagePushPerformed -eq $false) `
    'Release updater contract is existing-package-only and never resends ambiguous writes'
Assert-Test ($profiles.managedBuild -ceq 'MANAGED_RELEASE_ARTIFACT_REQUIRES_APPROVED_TEST_REHEARSAL' -and
    $artifact.releaseConstraints.managedBuild -ceq 'MANAGED_RELEASE_ARTIFACT_REQUIRES_APPROVED_TEST_REHEARSAL') `
    'Managed promotion remains blocked without an approved Test environment'

$gateResult = @(& $gatePath)
Assert-Test ($gateResult.Result -ceq 'TEST_REHEARSAL_RUNNER_READY_TARGET_REQUIRED' -and
    $gateResult.Gate -ceq 'TEST_TARGET_APPROVAL_REQUIRED' -and
    $gateResult.NetworkOperations -eq 0 -and $gateResult.Imports -eq 0 -and
    $gateSource.Contains("CandidateCorePackageUpdater = '../scripts/Update-BsoRsCandidatePluginPackage.ps1'") -and
    $gateSource.Contains("'CANDIDATE_CORE_PACKAGE_UPDATER_PREFLIGHT'")) `
    'Offline Test gate stops without target evidence and performs no connection or import'
Assert-Test ($gateSource -notmatch '\bpac\b|Invoke-WebRequest|Invoke-RestMethod|solution import') `
    'Test rehearsal gate has no network or import execution path'

Assert-Test ($roots.Count -eq 21 -and
    @($roots | Where-Object { $_.GetAttribute('type') -in @('91', '92') }).Count -eq 0) `
    'Canonical release manifest excludes assembly registrations and all guard steps'
Assert-Test (-not (Test-Path -LiteralPath (Join-Path $solutions 'SdkMessageProcessingSteps')) -and
    -not (Test-Path -LiteralPath (Join-Path $solutions 'PluginAssemblies')) -and
    -not (Test-Path -LiteralPath (Join-Path $solutions 'customapis\os_sr_devcs'))) `
    'Canonical source excludes inactive guards, the signed assembly, and temporary DEV API'

$canonicalSourceModule = Join-Path $root 'scripts\BsoRsCanonicalSourceFingerprint.psm1'
Import-Module $canonicalSourceModule -Force
$canonicalSourceInventory = Get-BsoRsCanonicalSourceInventory -RepositoryRoot $root
$sourceFiles = @($canonicalSourceInventory.Files | Where-Object {
    [IO.Path]::GetExtension($_.FullPath) -in @('.xml', '.json', '.js', '.html', '.css')
})
$releaseText = ($sourceFiles | ForEach-Object { [IO.File]::ReadAllText($_.FullPath) }) -join "`n"
Assert-Test ($releaseText -notmatch '(?i)\bVN LMV IT\b|https://[a-z0-9-]+\.crm\d+\.dynamics\.com|organizationUrl:\s*"https?://' -and
    $releaseText -notmatch '(?i)\bBearer\s+[A-Za-z0-9._~-]{20,}|client_secret\s*[:=]|password\s*[:=]') `
    'Canonical release source contains no DEV target configuration or credential-like values'

$temporaryZip = Join-Path ([IO.Path]::GetTempPath()) "bso-rs-release-test-$([Guid]::NewGuid().ToString('N')).zip"
try {
    $buildRejected = $false
    try {
        & $buildPath -OutputPath $temporaryZip | Out-Null
    } catch {
        if ($_.Exception.Message -cne 'Release manifest must contain exactly the 20 approved roots and no assembly or guard registrations.') {
            throw
        }
        $buildRejected = $true
    }
    Assert-Test ($buildRejected -and -not (Test-Path -LiteralPath $temporaryZip)) `
        'Frozen release builder rejects source-ahead P0 roots before packing; no release artifact is rebuilt'
} finally {
    if (Test-Path -LiteralPath $temporaryZip) {
        Remove-Item -LiteralPath $temporaryZip -Force
    }
}

Write-Output "BSO-RS release source checks passed: $passed"
