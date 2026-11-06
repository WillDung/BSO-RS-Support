#requires -Version 7.4
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('DEV', 'TEST', 'PROD', 'UNCONFIGURED')][string]$Mode,
    [string]$OrganizationUrl,
    [string]$EnvironmentId,
    [string]$OrganizationId,
    [Parameter(Mandatory)][string]$OutputConfigurationPath,
    [Parameter(Mandatory)][string]$OutputHtmlPath,
    [switch]$ReleaseProfile,
    [bool]$CandidateCoreEnabled = $true,
    [bool]$SyntheticDataOnly = $true,
    [switch]$AvailabilityEnabled,
    [switch]$DevDirectWriteFallbackEnabled,
    [ValidateSet('OFF', 'SAFE')][string]$DiagnosticsMode = 'OFF'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$releaseNeutral = $Mode -ceq 'UNCONFIGURED'
if ($AvailabilityEnabled -and
    ($Mode -cne 'DEV' -or -not $SyntheticDataOnly -or
     -not $CandidateCoreEnabled -or $ReleaseProfile)) {
    throw 'Availability can be enabled only for bound synthetic-only DEV with Candidate Core enabled and no release profile. Generation does not authorize deployment or activation.'
}
if ($Mode -ne 'PROD' -and -not $SyntheticDataOnly) {
    throw 'DEV and TEST configurations must remain synthetic-only.'
}
if ($Mode -ne 'DEV' -and $DevDirectWriteFallbackEnabled) {
    throw 'Direct-write fallback can be configured only for DEV.'
}
if ($releaseNeutral -and
    (-not [string]::IsNullOrWhiteSpace($OrganizationUrl) -or
     -not [string]::IsNullOrWhiteSpace($EnvironmentId) -or
     -not [string]::IsNullOrWhiteSpace($OrganizationId) -or
     $CandidateCoreEnabled -or -not $SyntheticDataOnly -or
     $DevDirectWriteFallbackEnabled -or $DiagnosticsMode -cne 'OFF' -or
     $ReleaseProfile)) {
    throw 'UNCONFIGURED release-neutral configuration requires no target binding, Candidate Core disabled, synthetic-only mode, fallback disabled, diagnostics Off, and no release profile.'
}
if (-not $releaseNeutral -and
    ([string]::IsNullOrWhiteSpace($OrganizationUrl) -or
     [string]::IsNullOrWhiteSpace($EnvironmentId) -or
     [string]::IsNullOrWhiteSpace($OrganizationId))) {
    throw 'Bound DEV, TEST, and PROD configurations require an explicit URL, environment ID, and organization ID.'
}
if ($ReleaseProfile -and
    (-not $CandidateCoreEnabled -or -not $SyntheticDataOnly -or
     $DevDirectWriteFallbackEnabled -or $DiagnosticsMode -cne 'OFF')) {
    throw 'Release profiles require Candidate Core, synthetic-only mode, fallback disabled, and diagnostics Off.'
}

$parsedEnvironmentId = [Guid]::Empty
$parsedOrganizationId = [Guid]::Empty
$organizationUrlValue = ''
$environmentIdValue = ''
$organizationIdValue = ''
if (-not $releaseNeutral) {
    if (-not [Guid]::TryParse($EnvironmentId, [ref]$parsedEnvironmentId) -or
        -not [Guid]::TryParse($OrganizationId, [ref]$parsedOrganizationId)) {
        throw 'Environment and organization IDs must be GUIDs.'
    }

    $organizationUri = $null
    if (-not [Uri]::TryCreate($OrganizationUrl, [UriKind]::Absolute, [ref]$organizationUri) -or
        $organizationUri.Scheme -cne 'https' -or
        $organizationUri.UserInfo -or
        $organizationUri.AbsolutePath -ne '/' -or
        $organizationUri.Query -or
        $organizationUri.Fragment) {
        throw 'Organization URL must be an HTTPS origin without credentials, path, query, or fragment.'
    }
    $organizationUrlValue = $organizationUri.GetLeftPart([UriPartial]::Authority).TrimEnd('/')
    $environmentIdValue = $parsedEnvironmentId.ToString('D').ToLowerInvariant()
    $organizationIdValue = $parsedOrganizationId.ToString('D').ToLowerInvariant()
}

