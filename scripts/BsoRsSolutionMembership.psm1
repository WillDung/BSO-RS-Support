#requires -Version 7.4
Set-StrictMode -Version Latest

function Assert-BsoRsSubcomponentMembership {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][Guid]$SolutionId,
        [Parameter(Mandatory)][ValidatePattern('^[a-zA-Z0-9_]+$')][string]$SolutionUniqueName,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$SolutionComponents,
        [Parameter(Mandatory)][ValidatePattern('^[a-zA-Z0-9_]+$')][string]$EntityName,
        [Parameter(Mandatory)][Guid]$EntityMetadataId,
        [Parameter(Mandatory)][ValidateSet('Attribute', 'Relationship')][string]$Kind,
        [Parameter(Mandatory)][ValidatePattern('^[a-zA-Z0-9_]+$')][string]$ComponentName,
        [Parameter(Mandatory)][object]$Metadata,
        [Parameter(Mandatory)][string]$UnpackedSolutionPath,
        [ValidatePattern('^[a-zA-Z0-9_]+$')][string]$ReferencedEntity,
        [ValidatePattern('^[a-zA-Z0-9_]+$')][string]$ReferencingAttribute
    )

    $componentId = [Guid]::Empty
    if (-not [Guid]::TryParse([string]$Metadata.MetadataId, [ref]$componentId) -or
        $componentId -eq [Guid]::Empty) {
        throw "SUBCOMPONENT_METADATA_ID_INVALID:$ComponentName"
    }
    if ($Kind -ceq 'Attribute') {
        if ($Metadata.LogicalName -cne $ComponentName -or $Metadata.EntityLogicalName -cne $EntityName) {
            throw "SUBCOMPONENT_METADATA_MISMATCH:$ComponentName"
        }
        $componentType = 2
    } else {
        if (-not $ReferencedEntity -or -not $ReferencingAttribute -or
            $Metadata.SchemaName -cne $ComponentName -or
            $Metadata.ReferencingEntity -cne $EntityName -or
            $Metadata.ReferencedEntity -cne $ReferencedEntity -or
            $Metadata.ReferencingAttribute -cne $ReferencingAttribute) {
            throw "SUBCOMPONENT_METADATA_MISMATCH:$ComponentName"
        }
        $componentType = 10
    }

    $members = @($SolutionComponents | Where-Object {
        [string]$_._solutionid_value -ieq $SolutionId.ToString()
    })
    $explicit = @($members | Where-Object {
        $_.componenttype -eq $componentType -and [string]$_.objectid -ieq $componentId.ToString()
    })
    if ($explicit.Count -gt 1) { throw "SUBCOMPONENT_EXPLICIT_MEMBERSHIP_AMBIGUOUS:$ComponentName" }
    if ($explicit.Count -eq 1) {
        return [pscustomobject]@{ Component = $ComponentName; Evidence = 'ExplicitSolutionComponent' }
    }

    $roots = @($members | Where-Object {
        $_.componenttype -eq 1 -and [string]$_.objectid -ieq $EntityMetadataId.ToString()
    })
    if ($roots.Count -ne 1 -or [string]$roots[0].rootcomponentbehavior -cne '0') {
        throw "SUBCOMPONENT_INCLUDE_ROOT_REQUIRED:$ComponentName"
    }
    [xml]$solution = [IO.File]::ReadAllText((Join-Path $UnpackedSolutionPath 'Other\Solution.xml'))
    $manifest = $solution.ImportExportXml.SolutionManifest
    $exportRoots = @($manifest.RootComponents.RootComponent | Where-Object {
        $_.type -ceq '1' -and $_.schemaName -ceq $EntityName -and $_.behavior -ceq '0'
    })
    if ($manifest.UniqueName -cne $SolutionUniqueName -or $exportRoots.Count -ne 1) {
        throw "SUBCOMPONENT_EXPORT_SOLUTION_MISMATCH:$ComponentName"
    }
    [xml]$entity = [IO.File]::ReadAllText((Join-Path $UnpackedSolutionPath "Entities\$EntityName\Entity.xml"))
    if ($entity.SelectSingleNode('/Entity/Name').InnerText -cne $EntityName -or
        $entity.Entity.EntityInfo.entity.Name -cne $EntityName) {
        throw "SUBCOMPONENT_EXPORT_ENTITY_MISMATCH:$ComponentName"
    }
    $attributeName = if ($Kind -ceq 'Attribute') { $ComponentName } else { $ReferencingAttribute }
    $exportAttributes = @($entity.Entity.EntityInfo.entity.attributes.attribute | Where-Object {
        $_.LogicalName -ceq $attributeName
    })
    if ($exportAttributes.Count -ne 1) { throw "SUBCOMPONENT_EXPORT_ATTRIBUTE_MISSING:$attributeName" }

    if ($Kind -ceq 'Relationship') {
        [xml]$index = [IO.File]::ReadAllText((Join-Path $UnpackedSolutionPath 'Other\Relationships.xml'))
        $indexed = @($index.EntityRelationships.EntityRelationship | Where-Object Name -CEQ $ComponentName)
        [xml]$details = [IO.File]::ReadAllText(
            (Join-Path $UnpackedSolutionPath "Other\Relationships\$ReferencedEntity.xml"))
        $exportRelationships = @($details.EntityRelationships.EntityRelationship | Where-Object {
            $_.Name -ceq $ComponentName -and $_.ReferencingEntityName -ceq $EntityName -and
            $_.ReferencedEntityName -ceq $ReferencedEntity -and
            [string]$_.ReferencingAttributeName -ieq $ReferencingAttribute -and
            $_.EntityRelationshipType -ceq 'OneToMany'
        })
        if ($indexed.Count -ne 1 -or $exportRelationships.Count -ne 1) {
            throw "SUBCOMPONENT_EXPORT_RELATIONSHIP_MISMATCH:$ComponentName"
        }
    }
    [pscustomobject]@{ Component = $ComponentName; Evidence = 'IncludeSubcomponentsMetadataAndExport' }
}

Export-ModuleMember -Function Assert-BsoRsSubcomponentMembership
