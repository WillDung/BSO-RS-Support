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
    param([scriptblock]$Action, [string]$Name, [string]$Pattern)
    $rejected = $false
    try { & $Action | Out-Null } catch { if ($Pattern -and $_.Exception.Message -notmatch $Pattern) { throw }; $rejected = $true }
    Assert-Test $rejected $Name
}

function Connect-AzAccount { throw 'Synthetic tests must not authenticate.' }
function Get-AzAccessToken { throw 'Synthetic tests must not acquire tokens.' }
function Invoke-RestMethod { throw 'Synthetic tests must not access the network.' }
function Get-InteractiveAccessToken { throw 'Synthetic tests must use a refresh callback.' }

. $provisioner -PlanOnly | Out-Null
$expected = @{
    os_sr_ta = @('TA Directory','TA Directories','os_sr_ta_nm','TA Name',200,1)
    os_sr_pos = @('Position','Positions','os_sr_pos_ttl','Position Title',200,0)
    os_sr_csrc = @('Candidate Source','Candidate Sources','os_sr_csrc_nm','Source Name',100,0)
    os_sr_loc = @('Location','Locations','os_sr_loc_nm','Location Name',150,2)
}
foreach ($name in $expected.Keys) {
    $plan = (& $provisioner -TableName $name -PlanOnly) | ConvertFrom-Json
    $row = $expected[$name]
    $primary = $plan.TablePayload.Attributes[0]
    Assert-Test ($plan.TableSchemaName -ceq $name -and $plan.OwnershipType -ceq 'OrganizationOwned') "$name table/ownership"
    Assert-Test ($plan.TableDisplayName -ceq $row[0] -and $plan.DisplayCollectionName -ceq $row[1]) "$name labels"
    Assert-Test ($primary.SchemaName -ceq $row[2] -and $primary.DisplayName.LocalizedLabels[0].Label -ceq $row[3]) "$name primary identity"
    Assert-Test ($primary.FormatName.Value -ceq 'Text' -and $primary.MaxLength -eq $row[4] -and $primary.RequiredLevel.Value -ceq 'ApplicationRequired' -and $primary.IsPrimaryName) "$name primary metadata"
    Assert-Test (@($plan.AdditionalColumnPayloads).Count -eq $row[5] -and $plan.PrimaryGuidLogicalName -ceq ($name+'id')) "$name additional count/GUID"
    if ($name -ne 'os_sr_ta') { Assert-Test ($plan.DisplayCollectionNameStatus -ceq 'Owner-approved Phase 1D-D') "$name approved plural" }
}
$loc = (& $provisioner -TableName os_sr_loc -PlanOnly) | ConvertFrom-Json
$email, $memo = $loc.AdditionalColumnPayloads
Assert-Test ($email.SchemaName -ceq 'os_sr_loc_rmeml' -and $email.DisplayName.LocalizedLabels[0].Label -ceq 'Room/Resource Email' -and $email.FormatName.Value -ceq 'Email' -and $email.MaxLength -eq 254 -and $email.RequiredLevel.Value -ceq 'None') 'Location email exact schema'
Assert-Test ($memo.'@odata.type' -ceq 'Microsoft.Dynamics.CRM.MemoAttributeMetadata' -and $memo.AttributeTypeName.Value -ceq 'MemoType' -and $memo.MaxLength -eq 1000 -and $memo.RequiredLevel.Value -ceq 'None' -and $memo.Format -ceq 'Text' -and $null -eq $memo.FormatName) 'Location memo exact schema'

