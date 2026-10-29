#requires -Version 7.4
[CmdletBinding()]
param(
    [string]$TestApprovalEvidencePath,
    [string]$ManagedArtifactPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ([string]::IsNullOrWhiteSpace($TestApprovalEvidencePath) -or
    [string]::IsNullOrWhiteSpace($ManagedArtifactPath)) {
    [pscustomobject]@{
        Result = 'TEST_REHEARSAL_RUNNER_READY_TARGET_REQUIRED'
        Gate = 'TEST_TARGET_APPROVAL_REQUIRED'
        NetworkOperations = 0
        Imports = 0
        RuntimeTests = 0
    }
    return
}

if (-not (Test-Path -LiteralPath $TestApprovalEvidencePath -PathType Leaf) -or
    -not (Test-Path -LiteralPath $ManagedArtifactPath -PathType Leaf)) {
    throw 'Test approval evidence and a managed artifact must both exist before gate validation.'
}

$approval = Get-Content -LiteralPath $TestApprovalEvidencePath -Raw | ConvertFrom-Json
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

if ($approval.mode -cne 'TEST' -or
    [string]::IsNullOrWhiteSpace([string]$approval.environmentDisplayName) -or
    [string]::IsNullOrWhiteSpace([string]$approval.region) -or
    -not $validTarget -or
    $approval.isProductionBusinessRuntime -ne $false -or
    $approval.ownerApproved -ne $true -or
    $approval.importApproved -ne $true -or
    $approval.testIdentityApproved -ne $true -or
    $approval.authorizedDeploymentIdentityApproved -ne $true -or
    $approval.rollbackCleanupOwnerApproved -ne $true -or
    $approval.pacWhoAmIAgreement -ne $true -or
    $approval.dataverseWhoAmIAgreement -ne $true -or
    $approval.targetIdentityVerified -ne $true -or
    $approval.candidateCoreEnabled -ne $true -or
    $approval.syntheticDataOnly -ne $true -or
    $approval.devDirectWriteFallbackEnabled -ne $false -or
    $approval.diagnosticsMode -cne 'OFF' -or
    $approval.solutionUniqueName -cne 'os_sr_bso_rs_support' -or
    $approval.solutionVersion -cne '1.0.0.0' -or
    $approval.artifactOrigin -cnotin @('CANONICAL_SOURCE', 'APPROVED_TEST_BUILD') -or
    $approval.artifactReleaseable -ne $true -or
    $approval.managedArtifactSha256 -cne $artifactHash) {
    throw 'Approval evidence is not a valid, explicit TEST target and release artifact approval.'
}

[pscustomobject]@{
    Result = 'TEST_REHEARSAL_PREFLIGHT_READY_NOT_EXECUTED'
    ManagedArtifactSha256 = $artifactHash
    NetworkOperations = 0
    Imports = 0
    RuntimeTests = 0
    RehearsalSequence = @(
        'TARGET_IDENTITY_AND_ENVIRONMENT_ORG_VERIFICATION',
        'NONPRODUCTION_TARGET_GATE',
        'PRE_REHEARSAL_INVENTORY',
        'APPROVED_SOLUTION_IMPORT_OR_UPDATE',
        'TARGET_CONFIGURATION',
        'CANDIDATE_CORE_PACKAGE_UPDATER_PREFLIGHT',
        'CANDIDATE_CORE_PACKAGE_RECONCILIATION',
        'BSO_ROLE_AND_APP_ACCESS',
        'EXACT_SRAPP_BROWSER_ACCEPTANCE',
        'POSITIVE_SYNTHETIC_CANDIDATE_CORE_LIFECYCLE',
        'REPLAY_CONFLICT_AND_STALE_STATUS_ACCEPTANCE',
        'FIVE_DIRECT_WRITE_NEGATIVES',
        'ROLLBACK_AND_RECOVERY_EXERCISE',
        'FINAL_READ_ONLY_RECONCILIATION'
    )
    CandidateCorePackageUpdater = '../scripts/Update-BsoRsCandidatePluginPackage.ps1'
    Note = 'This gate validates supplied evidence only. It does not authenticate, connect, import, assign roles, or run browser/runtime tests.'
}
