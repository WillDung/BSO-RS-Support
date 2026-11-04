#requires -Version 7.4
[CmdletBinding()]
param(
    [ValidateSet('Plan', 'Preflight', 'Apply', 'Reconcile')][string]$Mode = 'Plan',
    [ValidateSet('DEV', 'TEST', 'PROD')][string]$TargetProfile,
    [string]$OrganizationUrl,
    [string]$ExpectedEnvironmentDisplayName,
    [string]$ExpectedEnvironmentId,
    [string]$ExpectedOrganizationId,
    [string]$ArtifactPath,
    [string]$ExpectedPackageSha256,
    [string]$ExpectedAssemblySha256,
    [string]$ExpectedPackageUniqueName,
    [string]$ExpectedHandlerTypeName,
    [string]$ExpectedSolutionUniqueName = 'os_sr_bso_rs_support',
    [string]$ExpectedDevelopmentBaselinePath,
    [string]$ExpectedDevelopmentApiPlanPath,
    [string]$ExpectedDevelopmentApiPlanSha256,
    [string]$JournalPath,
    [string]$ApprovalEvidencePath,
    [string]$ManagedSolutionArtifactPath,
    [switch]$DevelopmentSourceAheadOfFrozenRelease,
    [string]$PacPath = 'pac'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$script:Root = Split-Path $PSScriptRoot -Parent
$script:ManifestPath = Join-Path $script:Root 'docs\RELEASE_INPUT_MANIFEST.json'
$script:Manifest = Get-Content -LiteralPath $script:ManifestPath -Raw | ConvertFrom-Json
$script:ApiRoot = $null
$script:AccessToken = $null
$script:ReadRequestCount = 0
$script:DispatchCount = 0
$script:PacIdentityCheckCount = 0
$script:PacVersionCheckCount = 0
$script:PriorDispatchCount = 0

function Stop-PackageUpdater {
    param([Parameter(Mandatory)][string]$FailureCode)
    throw [InvalidOperationException]::new($FailureCode)
}

function Get-Sha256FromBytes {
    param([Parameter(Mandatory)][byte[]]$Bytes)
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes)).ToLowerInvariant()
}

function ConvertTo-NormalizedOrganizationUrl {
    param([Parameter(Mandatory)][string]$Value)
    $uri = $null
    if (-not [Uri]::TryCreate($Value, [UriKind]::Absolute, [ref]$uri) -or
        $uri.Scheme -cne 'https' -or
        -not [string]::IsNullOrEmpty($uri.UserInfo) -or
        $uri.AbsolutePath -notin @('', '/') -or
        -not [string]::IsNullOrEmpty($uri.Query) -or
        -not [string]::IsNullOrEmpty($uri.Fragment)) {
        Stop-PackageUpdater 'PACKAGE_TARGET_IDENTITY_MISMATCH'
    }
    $uri.GetLeftPart([UriPartial]::Authority).TrimEnd('/')
}

function ConvertTo-CanonicalGuid {
    param([Parameter(Mandatory)][string]$Value)
    $parsed = [Guid]::Empty
    if (-not [Guid]::TryParse($Value, [ref]$parsed) -or $parsed -eq [Guid]::Empty) {
        Stop-PackageUpdater 'PACKAGE_TARGET_IDENTITY_MISMATCH'
    }
    $parsed.ToString('D').ToLowerInvariant()
}

function Test-PackageModifiedOnMatchesBaseline {
    param(
        [Parameter(Mandatory)][object]$CurrentModifiedOn,
        [Parameter(Mandatory)][object]$BaselineModifiedOn
    )
    ([DateTimeOffset]$CurrentModifiedOn).ToUniversalTime() -eq
        ([DateTimeOffset]$BaselineModifiedOn).ToUniversalTime()
}

function Assert-UpdaterInputs {
    param([Parameter(Mandatory)][string]$RequestedMode)
    $required = @(
        $TargetProfile, $OrganizationUrl, $ExpectedEnvironmentId, $ExpectedOrganizationId,
        $ArtifactPath, $ExpectedPackageSha256, $ExpectedPackageUniqueName,
        $ExpectedHandlerTypeName, $ExpectedSolutionUniqueName, $JournalPath
    )
    if (@($required | Where-Object { [string]::IsNullOrWhiteSpace([string]$_) }).Count -gt 0) {
        Stop-PackageUpdater 'PACKAGE_REQUIRED_INPUT_MISSING'
    }
    if ($RequestedMode -in @('Apply', 'Reconcile') -and
        $TargetProfile -cne 'DEV' -and
        ([string]::IsNullOrWhiteSpace($ApprovalEvidencePath) -or
            [string]::IsNullOrWhiteSpace($ManagedSolutionArtifactPath))) {
        Stop-PackageUpdater 'TEST_TARGET_APPROVAL_REQUIRED'
    }
    if (($TargetProfile -ceq 'DEV') -ne [bool]$DevelopmentSourceAheadOfFrozenRelease -or
        ($RequestedMode -eq 'Preflight' -and $TargetProfile -cne 'DEV') -or
        ($TargetProfile -ceq 'DEV' -and
            ([string]::IsNullOrWhiteSpace($ExpectedEnvironmentDisplayName) -or
                $ExpectedEnvironmentDisplayName -cne 'VN LMV IT' -or
                $ExpectedAssemblySha256 -cnotmatch '^[0-9a-f]{64}$' -or
                $ExpectedPackageSha256 -cnotmatch '^[0-9a-f]{64}$')) -or
        ($TargetProfile -ceq 'DEV' -and $RequestedMode -in @('Preflight', 'Apply', 'Reconcile') -and
            [string]::IsNullOrWhiteSpace($ExpectedDevelopmentBaselinePath)) -or
        ($TargetProfile -ceq 'DEV' -and $RequestedMode -in @('Preflight', 'Apply') -and
            ([string]::IsNullOrWhiteSpace($ExpectedDevelopmentApiPlanPath) -or
                $ExpectedDevelopmentApiPlanSha256 -cnotmatch '^[0-9a-f]{64}$'))) {
        Stop-PackageUpdater 'PACKAGE_DEVELOPMENT_SOURCE_AUTHORIZATION_REQUIRED'
    }
    if ($ExpectedPackageSha256 -cnotmatch '^[0-9a-f]{64}$' -or
        $ExpectedPackageUniqueName -cne [string]$script:Manifest.candidateCore.packageUniqueName -or
        $ExpectedHandlerTypeName -cne [string]$script:Manifest.candidateCore.customApiHandlerTypeName -or
        $ExpectedSolutionUniqueName -cne [string]$script:Manifest.solution.uniqueName) {
        Stop-PackageUpdater 'PACKAGE_ARTIFACT_VALIDATION_FAILED'
    }
    $null = ConvertTo-NormalizedOrganizationUrl -Value $OrganizationUrl
    $null = ConvertTo-CanonicalGuid -Value $ExpectedEnvironmentId
    $null = ConvertTo-CanonicalGuid -Value $ExpectedOrganizationId
}

function Read-ZipEntryBytes {
    param(
        [Parameter(Mandatory)][IO.Compression.ZipArchive]$Archive,
        [Parameter(Mandatory)][string]$EntryName
    )
    $entry = $Archive.GetEntry($EntryName)
    if ($null -eq $entry) { Stop-PackageUpdater 'PACKAGE_ARTIFACT_VALIDATION_FAILED' }
    $input = $entry.Open()
    $memory = [IO.MemoryStream]::new()
    try {
        $input.CopyTo($memory)
        return ,$memory.ToArray()
    } finally {
        $memory.Dispose()
        $input.Dispose()
    }
}

function Get-PackageArtifactEvidence {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$ExpectedSha256,
        [string]$ExpectedAssemblySha256,
        [Parameter(Mandatory)][string]$ExpectedUniqueName,
        [Parameter(Mandatory)][string]$ExpectedHandler,
        [bool]$DevelopmentSourceAheadOfFrozenRelease = $false
    )
    try {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf) -or
            [IO.Path]::GetExtension($Path) -cne '.nupkg') {
            Stop-PackageUpdater 'PACKAGE_ARTIFACT_VALIDATION_FAILED'
        }
        $fullPath = [IO.Path]::GetFullPath($Path)
        $packageBytes = [IO.File]::ReadAllBytes($fullPath)
        $packageHash = Get-Sha256FromBytes -Bytes $packageBytes
        if ($packageHash -cne $ExpectedSha256 -or
            (-not $DevelopmentSourceAheadOfFrozenRelease -and
                $packageHash -cne [string]$script:Manifest.candidateCore.packageSha256)) {
            Stop-PackageUpdater 'PACKAGE_ARTIFACT_VALIDATION_FAILED'
        }

        $archive = [IO.Compression.ZipArchive]::new(
            [IO.MemoryStream]::new($packageBytes),
            [IO.Compression.ZipArchiveMode]::Read,
            $false
        )
        try {
            $expectedEntries = @(
                '[Content_Types].xml',
                '_rels/.rels',
                'lib/net462/os_sr_cact.dll',
                'os_sr_cact_pkg.nuspec',
                'package/services/metadata/core-properties/nuget.psmdcp'
            ) | Sort-Object
            $actualEntries = @($archive.Entries | ForEach-Object FullName | Sort-Object)
            if ([string]::Join('|', $actualEntries) -cne [string]::Join('|', $expectedEntries) -or
                @($archive.Entries | Where-Object { $_.FullName -match '\.(pdb|snk|pfx|key)$' }).Count -gt 0) {
                Stop-PackageUpdater 'PACKAGE_ARTIFACT_VALIDATION_FAILED'
            }

            $nuspecBytes = Read-ZipEntryBytes -Archive $archive -EntryName 'os_sr_cact_pkg.nuspec'
            $nuspec = [xml]::new()
            $nuspec.Load([IO.MemoryStream]::new([byte[]]$nuspecBytes))
            $packageId = $nuspec.SelectSingleNode('/*[local-name()="package"]/*[local-name()="metadata"]/*[local-name()="id"]')
            $packageVersion = $nuspec.SelectSingleNode('/*[local-name()="package"]/*[local-name()="metadata"]/*[local-name()="version"]')
            if ($null -eq $packageId -or $null -eq $packageVersion -or
                $packageId.InnerText -cne $ExpectedUniqueName -or
                $packageVersion.InnerText -cne [string]$script:Manifest.candidateCore.packageVersion) {
                Stop-PackageUpdater 'PACKAGE_ARTIFACT_VALIDATION_FAILED'
            }

            Add-Type -AssemblyName System.Reflection.Metadata -ErrorAction Stop
            $dllBytes = Read-ZipEntryBytes -Archive $archive -EntryName 'lib/net462/os_sr_cact.dll'
            $dllHash = Get-Sha256FromBytes -Bytes $dllBytes
            $expectedDllHash = if ($DevelopmentSourceAheadOfFrozenRelease) {
                $ExpectedAssemblySha256
            } else {
                [string]$script:Manifest.candidateCore.embeddedAssemblySha256
            }
            if ($dllHash -cne $expectedDllHash) {
                Stop-PackageUpdater 'PACKAGE_ARTIFACT_VALIDATION_FAILED'
            }
            $dllStream = [IO.MemoryStream]::new($dllBytes)
            $peReader = [System.Reflection.PortableExecutable.PEReader]::new($dllStream)
            try {
                $metadata = [System.Reflection.Metadata.PEReaderExtensions]::GetMetadataReader($peReader)
                $assembly = $metadata.GetAssemblyDefinition()
                $assemblyName = $metadata.GetString($assembly.Name)
                $assemblyVersion = $assembly.Version.ToString()
                $publicKey = $metadata.GetBlobBytes($assembly.PublicKey)
                $typeNames = @(
                    foreach ($handle in $metadata.TypeDefinitions) {
                        $type = $metadata.GetTypeDefinition($handle)
                        '{0}.{1}' -f $metadata.GetString($type.Namespace), $metadata.GetString($type.Name)
                    }
                )
                if ($assemblyName -cne 'os_sr_cact' -or $assemblyVersion -cne '1.0.0.0' -or
                    $publicKey.Length -ne 0 -or $ExpectedHandler -notin $typeNames -or
                    [string]$script:Manifest.candidateCore.publicKeyToken -ne '') {
                    Stop-PackageUpdater 'PACKAGE_ARTIFACT_VALIDATION_FAILED'
                }
            } finally {
                $peReader.Dispose()
                $dllStream.Dispose()
            }
        } finally {
            $archive.Dispose()
        }
        [pscustomobject]@{
            FullPath = $fullPath
            FileName = [IO.Path]::GetFileName($fullPath)
            Sha256 = $packageHash
            DllSha256 = $dllHash
            UniqueName = $packageId.InnerText
            Version = $packageVersion.InnerText
            HandlerTypeName = $ExpectedHandler
        }
    } catch {
        Stop-PackageUpdater 'PACKAGE_ARTIFACT_VALIDATION_FAILED'
    }
}

