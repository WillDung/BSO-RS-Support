#requires -Version 7.4
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('TEST', 'PROD')][string]$Mode,
    [string]$TestTargetAuthorizationEvidencePath,
    [string]$ApprovalEvidencePath,
    [string]$ManagedArtifactPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($Mode -ceq 'TEST' -and -not [string]::IsNullOrWhiteSpace($TestTargetAuthorizationEvidencePath)) {
    Import-Module (Join-Path $PSScriptRoot 'BsoRsTestTargetAuthorization.psm1') -Force
    $targetAuthorization = Get-BsoRsTestTargetAuthorizationEvidence -Path $TestTargetAuthorizationEvidencePath
} else {
    $targetAuthorization = $null
}

if ([string]::IsNullOrWhiteSpace($ApprovalEvidencePath) -or
    [string]::IsNullOrWhiteSpace($ManagedArtifactPath)) {
    if ($null -ne $targetAuthorization) {
        [pscustomobject]@{
            Result = $targetAuthorization.Status
            Gate = 'TEST_RELEASE_READINESS_EVIDENCE_REQUIRED'
            OwnerAuthorization = $targetAuthorization.Status
            RequiredNextEvidence = @(
                'BOUNDED_TARGET_REQUALIFICATION',
                'APPROVED_TEST_MANAGED_ARTIFACT',
                'RELEASE_AND_RECOVERY_APPROVAL_EVIDENCE'
            )
            NetworkOperations = 0
            Imports = 0
        }
        return
    }

    [pscustomobject]@{
        Result = if ($Mode -ceq 'TEST') { 'TEST_TARGET_APPROVAL_REQUIRED' } else { 'PRODUCTION_APPROVAL_REQUIRED' }
        NetworkOperations = 0
        Imports = 0
    }
    return
}
if (-not (Test-Path -LiteralPath $ApprovalEvidencePath -PathType Leaf) -or
    -not (Test-Path -LiteralPath $ManagedArtifactPath -PathType Leaf)) {
    throw 'Approval evidence and the pinned managed artifact must both exist before import-gate validation.'
}

$approval = Get-Content -LiteralPath $ApprovalEvidencePath -Raw | ConvertFrom-Json
$environmentId = [Guid]::Empty
$organizationId = [Guid]::Empty
$organizationUri = $null
$artifactHash = (Get-FileHash -LiteralPath $ManagedArtifactPath -Algorithm SHA256).Hash.ToLowerInvariant()
$validTarget = [Guid]::TryParse([string]$approval.environmentId, [ref]$environmentId) -and
    [Guid]::TryParse([string]$approval.organizationId, [ref]$organizationId) -and
    [Uri]::TryCreate([string]$approval.organizationUrl, [UriKind]::Absolute, [ref]$organizationUri) -and
    $organizationUri.Scheme -ceq 'https' -and
    [string]::IsNullOrEmpty($organizationUri.UserInfo) -and
    $organizationUri.AbsolutePath -eq '/' -and
    [string]::IsNullOrEmpty($organizationUri.Query) -and
    [string]::IsNullOrEmpty($organizationUri.Fragment)

$requiredCommonApproval = $approval.mode -ceq $Mode -and
    -not [string]::IsNullOrWhiteSpace([string]$approval.environmentDisplayName) -and
    -not [string]::IsNullOrWhiteSpace([string]$approval.region) -and
    $validTarget -and
    $approval.pacWhoAmIAgreement -eq $true -and
    $approval.dataverseWhoAmIAgreement -eq $true -and
    $approval.targetIdentityVerified -eq $true -and
    $approval.ownerApproved -eq $true -and
    $approval.authorizedDeploymentIdentityApproved -eq $true -and
    $approval.solutionUniqueName -ceq 'os_sr_bso_rs_support' -and
    $approval.solutionVersion -ceq '1.0.0.1' -and
    $approval.artifactOrigin -cin @('CANONICAL_SOURCE', 'APPROVED_TEST_BUILD') -and
    $approval.artifactReleaseable -eq $true -and
    $approval.managedArtifactSha256 -ceq $artifactHash -and
    $approval.importApproved -eq $true -and
    $approval.backupRecoveryGateComplete -eq $true

$securityApproval = $approval.PSObject.Properties['securityOwnerApprovalComplete']
$governanceApproval = $approval.PSObject.Properties['governanceGateComplete']
$migrationApproval = $approval.PSObject.Properties['migrationDecisionComplete']
$productionApprovalComplete = $Mode -cne 'PROD' -or (
    $null -ne $securityApproval -and $securityApproval.Value -eq $true -and
    $null -ne $governanceApproval -and $governanceApproval.Value -eq $true -and
    $null -ne $migrationApproval -and $migrationApproval.Value -eq $true -and
    $approval.releaseApprovalEvidencePresent -eq $true
)

$testEnvironmentPolicyStatus = $approval.PSObject.Properties['testEnvironmentPolicyStatus']
$testEnvironmentPolicyEvidence = $approval.PSObject.Properties['testEnvironmentPolicyEvidenceVerified']
$testEnvironmentProhibited = $Mode -ceq 'TEST' -and
    $null -ne $testEnvironmentPolicyStatus -and
    $testEnvironmentPolicyStatus.Value -ceq 'PROHIBITED' -and
    $null -ne $testEnvironmentPolicyEvidence -and
    $testEnvironmentPolicyEvidence.Value -eq $true

if (-not $requiredCommonApproval -or
    -not $productionApprovalComplete -or
    $testEnvironmentProhibited -or
    ($Mode -ceq 'TEST' -and (
        $approval.isProductionBusinessRuntime -ne $false -or
        $approval.candidateCoreEnabled -ne $true -or
        $approval.syntheticDataOnly -ne $true -or
        $approval.devDirectWriteFallbackEnabled -ne $false -or
        $approval.diagnosticsMode -cne 'OFF'
    )) -or
    ($Mode -ceq 'PROD' -and (
        $approval.isProductionBusinessRuntime -ne $true -or
        $approval.productionApprovalEvidencePresent -ne $true
    ))) {
    throw 'Import approval evidence does not satisfy the explicit target, artifact, and release gates.'
}

[pscustomobject]@{
    Result = if ($Mode -ceq 'TEST') {
        'TEST_IMPORT_PREFLIGHT_READY_NOT_EXECUTED'
    } else {
        'PRODUCTION_IMPORT_PREFLIGHT_READY_NOT_EXECUTED'
    }
    ManagedArtifactSha256 = $artifactHash
    NetworkOperations = 0
    Imports = 0
    ImportPolicy = [ordered]@{
        publishAllXml = $false
        forceOverwrite = $false
        skipDependencyCheck = $false
        retriesOnAmbiguousWrite = 0
        targetIdentityGuardRequiredBeforeWrite = $true
        postImportReadOnlyReconciliationRequired = $true
    }
    Note = 'This gate validates supplied approval evidence only. It never authenticates, connects, imports, publishes, overwrites, or bypasses dependencies.'
}
