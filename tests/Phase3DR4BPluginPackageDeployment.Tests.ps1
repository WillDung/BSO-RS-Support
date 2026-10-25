#requires -Version 7.4
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$deploymentPath = Join-Path $root 'scripts\Deploy-BsoRsCandidatePluginPackage.ps1'
$runtimePath = Join-Path $root 'scripts\Test-BsoRsCandidateCoreRuntime.ps1'
$packageTests = Join-Path $PSScriptRoot 'Phase3DR4PluginPackage.Tests.ps1'
$contract = Get-Content -Raw (Join-Path $root 'docs\PHASE_3C_API_CONTRACT.json') | ConvertFrom-Json
$deployment = Get-Content -Raw $deploymentPath
$runtime = Get-Content -Raw $runtimePath
$script:Passed = 0

function Assert-Test([bool]$Condition, [string]$Name) {
    if (-not $Condition) { throw "FAIL: $Name" }
    $script:Passed++
}

foreach ($path in @($deploymentPath, $runtimePath)) {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors) | Out-Null
    Assert-Test ($errors.Count -eq 0) "PowerShell parses: $(Split-Path $path -Leaf)"
}

Assert-Test ($deployment -match "ValidateSet\('Preflight', 'Apply', 'InspectPackage', 'Reconcile', 'Rollback'," -and
    $deployment -match "'CutoverExistingPreflight', 'CutoverExistingApply', 'RollbackExistingCutover'\)" -and
    $deployment -match "Name = 'os_sr_cact_pkg'" -and $deployment -match "Version = '1\.0\.0'") 'Package deployment modes and identity are pinned'
Assert-Test ($deployment -match [regex]::Escape('41a18a66aabf0c75356209e6814d93f60aa6d4dc2eebd3a965d9291b3bb8b59b') -and
    $deployment -match [regex]::Escape('ba332f58c55c8c13b8eb44df619b8236022f78261b7a02099890b3281a88aaf1') -and
    $deployment -match [regex]::Escape('86332729d1956f61ec7a282b1831ae81c044ee120a1689772017feb014ba17f0')) 'Frozen package, DLL, and inventory fingerprints are enforced'
Assert-Test ($deployment -match 'MaximumRetryCount = 0' -and $deployment -match 'MaximumRedirection = 0' -and
    $deployment -match 'AutomaticRetries = 0' -and $deployment -match 'RollbackAutomaticRetries = 0') 'All deployment and rollback writes disable automatic retries'
Assert-Test ($deployment -match 'MaximumPackagePosts = 1' -and $deployment -match 'MaximumHandlerPatches = 1' -and
    $deployment -match "Path -cne 'pluginpackages'" -and $deployment -match 'MSCRM.SolutionUniqueName') 'Only one package create and one authorized API handler patch are allowed'
Assert-Test ($deployment -match 'name = \$script:PackageIdentity.Name' -and
    $deployment -match 'uniquename = \$script:PackageIdentity.UniqueName' -and
    $deployment -match 'version = \$script:PackageIdentity.Version' -and
    $deployment -match 'content = \[Convert\]::ToBase64String' -and
    $deployment -notmatch "Method POST -Path 'pluginassemblies'") 'Package upload contains exact package bytes, not assembly content'
Assert-Test ($deployment -match 'FileMode\]::CreateNew' -and
    $deployment -match "State = 'DISPATCH_RESERVED'" -and
    $deployment -match 'Get-PackageRowsByName' -and
    $deployment.IndexOf("Invoke-PackageRequest -Method POST -Path 'pluginpackages'") -lt
$deployment.LastIndexOf('$packages = @(Get-PackageRowsByName)')) 'One-shot journal precedes immediate exact-name package reconciliation'
Assert-Test ($deployment -match 'Assert-PackageReadback' -and
    $deployment -match 'Live Plug-in Package content hash differs' -and
    $deployment -match 'Assert-PackageSolutionMembership') 'Package metadata, bytes, and Solution membership are GET-reconciled'
Assert-Test ($deployment -match 'if \(\$Mode -ceq ''InspectPackage''\)' -and
    $deployment -match 'PLUGIN_PACKAGE_POST_INSPECTION_COMPLETE' -and
    $deployment -match 'ExpectedContentSha256Matches' -and
    $deployment -match 'DirectReadContentSha256Matches' -and
    $deployment -match 'SolutionMembershipMatches' -and
    $deployment -match 'ApiHandlerMatchesLegacy' -and
    $deployment -match 'Get-LegacyHandlers -Plan \$legacyPlan' -and
    $deployment -match 'Get-ApiSnapshot' -and
    $deployment -match 'POST = 0; PATCH = 0; AutomaticRetries = 0') 'Post-create package inspection is read-only and reports exact reconciliation fields'