function New-Fixture {
    param([string]$Name)
    $definition = $script:Definitions[$Name]
    $columns = @($definition.PrimaryName) + @($definition.Columns)
    $attributes = [System.Collections.Generic.List[object]]::new()
    foreach ($column in $columns) {
        $attribute = New-ColumnPayload $column | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        $attribute | Add-Member LogicalName $column.SchemaName
        $attribute | Add-Member MetadataId ('synthetic-'+$column.SchemaName)
        $attribute | Add-Member IsCustomAttribute $true
        $attribute.DisplayName | Add-Member UserLocalizedLabel ([pscustomobject]@{Label=$column.DisplayName})
        $attributes.Add($attribute)
    }
    $attributes.Add([pscustomobject]@{LogicalName=$Name+'id';AttributeType='Uniqueidentifier';IsPrimaryId=$true;IsCustomAttribute=$false})
    $attributes.Add([pscustomobject]@{LogicalName='statecode';AttributeType='State'})
    $attributes.Add([pscustomobject]@{LogicalName='statuscode';AttributeType='Status'})
    [pscustomobject]@{
        LogicalName=$Name;SchemaName=$Name;MetadataId='synthetic-table';OwnershipType='OrganizationOwned'
        PrimaryNameAttribute=$definition.PrimaryName.SchemaName;PrimaryIdAttribute=$Name+'id'
        DisplayName=[pscustomobject]@{UserLocalizedLabel=[pscustomobject]@{Label=$definition.DisplayName}}
        DisplayCollectionName=[pscustomobject]@{UserLocalizedLabel=[pscustomobject]@{Label=$definition.DisplayCollectionName}}
        Attributes=$attributes.ToArray();Keys=@();ManyToOneRelationships=@();OneToManyRelationships=@();ManyToManyRelationships=@()
        IsAuditEnabled=[pscustomobject]@{Value=$false};IsDuplicateDetectionEnabled=[pscustomobject]@{Value=$false}
    }
}
foreach ($name in $expected.Keys) { Assert-TableMetadata (New-Fixture $name); $script:Passed++ }
$fixture=New-Fixture os_sr_ta;$fixture.Attributes[0].MaxLength=201
Assert-Rejected {Assert-TableMetadata $fixture} 'Wrong text length' 'Column metadata mismatch'
$fixture=New-Fixture os_sr_loc;$fixture.Attributes[2].AttributeType='String'
Assert-Rejected {Assert-TableMetadata $fixture} 'Memo-to-string drift' 'Column metadata mismatch'
$fixture=New-Fixture os_sr_pos;$fixture.Keys=@([pscustomobject]@{LogicalName='synthetic-key'})
Assert-Rejected {Assert-TableMetadata $fixture} 'Unexpected key' 'Alternate key'
$fixture=New-Fixture os_sr_csrc;$fixture.ManyToOneRelationships=@([pscustomobject]@{IsCustomRelationship=$true})
Assert-Rejected {Assert-TableMetadata $fixture} 'Unexpected relationship' 'Custom relationship'
$fixture=New-Fixture os_sr_ta;$fixture.Attributes += [pscustomobject]@{LogicalName='os_sr_ta_is_active';IsCustomAttribute=$true}
Assert-Rejected {Assert-TableMetadata $fixture} 'Custom active column' 'Unexpected or missing custom'

