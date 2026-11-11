$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

function Assert-Test([bool]$condition, [string]$message) {
    if (-not $condition) { throw "FAIL: $message" }
    $script:checks++
}

$script:checks = 0
$schemaPath = Join-Path $root 'solutions\Entities\os_sr_avq\AvailabilityQuery.schema.json'
$flowPath = Join-Path $root 'solutions\AvailabilityQuery\availability-flow.contract.json'
$environmentPath = Join-Path $root 'solutions\AvailabilityQuery\availability-environment-variables.json'
$retentionPath = Join-Path $root 'solutions\AvailabilityQuery\availability-query-retention.json'
$rolePath = Join-Path $root 'solutions\AvailabilityQuery\availability-role-delta.json'
$registrationPath = Join-Path $root 'solutions\AvailabilityQuery\availability-plugin-registration.contract.json'
$resultApiPath = Join-Path $root 'solutions\AvailabilityQuery\availability-result-api.contract.json'
$pluginPath = Join-Path $root 'solutions\AvailabilityQuery\AvailabilityQueryPlugin.cs'
$rulesPath = Join-Path $root 'solutions\AvailabilityQuery\AvailabilityRules.cs'
$adapterPath = Join-Path $root 'solutions\AvailabilityQuery\OutlookMeetingTimesAdapter.cs'
$driftPath = Join-Path $root 'solutions\AvailabilityQuery\ReferenceDriftPolicy.cs'
$rendererPath = Join-Path $root 'solutions\AvailabilityQuery\AvailabilityConfigurationRenderer.cs'
$consolePath = Join-Path $root 'solutions\CandidateConsole\WebResources\os_\bso\candidate-console-availability.js'
$htmlPath = Join-Path $root 'solutions\CandidateConsole\WebResources\os_\bso\candidate-console.html'
$configPath = Join-Path $root 'solutions\CandidateConsole\WebResources\os_\bso\candidate-console-environment.js'
$supersededConnectorPath = Join-Path $root 'solutions\AvailabilityQuery\graph-scheduling.openapi.json'
$flowDefinitionPath = Join-Path $root 'solutions\AvailabilityQuery\os_sr_avchk.clientdata.json'

$schema = Get-Content -LiteralPath $schemaPath -Raw | ConvertFrom-Json -AsHashtable
$flow = Get-Content -LiteralPath $flowPath -Raw | ConvertFrom-Json -AsHashtable
$environment = Get-Content -LiteralPath $environmentPath -Raw | ConvertFrom-Json -AsHashtable
$retention = Get-Content -LiteralPath $retentionPath -Raw | ConvertFrom-Json -AsHashtable
$role = Get-Content -LiteralPath $rolePath -Raw | ConvertFrom-Json -AsHashtable
$registration = Get-Content -LiteralPath $registrationPath -Raw | ConvertFrom-Json -AsHashtable
$resultApi = Get-Content -LiteralPath $resultApiPath -Raw | ConvertFrom-Json -AsHashtable

Assert-Test ($schema.status -eq 'PROPOSED_SOURCE_OFFLINE_NOT_PROVISIONED') 'Schema source remains clearly offline.'
Assert-Test ($schema.solutionUniqueName -eq 'os_sr_bso_rs_support') 'Schema targets the existing P0 Solution.'
Assert-Test ($schema.table.logicalName -eq 'os_sr_avq' -and $schema.table.ownership -eq 'UserOwned') 'Availability Query identity and ownership are exact.'
Assert-Test (-not $schema.table.auditEnabled -and $schema.table.retentionDays -eq 30) 'Audit and approved retention are explicit.'
Assert-Test ($schema.table.primaryName.logicalName -eq 'os_sr_avq_ref' -and $schema.table.primaryName.format -eq 'AVQ-{SEQNUM:8}') 'Primary AutoNumber contract is exact.'
Assert-Test (@($schema.table.fields | Where-Object logicalName -eq 'os_sr_avq_ta').Count -eq 1) 'Required TA lookup exists.'
Assert-Test (@($schema.table.fields | Where-Object logicalName -eq 'os_sr_avq_loc').Count -eq 1) 'Optional Location lookup exists.'
Assert-Test (@($schema.table.fields | Where-Object { $_.logicalName -match 'cand|intv' }).Count -eq 0) 'No Candidate or Interview Schedule fields exist.'
Assert-Test (@($schema.table.fields | Where-Object { $_.logicalName -match 'provider|payload|email' }).Count -eq 0) 'No provider payload or mailbox-address fields exist.'
Assert-Test (@($schema.table.fields | Where-Object logicalName -eq 'os_sr_avq_slts').Count -eq 1) 'Only computed slot results are persisted.'
Assert-Test (@($schema.table.fields.logicalName | Sort-Object) -join ',' -eq 'os_sr_avq_cat,os_sr_avq_corr,os_sr_avq_dead,os_sr_avq_dur,os_sr_avq_end,os_sr_avq_err,os_sr_avq_exp,os_sr_avq_loc,os_sr_avq_mod,os_sr_avq_qat,os_sr_avq_rsn,os_sr_avq_slts,os_sr_avq_stat,os_sr_avq_strt,os_sr_avq_ta') 'Availability Query includes only the approved operational fields and security v2 correlation/clock metadata.'
Assert-Test (@($schema.table.relationships | ForEach-Object schemaName) -join ',' -eq 'os_sr_ta_avq,os_sr_loc_avq') 'Only TA and Location relationships exist.'
Assert-Test (@($schema.table.relationships | Where-Object { $_.cascadeDelete -ne 'Restrict' -or $_.cascadeAssign -ne 'NoCascade' -or $_.cascadeShare -ne 'NoCascade' -or $_.cascadeUnshare -ne 'NoCascade' -or $_.cascadeReparent -ne 'NoCascade' }).Count -eq 0) 'Relationship cascades are restrictive and non-cascading.'