function New-PacPluginPushArguments {
    param(
        [Parameter(Mandatory)][string]$NormalizedOrganizationUrl,
        [Parameter(Mandatory)][string]$ExistingPackageId,
        [Parameter(Mandatory)][string]$PackageFile
    )
    [string[]]@(
        'plugin', 'push',
        '--environment', $NormalizedOrganizationUrl,
        '--pluginId', $ExistingPackageId,
        '--pluginFile', [IO.Path]::GetFullPath($PackageFile),
        '--type', 'Nuget',
        '--configuration', 'Release'
    )
}

function Resolve-PackageMatch {
    param(
        [Parameter(Mandatory)][object[]]$Rows,
        [Parameter(Mandatory)][string]$UniqueName
    )
    if ($Rows.Count -eq 0) { Stop-PackageUpdater 'PACKAGE_NOT_FOUND' }
    if ($Rows.Count -ne 1) { Stop-PackageUpdater 'PACKAGE_IDENTITY_AMBIGUOUS' }
    $row = $Rows[0]
    $packageId = [Guid]::Empty
    if ([string]$row.uniquename -cne $UniqueName -or
        [string]$row.name -cne $UniqueName -or
        [string]$row.version -cne [string]$script:Manifest.candidateCore.packageVersion -or
        -not [Guid]::TryParse([string]$row.pluginpackageid, [ref]$packageId) -or
        $packageId -eq [Guid]::Empty) {
        Stop-PackageUpdater 'PACKAGE_IDENTITY_AMBIGUOUS'
    }
    $row
}

function Get-PackageIdFingerprint {
    param([Parameter(Mandatory)][string]$PackageId)
    Get-Sha256FromBytes -Bytes ([Text.Encoding]::UTF8.GetBytes($PackageId.ToLowerInvariant()))
}

function Get-TargetIdentityFingerprint {
    param([Parameter(Mandatory)][string]$Identifier)
    $canonical = ConvertTo-CanonicalGuid -Value $Identifier
    Get-Sha256FromBytes -Bytes ([Text.Encoding]::UTF8.GetBytes($canonical))
}

function Assert-ReconcileJournal {
    param([Parameter(Mandatory)][object]$Journal)
    if ($null -eq $Journal) { Stop-PackageUpdater 'PACKAGE_DISPATCH_JOURNAL_NOT_RECONCILABLE' }
    $requiredProperties = @(
        'schemaVersion', 'dispatchState', 'dispatchCount', 'retryCount', 'targetProfile',
        'targetEnvironmentIdentitySha256', 'targetOrganizationIdentitySha256',
        'packageIdentity', 'packageUniqueName', 'packageRecordIdentitySha256',
        'artifactSha256', 'preflightTopology'
    )
    if (@($requiredProperties | Where-Object { -not $Journal.PSObject.Properties[$_] }).Count -gt 0 -or
        $null -eq $Journal.preflightTopology) {
        Stop-PackageUpdater 'PACKAGE_DISPATCH_JOURNAL_NOT_RECONCILABLE'
    }
    $topologyProperties = @(
        'packageRecordIdentitySha256', 'packageAssemblyIdentitySha256',
        'handlerTypeIdentitySha256', 'apiMetadataSha256',
        'legacyAssemblyIdentitySha256', 'legacyAssemblySha256', 'packageCount'
    )
    if (@($topologyProperties | Where-Object {
        -not $Journal.preflightTopology.PSObject.Properties[$_]
    }).Count -gt 0) {
        Stop-PackageUpdater 'PACKAGE_DISPATCH_JOURNAL_NOT_RECONCILABLE'
    }
    $fingerprints = @(
        $Journal.targetEnvironmentIdentitySha256,
        $Journal.targetOrganizationIdentitySha256,
        $Journal.packageRecordIdentitySha256,
        $Journal.preflightTopology.packageRecordIdentitySha256,
        $Journal.preflightTopology.packageAssemblyIdentitySha256,
        $Journal.preflightTopology.handlerTypeIdentitySha256,
        $Journal.preflightTopology.apiMetadataSha256,
        $Journal.preflightTopology.legacyAssemblyIdentitySha256,
        $Journal.preflightTopology.legacyAssemblySha256
    )
    $packageCount = 0
    if (-not [int]::TryParse([string]$Journal.preflightTopology.packageCount, [ref]$packageCount) -or
        $packageCount -lt 1) {
        Stop-PackageUpdater 'PACKAGE_DISPATCH_JOURNAL_NOT_RECONCILABLE'
    }
    $expectedJournalArtifactSha256 = if ($TargetProfile -ceq 'DEV' -and
        $DevelopmentSourceAheadOfFrozenRelease) {
        $ExpectedPackageSha256
    } else {
        [string]$script:Manifest.candidateCore.packageSha256
    }
    if ($Journal.schemaVersion -ne 1 -or
        $Journal.dispatchState -cnotin @('OUTCOME_AMBIGUOUS', 'DISPATCH_RESERVED') -or
        [int]$Journal.dispatchCount -ne 1 -or
        [int]$Journal.retryCount -ne 0 -or
        $Journal.targetProfile -cne $TargetProfile -or
        [bool]$Journal.developmentSourceAheadOfFrozenRelease -ne
            [bool]$DevelopmentSourceAheadOfFrozenRelease -or
        $Journal.packageUniqueName -cne $ExpectedPackageUniqueName -or
        [string]$Journal.packageIdentity -cne 'EXISTING_PLUGINPACKAGE_UNIQUE_MATCH' -or
        $Journal.targetEnvironmentIdentitySha256 -cne
            (Get-TargetIdentityFingerprint -Identifier $ExpectedEnvironmentId) -or
        $Journal.targetOrganizationIdentitySha256 -cne
            (Get-TargetIdentityFingerprint -Identifier $ExpectedOrganizationId) -or
        $Journal.artifactSha256 -cne $expectedJournalArtifactSha256 -or
        $Journal.artifactSha256 -cne $ExpectedPackageSha256 -or
        $Journal.packageRecordIdentitySha256 -notmatch '^[0-9a-f]{64}$' -or
        $Journal.preflightTopology.packageRecordIdentitySha256 -cne $Journal.packageRecordIdentitySha256 -or
        @($fingerprints | Where-Object { [string]$_ -notmatch '^[0-9a-f]{64}$' }).Count -gt 0) {
        Stop-PackageUpdater 'PACKAGE_DISPATCH_JOURNAL_NOT_RECONCILABLE'
    }
}

function New-PackageUpdaterJournal {
    param(
        [Parameter(Mandatory)][string]$Profile,
        [Parameter(Mandatory)][string]$UniqueName,
        [Parameter(Mandatory)][string]$ArtifactSha256,
        [Parameter(Mandatory)][string]$EnvironmentId,
        [Parameter(Mandatory)][string]$OrganizationId,
        [bool]$DevelopmentSourceAheadOfFrozenRelease = $false
    )
    [ordered]@{
        schemaVersion = 1
        createdAtUtc = [DateTime]::UtcNow.ToString('o')
        runId = [Guid]::NewGuid().ToString('D')
        targetProfile = $Profile
        developmentSourceAheadOfFrozenRelease = $DevelopmentSourceAheadOfFrozenRelease
        targetEnvironmentIdentitySha256 = Get-TargetIdentityFingerprint -Identifier $EnvironmentId
        targetOrganizationIdentitySha256 = Get-TargetIdentityFingerprint -Identifier $OrganizationId
        packageIdentity = 'EXISTING_PLUGINPACKAGE_UNIQUE_MATCH'
        packageUniqueName = $UniqueName
        packageRecordIdentitySha256 = $null
        artifactSha256 = $ArtifactSha256
        dispatchState = 'PREFLIGHT_COMPLETE'
        dispatchCount = 0
        retryCount = 0
        pacExitClassification = 'NOT_RUN'
        preflightTopology = $null
        finalClassification = 'DEPLOYMENT_NOT_DISPATCHED'
        reconciliation = $null
    }
}

function Test-JournalCanReserveDispatch {
    param([Parameter(Mandatory)][object]$Journal)
    $Journal.dispatchCount -eq 0 -and
        $Journal.retryCount -eq 0 -and
        $Journal.dispatchState -ceq 'PREFLIGHT_COMPLETE' -and
        $Journal.finalClassification -ceq 'DEPLOYMENT_NOT_DISPATCHED'
}

function Set-JournalReserved {
    param([Parameter(Mandatory)][object]$Journal)
    if (-not (Test-JournalCanReserveDispatch -Journal $Journal)) {
        Stop-PackageUpdater 'PACKAGE_DISPATCH_JOURNAL_ALREADY_CONSUMED'
    }
    $Journal.dispatchState = 'DISPATCH_RESERVED'
    $Journal.dispatchCount = 1
    $Journal.retryCount = 0
}

function Get-PacPushClassification {
    param(
        [Parameter(Mandatory)][bool]$ProcessStarted,
        [Parameter(Mandatory)][int]$ExitCode,
        [AllowEmptyString()][string]$StandardOutput,
        [AllowEmptyString()][string]$StandardError
    )
    if (-not $ProcessStarted) {
        return 'NOT_DISPATCHED'
    }
    $text = "$StandardOutput`n$StandardError"
    if ($ExitCode -eq 0 -and
        $text -match '(?is)(plugin\s*package|pluginpackage|plug-in\s*package).{0,100}(successfully|succeeded|updated|pushed)|(successfully|succeeded).{0,100}(plugin\s*package|pluginpackage|plug-in\s*package)') {
        return 'PAC_SUCCESS_REPORTED'
    }
    if ($ExitCode -ne 0 -and
        $text -match '(?im)^\s*(?:error|fatal):\s*(?:unknown command|missing required option|invalid value for option|could not find file|file not found)\b') {
        return 'PAC_CLEAR_COMMAND_REJECTION'
    }
    'PAC_RESULT_AMBIGUOUS'
}

function Get-PacExecutablePath {
    param([Parameter(Mandatory)][string]$Executable)
    $resolved = Get-Command -Name $Executable -ErrorAction SilentlyContinue
    if ($null -eq $resolved -or $resolved.CommandType -ne 'Application') {
        Stop-PackageUpdater 'PACKAGE_TARGET_IDENTITY_MISMATCH'
    }
    $path = [IO.Path]::GetFullPath([string]$resolved.Source)
    if ([IO.Path]::GetFileNameWithoutExtension($path) -ine 'pac') {
        Stop-PackageUpdater 'PACKAGE_TARGET_IDENTITY_MISMATCH'
    }
    $path
}

function Assert-PacCliVersion {
    param([Parameter(Mandatory)][string]$ExecutablePath)
    try {
        $script:PacVersionCheckCount++
        $output = @(& $ExecutablePath help 2>&1 | ForEach-Object { [string]$_ })
    } catch {
        Stop-PackageUpdater 'PACKAGE_TARGET_IDENTITY_MISMATCH'
    }
    if ($LASTEXITCODE -ne 0 -or
        ($output -join "`n") -notmatch [regex]::Escape([string]$script:Manifest.releaseTooling.pacCliVersion)) {
        Stop-PackageUpdater 'PACKAGE_TARGET_IDENTITY_MISMATCH'
    }
}

