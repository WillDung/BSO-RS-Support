#requires -Version 7.4
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$provisioner = Join-Path $PSScriptRoot '../scripts/Provision-BsoRsTaTable.ps1'
$script:Passed = 0

function Assert-Test {
    param([bool]$Condition, [string]$Name)
    if (-not $Condition) { throw "FAIL: $Name" }
    $script:Passed++
}

function Assert-Rejected {
    param([scriptblock]$Action, [string]$Name, [string]$MessagePattern)
    $rejected = $false
    try { & $Action | Out-Null }
    catch {
        if ($MessagePattern -and $_.Exception.Message -notmatch $MessagePattern) { throw }
        $rejected = $true
    }
    Assert-Test $rejected $Name
}

function Connect-AzAccount { throw 'Tests must not authenticate.' }
function Get-AzAccessToken { throw 'Tests must not acquire tokens.' }
function Invoke-RestMethod { throw 'Tests must not access the network.' }

. $provisioner -PlanOnly | Out-Null

$expectedNames = @{
    os_sr_ta = @('TA Directory', 'TA Directories', 'os_sr_ta_nm', 'TA Name', 200, 1)
    os_sr_pos = @('Position', 'Positions', 'os_sr_pos_ttl', 'Position Title', 200, 0)
    os_sr_csrc = @('Candidate Source', 'Candidate Sources', 'os_sr_csrc_nm', 'Source Name', 100, 0)
    os_sr_loc = @('Location', 'Locations', 'os_sr_loc_nm', 'Location Name', 150, 2)
}
foreach ($logicalName in @('os_sr_ta', 'os_sr_pos', 'os_sr_csrc', 'os_sr_loc')) {
    $plan = (& $provisioner -TableName $logicalName -PlanOnly) | ConvertFrom-Json
    $expected = $expectedNames[$logicalName]
    $primary = $plan.TablePayload.Attributes[0]
    Assert-Test ($plan.Mode -like 'PlanOnly*' -and $plan.TableSchemaName -ceq $logicalName) "$logicalName offline mode/name"
    Assert-Test ($plan.TableDisplayName -ceq $expected[0] -and $plan.DisplayCollectionName -ceq $expected[1]) "$logicalName labels"
    Assert-Test ($plan.OwnershipType -ceq 'OrganizationOwned') "$logicalName ownership"
    Assert-Test ($primary.SchemaName -ceq $expected[2] -and $primary.DisplayName.LocalizedLabels[0].Label -ceq $expected[3]) "$logicalName primary name"
    Assert-Test ($primary.AttributeType -ceq 'String' -and $primary.FormatName.Value -ceq 'Text' -and $primary.MaxLength -eq $expected[4]) "$logicalName primary type/length"
    Assert-Test ($primary.RequiredLevel.Value -ceq 'ApplicationRequired' -and $primary.IsPrimaryName -eq $true) "$logicalName primary flags"
    Assert-Test (@($plan.AdditionalColumnPayloads).Count -eq $expected[5]) "$logicalName exact extra column count"
    Assert-Test ($plan.PrimaryGuidLogicalName -ceq ($logicalName + 'id')) "$logicalName generated GUID name"
    if ($logicalName -cne 'os_sr_ta') {
        Assert-Test ($plan.DisplayCollectionNameStatus -like 'Pending owner approval*') "$logicalName plural pending"
    }
}
$location = (& $provisioner -TableName os_sr_loc -PlanOnly) | ConvertFrom-Json
$email = $location.AdditionalColumnPayloads[0]
$memo = $location.AdditionalColumnPayloads[1]
Assert-Test ($email.SchemaName -ceq 'os_sr_loc_rmeml' -and $email.DisplayName.LocalizedLabels[0].Label -ceq 'Room/Resource Email') 'Schema-authoritative Location email label'
Assert-Test ($email.AttributeType -ceq 'String' -and $email.FormatName.Value -ceq 'Email' -and $email.MaxLength -eq 254 -and $email.RequiredLevel.Value -ceq 'None') 'Optional Location Email(254)'
Assert-Test ($memo.SchemaName -ceq 'os_sr_loc_det' -and $memo.DisplayName.LocalizedLabels[0].Label -ceq 'Location Details') 'Location details identity'
Assert-Test ($memo.'@odata.type' -ceq 'Microsoft.Dynamics.CRM.MemoAttributeMetadata' -and $memo.AttributeTypeName.Value -ceq 'MemoType' -and $memo.MaxLength -eq 1000 -and $memo.RequiredLevel.Value -ceq 'None' -and $memo.Format -ceq 'Text') 'Optional Location Memo(1000)'
Assert-Test ($null -eq $memo.FormatName) 'Memo does not use String FormatName'

