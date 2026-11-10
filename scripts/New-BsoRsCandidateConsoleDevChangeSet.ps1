#requires -Version 7.4
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$OrganizationUrl,
    [Parameter(Mandatory)][Guid]$EnvironmentId,
    [Parameter(Mandatory)][Guid]$OrganizationId,
    [Parameter(Mandatory)][string]$BaselineSnapshotPath,
    [Parameter(Mandatory)][string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$output = [IO.Path]::GetFullPath($OutputDirectory)
$relative = [IO.Path]::GetRelativePath($root, $output)
if ($relative -eq '.' -or
    (-not [IO.Path]::IsPathRooted($relative) -and $relative -notmatch '^\.\.(\\|$)')) {
    throw 'DEV_CHANGE_SET_EXTERNAL_DIRECTORY_REQUIRED'
}
if (Test-Path -LiteralPath $output) { throw 'DEV_CHANGE_SET_OUTPUT_ALREADY_EXISTS' }
$origin = $null
if (-not [Uri]::TryCreate($OrganizationUrl, [UriKind]::Absolute, [ref]$origin) -or
    $origin.Scheme -cne 'https' -or $origin.UserInfo -or $origin.AbsolutePath -ne '/' -or
    $origin.Query -or $origin.Fragment -or $EnvironmentId -eq [Guid]::Empty -or $OrganizationId -eq [Guid]::Empty) {
    throw 'DEV_CHANGE_SET_TARGET_INVALID'
}
$snapshot = Get-Content -LiteralPath $BaselineSnapshotPath -Raw | ConvertFrom-Json
if ($snapshot.solution.uniquename -cne 'os_sr_bso_rs_support' -or $snapshot.solution.ismanaged) {
    throw 'DEV_CHANGE_SET_SOLUTION_INVALID'
}
$names = @(
    'candidate-console.html', 'candidate-console-environment.js', 'candidate-console-policy.js',
    'candidate-console.js', 'candidate-console-availability.js'
)
function Get-BytesHash([byte[]]$Bytes) {
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes)).ToLowerInvariant()
}
$resources = @()
foreach ($name in $names) {
    $logicalName = "os_/bso/$name"
    $current = @($snapshot.current | Where-Object name -CEQ $logicalName)
    $published = @($snapshot.published | Where-Object name -CEQ $logicalName)
    $id = [Guid]::Empty
    if ($current.Count -ne 1 -or $published.Count -ne 1 -or
        -not [Guid]::TryParse([string]$current[0].webresourceid, [ref]$id) -or $id -eq [Guid]::Empty -or
        $published[0].webresourceid -ine $current[0].webresourceid -or
        $current[0].ismanaged -or $published[0].ismanaged) {
        throw 'DEV_CHANGE_SET_RESOURCE_MAPPING_INVALID'
    }
    $before = Get-BytesHash ([Convert]::FromBase64String($current[0].content))
    if ($before -cne (Get-BytesHash ([Convert]::FromBase64String($published[0].content)))) {
        throw 'DEV_CHANGE_SET_PENDING_DRAFT_REQUIRES_RECONCILIATION'
    }
    $resources += [ordered]@{
        name = $logicalName; id = $id.ToString('D'); baselineSha256 = $before
        expectedSha256 = $null; file = $name
    }
}
if (@($resources.id | Select-Object -Unique).Count -ne 5) { throw 'DEV_CHANGE_SET_DUPLICATE_RESOURCE_ID' }
if (@($snapshot.current).Count -ne 5 -or @($snapshot.published).Count -ne 5) {
    throw 'DEV_CHANGE_SET_SNAPSHOT_SCOPE_INVALID'
}

