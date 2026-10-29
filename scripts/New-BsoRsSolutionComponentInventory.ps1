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
                $disposition = 'PACKAGE_BACKED_ASSEMBLY_MANAGED_BY_EXISTING_PACKAGE_UPDATER'
                $sourceMapping = 'pluginpackages/os_sr_cact_pkg/pluginpackage.xml; package/os_sr_cact_pkg.nupkg'
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
$inventory = [ordered]@{
    provenance = 'Unmanaged PAC export unpacked 2026-10-29; 72 root components; target identifiers excluded.'
    rootComponentCount = $components.Count
    countsByType = $counts
    releaseDisposition = [ordered]@{
        retainedReleaseRoots = 20
        excludedInactiveProtectCandidateCoreSteps = 50
        excludedSignedRollbackAssembly = 1
        packageBackedAssemblyManagedSeparately = 1
        temporaryDevCustomApiExcluded = 'os_sr_devcs'
    }
    components = @($components)
}

$fullOutputPath = [IO.Path]::GetFullPath($OutputPath)
$json = ConvertTo-Json -InputObject $inventory -Depth 20
[IO.File]::WriteAllText($fullOutputPath, $json + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
Write-Output "Solution inventory written: $($components.Count) root components."