Assert-Test (-not (Test-Path -LiteralPath $supersededConnectorPath)) 'Superseded custom connector source is absent.'
Assert-Test ($flow.status -eq 'DEPLOYED_FLOW_ON_ATOMIC_API_HANDOFF_UI_OFF_RUNTIME_NOT_ACCEPTED' -and
    $flow.deploymentState -match 'acceptance remain NOT RUN') 'Installed handoff is distinguished from incomplete genuine identity/provider runtime acceptance.'
Assert-Test ($resultApi.uniqueName -eq 'os_sr_avq_complete' -and $resultApi.version -eq '1.0.2' -and
    $resultApi.bindingType -eq 'Global' -and -not $resultApi.isFunction -and -not $resultApi.isPrivate) 'Reviewed result API is a discoverable global action with server-side authorization.'
Assert-Test ($resultApi.allowedCustomProcessingStepType -eq 'SyncAndAsync' -and
    $null -eq $resultApi.mainOperationPlugin -and $resultApi.handler.pluginType -eq 'os_sr_avqg.CompleteAvailabilityQuery' -and
    $resultApi.handler.message -eq $resultApi.uniqueName -and $resultApi.handler.stage -eq 20 -and
    $resultApi.handler.mode -eq 0 -and $resultApi.handler.rank -eq 1 -and
    $resultApi.handler.executionIdentity -eq 'CallingUser') 'API uses the reviewed configured synchronous transaction handler without impersonation.'
Assert-Test ((@($resultApi.inputs.name | Sort-Object) -join ',') -eq
    'CorrelationId,ErrorCode,ExpectedRowVersion,ExpiresAt,QueriedAt,QueryId,ReasonCode,SlotsJson,TerminalStatus' -and
    @($resultApi.inputs | Where-Object { -not $_.required }).Count -eq 2) 'API has exactly nine inputs and only safe reason/error are optional.'
Assert-Test ($resultApi.outputs.Count -eq 1 -and $resultApi.outputs[0].name -eq 'ResultCode' -and
    $resultApi.outputs[0].success -eq 'Applied' -and
    $resultApi.concurrency -match 'IfRowVersionMatches' -and $resultApi.errors -match 'never return Applied on fault or retry') 'API success requires the conditional write, never a success-shaped concurrency fallback.'
