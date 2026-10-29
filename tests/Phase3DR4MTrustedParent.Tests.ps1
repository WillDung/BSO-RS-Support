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

$search = [regex]::Match($plugin, '(?s)HasTrustedAncestor\(.*?\n\s*private static bool IsActionForOperation')
Assert-Test ($plugin -notmatch 'IntentKey|SharedVariables' -and
    $plugin -match 'MaximumParentContexts = 8') 'MVP omits mutation markers and retains a bounded ancestor limit'
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
Assert-Test ($search.Value -notmatch 'ancestor\.SharedVariables|expectedIntent|RegistrationFailure|OwningExtension' -and
    $plugin -notmatch 'ResolveGuardRegistration|CreateOrganizationService\(context\.UserId\)') `
    'Historical guard source uses server-owned ParentContext predicates without runtime registration metadata reads'
Assert-Test ($search.Value -match 'IsActionForOperation\(ancestor, operation\)' -and
    $plugin -match 'action == "CreateCandidate"' -and $plugin -match 'action == "RecordCall"' -and
    $plugin -match 'action == "ProceedToScheduling"') 'Trusted Custom API actions are constrained to the protected mutation category'
Assert-Test ($plugin -notmatch 'SharedVariables|IntentKey|Authorize\(' -and
    $plugin -match 'CreateOrganizationService\(context\.InitiatingUserId\)' -and
    $plugin -match 'CreateOrganizationService\(null\)' -and
    $plugin -match 'CandidateOperation\.AllowsMutation') `
    'Current API uses caller reads and a matrix-constrained SYSTEM write service without markers'
Assert-Test ($plugin -match 'CC_GUARD_TRUSTED_PARENT_FOUND:ANCESTOR_HOPS' -and
    $plugin -match 'CC_GUARD_TRUSTED_PARENT_NOT_FOUND:ANCESTOR_HOPS' -and
    $plugin -notmatch 'Trace\(.*IntentKey|Trace\(.*expectedIntent|Trace\(.*marker') `
    'Tracing reports safe parent status and hop category without marker values'
Assert-Test ($contract -notmatch 'validated_intent|IntentKey|ParentContext') `
    'The private marker is absent from Custom API metadata contract'
Assert-Test ($sdk -match 'Trusted Candidate Create is accepted without marker or registration cache' -and
    $sdk -match 'Trusted Candidate Create marker two ancestors up is accepted' -and
    $sdk -match 'eight contexts and fails closed beyond the bound') 'SDK tests cover variable ancestor distance and fail-closed traversal bound'
Assert-Test ($sdk -match 'externalTag' -and $sdk -match 'injectedPrivateKey' -and
    $sdk -match 'tagWithUntrustedParent' -and $sdk -match 'malformedMarkerParent' -and
    $sdk -match 'unrelatedParent') 'SDK tests reject caller tag, current-context marker, malformed marker, and unrelated parent injection'
Assert-Test ($sdk -match 'Operation Receipt child write' -and $sdk -match 'Call Log child write' -and
    $sdk -match 'Status History child write' -and $sdk -match 'Candidate Answered update') `
    'SDK tests accept legitimate Candidate, Call Log, History, and Receipt child writes by action'
Assert-Test ($sdk -match 'MVP operation does not create, persist, return, trace, or require the superseded marker' -and
    $sdk -match 'Candidate Core handler obtains its SYSTEM service after validating API context' -and
    $sdk -match 'packageApiParent\.ServiceFactorySelections\.Contains\(null\)' -and
    $plugin -match 'CreateOrganizationService\(null\)') 'SDK tests verify marker independence and the matrix-constrained SYSTEM path'
Assert-Test ($plugin -match 'RegisteredWriteCode\(context\.MessageName, context\.PrimaryEntityName\)' -and
    $plugin -match 'context\.MessageName == "Associate"' -and
    $plugin -notmatch 'sdkmessageprocessingstep|pluginpackage|OwningExtension') `
    'MVP child write mapping is package-known and contains no runtime registration lookup'

"PASS: $script:Passed Phase 3D-R4M trusted-parent source assertions; no authentication/network."
