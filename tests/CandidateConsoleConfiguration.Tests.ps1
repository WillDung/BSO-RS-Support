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

    $rejected = $false
    try {
        & $generatorPath `
            -Mode STAGING `
            -OrganizationUrl 'https://test.example.invalid' `
            -EnvironmentId '11111111-1111-4111-8111-111111111111' `
            -OrganizationId '22222222-2222-4222-8222-222222222222' `
            -OutputConfigurationPath $rejectedOutputPath `
            -OutputHtmlPath $rejectedHtmlPath
    } catch {
        $rejected = $true
    }
    Assert-Test ($rejected -and -not (Test-Path -LiteralPath $rejectedOutputPath)) `
        'Reject unknown environment modes before producing target configuration'

    $releaseNeutralOutputPath = Join-Path ([IO.Path]::GetTempPath()) "release-neutral-$tempName.js"
    $releaseNeutralHtmlPath = Join-Path ([IO.Path]::GetTempPath()) "release-neutral-$tempName.html"
    & $generatorPath `
        -Mode UNCONFIGURED `
        -CandidateCoreEnabled:$false `
        -OutputConfigurationPath $releaseNeutralOutputPath `
        -OutputHtmlPath $releaseNeutralHtmlPath | Out-Null
    $releaseNeutralText = [IO.File]::ReadAllText($releaseNeutralOutputPath)
    $releaseNeutralMatch = [regex]::Match($releaseNeutralText, '(?s)const configuration = (?<json>\{.*?\});')
    $releaseNeutralConfiguration = $releaseNeutralMatch.Groups['json'].Value | ConvertFrom-Json
    $releaseNeutralHash = (Get-FileHash -LiteralPath $releaseNeutralOutputPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $releaseNeutralHtml = [IO.File]::ReadAllText($releaseNeutralHtmlPath)
    Assert-Test ($releaseNeutralMatch.Success -and
        $releaseNeutralConfiguration.mode -ceq 'UNCONFIGURED' -and
        $releaseNeutralConfiguration.environmentId -ceq '' -and
        $releaseNeutralConfiguration.organizationId -ceq '' -and
        $releaseNeutralConfiguration.organizationUrl -ceq '' -and
        $releaseNeutralConfiguration.candidateCoreEnabled -eq $false -and
        $releaseNeutralConfiguration.syntheticDataOnly -eq $true -and
        $releaseNeutralConfiguration.devDirectWriteFallbackEnabled -eq $false -and
        $releaseNeutralConfiguration.diagnosticsMode -ceq 'OFF' -and
        $releaseNeutralHtml.Contains("candidate-console-environment.js?v=$($releaseNeutralHash.Substring(0, 12))")) `
        'Generate an unbound, fail-closed release-neutral configuration and matching HTML cache token'
    Remove-Item -LiteralPath $releaseNeutralOutputPath, $releaseNeutralHtmlPath

    $releaseNeutralFailures = @(
        @{ Name = 'Candidate Core enabled'; Options = @{ CandidateCoreEnabled = $true } },
        @{ Name = 'organization URL binding'; Options = @{ OrganizationUrl = 'https://test.example.invalid' } },
        @{ Name = 'environment ID binding'; Options = @{ EnvironmentId = '11111111-1111-4111-8111-111111111111' } },
        @{ Name = 'non-synthetic mode'; Options = @{ SyntheticDataOnly = $false } },
        @{ Name = 'DEV direct-write fallback'; Options = @{ DevDirectWriteFallbackEnabled = $true } },
        @{ Name = 'diagnostics enabled'; Options = @{ DiagnosticsMode = 'SAFE' } },
        @{ Name = 'release profile'; Options = @{ ReleaseProfile = $true } }
    )
    foreach ($case in $releaseNeutralFailures) {
        $arguments = @{
            Mode = 'UNCONFIGURED'
            CandidateCoreEnabled = $false
            OutputConfigurationPath = $rejectedOutputPath
            OutputHtmlPath = $rejectedHtmlPath
        }
        foreach ($key in $case.Options.Keys) { $arguments[$key] = $case.Options[$key] }
        $rejected = $false
        try { & $generatorPath @arguments } catch { $rejected = $true }
        Assert-Test ($rejected -and
            -not (Test-Path -LiteralPath $rejectedOutputPath) -and
            -not (Test-Path -LiteralPath $rejectedHtmlPath)) `
            "Reject release-neutral configuration with $($case.Name)"
    }

    $releaseOutputPath = Join-Path ([IO.Path]::GetTempPath()) "release-$tempName.js"
    $releaseHtmlPath = Join-Path ([IO.Path]::GetTempPath()) "release-$tempName.html"
    & $generatorPath `
        -Mode TEST `
        -OrganizationUrl 'https://test.example.invalid' `
        -EnvironmentId '11111111-1111-4111-8111-111111111111' `
        -OrganizationId '22222222-2222-4222-8222-222222222222' `
        -OutputConfigurationPath $releaseOutputPath `
        -OutputHtmlPath $releaseHtmlPath `
        -ReleaseProfile | Out-Null
    $releaseText = [IO.File]::ReadAllText($releaseOutputPath)
    $releaseMatch = [regex]::Match($releaseText, '(?s)const configuration = (?<json>\{.*?\});')
    $releaseConfiguration = $releaseMatch.Groups['json'].Value | ConvertFrom-Json
    Assert-Test ($releaseMatch.Success -and
        $releaseConfiguration.candidateCoreEnabled -eq $true -and
        $releaseConfiguration.syntheticDataOnly -eq $true -and
        $releaseConfiguration.devDirectWriteFallbackEnabled -eq $false -and
        $releaseConfiguration.diagnosticsMode -ceq 'OFF') `
        'Emit a fail-closed synthetic TEST release profile'
    Remove-Item -LiteralPath $releaseOutputPath, $releaseHtmlPath

    $devReleaseOutputPath = Join-Path ([IO.Path]::GetTempPath()) "release-dev-$tempName.js"
    $devReleaseHtmlPath = Join-Path ([IO.Path]::GetTempPath()) "release-dev-$tempName.html"
    & $generatorPath `
        -Mode DEV `
        -OrganizationUrl 'https://dev.example.invalid' `
        -EnvironmentId '11111111-1111-4111-8111-111111111111' `
        -OrganizationId '22222222-2222-4222-8222-222222222222' `
        -OutputConfigurationPath $devReleaseOutputPath `
        -OutputHtmlPath $devReleaseHtmlPath `
        -ReleaseProfile | Out-Null
    $devReleaseText = [IO.File]::ReadAllText($devReleaseOutputPath)
    $devReleaseMatch = [regex]::Match($devReleaseText, '(?s)const configuration = (?<json>\{.*?\});')
    $devReleaseConfiguration = $devReleaseMatch.Groups['json'].Value | ConvertFrom-Json
    Assert-Test ($devReleaseMatch.Success -and $devReleaseConfiguration.mode -ceq 'DEV' -and
        $devReleaseConfiguration.environmentId -ceq '11111111-1111-4111-8111-111111111111' -and
        $devReleaseConfiguration.organizationId -ceq '22222222-2222-4222-8222-222222222222' -and
        $devReleaseConfiguration.candidateCoreEnabled -eq $true -and
        $devReleaseConfiguration.syntheticDataOnly -eq $true -and
        $devReleaseConfiguration.devDirectWriteFallbackEnabled -eq $false -and
        $devReleaseConfiguration.diagnosticsMode -ceq 'OFF') `
        'Bind DEV release configuration to explicit target evidence and keep fallback disabled'
    Remove-Item -LiteralPath $devReleaseOutputPath, $devReleaseHtmlPath

    $releaseProfileFailures = @(
        @{ Name = 'Candidate Core disabled'; Options = @{ CandidateCoreEnabled = $false } },
        @{ Name = 'non-synthetic mode'; Options = @{ SyntheticDataOnly = $false } },
        @{ Name = 'DEV direct-write fallback'; Options = @{ DevDirectWriteFallbackEnabled = $true } },
        @{ Name = 'diagnostics enabled'; Options = @{ DiagnosticsMode = 'SAFE' } }
    )
    foreach ($case in $releaseProfileFailures) {
        $arguments = @{
            Mode = 'TEST'
            OrganizationUrl = 'https://test.example.invalid'
            EnvironmentId = '11111111-1111-4111-8111-111111111111'
            OrganizationId = '22222222-2222-4222-8222-222222222222'
            OutputConfigurationPath = $rejectedOutputPath
            OutputHtmlPath = $rejectedHtmlPath
            ReleaseProfile = $true
        }
        foreach ($key in $case.Options.Keys) { $arguments[$key] = $case.Options[$key] }
        $rejected = $false
        try { & $generatorPath @arguments } catch { $rejected = $true }
        Assert-Test ($rejected -and -not (Test-Path -LiteralPath $rejectedOutputPath)) `
            "Reject release profile with $($case.Name)"
    }
} finally {
    foreach ($path in @($outputPath, $htmlOutputPath, $rejectedOutputPath, $rejectedHtmlPath,
        $releaseNeutralOutputPath, $releaseNeutralHtmlPath,
        $releaseOutputPath, $releaseHtmlPath, $devReleaseOutputPath, $devReleaseHtmlPath)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$path) -and
            (Test-Path -LiteralPath $path)) {
            Remove-Item -LiteralPath $path
        }
    }
}

Write-Output "Candidate Console configuration checks passed: $passed"