Assert-Test ($flow.trigger.concurrency -eq 1 -and $flow.trigger.condition -match 'Pending') 'Flow is Pending-only and serial.'
Assert-Test (@($flow.actions.sequence) -join ',' -eq '1,2,3,4,5,6,7,8,9,10,11') 'Flow has the exact ordered eleven-step contract.'
Assert-Test (@($flow.resultTransitions) -join ',' -eq 'Pending -> Available,Pending -> NoSlots,Pending -> Failed') 'Flow has exactly three terminal transitions.'
Assert-Test (@($flow.actions | Where-Object { $_.operation -match '(?i)Candidate|os_sr_cact|os_sr_intv|Receipt|Status History|email send|event creat' }).Count -eq 0) 'Flow actions exclude Candidate Core and business writes.'
Assert-Test ($flow.actions[5].operation -match 'Office 365 Outlook Find meeting times \(V2\)') 'Flow calls the approved Outlook action.'
Assert-Test ($flow.actions[6].operation -match 'entire provider response' -and $flow.actions[7].operation -match 'OutlookMeetingTimesAdapter') 'Flow validates and filters the entire response.'
Assert-Test ($flow.actions[8].operation -match 'Before every terminal write' -and $flow.actions[8].operation -match 're-read TA') 'Required reference re-read immediately precedes drift comparison.'
Assert-Test ($flow.actions[9].operation -match 'ReferenceDriftPolicy.BeforeTerminalWrite' -and $flow.actions[10].operation -match 'Invoke os_sr_avq_complete once') 'Drift is applied before the single terminal API write.'
Assert-Test ($flow.provider.connector -eq 'Office 365 Outlook' -and $flow.provider.action -eq 'Find meeting times (V2)' -and $flow.provider.operationId -eq 'FindMeetingTimes_V2') 'The standard Outlook V2 provider is authoritative.'
Assert-Test (@($flow.provider.inputs.Keys | Sort-Object) -join ',' -eq 'ActivityDomain,End,IsOrganizerOptional,MaxCandidates,MeetingDuration,MinimumAttendeePercentage,RequiredAttendees,ResourceAttendees,Start') 'Provider has exactly the approved input keys.'
Assert-Test ($flow.provider.inputs.RequiredAttendees -match 'TA email' -and $flow.provider.inputs.ResourceAttendees -match 'Empty for Online' -and $flow.provider.inputs.ResourceAttendees -match 'Onsite') 'TA and mode-specific room inputs are explicit.'
Assert-Test ($flow.provider.inputs.MeetingDuration -match 'duration' -and $flow.provider.inputs.Start -match 'UTC' -and $flow.provider.inputs.End -match 'UTC') 'Duration and UTC request window are explicit.'
Assert-Test ($flow.provider.inputs.MaxCandidates -match 'os_sr_avq_maxc' -and $flow.provider.inputs.MaxCandidates -match '1-200') 'MaxCandidates is bounded and configured.'
Assert-Test ($flow.provider.inputs.MinimumAttendeePercentage -is [string] -and $flow.provider.inputs.MinimumAttendeePercentage -ceq '100') 'Minimum attendee percentage is the exact string 100.'
Assert-Test ($flow.provider.inputs.IsOrganizerOptional -eq $true -and $flow.provider.inputs.ActivityDomain -ceq 'Work') 'Organizer is optional and activity domain is Work.'
Assert-Test (@($flow.provider.noInputs) -join ',' -eq 'Candidate,Interview Schedule,Timezone') 'No Candidate, Interview Schedule or timezone is passed to the connector.'
Assert-Test ($flow.provider.evaluationClock -match 'current UTC after the provider call' -and $flow.provider.evaluationClock -match 'never backdate') 'Lead time and queried-at use the same current post-provider instant.'
Assert-Test (@($flow.provider.response.requiredTopLevel) -join ',' -eq 'emptySuggestionsReason,meetingTimeSuggestions') 'Top-level provider response is explicit.'
Assert-Test (@($flow.provider.response.requiredSuggestion).Count -eq 5 -and $flow.provider.response.requiredSuggestion -contains 'attendeeAvailability') 'Suggestion time and attendee structures are required.'
Assert-Test (@($flow.provider.response.requiredAttendeeAvailability) -join ',' -eq 'attendee.emailAddress.address,attendee.type,availability') 'Every attendee supplies address, type and availability.'
Assert-Test ($flow.provider.response.acceptedAvailability -match 'Exactly free' -and $flow.provider.response.acceptedAvailability -match 'exactly once') 'Expected attendee counts and free-only semantics are explicit.'
Assert-Test ($flow.provider.response.organizer -match 'never used' -and $flow.provider.response.noValidSuggestions -match 'NO_COMMON_SLOT') 'Organizer is ignored and empty results have a deterministic reason.'
Assert-Test ($flow.provider.response.unknownOrMalformed -match 'PROVIDER_RESPONSE_INVALID' -and $flow.provider.response.unknownOrMalformed -match 'PROVIDER_TIMEZONE_UNSUPPORTED') 'Malformed shape and unsupported timezone fail safely.'
Assert-Test ($flow.provider.response.persistence -match 'Only sorted, distinct UTC startUtc/endUtc slots' -and $flow.provider.response.persistence -match 'Never persist or expose') 'Only canonical slots persist, without provider data.'
Assert-Test ($flow.provider.implementation -match 'offline algorithm reference' -and
    $flow.provider.implementation -match 'not a deployed provider action' -and
    $flow.provider.implementation -match 'handoff is saved and independently verified') 'Offline algorithm reference is distinguished from the installed Flow result handoff.'
Assert-Test ($flow.providerTimezoneFirstRuntimeGate.action -eq 'STOP' -and -not $flow.providerTimezoneFirstRuntimeGate.retry -and -not $flow.providerTimezoneFirstRuntimeGate.automaticConversion) 'First unsupported timezone stops without retry or conversion.'
Assert-Test ($flow.providerTimezoneFirstRuntimeGate.capture -match 'field names, types and timezone' -and $flow.providerTimezoneFirstRuntimeGate.capture -match 'do not persist raw') 'Only sanitized synthetic shape evidence may be captured.'
Assert-Test ($flow.retry.'429' -match 'no automatic retry' -and
    $flow.retry.proposed429Requirement -match 'two retries' -and
    $flow.retry.retryAfterDecision -eq 'PENDING_OWNER_TECHNICAL_LEAD') 'Retry-none implementation does not silently resolve the bounded Retry-After decision.'
Assert-Test ($flow.retry.ambiguousTimeout -match 'No blind repeat' -and $flow.retry.unsupportedTimezoneOrShape -match 'do not retry') 'Timeout and unsupported-shape stop rules are explicit.'
Assert-Test ($flow.safeErrors -contains 'REFERENCE_CHANGED') 'Flow recognizes the deterministic reference-drift failure.'
Assert-Test ($flow.referenceDrift.terminalCoverage -join ',' -eq 'Available,NoSlots,Failed') 'Drift recheck covers every terminal result.'
Assert-Test ($flow.referenceDrift.onChangedOrUnreadable.state -eq 'Failed' -and @($flow.referenceDrift.onChangedOrUnreadable.slots).Count -eq 0 -and $flow.referenceDrift.onChangedOrUnreadable.error -eq 'REFERENCE_CHANGED') 'Drift always fails closed with zero slots.'
Assert-Test ($flow.referenceDrift.memoryOnlyFields.Count -eq 6 -and $flow.referenceDrift.storage -match 'Memory only') 'Reference snapshots remain flow-memory-only.'
Assert-Test ($flow.runHistoryPrivacy.status -eq 'SOURCE_PROTECTIONS_ADDED_RUNTIME_VERIFICATION_REQUIRED' -and
    $flow.runHistoryPrivacy.platformEvidence -match 'does not establish offline') 'Run-history privacy is not claimed without platform runtime verification.'
