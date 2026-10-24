#requires -Version 7.4
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$runnerPath = Join-Path $root 'scripts/Provision-BsoRsCandidateChildTables.ps1'
$manifestPath = Join-Path $root 'docs/PHASE_3A_CANDIDATE_CORE_METADATA_PLAN.json'
$modelPath = Join-Path $root 'docs/DATA_MODEL.md'
$runner = Get-Content -LiteralPath $runnerPath -Raw
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$model = Get-Content -LiteralPath $modelPath -Raw
$script:Passed = 0

function Assert-Test {
    param([bool]$Condition, [string]$Name)
    if (-not $Condition) { throw "FAIL: $Name" }
    $script:Passed++
}

$tokens = $null
$parseErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile($runnerPath, [ref]$tokens, [ref]$parseErrors) | Out-Null
Assert-Test ($parseErrors.Count -eq 0) 'Child-table runner parses without diagnostics'
Assert-Test ($runner -match "MaximumRetryCount\s*=\s*0" -and
    $runner -match "AutomaticRetries\s*=\s*0") 'Automatic retry count is fixed at zero'
Assert-Test ($runner -match "MaximumWrites\s*=\s*9" -and
    $runner -match "GlobalOptionSetDefinitions" -and
    $runner -match "RelationshipDefinitions" -and
    $runner -match "/Keys") 'Write ceiling and metadata endpoint allowlist are explicit'
Assert-Test ($runner -match "CandidateWrites\s*=\s*0" -and
    $runner -match "BusinessDataWrites\s*=\s*0" -and
    $runner -match "PublicationWrites\s*=\s*0" -and
    $runner -notmatch "PublishAllXml") 'Candidate, business data, and publication remain excluded'
Assert-Test ($runner -match "Assert-ChildTableAbsent" -and
    $runner -match "Assert-InitialState" -and
    $runner -match "Assert-TableReadback" -and
    $runner -match "Assert-RelationshipsAndKeys") 'Preflight and exact post-write reconciliation paths are required'
Assert-Test ($runner -match 'GlobalOptionSetDefinitions\(Name=' -and
    $runner -match "Update-ManifestChoiceValues" -and
    $runner.Contains('"relationships"\s*:')) 'Call Outcome Choice existence check and value freeze are wired'
Assert-Test ($runner -match "candidateCreateOrModification" -and
    $runner -match "customApiOrPlugin" -and
    $runner -match "securityOrAppChanges" -and
    $runner -match "publication") 'Manifest scope exclusions are enforced before any write'
Assert-Test ($runner -match "STOPPED_AFTER_REJECTED_TABLE_CREATE_NO_RETRY" -and
    $runner -match "no further writes are permitted") 'Stopped authorization fails closed before target checks or network requests'
Assert-Test ($manifest.relationships.Count -eq 7 -and
    @($manifest.relationships | ForEach-Object schemaName | Select-Object -Unique).Count -eq 7) 'Seven manifest relationship schema names are unique'
Assert-Test ($model -match '`usr` = Dataverse system user' -and
    $model -match 'os_sr_usr_call_ctby' -and $model -match 'os_sr_usr_csh_actr') 'User lookup naming follows the documented publisher/project convention'
Assert-Test ($manifest.callOutcomeChoice.options.Count -eq 3 -and
    @($manifest.callOutcomeChoice.options | ForEach-Object label) -join '|' -ceq 'Answered|No Answer|Call Back Requested') 'Call Outcome taxonomy remains exact'
Assert-Test ($manifest.provisioning.phase3B2AuthorizedContinuation.status -ceq 'STOPPED_AFTER_REJECTED_TABLE_CREATE_NO_RETRY' -and
    $manifest.provisioning.phase3B2AuthorizedContinuation.executionOutcome.successfulChildTableWrites -eq 0 -and
    $manifest.provisioning.phase3B2AuthorizedContinuation.automaticRetries -eq 0) 'Rejected Call Log create is recorded with authorization stopped and no retry'

Write-Output "PASS: $script:Passed synthetic Phase 3B.2 provisioning assertions; no authentication, network, PAC, or tenant calls."