Assert-Test ($deployment -match 'Assert-PackageProcessingMetadata' -and
    $deployment -match 'Package-to-assembly lookup relationship is missing or ambiguous before create' -and
    $deployment -match 'SourceType does not expose a Package/FileStore option before create' -and
    $deployment -match 'Custom API handler navigation metadata is missing or ambiguous before create' -and
    $deployment.LastIndexOf('$processingMetadata = Assert-PackageProcessingMetadata') -lt
    $deployment.IndexOf("Invoke-PackageRequest -Method POST -Path 'pluginpackages'")) 'Package processing and handler metadata are validated before package creation'
Assert-Test ($deployment -match 'Get-RuntimeZeroRowGate' -and
    $deployment -match 'FreshZeroRowCounts' -and
    $deployment -match 'Fresh Candidate Core business-row counts are nonzero or unknown' -and
    $deployment.LastIndexOf('$zeroRows = Get-RuntimeZeroRowGate') -lt
    $deployment.IndexOf("Invoke-PackageRequest -Method POST -Path 'pluginpackages'") -and
    $deployment.IndexOf("Exact package appeared after the zero-row gate; stop without POST.") -lt
    $deployment.IndexOf("Invoke-PackageRequest -Method POST -Path 'pluginpackages'")) 'Fresh zero-row gate and package-absence recheck precede the single package POST'
Assert-Test ($deployment -match '\[int\]\$strict\.StrictResult\.StorageGateGET' -and
    $deployment -match 'StrictLegacyStorageGateGET' -and
    $deployment -match 'NestedGETCounts\.StrictStorage') 'Aggregate request counts include nested strict storage-gate GETs'
Assert-Test ($deployment -match 'Get-PackageAssemblyAndTypes' -and
    $deployment -match "ReferencedEntity -CEQ 'pluginpackage'" -and
    $deployment -match 'SourceType is not the live metadata Package/FileStore option' -and
    $deployment -match 'Package-backed PlugInType inventory is not exactly') 'Package-generated assembly and exact handler/guard types are verified'
Assert-Test ($deployment -match 'Invoke-StrictLegacyGate' -and
    $deployment -match 'CANDIDATE_CORE_ASSEMBLY_RECONCILED' -and
    $deployment -match 'Legacy signed assembly changed from its retained successful state' -and
    $deployment -match 'Legacy guard-step topology differs') 'Fresh strict legacy assembly, API, and guard topology gates precede create'
Assert-Test ($deployment -match 'ApiNonHandlerSha256' -and
    $deployment -match 'Custom API properties other than PluginTypeId changed during cutover' -and
    $deployment -match 'MaximumHandlerPatches = 1') 'Only PluginTypeId may change, with a bounded PATCH'
Assert-Test ($deployment -match 'RequestParameters = @\(\$inputs \| Sort-Object uniquename' -and
    $deployment -match 'UniqueName = \[string\]\$_.uniquename' -and
    $deployment -match 'Type = \[int\]\$_.type' -and
    $deployment -match 'IsOptional = \[bool\]\$_.isoptional' -and
    $deployment -match 'LogicalEntityName = if \(\$_.logicalentityname\)' -and
    $deployment -match 'ApiRequestParameters = \$state\.API\.RequestParameters') 'Read-only preflight exposes exact live request parameter metadata'
Assert-Test ($deployment -match 'Component Solution membership mismatch for \$EntityLogicalName \(rows=') 'Solution membership gate reports bounded type/count diagnostics on drift'
Assert-Test ($deployment -match 'ComponentType -ne 91' -and
    $deployment -match '-ExpectedComponentType \(\[int\]\$legacyAssemblyPlan\[0\]\.ComponentType\)' -and
    $deployment -match 'if \(\$ExpectedComponentType -lt 0\)') 'Plug-in Assembly membership uses the pinned Solution component code, not entity ObjectTypeCode'
 $cutoverStart = $deployment.IndexOf("if (`$Mode -in @('CutoverExistingPreflight', 'CutoverExistingApply', 'RollbackExistingCutover'))")
 $cutoverEnd = $deployment.IndexOf("if (`$Mode -in @('Preflight', 'Apply'))", $cutoverStart)
 $existingCutover = if ($cutoverStart -ge 0 -and $cutoverEnd -gt $cutoverStart) {
    $deployment.Substring($cutoverStart, $cutoverEnd - $cutoverStart)
 } else { '' }