[IO.Directory]::CreateDirectory($output) | Out-Null
if ($IsWindows) {
    $identity = & whoami /user /fo csv /nh
    $sid = [regex]::Match(($identity -join ''), 'S-1-[0-9]+(?:-[0-9]+)+').Value
    if (-not $sid) { throw 'DEV_CHANGE_SET_EVIDENCE_IDENTITY_UNAVAILABLE' }
    & icacls $output /inheritance:r /grant:r "*${sid}:(OI)(CI)F" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'DEV_CHANGE_SET_EVIDENCE_PROTECTION_FAILED' }
} else {
    & chmod 700 $output
    if ($LASTEXITCODE -ne 0) { throw 'DEV_CHANGE_SET_EVIDENCE_PROTECTION_FAILED' }
}
& (Join-Path $PSScriptRoot 'New-BsoRsCandidateConsoleEnvironmentConfig.ps1') `
    -Mode DEV -OrganizationUrl $OrganizationUrl -EnvironmentId $EnvironmentId -OrganizationId $OrganizationId `
    -OutputConfigurationPath (Join-Path $output 'candidate-console-environment.js') `
    -OutputHtmlPath (Join-Path $output 'candidate-console.html') | Out-Null
$sourceDirectory = Join-Path $root 'solutions\CandidateConsole\WebResources\os_\bso'
foreach ($name in $names | Where-Object { $_ -notin @('candidate-console.html', 'candidate-console-environment.js') }) {
    Copy-Item -LiteralPath (Join-Path $sourceDirectory $name) -Destination (Join-Path $output $name)
}
foreach ($resource in $resources) {
    $resource.expectedSha256 = (Get-FileHash -LiteralPath (Join-Path $output $resource.file) -Algorithm SHA256).Hash.ToLowerInvariant()
}
$manifest = [ordered]@{
    schemaVersion = 1
    target = [ordered]@{
        organizationUrl = $origin.GetLeftPart([UriPartial]::Authority)
        environmentId = $EnvironmentId.ToString('D'); organizationId = $OrganizationId.ToString('D')
        solutionUniqueName = 'os_sr_bso_rs_support'
    }
    resources = $resources
    baselineSnapshotSha256 = (Get-FileHash -LiteralPath $BaselineSnapshotPath -Algorithm SHA256).Hash.ToLowerInvariant()
    scopeApprovalRequired = $true
    syntheticIsolation = 'IMPLEMENTED_OFFLINE_REQUIRES_SERVER_DEPLOYMENT_AND_VERIFICATION'
    publicationConcurrency = 'REQUIRES_CONFIRMED_CHANGE_WINDOW_AND_FRESH_CONDITIONAL_WRITES'
    baselineTargetBinding = 'MUST_REVALIDATE_LIVE'
    deploymentReady = $false
    requiredSequence = @(
        'Verify exact target/account, Solution membership and five resource IDs against this manifest.',
        'Approve revised hashes and separate server delta; install and verify the server-controlled profile and complete guard coverage before Console activation.',
        'Confirm a resource-specific edit/import/publish freeze covering applicable makers and automated publishers through final verification.',
        'Refresh current/published contents, exact ETags and permissions; stop on drift, missing evidence or conflicting activity.',
        'Capture fresh protected published/current rollback bytes and read back every hash.',
        'Under the confirmed window, PATCH only changed approved webresourceset(id) members once with Base64 file content and its fresh exact If-Match, never wildcard.',
        'After each acknowledged PATCH, verify current hash equals this manifest and published hash remains the captured baseline; stop on 412, failed or uncertain response.',
        'Reconfirm the window and all current hashes/versions immediately before one five-ID PublishXml using publish-request.json.',
        'Do not retry ambiguous updates/publication or automatically roll back; reconcile read-only.',
        'Verify published/current hashes, unchanged CSS, then run authentication-only.cjs with BSO_UAT_RESOURCE_MANIFEST_FILE pointing to this manifest.',
        'Require served hashes, policy loading, no unresolved Console errors, Calendar disabled and the correct fail-closed Create gate; lifecycle remains separately unauthorized.'
    )
}
$xml = '<importexportxml><webresources>' +
    (($resources | ForEach-Object { "<webresource>$($_.id)</webresource>" }) -join '') +
    '</webresources></importexportxml>'
[IO.File]::WriteAllText((Join-Path $output 'publish-request.json'),
    (@{ ParameterXml = $xml } | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $output 'manifest.json'),
    ($manifest | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))
[pscustomobject]@{ Result = 'DEV_CHANGE_SET_PREPARED_NOT_AUTHORIZED'; Directory = $output; DeploymentReady = $false }
