#requires -Version 7.4
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'scripts\BsoRsTestTargetAuthorization.psm1') -Force
$temporaryPath = Join-Path ([IO.Path]::GetTempPath()) "bso-rs-test-authorization-$([Guid]::NewGuid().ToString('N')).json"
$passed = 0

function Assert-Test {
    param([bool]$Condition, [string]$Name)
    if (-not $Condition) { throw "FAIL: $Name" }
    $script:passed++
}

function Write-Evidence {
    param([Parameter(Mandatory)][object]$Evidence)
    [IO.File]::WriteAllText(
        $temporaryPath,
        (ConvertTo-Json -InputObject $Evidence -Depth 4),
        [Text.UTF8Encoding]::new($false)
    )
}

$validEvidence = [ordered]@{
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
    Write-Evidence -Evidence $validEvidence
    $result = Get-BsoRsTestTargetAuthorizationEvidence -Path $temporaryPath
    Assert-Test ($result.Status -ceq 'TEST_TARGET_APPROVAL_EVIDENCE_SATISFIED' -and
        $result.TargetDisplayName -ceq 'LMV BI DEV' -and
        $result.AuthorizationScope -ceq 'BOUNDED_TEST_REHEARSAL') `
        'Accept the explicit current-session owner authorization for the bounded Test rehearsal'

    $wrongTarget = [ordered]@{} + $validEvidence
    $wrongTarget.targetDisplayName = 'VN LMV IT'
    Write-Evidence -Evidence $wrongTarget
    $rejected = $false
    try { Get-BsoRsTestTargetAuthorizationEvidence -Path $temporaryPath | Out-Null } catch { $rejected = $true }
    Assert-Test $rejected 'Reject authorization evidence that names a different target'

    $expandedScope = [ordered]@{} + $validEvidence
    $expandedScope.productionOperationsProhibited = $false
    Write-Evidence -Evidence $expandedScope
    $rejected = $false
    try { Get-BsoRsTestTargetAuthorizationEvidence -Path $temporaryPath | Out-Null } catch { $rejected = $true }
    Assert-Test $rejected 'Reject evidence that does not prohibit Production operations'

    $withIdentity = [ordered]@{} + $validEvidence
    $withIdentity.userEmail = 'synthetic@example.invalid'
    Write-Evidence -Evidence $withIdentity
    $rejected = $false
    try { Get-BsoRsTestTargetAuthorizationEvidence -Path $temporaryPath | Out-Null } catch { $rejected = $true }
    Assert-Test $rejected 'Reject additional identity or unapproved data fields'
} finally {
    if (Test-Path -LiteralPath $temporaryPath) {
        Remove-Item -LiteralPath $temporaryPath -Force
    }
}

Write-Output "BSO-RS Test target authorization checks passed: $passed"
