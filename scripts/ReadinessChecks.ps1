function Test-PacModelCreateCapability {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$HelpText,
        [Parameter(Mandatory = $true)][int]$ExitCode
    )

    return ($ExitCode -eq 0) -and ($HelpText -match '(?im)^\s*create\s+Creates a new model-driven app\.\s*$')
}
