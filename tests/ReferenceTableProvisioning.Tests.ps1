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

function Get-UtcTimestampFromJson {
    param([Parameter(Mandatory = $true)][string]$Json)
    $document = [System.Text.Json.JsonDocument]::Parse($Json)
    try {
        $value = $document.RootElement.GetProperty('Details').GetProperty('HttpFailure').GetProperty('TimestampUtc').GetString()
        $timestamp = [DateTimeOffset]::ParseExact(
            $value,
            'o',
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::None
        )
        if ($timestamp.Offset -ne [TimeSpan]::Zero) { throw 'TimestampUtc must have a zero UTC offset.' }
        $timestamp
    }
    finally { $document.Dispose() }
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
$positionPlan = (& $provisioner -TableName os_sr_pos -PlanOnly) | ConvertFrom-Json
$positionPayload = $positionPlan.TablePayload
$positionPayloadJson = ConvertTo-Json -InputObject $positionPayload -Depth 40 -Compress
$positionPayloadHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($positionPayloadJson))).ToLowerInvariant()
Assert-Test ($positionPayloadHash -ceq '0f7372eeb66c0214ae08ed0dc74f82c981cc4cd73baa9156f16d6e1bd1f48e80') 'Position PlanOnly payload matches the recovery SHA-256 fingerprint'
Assert-Test ($positionPlan.Mode -like 'PlanOnly*' -and $positionPlan.OwnershipType -ceq 'OrganizationOwned' -and $positionPlan.TableDisplayName -ceq 'Position' -and $positionPlan.DisplayCollectionName -ceq 'Positions' -and @($positionPlan.AdditionalColumnPayloads).Count -eq 0 -and $positionPlan.AlternateKeys -ceq 'None' -and $positionPlan.DuplicateDetection -ceq 'None' -and $positionPlan.DataRowOperations -match 'no data-table requests') 'Position recovery plan excludes extra columns, keys, relationships and business rows'
$candidateSourcePlan = (& $provisioner -TableName os_sr_csrc -PlanOnly) | ConvertFrom-Json
$candidateSourcePayloadJson = ConvertTo-Json -InputObject $candidateSourcePlan.TablePayload -Depth 40 -Compress
$candidateSourcePayloadHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($candidateSourcePayloadJson))).ToLowerInvariant()
Assert-Test ($candidateSourcePayloadHash -ceq '867803e7533bfb053c70b951edc47cb4475b5f0183852dcb850b88b317c08f16') 'Candidate Source PlanOnly payload matches the approved SHA-256 fingerprint'
Assert-Test ($candidateSourcePlan.TableDisplayName -ceq 'Candidate Source' -and $candidateSourcePlan.DisplayCollectionName -ceq 'Candidate Sources' -and $candidateSourcePlan.OwnershipType -ceq 'OrganizationOwned' -and $candidateSourcePlan.PrimaryNameSchemaName -ceq 'os_sr_csrc_nm' -and @($candidateSourcePlan.AdditionalColumnPayloads).Count -eq 0 -and $candidateSourcePlan.AlternateKeys -ceq 'None') 'Candidate Source payload remains single-column and OrganizationOwned'
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
$httpModule=New-Module -Name 'SyntheticProvisioningHttpTests' -ArgumentList @($sourceAst,$candidateSourcePlan.TablePayload) -ScriptBlock {
    param($sourceAst,$CandidateSourcePayload)
    $script:CandidateSourcePayload=$CandidateSourcePayload
    $script:CandidateSourceExpectedFingerprint='867803e7533bfb053c70b951edc47cb4475b5f0183852dcb850b88b317c08f16'
    foreach ($functionName in @('Ensure-DataverseAccessToken','Invoke-PrivateOperation','Get-SafeDiagnosticText','Get-SafeErrorMessage','Get-SafeResponseHeader','Get-SafeRawResponseHeader','Get-SafeAuthenticationChallenge','Get-HttpExceptionDetails','Get-RecoveryFailureClass','New-SafeHttpFailure','Get-StoppedDetails','Get-ReconciliationSummary','Write-Result','Get-PayloadFingerprint','Set-RecoveryState','Get-RecoveryFailureState','Assert-CreateOnlyRecoveryTable','Assert-CandidateSourceTable','Assert-PositionPayloadFingerprint','Assert-CandidateSourcePayloadFingerprint','Assert-ExpectedRecoveryUser','Assert-RequiredPrivilegeSet','Assert-RecoveryInventory','Assert-RecoveryPrivileges','Get-RetrieveEntityMetadata','Get-PublicationLabelText','ConvertTo-PublicationMetadataSnapshot','Compare-PublicationMetadataSnapshots','Get-TablePublicationState','Invoke-BoundedEntityCreation','Invoke-PositionCreateOnlyRecovery','Invoke-CandidateSourceCreateOnly','Invoke-TableScopedPublication','Invoke-DataverseRequest')) {
        $functionAst=$sourceAst.Find({param($node)$node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $functionName},$true)
        Invoke-Expression $functionAst.Extent.Text
    }
    $script:OrganizationUrl='https://synthetic.crm.dynamics.com/';$script:ApiRoot=$script:OrganizationUrl+'api/data/v9.2/'
    $script:TableName='os_sr_pos';$script:Apply=$true;$script:PlanOnly=$false;$script:Definition=@{Columns=@()}
    $script:Secrets=@('synthetic.access.token-marker','synthetic-refresh-marker','synthetic-client-secret','synthetic-auth-code','synthetic-cookie-marker','synthetic-basic-marker')
    $script:UnsafeText='Authorization: Bearer '+$script:Secrets[0]+'; refresh_token='+$script:Secrets[1]+'; client_secret='+$script:Secrets[2]+'; code='+$script:Secrets[3]+'; Cookie: session='+$script:Secrets[4]+'; Basic '+$script:Secrets[5]
    function Get-InteractiveAccessToken {
        $script:Refreshes++
        $script:AccessToken=$script:Secrets[0]
        $script:AccessTokenIssuedAt=[DateTimeOffset]::UtcNow
        $script:AccessTokenExpiresOn=[DateTimeOffset]::UtcNow.AddHours(1)
        $script:TransportState.ExpiresOn=$script:AccessTokenExpiresOn
    }
    function Get-ODataList {
        param([string]$Path)
        $script:LastPublicationQuery = $Path
        @($script:PublicationRows)
    }
    function New-PrivatePipeline {
        $pipeline=[System.Management.Automation.PowerShell]::Create()
        $null=$pipeline.AddScript({
            param($state)
            $script:State=$state
            function Invoke-RestMethod {
                [CmdletBinding()]
                param($Method,$Uri,$Headers,$SkipHeaderValidation,$MaximumRedirection,$MaximumRetryCount,$SkipHttpErrorCheck,$StatusCodeVariable,$ResponseHeadersVariable,$TimeoutSec,$ContentType,$Body)
                $script:State.Calls++
                if ($Method -eq 'POST') {
                    $script:State.PostCalls++
                    $script:State.Request=[ordered]@{Method=$Method;Uri=[string]$Uri;ExactBearer=($Headers.Authorization -ceq ('Bearer '+$script:State.Secrets[0]));Fresh=($script:State.ExpiresOn -gt [DateTimeOffset]::UtcNow.AddMinutes(5));Solution=$Headers['MSCRM.SolutionUniqueName'];ContentType=$ContentType;Redirects=$MaximumRedirection;MaximumRetryCount=$MaximumRetryCount;SkipHttpErrorCheck=$SkipHttpErrorCheck;Body=(ConvertFrom-Json $Body)}
                }
                if ($Method -eq 'GET') {
                    $script:State.ReadUris.Add([string]$Uri)
                    $script:State.ReadMethods.Add($Method)
                    $script:State.ReadRetryLimits.Add([int]$MaximumRetryCount)
                }
                Write-Warning $script:State.UnsafeText
                Write-Information $script:State.UnsafeText
                Write-Verbose $script:State.UnsafeText
                if ($Method -eq 'POST' -and $script:State.ExceptionScenario) {
                    if ($script:State.ExceptionScenario -eq 'Timeout') { throw [TimeoutException]::new($script:State.UnsafeText) }
                    if ($script:State.ExceptionScenario -eq 'Transport') { throw [System.Net.Http.HttpRequestException]::new($script:State.UnsafeText) }
                    if ($script:State.ExceptionScenario -eq 'Unknown') { throw [InvalidOperationException]::new($script:State.UnsafeText) }
                    $responseCode = [int]$script:State.Status
                    $httpResponse = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]$responseCode)
                    [void]$httpResponse.Headers.TryAddWithoutValidation('WWW-Authenticate', ('Bearer error="invalid_token", error_description="'+$script:State.UnsafeText+'", claims="'+$script:State.Secrets[0]+'"'))
                    [void]$httpResponse.Headers.TryAddWithoutValidation('x-ms-service-request-id', '11111111-1111-4111-8111-111111111111')
                    [void]$httpResponse.Headers.TryAddWithoutValidation('x-ms-correlation-request-id', '22222222-2222-4222-8222-222222222222')
                    [void]$httpResponse.Headers.TryAddWithoutValidation('Authorization', $script:State.UnsafeText)
                    [void]$httpResponse.Headers.TryAddWithoutValidation('Set-Cookie', $script:State.UnsafeText)
                    $exception = [InvalidOperationException]::new($script:State.UnsafeText)
                    $exception | Add-Member -NotePropertyName Response -NotePropertyValue $httpResponse -Force
                    $errorRecord = [System.Management.Automation.ErrorRecord]::new($exception, 'SyntheticHttpException', [System.Management.Automation.ErrorCategory]::InvalidOperation, $null)
                    $bodyText = if ($script:State.ExceptionScenario -eq 'MalformedBody') {
                        'not-json ' + $script:State.UnsafeText
                    } else {
                        '{"error":{"code":"0x80040220","message":"'+$script:State.UnsafeText+'"},"rawAuthentication":"'+$script:State.UnsafeText+'"}'
                    }
                    $errorRecord.ErrorDetails = [System.Management.Automation.ErrorDetails]::new($bodyText)
                    throw $errorRecord
                }
                if ($script:State.Timeout) { throw [TimeoutException]::new($script:State.UnsafeText) }
                if ($script:State.TransportException) { throw [IOException]::new($script:State.UnsafeText) }
                $retrieveScenario=$null
                $retrieveFlag=$null
                if ($Method -eq 'GET' -and [string]$Uri -match 'RetrieveEntity\(') {
                    $retrieveFlag=if ([string]$Uri -match 'RetrieveAsIfPublished=true') { 'true' } else { 'false' }
                    $retrieveScenario=$script:State.RetrieveEntityResponses[$retrieveFlag]
                }
                $responseCode=if ($null -ne $retrieveScenario -and $null -ne $retrieveScenario.Status) { [int]$retrieveScenario.Status } elseif ($Method -eq 'GET') { $script:State.GetStatus } else { $script:State.Status }
                Set-Variable -Name $StatusCodeVariable -Value $responseCode -Scope 1
                Set-Variable -Name $ResponseHeadersVariable -Value @{
                    'WWW-Authenticate'=('Bearer error="'+$script:State.Secrets[0]+'", error_description="'+$script:State.UnsafeText+'"')
                    'Authorization'=$script:State.UnsafeText;'Set-Cookie'=$script:State.UnsafeText
                    'x-ms-service-request-id'='11111111-1111-4111-8111-111111111111'
                    'x-ms-correlation-request-id'='22222222-2222-4222-8222-222222222222'
                } -Scope 1
                if ($Method -eq 'GET' -and [string]$Uri -match 'RetrieveUserSetOfPrivilegesByNames') {
                    return [pscustomobject]@{RolePrivileges=@(1..$script:State.PrivilegeCount | ForEach-Object { [pscustomobject]@{PrivilegeId=('synthetic-'+$_);Depth='Global'} })}
                }
                if ($Method -eq 'GET' -and [string]$Uri -match 'RetrieveEntity\(') {
                    if ($responseCode -lt 200 -or $responseCode -ge 300) {
                        $httpResponse=[System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]$responseCode)
                        $exception=[InvalidOperationException]::new('Synthetic RetrieveEntity HTTP failure')
                        $exception | Add-Member -NotePropertyName Response -NotePropertyValue $httpResponse -Force
                        $errorRecord=[System.Management.Automation.ErrorRecord]::new($exception,'SyntheticRetrieveEntityFailure',[System.Management.Automation.ErrorCategory]::InvalidOperation,$null)
                        $errorRecord.ErrorDetails=[System.Management.Automation.ErrorDetails]::new('{"error":{"code":"0x80040217","message":"synthetic not found"}}')
                        throw $errorRecord
                    }
                    return $retrieveScenario.Response
                }
                [pscustomobject]@{error=[pscustomobject]@{code='0x80040220';message=$script:State.UnsafeText};rawAuthentication=$script:State.UnsafeText}
            }
        }).AddArgument($script:TransportState)
        $null=$pipeline.Invoke()
        $pipeline.Commands.Clear()
        $pipeline
    }
    function Get-TableMetadataIfPresent {
        if ($script:CreateOnlyRecovery) {
            if ($script:Outcome -eq 'UNKNOWN') { $script:TransportState.Timeout=$true }
            Invoke-DataverseRequest -Method GET -Path "EntityDefinitions(LogicalName='os_sr_pos')" | Out-Null
            if ($script:Outcome -eq 'ABSENT') { return $null }
            return $script:ExpectedPositionMetadata
        }
        if ($script:Outcome -eq 'UNKNOWN') {
            $script:TransportState.Timeout=$true
            Invoke-DataverseRequest -Method GET -Path EntityDefinitions | Out-Null
        }
        if ($script:Outcome -eq 'ABSENT') { return $null }
        [pscustomobject]@{LogicalName='os_sr_pos'}
    }
    function Assert-TableMetadata {
        param($Metadata)
        if (-not $script:CreateOnlyRecovery) {
            if ($script:Outcome -eq 'PARTIAL') { throw 'Synthetic metadata is incomplete.' }
            return
        }
        if ($script:Outcome -eq 'PARTIAL' -or $Metadata.LogicalName -cne 'os_sr_pos' -or
            $Metadata.SchemaName -cne 'os_sr_pos' -or $Metadata.OwnershipType -cne 'OrganizationOwned' -or
            $Metadata.DisplayName.UserLocalizedLabel.Label -cne 'Position' -or
            $Metadata.DisplayCollectionName.UserLocalizedLabel.Label -cne 'Positions' -or
            $Metadata.PrimaryIdAttribute -cne 'os_sr_posid' -or $Metadata.PrimaryNameAttribute -cne 'os_sr_pos_ttl' -or
            @($Metadata.Attributes | Where-Object { $_.LogicalName -ceq 'os_sr_pos_ttl' -and $_.DisplayName.UserLocalizedLabel.Label -ceq 'Position Title' -and $_.AttributeType -ceq 'String' -and $_.FormatName.Value -ceq 'Text' -and $_.MaxLength -eq 200 -and $_.RequiredLevel.Value -ceq 'ApplicationRequired' -and $_.IsPrimaryName }).Count -ne 1 -or
            @($Metadata.Attributes | Where-Object IsCustomAttribute).Count -ne 1 -or
            @($Metadata.Keys).Count -ne 0 -or
            @($Metadata.ManyToOneRelationships | Where-Object IsCustomRelationship).Count -ne 0 -or
            @($Metadata.OneToManyRelationships | Where-Object IsCustomRelationship).Count -ne 0 -or
            @($Metadata.ManyToManyRelationships | Where-Object IsCustomRelationship).Count -ne 0) {
            throw 'Synthetic metadata is incomplete or differs from the exact Position schema.'
        }
    }
    function Assert-SolutionMembership {
        param($SolutionId,$Metadata)
        if ($script:MembershipInvalid) { throw 'Synthetic Solution membership is incomplete.' }
    }
    function Reset-SyntheticState {
        $script:Refreshes=0;$script:LastHttpFailure=$null
        $script:AccessToken='expired-synthetic';$script:AccessTokenExpiresOn=[DateTimeOffset]::UtcNow.AddMinutes(-1)
        $script:RequestCounts=@{GET=0;POST=0};$script:WriteResults=[System.Collections.Generic.List[object]]::new()
        $script:Apply=$true;$script:CreateOnlyRecovery=$false;$script:CreateOnlyCandidateSource=$false;$script:PublishOnly=$false;$script:VerifyPublicationOnly=$false;$script:RecoveryState=$null
        $script:TableName='os_sr_pos'
        $script:RecoveryTransitions=[System.Collections.Generic.List[object]]::new()
        $script:RecoveryExpectedFingerprint='0f7372eeb66c0214ae08ed0dc74f82c981cc4cd73baa9156f16d6e1bd1f48e80'
        $script:RecoveryActualFingerprint=$null;$script:RecoveryReconciliation=$null;$script:RecoveryResponseClass=$null
        $script:RecoveryAttemptTimestampUtc=$null;$script:RecoveryEnvironmentVerified=$false
        $script:RecoveryIdentityVerified=$false;$script:RecoveryVerifiedPrivileges=@()
        $script:RecoveryPreflight=$null
        $script:PublicationStateDiagnostic=$null;$script:PreflightStage='INITIALIZATION';$script:PublicationRows=@()
        $script:RecoveryRequestId=$null;$script:RecoveryCorrelationId=$null;$script:LastRequestDispatchStarted=$false
        $script:WritesAllowed=$true;$script:WritesStarted=$false
        $script:TransportState=@{Calls=0;PostCalls=0;Request=$null;ReadUris=[System.Collections.Generic.List[string]]::new();ReadMethods=[System.Collections.Generic.List[string]]::new();ReadRetryLimits=[System.Collections.Generic.List[int]]::new();Status=0;GetStatus=200;Timeout=$false;TransportException=$false;ExceptionScenario=$null;PrivilegeCount=3;Secrets=$script:Secrets;UnsafeText=$script:UnsafeText;ExpiresOn=[DateTimeOffset]::MinValue;RetrieveEntityResponses=@{}}
    }
    function Test-SyntheticHttpChecks {
        param([object]$RecoveryPayload)
        $results=[System.Collections.Generic.List[object]]::new()
        foreach ($status in @(401,403,400,408,429,500,0,302)) {
            foreach ($outcome in @('PRESENT','ABSENT','PARTIAL','UNKNOWN')) {
                Reset-SyntheticState
                $script:TransportState.Status=$status;$script:TransportState.Timeout=($status -eq 0);$script:Outcome=$outcome
                $script:SafeException=$null
                $capture=@(& {
                    try { Invoke-DataverseRequest -Method POST -Path EntityDefinitions -Body @{SchemaName='os_sr_pos'} -WithSolutionHeader | Out-Null }
                    catch { $script:SafeException=$_.Exception.Message }
                    Write-Result -Stage PreflightOrExecution -Status Stopped -Details (Get-StoppedDetails)
                } *>&1)
                $text=$capture | Out-String
                $diagnostic=$text | ConvertFrom-Json
                $file=[IO.Path]::GetTempFileName()
                try {
                    Set-Content -LiteralPath $file -Value $text
                    $persisted=Get-Content -LiteralPath $file -Raw
                    $secretFound=$false
                    foreach ($secret in $script:Secrets) {
                        if ($text.Contains($secret) -or $persisted.Contains($secret) -or $script:SafeException.Contains($secret)) { $secretFound=$true }
                    }
                    $results.Add([pscustomobject]@{Status=$status;Outcome=$outcome;Diagnostic=$diagnostic;Json=$text;SecretFound=$secretFound;Request=$script:TransportState.Request;Calls=$script:TransportState.PostCalls;Refreshes=$script:Refreshes;Exception=$script:SafeException})
                }
                finally { Remove-Item -LiteralPath $file -Force }
            }
        }
        Reset-SyntheticState
        $guardResults=[ordered]@{}
        $script:WritesAllowed=$false
        try { Invoke-DataverseRequest -Method POST -Path EntityDefinitions -Body @{SchemaName='os_sr_pos'} -WithSolutionHeader | Out-Null } catch { $guardResults.Unconfirmed=($script:TransportState.Calls -eq 0) }
        $script:WritesAllowed=$true
        try { Invoke-DataverseRequest -Method GET -Path 'https://unapproved.invalid/api/data/v9.2/WhoAmI' | Out-Null } catch { $guardResults.ForeignOrigin=($script:TransportState.Calls -eq 0) }
        try { Invoke-DataverseRequest -Method POST -Path 'os_sr_pos' -Body @{} | Out-Null } catch { $guardResults.BusinessWrite=($script:TransportState.Calls -eq 0) }
        $script:AccessTokenExpiresOn=[DateTimeOffset]::UtcNow.AddMinutes(-1)
        try { Ensure-DataverseAccessToken -RefreshAction {} } catch { $guardResults.InvalidRefresh=($script:TransportState.Calls -eq 0) }
        $unsafeCode=New-SafeHttpFailure -Method POST -Resource ('EntityDefinitions/'+$script:Secrets[0]) -Timestamp ([DateTimeOffset]::UtcNow) -StatusCode 400 -Response ([pscustomobject]@{error=[pscustomobject]@{code=$script:UnsafeText}}) -Headers @{'x-ms-request-id'=$script:Secrets[0]}
        $exceptionCases=[System.Collections.Generic.List[object]]::new()
        foreach($case in @(
            @{Status=401;Scenario='HttpResponse';Class='HTTP_401';State='FAILED_AUTH';Category='HttpResponse';Code='0x80040220'},
            @{Status=403;Scenario='HttpResponse';Class='HTTP_403';State='FAILED_AUTHZ';Category='HttpResponse';Code='0x80040220'},
            @{Status=422;Scenario='HttpResponse';Class='HTTP_4XX_VALIDATION';State='FAILED_VALIDATION';Category='HttpResponse';Code='0x80040220'},
            @{Status=429;Scenario='HttpResponse';Class='HTTP_429';State='UNCERTAIN';Category='HttpResponse';Code='0x80040220'},
            @{Status=503;Scenario='HttpResponse';Class='HTTP_5XX';State='UNCERTAIN';Category='HttpResponse';Code='0x80040220'},
            @{Status=0;Scenario='Timeout';Class='TIMEOUT';State='UNCERTAIN';Category='Timeout';Code=$null},
            @{Status=0;Scenario='Transport';Class='TRANSPORT_FAILURE';State='UNCERTAIN';Category='Transport';Code=$null},
            @{Status=400;Scenario='MalformedBody';Class='HTTP_4XX_VALIDATION';State='FAILED_VALIDATION';Category='HttpResponse';Code=$null},
            @{Status=0;Scenario='Unknown';Class='UNKNOWN_HTTP_FAILURE';State='UNCERTAIN';Category='Unknown';Code=$null}
        )){
            Reset-SyntheticState
            $script:CreateOnlyRecovery=$true;$script:Apply=$false;$script:TableName='os_sr_pos'
            $script:RecoveryActualFingerprint=$script:RecoveryExpectedFingerprint
            $script:RecoveryState='READY';$script:WritesAllowed=$true;$script:Outcome='ABSENT'
            $script:TransportState.Status=$case.Status;$script:TransportState.ExceptionScenario=$case.Scenario
            $result=Invoke-PositionCreateOnlyRecovery -Payload $RecoveryPayload -SolutionId 'synthetic-solution'
            $failure=$result.HttpFailure
            $report=Write-Result -Stage Recovery -Status $result.State -Details $result | ConvertFrom-Json
            $serialized=ConvertTo-Json -InputObject $report -Depth 25 -Compress
            $reportedFailure=$report.Details.HttpFailure
            $challengeSafe=if($case.Scenario -in @('HttpResponse','MalformedBody')) {
                $failure.AuthenticationChallenge.Scheme -ceq 'Bearer' -and $failure.AuthenticationChallenge.Error -ceq 'invalid_token' -and
                    $failure.AuthenticationChallenge.ErrorDescriptionPresent -and $failure.AuthenticationChallenge.ClaimsChallengePresent
            } else { $null -eq $failure.AuthenticationChallenge }
            $checks=[ordered]@{
                Classification=($failure.FailureClass -ceq $case.Class -and $failure.ExceptionCategory -ceq $case.Category)
                TerminalState=($result.State -ceq $case.State)
                Status=($failure.StatusCode -eq $(if($case.Status -eq 0){$null}else{$case.Status}) -and $reportedFailure.StatusCode -eq $failure.StatusCode)
                StatusExplicit=($failure.HttpStatus -eq $(if($case.Status -eq 0){'UNKNOWN'}else{$case.Status}))
                ErrorCode=($failure.DataverseErrorCode -ceq $case.Code)
                Dispatch=([bool]$failure.DispatchStarted -and [bool]$failure.WritesMayHaveOccurred)
                SingleWrite=($script:TransportState.PostCalls -eq 1 -and $script:RequestCounts.POST -eq 1 -and $script:TransportState.Request.MaximumRetryCount -eq 0)
                GetOnlyReconciliation=($script:RequestCounts.GET -ge 1 -and @($script:TransportState.ReadMethods | Where-Object { $_ -ne 'GET' }).Count -eq 0)
                Challenge=$challengeSafe
                RequestIds=($case.Scenario -notin @('HttpResponse','MalformedBody') -or
                    ($failure.RequestId -ceq '11111111-1111-4111-8111-111111111111' -and $failure.CorrelationId -ceq '22222222-2222-4222-8222-222222222222'))
                Privacy=($serialized -notmatch [regex]::Escape($script:Secrets[0]) -and
                    $serialized -notmatch '"Authorization"\s*:|rawAuthentication|refresh_token\s*=|client_secret\s*=|Set-Cookie|error_description\s*=|claims\s*=')
            }
            $valid=@($checks.Values | Where-Object { -not $_ }).Count -eq 0
            $exceptionCases.Add([pscustomobject]@{Scenario=$case.Scenario;Status=$failure.StatusCode;HttpStatus=$failure.HttpStatus;FailureClass=$failure.FailureClass;ExceptionCategory=$failure.ExceptionCategory;State=$result.State;Passed=$valid;CheckSummary=($checks.GetEnumerator() | Where-Object { -not $_.Value } | ForEach-Object Key) -join ',';ReportStatus=$reportedFailure.StatusCode;ReportHttpStatus=$reportedFailure.HttpStatus;RequestId=$failure.RequestId;CorrelationId=$failure.CorrelationId})
        }
        [pscustomobject]@{Cases=$results.ToArray();ExceptionCases=$exceptionCases.ToArray();Guards=$guardResults;UnsafeCode=$unsafeCode;OmittedText=(Get-SafeDiagnosticText $script:UnsafeText);OmittedException=(Get-SafeErrorMessage ([System.Management.Automation.ErrorRecord]::new([Exception]::new($script:UnsafeText),'Synthetic',[System.Management.Automation.ErrorCategory]::NotSpecified,$null)))}
    }
    function Test-SyntheticRecoveryChecks {
        param([object]$RecoveryPayload,[object]$ExpectedPositionMetadata)
        $results=[System.Collections.Generic.List[object]]::new()
        $script:ExpectedPositionMetadata=$ExpectedPositionMetadata
        foreach ($name in @('os_sr_csrc','os_sr_loc','os_sr_ta')) {
            $rejected=$false
            try { Assert-CreateOnlyRecoveryTable -Name $name } catch { $rejected=$true }
            $results.Add([pscustomobject]@{Kind='TableGuard';Name=$name;Passed=$rejected})
        }
        Assert-CreateOnlyRecoveryTable -Name 'os_sr_pos'
        $expectedUser='11111111-1111-4111-8111-111111111111'
        $script:ExpectedUserId=$expectedUser
        Assert-ExpectedRecoveryUser -ActualUserId $expectedUser
        $identityMismatch=$false
        try { Assert-ExpectedRecoveryUser -ActualUserId '22222222-2222-4222-8222-222222222222' } catch { $identityMismatch=$true }
        $results.Add([pscustomobject]@{Kind='IdentityGuard';Passed=$identityMismatch})
        $script:ExpectedUserId=$null
        $pacEnvironmentAst=$sourceAst.Find({param($node)$node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Assert-PacEnvironment'},$true)
        $candidateSourceExpectedUserGuard=$pacEnvironmentAst.Extent.Text -match '(?s)if \(\$CreateOnlyRecovery -or \$CreateOnlyCandidateSource\)\s*\{\s*Assert-ExpectedRecoveryUser'
        $results.Add([pscustomobject]@{Kind='CandidateSourceExpectedUserGuard';Passed=$candidateSourceExpectedUserGuard})
        $required=@('prvCreateEntity','prvCreateAttribute','prvCreateCustomization')
        Assert-RequiredPrivilegeSet -Privileges @([pscustomobject]@{Name='synthetic'},[pscustomobject]@{Name='synthetic'},[pscustomobject]@{Name='synthetic'}) -RequiredNames $required
        $privilegeMissing=$false
        try { Assert-RequiredPrivilegeSet -Privileges @([pscustomobject]@{Name='synthetic'}) -RequiredNames $required } catch { $privilegeMissing=$true }
        $results.Add([pscustomobject]@{Kind='PrivilegeGuard';Passed=$privilegeMissing})
        Assert-RecoveryInventory -ProjectTables @('os_sr_ta') -SolutionComponents @([pscustomobject]@{objectid='ta-id';componenttype=1}) -ExistingTableIds @('ta-id')
        $inventoryMismatch=$false
        try { Assert-RecoveryInventory -ProjectTables @('os_sr_ta') -SolutionComponents @([pscustomobject]@{objectid='orphan-id';componenttype=2}) -ExistingTableIds @('ta-id') } catch { $inventoryMismatch=$true }
        $results.Add([pscustomobject]@{Kind='InventoryGuard';Passed=$inventoryMismatch})
        Reset-SyntheticState
        $script:CreateOnlyRecovery=$true;$script:Apply=$false;$script:PacUserId='11111111-1111-4111-8111-111111111111'
        $script:TransportState.Status=200
        $verifiedPrivileges=@(Assert-RecoveryPrivileges)
        $privilegePath=$script:TransportState.ReadUris[0]
        $privilegeCallPassed=($verifiedPrivileges.Count -eq 3 -and $script:RequestCounts.POST -eq 0 -and
            $privilegePath -match 'RetrieveUserSetOfPrivilegesByNames' -and
            $privilegePath -match 'prvCreateEntity' -and $privilegePath -match 'prvCreateAttribute' -and
            $privilegePath -match 'prvCreateCustomization')
        Reset-SyntheticState
        $script:CreateOnlyRecovery=$true;$script:Apply=$false;$script:PacUserId='11111111-1111-4111-8111-111111111111'
        $script:TransportState.Status=200;$script:TransportState.PrivilegeCount=2
        $privilegeMissing=$false
        try { Assert-RecoveryPrivileges | Out-Null } catch { $privilegeMissing=$true }
        $results.Add([pscustomobject]@{Kind='PrivilegeEndpoint';Passed=($privilegeCallPassed -and $privilegeMissing)})
        Reset-SyntheticState
        $script:CreateOnlyRecovery=$true;$script:Apply=$false;$script:TableName='os_sr_pos'
        $script:RecoveryState='PRECHECK';$script:RecoveryActualFingerprint=$null
        $wrongPayload=[pscustomobject]@{SchemaName='os_sr_pos';DisplayName='Wrong'}
        $wrongRejected=$false
        try { Assert-PositionPayloadFingerprint -Payload $wrongPayload | Out-Null } catch { $wrongRejected=$true }
        $wrongDetails=Get-StoppedDetails
        $results.Add([pscustomobject]@{Kind='FingerprintMismatch';Passed=($wrongRejected -and $script:RecoveryState -eq 'FAILED_VALIDATION' -and $script:TransportState.Calls -eq 0 -and $script:Refreshes -eq 0 -and $wrongDetails.Recovery.ExpectedPayloadSha256 -ceq $script:RecoveryExpectedFingerprint -and $wrongDetails.Recovery.ActualPayloadSha256 -ceq $script:RecoveryActualFingerprint);Expected=$script:RecoveryExpectedFingerprint;Actual=$script:RecoveryActualFingerprint})

        Reset-SyntheticState
        $script:CreateOnlyRecovery=$true;$script:Apply=$false;$script:TableName='os_sr_pos'
        $script:RecoveryState='PRECHECK'
        $fingerprint=Assert-PositionPayloadFingerprint -Payload $RecoveryPayload
        $results.Add([pscustomobject]@{Kind='FingerprintMatch';Passed=($fingerprint -ceq $script:RecoveryExpectedFingerprint)})

        Reset-SyntheticState
        $script:CreateOnlyCandidateSource=$true;$script:Apply=$false;$script:TableName='os_sr_csrc';$script:RecoveryState='PRECHECK'
        $candidateFingerprint=Assert-CandidateSourcePayloadFingerprint -Payload $script:CandidateSourcePayload
        $candidateTableBlocked=$false
        try { Assert-CandidateSourceTable -Name 'os_sr_pos' } catch { $candidateTableBlocked=$true }
        $results.Add([pscustomobject]@{Kind='CandidateSourceFingerprintMatch';Passed=($candidateFingerprint -ceq $script:CandidateSourceExpectedFingerprint -and $script:RecoveryExpectedFingerprint -ceq $script:CandidateSourceExpectedFingerprint)})
        $results.Add([pscustomobject]@{Kind='CandidateSourceTableRestriction';Passed=$candidateTableBlocked})

        Reset-SyntheticState
        $script:CreateOnlyCandidateSource=$true;$script:Apply=$false;$script:TableName='os_sr_csrc';$script:RecoveryState='PRECHECK'
        $candidateWrongPayload=[ordered]@{SchemaName='os_sr_csrc';DisplayName='Unexpected'}
        $candidateFingerprintRejected=$false
        try { Assert-CandidateSourcePayloadFingerprint -Payload $candidateWrongPayload | Out-Null } catch { $candidateFingerprintRejected=$true }
        $results.Add([pscustomobject]@{Kind='CandidateSourceFingerprintMismatch';Passed=($candidateFingerprintRejected -and $script:RecoveryState -eq 'FAILED_VALIDATION' -and $script:TransportState.Calls -eq 0 -and $script:Refreshes -eq 0)})

        function New-SyntheticPositionMetadata {
            param([int]$MaxLength=200,[string]$DisplayName='Position Title',[string[]]$AttributeOrder=@('os_sr_pos_ttl','os_sr_posid'),[string]$RuntimeMarker='ignored')
            $attrs=@($AttributeOrder | ForEach-Object {
                if ($_ -ceq 'os_sr_pos_ttl') {
                    [pscustomobject]@{LogicalName='os_sr_pos_ttl';SchemaName='os_sr_pos_ttl';DisplayName=[pscustomobject]@{UserLocalizedLabel=[pscustomobject]@{Label=$DisplayName};LocalizedLabels=@()};AttributeType='String';FormatName=[pscustomobject]@{Value='Text'};MaxLength=$MaxLength;RequiredLevel=[pscustomobject]@{Value='ApplicationRequired'};IsPrimaryName=$true;IsCustomAttribute=$true}
                } else {
                    [pscustomobject]@{LogicalName='os_sr_posid';SchemaName='os_sr_posid';AttributeType='Uniqueidentifier';IsPrimaryId=$true;IsCustomAttribute=$false}
                }
            })
            [pscustomobject]@{
                LogicalName='os_sr_pos';SchemaName='os_sr_pos';MetadataId='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
                DisplayName=[pscustomobject]@{UserLocalizedLabel=[pscustomobject]@{Label='Position'};LocalizedLabels=@()}
                DisplayCollectionName=[pscustomobject]@{UserLocalizedLabel=[pscustomobject]@{Label='Positions'};LocalizedLabels=@()}
                OwnershipType='OrganizationOwned';PrimaryIdAttribute='os_sr_posid';PrimaryNameAttribute='os_sr_pos_ttl'
                Attributes=$attrs;Keys=@();ManyToOneRelationships=@();OneToManyRelationships=@();ManyToManyRelationships=@()
                RuntimeMetadata=$RuntimeMarker;Timestamp='ignored'
            }
        }
        $positionMetadata=New-SyntheticPositionMetadata
        $publicationCases=@(
            @{Name='PublishedNoDelta';False=@{Response=[pscustomobject]@{EntityMetadata=$positionMetadata}};True=@{Response=[pscustomobject]@{EntityMetadata=$positionMetadata}};Expected='PUBLISHED_NO_PENDING_DELTA'},
            @{Name='PublishedWithDelta';False=@{Response=[pscustomobject]@{EntityMetadata=$positionMetadata}};True=@{Response=[pscustomobject]@{EntityMetadata=(New-SyntheticPositionMetadata -MaxLength 199)}};Expected='PUBLISHED_WITH_UNPUBLISHED_DELTA'},
            @{Name='UnpublishedOnly';False=@{Status=404};True=@{Response=[pscustomobject]@{EntityMetadata=$positionMetadata}};Expected='UNPUBLISHED_ONLY'},
            @{Name='AbsentBoth';False=@{Status=404};True=@{Status=404};Expected='UNKNOWN'},
            @{Name='FailedRetrieval';False=@{Status=503};True=@{Response=[pscustomobject]@{EntityMetadata=$positionMetadata}};Expected='UNKNOWN'},
            @{Name='MalformedRetrieval';False=@{Response=[pscustomobject]@{Unexpected='shape'}};True=@{Response=[pscustomobject]@{EntityMetadata=$positionMetadata}};Expected='UNKNOWN'}
        )
        $publicationStates=[ordered]@{}
        foreach($case in $publicationCases) {
            Reset-SyntheticState
            $script:VerifyPublicationOnly=$true
            $script:TransportState.RetrieveEntityResponses=@{false=$case.False;true=$case.True}
            $actual=Get-TablePublicationState -SolutionId 'synthetic-solution' -Metadata $positionMetadata
            $publicationStates[$case.Name]=($actual -ceq $case.Expected -and $script:RequestCounts.GET -eq 2 -and
                @($script:TransportState.ReadMethods | Where-Object { $_ -ne 'GET' }).Count -eq 0 -and
                $script:RequestCounts.POST -eq 0 -and $script:WritesStarted -eq $false -and
                @($script:TransportState.ReadRetryLimits | Where-Object { $_ -ne 0 }).Count -eq 0 -and
                @($script:TransportState.ReadUris | Where-Object { $_ -match 'RetrieveEntity\(EntityFilters=Microsoft\.Dynamics\.CRM\.EntityFilters''All'',MetadataId=aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa,RetrieveAsIfPublished=(true|false)\)' }).Count -eq 2)
        }
        Reset-SyntheticState
        $script:VerifyPublicationOnly=$true
        $orderedPublished=New-SyntheticPositionMetadata -AttributeOrder @('os_sr_posid','os_sr_pos_ttl') -RuntimeMarker 'changed'
        $orderedCurrent=New-SyntheticPositionMetadata -AttributeOrder @('os_sr_pos_ttl','os_sr_posid') -RuntimeMarker 'different'
        $script:TransportState.RetrieveEntityResponses=@{
            false=@{Response=[pscustomobject]@{EntityMetadata=$orderedPublished}}
            true=@{Response=[pscustomobject]@{EntityMetadata=$orderedCurrent}}
        }
        $orderIgnored=(Get-TablePublicationState -SolutionId 'synthetic-solution' -Metadata $orderedCurrent) -ceq 'PUBLISHED_NO_PENDING_DELTA'
        $results.Add([pscustomobject]@{Kind='PublicationStateClassification';Passed=($publicationStates.Count -eq 6 -and @($publicationStates.Values | Where-Object { -not $_ }).Count -eq 0 -and $orderIgnored);Cases=$publicationStates;OrderingAndRuntimeIgnored=$orderIgnored})

        Reset-SyntheticState
        $script:Apply=$false;$script:VerifyPublicationOnly=$true;$script:WritesAllowed=$false
        $publicationWriteBlocked=$false
        try { Invoke-DataverseRequest -Method POST -Path EntityDefinitions -Body @{SchemaName='os_sr_pos'} | Out-Null }
        catch { $publicationWriteBlocked=($script:TransportState.Calls -eq 0 -and $script:RequestCounts.POST -eq 0 -and -not $script:WritesStarted) }
        $results.Add([pscustomobject]@{Kind='PublicationVerifyWriteBlocked';Passed=$publicationWriteBlocked})

        Reset-SyntheticState
        $script:CreateOnlyCandidateSource=$true;$script:Apply=$false;$script:TableName='os_sr_csrc'
        $script:RecoveryActualFingerprint=$script:CandidateSourceExpectedFingerprint
        $script:RecoveryState='READY';$script:WritesAllowed=$true;$script:TransportState.Status=201
        $candidateCreated=Invoke-DataverseRequest -Method POST -Path EntityDefinitions -Body $script:CandidateSourcePayload -WithSolutionHeader
        $candidateFirstWrite=($script:TransportState.PostCalls -eq 1 -and $script:RequestCounts.POST -eq 1 -and
            $script:TransportState.Request.MaximumRetryCount -eq 0 -and
            $script:TransportState.Request.Solution -ceq 'os_sr_bso_rs_support' -and
            $script:TransportState.Request.Body.SchemaName -ceq 'os_sr_csrc')
        $candidateSecondWriteBlocked=$false
        try { Invoke-DataverseRequest -Method POST -Path EntityDefinitions -Body $script:CandidateSourcePayload -WithSolutionHeader | Out-Null }
        catch { $candidateSecondWriteBlocked=($script:TransportState.PostCalls -eq 1) }
        $candidateAttributeBlocked=$false
        try { Invoke-DataverseRequest -Method POST -Path "EntityDefinitions(LogicalName='os_sr_csrc')/Attributes" -Body @{SchemaName='os_sr_csrc_extra'} -WithSolutionHeader | Out-Null }
        catch { $candidateAttributeBlocked=($script:TransportState.PostCalls -eq 1) }
        $results.Add([pscustomobject]@{Kind='CandidateSourceSingleCreateGuard';Passed=($candidateFirstWrite -and $candidateSecondWriteBlocked -and $candidateAttributeBlocked -and $null -ne $candidateCreated)})

        Reset-SyntheticState
        $script:CreateOnlyCandidateSource=$true;$script:Apply=$false;$script:TableName='os_sr_csrc'
        $script:RecoveryActualFingerprint=$script:CandidateSourceExpectedFingerprint
        $script:RecoveryState='READY';$script:WritesAllowed=$true;$script:Outcome='PRESENT';$script:TransportState.Status=201
        $candidateCreatedResult=Invoke-CandidateSourceCreateOnly -Payload $script:CandidateSourcePayload -SolutionId 'synthetic-solution'
        $results.Add([pscustomobject]@{Kind='CandidateSourceCreateOutcome';Passed=($candidateCreatedResult.State -ceq 'VERIFIED_SUCCESS' -and $candidateCreatedResult.Outcome -ceq 'VERIFIED_CREATED' -and $script:TransportState.PostCalls -eq 1 -and $candidateCreatedResult.RequestCounts.POST -eq 1 -and $candidateCreatedResult.RequestCounts.GET -eq $script:RequestCounts.GET)})

        Reset-SyntheticState
        $script:CreateOnlyCandidateSource=$true;$script:Apply=$false;$script:TableName='os_sr_csrc'
        $script:RecoveryActualFingerprint=$script:CandidateSourceExpectedFingerprint
        $script:RecoveryState='READY';$script:WritesAllowed=$true;$script:Outcome='PRESENT';$script:TransportState.Status=401
        $candidateExistingResult=Invoke-CandidateSourceCreateOnly -Payload $script:CandidateSourcePayload -SolutionId 'synthetic-solution'
        $results.Add([pscustomobject]@{Kind='CandidateSourceExistingOutcome';Passed=($candidateExistingResult.Outcome -ceq 'EXISTING_STATE' -and $script:TransportState.PostCalls -eq 1)})

        Reset-SyntheticState
        $script:PublishOnly=$true;$script:Apply=$false;$script:TableName='os_sr_pos'
        $script:RecoveryState='READY';$script:WritesAllowed=$true;$script:TransportState.Status=200
        $publishBody=[ordered]@{ParameterXml="<importexportxml><entities><entity>os_sr_pos</entity></entities></importexportxml>"}
        $null=Invoke-DataverseRequest -Method POST -Path PublishXml -Body $publishBody
        $publishEntityBlocked=$false
        try { Invoke-DataverseRequest -Method POST -Path EntityDefinitions -Body @{SchemaName='os_sr_pos'} -WithSolutionHeader | Out-Null }
        catch { $publishEntityBlocked=($script:TransportState.PostCalls -eq 1) }
        $results.Add([pscustomobject]@{Kind='PublishOnlyScopeGuard';Passed=($script:TransportState.PostCalls -eq 1 -and $script:RequestCounts.POST -eq 1 -and $script:TransportState.Request.MaximumRetryCount -eq 0 -and $script:TransportState.Request.Uri -match '/PublishXml$' -and $publishEntityBlocked)})

        foreach ($case in @(
            @{Status=401;Outcome='ABSENT';Expected='FAILED_AUTH'},
            @{Status=403;Outcome='ABSENT';Expected='FAILED_AUTHZ'},
            @{Status=400;Outcome='ABSENT';Expected='FAILED_VALIDATION'},
            @{Status=408;Outcome='ABSENT';Expected='UNCERTAIN'},
            @{Status=429;Outcome='ABSENT';Expected='UNCERTAIN'},
            @{Status=500;Outcome='ABSENT';Expected='UNCERTAIN'},
            @{Status=0;Outcome='ABSENT';Expected='UNCERTAIN'},
            @{Status=201;Outcome='PRESENT';Expected='VERIFIED_SUCCESS'},
            @{Status=201;Outcome='PRESENT';Expected='PARTIAL_STATE';MembershipInvalid=$true},
            @{Status=401;Outcome='PRESENT';Expected='VERIFIED_SUCCESS'},
            @{Status=500;Outcome='PARTIAL';Expected='PARTIAL_STATE'},
            @{Status=200;Outcome='UNKNOWN';Expected='UNCERTAIN'}
        )) {
            Reset-SyntheticState
            $script:CreateOnlyRecovery=$true;$script:Apply=$false;$script:TableName='os_sr_pos'
            $script:RecoveryState='PRECHECK';$script:RecoveryActualFingerprint=$script:RecoveryExpectedFingerprint
            $script:RecoveryTransitions.Add([ordered]@{State='READY';TimestampUtc=[DateTimeOffset]::UtcNow.ToString('o')})
            $script:RecoveryState='READY';$script:WritesAllowed=$true
            $script:TransportState.Status=$case.Status
            $script:TransportState.Timeout=($case.Status -eq 0)
            $script:Outcome=$case.Outcome
            $script:MembershipInvalid=[bool]$case.MembershipInvalid
            $result=Invoke-PositionCreateOnlyRecovery -Payload $RecoveryPayload -SolutionId 'synthetic-solution'
            $attemptTime=[DateTimeOffset]::ParseExact($script:RecoveryAttemptTimestampUtc,'o',[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::None)
            $states=(@($result.StateTransitions | ForEach-Object State) -join ',')
            $valid=$result.State -ceq $case.Expected -and $script:TransportState.PostCalls -eq 1 -and
                $script:RequestCounts.POST -eq 1 -and $script:RequestCounts.GET -ge 1 -and
                @($script:TransportState.ReadMethods | Where-Object { $_ -ne 'GET' }).Count -eq 0 -and
                $script:TransportState.Request.MaximumRetryCount -eq 0 -and
                $attemptTime.Offset -eq [TimeSpan]::Zero -and
                $states -match "WRITE_ATTEMPTED,RECONCILING,$($case.Expected)$"
            $results.Add([pscustomobject]@{Kind='Response';Status=$case.Status;Outcome=$case.Outcome;Expected=$case.Expected;Actual=$result.State;Passed=$valid;Result=$result})
        }

        Reset-SyntheticState
        $script:CreateOnlyRecovery=$true;$script:Apply=$false;$script:TableName='os_sr_pos'
        $script:RecoveryActualFingerprint=$script:RecoveryExpectedFingerprint
        $script:RecoveryState='READY';$script:WritesAllowed=$true
        $script:Outcome='ABSENT';$script:TransportState.TransportException=$true
        $null=Invoke-PositionCreateOnlyRecovery -Payload $RecoveryPayload -SolutionId 'synthetic-solution'
        $results.Add([pscustomobject]@{Kind='TransportException';Passed=($script:RecoveryState -eq 'UNCERTAIN' -and $script:TransportState.PostCalls -eq 1)})

        Reset-SyntheticState
        $script:CreateOnlyRecovery=$true;$script:Apply=$false;$script:TableName='os_sr_pos'
        $script:RecoveryActualFingerprint=$script:RecoveryExpectedFingerprint
        $script:RecoveryState='READY';$script:WritesAllowed=$true
        $script:Outcome='PRESENT';$script:TransportState.Status=201
        $null=Invoke-PositionCreateOnlyRecovery -Payload $RecoveryPayload -SolutionId 'synthetic-solution'
        $before=$script:TransportState.PostCalls
        $blockedPaths=[ordered]@{}
        foreach ($path in @("EntityDefinitions(LogicalName='os_sr_pos')/Attributes",'PublishXml')) {
            try { Invoke-DataverseRequest -Method POST -Path $path -Body @{SchemaName='os_sr_pos'} -WithSolutionHeader | Out-Null }
            catch { $blockedPaths[$path]=($script:TransportState.PostCalls -eq $before) }
        }
        $secondBlocked=$false
        try { Invoke-DataverseRequest -Method POST -Path EntityDefinitions -Body $RecoveryPayload -WithSolutionHeader | Out-Null }
        catch { $secondBlocked=($script:TransportState.PostCalls -eq $before) }
        $deleteBlocked=$false
        try { Invoke-DataverseRequest -Method DELETE -Path EntityDefinitions | Out-Null }
        catch { $deleteBlocked=($script:TransportState.PostCalls -eq $before) }
        $patchBlocked=$false
        try { Invoke-DataverseRequest -Method PATCH -Path EntityDefinitions -Body @{DisplayName='Changed'} | Out-Null }
        catch { $patchBlocked=($script:TransportState.PostCalls -eq $before) }
        $results.Add([pscustomobject]@{Kind='WriteGuards';Passed=($before -eq 1 -and $secondBlocked -and $deleteBlocked -and $patchBlocked -and @($blockedPaths.Values | Where-Object { -not $_ }).Count -eq 0);Paths=$blockedPaths;SecondPostBlocked=$secondBlocked;DeleteBlocked=$deleteBlocked;PatchBlocked=$patchBlocked})

        $safeDetails=Get-StoppedDetails | ConvertTo-Json -Depth 20 -Compress
        $results.Add([pscustomobject]@{Kind='DiagnosticPrivacy';Passed=($safeDetails -notmatch 'synthetic\.access\.token-marker|synthetic-refresh-marker|"Authorization"\s*:|Bearer|User Email|https://synthetic\.crm\.dynamics\.com|11111111-1111-4111-8111-111111111111')})
        $results.ToArray()
    }
    Export-ModuleMember -Function Test-SyntheticHttpChecks,Test-SyntheticRecoveryChecks
}
Import-Module $httpModule -Force
$originalCulture = [System.Threading.Thread]::CurrentThread.CurrentCulture
$originalUiCulture = [System.Threading.Thread]::CurrentThread.CurrentUICulture
try {
    [System.Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::GetCultureInfo('fr-FR')
    [System.Threading.Thread]::CurrentThread.CurrentUICulture = [Globalization.CultureInfo]::GetCultureInfo('fr-FR')
    $utcFixture = '{"Details":{"HttpFailure":{"TimestampUtc":"2026-10-21T20:55:06.1234567+00:00"}}}'
    $parsedUtcFixture = Get-UtcTimestampFromJson -Json $utcFixture
    Assert-Test ($parsedUtcFixture.Offset -eq [TimeSpan]::Zero) 'Round-trip UTC timestamp parsing is culture invariant'
    $nonUtcFixture = '{"Details":{"HttpFailure":{"TimestampUtc":"2026-10-21T20:55:06.1234567+07:00"}}}'
    Assert-Rejected { Get-UtcTimestampFromJson -Json $nonUtcFixture } 'Reject non-UTC timestamp offset' 'zero UTC offset'
}
finally {
    [System.Threading.Thread]::CurrentThread.CurrentCulture = $originalCulture
    [System.Threading.Thread]::CurrentThread.CurrentUICulture = $originalUiCulture
}
$transcript=[IO.Path]::GetTempFileName()
try {
    Start-Transcript -LiteralPath $transcript -Force | Out-Null
    try {
        $http=Test-SyntheticHttpChecks -RecoveryPayload $positionPayload
        $recovery=Test-SyntheticRecoveryChecks -RecoveryPayload $positionPayload -ExpectedPositionMetadata (New-Fixture os_sr_pos)
    }
    finally { Stop-Transcript | Out-Null }
    $transcriptText=Get-Content -LiteralPath $transcript -Raw
    Assert-Test ($transcriptText -notmatch 'synthetic\.(access\.token-marker)|synthetic-(refresh-marker|client-secret|auth-code|cookie-marker|basic-marker)') 'Transcript excludes synthetic secrets'
}
finally { Remove-Item -LiteralPath $transcript -Force; Remove-Module $httpModule }
$tableGuards=@($recovery | Where-Object Kind -eq 'TableGuard')
Assert-Test ($tableGuards.Count -eq 3 -and @($tableGuards | Where-Object { -not $_.Passed }).Count -eq 0) 'Recovery mode rejects Candidate Source, Location and TA'
foreach ($kind in @('IdentityGuard','PrivilegeGuard','PrivilegeEndpoint','InventoryGuard')) {
    $guard=@($recovery | Where-Object Kind -eq $kind)[0]
    Assert-Test $guard.Passed "$kind fails closed on mismatch"
}
$candidateSourceIdentityGuard=@($recovery | Where-Object Kind -eq 'CandidateSourceExpectedUserGuard')[0]
Assert-Test $candidateSourceIdentityGuard.Passed 'Candidate Source create-only preflight enforces the process-scoped expected-user guard'
$fingerprintMismatch=@($recovery | Where-Object Kind -eq 'FingerprintMismatch')[0]
Assert-Test ($fingerprintMismatch.Passed -and $fingerprintMismatch.Expected -ceq '0f7372eeb66c0214ae08ed0dc74f82c981cc4cd73baa9156f16d6e1bd1f48e80' -and $fingerprintMismatch.Actual -cne $fingerprintMismatch.Expected) 'Fingerprint mismatch fails validation before authentication or network'
$fingerprintMatch=@($recovery | Where-Object Kind -eq 'FingerprintMatch')[0]
Assert-Test $fingerprintMatch.Passed 'Exact Position payload fingerprint is accepted'
$responseCases=@($recovery | Where-Object Kind -eq 'Response')
Assert-Test ($responseCases.Count -eq 12 -and @($responseCases | Where-Object { -not $_.Passed }).Count -eq 0) 'Recovery state machine classifies HTTP and reconciliation outcomes'
Assert-Test (@($responseCases | Where-Object { $_.Status -eq 429 -and $_.Actual -eq 'UNCERTAIN' }).Count -eq 1 -and
    @($responseCases | Where-Object { $_.Status -eq 500 -and $_.Actual -eq 'UNCERTAIN' }).Count -eq 1 -and
    @($responseCases | Where-Object { $_.Outcome -eq 'UNKNOWN' -and $_.Actual -eq 'UNCERTAIN' }).Count -eq 1) 'Throttling, server error and unknown reconciliation remain uncertain'
$transportException=@($recovery | Where-Object Kind -eq 'TransportException')[0]
Assert-Test $transportException.Passed 'Transport exception is uncertain and never retried'
$writeGuards=@($recovery | Where-Object Kind -eq 'WriteGuards')[0]
Assert-Test $writeGuards.Passed 'Recovery mode blocks second POST, attribute POST, PublishXml and DELETE'
$candidateSourceGuard=@($recovery | Where-Object Kind -eq 'CandidateSourceSingleCreateGuard')[0]
Assert-Test $candidateSourceGuard.Passed 'Candidate Source mode allows only its fingerprinted EntityDefinitions POST and disables retries'
$candidateCreatedOutcome=@($recovery | Where-Object Kind -eq 'CandidateSourceCreateOutcome')[0]
Assert-Test $candidateCreatedOutcome.Passed 'Candidate Source verified create outcome is reported distinctly'
$candidateExistingOutcome=@($recovery | Where-Object Kind -eq 'CandidateSourceExistingOutcome')[0]
Assert-Test $candidateExistingOutcome.Passed 'Existing exact Candidate Source state is not mislabeled as newly created'
$candidateFingerprintMatch=@($recovery | Where-Object Kind -eq 'CandidateSourceFingerprintMatch')[0]
Assert-Test $candidateFingerprintMatch.Passed 'Candidate Source runtime fingerprint gate matches the approved hash'
$candidateFingerprintMismatch=@($recovery | Where-Object Kind -eq 'CandidateSourceFingerprintMismatch')[0]
Assert-Test $candidateFingerprintMismatch.Passed 'Candidate Source fingerprint mismatch fails before authentication or network'
$candidateTableRestriction=@($recovery | Where-Object Kind -eq 'CandidateSourceTableRestriction')[0]
Assert-Test $candidateTableRestriction.Passed 'Candidate Source create-only mode rejects other table targets'
$publishGuard=@($recovery | Where-Object Kind -eq 'PublishOnlyScopeGuard')[0]
Assert-Test $publishGuard.Passed 'Publish-only mode permits only one table-scoped PublishXml POST'
$publicationStates=@($recovery | Where-Object Kind -eq 'PublicationStateClassification')[0]
Assert-Test $publicationStates.Passed 'RetrieveEntity comparison classifies published, unpublished-only, missing, failed, malformed, and order-insensitive metadata'
$publicationVerifyWriteBlocked=@($recovery | Where-Object Kind -eq 'PublicationVerifyWriteBlocked')[0]
Assert-Test $publicationVerifyWriteBlocked.Passed 'Position publication verification blocks writes before request dispatch'
$privacy=@($recovery | Where-Object Kind -eq 'DiagnosticPrivacy')[0]
Assert-Test $privacy.Passed 'Recovery diagnostics omit token, identity and environment URL'
$diagnosticKeys=@('Operation','Method','ApiPath','TimestampUtc','StatusCode','HttpStatus','DataverseErrorCode','ErrorSummary','RequestId','CorrelationId','AuthenticationChallenge','FailureClass','ExceptionCategory','TransportKind','DispatchStarted','WritesMayHaveOccurred','ReconciliationCompleted','ReconciliationOutcome') | Sort-Object
foreach ($case in $http.Cases) {
    $failure=$case.Diagnostic.Details.HttpFailure
    $name="HTTP $($case.Status) / $($case.Outcome)"
    Assert-Test (-not $case.SecretFound) "$name stdout, stderr, exception and persisted diagnostics exclude secrets"
    Assert-Test ($case.Calls -eq 1 -and $case.Diagnostic.Details.RequestsAttempted.POST -eq 1) "$name no automatic retry"
    Assert-Test ($case.Refreshes -eq 1 -and $case.Request.Fresh -and $case.Request.ExactBearer) "$name expired token refreshed before exact bearer construction"
    Assert-Test ($case.Request.Solution -ceq 'os_sr_bso_rs_support' -and $case.Request.ContentType -ceq 'application/json; charset=utf-8' -and $case.Request.Body.SchemaName -ceq 'os_sr_pos') "$name Position POST construction"
    Assert-Test ($case.Request.Redirects -eq 0 -and $case.Request.SkipHttpErrorCheck) "$name redirects disabled"
    Assert-Test ((@($failure.PSObject.Properties.Name | Sort-Object) -join ',') -ceq ($diagnosticKeys -join ',')) "$name diagnostic schema allowlist"
    Assert-Test ($failure.Method -ceq 'POST' -and $failure.Operation -ceq 'CreateTable' -and $failure.ApiPath -ceq '/api/data/v9.2/EntityDefinitions') "$name original operation preserved"
    Assert-Test ($failure.WritesMayHaveOccurred -and $case.Diagnostic.Details.WritesMayHaveOccurred) "$name uncertain write retained"
    Assert-Test ($failure.ReconciliationOutcome -ceq $case.Outcome -and $failure.ReconciliationCompleted -eq ($case.Outcome -ne 'UNKNOWN')) "$name reconciliation outcome"
    Assert-Test ($failure.StatusCode -eq $(if ($case.Status -eq 0) { $null } else { $case.Status })) "$name original status survives secondary error"
    $timestamp = Get-UtcTimestampFromJson -Json $case.Json
    Assert-Test ($timestamp.Offset -eq [TimeSpan]::Zero) "$name UTC request timestamp"
    if ($case.Status -ne 0) {
        Assert-Test ($failure.RequestId -ceq '11111111-1111-4111-8111-111111111111' -and $failure.CorrelationId -ceq '22222222-2222-4222-8222-222222222222' -and $failure.DataverseErrorCode -ceq '0x80040220') "$name safe IDs and Dataverse code"
    }
    $summaryPattern=switch ($case.Status) { 401 {'Authentication/token'} 403 {'Authorization/privilege'} 400 {'Dataverse rejected'} 408 {'timed out'} 429 {'rate limited'} 500 {'server failure'} 0 {'timed out'} default {'status unavailable'} }
    Assert-Test ($failure.ErrorSummary -match $summaryPattern) "$name trusted status summary"
    Assert-Test (($case.Diagnostic | ConvertTo-Json -Depth 20) -notmatch '"Authorization"\s*:|WWW-Authenticate|Set-Cookie|rawAuthentication|refresh_token\s*=|client_secret\s*=|error_description\s*=|claims\s*=') "$name sensitive headers and bodies omitted"
}
Assert-Test ($http.ExceptionCases.Count -eq 9) 'All requested exception-path diagnostic scenarios executed'
foreach($case in $http.ExceptionCases){ Assert-Test $case.Passed "Exception $($case.Scenario) safe diagnostics and GET-only recovery; class=$($case.FailureClass), category=$($case.ExceptionCategory), state=$($case.State), status=$($case.Status), failed checks=$($case.CheckSummary)" }
Assert-Test (@($http.ExceptionCases | Where-Object { $_.Scenario -eq 'Unknown' -and $null -eq $_.Status -and $_.FailureClass -eq 'UNKNOWN_HTTP_FAILURE' -and $null -eq $_.ReportStatus }).Count -eq 1) 'Unavailable HTTP status remains explicitly UNKNOWN'
Assert-Test (@($http.ExceptionCases | Where-Object { $_.Scenario -eq 'Unknown' -and $_.HttpStatus -eq 'UNKNOWN' -and $_.ReportHttpStatus -eq 'UNKNOWN' }).Count -eq 1) 'UNKNOWN status is retained in serialized diagnostics'
Assert-Test (@($http.ExceptionCases | Where-Object { $_.Scenario -eq 'MalformedBody' -and $_.Status -eq 400 -and $_.ReportStatus -eq 400 -and $_.FailureClass -eq 'HTTP_4XX_VALIDATION' }).Count -eq 1) 'Malformed non-JSON exception body does not leak and preserves HTTP status'
Assert-Test (@($http.ExceptionCases | Where-Object { $_.Scenario -eq 'HttpResponse' -and $_.RequestId -eq '11111111-1111-4111-8111-111111111111' -and $_.CorrelationId -eq '22222222-2222-4222-8222-222222222222' }).Count -ge 5) 'Exception response request and correlation GUIDs are extracted'
Assert-Test (@($http.Cases | Where-Object { $_.Status -eq 302 -and $_.Diagnostic.Details.HttpFailure.FailureClass -eq 'UNKNOWN_HTTP_FAILURE' }).Count -eq 4) 'Unrecognized HTTP status remains an explicit unknown HTTP failure'
Assert-Test (@($http.Cases | Where-Object { $_.Status -eq 408 -and $_.Diagnostic.Details.HttpFailure.FailureClass -eq 'TIMEOUT' }).Count -eq 4) 'HTTP 408 maps to timeout without retry'
foreach ($guard in $http.Guards.GetEnumerator()) { Assert-Test $guard.Value "$($guard.Key) guard" }
Assert-Test ($null -eq $http.UnsafeCode.DataverseErrorCode -and $null -eq $http.UnsafeCode.RequestId -and $http.UnsafeCode.ApiPath -ceq '/api/data/v9.2/EntityDefinitions') 'Risky code, ID and endpoint values omitted'
Assert-Test ($http.OmittedText -ceq 'Untrusted text omitted.' -and $http.OmittedException -notmatch 'synthetic-') 'Untrusted local text and exceptions omitted'
$sourceText=$sourceAst.Extent.Text
Assert-Test ($sourceText.IndexOf('$confirmation = Read-Host') -lt $sourceText.IndexOf('$script:WritesAllowed = $true') -and $sourceText -match 'Ensure-DataverseAccessToken\s+\$script:WritesAllowed = \$true') 'Interactive confirmation and final token check retained'
Write-Output "PASS: $script:Passed synthetic provisioning assertions; no authentication, API calls, or Apply invocation."
