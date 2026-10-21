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

Write-Output "PASS: $script:Passed synthetic readiness assertions; no PAC, authentication, or network calls."
