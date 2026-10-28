#requires -Version 7.4
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $root 'scripts\Provision-BsoRsRound1Schedule.ps1'
$tokens = $null
$parseErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw 'Scheduling provisioning script has parser errors.' }

$source = Get-Content -LiteralPath $scriptPath -Raw
$plan = (& $scriptPath -Mode PlanOnly) | ConvertFrom-Json
$passed = 0

function Assert-Test {
    param([bool]$Condition, [string]$Name)
    if (-not $Condition) { throw "FAIL: $Name" }
    $script:passed++
}

Assert-Test ($plan.Table -ceq 'os_sr_intv' -and
    $plan.Solution -ceq 'os_sr_bso_rs_support' -and
    $plan.Ownership -ceq 'UserOwned' -and $plan.TableAudit) 'Plan only targets one audited User-owned table in the existing solution'
Assert-Test ($plan.PrimaryName.LogicalName -ceq 'os_sr_intv_ref' -and
    $plan.PrimaryName.Format -ceq 'INTV-{SEQNUM:8}' -and
    -not $plan.PrimaryName.ContainsPersonalData) 'Use a nonpersonal auto-number primary name'
Assert-Test (@($plan.Fields | Where-Object LogicalName -ceq 'os_sr_intv_rnd').Count -eq 1 -and
    @($plan.Fields | Where-Object { $_.LogicalName -ceq 'os_sr_intv_rnd' -and @($_.Options).Count -eq 1 -and $_.Options[0] -ceq 'Round 1' }).Count -eq 1) 'Support Round 1 only with a single local Choice option'
Assert-Test (@($plan.Fields | Where-Object { $_.LogicalName -in @('os_sr_intv_strt', 'os_sr_intv_end') -and $_.Type -ceq 'DateTime UserLocal' -and $_.Required }).Count -eq 2) 'Require User Local start and end Date/Time'
Assert-Test (@($plan.Fields | Where-Object { $_.LogicalName -ceq 'os_sr_intv_res' -and $_.Type -ceq 'Local Choice' -and -not $_.Required -and (@($_.Options) -join '|') -ceq 'Pending|Pass|Fail' }).Count -eq 1 -and
    @($plan.Fields | Where-Object { $_.LogicalName -ceq 'os_sr_intv_recat' -and $_.Type -ceq 'DateTime UserLocal' -and -not $_.Required }).Count -eq 1 -and
    @($plan.Fields | Where-Object { $_.LogicalName -ceq 'os_sr_intv_rnts' -and $_.Type -ceq 'Memo' -and $_.MaxLength -eq 1000 -and -not $_.Required }).Count -eq 1) 'Plan only includes the three optional interview-result fields'
Assert-Test (@($plan.Fields | Where-Object { $_.LogicalName -ceq 'os_sr_intv_stat' -and $_.Type -ceq 'Local Choice' -and -not $_.Required -and (@($_.Options) -join '|') -ceq 'Proposed|Scheduled|Cancelled|Superseded' }).Count -eq 1 -and
    @($plan.Fields | Where-Object { $_.LogicalName -ceq 'os_sr_intv_rsn' -and $_.Type -ceq 'Memo' -and $_.MaxLength -eq 1000 -and -not $_.Required }).Count -eq 1 -and
    @($plan.Fields | Where-Object { $_.LogicalName -ceq 'os_sr_intv_chg' -and $_.Type -ceq 'DateTime UserLocal' -and -not $_.Required }).Count -eq 1) 'Plan includes only minimal optional scheduling lifecycle metadata'
Assert-Test (@($plan.Relationships | Where-Object { $_.Parent -in @('os_sr_cand', 'os_sr_ta', 'os_sr_loc') -and $_.Required -and $_.Delete -ceq 'Restrict' }).Count -eq 3) 'Require the Candidate, TA, and Location lookups with restricted deletes'
Assert-Test ($plan.Writes -eq 0 -and $source.Contains("MaximumRetryCount = 0") -and
    $source.Contains('Retries = 0')) 'Plan and provisioning use no retry'
Assert-Test ($source.Contains("MSCRM.SolutionName") -and
    $source.Contains('Ensure-SolutionMembership') -and
    $source.Contains('Assert-SolutionMembership') -and
    $source.Contains('RootIncludesSubcomponents = $true')) 'Add the schema to and verify the exact solution'