Assert-Test ($flow.referenceDrift.compare -join ',' -eq 'reference id,active state,normalized mailbox email' -and $flow.referenceDrift.ignore -contains 'TA display name') 'Relevant drift excludes display-name changes.'
Assert-Test ($flow.identity.requestCreator -match 'Separate BSO' -and $flow.identity.resultWriter -match 'current DEV owner' -and $flow.identity.outlookConnection -match 'not an impersonation') 'Requester, writer and connector identities are explicit.'
Assert-Test ($flow.identity.classification -eq 'DEV_FUNCTIONAL_IDENTITY_ELEVATED_NOT_SECURITY_ACCEPTANCE' -and $flow.identity.production -match 'later decision') 'Elevated DEV behavior is not security acceptance.'

Assert-Test ($environment.fixedConstants.timeZone -eq 'SE Asia Standard Time' -and $environment.fixedConstants.availabilityIntervalMinutes -eq 15) 'Timezone and interval are fixed constants.'
Assert-Test ($environment.fixedConstants.maximumHorizonDays -eq 61) 'Existing conservative maximum horizon is 61 days.'
Assert-Test (@($environment.definitions | Where-Object { $_.defaultValue -ne $null }).Count -eq 0) 'No tenant runtime configuration is invented.'
Assert-Test (@($environment.definitions.schemaName | Sort-Object) -join ',' -eq 'os_sr_avq_bhrs,os_sr_avq_dom,os_sr_avq_durs,os_sr_avq_exp,os_sr_avq_hzn,os_sr_avq_lead,os_sr_avq_maxc') 'The canonical environment definitions include the bounded provider limit.'
$maximum = @($environment.definitions | Where-Object schemaName -eq 'os_sr_avq_maxc')[0]
Assert-Test ($maximum.minimum -eq 1 -and $maximum.maximum -eq 200 -and $maximum.technicalNameStatus -eq 'TECHNICAL_LEAD_APPROVED') 'Candidate-limit bounds and approved technical name are explicit.'
Assert-Test ($environment.deploymentBinding.renderer -eq 'AvailabilityConfigurationRenderer.RenderSecured' -and $registration.unsecureConfigurationBinding.renderer -eq $environment.deploymentBinding.renderer) 'Deployment and registration share the versioned security renderer.'
Assert-Test (-not $registration.unsecureConfigurationBinding.manualValuesAllowed -and $registration.unsecureConfigurationBinding.sameRenderedBytesForSteps) 'All steps must use identical generated values, never hand-maintained copies.'
Assert-Test ($registration.dateTimeFirstRuntimeGate.action -eq 'STOP' -and -not $registration.dateTimeFirstRuntimeGate.retry -and -not $registration.dateTimeFirstRuntimeGate.automaticNormalization) 'Unproven Dataverse DateTime transport requires stop and no normalization.'
Assert-Test ($retention.retentionDays -eq 30 -and $retention.cleanup.frequency -eq 'Daily') 'Approved 30-day daily cleanup policy is bounded.'
Assert-Test (-not $retention.cleanup.deleteBsoPrivilege) 'BSO has no cleanup Delete privilege.'
Assert-Test ($role.existingBsoRole.mustNotAdd -contains 'Any Candidate Core privilege') 'BSO role delta prohibits Candidate Core rights.'
Assert-Test (@($role.existingBsoRole.addPrivileges | Where-Object { $_.privilege -match 'Write|Delete|Assign|Share' }).Count -eq 0) 'BSO receives no Availability Query write/delete/assign/share.'
Assert-Test (@($role.integrationRole.privileges | Where-Object { $_.privilege -match 'os_sr_cact|os_sr_cand|os_sr_intv|os_sr_call|os_sr_csh|os_sr_oprc' }).Count -eq 0) 'Proposed least-privilege model has no Candidate Core business privilege.'
Assert-Test ($role.integrationRole.assignTo -match '^Unassigned' -and $role.integrationRole.assignTo -match 'current owner' -and $role.deployment -match 'DEV_FUNCTIONAL_IDENTITY_ELEVATED_NOT_SECURITY_ACCEPTANCE') 'No app user or role change is a DEV dependency.'
Assert-Test ($registration.packageId -eq 'os_sr_avqg_pkg' -and $registration.pluginType -eq 'os_sr_avqg.ProtectAvailabilityQuery') 'Guard package and plugin type are separate from Candidate Core.'
Assert-Test ($registration.steps.Count -eq 4 -and @($registration.steps | Where-Object { $_.message -notin @('Create', 'Update', 'Assign', 'Delete') -or $_.stageNumber -ne 20 -or $_.mode -ne 'Synchronous' }).Count -eq 0) 'Only request Create/Update and immutable ownership/deletion guards are synchronous PreOperation steps.'
Assert-Test (@($registration.steps | Where-Object { $_.executionUser -ne 'Calling User' }).Count -eq 0) 'Guard steps run as Calling User.'
Assert-Test (@($registration.steps | Where-Object { $_.message -eq 'Update' -and
    @($_.filteringAttributes).Count -ne 0 }).Count -eq 0) 'All Updates reach the guard, including immutable inputs and ownership-only changes.'

