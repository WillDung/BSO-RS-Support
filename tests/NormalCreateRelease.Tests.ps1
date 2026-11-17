#requires -Version 7.4
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = Split-Path $PSScriptRoot -Parent
$tokens = $null
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $root 'scripts\Deploy-BsoRsNormalCreateRelease.ps1'), [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'Deployment script syntax errors.' }
foreach ($name in @('Save-Json', 'Write-Step', 'Request', 'One', 'Assert-Disabled',
    'Assert-Enabled', 'Get-NormalConfiguration', 'Core')) {
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
$plan = @{
    disabledConfiguration = 'v1|enabled=false|organizationId=00000000-0000-0000-0000-000000000001'
    enabledConfiguration = 'v1|enabled=true|organizationId=00000000-0000-0000-0000-000000000001'
}
$ExpectedOrganizationId = [guid]'00000000-0000-0000-0000-000000000001'
$script:configValues = @(@{
    environmentvariablevalueid = '00000000-0000-0000-0000-000000000002'
    value = $plan.disabledConfiguration
    statecode = 0
    _environmentvariabledefinitionid_value = 'synthetic-definition-id'
})
$script:configRow = [ordered]@{
    environmentvariablevalueid = '00000000-0000-0000-0000-000000000002'
    value = $plan.disabledConfiguration
    statecode = 0
    _environmentvariabledefinitionid_value = 'synthetic-definition-id'
    '@odata.etag' = 'W/"synthetic"'
}
function Get-PagedRows {
    param([string]$Path)
    if ($Path.StartsWith('environmentvariabledefinitions')) {
        @{ environmentvariabledefinitionid = 'synthetic-definition-id'; schemaname = 'os_sr_ncrcfg'; type = 100000000; statecode = 0 }
    } else { $script:configValues }
}
function Invoke-WebRequest {
    param($Uri, $Method, $Headers, $Body, $ContentType, $TimeoutSec,
        $MaximumRetryCount, $MaximumRedirection, $SkipHttpErrorCheck)
    $script:httpCalls++
    if ($Method -eq 'GET') {
        return [pscustomobject]@{ StatusCode = 200; Content = ConvertTo-Json $script:configRow -Compress }
    }
    $script:capturedRequest = [pscustomobject]@{
        Uri = [string]$Uri; Method = $Method; Headers = $Headers; Body = $Body
    }
    [pscustomobject]@{ StatusCode = 204; Content = '' }
}
Assert-Disabled
$checks++
$script:configValues += $script:configValues[0]
Rejects { Assert-Disabled } 'AMBIGUOUS:CONFIG_VALUE'
$script:configValues = @(@{
    environmentvariablevalueid = '00000000-0000-0000-0000-000000000002'
    value = $plan.enabledConfiguration
    statecode = 0
    _environmentvariabledefinitionid_value = 'synthetic-definition-id'
})
$script:configRow.value = $plan.enabledConfiguration
$null = Assert-Enabled
$checks++
Rejects { Assert-Disabled } 'CONFIGURATION_NOT_DISABLED'
$script:configValues = @(@{
    environmentvariablevalueid = '00000000-0000-0000-0000-000000000002'
    value = $plan.disabledConfiguration
    statecode = 1
    _environmentvariabledefinitionid_value = 'synthetic-definition-id'
})
$script:configRow.value = $plan.disabledConfiguration
$script:configRow.statecode = 1
Rejects { Assert-Disabled } 'CONFIGURATION_NOT_DISABLED'
$script:configValues[0].statecode = 0
$script:configRow.statecode = 0
$script:Mode = 'Activate'
$script:ActivationWriteAllowed = $true
$script:ActivationValueId = '00000000-0000-0000-0000-000000000002'
$script:ActivationExpectedEtag = 'W/"synthetic"'
$script:ActivationExpectedValue = $plan.enabledConfiguration
$beforeRejectedPatches = $script:httpCalls
Rejects {
    Request -Path 'environmentvariablevalues(00000000-0000-0000-0000-000000000003)' `
        -Method 'PATCH' -Body @{ value = $script:ActivationExpectedValue } -ETag $script:ActivationExpectedEtag
} 'CONFIGURATION_WRITE_REJECTED'
Rejects {
    Request -Path "environmentvariablevalues($script:ActivationValueId)" -Method 'PATCH' `
        -Body @{ value = $plan.disabledConfiguration } -ETag $script:ActivationExpectedEtag
} 'CONFIGURATION_WRITE_REJECTED'
Rejects {
    Request -Path "environmentvariablevalues($script:ActivationValueId)" -Method 'PATCH' `
        -Body @{ value = $script:ActivationExpectedValue } -ETag 'W/"stale"'
} 'CONFIGURATION_WRITE_REJECTED'
if ($script:httpCalls -ne $beforeRejectedPatches) { throw 'A rejected gate write reached HTTP.' }
Request -Path "environmentvariablevalues($script:ActivationValueId)" -Method 'PATCH' `
    -Body @{ value = $script:ActivationExpectedValue } -ETag $script:ActivationExpectedEtag
if ($script:httpCalls -ne $beforeRejectedPatches + 1 -or
    $script:capturedRequest.Method -cne 'PATCH' -or
    $script:capturedRequest.Headers['If-Match'] -cne 'W/"synthetic"' -or
    ($script:capturedRequest.Body | ConvertFrom-Json).value -cne $plan.enabledConfiguration) {
    throw 'The authorized gate patch was not a single exact ETag-conditional update.'
}
$checks++
"NORMAL Create release tooling checks passed: $checks"
