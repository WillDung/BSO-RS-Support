#requires -Version 7.4
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'scripts\BsoRsCanonicalSourceFingerprint.psm1') -Force
$passed = 0

function Assert-Test {
    param([bool]$Condition, [string]$Name)
    if (-not $Condition) { throw "FAIL: $Name" }
    $script:passed++
}

function Get-TestRootFingerprint {
    param([Parameter(Mandatory)][string]$Path)
    [xml]$document = [IO.File]::ReadAllText($Path)
    $lines = foreach ($component in $document.SelectNodes('//*[local-name()="RootComponent"]')) {
        '{0}|{1}|{2}' -f $component.GetAttribute('type'),
            $component.GetAttribute('id'), $component.GetAttribute('schemaName')
    }
    Get-BsoRsSha256OfSortedUtf8Lines -Lines ([string[]]@($lines))
}

$hashA = 'a' * 64
$hashB = 'b' * 64
$ordered = @(
    [pscustomobject]@{ Path = 'zeta\file.bin'; Sha256 = $hashB }
    [pscustomobject]@{ Path = 'alpha/file.bin'; Sha256 = $hashA }
)
$reversed = @(
    [pscustomobject]@{ Path = 'alpha\file.bin'; Sha256 = $hashA }
    [pscustomobject]@{ Path = 'zeta/file.bin'; Sha256 = $hashB }
)
$orderedFingerprint = Get-BsoRsCanonicalSourceFingerprint -Files $ordered
Assert-Test ($orderedFingerprint -ceq (Get-BsoRsCanonicalSourceFingerprint -Files $reversed)) `
    'Ordinal path sorting and slash normalization make the aggregate order-independent'

$expectedLines = @("alpha/file.bin|$hashA", "zeta/file.bin|$hashB")
$expectedPayload = [Text.UTF8Encoding]::new($false).GetBytes($expectedLines -join "`n")
$expectedFingerprint = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($expectedPayload)).ToLowerInvariant()
Assert-Test ($orderedFingerprint -ceq $expectedFingerprint) `
    'Aggregate serialization uses UTF-8 without BOM and LF separators without a trailing newline'
Assert-Test ($orderedFingerprint -cne (Get-BsoRsSha256OfSortedUtf8Lines -Lines ($expectedLines -join "`r`n"))) `
    'CRLF separators produce a distinct digest'
Assert-Test ($orderedFingerprint -cne (Get-BsoRsSha256OfSortedUtf8Lines -Lines ($expectedLines + ''))) `
    'A trailing empty record produces a distinct digest'
$bomPayload = [byte[]]@(0xef, 0xbb, 0xbf) + $expectedPayload
$bomFingerprint = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bomPayload)).ToLowerInvariant()
Assert-Test ($orderedFingerprint -cne $bomFingerprint) `
    'UTF-8 BOM bytes are not silently introduced into the aggregate payload'

$duplicateRejected = $false
try {
    Get-BsoRsCanonicalSourceFingerprint -Files @(
        [pscustomobject]@{ Path = 'same\file'; Sha256 = $hashA }
        [pscustomobject]@{ Path = 'same/file'; Sha256 = $hashB }
    ) | Out-Null
} catch {
    $duplicateRejected = $true
}
Assert-Test $duplicateRejected 'Duplicate paths after separator normalization are rejected'

