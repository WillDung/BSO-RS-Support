#requires -Version 7.4
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ExportFolder,
    [string]$OutputPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'docs\SOLUTION_COMPONENT_INVENTORY.json')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$solutionPath = Join-Path $ExportFolder 'Other\Solution.xml'
if (-not (Test-Path -LiteralPath $solutionPath -PathType Leaf)) {
    throw 'The supplied folder is not an unpacked Solution export.'
}

[xml]$solution = [IO.File]::ReadAllText($solutionPath)
$roots = @($solution.SelectNodes('//*[local-name()="RootComponent"]'))
if ($roots.Count -ne 72) {
    throw "Expected the retained 72-root export; found $($roots.Count)."
}

function Get-RelativePath {
    param([Parameter(Mandatory)][string]$Path)
    [IO.Path]::GetRelativePath($ExportFolder, $Path).Replace('\', '/')
}

$roleById = @{}
foreach ($file in Get-ChildItem -LiteralPath (Join-Path $ExportFolder 'Roles') -Filter '*.xml' -File) {
    [xml]$role = [IO.File]::ReadAllText($file.FullName)
    $roleById[[string]$role.DocumentElement.GetAttribute('id').Trim('{}').ToLowerInvariant()] = Get-RelativePath $file.FullName
}

$stepById = @{}
foreach ($file in Get-ChildItem -LiteralPath (Join-Path $ExportFolder 'SdkMessageProcessingSteps') -Filter '*.xml' -File) {
    [xml]$step = [IO.File]::ReadAllText($file.FullName)
    $id = $step.DocumentElement.GetAttribute('SdkMessageProcessingStepId').Trim('{}').ToLowerInvariant()
    $stepById[$id] = [ordered]@{
        name = $step.DocumentElement.GetAttribute('Name')
        sourcePath = Get-RelativePath $file.FullName
    }
}

$components = foreach ($root in $roots) {
    $type = $root.GetAttribute('type')
    $id = $root.GetAttribute('id').Trim('{}').ToLowerInvariant()
    $schemaName = $root.GetAttribute('schemaName')
    $name = $schemaName
    $sourceMapping = $null
    $disposition = 'RETAINED_SOURCE'

    switch ($type) {
        '1' {
            $name = $schemaName
            $sourceMapping = "Entities/$schemaName/Entity.xml"
        }
        '9' {
            $name = $schemaName
            $sourceMapping = "OptionSets/$schemaName.xml"
        }
        '20' {
            $sourceMapping = $roleById[$id]
            if (-not $sourceMapping) { throw "Role root has no exported source mapping: $id" }
            $name = [IO.Path]::GetFileNameWithoutExtension($sourceMapping)
        }
        '61' {
            $name = $schemaName
            $fileName = [IO.Path]::GetFileName($schemaName)
            $sourceMapping = "CandidateConsole/WebResources/os_/bso/$fileName; WebResources/os_/bso/$fileName.data.xml"
        }
        '62' {
            $name = $schemaName
            $sourceMapping = "AppModuleSiteMaps/$schemaName/AppModuleSiteMap.xml"
        }
        '80' {
            $name = $schemaName
            $sourceMapping = "AppModules/$schemaName/AppModule.xml"
        }
        '91' {
            $name = $schemaName
            if ($schemaName -match 'PublicKeyToken=d73b02688ba7f9aa') {
                $disposition = 'ROLLBACK_ONLY_SIGNED_ASSEMBLY_NOT_RETAINED'
                $sourceMapping = 'Rollback manifest only; binary excluded from canonical source.'
            } else {
                $disposition = 'GENERATED_FROM_CANONICAL_SOURCE'
                $sourceMapping = 'Generated from pluginpackages/os_sr_cact_pkg/pluginpackage.xml and package/os_sr_cact_pkg.nupkg; confirm live packageid linkage before release.'
            }
        }
        '92' {
            $stepRecord = $stepById[$id]
            if (-not $stepRecord) { throw "Step root has no exported source mapping: $id" }
            $name = $stepRecord.name
            $sourceMapping = 'Step definition inventoried from export; excluded from release to prevent guard reactivation.'
            $disposition = 'INACTIVE_PROTECTCANDIDATECORE_GUARD_EXCLUDED_FROM_RELEASE'
        }
        default { throw "Unsupported root component type: $type" }
    }

    [ordered]@{
        type = [int]$type
        typeName = switch ($type) {
            '1' { 'Entity' }
            '9' { 'OptionSet' }
            '20' { 'SecurityRole' }
            '61' { 'WebResource' }
            '62' { 'AppModuleSiteMap' }
            '80' { 'AppModule' }
            '91' { 'PluginAssembly' }
            '92' { 'SdkMessageProcessingStep' }
        }
        id = if ($id) { $id } else { $null }
        schemaName = if ($schemaName) { $schemaName } else { $null }
        name = $name
        sourceMapping = $sourceMapping
        disposition = $disposition
    }
}

$counts = @($components | Group-Object { [int]$_['type'] } | Sort-Object { [int]$_.Name } | ForEach-Object {
    $group = $_
    [ordered]@{
        componentType = [int]$group.Name
        typeName = [string]$group.Group[0]['typeName']
        count = [int]$group.Count
    }
})
$allApiFiles = @(Get-ChildItem -LiteralPath (Join-Path $ExportFolder 'customapis') -Recurse -File)
$coreApiFiles = @(Get-ChildItem -LiteralPath (Join-Path $ExportFolder 'customapis\os_sr_cact') -Recurse -File)
$temporaryApiFiles = @(Get-ChildItem -LiteralPath (Join-Path $ExportFolder 'customapis\os_sr_devcs') -Recurse -File)
$entityMetadataFiles = @(Get-ChildItem -LiteralPath (Join-Path $ExportFolder 'Entities') -Recurse -File)
$webResourceMetadataFiles = @(Get-ChildItem -LiteralPath (Join-Path $ExportFolder 'WebResources') -Filter '*.data.xml' -File -Recurse)
$inventory = [ordered]@{
    provenance = 'Unmanaged PAC export unpacked 2026-10-29; 72 root components; environment URL and environment/organization identifiers excluded. Structural component IDs are retained where supplied by the export.'
    rootComponentCount = $components.Count
    countsByType = $counts
    additionalSourceAreas = [ordered]@{
        customApiFilesInExport = $allApiFiles.Count
        retainedCandidateCoreApiFiles = $coreApiFiles.Count
        excludedTemporaryDevApiFiles = $temporaryApiFiles.Count
        entityMetadataFiles = $entityMetadataFiles.Count
        webResourceMetadataFiles = $webResourceMetadataFiles.Count
        pluginPackageArtifacts = 1
    }
    exportCoverage = [ordered]@{
        topLevelFolders = @((Get-ChildItem -LiteralPath $ExportFolder -Directory | Sort-Object Name | ForEach-Object Name))
        interpretation = 'Folder inventory describes this Solution export only; it does not establish tenant-wide absence of integrations or resources.'
        noTopLevelFolderFor = @('CloudFlows', 'ConnectionReferences', 'EnvironmentVariableDefinitions')
    }
    releaseDisposition = [ordered]@{
        authoredCanonicalRoots = 20
        generatedPackageAssemblyRoots = 1
        expectedLiveAndExportReleaseRoots = 21
        excludedInactiveProtectCandidateCoreSteps = 50
        excludedSignedRollbackAssembly = 1
        excludedRoots = 51
        temporaryDevCustomApiExcluded = 'os_sr_devcs'
    }
    countSemantics = [ordered]@{
        preCleanupExportRoots = $components.Count
        authoredCanonicalRoots = 20
        generatedReleaseRoots = 1
        expectedLiveAndExportReleaseRoots = 21
        excludedRoots = 51
        canonicalRootsByType = @(
            [ordered]@{ type = 1; typeName = 'Entity'; count = 10 }
            [ordered]@{ type = 9; typeName = 'OptionSet'; count = 2 }
            [ordered]@{ type = 20; typeName = 'SecurityRole'; count = 1 }
            [ordered]@{ type = 61; typeName = 'WebResource'; count = 5 }
            [ordered]@{ type = 62; typeName = 'AppModuleSiteMap'; count = 1 }
            [ordered]@{ type = 80; typeName = 'AppModule'; count = 1 }
        )
        generatedRootsByType = @(
            [ordered]@{
                type = 91
                typeName = 'PluginAssembly'
                count = 1
                disposition = 'unsigned assembly generated from the retained os_sr_cact_pkg PluginPackage'
            }
        )
        excludedRootsByType = @(
            [ordered]@{
                type = 91
                typeName = 'PluginAssembly'
                count = 1
                disposition = 'signed rollback-only assembly root excluded; component remains environment-resident'
            }
            [ordered]@{
                type = 92
                typeName = 'SdkMessageProcessingStep'
                count = 50
                disposition = 'inactive ProtectCandidateCore registrations excluded to prevent reactivation'
            }
        )
        additionalSourceNotRootCounts = [ordered]@{
            customApiFiles = $allApiFiles.Count
            entityMetadataFiles = $entityMetadataFiles.Count
            webResourceMetadataFiles = $webResourceMetadataFiles.Count
            candidateCorePackageArtifacts = 1
        }
        explanation = 'The 72 count is the pre-cleanup unmanaged export RootComponent inventory: 20 authored canonical roots, one package-generated unsigned PluginAssembly root, and 51 excluded roots (one signed rollback assembly plus 50 inactive guard steps). The canonical Solution.xml remains at 20 authored roots; the expected live and managed-export release composition is 21 roots. Custom API, entity, and web-resource metadata files are included source details rather than separate counted roots.'
    }
    requiredCapabilityDisposition = @(
        [ordered]@{
            capability = 'srapp AppModule'
            classification = 'CANONICAL_SOURCE'
            evidence = 'AppModules/srapp/AppModule.xml'
        }
        [ordered]@{
            capability = 'srapp Site Map and navigation'
            classification = 'CANONICAL_SOURCE'
            evidence = 'AppModuleSiteMaps/srapp/AppModuleSiteMap.xml'
        }
        [ordered]@{
            capability = 'Candidate Console HTML, JavaScript, and CSS'
            classification = 'CANONICAL_SOURCE'
            evidence = 'CandidateConsole/WebResources/os_/bso and matching WebResources metadata'
        }
        [ordered]@{
            capability = 'Environment configuration and policy'
            classification = 'DEPLOYMENT_TIME_CONFIGURATION'
            evidence = 'Unconfigured source template and canonical policy are retained; target-bound configuration and its HTML cache token are generated outside the repository from explicit approved target inputs.'
        }
        [ordered]@{
            capability = 'Candidate, Call Log, Candidate Status History, Interview Schedule, Operation Receipt, Position, Candidate Source, TA Directory, Location'
            classification = 'CANONICAL_SOURCE'
            evidence = 'Entity roots and Entity.xml metadata under Entities/'
        }
        [ordered]@{
            capability = 'Choices, relationships, alternate keys, forms, and views'
            classification = 'CANONICAL_SOURCE'
            evidence = 'OptionSets/ and included entity metadata files; checked by source completeness tests.'
        }
        [ordered]@{
            capability = 'BSO security-role definition'
            classification = 'CANONICAL_SOURCE'
            evidence = 'Roles/BSO-RS Support - BSO.xml'
        }
        [ordered]@{
            capability = 'Candidate Core Custom API metadata'
            classification = 'CANONICAL_SOURCE'
            evidence = 'customapis/os_sr_cact and retained Candidate Core API files'
        }
        [ordered]@{
            capability = 'Candidate Core package and package-backed handler reference topology'
            classification = 'CANONICAL_SOURCE'
            evidence = 'pluginpackages/os_sr_cact_pkg/pluginpackage.xml and the pinned unsigned package; Custom API metadata retains the handler binding.'
        }
        [ordered]@{
            capability = 'Signed legacy Candidate Core assembly'
            classification = 'ROLLBACK_ONLY'
            evidence = 'Hash-pinned in ROLLBACK_MANIFEST.json; binary excluded from canonical source.'
        }
        [ordered]@{
            capability = 'Email, Teams, calendar/free-busy, room, SharePoint/CV, and LEGO Careers integrations'
            classification = 'EXTERNAL_DEPENDENCY'
            evidence = 'No integration roots appear in this Solution export; launch inclusion remains a product decision.'
        }
    )
    components = @($components)
}

$fullOutputPath = [IO.Path]::GetFullPath($OutputPath)
$json = ConvertTo-Json -InputObject $inventory -Depth 20
[IO.File]::WriteAllText($fullOutputPath, $json + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
Write-Output "Solution inventory written: $($components.Count) root components."