function Write-NewJournal {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][object]$Journal
    )
    $fullPath = [IO.Path]::GetFullPath($Path)
    $parent = Split-Path -Parent $fullPath
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        Stop-PackageUpdater 'PACKAGE_JOURNAL_PATH_INVALID'
    }
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes(
        (ConvertTo-Json -InputObject $Journal -Depth 20)
    )
    try {
        $stream = [IO.File]::Open($fullPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try { $stream.Write($bytes, 0, $bytes.Length); $stream.Flush($true) }
        finally { $stream.Dispose() }
    } catch {
        if (Test-Path -LiteralPath $fullPath) {
            Stop-PackageUpdater 'PACKAGE_DISPATCH_JOURNAL_ALREADY_EXISTS'
        }
        Stop-PackageUpdater 'PACKAGE_DISPATCH_JOURNAL_WRITE_FAILED'
    }
}

function Save-ExistingJournal {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][object]$Journal
    )
    $fullPath = [IO.Path]::GetFullPath($Path)
    $temporaryPath = "$fullPath.$([Guid]::NewGuid().ToString('N')).tmp"
    try {
        $bytes = [Text.UTF8Encoding]::new($false).GetBytes((ConvertTo-Json -InputObject $Journal -Depth 20))
        $stream = [IO.File]::Open($temporaryPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try {
            $stream.Write($bytes, 0, $bytes.Length)
            $stream.Flush($true)
        } finally { $stream.Dispose() }
        [IO.File]::Move($temporaryPath, $fullPath, $true)
    } catch {
        if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
            try { [IO.File]::Delete($temporaryPath) }
            catch { Stop-PackageUpdater 'PACKAGE_DISPATCH_JOURNAL_TEMP_CLEANUP_FAILED' }
        }
        Stop-PackageUpdater 'PACKAGE_DISPATCH_JOURNAL_WRITE_FAILED'
    }
}

function Invoke-OneShotDispatchStateMachine {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][object]$Journal,
        [Parameter(Mandatory)][scriptblock]$Dispatch,
        [Parameter(Mandatory)][scriptblock]$Reconcile
    )
    if (Test-Path -LiteralPath $Path) {
        Stop-PackageUpdater 'PACKAGE_DISPATCH_JOURNAL_ALREADY_EXISTS'
    }
    Set-JournalReserved -Journal $Journal
    Write-NewJournal -Path $Path -Journal $Journal

    $dispatchResult = $null
    try { $dispatchResult = & $Dispatch }
    catch {
        $Journal.dispatchState = 'OUTCOME_AMBIGUOUS'
        $Journal.pacExitClassification = 'PROCESS_OR_OUTPUT_UNCERTAIN'
        $Journal.finalClassification = 'DEPLOYMENT_OUTCOME_AMBIGUOUS_REQUIRES_RECONCILIATION'
        Save-ExistingJournal -Path $Path -Journal $Journal
        return [pscustomobject]@{
            Result = $Journal.finalClassification
            DispatchCount = 1
            RetryCount = 0
            ReadOnlyRequestCount = $script:ReadRequestCount
            PacVersionCheckCount = $script:PacVersionCheckCount
            PacIdentityCheckCount = $script:PacIdentityCheckCount
            NetworkOperations = $script:ReadRequestCount + $script:PacIdentityCheckCount + 1
            JournalCreated = $true
        }
    }

    $Journal.pacExitClassification = [string]$dispatchResult.Classification
    if ($dispatchResult.Classification -ceq 'NOT_DISPATCHED') {
        $Journal.dispatchState = 'PROCESS_NOT_STARTED'
        $Journal.dispatchCount = 0
        $Journal.finalClassification = 'DEPLOYMENT_NOT_DISPATCHED'
        Save-ExistingJournal -Path $Path -Journal $Journal
        return [pscustomobject]@{
            Result = $Journal.finalClassification
            DispatchCount = 0
            RetryCount = 0
            ReadOnlyRequestCount = $script:ReadRequestCount
            PacVersionCheckCount = $script:PacVersionCheckCount
            PacIdentityCheckCount = $script:PacIdentityCheckCount
            NetworkOperations = $script:ReadRequestCount + $script:PacIdentityCheckCount
            JournalCreated = $true
        }
    }
    if ($dispatchResult.Classification -ceq 'PAC_CLEAR_COMMAND_REJECTION') {
        $Journal.dispatchState = 'PAC_REJECTED'
        $Journal.finalClassification = 'PACKAGE_UPDATE_REJECTED'
        Save-ExistingJournal -Path $Path -Journal $Journal
        return [pscustomobject]@{
            Result = $Journal.finalClassification
            DispatchCount = 1
            RetryCount = 0
            ReadOnlyRequestCount = $script:ReadRequestCount
            PacVersionCheckCount = $script:PacVersionCheckCount
            PacIdentityChecks = $script:PacIdentityCheckCount
            NetworkOperations = $script:ReadRequestCount + $script:PacIdentityCheckCount + $script:DispatchCount
            JournalCreated = $true
        }
    }
    if ($dispatchResult.Classification -cne 'PAC_SUCCESS_REPORTED') {
        $Journal.dispatchState = 'OUTCOME_AMBIGUOUS'
        $Journal.finalClassification = 'DEPLOYMENT_OUTCOME_AMBIGUOUS_REQUIRES_RECONCILIATION'
        Save-ExistingJournal -Path $Path -Journal $Journal
        return [pscustomobject]@{
            Result = $Journal.finalClassification
            DispatchCount = 1
            RetryCount = 0
            ReadOnlyRequestCount = $script:ReadRequestCount
            PacVersionCheckCount = $script:PacVersionCheckCount
            NetworkOperations = $script:ReadRequestCount + $script:PacIdentityCheckCount + $script:DispatchCount
            JournalCreated = $true
        }
    }

    try {
        $after = & $Reconcile
        $same = Test-SnapshotEquivalent -Before $Journal.preflightTopology -After $after
        $Journal.reconciliation = Get-SanitizedTopologyPredicates -Snapshot $after
        if (-not $same) {
            throw [InvalidOperationException]::new('TOPOLOGY_RECONCILIATION_FAILED')
        }
        $Journal.dispatchState = 'RECONCILED'
        $Journal.finalClassification = 'DEPLOYMENT_CONFIRMED'
    } catch {
        $Journal.dispatchState = 'OUTCOME_AMBIGUOUS'
        $Journal.finalClassification = 'DEPLOYMENT_OUTCOME_AMBIGUOUS_REQUIRES_RECONCILIATION'
    }
    Save-ExistingJournal -Path $Path -Journal $Journal
    [pscustomobject]@{
        Result = $Journal.finalClassification
        DispatchCount = 1
        RetryCount = 0
        ReadOnlyRequestCount = $script:ReadRequestCount
        PacVersionCheckCount = $script:PacVersionCheckCount
        PacIdentityCheckCount = $script:PacIdentityCheckCount
        NetworkOperations = $script:ReadRequestCount + $script:PacIdentityCheckCount + $script:DispatchCount
        JournalCreated = $true
    }
}

function Get-SanitizedTopologyPredicates {
    param([Parameter(Mandatory)][object]$Snapshot)
    [ordered]@{
        oneExistingPackage = [bool]$Snapshot.OneExistingPackage
        packageAssemblyLinked = [bool]$Snapshot.PackageAssemblyLinked
        expectedHandlerPackageBacked = [bool]$Snapshot.ExpectedHandlerPackageBacked
        customApiMetadataUnchanged = [bool]$Snapshot.CustomApiMetadataUnchanged
        legacyAssemblyUntouched = [bool]$Snapshot.LegacyAssemblyUntouched
        allProtectCandidateCoreStepsInactive = [bool]$Snapshot.AllProtectCandidateCoreStepsInactive
        noActiveLegacyHandlers = [bool]$Snapshot.NoActiveLegacyHandlers
        noActiveCandidateCoreProfilerWrappers = [bool]$Snapshot.NoActiveCandidateCoreProfilerWrappers
        pluginTraceLogOff = [bool]$Snapshot.PluginTraceLogOff
        noNewPluginPackage = [bool]$Snapshot.NoNewPluginPackage
        modifiedOnAdvanced = [bool]$Snapshot.ModifiedOnAdvanced
        serverPackageBytesAvailable = [bool]$Snapshot.ServerPackageBytesAvailable
    }
}

function Test-SnapshotEquivalent {
    param([Parameter(Mandatory)][object]$Before, [Parameter(Mandatory)][object]$After)
    $packageFingerprint = if ($Before.PSObject.Properties['PackageIdFingerprint']) {
        [string]$Before.PackageIdFingerprint
    } else { [string]$Before.packageRecordIdentitySha256 }
    $assemblyFingerprint = if ($Before.PSObject.Properties['AssemblyId']) {
        Get-Sha256FromBytes -Bytes ([Text.Encoding]::UTF8.GetBytes(([string]$Before.AssemblyId).ToLowerInvariant()))
    } else { [string]$Before.packageAssemblyIdentitySha256 }
    $handlerFingerprint = if ($Before.PSObject.Properties['HandlerTypeId']) {
        Get-Sha256FromBytes -Bytes ([Text.Encoding]::UTF8.GetBytes(([string]$Before.HandlerTypeId).ToLowerInvariant()))
    } else { [string]$Before.handlerTypeIdentitySha256 }
    $legacyFingerprint = if ($Before.PSObject.Properties['LegacyAssemblyId']) {
        Get-Sha256FromBytes -Bytes ([Text.Encoding]::UTF8.GetBytes(([string]$Before.LegacyAssemblyId).ToLowerInvariant()))
    } else { [string]$Before.legacyAssemblyIdentitySha256 }
    $packageCount = if ($Before.PSObject.Properties['PackageCount']) {
        [int]$Before.PackageCount
    } else { [int]$Before.packageCount }
    $apiMetadataFingerprint = if ($Before.PSObject.Properties['ApiMetadataSha256']) {
        [string]$Before.ApiMetadataSha256
    } else { [string]$Before.apiMetadataSha256 }
    $legacyAssemblyHash = if ($Before.PSObject.Properties['LegacyAssemblySha256']) {
        [string]$Before.LegacyAssemblySha256
    } else { [string]$Before.legacyAssemblySha256 }
    $identityValid = [string]$After.PackageIdFingerprint -ceq $packageFingerprint -and
        (Get-Sha256FromBytes -Bytes ([Text.Encoding]::UTF8.GetBytes(([string]$After.AssemblyId).ToLowerInvariant()))) -ceq $assemblyFingerprint -and
        (Get-Sha256FromBytes -Bytes ([Text.Encoding]::UTF8.GetBytes(([string]$After.HandlerTypeId).ToLowerInvariant()))) -ceq $handlerFingerprint -and
        (Get-Sha256FromBytes -Bytes ([Text.Encoding]::UTF8.GetBytes(([string]$After.LegacyAssemblyId).ToLowerInvariant()))) -ceq $legacyFingerprint -and
        [int]$After.PackageCount -eq $packageCount -and
        [string]$After.ApiMetadataSha256 -ceq $apiMetadataFingerprint -and
        [string]$After.LegacyAssemblySha256 -ceq $legacyAssemblyHash
    $requiredPredicates = @(
        'OneExistingPackage', 'SamePackageRecord', 'PackageAssemblyLinked',
        'SamePackageAssembly', 'ExpectedHandlerPackageBacked', 'SameHandlerType',
        'CustomApiMetadataUnchanged', 'LegacyAssemblyUntouched',
        'AllProtectCandidateCoreStepsInactive', 'NoActiveLegacyHandlers', 'NoActiveCandidateCoreProfilerWrappers',
        'PluginTraceLogOff', 'NoNewPluginPackage'
    )
    $predicatesValid = @($requiredPredicates | Where-Object { -not [bool]$After.$_ }).Count -eq 0
    $identityValid -and $predicatesValid
}

