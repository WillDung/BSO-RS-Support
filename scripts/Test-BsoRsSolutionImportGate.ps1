#requires -Version 7.4
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('TEST', 'PROD')][string]$Mode,
    [string]$ApprovalEvidencePath,
    [string]$ManagedArtifactPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ([string]::IsNullOrWhiteSpace($ApprovalEvidencePath) -or
    [string]::IsNullOrWhiteSpace($ManagedArtifactPath)) {
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
    $approval.solutionVersion -ceq '1.0.0.0' -and
    $approval.artifactOrigin -cin @('CANONICAL_SOURCE', 'APPROVED_TEST_BUILD') -and
    $approval.artifactReleaseable -eq $true -and
    $approval.managedArtifactSha256 -ceq $artifactHash -and
    $approval.importApproved -eq $true -and
    $approval.releaseApprovalEvidencePresent -eq $true -and
    $approval.backupRecoveryGateComplete -eq $true -and
    $approval.securityOwnerApprovalComplete -eq $true -and
    $approval.governanceGateComplete -eq $true -and
    $approval.migrationDecisionComplete -eq $true

if (-not $requiredCommonApproval -or
    ($Mode -ceq 'TEST' -and (
        $approval.isProductionBusinessRuntime -ne $false -or
        $approval.testIdentityApproved -ne $true -or
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