$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) "bso-rs-fingerprint-$([Guid]::NewGuid().ToString('N'))"
$repositoryIndexFile = $env:GIT_INDEX_FILE
try {
    if ($repositoryIndexFile) { Remove-Item Env:GIT_INDEX_FILE }
    $null = New-Item -ItemType Directory -Path $temporaryRoot
    $null = New-Item -ItemType Directory -Path (Join-Path $temporaryRoot 'solutions\Other') -Force
    $null = New-Item -ItemType Directory -Path (Join-Path $temporaryRoot 'solutions\CandidateCore') -Force
    $null = New-Item -ItemType Directory -Path (Join-Path $temporaryRoot 'solutions\obj') -Force

    [IO.File]::WriteAllText((Join-Path $temporaryRoot '.gitignore'), "bin/`nobj/`n")
    $solutionXmlPath = Join-Path $temporaryRoot 'solutions\Other\Solution.xml'
    [IO.File]::WriteAllText(
        $solutionXmlPath,
        '<ImportExportXml><SolutionManifest><RootComponents><RootComponent type="1" id="1" schemaName="os_sr_cand" /></RootComponents></SolutionManifest></ImportExportXml>',
        [Text.UTF8Encoding]::new($false)
    )
    $binaryPath = Join-Path $temporaryRoot 'solutions\CandidateCore\content.bin'
    [IO.File]::WriteAllBytes($binaryPath, [byte[]]@(0x00, 0x7f, 0xff))

    & git -C $temporaryRoot init --quiet
    if ($LASTEXITCODE -ne 0) { throw 'Unable to initialize the synthetic fingerprint repository.' }
    & git -C $temporaryRoot config core.autocrlf false
    if ($LASTEXITCODE -ne 0) { throw 'Unable to configure the synthetic fingerprint repository.' }
    & git -C $temporaryRoot add -- .gitignore solutions/CandidateCore/content.bin solutions/Other/Solution.xml
    if ($LASTEXITCODE -ne 0) { throw 'Unable to stage synthetic canonical source files.' }

    $baseline = Get-BsoRsCanonicalSourceInventory -RepositoryRoot $temporaryRoot
    Assert-Test ($baseline.FileCount -eq 2) 'Inventory includes only Git-index files below solutions'

    $null = New-Item -ItemType Directory -Path (Join-Path $temporaryRoot 'solutions\bin') -Force
    [IO.File]::WriteAllBytes((Join-Path $temporaryRoot 'solutions\bin\generated.dll'), [byte[]]@(1, 2, 3))
    [IO.File]::WriteAllText((Join-Path $temporaryRoot 'solutions\obj\generated.json'), '{"generated":true}')
    $withIgnoredOutputs = Get-BsoRsCanonicalSourceInventory -RepositoryRoot $temporaryRoot
    Assert-Test ($withIgnoredOutputs.FileCount -eq 2 -and $withIgnoredOutputs.Fingerprint -ceq $baseline.Fingerprint) `
        'Ignored bin/obj outputs do not enter the canonical inventory or change its fingerprint'

    $untrackedPath = Join-Path $temporaryRoot 'solutions\local-source.txt'
    [IO.File]::WriteAllText($untrackedPath, 'untracked source')
    $untrackedRejected = $false
    try {
        Get-BsoRsCanonicalSourceInventory -RepositoryRoot $temporaryRoot | Out-Null
    } catch {
        $untrackedRejected = $_.Exception.Message -like '*Unignored untracked files*'
    }
    Assert-Test $untrackedRejected 'Unignored untracked source fails closed instead of being omitted'
    Remove-Item -LiteralPath $untrackedPath -Force

    $rootFingerprintBefore = Get-TestRootFingerprint -Path $solutionXmlPath
    [IO.File]::WriteAllBytes($binaryPath, [byte[]]@(0xef, 0xbb, 0xbf, 0x61, 0x0d, 0x0a))
    $withBomAndCrLf = Get-BsoRsCanonicalSourceInventory -RepositoryRoot $temporaryRoot
    $rootFingerprintAfter = Get-TestRootFingerprint -Path $solutionXmlPath
    Assert-Test ($withBomAndCrLf.Fingerprint -cne $baseline.Fingerprint) `
        'Changing tracked raw file bytes, including BOM or CRLF bytes, changes the source fingerprint'
    Assert-Test (@($withBomAndCrLf.Files | Where-Object {
        $_.Path -ceq 'CandidateCore/content.bin' -and $_.Sha256 -ceq
            [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([byte[]]@(0xef, 0xbb, 0xbf, 0x61, 0x0d, 0x0a))).ToLowerInvariant()
    }).Count -eq 1) 'Per-file SHA-256 is calculated over exact raw bytes'
    Assert-Test ($rootFingerprintBefore -ceq $rootFingerprintAfter -and
        $withBomAndCrLf.Fingerprint -cne $baseline.Fingerprint) `
        'A non-root file change affects aggregate source but not the root-component fingerprint'
    Assert-Test ($withBomAndCrLf.Fingerprint -cne $baseline.Fingerprint) `
        'A changed source fingerprint detects a stale previously frozen pin'
} finally {
    if ($repositoryIndexFile) { $env:GIT_INDEX_FILE = $repositoryIndexFile }
    if (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}

$repositoryInventory = Get-BsoRsCanonicalSourceInventory -RepositoryRoot $root
$repositoryPaths = [string[]]@($repositoryInventory.Files | Select-Object -ExpandProperty Path)
$expectedRepositoryPaths = [string[]]@($repositoryPaths)
[Array]::Sort($expectedRepositoryPaths, [StringComparer]::Ordinal)
Assert-Test ($repositoryInventory.FileCount -eq $repositoryInventory.Files.Count -and
    [string]::Join('|', $repositoryPaths) -ceq [string]::Join('|', $expectedRepositoryPaths)) `
    'Current canonical inventory contains the expected sorted tracked source files'

Write-Output "BSO-RS canonical source fingerprint checks passed: $passed"
