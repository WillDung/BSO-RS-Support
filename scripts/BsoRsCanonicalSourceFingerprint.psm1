Set-StrictMode -Version Latest

$script:CanonicalSourceFingerprintAlgorithm = 'SHA256_OF_UTF8_SORTED_GIT_INDEX_LINES_RELATIVE_PATH_PIPE_RAW_FILE_SHA256'

function Get-BsoRsSha256OfSortedUtf8Lines {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()]
        [string[]]$Lines = @()
    )

    $orderedLines = [string[]]@($Lines)
    [Array]::Sort($orderedLines, [StringComparer]::Ordinal)
    $payload = [Text.UTF8Encoding]::new($false).GetBytes($orderedLines -join "`n")
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($payload)).ToLowerInvariant()
}

function Get-BsoRsCanonicalSourceFingerprint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Files
    )

    $seenPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $lines = foreach ($file in $Files) {
        $path = ([string]$file.Path).Replace('\', '/')
        $hash = ([string]$file.Sha256).ToLowerInvariant()

        if ([string]::IsNullOrWhiteSpace($path) -or
            $path.StartsWith('/') -or
            $path -match '^[A-Za-z]:' -or
            $path.Contains('|') -or $path.Contains("`n") -or $path.Contains("`r") -or
            @($path.Split('/') | Where-Object { $_ -in @('', '.', '..') }).Count -gt 0) {
            throw 'Canonical source inventory contains an invalid relative path.'
        }
        if ($hash -notmatch '\A[0-9a-f]{64}\z') {
            throw 'Canonical source inventory contains an invalid SHA-256 value.'
        }
        if (-not $seenPaths.Add($path)) {
            throw 'Canonical source inventory contains duplicate normalized paths.'
        }

        "$path|$hash"
    }

    Get-BsoRsSha256OfSortedUtf8Lines -Lines ([string[]]@($lines))
}

function Get-BsoRsCanonicalSourceInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepositoryRoot
    )

    $repositoryPath = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $RepositoryRoot).Path)
    $trackedPaths = @(& git -C $repositoryPath ls-files --cached -- 'solutions/')
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to enumerate Git-index canonical Solution source.'
    }

    $untrackedPaths = @(& git -C $repositoryPath ls-files --others --exclude-standard -- 'solutions/')
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to check for untracked canonical Solution source.'
    }
    if ($untrackedPaths.Count -gt 0) {
        throw 'Unignored untracked files exist under canonical Solution source.'
    }
    if ($trackedPaths.Count -eq 0) {
        throw 'No Git-index canonical Solution source files were found.'
    }

    $relativePaths = foreach ($trackedPath in $trackedPaths) {
        $normalized = ([string]$trackedPath).Replace('\', '/')
        if (-not $normalized.StartsWith('solutions/', [StringComparison]::Ordinal)) {
            throw 'Git returned a path outside canonical Solution source.'
        }
        $normalized.Substring('solutions/'.Length)
    }
    $relativePaths = [string[]]@($relativePaths)
    [Array]::Sort($relativePaths, [StringComparer]::Ordinal)

    $files = foreach ($relativePath in $relativePaths) {
        $fullPath = Join-Path $repositoryPath (Join-Path 'solutions' ($relativePath.Replace('/', [IO.Path]::DirectorySeparatorChar)))
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
            throw 'A Git-index canonical Solution file is missing from the working tree.'
        }

        $bytes = [IO.File]::ReadAllBytes($fullPath)
        $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
        [pscustomobject]@{
            Path = $relativePath
            FullPath = $fullPath
            Length = $bytes.Length
            Sha256 = $hash
        }
    }
    $files = @($files)

    [pscustomobject]@{
        Algorithm = $script:CanonicalSourceFingerprintAlgorithm
        FileCount = $files.Count
        Fingerprint = Get-BsoRsCanonicalSourceFingerprint -Files $files
        Files = $files
    }
}

Export-ModuleMember -Function Get-BsoRsSha256OfSortedUtf8Lines, Get-BsoRsCanonicalSourceFingerprint, Get-BsoRsCanonicalSourceInventory
