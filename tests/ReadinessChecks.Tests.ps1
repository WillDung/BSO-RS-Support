#requires -Version 7.4
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$readinessChecks = Join-Path $PSScriptRoot '../scripts/ReadinessChecks.ps1'
$script:Passed = 0

function Assert-Test {
    param([bool]$Condition, [string]$Name)
    if (-not $Condition) { throw "FAIL: $Name" }
    $script:Passed++
}

. $readinessChecks

$supportedHelp = @'
Usage: pac model [list] [list-tables] [create] [genpage] [list-languages]

Commands:
  list               Lists all model-driven apps in the environment.
  create             Creates a new model-driven app.
'@
$unsupportedHelp = @'
Usage: pac model [list] [list-tables] [genpage] [list-languages]

Commands:
  list               Lists all model-driven apps in the environment.
'@

Assert-Test (Test-PacModelCreateCapability -HelpText $supportedHelp -ExitCode 0) 'Advertised model create command is detected'
Assert-Test (-not (Test-PacModelCreateCapability -HelpText $supportedHelp -ExitCode 1)) 'Failed PAC help command is not treated as capability evidence'
Assert-Test (-not (Test-PacModelCreateCapability -HelpText $unsupportedHelp -ExitCode 0)) 'Help without model create is not treated as capability evidence'

$rootConfig = [pscustomobject]@{
    mcpServers = [pscustomobject]@{
        dataverse = [pscustomobject]@{ url = 'https://example.invalid/mcp'; tools = @('*') }
    }
}
$workspaceConfig = [pscustomobject]@{ servers = [pscustomobject]@{} }
$mcp = Get-McpConfigurationAssessment -RootConfiguration $rootConfig -VsCodeConfiguration $workspaceConfig
Assert-Test ($mcp.RootConfigStatus -ceq 'CONFIGURED' -and $mcp.RootServerCount -eq 1) 'Root MCP declarations are reported as configured'
Assert-Test ($mcp.VsCodeConfigStatus -ceq 'EMPTY' -and $mcp.VsCodeServerCount -eq 0) 'Empty VS Code MCP configuration is distinguished'
Assert-Test ($mcp.RuntimeConfigSource -ceq 'UNKNOWN' -and $mcp.Discoverability -ceq 'UNKNOWN' -and $mcp.Callability -ceq 'UNKNOWN') 'Configuration presence does not imply runtime discovery or callability'
Assert-Test ($mcp.ToolPermissionScope -ceq 'UNKNOWN' -and $mcp.WildcardToolExposure -and $mcp.EnvironmentSpecificEndpointPresent) 'Wildcard and environment-specific endpoint are detected without returning values'
$noEndpointConfig = [pscustomobject]@{ mcpServers = [pscustomobject]@{ local = [pscustomobject]@{ command = 'tool'; args = @('serve') } } }
$noEndpointAssessment = Get-McpConfigurationAssessment -RootConfiguration $noEndpointConfig -VsCodeConfiguration $workspaceConfig
Assert-Test (-not $noEndpointAssessment.EnvironmentSpecificEndpointPresent -and -not $noEndpointAssessment.WildcardToolExposure) 'Local MCP command without optional URL/tools is handled safely'

$lockedSkills = [pscustomobject]@{
    'dv-metadata' = [pscustomobject]@{ skillPath = '.github/plugins/dataverse/skills/dv-metadata/SKILL.md' }
}
$aligned = Get-SkillsLockAssessment -LockedSkills $lockedSkills -InstalledSkillPaths @('.agents/skills/dv-metadata/SKILL.md')
Assert-Test ($aligned.PathAlignment -ceq 'MISMATCH' -and $aligned.MismatchedPathCount -eq 1) 'Stale lockfile path is reported as mismatch'
$aligned = Get-SkillsLockAssessment -LockedSkills $lockedSkills -InstalledSkillPaths @('.github/plugins/dataverse/skills/dv-metadata/SKILL.md')
Assert-Test ($aligned.PathAlignment -ceq 'ALIGNED' -and $aligned.MismatchedPathCount -eq 0) 'Matching lockfile path is reported as aligned'
$duplicates = Get-SkillsLockAssessment -LockedSkills ([pscustomobject]@{}) -InstalledSkillPaths @('.agents/skills/dv-metadata/SKILL.md', '.github/skills/dv-metadata/SKILL.md')
Assert-Test ($duplicates.DuplicateSkillNameCount -eq 1) 'Duplicate local skill names are counted'

Write-Output "PASS: $script:Passed synthetic readiness assertions; no PAC, authentication, or network calls."
