#requires -Version 7.4
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$script:Passed = 0
function Assert-Test([bool]$Condition, [string]$Name) {
    if (-not $Condition) { throw "FAIL: $Name" }
    $script:Passed++
}
$path = Join-Path $root 'scripts\Provision-BsoRsOperationReceipt.ps1'
$source = Get-Content -Raw $path
$plan = Get-Content -Raw (Join-Path $root 'docs\PHASE_3C_OPERATION_RECEIPT_PLAN.json') | ConvertFrom-Json
$manifest = Get-Content -Raw (Join-Path $root 'docs\PHASE_3A_CANDIDATE_CORE_METADATA_PLAN.json') | ConvertFrom-Json
$output = & $path | ConvertFrom-Json
Assert-Test ($output.Result -ceq 'LOCAL_PLAN_ONLY' -and $output.Requests.GET -eq 0 -and $output.Requests.POST -eq 0) 'PlanOnly makes zero requests'
Assert-Test ($output.Payloads.Count -eq 3 -and $output.MaximumWrites -eq 5) 'Three metadata creates plus separately gated primary and lookup metadata corrections'
Assert-Test ($output.Payloads[0].Path -ceq 'EntityDefinitions') 'Table first'
Assert-Test ($output.Payloads[1].Path -ceq 'RelationshipDefinitions') 'Candidate lookup second'
Assert-Test ($output.Payloads[2].Path -ceq "EntityDefinitions(LogicalName='os_sr_oprc')/Keys") 'Key third'
$table = $output.Payloads[0].Body
Assert-Test ($table.SchemaName -ceq 'os_sr_oprc' -and $table.OwnershipType -ceq 'UserOwned') 'Dedicated user-owned infrastructure table'
Assert-Test ($table.IsAuditEnabled.Value -eq $true -and -not $table.HasNotes -and -not $table.HasActivities) 'Audited with no notes/activities'
Assert-Test ($table.Attributes.Count -eq 9) 'Only minimum scalar evidence'
Assert-Test (@($table.Attributes | Where-Object SchemaName -Match 'email|phone|notes|reason|payload').Count -eq 0) 'No raw contact/free-text evidence fields'
$correlation = @($table.Attributes | Where-Object SchemaName -CEQ 'os_sr_oprc_corid')
Assert-Test ($correlation.Count -eq 1 -and $correlation[0].'@odata.type' -ceq 'Microsoft.Dynamics.CRM.StringAttributeMetadata' -and $correlation[0].MaxLength -eq 36) 'Canonical GUID stored as supported String key'
Assert-Test ($output.Payloads[2].Body.KeyAttributes.Count -eq 1 -and $output.Payloads[2].Body.KeyAttributes[0] -ceq 'os_sr_oprc_corid') 'Global correlation uniqueness'
Assert-Test ($output.Payloads[1].Body.CascadeConfiguration.Delete -ceq 'Restrict') 'Candidate deletion cannot destroy receipts'
Assert-Test ($output.Payloads[1].Body.ReferencedEntity -ceq 'os_sr_cand' -and $output.Payloads[1].Body.ReferencingEntity -ceq 'os_sr_oprc') 'Only new receipt relationship'
Assert-Test ($output.AutomaticRetries -eq 0 -and $source -match 'MaximumRetryCount = 0') 'No automatic retry'
Assert-Test ($source -match "ValidateSet\('GET', 'POST', 'PUT'\)" -and $source -match 'CompleteReceipt') 'One separately gated metadata correction; no destructive transport'
Assert-Test ($source -match 'FileMode\]::CreateNew' -and $source -match "DISPATCH_RESERVED" -and $source -match 'Flush\(\$true\)') 'Durable consumed dispatch journal before network'
Assert-Test ($source.IndexOf('$entry.State = ''DISPATCH_RESERVED''') -lt $source.IndexOf('$response = Invoke-WebRequest')) 'Reservation precedes dispatch'
Assert-Test ($source -match 'PlanSha256' -and $source -match 'PayloadSha256' -and $source -match 'GET_RECONCILED') 'Pinned plan/payload and readback evidence'
Assert-Test ($source -match 'Assert-PacIdentity' -and $source -match 'Get-ValidatedToken' -and $source -match 'Get-ReconciliationSnapshot') 'PAC/credential/WhoAmI guards reused'
Assert-Test ($source -match 'Repaired attribute identity differs' -and $source -match 'IsOptimisticConcurrencyEnabled') 'Retained repair identities and concurrency checked'
Assert-Test ($manifest.globalChoice.options.Count -eq 6 -and $manifest.callOutcomeChoice.options.Count -eq 3) 'Current exact Choice source properties'
Assert-Test ($source -match 'ExpectedOptions \$manifest.globalChoice.options') 'Candidate Choice comes from actual manifest property'
Assert-Test ($source -match 'script:WriteStages = .*List\[string\]' -and $source -match '\$candidateResult = \$candidate') 'Shared read helper state initialized'
Assert-Test ($source -notmatch "PublishAllXml|Method DELETE|Method PATCH") 'No schema replacement/publication'
Assert-Test ($source -match "prior.Writes\[0\].State -cne 'ACKNOWLEDGED'" -and $source -match 'AllowKnownPrimaryDefaults') 'Correction requires retained acknowledged create and exact known defaults'
Assert-Test ($table.PSObject.Properties.Name -cnotcontains 'PrimaryNameAttribute' -and $table.Attributes[0].AttributeType -ceq 'String') 'Use prior-art typed primary attribute rather than read-only table selector'
$t = $null; $e = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$t, [ref]$e)
Assert-Test ($e.Count -eq 0) 'Runner parses'
"PASS: $script:Passed synthetic Phase 3C receipt assertions; PlanOnly and source/payload checks only; no authentication/network."
