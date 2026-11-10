#requires -Version 7.4
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PackagePath,
    [Parameter(Mandatory)][string]$ConsoleManifestPath,
    [Parameter(Mandatory)][string]$OutputPath
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$output = [IO.Path]::GetFullPath($OutputPath)
$relative = [IO.Path]::GetRelativePath($root, $output)
if ($relative -eq '.' -or (-not [IO.Path]::IsPathRooted($relative) -and $relative -notmatch '^\.\.(\\|$)')) {
    throw 'ISOLATION_MANIFEST_EXTERNAL_PATH_REQUIRED'
}
if (Test-Path -LiteralPath $output) { throw 'ISOLATION_MANIFEST_OUTPUT_ALREADY_EXISTS' }
$console = Get-Content -LiteralPath $ConsoleManifestPath -Raw | ConvertFrom-Json
if ($console.resources.Count -ne 5 -or $console.target.solutionUniqueName -cne 'os_sr_bso_rs_support' -or
    $console.deploymentReady -ne $false) { throw 'ISOLATION_CONSOLE_MANIFEST_INVALID' }
$sourceFiles = @(
    'solutions\CandidateCore\DataversePlugin.cs',
    'solutions\CandidateCore\Operation.cs',
    'solutions\CandidateCore\SyntheticIsolation.cs',
    'solutions\CandidateCorePackage\CandidateCore.Package.csproj',
    'solutions\customapis\os_sr_cact\customapi.xml',
    'solutions\customapis\os_sr_cact\customapirequestparameters\SyntheticScopeId\customapirequestparameter.xml',
    'solutions\customapis\os_sr_cact\customapiresponseproperties\IsolationContract\customapiresponseproperty.xml'
)
$sources = @($sourceFiles | ForEach-Object {
    [ordered]@{ path = $_; sha256 = (Get-FileHash -LiteralPath (Join-Path $root $_) -Algorithm SHA256).Hash.ToLowerInvariant() }
})
$consoleDirectory = Split-Path -Parent $ConsoleManifestPath
$expectedFiles = @('candidate-console.html', 'candidate-console-environment.js', 'candidate-console-policy.js',
    'candidate-console.js', 'candidate-console-availability.js')
if ((@($console.resources.file | Sort-Object) -join '|') -cne (@($expectedFiles | Sort-Object) -join '|') -or
    @($console.resources.id | Select-Object -Unique).Count -ne 5) { throw 'ISOLATION_CONSOLE_MANIFEST_INVALID' }
foreach ($resource in $console.resources) {
    if ($resource.file -cnotmatch '^candidate-console(?:-environment|-policy|-availability)?\.(?:js|html)$' -or
        $resource.name -cne "os_/bso/$($resource.file)" -or
        (Get-FileHash -LiteralPath (Join-Path $consoleDirectory $resource.file) -Algorithm SHA256).Hash.ToLowerInvariant() -cne
            $resource.expectedSha256) { throw 'ISOLATION_CONSOLE_SOURCE_DRIFT' }
    if ($resource.file -notin @('candidate-console.html', 'candidate-console-environment.js') -and
        (Get-FileHash -LiteralPath (Join-Path $root "solutions\CandidateConsole\WebResources\os_\bso\$($resource.file)") -Algorithm SHA256).Hash.ToLowerInvariant() -cne
            $resource.expectedSha256) { throw 'ISOLATION_CONSOLE_SOURCE_DRIFT' }
}
$webResources = @($console.resources | ForEach-Object {
    [ordered]@{
        name = $_.name; id = $_.id; file = $_.file; baselineSha256 = $_.baselineSha256
        sourceSha256 = (Get-FileHash -LiteralPath (Join-Path $root "solutions\CandidateConsole\WebResources\os_\bso\$($_.file)") -Algorithm SHA256).Hash.ToLowerInvariant()
        expectedSha256 = $_.expectedSha256
    }
})
$configuration = Get-Content -LiteralPath (Join-Path $consoleDirectory 'candidate-console-environment.js') -Raw
$config = ([regex]::Match($configuration, 'const configuration = (\{.*\});').Groups[1].Value) | ConvertFrom-Json
if (-not $config -or $config.mode -cne 'DEV' -or -not $config.syntheticDataOnly -or
    -not $config.candidateCoreEnabled -or $config.devDirectWriteFallbackEnabled -or $config.diagnosticsMode -cne 'OFF' -or
    $config.organizationId -cne $console.target.organizationId -or $config.environmentId -cne $console.target.environmentId -or
    $config.organizationUrl -cne $console.target.organizationUrl -or
    ($config.PSObject.Properties.Name -contains 'availabilityEnabled' -and $config.availabilityEnabled)) {
    throw 'ISOLATION_CONSOLE_CONFIGURATION_INVALID'
}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$package = [IO.Compression.ZipFile]::OpenRead([IO.Path]::GetFullPath($PackagePath))
try {
    $dlls = @($package.Entries | Where-Object FullName -CEQ 'lib/net462/os_sr_cact.dll')
    if ($dlls.Count -ne 1) { throw 'ISOLATION_PACKAGE_ASSEMBLY_MISSING' }
    $stream = $dlls[0].Open()
    try { $assemblyHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream)).ToLowerInvariant() }
    finally { $stream.Dispose() }
} finally { $package.Dispose() }
$tables = @('os_sr_cand', 'os_sr_call', 'os_sr_csh', 'os_sr_intv', 'os_sr_oprc',
    'os_sr_pos', 'os_sr_csrc', 'os_sr_ta', 'os_sr_loc')