function Get-PacTargetIdentity {
    param([Parameter(Mandatory)][string]$Executable)
    $executablePath = Get-PacExecutablePath -Executable $Executable
    Assert-PacCliVersion -ExecutablePath $executablePath
    try {
        $script:PacIdentityCheckCount++
        $output = @(& $executablePath env who 2>&1 | ForEach-Object { [string]$_ })
    }
    catch { Stop-PackageUpdater 'PACKAGE_TARGET_IDENTITY_MISMATCH' }
    if ($LASTEXITCODE -ne 0) { Stop-PackageUpdater 'PACKAGE_TARGET_IDENTITY_MISMATCH' }
    $text = $output -join "`n"
    $url = [regex]::Match($text, '(?m)^\s*Org URL:\s*(\S+)')
    $orgId = [regex]::Match($text, '(?m)^\s*Org ID:\s*([0-9a-fA-F-]{36})')
    $environmentId = [regex]::Match($text, '(?m)^\s*Environment ID:\s*([0-9a-fA-F-]{36})')
    $userId = [regex]::Match($text, '(?m)^\s*User ID:\s*([0-9a-fA-F-]{36})')
    $email = [regex]::Match($text, '(?m)^\s*User Email:\s*(\S+)')
    $name = [regex]::Match($text, '(?m)^\s*Friendly Name:\s*(.+?)\s*$')
    if (-not ($url.Success -and $orgId.Success -and $environmentId.Success -and
        $userId.Success -and $email.Success -and $name.Success)) {
        Stop-PackageUpdater 'PACKAGE_TARGET_IDENTITY_MISMATCH'
    }
    [pscustomobject]@{
        OrganizationUrl = ConvertTo-NormalizedOrganizationUrl -Value $url.Groups[1].Value
        OrganizationId = ConvertTo-CanonicalGuid -Value $orgId.Groups[1].Value
        EnvironmentId = ConvertTo-CanonicalGuid -Value $environmentId.Groups[1].Value
        UserId = ConvertTo-CanonicalGuid -Value $userId.Groups[1].Value
        UserEmail = $email.Groups[1].Value
        EnvironmentName = $name.Groups[1].Value
    }
}

function Get-ValidatedDataverseToken {
    param(
        [Parameter(Mandatory)][string]$TargetUrl,
        [Parameter(Mandatory)][string]$PacUserEmail
    )
    try {
        if (-not (Get-Module -ListAvailable -Name Az.Accounts)) {
            Stop-PackageUpdater 'PACKAGE_TARGET_IDENTITY_MISMATCH'
        }
        Import-Module Az.Accounts -ErrorAction Stop
        $context = Get-AzContext -ErrorAction Stop
        if ($null -eq $context -or $context.Account.Type -ne 'User' -or
            $context.Account.Id -ine $PacUserEmail) {
            Stop-PackageUpdater 'PACKAGE_TARGET_IDENTITY_MISMATCH'
        }
        $result = Get-AzAccessToken -ResourceUrl $TargetUrl -AsSecureString -ErrorAction Stop
        if ($result.Token -isnot [Security.SecureString]) {
            Stop-PackageUpdater 'PACKAGE_TARGET_IDENTITY_MISMATCH'
        }
        $token = ConvertFrom-SecureString -SecureString $result.Token -AsPlainText
        $parts = $token.Split('.')
        if ($parts.Count -ne 3) { Stop-PackageUpdater 'PACKAGE_TARGET_IDENTITY_MISMATCH' }
        $payload = $parts[1].Replace('-', '+').Replace('_', '/')
        switch ($payload.Length % 4) { 2 { $payload += '==' } 3 { $payload += '=' } }
        $claims = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload)) | ConvertFrom-Json
        $audience = [Uri]([string]$claims.aud)
        if ($claims.tid -ine $context.Tenant.Id -or $audience.Authority -ine ([Uri]$TargetUrl).Authority -or
            'user_impersonation' -notin @(([string]$claims.scp) -split '\s+') -or
            [DateTimeOffset]::FromUnixTimeSeconds([long]$claims.exp) -le [DateTimeOffset]::UtcNow) {
            Stop-PackageUpdater 'PACKAGE_TARGET_IDENTITY_MISMATCH'
        }
        $token
    } catch {
        Stop-PackageUpdater 'PACKAGE_TARGET_IDENTITY_MISMATCH'
    }
}

function Invoke-DataverseGet {
    param([Parameter(Mandatory)][string]$Path)
    $uri = [Uri]($script:ApiRoot + $Path)
    Invoke-DataverseUriGet -Uri $uri
}

function Invoke-DataverseUriGet {
    param([Parameter(Mandatory)][Uri]$Uri)
    $uri = $Uri
    if ($uri.Scheme -cne 'https' -or $uri.Authority -ine ([Uri]$OrganizationUrl).Authority -or
        $uri.AbsolutePath -notmatch '^/api/data/v9\.2/' -or
        -not [string]::IsNullOrEmpty($uri.UserInfo) -or
        -not [string]::IsNullOrEmpty($uri.Fragment)) {
        Stop-PackageUpdater 'PACKAGE_TARGET_IDENTITY_MISMATCH'
    }
    try {
        $script:ReadRequestCount++
        Invoke-RestMethod -Uri $uri -Method GET -Headers @{
            Authorization = "Bearer $script:AccessToken"
            Accept = 'application/json'
            'OData-Version' = '4.0'
            'OData-MaxVersion' = '4.0'
            Consistency = 'Strong'
        } -MaximumRetryCount 0 -MaximumRedirection 0 -TimeoutSec 120 -ErrorAction Stop
    } catch {
        Stop-PackageUpdater 'PACKAGE_READ_ONLY_PREFLIGHT_FAILED'
    }
}

function Get-DataverseRows {
    param([Parameter(Mandatory)][string]$Path)
    $next = [Uri]($script:ApiRoot + $Path)
    $rows = [Collections.Generic.List[object]]::new()
    while ($next) {
        $page = Invoke-DataverseUriGet -Uri $next
        if ($null -eq $page -or $null -eq $page.PSObject.Properties['value']) {
            Stop-PackageUpdater 'PACKAGE_READ_ONLY_PREFLIGHT_FAILED'
        }
        foreach ($row in @($page.value)) { $rows.Add($row) }
        $nextLinkProperty = $page.PSObject.Properties['@odata.nextLink']
        $nextLink = if ($null -eq $nextLinkProperty) { '' } else { [string]$nextLinkProperty.Value }
        if ($nextLink) { $next = [Uri]$nextLink } else { $next = $null }
    }
    $rows.ToArray()
}

function Assert-ApprovedTargetEvidence {
    param([Parameter(Mandatory)][string]$Profile)
    if (-not (Test-Path -LiteralPath $ApprovalEvidencePath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $ManagedSolutionArtifactPath -PathType Leaf)) {
        Stop-PackageUpdater 'TEST_TARGET_APPROVAL_REQUIRED'
    }
    try {
        $approval = Get-Content -LiteralPath $ApprovalEvidencePath -Raw | ConvertFrom-Json
    } catch {
        Stop-PackageUpdater 'TEST_TARGET_APPROVAL_REQUIRED'
    }
    if ($approval.mode -cne $Profile -or
        (ConvertTo-NormalizedOrganizationUrl -Value ([string]$approval.organizationUrl)) -cne
            (ConvertTo-NormalizedOrganizationUrl -Value $OrganizationUrl) -or
        (ConvertTo-CanonicalGuid -Value ([string]$approval.environmentId)) -cne
            (ConvertTo-CanonicalGuid -Value $ExpectedEnvironmentId) -or
        (ConvertTo-CanonicalGuid -Value ([string]$approval.organizationId)) -cne
            (ConvertTo-CanonicalGuid -Value $ExpectedOrganizationId)) {
        Stop-PackageUpdater 'PACKAGE_TARGET_IDENTITY_MISMATCH'
    }
    if ($Profile -ceq 'TEST') {
        $gate = & (Join-Path $script:Root 'scripts\Test-BsoRsTestRehearsalGate.ps1') `
            -TestApprovalEvidencePath $ApprovalEvidencePath `
            -ManagedArtifactPath $ManagedSolutionArtifactPath
        if ($gate.Result -cne 'TEST_REHEARSAL_PREFLIGHT_READY_NOT_EXECUTED') {
            Stop-PackageUpdater 'TEST_TARGET_APPROVAL_REQUIRED'
        }
    } else {
        $gate = & (Join-Path $script:Root 'scripts\Test-BsoRsSolutionImportGate.ps1') `
            -Mode PROD -ApprovalEvidencePath $ApprovalEvidencePath `
            -ManagedArtifactPath $ManagedSolutionArtifactPath
        if ($gate.Result -cne 'PRODUCTION_IMPORT_PREFLIGHT_READY_NOT_EXECUTED') {
            Stop-PackageUpdater 'PRODUCTION_APPROVAL_REQUIRED'
        }
    }
    if ([string]$approval.solutionUniqueName -cne $ExpectedSolutionUniqueName -or
        [string]$approval.solutionVersion -cne [string]$script:Manifest.solution.version) {
        Stop-PackageUpdater 'PACKAGE_TARGET_IDENTITY_MISMATCH'
    }
    $approval
}

function Get-PagedRows {
    param([Parameter(Mandatory)][string]$Path)
    Get-DataverseRows -Path $Path
}

function Get-ApiMetadataSnapshot {
    param([Parameter(Mandatory)][string]$UniqueName)
    $apis = @(Get-PagedRows -Path "customapis?`$select=customapiid,uniquename,name,displayname,description,executeprivilegename,bindingtype,isfunction,isprivate,allowedcustomprocessingsteptype,_plugintypeid_value&`$filter=uniquename eq '$UniqueName'")
    if ($apis.Count -ne 1 -or $apis[0].uniquename -cne $UniqueName) {
        Stop-PackageUpdater 'PACKAGE_TOPOLOGY_PREFLIGHT_FAILED'
    }
    $api = $apis[0]
    $inputs = @(Get-PagedRows -Path "customapirequestparameters?`$filter=_customapiid_value eq $($api.customapiid)")
    $outputs = @(Get-PagedRows -Path "customapiresponseproperties?`$filter=_customapiid_value eq $($api.customapiid)")
    $canonical = [ordered]@{
        customapiid = [string]$api.customapiid
        uniquename = [string]$api.uniquename
        name = [string]$api.name
        displayname = [string]$api.displayname
        description = [string]$api.description
        executeprivilegename = [string]$api.executeprivilegename
        bindingtype = [int]$api.bindingtype
        isfunction = [bool]$api.isfunction
        isprivate = [bool]$api.isprivate
        allowedcustomprocessingsteptype = [int]$api.allowedcustomprocessingsteptype
        handlerTypeId = [string]$api._plugintypeid_value
        inputs = @($inputs | Sort-Object uniquename | ForEach-Object {
            [ordered]@{ uniquename = [string]$_.uniquename; type = [int]$_.type; isoptional = [bool]$_.isoptional; logicalentityname = [string]$_.logicalentityname }
        })
        outputs = @($outputs | Sort-Object uniquename | ForEach-Object {
            [ordered]@{ uniquename = [string]$_.uniquename; type = [int]$_.type }
        })
    }
    [pscustomobject]@{
        Api = $api
        InputNames = @($inputs | ForEach-Object { [string]$_.uniquename } | Sort-Object -CaseSensitive)
        InputDetails = @($inputs | ForEach-Object {
            [pscustomobject]@{
                Id = [string]$_.customapirequestparameterid
                Name = [string]$_.uniquename
                Type = [int]$_.type
                IsOptional = [bool]$_.isoptional
                ApiId = [string]$_._customapiid_value
            }
        })
        OutputNames = @($outputs | ForEach-Object { [string]$_.uniquename } | Sort-Object -CaseSensitive)
        Hash = Get-Sha256FromBytes -Bytes ([Text.Encoding]::UTF8.GetBytes(
            (ConvertTo-Json -InputObject $canonical -Depth 15 -Compress)
        ))
    }
}

function Test-HasFileStoreSourceLabel {
    param([Parameter(Mandatory)][string[]]$Labels)
    @($Labels | Where-Object { $_ -match '(?i)^file\s*store$' } | Sort-Object -Unique).Count -eq 1
}