$plugin = Get-Content -LiteralPath $pluginPath -Raw
$rules = Get-Content -LiteralPath $rulesPath -Raw
$adapter = Get-Content -LiteralPath $adapterPath -Raw
$drift = Get-Content -LiteralPath $driftPath -Raw
$renderer = Get-Content -LiteralPath $rendererPath -Raw
$console = Get-Content -LiteralPath $consolePath -Raw
$html = Get-Content -LiteralPath $htmlPath -Raw
$config = Get-Content -LiteralPath $configPath -Raw
Assert-Test ($plugin -match 'class ProtectAvailabilityQuery' -and $plugin -match 'Stage != 20') 'Separate synchronous PreOperation guard exists.'
Assert-Test ($plugin -match 'IsCreateCaller' -and $plugin -match 'IsResultUpdateCaller' -and $plugin -match 'ResultWriterUserId') 'Guard applies independent creator and configured writer boundaries.'
Assert-Test ($plugin -match 'new ColumnSet\("os_sr_avq_stat", "os_sr_avq_ta", "os_sr_avq_loc"') 'Guard reads the actual query columns for result validation.'
Assert-Test ($plugin -notmatch 'os_sr_cact|os_sr_cand|os_sr_intv|os_sr_csh|os_sr_oprc') 'Availability plug-in has no Candidate Core references.'
Assert-Test ($drift -notmatch 'Microsoft\.Xrm|IOrganizationService|os_sr_cact|os_sr_cand|os_sr_intv|os_sr_csh|os_sr_oprc|CreateRecord|UpdateRecord') 'Every drift path is pure: no business-table dependency or mutation service.'
Assert-Test ($rules -match '"REFERENCE_CHANGED"' -and $console -match 'REFERENCE_CHANGED:') 'Guard category and safe Console mapping both cover drift.'
Assert-Test ($plugin -match '!AllowedKeys.Contains\(name\)') 'Real parser rejects unknown configuration keys.'
Assert-Test ($renderer -match 'PluginConfiguration.Parse\(rendered\)' -and $renderer -match 'parsed.BusinessHours.Count != hours.Count') 'Renderer round-trips through the real parser and verifies equality.'
Assert-Test ($renderer -notmatch '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' -and (Get-Content -LiteralPath $registrationPath -Raw) -notmatch '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}') 'No deployment identity GUID is committed in renderer or registration.'
Assert-Test ($plugin -match 'time.Kind != DateTimeKind.Utc') 'Strict UTC validation remains unchanged.'
Assert-Test ($rules -match 'TimeZoneId = "SE Asia Standard Time"' -and $rules -match 'IntervalMinutes = 15') 'Pure calculator fixes the approved timezone and interval.'
Assert-Test ($rules -match 'HardMaximumHorizonDays = 61' -and $rules -match 'IsTerminalTransition') 'Calculator enforces the existing horizon and terminal transition rules.'
Assert-Test ($adapter -match 'IsOrganizerOptional => true' -and $adapter -match 'MinimumAttendeePercentage => "100"') 'Adapter request implements organizer independence and the exact percentage.'
Assert-Test ($adapter -match 'PROVIDER_TIMEZONE_UNSUPPORTED' -and $adapter -match 'StringComparison.Ordinal' -and $adapter -match 'DateTime.SpecifyKind') 'Adapter requires a recognized UTC representation before marking timestamps UTC.'
Assert-Test ($adapter -match 'taCount == 1' -and $adapter -match 'roomCount == 1' -and $adapter -match 'availability == "free"') 'Adapter requires one free expected attendee of each required type.'
Assert-Test ($adapter -match 'SortedDictionary<DateTime, AvailableSlot>' -and $adapter -match 'SlotResultJson.Serialize') 'Adapter emits ordered bounded canonical slots.'
foreach ($errorCode in $flow.safeErrors) {
    Assert-Test ($rules.Contains('"' + $errorCode + '"')) "Guard permits safe Flow error $errorCode."
}
Assert-Test ($console -match 'availabilityEnabled !== true') 'Console panel is off unless explicitly configured.'
Assert-Test ($console -match 'createRecord\(TABLE\.query\.logicalName' -and $console -match 'retrieveRecord\(query\.logicalName') 'Console creates and polls only an Availability Query.'
Assert-Test ($console -match 'queryId !== lastQueryId') 'Superseded availability polling cannot overwrite a newer query.'
Assert-Test ([regex]::Matches($console, 'queryId !== lastQueryId').Count -ge 2) 'The query identity is rechecked after the asynchronous poll returns.'
Assert-Test ($console -match 'submission !== activeSubmission' -and $console -match 'submission === activeSubmission') 'Superseded submissions cannot publish stale success or error states.'
Assert-Test ($console -notmatch 'updateRecord|deleteRecord|os_sr_cact|os_sr_cand|os_sr_intv|os_sr_csh|os_sr_oprc|MarkRound1Scheduled|selectedCandidate') 'Console cannot mutate or select Candidate/schedule state.'
Assert-Test ($console -notmatch 'os_sr_ta_eml|os_sr_loc_rmeml') 'The display-only Console does not retrieve mailbox addresses.'
Assert-Test ($console -match 'Object\.prototype\.hasOwnProperty\.call\(SAFE_ERRORS, error\)') 'Only owned safe error mappings are displayed.'
Assert-Test ($console -match 'Asia/Ho_Chi_Minh' -and $console -match 'Pending' -and $console -match 'NoSlots' -and $console -match 'Failed') 'Console displays supported states in Vietnam time.'
$panel = [regex]::Match($html, '(?s)<section class="panel" aria-labelledby="availability-heading">.*?</section>').Value
Assert-Test ($panel -match 'availability-form' -and $panel -match 'display-only' -and $panel -notmatch 'CandidateId|MarkRound1Scheduled|os_sr_cact') 'Panel is separate, display-only and Candidate-independent.'
Assert-Test ($config -notmatch 'availabilityEnabled\s*:\s*true') 'Current browser configuration does not enable availability.'
Assert-Test ($console -match 'allowsReference\(record\[table\.name\], config\.syntheticDataOnly\)') 'TA and Location choices follow the shared synthetic-reference policy.'
$guardSource = (@($pluginPath, $rulesPath, $adapterPath, $driftPath, $rendererPath) | ForEach-Object { Get-Content -LiteralPath $_ -Raw }) -join "`n"
Assert-Test ($guardSource -notmatch '(?<!Enumerable)\.SequenceEqual\(' -and $guardSource -match 'Enumerable\.SequenceEqual\(') 'Guard source uses explicit Enumerable.SequenceEqual so C# first-class spans cannot bind System.Memory.'

