#requires -Version 7.4
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\BsoRsSolutionMembership.psm1') -Force
$passed = 0
function Assert-Test([bool]$Condition, [string]$Name) {
    if (-not $Condition) { throw "FAIL: $Name" }
    $script:passed++
}
function Assert-Rejected([scriptblock]$Action, [string]$Name) {
    $rejected = $false
    try { & $Action | Out-Null } catch { $rejected = $true }
    Assert-Test $rejected $Name
}
$temporary = Join-Path ([IO.Path]::GetTempPath()) "bso-rs-membership-$([Guid]::NewGuid().ToString('N'))"
$solutionId = '11111111-1111-4111-8111-111111111111'
$entityId = '22222222-2222-4222-8222-222222222222'
$attributeId = '33333333-3333-4333-8333-333333333333'
$relationshipId = '44444444-4444-4444-8444-444444444444'
$root = [pscustomobject]@{ _solutionid_value=$solutionId; componenttype=1; objectid=$entityId; rootcomponentbehavior=0 }
$attribute = [pscustomobject]@{ MetadataId=$attributeId; LogicalName='os_sr_avq_ta'; EntityLogicalName='os_sr_avq' }
$relationship = [pscustomobject]@{
    MetadataId=$relationshipId; SchemaName='os_sr_ta_avq'; ReferencingEntity='os_sr_avq'
    ReferencedEntity='os_sr_ta'; ReferencingAttribute='os_sr_avq_ta'
}
$common = @{
    SolutionId=$solutionId; SolutionUniqueName='synthetic_solution'; SolutionComponents=@($root)
    EntityName='os_sr_avq'; EntityMetadataId=$entityId; UnpackedSolutionPath=$temporary
}
$attributeArgs = @{ Kind='Attribute'; ComponentName='os_sr_avq_ta'; Metadata=$attribute }
$relationshipArgs = @{
    Kind='Relationship'; ComponentName='os_sr_ta_avq'; Metadata=$relationship
    ReferencedEntity='os_sr_ta'; ReferencingAttribute='os_sr_avq_ta'
}
function Write-Fixture([string]$Path, [string]$Text) {
    [IO.Directory]::CreateDirectory((Split-Path $Path -Parent)) | Out-Null
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
}
$solutionXml = '<ImportExportXml><SolutionManifest><UniqueName>synthetic_solution</UniqueName><RootComponents><RootComponent type="1" schemaName="os_sr_avq" behavior="0" /></RootComponents></SolutionManifest></ImportExportXml>'
$entityXml = '<Entity><Name>os_sr_avq</Name><EntityInfo><entity Name="os_sr_avq"><attributes><attribute PhysicalName="os_sr_avq_ta"><LogicalName>os_sr_avq_ta</LogicalName></attribute></attributes></entity></EntityInfo></Entity>'
$relationshipXml = '<EntityRelationships><EntityRelationship Name="os_sr_ta_avq"><EntityRelationshipType>OneToMany</EntityRelationshipType><ReferencingEntityName>os_sr_avq</ReferencingEntityName><ReferencedEntityName>os_sr_ta</ReferencedEntityName><ReferencingAttributeName>os_sr_avq_ta</ReferencingAttributeName></EntityRelationship></EntityRelationships>'
try {
    Write-Fixture "$temporary\Other\Solution.xml" $solutionXml
    Write-Fixture "$temporary\Entities\os_sr_avq\Entity.xml" $entityXml
    Write-Fixture "$temporary\Other\Relationships.xml" '<EntityRelationships><EntityRelationship Name="os_sr_ta_avq" /></EntityRelationships>'
    Write-Fixture "$temporary\Other\Relationships\os_sr_ta.xml" $relationshipXml
    Assert-Test ((Assert-BsoRsSubcomponentMembership @common @attributeArgs).Evidence -ceq 'IncludeSubcomponentsMetadataAndExport') 'Lookup accepted without an explicit child row'
    Assert-Test ((Assert-BsoRsSubcomponentMembership @common @relationshipArgs).Evidence -ceq 'IncludeSubcomponentsMetadataAndExport') 'Regression: relationship accepted by complete inherited export evidence'
    foreach ($behavior in @(1,2,$null)) {
        $root.rootcomponentbehavior=$behavior
        Assert-Rejected { Assert-BsoRsSubcomponentMembership @common @relationshipArgs } "Inherited proof rejects root behavior '$behavior'"
    }
    $root.rootcomponentbehavior=0
    $common.SolutionComponents=@()
    Assert-Rejected { Assert-BsoRsSubcomponentMembership @common @relationshipArgs } 'Missing owning root rejects'
    $common.SolutionComponents=@($root)
    $root._solutionid_value='55555555-5555-4555-8555-555555555555'
    Assert-Rejected { Assert-BsoRsSubcomponentMembership @common @relationshipArgs } 'Root in a different Solution rejects'
    $root._solutionid_value=$solutionId
    $relationship.ReferencingEntity='os_sr_other'
    Assert-Rejected { Assert-BsoRsSubcomponentMembership @common @relationshipArgs } 'Mismatched relationship owner rejects'
    $relationship.ReferencingEntity='os_sr_avq'
    $attribute.EntityLogicalName='os_sr_other'
    Assert-Rejected { Assert-BsoRsSubcomponentMembership @common @attributeArgs } 'Mismatched attribute owner rejects'
    $attribute.EntityLogicalName='os_sr_avq'
    $relationship.MetadataId=''
    Assert-Rejected { Assert-BsoRsSubcomponentMembership @common @relationshipArgs } 'Missing metadata identity rejects'
    $relationship.MetadataId=$relationshipId
    foreach ($behavior in @(1,2)) {
        Write-Fixture "$temporary\Other\Solution.xml" ($solutionXml.Replace('behavior="0"', "behavior=`"$behavior`""))
        Assert-Rejected { Assert-BsoRsSubcomponentMembership @common @relationshipArgs } "Exported shell/exclusion behavior $behavior rejects"
    }
    Write-Fixture "$temporary\Other\Solution.xml" ($solutionXml.Replace('synthetic_solution','different_solution'))
    Assert-Rejected { Assert-BsoRsSubcomponentMembership @common @relationshipArgs } 'Wrong exported Solution rejects'
    Write-Fixture "$temporary\Other\Solution.xml" $solutionXml
    Write-Fixture "$temporary\Entities\os_sr_avq\Entity.xml" ($entityXml.Replace('<LogicalName>os_sr_avq_ta</LogicalName>','<LogicalName>os_sr_other</LogicalName>'))
    Assert-Rejected { Assert-BsoRsSubcomponentMembership @common @attributeArgs } 'Missing exact exported lookup rejects'
    Write-Fixture "$temporary\Entities\os_sr_avq\Entity.xml" $entityXml
    Write-Fixture "$temporary\Other\Relationships\os_sr_ta.xml" ($relationshipXml.Replace('<ReferencingEntityName>os_sr_avq</ReferencingEntityName>','<ReferencingEntityName>os_sr_other</ReferencingEntityName>'))
    Assert-Rejected { Assert-BsoRsSubcomponentMembership @common @relationshipArgs } 'A relationship name alone does not prove correct ownership'
    Write-Fixture "$temporary\Other\Relationships\os_sr_ta.xml" $relationshipXml
    Write-Fixture "$temporary\Other\Relationships.xml" '<EntityRelationships />'
    Assert-Rejected { Assert-BsoRsSubcomponentMembership @common @relationshipArgs } 'Missing exported relationship index rejects'
    $explicit = [pscustomobject]@{ _solutionid_value=$solutionId; componenttype=10; objectid=$relationshipId; rootcomponentbehavior=0 }
    $common.SolutionComponents=@($explicit)
    $common.UnpackedSolutionPath=Join-Path $temporary 'not-present'
    Assert-Test ((Assert-BsoRsSubcomponentMembership @common @relationshipArgs).Evidence -ceq 'ExplicitSolutionComponent') 'Exact explicit membership is an independent proof'
    $common.SolutionComponents=@($explicit,$explicit)
    Assert-Rejected { Assert-BsoRsSubcomponentMembership @common @relationshipArgs } 'Duplicate explicit membership rejects'
    $explicit._solutionid_value='55555555-5555-4555-8555-555555555555'
    $common.SolutionComponents=@($explicit)
    Assert-Rejected { Assert-BsoRsSubcomponentMembership @common @relationshipArgs } 'Explicit membership from another Solution rejects'
} finally {
    if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Recurse -Force }
}
Write-Host "Solution subcomponent membership checks passed: $passed"