function Test-IsCandidateCoreProfilerStep {
    param(
        [Parameter(Mandatory)][object]$Step,
        [Parameter(Mandatory)][string[]]$ProfilerTypeIds
    )
    $candidateCoreName = [string]$Step.name -match '(?i)(os_sr_cact|ApplyCandidateAction|ProtectCandidateCore)'
    $profilerStep = [string]$Step.name -match '(?i)profiler'
    $profilerHandler = [string]$Step._eventhandler_value -in $ProfilerTypeIds
    $candidateCoreName -and ($profilerStep -or $profilerHandler)
}

function Get-TopologySnapshot {
    param(
        [Parameter(Mandatory)][object]$PackageRow,
        [Parameter(Mandatory)][int]$PackageCountBefore,
        [AllowNull()][object]$Before
    )
    $relationshipRows = @(Get-PagedRows -Path "EntityDefinitions(LogicalName='pluginassembly')/ManyToOneRelationships?`$select=ReferencingAttribute,ReferencedEntity,ReferencingEntityNavigationPropertyName")
    $packageRelationships = @($relationshipRows | Where-Object { $_.ReferencedEntity -ceq 'pluginpackage' })
    if ($packageRelationships.Count -ne 1 -or
        [string]::IsNullOrWhiteSpace([string]$packageRelationships[0].ReferencingAttribute)) {
        Stop-PackageUpdater 'PACKAGE_TOPOLOGY_PREFLIGHT_FAILED'
    }
    $packageLookup = "_$([string]$packageRelationships[0].ReferencingAttribute)_value"
    $assemblies = @(Get-PagedRows -Path "pluginassemblies?`$select=pluginassemblyid,name,version,publickeytoken,sourcetype,$packageLookup&`$filter=$packageLookup eq $($PackageRow.pluginpackageid)")
    if ($assemblies.Count -ne 1) { Stop-PackageUpdater 'PACKAGE_TOPOLOGY_PREFLIGHT_FAILED' }
    $assembly = $assemblies[0]
    $sourceMetadata = Invoke-DataverseGet -Path "EntityDefinitions(LogicalName='pluginassembly')/Attributes(LogicalName='sourcetype')/Microsoft.Dynamics.CRM.PicklistAttributeMetadata?`$select=LogicalName&`$expand=OptionSet"
    $sourceOptions = @($sourceMetadata.OptionSet.Options | Where-Object { [int]$_.Value -eq [int]$assembly.sourcetype })
    $sourceLabels = @($sourceOptions | ForEach-Object {
        @($_.Label.LocalizedLabels | ForEach-Object Label) + [string]$_.Label.UserLocalizedLabel.Label
    } | Where-Object { $_ })
    $types = @(Get-PagedRows -Path "plugintypes?`$select=plugintypeid,typename,_pluginassemblyid_value&`$filter=_pluginassemblyid_value eq $($assembly.pluginassemblyid)")
    $handlerTypes = @($types | Where-Object typename -CEQ $ExpectedHandlerTypeName)
    $guardName = [string]$script:Manifest.candidateCore.embeddedAssemblyTypeName -replace '\.ApplyCandidateAction$', '.ProtectCandidateCore'
    $guardTypes = @(Get-PagedRows -Path "plugintypes?`$select=plugintypeid,typename,_pluginassemblyid_value&`$filter=typename eq '$guardName'")
    $legacyAssemblies = @(Get-PagedRows -Path "pluginassemblies?`$select=pluginassemblyid,name,version,publickeytoken,sourcetype,content&`$filter=name eq 'os_sr_cact'")
    $legacyRows = @($legacyAssemblies | Where-Object { [string]$_.pluginassemblyid -ine [string]$assembly.pluginassemblyid })
    if ($legacyRows.Count -ne 1 -or [string]$legacyRows[0].publickeytoken -cne
        [string]((Get-Content -LiteralPath (Join-Path $script:Root 'docs\ROLLBACK_MANIFEST.json') -Raw | ConvertFrom-Json).publicKeyToken)) {
        Stop-PackageUpdater 'PACKAGE_TOPOLOGY_PREFLIGHT_FAILED'
    }
    $legacyAssembly = $legacyRows[0]
    $legacyContentHash = Get-Sha256FromBytes -Bytes ([Convert]::FromBase64String([string]$legacyAssembly.content))
    $rollback = Get-Content -LiteralPath (Join-Path $script:Root 'docs\ROLLBACK_MANIFEST.json') -Raw | ConvertFrom-Json
    $legacyHashMatches = $legacyContentHash -ceq [string]$rollback.sha256

    $allGuardTypeIds = @($guardTypes | ForEach-Object { [string]$_.plugintypeid } | Sort-Object -Unique)
    $guardSteps = @()
    if ($allGuardTypeIds.Count -gt 0) {
        $guardFilter = [string]::Join(' or ', @($allGuardTypeIds | ForEach-Object { "_eventhandler_value eq $_" }))
        $guardSteps = @(Get-PagedRows -Path "sdkmessageprocessingsteps?`$select=sdkmessageprocessingstepid,name,statecode,_eventhandler_value&`$filter=($guardFilter)")
    }
    $allGuardInactive = @($guardSteps | Where-Object { [int]$_.statecode -ne 1 }).Count -eq 0

    $allTypes = @(Get-PagedRows -Path 'plugintypes?$select=plugintypeid,typename')
    $profilerTypeIds = @($allTypes | Where-Object { [string]$_.typename -match '(?i)profiler' } |
        ForEach-Object { [string]$_.plugintypeid })
    $activeSteps = @(Get-PagedRows -Path 'sdkmessageprocessingsteps?$select=sdkmessageprocessingstepid,name,statecode,_eventhandler_value&$filter=statecode eq 0')
    $activeProfiler = @($activeSteps | Where-Object {
        Test-IsCandidateCoreProfilerStep -Step $_ -ProfilerTypeIds $profilerTypeIds
    })
    $legacyTypeRows = @(Get-PagedRows -Path "plugintypes?`$select=plugintypeid,typename,_pluginassemblyid_value&`$filter=_pluginassemblyid_value eq $($legacyAssembly.pluginassemblyid)")
    $legacyTypeIds = @($legacyTypeRows | ForEach-Object { [string]$_.plugintypeid })
    $activeLegacyHandlers = @($activeSteps | Where-Object {
        [string]$_._eventhandler_value -in $legacyTypeIds
    })

    $organizationAttributes = @(Get-PagedRows -Path "EntityDefinitions(LogicalName='organization')/Attributes?`$select=LogicalName&`$filter=LogicalName eq 'plugintracelogsetting'")
    if (@($organizationAttributes | Where-Object LogicalName -CEQ 'plugintracelogsetting').Count -ne 1) {
        Stop-PackageUpdater 'PACKAGE_TOPOLOGY_PREFLIGHT_FAILED'
    }
    $organization = Invoke-DataverseGet -Path "organizations($ExpectedOrganizationId)?`$select=organizationid,plugintracelogsetting"
    $traceOff = [string]$organization.organizationid -ieq $ExpectedOrganizationId -and
        [int]$organization.plugintracelogsetting -eq 0

    $apiSnapshot = Get-ApiMetadataSnapshot -UniqueName 'os_sr_cact'
    $packageTypesExact = $types.Count -eq 2 -and $handlerTypes.Count -eq 1 -and
        @($types | Where-Object typename -CEQ $guardName).Count -eq 1 -and
        @($types | Where-Object { [string]$_._pluginassemblyid_value -ine [string]$assembly.pluginassemblyid }).Count -eq 0
    $packageLinked = [string]$assembly.$packageLookup -ieq [string]$PackageRow.pluginpackageid
    $handlerBacked = $packageTypesExact -and
        [string]$apiSnapshot.Api._plugintypeid_value -ieq [string]$handlerTypes[0].plugintypeid
    $allPackageRows = @(Get-PagedRows -Path 'pluginpackages?$select=pluginpackageid')
    $packageCountMatches = $allPackageRows.Count -eq $PackageCountBefore
    $modifiedAdvanced = $false
    $beforeModifiedOn = if ($null -ne $Before -and $Before.PSObject.Properties['ModifiedOn']) {
        $Before.ModifiedOn
    } else { $null }
    if ($null -ne $PackageRow.modifiedon -and $null -ne $beforeModifiedOn) {
        $modifiedAdvanced = [DateTimeOffset]$PackageRow.modifiedon -gt [DateTimeOffset]$beforeModifiedOn
    }
    $beforePackageFingerprint = if ($null -eq $Before) { $null }
        elseif ($Before.PSObject.Properties['PackageIdFingerprint']) { [string]$Before.PackageIdFingerprint }
        else { [string]$Before.packageRecordIdentitySha256 }
    $beforeAssemblyFingerprint = if ($null -eq $Before) { $null }
        elseif ($Before.PSObject.Properties['AssemblyId']) {
            Get-Sha256FromBytes -Bytes ([Text.Encoding]::UTF8.GetBytes(([string]$Before.AssemblyId).ToLowerInvariant()))
        } else { [string]$Before.packageAssemblyIdentitySha256 }
    $beforeHandlerFingerprint = if ($null -eq $Before) { $null }
        elseif ($Before.PSObject.Properties['HandlerTypeId']) {
            Get-Sha256FromBytes -Bytes ([Text.Encoding]::UTF8.GetBytes(([string]$Before.HandlerTypeId).ToLowerInvariant()))
        } else { [string]$Before.handlerTypeIdentitySha256 }
    $samePackage = $null -eq $Before -or
        $beforePackageFingerprint -ceq (Get-PackageIdFingerprint -PackageId ([string]$PackageRow.pluginpackageid))
    $sameAssembly = $null -eq $Before -or
        $beforeAssemblyFingerprint -ceq (Get-Sha256FromBytes -Bytes ([Text.Encoding]::UTF8.GetBytes(([string]$assembly.pluginassemblyid).ToLowerInvariant())))
    $sameHandler = $null -eq $Before -or
        $beforeHandlerFingerprint -ceq (Get-Sha256FromBytes -Bytes ([Text.Encoding]::UTF8.GetBytes(([string]$handlerTypes[0].plugintypeid).ToLowerInvariant())))
    $apiUnchanged = $null -eq $Before -or
        [string]$Before.ApiMetadataSha256 -ceq [string]$apiSnapshot.Hash
    $beforeLegacyFingerprint = if ($null -eq $Before) { $null }
        elseif ($Before.PSObject.Properties['LegacyAssemblyId']) {
            Get-Sha256FromBytes -Bytes ([Text.Encoding]::UTF8.GetBytes(([string]$Before.LegacyAssemblyId).ToLowerInvariant()))
        } else { [string]$Before.legacyAssemblyIdentitySha256 }
    $legacyUnchanged = $null -eq $Before -or
        ($beforeLegacyFingerprint -ceq
            (Get-Sha256FromBytes -Bytes ([Text.Encoding]::UTF8.GetBytes(([string]$legacyAssembly.pluginassemblyid).ToLowerInvariant()))) -and
            [string]$Before.LegacyAssemblySha256 -ceq $legacyContentHash)

    [pscustomobject]@{
        PackageId = [string]$PackageRow.pluginpackageid
        PackageIdFingerprint = Get-PackageIdFingerprint -PackageId ([string]$PackageRow.pluginpackageid)
        PackageName = [string]$PackageRow.uniquename
        PackageVersion = [string]$PackageRow.version
        ModifiedOn = $PackageRow.modifiedon
        AssemblyId = [string]$assembly.pluginassemblyid
        HandlerTypeId = [string]$handlerTypes[0].plugintypeid
        ApiMetadataSha256 = [string]$apiSnapshot.Hash
        ApiId = [string]$apiSnapshot.Api.customapiid
        ApiUniqueName = [string]$apiSnapshot.Api.uniquename
        ApiIsPrivate = [bool]$apiSnapshot.Api.isprivate
        ApiIsFunction = [bool]$apiSnapshot.Api.isfunction
        ApiInputCount = $apiSnapshot.InputNames.Count
        ApiOutputCount = $apiSnapshot.OutputNames.Count
        ApiInputNames = @($apiSnapshot.InputNames)
        ApiInputDetails = @($apiSnapshot.InputDetails)
        ApiOutputNames = @($apiSnapshot.OutputNames)
        LegacyAssemblyId = [string]$legacyAssembly.pluginassemblyid
        LegacyAssemblySha256 = $legacyContentHash
        PackageCount = $allPackageRows.Count
        OneExistingPackage = $true
        SamePackageRecord = $samePackage
        PackageAssemblyLinked = $packageLinked -and
            (Test-HasFileStoreSourceLabel -Labels $sourceLabels)
        SamePackageAssembly = $sameAssembly
        ExpectedHandlerPackageBacked = $handlerBacked
        SameHandlerType = $sameHandler
        CustomApiMetadataUnchanged = $apiUnchanged
        LegacyAssemblyUntouched = $legacyHashMatches -and $legacyUnchanged
        AllProtectCandidateCoreStepsInactive = $allGuardInactive
        ProtectCandidateCoreStepCount = $guardSteps.Count
        NoActiveLegacyHandlers = $activeLegacyHandlers.Count -eq 0
        NoActiveCandidateCoreProfilerWrappers = $activeProfiler.Count -eq 0
        PluginTraceLogOff = $traceOff
        NoNewPluginPackage = $packageCountMatches
        ModifiedOnAdvanced = $modifiedAdvanced
        ServerPackageBytesAvailable = $false
    }
}