function New-SyntheticMetadata {
    param([string]$LogicalName)
    $definition = $script:Definitions[$LogicalName]
    $attributes = @()
    foreach ($column in @($definition.PrimaryName) + @($definition.Columns)) {
        $attribute = New-ColumnPayload $column | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        $attribute | Add-Member -NotePropertyName LogicalName -NotePropertyValue $column.SchemaName
        $attribute | Add-Member -NotePropertyName MetadataId -NotePropertyValue ('synthetic-' + $column.SchemaName)
        $attribute | Add-Member -NotePropertyName IsCustomAttribute -NotePropertyValue $true
        $attribute.DisplayName | Add-Member -NotePropertyName UserLocalizedLabel -NotePropertyValue ([pscustomobject]@{ Label = $column.DisplayName })
        $attributes += $attribute
    }
    $attributes += [pscustomobject]@{ LogicalName = $LogicalName + 'id'; AttributeType = 'Uniqueidentifier'; IsPrimaryId = $true; IsCustomAttribute = $false }
    $attributes += [pscustomobject]@{ LogicalName = 'statecode'; AttributeType = 'State' }
    $attributes += [pscustomobject]@{ LogicalName = 'statuscode'; AttributeType = 'Status' }
    [pscustomobject]@{
        LogicalName = $LogicalName; SchemaName = $LogicalName; MetadataId = 'synthetic-table'
        OwnershipType = 'OrganizationOwned'; PrimaryNameAttribute = $definition.PrimaryName.SchemaName
        PrimaryIdAttribute = $LogicalName + 'id'
        DisplayName = [pscustomobject]@{ UserLocalizedLabel = [pscustomobject]@{ Label = $definition.DisplayName } }
        DisplayCollectionName = [pscustomobject]@{ UserLocalizedLabel = [pscustomobject]@{ Label = $definition.DisplayCollectionName } }
        Attributes = $attributes; Keys = @()
        ManyToOneRelationships = @(); OneToManyRelationships = @(); ManyToManyRelationships = @()
        IsAuditEnabled = [pscustomobject]@{ Value = $false }
        IsDuplicateDetectionEnabled = [pscustomobject]@{ Value = $false }
    }
}

foreach ($logicalName in $expectedNames.Keys) {
    Assert-TableMetadata (New-SyntheticMetadata $logicalName)
    $script:Passed++
}
$fixture = New-SyntheticMetadata 'os_sr_ta'
$fixture.Attributes[0].MaxLength = 201
Assert-Rejected { Assert-TableMetadata $fixture } 'Wrong primary length rejected' 'Column metadata mismatch'
$fixture = New-SyntheticMetadata 'os_sr_ta'
$fixture.PrimaryIdAttribute = 'synthetic_wrongid'
Assert-Rejected { Assert-TableMetadata $fixture } 'Wrong primary GUID name rejected' 'Table schema'
$fixture = New-SyntheticMetadata 'os_sr_ta'
$fixture.Attributes += [pscustomobject]@{ LogicalName = 'os_sr_ta_is_active'; IsCustomAttribute = $true }
Assert-Rejected { Assert-TableMetadata $fixture } 'Unexpected active flag rejected' 'Unexpected or missing custom'
$fixture = New-SyntheticMetadata 'os_sr_loc'
$fixture.Attributes[1].RequiredLevel.Value = 'ApplicationRequired'
Assert-Rejected { Assert-TableMetadata $fixture } 'Wrong email requiredness rejected' 'Column metadata mismatch'
$fixture = New-SyntheticMetadata 'os_sr_loc'
$fixture.Attributes[2].AttributeType = 'String'
Assert-Rejected { Assert-TableMetadata $fixture } 'String substituted for Memo rejected' 'Column metadata mismatch'
$fixture = New-SyntheticMetadata 'os_sr_pos'
$fixture.Keys = @([pscustomobject]@{ LogicalName = 'synthetic_key' })
Assert-Rejected { Assert-TableMetadata $fixture } 'Alternate key rejected' 'Alternate key'
$fixture = New-SyntheticMetadata 'os_sr_csrc'
$fixture.ManyToOneRelationships = @([pscustomobject]@{ IsCustomRelationship = $true })
Assert-Rejected { Assert-TableMetadata $fixture } 'Custom relationship rejected' 'Custom relationship'
$fixture = New-SyntheticMetadata 'os_sr_ta'
$fixture.IsAuditEnabled.Value = $true
Assert-Rejected { Assert-TableMetadata $fixture } 'Unexpected audit activation rejected' 'Audit or duplicate'