$flowDefinitionText = Get-Content -LiteralPath $flowDefinitionPath -Raw
$flowDefinition = $flowDefinitionText | ConvertFrom-Json -AsHashtable
$flowActions = [System.Collections.Generic.Dictionary[string, object]]::new()
function Add-FlowActions($actions) {
    foreach ($name in $actions.Keys) {
        $action = $actions[$name]
        $flowActions.Add($name, $action)
        foreach ($containerName in @('actions', 'else', 'default')) {
            if (-not $action.ContainsKey($containerName)) { continue }
            $container = $action[$containerName]
            if ($containerName -eq 'actions') {
                $children = $container
            } elseif ($container.ContainsKey('actions')) {
                $children = $container.actions
            } else {
                continue
            }
            if ($children -is [System.Collections.IDictionary]) {
                Add-FlowActions $children
            }
        }
        if ($action.ContainsKey('cases')) {
            foreach ($caseName in $action.cases.Keys) {
                if ($action.cases[$caseName].ContainsKey('actions')) {
                    Add-FlowActions $action.cases[$caseName].actions
                }
            }
        }
    }
}
Add-FlowActions $flowDefinition.properties.definition.actions
$flowReferences = $flowDefinition.properties.connectionReferences
Assert-Test ((@($flowReferences.Keys | Sort-Object) -join ',') -eq 'shared_commondataserviceforapps,shared_office365') 'Flow uses only the Dataverse and Office 365 Outlook connectors.'
Assert-Test ($flowReferences.shared_office365.connection.connectionReferenceLogicalName -eq 'os_sr_avchk_outlook_cr' -and $flowReferences.shared_commondataserviceforapps.connection.connectionReferenceLogicalName -eq 'os_sr_avchk_dataverse_cr') 'Flow binds only through the two solution connection references.'
$flowTrigger = @($flowDefinition.properties.definition.triggers.Values)
Assert-Test ($flowTrigger.Count -eq 1 -and $flowTrigger[0].inputs.parameters['subscriptionRequest/entityname'] -eq 'os_sr_avq' -and $flowTrigger[0].inputs.parameters['subscriptionRequest/message'] -eq 1 -and $flowTrigger[0].inputs.parameters['subscriptionRequest/filterexpression'] -eq 'os_sr_avq_stat eq 100000000' -and $flowTrigger[0].runtimeConfiguration.concurrency.runs -eq 1) 'Flow triggers once per new Pending query with concurrency 1.'
$flowEnvParameters = @($flowDefinition.properties.definition.parameters.GetEnumerator() | Where-Object { $_.Key -notlike '$*' })
Assert-Test ((@($flowEnvParameters | ForEach-Object { $_.Value.metadata.schemaName } | Sort-Object) -join ',') -eq 'os_sr_avq_bhrs,os_sr_avq_dom,os_sr_avq_durs,os_sr_avq_exp,os_sr_avq_hzn,os_sr_avq_lead,os_sr_avq_maxc' -and @($flowEnvParameters | Where-Object { $_.Value.ContainsKey('defaultValue') }).Count -eq 0) 'Flow references exactly the seven value-less environment-variable definitions.'
$numericFlowParameters = @($flowEnvParameters | Where-Object { $_.Value.metadata.schemaName -in @('os_sr_avq_lead', 'os_sr_avq_hzn', 'os_sr_avq_exp', 'os_sr_avq_maxc') })
Assert-Test (@($numericFlowParameters | Where-Object { $_.Value.type -ne 'Float' }).Count -eq 0 -and
    @($numericFlowParameters | Where-Object { $flowDefinitionText -notmatch [regex]::Escape("@int(string(parameters('$($_.Key)')))") }).Count -eq 0) 'Number parameter declarations and integer conversions remain unchanged pending runtime verification.'