function Assert-PreflightTopology {
    param([Parameter(Mandatory)][object]$Snapshot)
    $predicates = @(
        'OneExistingPackage', 'PackageAssemblyLinked', 'ExpectedHandlerPackageBacked',
        'CustomApiMetadataUnchanged', 'LegacyAssemblyUntouched',
        'AllProtectCandidateCoreStepsInactive', 'NoActiveLegacyHandlers', 'NoActiveCandidateCoreProfilerWrappers',
        'PluginTraceLogOff', 'NoNewPluginPackage'
    )
    if (@($predicates | Where-Object { -not [bool]$Snapshot.$_ }).Count -gt 0) {
        Stop-PackageUpdater 'PACKAGE_TOPOLOGY_PREFLIGHT_FAILED'
    }
}

function Get-RolePrivilegeMapFromXml {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$ExpectedRoleName
    )
    $settings = [Xml.XmlReaderSettings]::new()
    $settings.DtdProcessing = [Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver = $null
    $reader = [Xml.XmlReader]::Create($Path, $settings)
    $document = [Xml.XmlDocument]::new()
    $document.XmlResolver = $null
    try { $document.Load($reader) }
    finally { $reader.Dispose() }
    if ($document.DocumentElement.GetAttribute('name') -cne $ExpectedRoleName) {
        Stop-PackageUpdater 'PACKAGE_SECURITY_PREFLIGHT_FAILED'
    }
    $privileges = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal)
    foreach ($node in $document.SelectNodes('/*/RolePrivileges/RolePrivilege')) {
        $name = [string]$node.GetAttribute('name')
        $depth = [string]$node.GetAttribute('level')
        if ([string]::IsNullOrWhiteSpace($name) -or
            $depth -cnotin @('Basic', 'Local', 'Deep', 'Global') -or
            $privileges.ContainsKey($name)) {
            Stop-PackageUpdater 'PACKAGE_SECURITY_PREFLIGHT_FAILED'
        }
        $privileges.Add($name, $depth)
    }
    $privileges
}

function Get-LiveRolePrivilegeMap {
    param([Parameter(Mandatory)][string]$RoleId)
    $response = Invoke-DataverseGet -Path "RetrieveRolePrivilegesRole(RoleId=$RoleId)"
    $rolePrivileges = @($response.RolePrivileges)
    if ($rolePrivileges.Count -eq 0) {
        Stop-PackageUpdater 'PACKAGE_SECURITY_PREFLIGHT_FAILED'
    }
    $depthNames = @('Basic', 'Local', 'Deep', 'Global')
    $privileges = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal)
    foreach ($privilege in $rolePrivileges) {
        $name = [string]$privilege.PrivilegeName
        $depthValue = [string]$privilege.Depth
        $depthName = if ($depthValue -cin @('Basic', 'Local', 'Deep', 'Global')) {
            $depthValue
        } else {
            $depthCode = -1
            if (-not [int]::TryParse($depthValue, [ref]$depthCode) -or
                $depthCode -lt 0 -or $depthCode -ge $depthNames.Count) {
                Stop-PackageUpdater 'PACKAGE_SECURITY_PREFLIGHT_FAILED'
            }
            $depthNames[$depthCode]
        }
        if ([string]::IsNullOrWhiteSpace($name) -or $privileges.ContainsKey($name)) {
            Stop-PackageUpdater 'PACKAGE_SECURITY_PREFLIGHT_FAILED'
        }
        $privileges.Add($name, $depthName)
    }
    $privileges
}

function Test-RolePrivilegeMapEqual {
    param(
        [Parameter(Mandatory)][Collections.Generic.Dictionary[string, string]]$Expected,
        [Parameter(Mandatory)][Collections.Generic.Dictionary[string, string]]$Actual
    )
    if ($Expected.Count -ne $Actual.Count) { return $false }
    foreach ($name in $Expected.Keys) {
        if (-not $Actual.ContainsKey($name) -or $Actual[$name] -cne $Expected[$name]) {
            return $false
        }
    }
    $true
}

function Get-DevRoleState {
    param([Parameter(Mandatory)][string]$RoleName)
    $escapedName = [Uri]::EscapeDataString($RoleName)
    $path = "roles?%24select=roleid,name&%24filter=name%20eq%20%27$escapedName%27&%24expand=systemuserroles_association(%24select=systemuserid),teamroles_association(%24select=teamid)"
    $roles = @(Get-PagedRows -Path $path)
    if ($roles.Count -ne 1 -or [string]$roles[0].name -cne $RoleName) {
        Stop-PackageUpdater 'PACKAGE_SECURITY_PREFLIGHT_FAILED'
    }
    [pscustomobject]@{
        Privileges = Get-LiveRolePrivilegeMap -RoleId ([string]$roles[0].roleid)
        UserAssignmentCount = @($roles[0].systemuserroles_association).Count
        TeamAssignmentCount = @($roles[0].teamroles_association).Count
    }
}

function Get-DevelopmentMembershipFingerprint {
    param([Parameter(Mandatory)][string]$SolutionId)
    $rows = @(Get-PagedRows -Path "solutioncomponents?%24select=componenttype,objectid,rootcomponentbehavior&%24filter=_solutionid_value%20eq%20$SolutionId")
    $lines = @($rows | ForEach-Object {
        '{0}|{1}|{2}' -f [int]$_.componenttype,
            ([string]$_.objectid).ToLowerInvariant(),
            [int]$_.rootcomponentbehavior
    } | Sort-Object -CaseSensitive)
    [pscustomobject]@{
        Count = $rows.Count
        Fingerprint = Get-Sha256FromBytes -Bytes ([Text.Encoding]::UTF8.GetBytes([string]::Join("`n", $lines)))
        Lines = @($lines)
    }
}

