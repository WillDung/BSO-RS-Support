#requires -Version 7.4
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$scriptPath = Join-Path $root 'scripts\Set-BsoRsCandidateCoreSecurityBoundary.ps1'
$source = Get-Content -LiteralPath $scriptPath -Raw
$script:Passed = 0

function Assert-Test([bool]$Condition, [string]$Name) {
    if (-not $Condition) { throw "FAIL: $Name" }
    $script:Passed++
}

$tokens = $null
$errors = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile(
    $scriptPath, [ref]$tokens, [ref]$errors
)
Assert-Test ($errors.Count -eq 0) 'Security boundary runner parses'
Assert-Test ($source -match "ValidateSet\('PlanOnly', 'Apply'\)" -and
    $source -match "EnvironmentName -cne 'VN LMV IT'" -and
    $source -match "https://org14938ec2\.crm4\.dynamics\.com") `
    'Runner is pinned to the user-designated VN LMV IT environment'
Assert-Test ($source -match "apiExecutionPrivilege = 'prvReados_sr_cand'" -and
    $source -match "expectedCurrentApiPrivilege = 'prvWriteos_sr_cand'") `
    'API execution privilege change is explicit and fail-closed'
Assert-Test ($source -match "roleName = 'BSO-RS Support - BSO'" -and
    $source -match 'prvCreateos_sr_cand' -and $source -match 'prvWriteos_sr_cand' -and
    $source -match 'prvCreateos_sr_call' -and $source -match 'prvCreateos_sr_csh' -and
    $source -match 'prvCreateos_sr_intv' -and $source -match 'prvWriteos_sr_intv') `
    'Only the reviewed Candidate Core protected Create/Write privileges are in scope'
Assert-Test ($source -match 'RemovePrivilegeRole' -and
    $source -match 'role is assigned to a user or team' -and
    $source -match 'RemainingDirectProtectedCreateWritePrivileges = 0' -and
    $source -match 'systemuserroles_association' -and $source -match 'teamroles_association') `
    'Role privilege removal is bounded and the role must remain unassigned'
Assert-Test ($source -notmatch 'CreateOrganizationService' -and
    $source -match 'MaximumRetryCount 0' -and $source -match 'MaximumRedirection 0' -and
    $source -match 'UNCERTAIN_WRITE_OUTCOME' -and
    $source -match 'no write retry is permitted') `
    'Writes are one-shot, no-retry, and uncertain outcomes stop'
Assert-Test ($source -match 'solutionUniqueName = ''os_sr_bso_rs_support''' -and
    $source -match "MSCRM.SolutionUniqueName") `
    'Custom API privilege patch is solution-scoped'
Assert-Test ($source -match 'CreateNew' -and $source -match 'PayloadSha256' -and
    $source -match "Mode -ceq 'PlanOnly'") `
    'Apply requires a new durable exact-payload journal; PlanOnly does not write'
Assert-Test ($source -match "PSObject\.Properties\['value'\]" -and
    $source -match 'if \(\$apiRows\[0\]\.executeprivilegename -cne \$apiExecutionPrivilege\)') `
    'Readback handles both collection and singleton responses without resending an acknowledged privilege patch'
Assert-Test ($source -notmatch 'pac admin assign-user' -and
    $source -notmatch 'System Administrator' -and
    $source -notmatch 'ProtectCandidateCore.*PATCH|PATCH.*ProtectCandidateCore') `
    'No role assignment, broad admin grant, or guard registration write path exists'

Write-Output "PASS: $script:Passed synthetic Phase 5A security-boundary assertions; no authentication/network."
