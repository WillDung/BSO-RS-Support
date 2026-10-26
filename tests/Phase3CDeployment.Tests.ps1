#requires -Version 7.4
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$sourcePath = Join-Path $root 'scripts\Deploy-BsoRsCandidateOperations.ps1'
$source = Get-Content -Raw $sourcePath
$contract = Get-Content -Raw (Join-Path $root 'docs\PHASE_3C_API_CONTRACT.json') | ConvertFrom-Json
$script:Passed = 0
function Assert-Test([bool]$Condition, [string]$Name) {
    if (-not $Condition) { throw "FAIL: $Name" }
    $script:Passed++
}
$t = $null; $e = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($sourcePath, [ref]$t, [ref]$e)
Assert-Test ($e.Count -eq 0) 'Deployment runner parses'
Assert-Test ($contract.uniqueName -ceq 'os_sr_cact' -and -not $contract.isFunction -and $contract.bindingType -eq 0) 'Approved unbound Action'
Assert-Test ($contract.isPrivate -and $contract.allowedCustomProcessingStepType -eq 0) 'Private discovery with no extension steps'
Assert-Test ($contract.executePrivilegeName -ceq 'prvWriteos_sr_cand') 'Existing generated Write privilege'
Assert-Test ($contract.inputs.Count -eq 13 -and $contract.outputs.Count -eq 5) 'Exact approved parameter/output counts'
Assert-Test (@($contract.inputs | Where-Object { -not $_.optional }).name -join ',' -ceq 'ActionType,CorrelationId') 'Only common mandatory parameters are metadata-required'
Assert-Test (@($contract.inputs | Where-Object name -CEQ 'CorrelationId')[0].type -eq 12) 'External CorrelationId remains GUID'
Assert-Test ($contract.protectedTables.Count -eq 4) 'Only Candidate Core and receipt tables protected'
Assert-Test ($source -match 'MaximumRetryCount = 0' -and $source -match 'MaximumRedirection = 0') 'No transport retry or redirect'
Assert-Test ($source -match 'FileMode\]::CreateNew' -and $source -match 'DISPATCH_RESERVED' -and $source -match 'Flush\(\$true\)') 'Durable per-dispatch consumption journal'
Assert-Test ($source -match 'Get-RegistrationNavigation' -and $source -match 'ReferencingEntityNavigationPropertyName') 'Resolve actual case-sensitive metadata navigation'
Assert-Test ($source -match 'AssemblySha256' -and $source -match 'ContractSha256' -and $source -match 'ReceiptPlanSha256' -and $source -match 'CoreManifestSha256') 'Predeployment immutable scope fingerprints'
Assert-Test ($source -notmatch 'Invoke-DeploymentRequest -Method (DELETE|PUT)' -and
    $source -match 'Non-registration write path rejected') 'Original registration path remains create-only'
Assert-Test ($source -match "ValidateSet\('GET', 'POST', 'PATCH'\)" -and
    $source -match "DeploymentMode -cne 'ApplyAssemblyUpdate'" -and
    $source -match 'MaximumPatchDispatches = 1' -and
    $source -match 'ExpectedCurrentAssemblySha256' -and
    $source -match 'ExpectedNewAssemblySha256') 'Separate assembly update mode pins old/new hashes and one PATCH ceiling'
Assert-Test ($source -match "State = 'DISPATCH_RESERVED'" -and
    $source -match 'FileMode\]::CreateNew' -and
    $source -match 'MaximumRetryCount = 0' -and
    $source.Contains('Path -cne "pluginassemblies($($script:assemblyUpdatePlan.AssemblyId))"')) 'Assembly update reserves one target dispatch with zero retries'
Assert-Test ($source -match 'ExpectedNewAssemblySha256' -and
    $source -match 'GET-reconciled' -or $source -match "State = 'GET_RECONCILED'") 'Assembly update requires post-dispatch GET reconciliation'
Assert-Test ($source -match 'AssemblyName\]::GetAssemblyName' -and $source -match 'GetPublicKeyToken' -and
    $source -match 'New assembly name, version, or signing identity') 'Assembly update preserves pinned name/version/signing identity'
Assert-Test ($source -match 'if \(\$Method -ceq ''PATCH''\) \{ \$entry = \$script:deploymentJournal\.Writes\[0\] \}' -and
    $source -match 'AssemblyUpdateDispatches =') 'PATCH response status is attached to the single durable dispatch entry'
Assert-Test ($source -match 'Assert-RegistrationReadback -Write \$write' -and $source -match 'Assert-RegistrationMembership' -and $source -match 'Assert-RegistrationInventoryExact') 'Immediate readback and full final membership/inventory'
Assert-Test ($source -match 'apiComponentTypes' -and $source -match '\$metadata.ObjectTypeCode') 'Custom API membership codes resolved from actual metadata, not stale static enum assumptions'
Assert-Test ($source -match 'one failed/uncertain registration GET reconciliation' -and $source -match 'throw \$original') 'Failed/uncertain write reconciles and stops'
Assert-Test ($source -match 'PrimaryIdAttribute -cne' -and $source -match "Required direct-write guard hook unavailable") 'Fail closed on missing baseline guard assumptions'
Assert-Test ($source -match "foreach \(\`$messageName in @\('Associate', 'Disassociate'\)\)") 'Protect lookup reassociation outside normal update paths'
$plugin = Get-Content -Raw (Join-Path $root 'solutions\CandidateCore\DataversePlugin.cs')
Assert-Test ($plugin -match 'context.UserId != context.InitiatingUserId' -and $plugin -match 'CreateOrganizationService\(context.InitiatingUserId\)') 'No implicit execution-user elevation'
Assert-Test ($plugin -match 'IfRowVersionMatches' -and $plugin -match 'RequireTransaction' -and
    $plugin -notmatch 'isauditenabled|AUDIT_ACTIVATION_PENDING') 'Conditional writes retain transaction gate without organization-audit runtime blocker'
Assert-Test ($plugin -match 'RegistrationFailure' -and $plugin -match 'ancestor.OwningExtension' -and
    $plugin -match 'MaximumParentContexts = 8' -and
    $plugin -match 'DIRECT_WRITE_GUARD_REJECTED:' -and $plugin -match 'CC_GUARD_REJECTED:') 'Server guard checks validated parent intent and emits sanitized rejection categories'
Assert-Test ($plugin -notmatch 'trace.Trace\([^;]*(Fingerprint|CandidateName|CandidateEmail|InputParameters)') 'No raw input/PII fingerprint tracing'
Assert-Test ($source -notmatch "PublishAllXml|PublishXml -|roles\?.*POST") 'No publication or role-write path'
"PASS: $script:Passed synthetic Phase 3C deployment/contract assertions; source/contract checks, no authentication/network."