Assert-Test ($existingCutover -match 'Get-ExistingPackageCutoverState' -and
    $existingCutover -match 'FreshZeroRowCounts' -and
    $existingCutover -match 'OPERATION_RECEIPT_STORAGE_RECONCILED' -and
    $existingCutover -match 'New-ExistingCutoverJournal' -and
    $existingCutover.IndexOf('Save-PackageJournal') -lt $existingCutover.IndexOf('Invoke-PackageRequest -Method PATCH') -and
    $existingCutover -match 'Get-ExistingPackageCutoverState -ExpectedHandlerTypeId' -and
    $existingCutover -match 'MaximumRollbackPatches -ne 1' -and
    $existingCutover -match 'RuntimeFailureClassification' -and
    $existingCutover -match 'ManifestSha256' -and
    $existingCutover -match 'PLUGIN_PACKAGE_CUTOVER_RECONCILED_RUNTIME_PENDING' -and
    $existingCutover -match 'AutomaticRetries -ne 0' -and
    $existingCutover -notmatch "Invoke-PackageRequest -Method POST -Path 'pluginpackages'") 'R4D existing-package handler-only cutover is gated, journaled before dispatch, and bounded'
Assert-Test ($deployment -match 'LegacyPluginTypeId' -and
    $deployment -match 'PackagePluginTypeId' -and
    $existingCutover -match 'LegacyHandlerTypeId' -and
    $existingCutover -match 'PackageHandlerTypeId' -and
    $existingCutover -match 'PackageAssemblySourceTypeLabels' -and
    $existingCutover -match 'PackageTypeSolutionMembership' -and
    $existingCutover -match 'Get-ExistingPackageCutoverState -ExpectedHandlerTypeId \(\[string\]\$script:Journal.LegacyHandlerTypeId\)' -and
    $existingCutover -match 'PLUGIN_PACKAGE_CUTOVER_ROLLED_BACK') 'R4D retains exact handler map and rollback reconciles only to the legacy handler'
Assert-Test ($deployment -match 'PLUGIN_PACKAGE_HANDLER_CUTOVER_FAILED' -and
    $deployment -match 'UNCERTAIN_WRITE_OUTCOME' -and $deployment -match 'no retry') 'Uncertain writes reconcile once and stop without resend'
Assert-Test ($deployment -match "Mode -ceq 'Rollback'" -and
    $deployment -match 'LegacyHandlerTypeId' -and $deployment -match 'PackageHandlerTypeId' -and
    $deployment -match 'PLUGIN_PACKAGE_CUTOVER_ROLLED_BACK') 'Rollback uses the retained handler mapping and keeps the package'
Assert-Test ($deployment -notmatch "PublishAllXml|Invoke-PackageRequest -Method (POST|PATCH|DELETE) -Path 'pluginassemblies'|Invoke-PackageRequest -Method (POST|PUT|DELETE) -Path 'EntityDefinitions") 'No publication, schema, or legacy assembly mutation path exists'
Assert-Test ($contract.handler -ceq 'os_sr_cact.ApplyCandidateAction' -and
    $contract.guard -ceq 'os_sr_cact.ProtectCandidateCore' -and
    $contract.uniqueName -ceq 'os_sr_cact') 'Deployment handler mappings match the approved API contract'

Assert-Test ($runtime -match 'ExpectedHandlerPackageUniqueName' -and
    $runtime -match 'Assert-PackageBackedHandler' -and
    $runtime -match 'Runtime Apply requires the reconciled package-backed handler identity') 'Runtime execution is gated on the package-backed API chain'
Assert-Test ($runtime -match 'phase3d-r4e-owner-authorized-package-runtime' -and
    $runtime -notmatch 'phase3d-r4d-owner-authorized-package-runtime' -and
    $runtime -match '\[SYNTHETIC-E2E\] Candidate Core Acceptance' -and
    $runtime -match '@example\.invalid') 'Runtime uses a distinct one-shot authorization and approved synthetic identity'
Assert-Test ($runtime -match 'MaximumRetryCount = 0' -and
    $runtime -match 'MaximumApiDispatches = \$expectedActionCalls' -and
    $runtime -match 'AutomaticRetries = 0') 'Runtime dispatch remains bounded with zero retries'

$null = & $packageTests
"PASS: $script:Passed Phase 3D-R4B package deployment assertions; no authentication/network."