$sourceAst=[System.Management.Automation.Language.Parser]::ParseFile($provisioner,[ref]$null,[ref]$null)
$httpModule=New-Module -Name 'SyntheticProvisioningHttpTests' -ArgumentList $sourceAst -ScriptBlock {
    param($sourceAst)
    foreach ($functionName in @('Ensure-DataverseAccessToken','Get-SafeDiagnosticText','Get-SafeResponseHeader','Get-WwwAuthenticateDetails','Invoke-DataverseRequest')) {
        $functionAst=$sourceAst.Find({param($node)$node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $functionName},$true)
        Invoke-Expression $functionAst.Extent.Text
    }
    $script:Refreshes=0;$script:Status=204;$script:Headers=@{};$script:Response=$null;$script:Request=$null
    $script:AccessToken='expired-synthetic';$script:AccessTokenExpiresOn=[DateTimeOffset]::UtcNow.AddMinutes(-1)
    $script:RequestCounts=@{GET=0;POST=0};$script:WriteResults=[System.Collections.Generic.List[object]]::new()
    $script:OrganizationUrl='https://synthetic.crm.dynamics.com/';$script:ApiRoot=$script:OrganizationUrl+'api/data/v9.2/'
    $script:TableName='os_sr_ta';$script:Apply=$true;$script:PlanOnly=$false;$script:WritesAllowed=$true;$script:Definition=@{Columns=@()}
    function Invoke-RestMethod {
        param($Method,$Uri,$Headers,$SkipHeaderValidation,$MaximumRedirection,$SkipHttpErrorCheck,$StatusCodeVariable,$ResponseHeadersVariable,$TimeoutSec,$ErrorAction,$ContentType,$Body)
        $script:Request=[ordered]@{Method=$Method;Uri=[string]$Uri;HasAuthorization=$Headers.ContainsKey('Authorization');Bearer=([string]$Headers.Authorization).StartsWith('Bearer ');Solution=$Headers['MSCRM.SolutionUniqueName'];ContentType=$ContentType;Redirects=$MaximumRedirection;SkipHttpErrorCheck=$SkipHttpErrorCheck;Body=(ConvertFrom-Json $Body)}
        Set-Variable -Name $StatusCodeVariable -Value $script:Status -Scope 1
        Set-Variable -Name $ResponseHeadersVariable -Value $script:Headers -Scope 1
        $script:Response
    }
    function Test-SyntheticHttpChecks {
        Ensure-DataverseAccessToken -RefreshAction {$script:Refreshes++;$script:AccessToken='fresh-synthetic';$script:AccessTokenIssuedAt=[DateTimeOffset]::UtcNow;$script:AccessTokenExpiresOn=[DateTimeOffset]::UtcNow.AddHours(1)}
        $table=[ordered]@{SchemaName='os_sr_ta'}
        Invoke-DataverseRequest -Method POST -Path 'EntityDefinitions' -Body $table -WithSolutionHeader | Out-Null
        $success=$script:Request
        $script:Status=401
        $script:Headers=@{'WWW-Authenticate'='Bearer error="invalid_token", error_description="do not expose"';'x-ms-service-request-id'='synthetic-request';'x-ms-correlation-request-id'='synthetic-correlation'}
        $script:Response=[pscustomobject]@{error=[pscustomobject]@{code='synthetic-code';message='test@example.invalid auth failure'}}
        $failed=$false;try {Invoke-DataverseRequest -Method POST -Path 'EntityDefinitions' -Body $table -WithSolutionHeader | Out-Null}catch{$failed=$true}
        $failure=$script:LastHttpFailure
        $script:Status=403
        $script:Headers=@{}
        $script:Response=[pscustomobject]@{error=[pscustomobject]@{code='forbidden';message='privilege denied'}}
        try {Invoke-DataverseRequest -Method POST -Path 'EntityDefinitions' -Body $table -WithSolutionHeader | Out-Null}catch{}
        [pscustomobject]@{Refreshes=$script:Refreshes;SuccessRequest=$success;Failed=$failed;Failure=$failure;Failure403=$script:LastHttpFailure;PostCount=$script:RequestCounts.POST}
    }
    Export-ModuleMember -Function Test-SyntheticHttpChecks
}
Import-Module $httpModule -Force
$http=Test-SyntheticHttpChecks
Assert-Test ($http.Refreshes -eq 1) 'Expired token refresh callback called once'
Assert-Test ($http.SuccessRequest.HasAuthorization -and $http.SuccessRequest.Bearer) 'Bearer header present'
Assert-Test ($http.SuccessRequest.Solution -ceq 'os_sr_bso_rs_support') 'Solution header present'
Assert-Test ($http.SuccessRequest.ContentType -ceq 'application/json; charset=utf-8' -and $http.SuccessRequest.Body.SchemaName -ceq 'os_sr_ta') 'POST construction and content type'
Assert-Test ($http.SuccessRequest.Redirects -eq 0 -and $http.SuccessRequest.SkipHttpErrorCheck) 'Redirect disabled and status capture enabled'
Assert-Test ($http.Failed -and $http.Failure.StatusCode -eq 401 -and $http.Failure.Classification -ceq 'Authentication/token failure') '401 safely classified'
Assert-Test ($http.Failure.WwwAuthenticateScheme -ceq 'Bearer' -and $http.Failure.WwwAuthenticateError -ceq 'invalid_token') 'WWW-Authenticate parsed safely'
Assert-Test ($http.Failure.RequestId -ceq 'synthetic-request' -and $http.Failure.CorrelationId -ceq 'synthetic-correlation') 'Request identifiers captured'
Assert-Test ($http.Failure.DataverseErrorMessage -notmatch 'test@example.invalid|do not expose') 'Sensitive 401 fields redacted'
Assert-Test ($http.Failure.TokenSecondsRemainingAtRequest -gt 0) 'Request-time token expiry captured'
Assert-Test ($http.Failure403.StatusCode -eq 403 -and $http.Failure403.Classification -ceq 'Permission/privilege failure') '403 permission classification'
Assert-Test ($http.PostCount -eq 3) '401 and 403 are not retried'
Remove-Module $httpModule
Write-Output "PASS: $script:Passed synthetic provisioning assertions; no authentication, API calls, or Apply invocation."
