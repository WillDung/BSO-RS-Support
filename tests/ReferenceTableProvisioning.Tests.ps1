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
    foreach ($functionName in @('Ensure-DataverseAccessToken','Invoke-PrivateOperation','Get-SafeDiagnosticText','Get-SafeErrorMessage','Get-SafeResponseHeader','New-SafeHttpFailure','Get-StoppedDetails','Get-ReconciliationSummary','Write-Result','Invoke-DataverseRequest')) {
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
    function New-PrivatePipeline {
        $pipeline=[System.Management.Automation.PowerShell]::Create()
        $null=$pipeline.AddScript({
            param($state)
            $script:State=$state
            function Invoke-RestMethod {
                [CmdletBinding()]
                param($Method,$Uri,$Headers,$SkipHeaderValidation,$MaximumRedirection,$SkipHttpErrorCheck,$StatusCodeVariable,$ResponseHeadersVariable,$TimeoutSec,$ContentType,$Body)
                $script:State.Calls++
                if ($Method -eq 'POST') {
                    $script:State.PostCalls++
                    $script:State.Request=[ordered]@{Method=$Method;Uri=[string]$Uri;ExactBearer=($Headers.Authorization -ceq ('Bearer '+$script:State.Secrets[0]));Fresh=($script:State.ExpiresOn -gt [DateTimeOffset]::UtcNow.AddMinutes(5));Solution=$Headers['MSCRM.SolutionUniqueName'];ContentType=$ContentType;Redirects=$MaximumRedirection;SkipHttpErrorCheck=$SkipHttpErrorCheck;Body=(ConvertFrom-Json $Body)}
                }
                Write-Warning $script:State.UnsafeText
                Write-Information $script:State.UnsafeText
                Write-Verbose $script:State.UnsafeText
                if ($script:State.Timeout) { throw [TimeoutException]::new($script:State.UnsafeText) }
                Set-Variable -Name $StatusCodeVariable -Value $script:State.Status -Scope 1
                Set-Variable -Name $ResponseHeadersVariable -Value @{
                    'WWW-Authenticate'=('Bearer error="'+$script:State.Secrets[0]+'", error_description="'+$script:State.UnsafeText+'"')
                    'Authorization'=$script:State.UnsafeText;'Set-Cookie'=$script:State.UnsafeText
                    'x-ms-service-request-id'='11111111-1111-4111-8111-111111111111'
                    'x-ms-correlation-request-id'='22222222-2222-4222-8222-222222222222'
                } -Scope 1
                [pscustomobject]@{error=[pscustomobject]@{code='0x80040220';message=$script:State.UnsafeText};rawAuthentication=$script:State.UnsafeText}
            }
        }).AddArgument($script:TransportState)
        $null=$pipeline.Invoke()
        $pipeline.Commands.Clear()
        $pipeline
    }
    function Get-TableMetadataIfPresent {
        if ($script:Outcome -eq 'UNKNOWN') {
            $script:TransportState.Timeout=$true
            Invoke-DataverseRequest -Method GET -Path EntityDefinitions | Out-Null
        }
        if ($script:Outcome -eq 'ABSENT') { return $null }
        [pscustomobject]@{LogicalName='os_sr_pos'}
    }
    function Assert-TableMetadata {
        param($Metadata)
        if ($script:Outcome -eq 'PARTIAL') { throw 'Synthetic metadata is incomplete.' }
    }
    function Assert-SolutionMembership { param($SolutionId,$Metadata) }
    function Reset-SyntheticState {
        $script:Refreshes=0;$script:LastHttpFailure=$null
        $script:AccessToken='expired-synthetic';$script:AccessTokenExpiresOn=[DateTimeOffset]::UtcNow.AddMinutes(-1)
        $script:RequestCounts=@{GET=0;POST=0};$script:WriteResults=[System.Collections.Generic.List[object]]::new()
        $script:WritesAllowed=$true;$script:WritesStarted=$false
        $script:TransportState=@{Calls=0;PostCalls=0;Request=$null;Status=0;Timeout=$false;Secrets=$script:Secrets;UnsafeText=$script:UnsafeText;ExpiresOn=[DateTimeOffset]::MinValue}
    }
    function Test-SyntheticHttpChecks {
        $results=[System.Collections.Generic.List[object]]::new()
        foreach ($status in @(401,403,400,429,500,0,302)) {
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
        [pscustomobject]@{Cases=$results.ToArray();Guards=$guardResults;UnsafeCode=$unsafeCode;OmittedText=(Get-SafeDiagnosticText $script:UnsafeText);OmittedException=(Get-SafeErrorMessage ([System.Management.Automation.ErrorRecord]::new([Exception]::new($script:UnsafeText),'Synthetic',[System.Management.Automation.ErrorCategory]::NotSpecified,$null)))}
    }
    Export-ModuleMember -Function Test-SyntheticHttpChecks
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
    try { $http=Test-SyntheticHttpChecks } finally { Stop-Transcript | Out-Null }
    $transcriptText=Get-Content -LiteralPath $transcript -Raw
    Assert-Test ($transcriptText -notmatch 'synthetic\.(access\.token-marker)|synthetic-(refresh-marker|client-secret|auth-code|cookie-marker|basic-marker)') 'Transcript excludes synthetic secrets'
}
finally { Remove-Item -LiteralPath $transcript -Force; Remove-Module $httpModule }
$diagnosticKeys=@('Operation','Method','ApiPath','TimestampUtc','StatusCode','DataverseErrorCode','ErrorSummary','RequestId','CorrelationId','WritesMayHaveOccurred','ReconciliationCompleted','ReconciliationOutcome') | Sort-Object
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
    $summaryPattern=switch ($case.Status) { 401 {'Authentication/token'} 403 {'Authorization/privilege'} 400 {'metadata validation'} 429 {'Rate limited'} 500 {'Server failure'} 0 {'Transport failure or timeout'} default {'Unexpected HTTP response'} }
    Assert-Test ($failure.ErrorSummary -match $summaryPattern) "$name trusted status summary"
    Assert-Test (($case.Diagnostic | ConvertTo-Json -Depth 20) -notmatch '"Authorization"\s*:|WWW-Authenticate|Cookie|rawAuthentication|Bearer') "$name sensitive headers and bodies omitted"
}
foreach ($guard in $http.Guards.GetEnumerator()) { Assert-Test $guard.Value "$($guard.Key) guard" }
Assert-Test ($null -eq $http.UnsafeCode.DataverseErrorCode -and $null -eq $http.UnsafeCode.RequestId -and $http.UnsafeCode.ApiPath -ceq '/api/data/v9.2/EntityDefinitions') 'Risky code, ID and endpoint values omitted'
Assert-Test ($http.OmittedText -ceq 'Untrusted text omitted.' -and $http.OmittedException -notmatch 'synthetic-') 'Untrusted local text and exceptions omitted'
$sourceText=$sourceAst.Extent.Text
Assert-Test ($sourceText.IndexOf('$confirmation = Read-Host') -lt $sourceText.IndexOf('$script:WritesAllowed = $true') -and $sourceText -match 'Ensure-DataverseAccessToken\s+\$script:WritesAllowed = \$true') 'Interactive confirmation and final token check retained'
Write-Output "PASS: $script:Passed synthetic provisioning assertions; no authentication, API calls, or Apply invocation."
