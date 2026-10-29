#requires -Version 7.4
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$OutputPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$solutionsRoot = Join-Path $repositoryRoot 'solutions'
$packageHash = 'dbf6087203508c8a0016fede8bea2c77a3734a9e294b407197faa08235203b91'
$packageAssemblyHash = '05e983e86290bb70ba82b73177c21dc3a1d87fd14f0d4aeea39af062ed0a721a'
$outputFullPath = [IO.Path]::GetFullPath($OutputPath)
$relativeOutputPath = [IO.Path]::GetRelativePath($repositoryRoot, $outputFullPath)
if ($relativeOutputPath -eq '.' -or
    (-not [IO.Path]::IsPathRooted($relativeOutputPath) -and $relativeOutputPath -notmatch '^\.\.(\\|$)')) {
    throw 'Build output must be outside the repository.'
}
if (Test-Path -LiteralPath $outputFullPath) {
    throw 'Build output already exists; choose a new path.'
}
$outputParent = Split-Path -Parent $outputFullPath
if (-not (Test-Path -LiteralPath $outputParent -PathType Container)) {
    throw 'Build output directory must already exist.'
}
if (-not (Get-Command pac -ErrorAction SilentlyContinue)) {
    throw 'PAC CLI is required for the local source pack and round-trip check.'
}

$workRoot = Join-Path ([IO.Path]::GetTempPath()) "bso-rs-solution-$([Guid]::NewGuid().ToString('N'))"
$sourceRoot = Join-Path $workRoot 'source'
$roundTripRoot = Join-Path $workRoot 'roundtrip'
$outputCreated = $false

function Get-RootComponentSignature {
    param([Parameter(Mandatory)][string]$SolutionPath)
    [xml]$xml = [IO.File]::ReadAllText($SolutionPath)
    @($xml.SelectNodes('//*[local-name()="RootComponent"]') | ForEach-Object {
        '{0}|{1}|{2}' -f $_.GetAttribute('type'), $_.GetAttribute('id'), $_.GetAttribute('schemaName')
    } | Sort-Object)
}

function Get-Sha256 {
    param([Parameter(Mandatory)][byte[]]$Bytes)
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes)).ToLowerInvariant()
}

