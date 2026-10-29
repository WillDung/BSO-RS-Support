#requires -Version 7.4
[CmdletBinding()]
param(
    [string]$TestApprovalEvidencePath,
    [string]$ManagedArtifactPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ([string]::IsNullOrWhiteSpace($TestApprovalEvidencePath)) {
    [pscustomobject]@{
        Result = 'TEST_TARGET_APPROVAL_REQUIRED'
        NetworkOperations = 0
        Imports = 0
    }
    return
}
if ([string]::IsNullOrWhiteSpace($ManagedArtifactPath)) {
    [pscustomobject]@{
        Result = 'MANAGED_ARTIFACT_REQUIRED'
        NetworkOperations = 0
        Imports = 0
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
if ($approval.mode -cne 'TEST' -or
    $approval.ownerApproved -ne $true -or
    $approval.importApproved -ne $true -or
    $approval.testIdentityApproved -ne $true -or
    $approval.candidateCoreEnabled -ne $true -or
    $approval.syntheticDataOnly -ne $true -or
    $approval.devDirectWriteFallbackEnabled -ne $false -or
    $approval.diagnosticsMode -cne 'OFF' -or
    -not [Guid]::TryParse([string]$approval.environmentId, [ref]$environmentId) -or
    -not [Guid]::TryParse([string]$approval.organizationId, [ref]$organizationId) -or
    -not [Uri]::TryCreate([string]$approval.organizationUrl, [UriKind]::Absolute, [ref]$organizationUri) -or
    $organizationUri.Scheme -cne 'https' -or
    $organizationUri.UserInfo -or
    $organizationUri.AbsolutePath -ne '/' -or
    $organizationUri.Query -or
    $organizationUri.Fragment) {
    throw 'Approval evidence is not a valid, explicit owner-approved TEST target.'
}

$artifactHash = (Get-FileHash -LiteralPath $ManagedArtifactPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($approval.solutionUniqueName -cne 'os_sr_bso_rs_support' -or
    $approval.managedArtifactSha256 -cne $artifactHash) {
    throw 'Managed artifact identity or approved hash does not match the approval evidence.'
}

[pscustomobject]@{
    Result = 'TEST_REHEARSAL_PREFLIGHT_READY_NOT_EXECUTED'
    ManagedArtifactSha256 = $artifactHash
    NetworkOperations = 0
    Imports = 0
    RuntimeTests = 0
    Note = 'This gate does not authenticate, connect, import, or run browser/runtime tests.'
}