$flowOperations = @($flowActions.Values | Where-Object type -eq 'OpenApiConnection' | ForEach-Object { $_.inputs.host.operationId })
Assert-Test (@($flowOperations | Where-Object { $_ -notin @('GetItem', 'FindMeetingTimes_V2', 'PerformUnboundAction') }).Count -eq 0 -and @($flowOperations | Where-Object { $_ -eq 'FindMeetingTimes_V2' }).Count -eq 1 -and @($flowOperations | Where-Object { $_ -eq 'PerformUnboundAction' }).Count -eq 1) 'Flow calls Find meeting times (V2) once and invokes exactly one terminal result API.'
$flowWrite = @($flowActions.Values | Where-Object { $_.type -eq 'OpenApiConnection' -and $_.inputs.host.operationId -eq 'PerformUnboundAction' })[0]
$resultApiInputs = 'item/CorrelationId,item/ErrorCode,item/ExpectedRowVersion,item/ExpiresAt,item/QueriedAt,item/QueryId,item/ReasonCode,item/SlotsJson,item/TerminalStatus'
Assert-Test ($flowWrite.inputs.parameters.actionName -eq 'os_sr_avq_complete' -and (@($flowWrite.inputs.parameters.Keys | Where-Object { $_ -like 'item/*' } | Sort-Object) -join ',') -eq $resultApiInputs) 'Terminal API carries only the nine reviewed inputs.'
$flowReads = @($flowActions.Values | Where-Object { $_.type -eq 'OpenApiConnection' -and $_.inputs.host.operationId -eq 'GetItem' } | ForEach-Object { $_.inputs.parameters.entityName } | Sort-Object -Unique)
Assert-Test (($flowReads -join ',') -eq 'os_sr_avqs,os_sr_locs,os_sr_tas') 'Flow reads only the query, TA and Location.'
$flowProvider = @($flowActions.Values | Where-Object { $_.type -eq 'OpenApiConnection' -and $_.inputs.host.operationId -eq 'FindMeetingTimes_V2' })[0]
Assert-Test ($flowProvider.inputs.parameters['body/MinimumAttendeePercentage'] -eq '100' -and $flowProvider.inputs.parameters['body/IsOrganizerOptional'] -eq $true -and $flowProvider.inputs.parameters['body/ActivityDomain'] -eq 'Work' -and @($flowProvider.inputs.parameters.Keys | Where-Object { $_ -match '(?i)timezone|OptionalAttendees' }).Count -eq 0) 'Flow provider inputs match the accepted Outlook contract.'
Assert-Test (@($flowActions.Values | Where-Object { $_.type -eq 'OpenApiConnection' -and
    ($_.inputs.retryPolicy.type -ne 'none' -or $_.ContainsKey('retryPolicy')) }).Count -eq 0) 'Flow connector actions disable retries at the executable inputs location.'
Assert-Test (@($flowActions.GetEnumerator() | Where-Object { $_.Value.type -eq 'OpenApiConnection' -and $_.Key -ne 'Read_query' -and -not $_.Value.runtimeConfiguration.secureData }).Count -eq 0) 'Reference reads, result API and Outlook call secure run-history inputs and outputs.'
$sensitiveFlowActions = @(
    'Read_query', 'Read_ta', 'Set_ta_snapshot', 'Read_location', 'Set_location_snapshot',
    'Compose_validation_error', 'Find_meeting_times', 'Check_response_shape', 'For_each_suggestion',
    'Check_suggestion_timezone', 'Compose_slot', 'Find_invalid_attendees', 'Find_ta_entries',
    'Find_room_entries', 'Compose_free', 'Check_suggestion_valid', 'Append_observation',
    'Check_slot_eligible', 'Append_slot', 'Compose_canonical_slots', 'Compose_proposed_result',
    'Set_result_slots', 'Evaluate', 'Map_failure', 'If_validated_snapshot', 'Reread_references',
    'Reread_ta', 'Compose_drift', 'Reread_location', 'Compose_location_drift',
    'Compose_terminal', 'Write_terminal_result', 'Set_location_changed', 'Check_pending',
    'Validate_request_shape', 'Validate_ta_response', 'Validate_location_response',
    'Validate_provider_response', 'Validate_UTC_timestamps'
)
Assert-Test (@($sensitiveFlowActions | Where-Object {
    -not $flowActions.ContainsKey($_) -or
    (@($flowActions[$_].runtimeConfiguration.secureData.properties | Sort-Object) -join ',') -ne 'inputs,outputs'
}).Count -eq 0) 'Every recursively nested action that handles snapshots, provider observations or slots secures its own inputs and outputs.'
Assert-Test ((@($flow.runHistoryPrivacy.sensitiveActions | Sort-Object) -join ',') -eq
    (@($sensitiveFlowActions | Sort-Object) -join ',')) 'Privacy contract and recursive protection regression cover the same action set.'