try {
    New-Item -ItemType Directory -Path $sourceRoot -Force | Out-Null
    foreach ($directory in @(
        'AppModules', 'AppModuleSiteMaps', 'customapis', 'Entities',
        'OptionSets', 'Other', 'pluginpackages', 'Roles', 'WebResources'
    )) {
        $source = Join-Path $solutionsRoot $directory
        if (-not (Test-Path -LiteralPath $source -PathType Container)) {
            throw "Required canonical Solution source is missing: $directory"
        }
        Copy-Item -LiteralPath $source -Destination $sourceRoot -Recurse
    }

    $payloadSource = Join-Path $solutionsRoot 'CandidateConsole\WebResources\os_\bso'
    $payloadTarget = Join-Path $sourceRoot 'WebResources\os_\bso'
    New-Item -ItemType Directory -Path $payloadTarget -Force | Out-Null
    foreach ($fileName in @(
        'candidate-console-environment.js',
        'candidate-console-policy.js',
        'candidate-console.css',
        'candidate-console.html',
        'candidate-console.js'
    )) {
        $source = Join-Path $payloadSource $fileName
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
            throw "Canonical web-resource payload is missing: $fileName"
        }
        Copy-Item -LiteralPath $source -Destination $payloadTarget
    }

    $manifestPath = Join-Path $sourceRoot 'Other\Solution.xml'
    $manifestSignatures = @(Get-RootComponentSignature -SolutionPath $manifestPath)
    if ($manifestSignatures.Count -ne 20 -or
        $manifestSignatures -match '^(91|92)\|' -or
        $manifestSignatures -match 'os_sr_devcs') {
        throw 'Release manifest must contain exactly the 20 approved roots and no assembly or guard registrations.'
    }
    if ((Test-Path -LiteralPath (Join-Path $sourceRoot 'SdkMessageProcessingSteps')) -or
        (Test-Path -LiteralPath (Join-Path $sourceRoot 'PluginAssemblies')) -or
        (Test-Path -LiteralPath (Join-Path $sourceRoot 'customapis\os_sr_devcs'))) {
        throw 'Inactive guard, rollback assembly, or temporary DEV API source leaked into the release staging tree.'
    }
    if (-not (Test-Path -LiteralPath (Join-Path $sourceRoot 'customapis\os_sr_cact\customapi.xml') -PathType Leaf)) {
        throw 'Candidate Core Custom API source is missing from the release staging tree.'
    }

    $environmentSource = [IO.File]::ReadAllText((Join-Path $payloadTarget 'candidate-console-environment.js'))
    if ($environmentSource -notmatch 'mode:\s*"UNCONFIGURED"' -or
        $environmentSource -notmatch 'candidateCoreEnabled:\s*false' -or
        $environmentSource -notmatch 'syntheticDataOnly:\s*true' -or
        $environmentSource -notmatch 'devDirectWriteFallbackEnabled:\s*false' -or
        $environmentSource -match 'organizationUrl:\s*"https?://') {
        throw 'Portable source configuration must remain unconfigured and fail closed.'
    }

    $htmlPath = Join-Path $payloadTarget 'candidate-console.html'
    $html = [IO.File]::ReadAllText($htmlPath)
    foreach ($resourceName in @(
        'candidate-console-environment.js',
        'candidate-console-policy.js',
        'candidate-console.js'
    )) {
        $resourcePath = Join-Path $payloadTarget $resourceName
        $expectedVersion = (Get-Sha256 -Bytes ([IO.File]::ReadAllBytes($resourcePath))).Substring(0, 12)
        $pattern = [regex]::Escape($resourceName) + '\?v=([0-9a-f]{12})'
        $match = [regex]::Match($html, $pattern)
        if (-not $match.Success -or $match.Groups[1].Value -cne $expectedVersion) {
            throw "Candidate Console cache-bust does not match the current source hash: $resourceName"
        }
    }

    $packagePath = Join-Path $sourceRoot 'pluginpackages\os_sr_cact_pkg\package\os_sr_cact_pkg.nupkg'
    if (-not (Test-Path -LiteralPath $packagePath -PathType Leaf) -or
        (Get-Sha256 -Bytes ([IO.File]::ReadAllBytes($packagePath))) -cne $packageHash) {
        throw 'Accepted unsigned package artifact hash does not match the approved local pin.'
    }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($packagePath)
    try {
        $assemblyEntry = $archive.GetEntry('lib/net462/os_sr_cact.dll')
        if ($null -eq $assemblyEntry) { throw 'Accepted package does not contain the expected plug-in assembly.' }
        $assemblyStream = $assemblyEntry.Open()
        $memoryStream = [IO.MemoryStream]::new()
        try {
            $assemblyStream.CopyTo($memoryStream)
            if ((Get-Sha256 -Bytes $memoryStream.ToArray()) -cne $packageAssemblyHash) {
                throw 'Accepted package assembly hash does not match the approved local pin.'
            }
        } finally {
            $memoryStream.Dispose()
            $assemblyStream.Dispose()
        }
    } finally { $archive.Dispose() }

    $pack = @(& pac solution pack --zipfile $outputFullPath --folder $sourceRoot --packagetype Unmanaged 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "PAC unmanaged source pack failed: $($pack -join ' ')"
    }
    $outputCreated = $true

    New-Item -ItemType Directory -Path $roundTripRoot -Force | Out-Null
    $unpack = @(& pac solution unpack --zipfile $outputFullPath --folder $roundTripRoot --packagetype Unmanaged 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "PAC unmanaged source unpack failed: $($unpack -join ' ')"
    }

    $packedSignatures = @(Get-RootComponentSignature -SolutionPath (Join-Path $roundTripRoot 'Other\Solution.xml'))
    if ($packedSignatures.Count -ne 20 -or
        [string]::Join("`n", $packedSignatures) -cne [string]::Join("`n", $manifestSignatures)) {
        throw 'PAC source round-trip changed the approved Solution root component set.'
    }
    if ((Get-Sha256 -Bytes ([IO.File]::ReadAllBytes((Join-Path $roundTripRoot 'pluginpackages\os_sr_cact_pkg\package\os_sr_cact_pkg.nupkg')))) -cne $packageHash) {
        throw 'PAC source round-trip changed the accepted Candidate Core package.'
    }
    if ((Get-ChildItem -LiteralPath $roundTripRoot -Directory -Name) -contains 'SdkMessageProcessingSteps' -or
        (Get-ChildItem -LiteralPath $roundTripRoot -Directory -Name) -contains 'PluginAssemblies' -or
        (Get-ChildItem -LiteralPath $roundTripRoot 'customapis' -Directory -Name) -contains 'os_sr_devcs') {
        throw 'PAC source round-trip reintroduced an excluded release component.'
    }
    if (-not (Test-Path -LiteralPath (Join-Path $roundTripRoot 'customapis\os_sr_cact\customapi.xml') -PathType Leaf)) {
        throw 'PAC source round-trip omitted the Candidate Core Custom API.'
    }

    [pscustomobject]@{
        Result = 'UNMANAGED_SOURCE_ROUNDTRIP_PASS'
        RootComponents = $packedSignatures.Count
        PackageSha256 = $packageHash
        PackageAssemblySha256 = $packageAssemblyHash
        ManagedRelease = 'MANAGED_BUILD_REQUIRES_APPROVED_TEST_ENVIRONMENT'
        OutputPath = $outputFullPath
    }
} catch {
    if ($outputCreated -and (Test-Path -LiteralPath $outputFullPath)) {
        Remove-Item -LiteralPath $outputFullPath -Force
    }
    throw
} finally {
    if (Test-Path -LiteralPath $workRoot -PathType Container) {
        Remove-Item -LiteralPath $workRoot -Recurse -Force
    }
}