$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
function Assert-ExternalOutputPath {
    param([Parameter(Mandatory)][string]$Path)
    $fullPath = [IO.Path]::GetFullPath($Path)
    $relativePath = [IO.Path]::GetRelativePath($repositoryRoot, $fullPath)
    if ($relativePath -eq '.' -or
        (-not [IO.Path]::IsPathRooted($relativePath) -and
         $relativePath -notmatch '^\.\.(\\|$)')) {
        throw 'Generated environment files must remain outside the repository.'
    }
    if (Test-Path -LiteralPath $fullPath) {
        throw 'Generated environment file already exists; choose a new path.'
    }
    if (-not (Test-Path -LiteralPath (Split-Path -Parent $fullPath) -PathType Container)) {
        throw 'Generated environment file parent directory must already exist.'
    }
    return $fullPath
}
$configurationFullPath = Assert-ExternalOutputPath -Path $OutputConfigurationPath
$htmlFullPath = Assert-ExternalOutputPath -Path $OutputHtmlPath
if ($configurationFullPath -ieq $htmlFullPath) {
    throw 'Configuration and HTML output paths must be different.'
}

$configuration = [ordered]@{
    mode = $Mode
    environmentId = $environmentIdValue
    organizationId = $organizationIdValue
    organizationUrl = $organizationUrlValue
    candidateCoreEnabled = $CandidateCoreEnabled
    syntheticDataOnly = $SyntheticDataOnly
    devDirectWriteFallbackEnabled = [bool]$DevDirectWriteFallbackEnabled
    diagnosticsMode = $DiagnosticsMode
}
if ($AvailabilityEnabled) {
    $configuration.availabilityEnabled = $true
}
$json = ConvertTo-Json -InputObject $configuration -Depth 4 -Compress
$source = @"
(function (global) {
  "use strict";

  const configuration = $json;
  Object.defineProperty(global, "BsoRsCandidateConsoleConfiguration", {
    configurable: false,
    enumerable: false,
    writable: false,
    value: Object.freeze(configuration)
  });
})(window);
"@
$sourceBytes = [Text.UTF8Encoding]::new($false).GetBytes($source)
$hash = [Convert]::ToHexString(
    [Security.Cryptography.SHA256]::HashData($sourceBytes)
).ToLowerInvariant()
$templateHtmlPath = Join-Path $repositoryRoot 'solutions\CandidateConsole\WebResources\os_\bso\candidate-console.html'
$html = [IO.File]::ReadAllText($templateHtmlPath)
$configScriptPattern = 'candidate-console-environment\.js\?v=[0-9a-f]+'
$configScriptMatches = [regex]::Matches($html, $configScriptPattern)
if ($configScriptMatches.Count -ne 1) {
    throw 'Candidate Console HTML must contain exactly one versioned environment configuration script.'
}
$generatedHtml = [regex]::Replace(
    $html,
    $configScriptPattern,
    "candidate-console-environment.js?v=$($hash.Substring(0, 12))"
)
if ($AvailabilityEnabled) {
    $availabilityScriptPattern = 'candidate-console-availability\.js\?v=[0-9a-z-]+'
    if ([regex]::Matches($generatedHtml, $availabilityScriptPattern).Count -ne 1) {
        throw 'Candidate Console HTML must contain exactly one versioned availability script.'
    }
    $availabilityPath = Join-Path $repositoryRoot 'solutions\CandidateConsole\WebResources\os_\bso\candidate-console-availability.js'
    $availabilityHash = (Get-FileHash -LiteralPath $availabilityPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $generatedHtml = [regex]::Replace(
        $generatedHtml,
        $availabilityScriptPattern,
        "candidate-console-availability.js?v=$($availabilityHash.Substring(0, 12))"
    )
}
[IO.File]::WriteAllBytes($configurationFullPath, $sourceBytes)
[IO.File]::WriteAllText($htmlFullPath, $generatedHtml, [Text.UTF8Encoding]::new($false))

[pscustomobject]@{
    Result = 'CANDIDATE_CONSOLE_ENVIRONMENT_CONFIG_CREATED'
    Mode = $Mode
    ReleaseProfile = [bool]$ReleaseProfile
    CandidateCoreEnabled = $CandidateCoreEnabled
    SyntheticDataOnly = $SyntheticDataOnly
    AvailabilityEnabled = [bool]$AvailabilityEnabled
    DevDirectWriteFallbackEnabled = [bool]$DevDirectWriteFallbackEnabled
    DiagnosticsMode = $DiagnosticsMode
    OutputConfigurationPath = $configurationFullPath
    OutputHtmlPath = $htmlFullPath
    Sha256 = $hash
}
