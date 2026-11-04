#requires -Version 7.4
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$scriptPath = Join-Path $root 'scripts\Repair-BsoRsCandidateCoreApiInputs.ps1'
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
Assert-Test ($errors.Count -eq 0) 'Candidate Core API input repair runner parses'
Assert-Test ($source -match "ValidateSet\('Preflight', 'Apply', 'Reconcile'\)" -and
    $source -match "EnvironmentName -cne 'VN LMV IT'" -and
    $source -match "https://org14938ec2\.crm4\.dynamics\.com") `
    'Metadata correction is pinned to VN LMV IT'
Assert-Test ($source -match "SolutionUniqueName = 'os_sr_bso_rs_support'" -and
    $source -match "PublisherUniqueName = 'os_bso_rs_support'" -and
    $source -match "customizationprefix -cne 'os'") `
    'Correction targets the existing project Solution and Publisher'
Assert-Test ($source -match "executeprivilegename -cne 'prvReados_sr_cand'" -and
    $source -match 'isprivate -ne \$true' -and
    $source -match "bindingtype -ne 0") `
    'Existing Custom API privilege and unbound private contract are guarded'
Assert-Test ($source -match "'CandidateCvUrl', 'AssignedTaId'" -and
    $source -match 'MaximumPostDispatches = \$writes\.Count' -and
    $source -match 'MaximumRetries|AutomaticRetries = 0') `
    'The only permitted request-parameter additions are the seven approved inputs'
Assert-Test ($source -match "ValidateSet\('GET', 'POST'\)" -and
    $source -match "customapirequestparameters" -and
    $source -match "MSCRM.SolutionUniqueName" -and
    $source -match 'Assert-RequestParameterReadback') `
    'Writes are limited to solution-aware request parameters with immediate readback'
Assert-Test ($source -match 'DISPATCH_RESERVED' -and
    $source -match 'CreateNew' -and $source -match 'AutomaticRetries = 0' -and
    $source -match 'MaximumPostDispatches = \$script:Plan\.Writes\.Count' -and
    $source -match 'PLANNED_NOT_DISPATCHED' -and
    $source -match 'UNRESOLVED_NO_RETRY') `
    'The runner journals only planned writes and reconciles partial dispatch without retry'
Assert-Test ($source -notmatch 'pluginpackages|pluginassemblies|sdkmessageprocessingsteps|PublishAllXml|pac admin assign-user|ProtectCandidateCore') `
    'No package deployment, guard mutation, publication, or role assignment path exists'

$contractPath = Join-Path $root 'docs\PHASE_3C_API_CONTRACT.json'
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
$expected = @(
    'AssignedTaId|12|True'
    'CandidateCvUrl|10|True'
    'EndAt|1|True'
    'InterviewerId|12|True'
    'LocationId|12|True'
    'ResultNotes|10|True'
    'StartAt|1|True'
)
$actual = @($contract.inputs | Where-Object {
    $_.name -in @(
        'InterviewerId', 'LocationId', 'StartAt', 'EndAt', 'ResultNotes',
        'CandidateCvUrl', 'AssignedTaId'
    )
} | ForEach-Object {
    '{0}|{1}|{2}' -f $_.name, [int]$_.type, [bool]$_.optional
} | Sort-Object -CaseSensitive)
Assert-Test ([string]::Join(';', $actual) -ceq [string]::Join(';', $expected)) `
    'The approved contract defines the exact seven missing inputs and types'

Write-Output "PASS: $script:Passed offline Phase 5A API-input repair assertions; no authentication/network."
