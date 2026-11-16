#requires -Version 7.4
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = Split-Path $PSScriptRoot -Parent
$tokens = $null
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $root 'scripts\Deploy-BsoRsNormalCreateRelease.ps1'), [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'Deployment script syntax errors.' }
foreach ($name in @('Save-Json', 'Write-Step', 'Request', 'One', 'Assert-Disabled', 'Core')) {
    $function = $ast.EndBlock.Statements | Where-Object {
        $_ -is [Management.Automation.Language.FunctionDefinitionAst] -and $_.Name -ceq $name
    }
    . ([scriptblock]::Create($function.Extent.Text))
}
$checks = 0
function Rejects {
    param([scriptblock]$Action, [string]$Expected)
    $caught = $null
    try { & $Action } catch { $caught = $_.Exception.Message }
    if (-not $caught -or $caught -notlike "*$Expected*") { throw "Expected rejection: $Expected; received: $caught" }
    $script:checks++
}
$OrganizationUrl = 'https://synthetic.invalid'
$script:ApiRoot = "$OrganizationUrl/api/data/v9.2/"
$script:AccessToken = 'SYNTHETIC_NOT_A_TOKEN'
$script:httpCalls = 0
function Invoke-WebRequest { $script:httpCalls++; throw 'OFFLINE_NETWORK_FORBIDDEN' }
Rejects { Request '../outside' } 'REQUEST_ORIGIN_REJECTED'
Rejects { Request 'webresourceset(00000000-0000-0000-0000-000000000001)' 'PATCH' @{ content = 'synthetic' } } 'CONDITIONAL_WRITE_REQUIRED'
Rejects { Request 'os_sr_cands' 'POST' @{ name = 'synthetic' } } 'WRITE_OUTSIDE_DELTA'
$ExpectedOrganizationId = [guid]'00000000-0000-0000-0000-000000000001'
Rejects { Request 'environmentvariablevalues' 'POST' @{ value = 'v1|enabled=true|organizationId=00000000-0000-0000-0000-000000000001' } } 'VALUE_WRITE_REJECTED'
if ($script:httpCalls) { throw 'A rejected request reached HTTP.' }
$checks++
$ExpectedBundleManifestSha256 = 'synthetic'
$bundle = Join-Path ([IO.Path]::GetTempPath()) ("normal-release-" + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path (Join-Path $bundle 'journals')
try {
    $script:writes = 0
    $path = 'synthetic-payload-path-not-the-journal'
    $script:observedPayloadPath = $null
    Write-Step 'one-shot' { $script:writes++; $script:observedPayloadPath = $path }
    if ($script:observedPayloadPath -cne $path) { throw 'The dispatch journal shadowed the payload path.' }
    $checks++
    Rejects { Write-Step 'one-shot' { $script:writes++ } } 'already exists'
    if ($script:writes -ne 1) { throw 'Duplicate dispatch was not blocked.' }
    $checks++
    Rejects { Write-Step 'uncertain' { $script:writes++; throw 'AMBIGUOUS_ACK' } } 'STOP_WITHOUT_RETRY'
    Rejects { Write-Step 'uncertain' { $script:writes++ } } 'already exists'
    $journal = Get-Content (Join-Path $bundle 'journals\uncertain.json') -Raw | ConvertFrom-Json
    if ($journal.state -cne 'DISPATCH_RESERVED' -or $script:writes -ne 2) { throw 'Uncertain dispatch was retried or concealed.' }
    $checks++
} finally {
    Remove-Item -LiteralPath (Join-Path $bundle 'journals\one-shot.json')
    Remove-Item -LiteralPath (Join-Path $bundle 'journals\uncertain.json')
    Remove-Item -LiteralPath (Join-Path $bundle 'journals')
    Remove-Item -LiteralPath $bundle
}
$plan = @{ disabledConfiguration = 'v1|enabled=false|organizationId=00000000-0000-0000-0000-000000000001' }
$script:configValues = @(@{ environmentvariablevalueid = 'synthetic'; value = $plan.disabledConfiguration; statecode = 0 })
function Get-PagedRows {
    param([string]$Path)
    if ($Path.StartsWith('environmentvariabledefinitions')) {
        @{ environmentvariabledefinitionid = 'synthetic'; type = 100000000; statecode = 0 }
    } else { $script:configValues }
}
Assert-Disabled
$checks++
$script:configValues += $script:configValues[0]
Rejects { Assert-Disabled } 'AMBIGUOUS:CONFIG_VALUE'
$script:configValues = @(@{ value = $plan.disabledConfiguration.Replace('false', 'true'); statecode = 0 })
Rejects { Assert-Disabled } 'CONFIGURATION_NOT_DISABLED'
$script:configValues = @(@{ value = $plan.disabledConfiguration; statecode = 1 })
Rejects { Assert-Disabled } 'CONFIGURATION_NOT_DISABLED'
"NORMAL Create release tooling checks passed: $checks"