& {
    function Get-SolutionMembership {
        param($SolutionId, $ObjectId, $ComponentType)
        if ($ComponentType -eq 1) {
            for ($index = 0; $index -lt $rootCount; $index++) { [pscustomobject]@{ rootcomponentbehavior = $rootBehavior } }
        }
        elseif ($explicitColumns -and $ObjectId -ne $missingColumnId) { [pscustomobject]@{ objectid = $ObjectId } }
    }
    foreach ($logicalName in $expectedNames.Keys) {
        $metadata = New-SyntheticMetadata $logicalName
        $rootCount = 1; $rootBehavior = 0; $explicitColumns = $false; $missingColumnId = ''
        Assert-SolutionMembership -SolutionId 'synthetic-solution' -Metadata $metadata
        $script:Passed++
        $rootBehavior = 1; $explicitColumns = $true
        Assert-SolutionMembership -SolutionId 'synthetic-solution' -Metadata $metadata
        $script:Passed++
        $explicitColumns = $false
        Assert-Rejected { Assert-SolutionMembership -SolutionId 'synthetic-solution' -Metadata $metadata } "$logicalName excluded columns rejected" 'does not include'
        $rootBehavior = 2
        Assert-Rejected { Assert-SolutionMembership -SolutionId 'synthetic-solution' -Metadata $metadata } "$logicalName shell-only rejected" 'does not include'
        $rootBehavior = $null
        Assert-Rejected { Assert-SolutionMembership -SolutionId 'synthetic-solution' -Metadata $metadata } "$logicalName null behavior rejected" 'does not include'
        $rootBehavior = 0; $rootCount = 0
        Assert-Rejected { Assert-SolutionMembership -SolutionId 'synthetic-solution' -Metadata $metadata } "$logicalName missing root rejected" 'Table Solution membership'
        $rootCount = 2
        Assert-Rejected { Assert-SolutionMembership -SolutionId 'synthetic-solution' -Metadata $metadata } "$logicalName duplicate root rejected" 'Table Solution membership'
        $rootCount = 1; $rootBehavior = 1; $explicitColumns = $true
        $primaryName = $script:Definitions[$logicalName].PrimaryName.SchemaName
        $missingColumnId = @($metadata.Attributes | Where-Object { $_.LogicalName -ceq $primaryName })[0].MetadataId
        Assert-Rejected { Assert-SolutionMembership -SolutionId 'synthetic-solution' -Metadata $metadata } "$logicalName missing explicit column rejected" 'does not include'
    }
}

$OrganizationUrl = 'https://synthetic.crm.dynamics.com/'
$script:ApiRoot = $OrganizationUrl + 'api/data/v9.2/'
$Apply = $false; $PlanOnly = $false; $script:WritesAllowed = $false
Assert-Rejected { Invoke-DataverseRequest -Method POST -Path 'EntityDefinitions' -Body @{} } 'DryRun POST blocked before transport' 'POST blocked'
Assert-Rejected { Invoke-DataverseRequest -Method GET -Path 'https://other.invalid/api/data/v9.2/EntityDefinitions' } 'Cross-origin read blocked' 'outside the verified'
Assert-Rejected { Invoke-DataverseRequest -Method GET -Path 'accounts' } 'Business row read blocked' 'only identity'
Assert-Rejected { Invoke-DataverseRequest -Method GET -Path 'http://synthetic.crm.dynamics.com/api/data/v9.2/EntityDefinitions' } 'HTTP read blocked' 'outside the verified'

& {
    $calls = [System.Collections.Generic.List[string]]::new()
    function Invoke-RestMethod {
        param($Method, $Uri, $Headers, $SkipHeaderValidation, $MaximumRedirection, $TimeoutSec, $ErrorAction)
        $calls.Add([string]$Uri)
        if ($calls.Count -eq 1) {
            return [pscustomobject]@{ value = @([pscustomobject]@{ LogicalName = 'synthetic_first' }); '@odata.nextLink' = $nextLink }
        }
        [pscustomobject]@{ value = @([pscustomobject]@{ LogicalName = 'synthetic_second' }) }
    }
    $nextLink = $script:ApiRoot + 'EntityDefinitions?$skiptoken=synthetic'
    $items = @(Get-ODataList -Path 'EntityDefinitions?$select=LogicalName')
    Assert-Test ($items.Count -eq 2 -and $calls.Count -eq 2) 'Same-origin OData pagination followed'
    $calls.Clear()
    $nextLink = 'https://other.invalid/api/data/v9.2/EntityDefinitions'
    Assert-Rejected { Get-ODataList -Path 'EntityDefinitions?$select=LogicalName' } 'Foreign continuation rejected' 'outside the verified'
    Assert-Test ($calls.Count -eq 1) 'Foreign continuation never reaches transport'
}

$payload = New-SchemaPayloads
$payload.Table['Keys'] = @()
Assert-Rejected { Assert-SchemaPayloads $payload } 'Unintended payload key property rejected' 'Unintended table payload'
Write-Output "PASS: $script:Passed provisioning assertions; synthetic metadata only; no authentication, API calls, or Apply invocation."