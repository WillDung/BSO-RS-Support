#requires -Version 7.4
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$generatorPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts\New-BsoRsCandidateConsoleEnvironmentConfig.ps1'
$tempName = "candidate-console-config-$([Guid]::NewGuid().ToString('N'))"
$outputPath = Join-Path ([IO.Path]::GetTempPath()) "$tempName.js"
$htmlOutputPath = Join-Path ([IO.Path]::GetTempPath()) "$tempName.html"
$rejectedOutputPath = $null
$rejectedHtmlPath = $null
$passed = 0

function Assert-Test {
    param([bool]$Condition, [string]$Name)
    if (-not $Condition) { throw "FAIL: $Name" }
    $script:passed++
}

try {
    & $generatorPath `
        -Mode DEV `
        -OrganizationUrl 'https://dev.example.invalid' `
        -EnvironmentId '11111111-1111-4111-8111-111111111111' `
        -OrganizationId '22222222-2222-4222-8222-222222222222' `
        -OutputConfigurationPath $outputPath `
        -OutputHtmlPath $htmlOutputPath `
        -DevDirectWriteFallbackEnabled | Out-Null

    $generated = [IO.File]::ReadAllText($outputPath)
    $match = [regex]::Match($generated, '(?s)const configuration = (?<json>\{.*?\});')
    Assert-Test $match.Success 'Emit the generated settings as a parseable configuration object'
    $configuration = $match.Groups['json'].Value | ConvertFrom-Json
    Assert-Test ($configuration.mode -ceq 'DEV' -and
        $configuration.environmentId -ceq '11111111-1111-4111-8111-111111111111' -and
        $configuration.organizationId -ceq '22222222-2222-4222-8222-222222222222' -and
        $configuration.organizationUrl -ceq 'https://dev.example.invalid' -and
        $configuration.candidateCoreEnabled -eq $true -and
        $configuration.syntheticDataOnly -eq $true -and
        $configuration.devDirectWriteFallbackEnabled -eq $true -and
        $configuration.diagnosticsMode -ceq 'OFF') 'Serialize only the requested environment policy'
    Assert-Test ($generated -notmatch 'https://[^"]+\.crm\d+\.dynamics\.com' -and
        $outputPath -notlike "$((Split-Path -Parent $PSScriptRoot))*" -and
        $htmlOutputPath -notlike "$((Split-Path -Parent $PSScriptRoot))*") `
        'Use a synthetic external target in this test and keep generated configuration outside the repository'
    $generatedHash = (Get-FileHash -LiteralPath $outputPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $generatedHtml = [IO.File]::ReadAllText($htmlOutputPath)
    Assert-Test ($generatedHtml.Contains("candidate-console-environment.js?v=$($generatedHash.Substring(0, 12))")) `
        'Cache-bust the generated environment resource from its actual content hash'

    Remove-Item -LiteralPath $outputPath
    Remove-Item -LiteralPath $htmlOutputPath
    $rejectedName = "candidate-console-config-$([Guid]::NewGuid().ToString('N'))"
    $rejectedOutputPath = Join-Path ([IO.Path]::GetTempPath()) "$rejectedName.js"
    $rejectedHtmlPath = Join-Path ([IO.Path]::GetTempPath()) "$rejectedName.html"
    $rejected = $false
    try {
        & $generatorPath `
            -Mode TEST `
            -OrganizationUrl 'https://test.example.invalid' `
            -EnvironmentId '11111111-1111-4111-8111-111111111111' `
            -OrganizationId '22222222-2222-4222-8222-222222222222' `
            -OutputConfigurationPath $rejectedOutputPath `
            -OutputHtmlPath $rejectedHtmlPath `
            -DevDirectWriteFallbackEnabled
    } catch {
        $rejected = $true
    }
    Assert-Test ($rejected -and -not (Test-Path -LiteralPath $rejectedOutputPath)) `
        'Reject non-DEV direct-write fallback before producing a configuration file'

    $rejected = $false
    try {
        & $generatorPath `
            -Mode DEV `
            -OrganizationUrl 'https://dev.example.invalid' `
            -EnvironmentId '11111111-1111-4111-8111-111111111111' `
            -OrganizationId '22222222-2222-4222-8222-222222222222' `
            -OutputConfigurationPath $rejectedOutputPath `
            -OutputHtmlPath $rejectedHtmlPath `
            -SyntheticDataOnly:$false
    } catch {
        $rejected = $true
    }
    Assert-Test ($rejected -and -not (Test-Path -LiteralPath $rejectedOutputPath)) `
        'Reject non-synthetic DEV configuration before producing a file'
} finally {
    foreach ($path in @($outputPath, $htmlOutputPath, $rejectedOutputPath, $rejectedHtmlPath)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$path) -and
            (Test-Path -LiteralPath $path)) {
            Remove-Item -LiteralPath $path
        }
    }
}

Write-Output "Candidate Console configuration checks passed: $passed"