function Get-ApprovedDevelopmentApiParameterPlan {
    param([Parameter(Mandatory)][object]$Baseline)
    if (-not (Test-Path -LiteralPath $ExpectedDevelopmentApiPlanPath -PathType Leaf) -or
        (Get-FileHash -LiteralPath $ExpectedDevelopmentApiPlanPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne
            $ExpectedDevelopmentApiPlanSha256) {
        Stop-PackageUpdater 'PACKAGE_TOPOLOGY_PREFLIGHT_FAILED'
    }
    try {
        $plan = Get-Content -LiteralPath $ExpectedDevelopmentApiPlanPath -Raw | ConvertFrom-Json
    } catch {
        Stop-PackageUpdater 'PACKAGE_TOPOLOGY_PREFLIGHT_FAILED'
    }
    if ($null -eq $plan) { Stop-PackageUpdater 'PACKAGE_TOPOLOGY_PREFLIGHT_FAILED' }
    $contract = Get-Content -LiteralPath (Join-Path $script:Root 'docs\PHASE_3C_API_CONTRACT.json') -Raw |
        ConvertFrom-Json
    $maskInputs = @($contract.inputs | Where-Object { [string]$_.name -ceq 'ProfileFieldMask' })
    $writes = @($plan.Writes)
    if ($maskInputs.Count -ne 1 -or $writes.Count -ne 1) {
        Stop-PackageUpdater 'PACKAGE_TOPOLOGY_PREFLIGHT_FAILED'
    }
    $writeId = $null
    try { $writeId = ConvertTo-CanonicalGuid -Value ([string]$writes[0].Id) } catch {
        Stop-PackageUpdater 'PACKAGE_TOPOLOGY_PREFLIGHT_FAILED'
    }
    if (
        [string]$plan.EnvironmentName -cne 'VN LMV IT' -or
        (ConvertTo-NormalizedOrganizationUrl -Value ([string]$plan.OrganizationUrl)) -cne
            (ConvertTo-NormalizedOrganizationUrl -Value $OrganizationUrl) -or
        (ConvertTo-CanonicalGuid -Value ([string]$plan.ExpectedEnvironmentId)) -cne
            (ConvertTo-CanonicalGuid -Value $ExpectedEnvironmentId) -or
        (ConvertTo-CanonicalGuid -Value ([string]$plan.ExpectedOrganizationId)) -cne
            (ConvertTo-CanonicalGuid -Value $ExpectedOrganizationId) -or
        [string]$plan.SolutionUniqueName -cne [string]$script:Manifest.solution.uniqueName -or
        [string]$plan.ApiUniqueName -cne 'os_sr_cact' -or
        [string]$plan.ApiId -ine [string]$Baseline.Api.customapiid -or
        [string]::Join('|', @($plan.ExpectedMissingNames)) -cne 'ProfileFieldMask' -or
        [int]$plan.AutomaticRetries -ne 0 -or [int]$plan.MaximumPostDispatches -ne 1 -or
        [string]$writes[0].Name -cne 'ProfileFieldMask' -or
        [int]$writes[0].Type -ne [int]$maskInputs[0].type -or
        [bool]$writes[0].IsOptional -ne [bool]$maskInputs[0].optional -or
        [string]$writes[0].Body.customapirequestparameterid -ine $writeId -or
        [string]$writes[0].Body.uniquename -cne 'ProfileFieldMask' -or
        [int]$writes[0].Body.type -ne [int]$maskInputs[0].type -or
        [bool]$writes[0].Body.isoptional -ne [bool]$maskInputs[0].optional) {
        Stop-PackageUpdater 'PACKAGE_TOPOLOGY_PREFLIGHT_FAILED'
    }
    $plan
}

function Test-ApprovedDevelopmentMembershipDelta {
    param(
        [Parameter(Mandatory)][string[]]$BaselineLines,
        [Parameter(Mandatory)][string[]]$CurrentLines,
        [Parameter(Mandatory)][string]$ApiParameterId,
        [Parameter(Mandatory)][bool]$ApiParameterPresent
    )
    $baselineSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $currentSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($line in $BaselineLines) {
        if (-not $baselineSet.Add($line)) { return $false }
    }
    foreach ($line in $CurrentLines) {
        if (-not $currentSet.Add($line)) { return $false }
    }
    $missing = @($BaselineLines | Where-Object { -not $currentSet.Contains($_) })
    $extra = @($CurrentLines | Where-Object { -not $baselineSet.Contains($_) })
    if ($missing.Count -ne 0) { return $false }
    if (-not $ApiParameterPresent) { return $extra.Count -eq 0 }
    if ($extra.Count -ne 1) { return $false }
    $parts = $extra[0].Split('|')
    return $parts.Count -eq 3 -and
        $parts[1] -ceq (ConvertTo-CanonicalGuid -Value $ApiParameterId).ToLowerInvariant()
}

function Assert-DevelopmentDeploymentBaseline {
    param([Parameter(Mandatory)][object]$PackageSnapshot)
    if (-not (Test-Path -LiteralPath $ExpectedDevelopmentBaselinePath -PathType Leaf)) {
        Stop-PackageUpdater 'PACKAGE_TARGET_IDENTITY_MISMATCH'
    }
    try {
        $baseline = Get-Content -LiteralPath $ExpectedDevelopmentBaselinePath -Raw | ConvertFrom-Json
    } catch {
        Stop-PackageUpdater 'PACKAGE_TARGET_IDENTITY_MISMATCH'
    }
    if ($null -eq $baseline -or
        $baseline.Classification -cne 'OWNER_DEV_FUNCTIONAL_IDENTITY' -or
        (ConvertTo-NormalizedOrganizationUrl -Value ([string]$baseline.OrganizationUrl)) -cne
            (ConvertTo-NormalizedOrganizationUrl -Value $OrganizationUrl) -or
        (ConvertTo-CanonicalGuid -Value ([string]$baseline.EnvironmentId)) -cne
            (ConvertTo-CanonicalGuid -Value $ExpectedEnvironmentId) -or
        (ConvertTo-CanonicalGuid -Value ([string]$baseline.OrganizationId)) -cne
            (ConvertTo-CanonicalGuid -Value $ExpectedOrganizationId)) {
        Stop-PackageUpdater 'PACKAGE_TARGET_IDENTITY_MISMATCH'
    }

    $solutionName = [string]$script:Manifest.solution.uniqueName
    $solutions = @(Get-PagedRows -Path "solutions?%24select=solutionid,uniquename,version&%24filter=uniquename%20eq%20%27$solutionName%27")
    $apps = @(Get-PagedRows -Path "appmodules?%24select=appmoduleid,uniquename,statecode&%24filter=uniquename%20eq%20%27srapp%27")
    if ($solutions.Count -ne 1 -or $solutions[0].uniquename -cne $solutionName -or
        [string]$solutions[0].version -cne '1.0.0.1' -or
        [string]$solutions[0].solutionid -ine [string]$baseline.Solution.solutionid -or
        $apps.Count -ne 1 -or $apps[0].uniquename -cne 'srapp' -or
        [string]$apps[0].appmoduleid -ine [string]$baseline.App.appmoduleid -or
        [int]$apps[0].statecode -ne 0 -or
        $PackageSnapshot.ApiUniqueName -cne 'os_sr_cact' -or
        -not $PackageSnapshot.ApiIsPrivate -or
        $PackageSnapshot.ApiIsFunction -or
        [string]$PackageSnapshot.ApiId -ine [string]$baseline.Api.customapiid -or
        [string]$PackageSnapshot.PackageId -ine [string]$baseline.Package.pluginpackageid -or
        [string]$PackageSnapshot.AssemblyId -ine [string]$baseline.Assembly.pluginassemblyid -or
        [string]$PackageSnapshot.HandlerTypeId -ine [string]$baseline.Handler.plugintypeid -or
        [int]$PackageSnapshot.ProtectCandidateCoreStepCount -ne [int]$baseline.Guards.LegacySteps -or
        [int]$baseline.Guards.ActiveLegacySteps -ne 0 -or
        [int]$baseline.Guards.DisabledLegacySteps -ne [int]$baseline.Guards.LegacySteps) {
        Stop-PackageUpdater 'PACKAGE_TARGET_IDENTITY_MISMATCH'
    }
    $modifiedOnMatches = Test-PackageModifiedOnMatchesBaseline `
        -CurrentModifiedOn $PackageSnapshot.ModifiedOn `
        -BaselineModifiedOn $baseline.Package.modifiedon
    $membership = Get-DevelopmentMembershipFingerprint -SolutionId ([string]$solutions[0].solutionid)
    $baselineMembershipLines = @($baseline.Memberships | ForEach-Object {
        '{0}|{1}|{2}' -f [int]$_.componenttype,
            ([string]$_.objectid).ToLowerInvariant(),
            [int]$_.rootcomponentbehavior
    } | Sort-Object -CaseSensitive)
    $apiPlan = Get-ApprovedDevelopmentApiParameterPlan -Baseline $baseline
    $maskInputs = @($PackageSnapshot.ApiInputDetails | Where-Object {
        [string]$_.Name -ceq 'ProfileFieldMask'
    })
    $maskPresent = $maskInputs.Count -eq 1
    $membershipMatchesApprovedPlan = Test-ApprovedDevelopmentMembershipDelta `
        -BaselineLines $baselineMembershipLines -CurrentLines $membership.Lines `
        -ApiParameterId ([string]$apiPlan.Writes[0].Id) -ApiParameterPresent $maskPresent
    if (-not $modifiedOnMatches) {
        Stop-PackageUpdater 'PACKAGE_MODIFIED_SINCE_BASELINE'
    }
    if (-not $membershipMatchesApprovedPlan -or
        $PackageSnapshot.ProtectCandidateCoreStepCount -ne $baseline.Guards.DisabledLegacySteps) {
        Stop-PackageUpdater 'PACKAGE_TOPOLOGY_PREFLIGHT_FAILED'
    }

    $contract = Get-Content -LiteralPath (Join-Path $script:Root 'docs\PHASE_3C_API_CONTRACT.json') -Raw |
        ConvertFrom-Json
    $expectedInputs = @($contract.inputs | Where-Object {
        $maskPresent -or [string]$_.name -cne 'ProfileFieldMask'
    } | ForEach-Object { [string]$_.name } | Sort-Object -CaseSensitive)
    $expectedOutputs = @($contract.outputs | ForEach-Object { [string]$_.name } |
        Sort-Object -CaseSensitive)
    $actualInputs = @($PackageSnapshot.ApiInputNames | Sort-Object -CaseSensitive)
    $actualOutputs = @($PackageSnapshot.ApiOutputNames | Sort-Object -CaseSensitive)
    $expectedInputCount = if ($maskPresent) { 21 } else { 20 }
    if ($maskInputs.Count -gt 1 -or $PackageSnapshot.ApiInputCount -ne $expectedInputCount -or
        $PackageSnapshot.ApiOutputCount -ne 5 -or
        [string]::Join('|', $actualInputs) -cne [string]::Join('|', $expectedInputs) -or
        [string]::Join('|', $actualOutputs) -cne [string]::Join('|', $expectedOutputs)) {
        Stop-PackageUpdater 'PACKAGE_TOPOLOGY_PREFLIGHT_FAILED'
    }
    if ($maskPresent -and
        ([string]$maskInputs[0].Id -ine [string]$apiPlan.Writes[0].Id -or
            [string]$maskInputs[0].ApiId -ine [string]$apiPlan.ApiId -or
            [int]$maskInputs[0].Type -ne [int]$apiPlan.Writes[0].Type -or
            [bool]$maskInputs[0].IsOptional -ne [bool]$apiPlan.Writes[0].IsOptional)) {
        Stop-PackageUpdater 'PACKAGE_TOPOLOGY_PREFLIGHT_FAILED'
    }

    $bsoRoleName = 'BSO-RS Support - BSO'
    $bsoExpected = Get-RolePrivilegeMapFromXml `
        -Path (Join-Path $script:Root 'solutions\Roles\BSO-RS Support - BSO.xml') `
        -ExpectedRoleName $bsoRoleName
    $bsoActual = Get-DevRoleState -RoleName $bsoRoleName
    if (-not (Test-RolePrivilegeMapEqual -Expected $bsoExpected -Actual $bsoActual.Privileges)) {
        Stop-PackageUpdater 'PACKAGE_SECURITY_PREFLIGHT_FAILED'
    }
    $protectedWritePrivileges = @(
        foreach ($table in $contract.protectedTables) {
            "prvCreate$([string]$table)"
            "prvWrite$([string]$table)"
        }
    )
    if (@($bsoActual.Privileges.Keys | Where-Object { $_ -cin $protectedWritePrivileges }).Count -gt 0) {
        Stop-PackageUpdater 'PACKAGE_SECURITY_PREFLIGHT_FAILED'
    }

    $referenceRoleName = 'BSO-RS Support - Reference Admin'
    $referenceExpected = Get-RolePrivilegeMapFromXml `
        -Path (Join-Path $script:Root 'solutions\Roles\BSO-RS Support - Reference Admin.xml') `
        -ExpectedRoleName $referenceRoleName
    $referenceActual = Get-DevRoleState -RoleName $referenceRoleName
    if (-not (Test-RolePrivilegeMapEqual -Expected $referenceExpected -Actual $referenceActual.Privileges) -or
        $referenceActual.UserAssignmentCount -ne 0 -or
        $referenceActual.TeamAssignmentCount -ne 0) {
        Stop-PackageUpdater 'PACKAGE_SECURITY_PREFLIGHT_FAILED'
    }

    [pscustomobject]@{
        SolutionVersion = [string]$solutions[0].version
        ApplicationUniqueName = [string]$apps[0].uniquename
        PackageModifiedOnMatchesBaseline = $modifiedOnMatches
        SolutionMembershipCount = $membership.Count
        SolutionMembershipMatchesApprovedPlan = $membershipMatchesApprovedPlan
        ApiInputCount = $PackageSnapshot.ApiInputCount
        ProfileFieldMaskParameterReconciled = $maskPresent
        ApiOutputCount = $PackageSnapshot.ApiOutputCount
        ProtectCandidateCoreStepCount = $PackageSnapshot.ProtectCandidateCoreStepCount
        AllProtectCandidateCoreStepsInactive = [bool]$PackageSnapshot.AllProtectCandidateCoreStepsInactive
        NoActiveLegacyHandlers = [bool]$PackageSnapshot.NoActiveLegacyHandlers
        BsoRoleDefinitionUnchanged = $true
        BsoProtectedDirectCreateWriteAbsent = $true
        ReferenceAdminRoleDefinitionUnchanged = $true
        ReferenceAdminRoleUnassigned = $true
    }
}

function Assert-TargetAgreement {
    param([Parameter(Mandatory)][object]$PacIdentity)
    if ($PacIdentity.OrganizationUrl -cne (ConvertTo-NormalizedOrganizationUrl -Value $OrganizationUrl) -or
        $PacIdentity.OrganizationId -cne (ConvertTo-CanonicalGuid -Value $ExpectedOrganizationId) -or
        $PacIdentity.EnvironmentId -cne (ConvertTo-CanonicalGuid -Value $ExpectedEnvironmentId)) {
        Stop-PackageUpdater 'PACKAGE_TARGET_IDENTITY_MISMATCH'
    }
    $token = Get-ValidatedDataverseToken -TargetUrl $PacIdentity.OrganizationUrl -PacUserEmail $PacIdentity.UserEmail
    $script:AccessToken = $token
    $script:ApiRoot = $PacIdentity.OrganizationUrl.TrimEnd('/') + '/api/data/v9.2/'
    $who = Invoke-DataverseGet -Path 'WhoAmI'
    if ((ConvertTo-CanonicalGuid -Value ([string]$who.OrganizationId)) -cne
        (ConvertTo-CanonicalGuid -Value $ExpectedOrganizationId) -or
        (ConvertTo-CanonicalGuid -Value ([string]$who.UserId)) -cne $PacIdentity.UserId) {
        Stop-PackageUpdater 'PACKAGE_TARGET_IDENTITY_MISMATCH'
    }
}

function Invoke-PacPluginPush {
    param(
        [Parameter(Mandatory)][string]$Executable,
        [Parameter(Mandatory)][string[]]$Arguments
    )
    $path = Get-PacExecutablePath -Executable $Executable
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $path
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($argument in $Arguments) { $null = $start.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    try {
        $script:DispatchCount++
        if (-not $process.Start()) {
            $script:DispatchCount--
            return [pscustomobject]@{
                ProcessStarted = $false
                ExitCode = -1
                Classification = 'NOT_DISPATCHED'
            }
        }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        $classification = Get-PacPushClassification -ProcessStarted $true `
            -ExitCode $process.ExitCode -StandardOutput $stdout -StandardError $stderr
        [pscustomobject]@{
            ProcessStarted = $true
            ExitCode = $process.ExitCode
            Classification = $classification
        }
    } catch {
        [pscustomobject]@{
            ProcessStarted = $true
            ExitCode = -1
            Classification = 'PAC_RESULT_AMBIGUOUS'
        }
    } finally {
        $process.Dispose()
    }
}

function New-PlanResult {
    param([Parameter(Mandatory)][object]$Artifact)
    [pscustomobject]@{
        Result = 'PACKAGE_UPDATE_PLAN_READY_NOT_DISPATCHED'
        TargetProfile = $TargetProfile
        PackageFileName = $Artifact.FileName
        PackageSha256 = $Artifact.Sha256
        PackageUniqueName = $Artifact.UniqueName
        PackageVersion = $Artifact.Version
        HandlerTypeName = $Artifact.HandlerTypeName
        PacCommand = 'pac plugin push'
        ArgumentContract = @(
            '--environment <approved-target-url>',
            '--pluginId <existing-pluginpackageid>',
            '--pluginFile <validated-package-file>',
            '--type Nuget',
            '--configuration Release'
        )
        MaximumDispatchCount = 1
        AutomaticRetries = 0
        NetworkOperations = 0
        JournalWritten = $false
        ReadOnlyRequestCount = 0
        PacVersionCheckCount = 0
        PacIdentityCheckCount = 0
        DispatchCount = 0
    }
}

function Invoke-PackageUpdaterMain {
    Assert-UpdaterInputs -RequestedMode $Mode
    $artifact = Get-PackageArtifactEvidence -Path $ArtifactPath `
        -ExpectedSha256 $ExpectedPackageSha256 `
        -ExpectedUniqueName $ExpectedPackageUniqueName `
        -ExpectedHandler $ExpectedHandlerTypeName `
        -DevelopmentSourceAheadOfFrozenRelease ([bool]$DevelopmentSourceAheadOfFrozenRelease) `
        -ExpectedAssemblySha256 $ExpectedAssemblySha256
    if ($Mode -ceq 'Plan') {
        return New-PlanResult -Artifact $artifact
    }

    if ($TargetProfile -cne 'DEV') {
        $null = Assert-ApprovedTargetEvidence -Profile $TargetProfile
    }
    if ($Mode -ceq 'Apply' -and (Test-Path -LiteralPath $JournalPath)) {
        Stop-PackageUpdater 'PACKAGE_DISPATCH_JOURNAL_ALREADY_EXISTS'
    }
    $journal = $null
    if ($Mode -ceq 'Reconcile') {
        if (-not (Test-Path -LiteralPath $JournalPath -PathType Leaf)) {
            Stop-PackageUpdater 'PACKAGE_DISPATCH_JOURNAL_NOT_FOUND'
        }
        try {
            $journal = Get-Content -LiteralPath $JournalPath -Raw | ConvertFrom-Json
        } catch {
            Stop-PackageUpdater 'PACKAGE_DISPATCH_JOURNAL_NOT_RECONCILABLE'
        }
        if ($null -eq $journal) { Stop-PackageUpdater 'PACKAGE_DISPATCH_JOURNAL_NOT_RECONCILABLE' }
        Assert-ReconcileJournal -Journal $journal
        $script:PriorDispatchCount = [int]$journal.dispatchCount
    }
    $pacIdentity = Get-PacTargetIdentity -Executable $PacPath
    Assert-TargetAgreement -PacIdentity $pacIdentity
    $expectedEnvironmentName = if ($TargetProfile -ceq 'DEV') {
        $ExpectedEnvironmentDisplayName
    } else {
        [string](Get-Content -LiteralPath $ApprovalEvidencePath -Raw | ConvertFrom-Json).environmentDisplayName
    }
    if ($pacIdentity.EnvironmentName -cne $expectedEnvironmentName) {
        Stop-PackageUpdater 'PACKAGE_TARGET_IDENTITY_MISMATCH'
    }

    if ($Mode -ceq 'Preflight') {
        $packages = @(Get-PagedRows -Path "pluginpackages?`$select=pluginpackageid,name,uniquename,version,modifiedon&`$filter=uniquename eq '$ExpectedPackageUniqueName'")
        $package = Resolve-PackageMatch -Rows $packages -UniqueName $ExpectedPackageUniqueName
        $packageCount = @(Get-PagedRows -Path 'pluginpackages?$select=pluginpackageid').Count
        $snapshot = Get-TopologySnapshot -PackageRow $package -PackageCountBefore $packageCount -Before $null
        Assert-PreflightTopology -Snapshot $snapshot
        $baseline = Assert-DevelopmentDeploymentBaseline -PackageSnapshot $snapshot
        return [pscustomobject]@{
            Result = 'P0_PROFILE_MASK_DEV_PREFLIGHT_READY_NOT_DISPATCHED'
            Classification = 'PROFILE_FIELD_MASK_DEV_DEPLOYMENT_PREFLIGHT_READY'
            EnvironmentName = $pacIdentity.EnvironmentName
            PackageUniqueName = $snapshot.PackageName
            PackageVersion = $snapshot.PackageVersion
            Topology = $baseline
            DispatchCount = 0
            RetryCount = 0
            JournalWritten = $false
            ReadOnlyRequestCount = $script:ReadRequestCount
            PacVersionCheckCount = $script:PacVersionCheckCount
            PacIdentityCheckCount = $script:PacIdentityCheckCount
            NetworkOperations = $script:ReadRequestCount + $script:PacIdentityCheckCount
            CredentialsLogged = $false
            RawFaultTextLogged = $false
        }
    }

    if ($Mode -ceq 'Reconcile') {
        $packages = @(Get-PagedRows -Path "pluginpackages?`$select=pluginpackageid,name,uniquename,version,modifiedon&`$filter=uniquename eq '$ExpectedPackageUniqueName'")
        $package = Resolve-PackageMatch -Rows $packages -UniqueName $ExpectedPackageUniqueName
        if ((Get-PackageIdFingerprint -PackageId ([string]$package.pluginpackageid)) -cne
            [string]$journal.packageRecordIdentitySha256) {
            Stop-PackageUpdater 'PACKAGE_IDENTITY_AMBIGUOUS'
        }
        $snapshot = Get-TopologySnapshot -PackageRow $package -PackageCountBefore ([int]$journal.preflightTopology.PackageCount) -Before $journal.preflightTopology
        $predicates = Get-SanitizedTopologyPredicates -Snapshot $snapshot
        $journal.reconciliation = $predicates
        $journal.finalClassification = 'READ_ONLY_RECONCILIATION_COMPLETE_OUTCOME_STILL_AMBIGUOUS'
        Save-ExistingJournal -Path $JournalPath -Journal $journal
        return [pscustomobject]@{
            Result = $journal.finalClassification
            DispatchCount = [int]$journal.dispatchCount
            CurrentRunDispatchCount = 0
            RetryCount = 0
            ReadOnlyRequestCount = $script:ReadRequestCount
            PacVersionCheckCount = $script:PacVersionCheckCount
            PacIdentityCheckCount = $script:PacIdentityCheckCount
            NetworkOperations = $script:ReadRequestCount + $script:PacIdentityCheckCount
            Topology = $predicates
        }
    }

    $packages = @(Get-PagedRows -Path "pluginpackages?`$select=pluginpackageid,name,uniquename,version,modifiedon&`$filter=uniquename eq '$ExpectedPackageUniqueName'")
    $package = Resolve-PackageMatch -Rows $packages -UniqueName $ExpectedPackageUniqueName
    $packageCount = @(Get-PagedRows -Path 'pluginpackages?$select=pluginpackageid').Count
    $before = Get-TopologySnapshot -PackageRow $package -PackageCountBefore $packageCount -Before $null
    Assert-PreflightTopology -Snapshot $before
    if ($TargetProfile -ceq 'DEV') {
        $null = Assert-DevelopmentDeploymentBaseline -PackageSnapshot $before
    }

    $journal = New-PackageUpdaterJournal -Profile $TargetProfile `
        -UniqueName $ExpectedPackageUniqueName -ArtifactSha256 $artifact.Sha256 `
        -EnvironmentId $ExpectedEnvironmentId -OrganizationId $ExpectedOrganizationId `
        -DevelopmentSourceAheadOfFrozenRelease ([bool]$DevelopmentSourceAheadOfFrozenRelease)
    $journal.packageRecordIdentitySha256 = $before.PackageIdFingerprint
    $journal.preflightTopology = [ordered]@{
        packageRecordIdentitySha256 = $before.PackageIdFingerprint
        packageAssemblyIdentitySha256 = Get-Sha256FromBytes -Bytes ([Text.Encoding]::UTF8.GetBytes($before.AssemblyId.ToLowerInvariant()))
        handlerTypeIdentitySha256 = Get-Sha256FromBytes -Bytes ([Text.Encoding]::UTF8.GetBytes($before.HandlerTypeId.ToLowerInvariant()))
        apiMetadataSha256 = $before.ApiMetadataSha256
        legacyAssemblyIdentitySha256 = Get-Sha256FromBytes -Bytes ([Text.Encoding]::UTF8.GetBytes($before.LegacyAssemblyId.ToLowerInvariant()))
        legacyAssemblySha256 = $before.LegacyAssemblySha256
        packageCount = $before.PackageCount
        predicates = Get-SanitizedTopologyPredicates -Snapshot $before
    }

    $arguments = New-PacPluginPushArguments `
        -NormalizedOrganizationUrl (ConvertTo-NormalizedOrganizationUrl -Value $OrganizationUrl) `
        -ExistingPackageId $before.PackageId -PackageFile $artifact.FullPath
    $state = Invoke-OneShotDispatchStateMachine -Path $JournalPath -Journal $journal `
        -Dispatch { Invoke-PacPluginPush -Executable $PacPath -Arguments $arguments } `
        -Reconcile {
            $afterRows = @(Get-PagedRows -Path "pluginpackages?`$select=pluginpackageid,name,uniquename,version,modifiedon&`$filter=uniquename eq '$ExpectedPackageUniqueName'")
            $afterPackage = Resolve-PackageMatch -Rows $afterRows -UniqueName $ExpectedPackageUniqueName
            Get-TopologySnapshot -PackageRow $afterPackage -PackageCountBefore $before.PackageCount -Before $before
        }
    if ($state.Result -ceq 'DEPLOYMENT_CONFIRMED') {
        $state | Add-Member -NotePropertyName Topology -NotePropertyValue (Get-Content -LiteralPath $JournalPath -Raw | ConvertFrom-Json).reconciliation
    }
    $state
}

if ($MyInvocation.InvocationName -ne '.') {
    try {
        Invoke-PackageUpdaterMain
    } catch {
        $code = [string]$_.Exception.Message
        if ($code -notmatch '^[A-Z0-9_]+$') { $code = 'PACKAGE_UPDATER_INTERNAL_FAILURE' }
        $result = if ($script:DispatchCount -gt 0 -or $script:PriorDispatchCount -gt 0) {
            'DEPLOYMENT_OUTCOME_AMBIGUOUS_REQUIRES_RECONCILIATION'
        } elseif ($code -in @(
            'PACKAGE_UPDATE_REJECTED',
            'DEPLOYMENT_CONFIRMED',
            'PACKAGE_UPDATE_PLAN_READY_NOT_DISPATCHED',
            'READ_ONLY_RECONCILIATION_COMPLETE_OUTCOME_STILL_AMBIGUOUS'
        )) { $code } else { 'DEPLOYMENT_NOT_DISPATCHED' }
        [pscustomobject]@{
            Result = $result
            FailureCode = $code
            DispatchCount = $script:DispatchCount
            PriorDispatchCount = $script:PriorDispatchCount
            RetryCount = 0
            ReadOnlyRequestCount = $script:ReadRequestCount
            PacVersionCheckCount = $script:PacVersionCheckCount
            PacIdentityChecks = $script:PacIdentityCheckCount
            NetworkOperations = $script:ReadRequestCount + $script:PacIdentityCheckCount + $script:DispatchCount
            CredentialsLogged = $false
            RawFaultTextLogged = $false
        }
        exit 1
    }
}