Assert-Test (@($flowActions.GetEnumerator() | Where-Object {
    $_.Value.type -eq 'Foreach' -and $_.Key -eq 'For_each_suggestion' -and
    $_.Value.runtimeConfiguration.concurrency.repetitions -ne 1
}).Count -eq 0) 'The provider-observation loop remains sequential while its full input/output is secured.'
Assert-Test ((@($flowDefinition.properties.definition.triggers.Values)[0].runtimeConfiguration.secureData.properties -join ',') -eq 'outputs') 'The Dataverse trigger secures its row payload in run history.'
Assert-Test (@($flowActions.Values | Where-Object { $_.type -eq 'Foreach' -and $_.runtimeConfiguration.concurrency.repetitions -ne 1 }).Count -eq 0) 'Suggestion evaluation is sequential.'
Assert-Test ($flowActions.Compose_canonical_slots.inputs -ceq "@sort(union(variables('v_slots'), variables('v_slots')), 'startUtc')") 'Canonical slots are deduplicated then ordered by UTC start.'
$observationCondition = $flowActions.Check_suggestion_valid.expression
Assert-Test ($observationCondition -match "not\(contains\(variables\('v_obs'\)" -and
    $observationCondition -match "string\(not\(outputs\('Compose_free'\)\)\)") 'Contradictory duplicate interval observations invalidate the provider response.'
$checkModeActions = $flowDefinition.properties.definition.actions.Evaluate.actions.Check_config.actions.Check_mode.actions
Assert-Test ($checkModeActions.Check_validation.expression -ceq "@equals(outputs('Compose_validation_error'), '')" -and
    $checkModeActions.Check_validation.runAfter.ContainsKey('Compose_validation_error') -and
    $checkModeActions.Check_validation.actions.Set_has_snapshot.inputs.value -eq $true) 'A reference snapshot exists only after initial TA and Location validation passes.'
Assert-Test ($flowActions.If_validated_snapshot.expression -ceq "@variables('v_hasSnapshot')" -and
    @($flowActions.If_validated_snapshot.runAfter.Map_failure).Count -eq 3) 'Reference-drift re-reads only run after a validated snapshot, including provider-failure handling.'
Assert-Test ($flowActions.Compose_drift.inputs -match "os_sr_taid" -and
    $flowActions.Compose_drift.inputs -match "statecode" -and
    $flowActions.Compose_drift.inputs -match "os_sr_ta_eml" -and
    $flowActions.Compose_drift.inputs -notmatch "name") 'TA drift compares only identity, active state and normalized email, not display name.'
Assert-Test ((@($flowActions.Write_terminal_result.inputs.parameters.Keys | Where-Object { $_ -like 'item/*' } | Sort-Object) -join ',') -eq $resultApiInputs) 'Terminal write remains limited to the reviewed API contract.'
Assert-Test ($flowActions.Write_terminal_result.inputs.parameters['item/ExpectedRowVersion'] -eq "@outputs('Read_query')?['body/@odata.etag']" -and -not $flowActions.Write_terminal_result.inputs.parameters.ContainsKey('If-Match')) 'Terminal API receives the exact original row version as an ordinary input, never a wildcard header.'
Assert-Test ($flowDefinitionText -notmatch '(?i)os_sr_cand|os_sr_cact|os_sr_intv|os_sr_csh|os_sr_oprc|SendEmail|CreateEvent|graph\.microsoft|teams|"Http"|shared-' -and $flowDefinitionText -notmatch '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}') 'Flow source has no forbidden operation, connection id or literal mailbox.'
foreach ($errorCode in @($flowDefinitionText | Select-String -Pattern "'([A-Z_]{6,})'" -AllMatches -CaseSensitive).Matches | ForEach-Object { $_.Groups[1].Value } | Where-Object { $_ -notin @('CONFIG', 'REFERENCE', 'REQUEST', 'PROVIDER', 'RESPONSE', 'RESULT', 'NO_COMMON_SLOT') } | Sort-Object -Unique) {
    Assert-Test ($flow.safeErrors -contains $errorCode) "Flow emits only contract safe error $errorCode."
}
$sourcePaths = @($pluginPath, $rulesPath, $adapterPath, $consolePath, $rendererPath, $driftPath, $flowPath, $environmentPath, $retentionPath, $rolePath, $registrationPath, $schemaPath, $flowDefinitionPath)
$activeSource = ($sourcePaths | ForEach-Object { Get-Content -LiteralPath $_ -Raw }) -join "`n"
Assert-Test ($activeSource -notmatch '(?i)getSchedule|availabilityView|graph-scheduling|os_sr_cr_grs|Calendars\.ReadBasic|IntegrationApplicationUserId|GRAPH_|DecodeSchedule|ScheduleSource') 'No superseded Graph provider contract remains in active source.'
Assert-Test ($activeSource -notmatch '(?i)(client_secret\s*[=:]\s*["''][^"'']+|Bearer\s+[A-Za-z0-9._-]{20,}|-----BEGIN (RSA |EC )?PRIVATE KEY-----)') 'No credentials, token or private key were introduced.'

Write-Output "Availability Query static checks passed: $script:checks"