$readOnlyMode = [regex]::Match($source, '(?s)if \(\$Mode -eq ''ReconcileOnly''\) \{(.*?)\r?\n\}')
Assert-Test ($source.Contains("pac solution add-solution-component") -and
    $source.Contains('--componentType 1') -and
    $readOnlyMode.Success -and
    -not $readOnlyMode.Groups[1].Value.Contains('Ensure-SolutionMembership')) 'Add solution membership only in Apply mode; reconciliation remains read-only'
Assert-Test ($source.Contains("Delete = 'Restrict'") -and
    $source.Contains("OwnershipType = 'UserOwned'") -and
    $source.Contains('IsAuditEnabled = New-AuditSetting')) 'Preserve ownership, auditing, and relationship delete restrictions'
Assert-Test ($source.Contains('`$select=LogicalName,RequiredLevel,IsAuditEnabled&`$filter=LogicalName%20eq%20%27os_sr_intv_rnd%27')) 'Read back required and audit metadata for the Round Choice'
Assert-Test ($source.Contains('LookupAttributeMetadata?') -and
    $source.Contains("ApplicationRequired") -and
    $source.Contains('RequiredLevel,IsAuditEnabled')) 'Read required and audit settings from typed lookup metadata'
Assert-Test ($source.Contains('$generatedLookupNames') -and
    $source.Contains('"$($_.Lookup)Name"')) 'Exclude only Dataverse-generated lookup name companions from custom field reconciliation'
Assert-Test ($source.Contains('$script:MaximumWrites = 10') -and
    $source.Contains('function Ensure-LookupAudit') -and
    $source.Contains('Send-MetadataWrite -Method PUT') -and
    $source.Contains('function Assert-LookupAudit') -and
    $source.Contains('for ($poll = 0; $poll -lt 6; $poll++)')) 'Update each lookup audit flag once and poll readback without retrying writes'
Assert-Test (-not $source.Contains('PublishAllXml') -and
    -not $source.Contains('System Administrator') -and
    -not $source.Contains('pac admin assign-user')) 'Do not publish globally or change role assignment'
Assert-Test ($source.Contains("Outcome = 'SCHEDULING_STORAGE_PROVISIONED'") -and
    $source.Contains("'SCHEDULING_STORAGE_NOT_PROVISIONED'")) 'Report storage state explicitly'
Assert-Test ($source.Contains('function Ensure-InterviewResultAttributes') -and
    $source.Contains('function Assert-InterviewResultAttributes') -and
    $source.Contains('InterviewResultChoiceValues = $resultState.ChoiceValues') -and
    $source.Contains('do not retry before read-only reconciliation')) 'Add the existing-table fields with authoritative metadata readback and no automatic retry'
Assert-Test ($source.Contains('function Ensure-SchedulingLifecycleAttributes') -and
    $source.Contains('function Assert-SchedulingLifecycleAttributes') -and
    $source.Contains('SchedulingStatusChoiceValues = $lifecycleState.ChoiceValues') -and
    $source.Contains("LogicalName = 'os_sr_intv_stat'") -and
    $source.Contains("LogicalName = 'os_sr_intv_rsn'") -and
    $source.Contains("LogicalName = 'os_sr_intv_chg'") -and
    $source.Contains('Cancellation / Reschedule Reason') -and
    $source.Contains('Scheduling Status Changed At')) 'Provision and reconcile the audited, minimal lifecycle fields on the existing schedule table'
Assert-Test ($source.Contains("LogicalName = 'os_sr_intv_res'") -and
    $source.Contains("LogicalName = 'os_sr_intv_recat'") -and
    $source.Contains("LogicalName = 'os_sr_intv_rnts'") -and
    $source.Contains("Value = `$null") -and
$source.Contains("DisplayName = New-Label -Text 'Result Recorded At'")) 'Use stable os_sr_ names and allow Dataverse to allocate Choice values'
Assert-Test ($source -notmatch 'https?://[A-Za-z0-9.-]+\.crm\d?\.dynamics\.com' -and
    $source -notmatch 'org[0-9a-f]{6,}\.crm\d?\.dynamics\.com') 'Keep tenant-specific organization URLs out of the provisioning source'
Assert-Test ($source.Contains("Host -notmatch '^org[0-9a-f]{6,}\.crm\d?\.dynamics\.com$'") -and
    $source.Contains('$script:Target.OrganizationUrl = $organizationUri.GetLeftPart([UriPartial]::Authority)')) 'Accept only an HTTPS Dataverse org host supplied by and reconciled with PAC'

Write-Output "Phase 4C scheduling provisioning checks passed: $passed"
