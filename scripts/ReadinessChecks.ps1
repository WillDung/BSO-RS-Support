function Test-PacModelCreateCapability {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$HelpText,
        [Parameter(Mandatory = $true)][int]$ExitCode
    )

    return ($ExitCode -eq 0) -and ($HelpText -match '(?im)^\s*create\s+Creates a new model-driven app\.\s*$')
}

function Get-McpConfigurationAssessment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$RootConfiguration,
        [Parameter(Mandatory = $true)][object]$VsCodeConfiguration
    )

    $rootServers = @($RootConfiguration.mcpServers.PSObject.Properties)
    $vsCodeServers = @($VsCodeConfiguration.servers.PSObject.Properties)
    $wildcardTools = $false
    $environmentEndpoint = $false
    foreach ($server in $rootServers) {
        $toolsProperty = $server.Value.PSObject.Properties['tools']
        $urlProperty = $server.Value.PSObject.Properties['url']
        if ($toolsProperty -and @($toolsProperty.Value) -contains '*') { $wildcardTools = $true }
        if ($urlProperty -and -not [string]::IsNullOrWhiteSpace([string]$urlProperty.Value)) { $environmentEndpoint = $true }
    }

    [pscustomobject]@{
        RootConfigStatus = if ($rootServers.Count) { 'CONFIGURED' } else { 'UNKNOWN' }
        RootServerCount = $rootServers.Count
        VsCodeConfigStatus = if ($vsCodeServers.Count) { 'CONFIGURED' } else { 'EMPTY' }
        VsCodeServerCount = $vsCodeServers.Count
        RuntimeConfigSource = 'UNKNOWN'
        Discoverability = 'UNKNOWN'
        Callability = 'UNKNOWN'
        ToolPermissionScope = 'UNKNOWN'
        WildcardToolExposure = $wildcardTools
        EnvironmentSpecificEndpointPresent = $environmentEndpoint
    }
}

function Get-SkillsLockAssessment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$LockedSkills,
        [Parameter(Mandatory = $true)][string[]]$InstalledSkillPaths
    )

    $lockedEntries = @($LockedSkills.PSObject.Properties)
    $normalizedInstalledPaths = @($InstalledSkillPaths | ForEach-Object { ([string]$_).Replace('\', '/') })
    $mismatchedEntries = @(
        $lockedEntries | Where-Object {
            $lockedPath = ([string]$_.Value.skillPath).Replace('\', '/')
            $lockedPath -notin $normalizedInstalledPaths
        }
    )
    $installedNames = @(
        $InstalledSkillPaths | ForEach-Object {
            $parts = ([string]$_).Replace('\', '/').Split('/')
            if ($parts.Count -ge 3 -and $parts[-1] -ceq 'SKILL.md') { $parts[-2] }
        }
    )
    $duplicateNames = @($installedNames | Group-Object | Where-Object Count -gt 1)

    [pscustomobject]@{
        PathAlignment = if ($mismatchedEntries.Count) { 'MISMATCH' } else { 'ALIGNED' }
        LockedSkillCount = $lockedEntries.Count
        MismatchedPathCount = $mismatchedEntries.Count
        InstalledSkillCount = $installedNames.Count
        DuplicateSkillNameCount = $duplicateNames.Count
    }
}
