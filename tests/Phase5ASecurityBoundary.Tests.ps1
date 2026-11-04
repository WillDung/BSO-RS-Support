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

$guardPath = Join-Path $root 'scripts\Cutover-BsoRsCandidateCoreGuards.ps1'
$guardSource = Get-Content -LiteralPath $guardPath -Raw
$contract = Get-Content -LiteralPath (Join-Path $root 'docs\PHASE_3C_API_CONTRACT.json') -Raw | ConvertFrom-Json
$guardAst = [System.Management.Automation.Language.Parser]::ParseFile($guardPath, [ref]$tokens, [ref]$errors)
Assert-Test ($errors.Count -eq 0) 'Reconciled guard tool parses'
Assert-Test ($guardSource.Contains("[string]`$SecurityModel = 'DataverseRoles'") -and
    $guardSource.Contains("`$SecurityModel -cne 'LegacyActiveGuardRecovery'") -and
    $guardSource.IndexOf("Current Dataverse role security model is read-only") -lt
        $guardSource.IndexOf('    Assert-TargetInput')) `
    'Default model blocks mutation modes before authentication and independently guards PATCH dispatch'
$mainTry = @($guardAst.EndBlock.Statements | Where-Object {
    $_ -is [System.Management.Automation.Language.TryStatementAst]
})
Assert-Test ($mainTry.Count -eq 1 -and
    $mainTry[0].Body.Statements[0].Extent.Text.Contains("`$SecurityModel -ceq 'DataverseRoles'")) `
    'Mode rejection is the first main-body statement, not an unused function or recovery catch'
$modeGuard = [scriptblock]::Create($mainTry[0].Body.Statements[0].Extent.Text)
$SecurityModel = 'DataverseRoles'
foreach ($Mode in 'Apply', 'Continue', 'Rollback') {
    $rejected = $false
    try { & $modeGuard } catch {
        $rejected = $_.Exception.Message -like 'Current Dataverse role security model is read-only*'
    }
    Assert-Test $rejected "Current model rejects $Mode before authentication"
}
foreach ($Mode in 'Preflight', 'Reconcile') { & $modeGuard }
Assert-Test $true 'Current model permits only the read-only modes'
$SecurityModel = 'LegacyActiveGuardRecovery'; $Mode = 'Apply'
& $modeGuard
Assert-Test $true 'Legacy recovery requires explicit model opt-in; its dispatcher is not invoked'
Assert-Test ($contract.securityModel.current -ceq 'CURRENT_DATAVERSE_ROLE_SECURITY_MODEL' -and
    $contract.securityModel.legacyRegistrationModel -ceq 'HISTORICAL_PROTECTCANDIDATECORE_REGISTRATION_MODEL' -and
    $contract.securityModel.directWriteBoundary -match 'BSO role denies direct protected-table Create/Write') `
    'Current role boundary is explicit and historical coverage is not active authorization'

foreach ($name in @('Get-RoleModelLegacyGuardInventory', 'Invoke-GuardRequest')) {
    $definition = @($guardAst.EndBlock.Statements | Where-Object {
        $_ -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $_.Name -ceq $name
    })
    Assert-Test ($definition.Count -eq 1) "Isolate offline function: $name"
    . ([scriptblock]::Create($definition[0].Extent.Text))
}
function Get-GuardRows {
    param([string]$Path)
    if ($Path.StartsWith('plugintypes?')) {
        return [pscustomobject]@{ plugintypeid = '00000000-0000-0000-0000-000000000001' }
    }
    if ($Path.Contains("startswith(name,'os_sr_cact.guard.')")) { return $script:NamedLegacySteps }
    if ($Path.Contains('_eventhandler_value eq')) { return $script:LegacySteps }
    throw "Unexpected offline query: $Path"
}
$script:LegacySteps = @(
    foreach ($index in 1..50) {
        [pscustomobject]@{
            sdkmessageprocessingstepid = '00000000-0000-0000-0001-{0:d12}' -f $index
            name = "os_sr_cact.guard.synthetic.$index"
            statecode = 1; stage = 10; mode = 0; _impersonatinguserid_value = $null
        }
    }
)
$script:NamedLegacySteps = $script:LegacySteps
$inventory = Get-RoleModelLegacyGuardInventory
Assert-Test ($inventory.Result -ceq 'LEGACY_PROTECTCANDIDATECORE_CUTOVER_NOT_APPLICABLE' -and
    $inventory.DisabledLegacySteps -eq 50 -and -not $inventory.LegacyRegistrationCountRequired -and
    -not $inventory.MissingInterviewScheduleRegistrationsRequired) `
    'Fifty disabled legacy steps without twelve Interview Schedule registrations pass current reconciliation'
$script:LegacySteps[0].statecode = 0
$rejected = $false
try { $null = Get-RoleModelLegacyGuardInventory } catch {
    $rejected = $_.Exception.Message -like 'Unexpected active ProtectCandidateCore registration*'
}
Assert-Test $rejected 'Any active legacy registration fails closed without attempting a write'
$script:LegacySteps[0].statecode = 1
$script:LegacySteps[0].stage = 20
$rejected = $false
try { $null = Get-RoleModelLegacyGuardInventory } catch {
    $rejected = $_.Exception.Message -like 'Disabled legacy guard registration configuration differs*'
}
Assert-Test $rejected 'Legacy registration configuration drift is explicit'
$script:LegacySteps = @(); $script:NamedLegacySteps = @()
$inventory = Get-RoleModelLegacyGuardInventory
Assert-Test ($inventory.LegacySteps -eq 0) 'No exact historical count is required'
$script:NamedLegacySteps = @([pscustomobject]@{ sdkmessageprocessingstepid = '00000000-0000-0000-0002-000000000001' })
$rejected = $false
try { $null = Get-RoleModelLegacyGuardInventory } catch {
    $rejected = $_.Exception.Message -like 'Legacy guard names reference an unexpected handler*'
}
Assert-Test $rejected 'A named guard on an unexpected handler fails reconciliation'
$SecurityModel = 'DataverseRoles'; $Mode = 'Apply'
$rejected = $false
try { $null = Invoke-GuardRequest -Method PATCH -Path 'sdkmessageprocessingsteps(00000000-0000-0000-0000-000000000001)' } catch {
    $rejected = $_.Exception.Message -eq 'Only a journaled SDK message processing step EventHandler PATCH is permitted.'
}
Assert-Test $rejected 'Dispatcher blocks a guard PATCH under the current model before network access'

Write-Output "PASS: $script:Passed synthetic Phase 5A security-boundary assertions; no authentication/network."
