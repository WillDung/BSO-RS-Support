#requires -Version 7.4
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$plugin = Get-Content -Raw (Join-Path $root 'solutions\CandidateCore\DataversePlugin.cs')
$sdk = Get-Content -Raw (Join-Path $root 'tests\CandidateCoreSdk\Program.cs')
$contract = Get-Content -Raw (Join-Path $root 'docs\PHASE_3C_API_CONTRACT.json')
$script:Passed = 0

function Assert-Test([bool]$Condition, [string]$Name) {
    if (-not $Condition) { throw "FAIL: $Name" }
    $script:Passed++
}

$search = [regex]::Match($plugin, '(?s)FindTrustedParent\(.*?\n\s*private static bool IsActionForOperation')
Assert-Test ($plugin -match 'IntentKey = "os_sr_cact\.validated_intent"' -and
    $plugin -match 'MaximumParentContexts = 8') 'Private marker key and bounded ancestor limit are stable'
Assert-Test ($search.Success -and $search.Value -match 'context\.ParentContext' -and
    $search.Value -match 'searched < MaximumParentContexts' -and
    $search.Value -match 'ancestor\.ParentContext') 'Guard traverses only the bounded ParentContext chain'
Assert-Test ($search.Value -match 'ancestor\.MessageName != "os_sr_cact"' -and
    $search.Value -match 'ancestor\.Stage != 30' -and $search.Value -match 'ancestor\.Mode != 0' -and
    $search.Value -match 'ancestor\.IsInTransaction' -and
    $search.Value -match 'ancestor\.Depth > 0 && ancestor\.Depth < context\.Depth' -and
    $search.Value -match 'ancestor\.UserId != context\.UserId' -and
    $search.Value -match 'ancestor\.InitiatingUserId != context\.InitiatingUserId') `
    'Trusted ancestor requires approved API, synchronous transaction, nested depth, and caller identity'
Assert-Test ($search.Value -notmatch 'ancestor\.SharedVariables|expectedIntent' -and
    $search.Value -match 'RegistrationFailure\(ancestor, context, factory\)') `
    'SharedVariables marker is superseded by server-owned registration verification'
Assert-Test ($search.Value -match 'IsActionForOperation\(ancestor, operation\)' -and
    $plugin -match 'action == "CreateCandidate"' -and $plugin -match 'action == "RecordCall"' -and
    $plugin -match 'action == "ProceedToScheduling"') 'Trusted Custom API actions are constrained to the protected mutation category'
Assert-Test ($plugin -match 'context\.SharedVariables\[ProtectCandidateCore\.IntentKey\] = ProtectCandidateCore\.Intent\(message, row\)' -and
    $plugin -match 'Authorize\("Create", row\);' -and $plugin -match 'Authorize\("Update", row\);' -and
    $plugin -match 'finally \{ context\.SharedVariables\.Remove\(ProtectCandidateCore\.IntentKey\); \}') `
    'ApplyCandidateAction creates the transaction-scoped intent before protected writes and removes it afterward'
Assert-Test ($plugin -match 'CC_GUARD_TRUSTED_PARENT_FOUND:ANCESTOR_HOPS' -and
    $plugin -match 'CC_GUARD_TRUSTED_PARENT_NOT_FOUND:ANCESTOR_HOPS' -and
    $plugin -notmatch 'Trace\(.*IntentKey|Trace\(.*expectedIntent|Trace\(.*marker') `
    'Tracing reports safe parent status and hop category without marker values'
Assert-Test ($contract -notmatch 'validated_intent|IntentKey|ParentContext') `
    'The private marker is absent from Custom API metadata contract'
Assert-Test ($sdk -match 'Trusted Candidate Create marker one ancestor up is accepted' -and
    $sdk -match 'Trusted Candidate Create marker two ancestors up is accepted' -and
    $sdk -match 'eight contexts and fails closed beyond the bound') 'SDK tests cover variable ancestor distance and fail-closed traversal bound'
Assert-Test ($sdk -match 'externalTag' -and $sdk -match 'injectedPrivateKey' -and
    $sdk -match 'tagWithUntrustedParent' -and $sdk -match 'malformedMarkerParent' -and
    $sdk -match 'unrelatedParent') 'SDK tests reject caller tag, current-context marker, malformed marker, and unrelated parent injection'
Assert-Test ($sdk -match 'Operation Receipt child write' -and $sdk -match 'Call Log child write' -and
    $sdk -match 'Status History child write' -and $sdk -match 'Candidate Answered update') `
    'SDK tests accept legitimate Candidate, Call Log, History, and Receipt child writes by action'
Assert-Test ($sdk -match 'Private mutation marker is removed and never persisted, returned, or traced' -and
    $sdk -match 'TRUSTED_PARENT_FOUND:ANCESTOR_HOPS') 'SDK tests verify marker lifetime and safe trace category'
Assert-Test ($plugin -match 'extension\.LogicalName != "sdkmessageprocessingstep"' -and
    $plugin -match 'Retrieve\("sdkmessageprocessingstep", extension\.Id' -and
    $plugin -match 'Retrieve\("plugintype", handler\.Id' -and
    $plugin -match 'Retrieve\("pluginassembly", assemblyReference\.Id' -and
    $plugin -match 'Retrieve\("pluginpackage", packageReference\.Id') `
    'Trust follows the server-owned step type assembly package chain without fixed registration IDs'
Assert-Test ($plugin -match 'CreateOrganizationService\(context\.UserId\)' -and
    $plugin -match 'Tuple.Create\(context.OrganizationId, context.UserId, extension.Id\)' -and
    $plugin -match 'RegistrationCache.Count >= 128' -and $plugin -match 'AddMinutes\(1\)' -and
    $plugin -match 'return "REGISTRATION_READ_FAILED"') 'Calling-user positive cache is bounded, expiring and fail closed'

"PASS: $script:Passed Phase 3D-R4M trusted-parent source assertions; no authentication/network."