$steps = @(
    foreach ($table in $tables) {
        foreach ($message in @('Create', 'Update', 'Delete', 'Retrieve', 'RetrieveMultiple', 'RetrieveMultiplePost')) {
            [ordered]@{ handler = 'os_sr_cact.SyntheticIsolationGuard'; table = $table; message = $message
                stage = $(if ($message -in @('Retrieve', 'RetrieveMultiplePost')) { 40 } else { 20 }); mode = 0; filteringAttributes = ''; runAs = 'CALLING_USER' }
        }
    }
    foreach ($message in @('Associate', 'Disassociate')) {
        [ordered]@{ handler = 'os_sr_cact.SyntheticIsolationGuard'; table = $null; message = $message
            stage = 20; mode = 0; filteringAttributes = ''; runAs = 'CALLING_USER' }
    }
    foreach ($pair in @(@('RetrieveMultiple', 20), @('RetrieveMultiple', 40), @('Retrieve', 40))) {
        [ordered]@{ handler = 'os_sr_cact.SyntheticIsolationReadGuard'; table = $null; message = $pair[0]
            stage = $pair[1]; mode = 0; filteringAttributes = ''; runAs = 'CALLING_USER' }
    }
)
foreach ($step in $steps) { if ($step.message -ceq 'RetrieveMultiplePost') { $step.message = 'RetrieveMultiple' } }
$manifest = [ordered]@{
    schemaVersion = 1; release = 'candidate-core-synthetic-isolation-1.0.1-offline'
    implementation = 'IMPLEMENTED_OFFLINE_NOT_DEPLOYED'; deploymentReady = $false
    target = $console.target
    package = [ordered]@{ path = [IO.Path]::GetFullPath($PackagePath)
        sha256 = (Get-FileHash -LiteralPath $PackagePath -Algorithm SHA256).Hash.ToLowerInvariant()
        assemblySha256 = $assemblyHash
        provenance = 'LOCAL_BUILD_REQUIRES_REVIEW_AGAINST_SOURCE_HASHES' }
    sources = $sources; webResources = $webResources
    checkedInWebResourceChanges = @('candidate-console.html', 'candidate-console-policy.js',
        'candidate-console.js', 'candidate-console-availability.js')
    environmentResource = 'BOUND_DEV_GENERATED_CONFIGURATION_NOT_THE_DISABLED_SOURCE_TEMPLATE'
    css = 'UNCHANGED_EXCLUDED'
    serverComponents = [ordered]@{
        existingPackage = 'os_sr_cact_pkg'; existingApi = 'os_sr_cact'
        apiAdditions = @('optional Guid SyntheticScopeId', 'String IsolationContract response',
            'read-only ActionType VerifySyntheticIsolation')
        newPluginTypes = @('os_sr_cact.SyntheticIsolationGuard', 'os_sr_cact.SyntheticIsolationReadGuard')
        requiredBaseSteps = $steps
        additionalSupportedMessageSteps = @('Upsert', 'SetState', 'SetStateDynamicEntity', 'Assign', 'Merge',
            'CreateMultiple', 'UpdateMultiple', 'UpsertMultiple', 'DeleteMultiple')
        supportedMessageRule = 'Discover sdkmessagefilter per table; every supported write message requires an unfiltered synchronous stage-20 guard. Any unguardable message blocks verification.'
        configuration = [ordered]@{ proposedSchemaName = 'os_sr_siso'; type = 'String'
            definition = 'One active environmentvariabledefinition, no default value'
            currentValue = 'Exactly one active environmentvariablevalue; administrator-controlled XML'
            requiredAttributes = @('organizationId', 'environmentId', 'actorId', 'scopeId', 'expiresUtc',
                'positionId', 'sourceId', 'taId', 'locationId')
            candidateIdRule = 'Reserved Candidate ID equals the existing approved original marker GUID; never regenerate a marker to bypass a journal or receipt.'
            identityRule = '[SYNTHETIC-E2E] Playwright <scopeId>; pw-<scopeId>@example.invalid'
            configurationPrepared = $false }
        legacyDevSlice = 'os_sr_devcs entrypoint rejected; historical ProtectCandidateCore registrations remain inactive'
    }
    deploymentOrder = @(
        'Approve the separate server/API/registration/profile delta and revised WebResource bytes. No existing authorization covers this delta.',
        'Confirm DEV identity, supported registrations, restricted caller, TDS/search disabled and all nine tables change-tracking disabled. STOP for missing controls; do not change organization settings or roles implicitly.',
        'Establish a real edit/import/publish change window, with all owner srapp tabs closed during server/guard/profile installation and resource refresh; capture recoverable package/API/step/config/resource rollback evidence and conditional version checks.',
        'Install the reviewed package into the existing package identity; preserve the rollback assembly. Add the optional request/response metadata without changing API execution privilege.',
        'Register/verify all supported table and global guard steps with this package version. Do not reactivate historical ProtectCandidateCore steps.',
        'Install the separately approved single active server profile with exact protected bindings, original marker and explicit expiry. No client setting authorizes this profile.',
        'Invoke only VerifySyntheticIsolation and reconcile server readback. Any failure blocks Console activation.',
        'Conditionally update exactly the five approved revised Console resources; scope PublishXml to those IDs only, within the confirmed window; no retries of uncertain outcomes.',
        'Run the protected read-only Chromium hash/policy/isolation/Create-gate verification. No Create click or business dispatch.'
    )
    approvalBoundaries = @('SERVER_PACKAGE_AND_CUSTOM_API_METADATA', 'NEW_GUARD_REGISTRATIONS_AND_SERVER_PROFILE',
        'ANY_REQUIRED_ORGANIZATION_OR_SECURITY_CHANGE_SEPARATELY_NOT_AUTHORIZED',
        'REVISED_FIVE_WEBRESOURCE_BYTES_AND_SCOPED_PUBLICATION', 'FRESH_LIFECYCLE_AUTHORIZATION_ONLY_AFTER_READ_ONLY_ACCEPTANCE')
    readOnlyAcceptance = @('Exact DEV organization/environment/account and solution membership',
        'Correct API contract, package-backed handler identities/versions, complete active guard coverage and supported-message inventory',
        'Restricted caller cannot bypass plug-ins, impersonate, read audit history or modify server controls; TDS/search/change tracking are disabled',
        'One active server profile, exact original marker and approved active references, unexpired scope; verifier performs zero storage writes',
        'Five effective served hashes equal the manifest; correct policy initializes before all business reads',
        'Missing/denied/expired proof disables Create; genuine proof may enable Create; Check Calendar remains disabled',
        'Zero business writes, no lifecycle claim acquisition, no journal changes')
    historicalEvidence = 'PRESERVE_ALL_PRIOR_MANIFESTS_SNAPSHOTS_AUTHORIZATIONS_AND_JOURNALS'
}
$json = $manifest | ConvertTo-Json -Depth 14
[IO.File]::WriteAllText($output, $json, [Text.UTF8Encoding]::new($false))
[pscustomobject]@{ Result = 'ISOLATION_DELTA_PREPARED_NOT_AUTHORIZED'; Path = $output
    Sha256 = (Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash.ToLowerInvariant() }
