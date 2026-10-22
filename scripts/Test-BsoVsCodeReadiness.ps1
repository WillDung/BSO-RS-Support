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

. (Join-Path $PSScriptRoot 'ReadinessChecks.ps1')

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

$rootMcpPath = Join-Path $workspaceRoot '.mcp.json'
$vsCodeMcpPath = Join-Path $workspaceRoot '.vscode/mcp.json'
$skillsLockPath = Join-Path $workspaceRoot 'skills-lock.json'
if ((Test-Path $rootMcpPath) -and (Test-Path $vsCodeMcpPath) -and (Test-Path $skillsLockPath)) {
    $rootMcp = Get-Content -LiteralPath $rootMcpPath -Raw | ConvertFrom-Json
    $vsCodeMcp = Get-Content -LiteralPath $vsCodeMcpPath -Raw | ConvertFrom-Json
    $skillsLock = Get-Content -LiteralPath $skillsLockPath -Raw | ConvertFrom-Json
    $mcpAssessment = Get-McpConfigurationAssessment -RootConfiguration $rootMcp -VsCodeConfiguration $vsCodeMcp
    $installedSkillPaths = @(
        foreach ($relativeRoot in @('.agents/skills', '.github/skills')) {
            $skillRoot = Join-Path $workspaceRoot $relativeRoot
            if (Test-Path $skillRoot) {
                Get-ChildItem -LiteralPath $skillRoot -Filter 'SKILL.md' -File -Recurse |
                    ForEach-Object { [IO.Path]::GetRelativePath($workspaceRoot, $_.FullName) }
            }
        }
    )
    $skillsAssessment = Get-SkillsLockAssessment -LockedSkills $skillsLock.skills -InstalledSkillPaths $installedSkillPaths
    Write-Check 'Root MCP configuration' ("{0} ({1} servers; endpoint values suppressed)" -f $mcpAssessment.RootConfigStatus, $mcpAssessment.RootServerCount)
    Write-Check 'VS Code MCP configuration' ("{0} ({1} servers)" -f $mcpAssessment.VsCodeConfigStatus, $mcpAssessment.VsCodeServerCount)
    Write-Check 'MCP runtime configuration source' $mcpAssessment.RuntimeConfigSource
    Write-Check 'MCP tool discoverability' $mcpAssessment.Discoverability
    Write-Check 'MCP callability' $mcpAssessment.Callability
    Write-Check 'MCP tool permission scope' $mcpAssessment.ToolPermissionScope
    Write-Check 'MCP wildcard tool selection' $(if ($mcpAssessment.WildcardToolExposure) { 'Present' } else { 'Not detected' })
    Write-Check 'Environment-specific MCP endpoint' $(if ($mcpAssessment.EnvironmentSpecificEndpointPresent) { 'Present; value suppressed' } else { 'Not detected' })
    Write-Check 'Skills lock/local path alignment' ("{0} ({1}/{2} locked paths unresolved; {3} local skills; {4} duplicate names)" -f $skillsAssessment.PathAlignment, $skillsAssessment.MismatchedPathCount, $skillsAssessment.LockedSkillCount, $skillsAssessment.InstalledSkillCount, $skillsAssessment.DuplicateSkillNameCount)
} else {
    Write-Check 'MCP/skills configuration assessment' 'UNKNOWN (one or more local configuration files are missing)'
}

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

# Match PAC's command-list entry; its help does not contain the literal phrase "model create".
$helpText = (& pac model help 2>&1 | Out-String)
if (Test-PacModelCreateCapability -HelpText $helpText -ExitCode $LASTEXITCODE) {
    Write-Check 'PAC model-driven app authoring' 'pac model create advertised'
} else {
    Write-Check 'PAC model-driven app authoring' 'Unverified/unavailable; review installed CLI help'
}
Write-Check 'Dataverse MCP readiness' 'Inspect in VS Code Copilot tool list (cannot verify from PAC alone)'
Write-Check 'Dataverse writes' 'NONE'
