# Read-only readiness check for BSO-RS-Support. Does not read records or print credentials.
[CmdletBinding()]
param(
    [string] $ExpectedEnvironmentName = 'VN LMV IT',
    [string] $ExpectedSolutionUniqueName = 'os_sr_bso_rs_support',
    [switch] $SkipOnlineChecks
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Check([string] $Name, [string] $Result) {
    Write-Output ('{0}: {1}' -f $Name, $Result)
}
function Test-Executable([string] $CommandName) {
    return $null -ne (Get-Command -Name $CommandName -ErrorAction SilentlyContinue)
}

Write-Check 'PowerShell' $PSVersionTable.PSVersion.ToString()
$hasPac = Test-Executable 'pac'
Write-Check 'PAC CLI' $(if ($hasPac) { 'Found' } else { 'MISSING' })
Write-Check 'Az.Accounts module' $(if (Get-Module -ListAvailable -Name Az.Accounts) { 'Found' } else { 'Not installed (optional if another approved auth works)' })
Write-Check 'Node/NPM (skills installer)' $(if ((Test-Executable 'node') -and (Test-Executable 'npx')) { 'Found' } else { 'Not detected' })

$workspaceRoot = Split-Path -Parent $PSScriptRoot
$hasOfficialSkill = (Test-Path (Join-Path $workspaceRoot '.github/skills/dv-metadata/SKILL.md')) -or
                    (Test-Path (Join-Path $workspaceRoot '.agents/skills/dv-metadata/SKILL.md'))
Write-Check 'Local dv-metadata skill' $(if ($hasOfficialSkill) { 'Found' } else { 'Not detected locally; inspect VS Code plugin installation' })
Write-Check 'Existing MCP config' $(if (Test-Path (Join-Path $workspaceRoot '.vscode/mcp.json')) { 'Found (not modified)' } else { 'Not found' })

if ($SkipOnlineChecks) {
    Write-Check 'Environment/Solution' 'Skipped (local-only)'
    exit 0
}
if (-not $hasPac) {
    throw 'PAC CLI unavailable. No target environment can be verified.'
}

# Capture locally and do NOT print full PAC output (includes user identity information).
$whoOutput = (& pac env who 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0) { throw 'PAC failed to verify active environment.' }
$escapedEnvName = [regex]::Escape($ExpectedEnvironmentName)
if ($whoOutput -notmatch ('(?im)^\s*(?:Friendly Name:\s*|Connected to\.\.\.\s*)' + $escapedEnvName + '\s*$')) {
    throw 'Active environment differs from expected VN LMV IT. No changes made.'
}
Write-Check 'Target environment' 'Verified by PAC'

$solOutput = (& pac solution list 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0) { throw 'PAC failed to list solutions.' }
$escapedSolName = [regex]::Escape($ExpectedSolutionUniqueName)
if ($solOutput -notmatch ('(?im)^\s*' + $escapedSolName + '\s+')) {
    throw 'Project Solution was not found in the verified environment.'
}
Write-Check 'Project Solution' 'Found in PAC list (publisher/membership still require independent read-back)'

# Model authoring capability is VERSION/INSTALLATION-DEPENDENT; do not assume PAC support.
$helpText = (& pac model help 2>&1 | Out-String)
if (($LASTEXITCODE -eq 0) -and ($helpText -match 'model create')) {
    Write-Check 'PAC model-driven app authoring' 'pac model create advertised'
} else {
    Write-Check 'PAC model-driven app authoring' 'Unverified/unavailable; review installed CLI help'
}
Write-Check 'Dataverse MCP readiness' 'Inspect in VS Code Copilot tool list (cannot verify from PAC alone)'
Write-Check 'Dataverse writes' 'NONE'
