$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

function Assert-Test([bool]$condition, [string]$message) {
    if (-not $condition) { throw "FAIL: $message" }
    $script:checks++
}

$script:checks = 0
$schemaPath = Join-Path $root 'solutions/Entities/os_sr_avq/AvailabilityQuery.schema.json'
$connectorPath = Join-Path $root 'solutions/AvailabilityQuery/graph-scheduling.openapi.json'
$flowPath = Join-Path $root 'solutions/AvailabilityQuery/availability-flow.contract.json'
$environmentPath = Join-Path $root 'solutions/AvailabilityQuery/availability-environment-variables.json'
$retentionPath = Join-Path $root 'solutions/AvailabilityQuery/availability-query-retention.json'
$rolePath = Join-Path $root 'solutions/AvailabilityQuery/availability-role-delta.json'
$registrationPath = Join-Path $root 'solutions/AvailabilityQuery/availability-plugin-registration.contract.json'
$pluginPath = Join-Path $root 'solutions/AvailabilityQuery/AvailabilityQueryPlugin.cs'
$rulesPath = Join-Path $root 'solutions/AvailabilityQuery/AvailabilityRules.cs'
$consolePath = Join-Path $root 'solutions/CandidateConsole/WebResources/os_/bso/candidate-console-availability.js'
$htmlPath = Join-Path $root 'solutions/CandidateConsole/WebResources/os_/bso/candidate-console.html'
$configPath = Join-Path $root 'solutions/CandidateConsole/WebResources/os_/bso/candidate-console-environment.js'

$schema = Get-Content -LiteralPath $schemaPath -Raw | ConvertFrom-Json -AsHashtable
$connector = Get-Content -LiteralPath $connectorPath -Raw | ConvertFrom-Json -AsHashtable
$flow = Get-Content -LiteralPath $flowPath -Raw | ConvertFrom-Json -AsHashtable
$environment = Get-Content -LiteralPath $environmentPath -Raw | ConvertFrom-Json -AsHashtable
$retention = Get-Content -LiteralPath $retentionPath -Raw | ConvertFrom-Json -AsHashtable
$role = Get-Content -LiteralPath $rolePath -Raw | ConvertFrom-Json -AsHashtable
$registration = Get-Content -LiteralPath $registrationPath -Raw | ConvertFrom-Json -AsHashtable

Assert-Test ($schema.status -eq 'PROPOSED_SOURCE_OFFLINE_NOT_PROVISIONED') 'Schema source remains clearly offline.'
Assert-Test ($schema.solutionUniqueName -eq 'os_sr_bso_rs_support') 'Schema targets the existing P0 Solution.'
Assert-Test ($schema.table.logicalName -eq 'os_sr_avq' -and $schema.table.ownership -eq 'UserOwned') 'Availability Query identity and ownership are exact.'
Assert-Test (-not $schema.table.auditEnabled -and $schema.table.retentionDays -eq 30) 'Audit and approved retention are explicit.'
Assert-Test ($schema.table.primaryName.logicalName -eq 'os_sr_avq_ref' -and $schema.table.primaryName.format -eq 'AVQ-{SEQNUM:8}') 'Primary AutoNumber contract is exact.'
Assert-Test (@($schema.table.fields | Where-Object logicalName -eq 'os_sr_avq_ta').Count -eq 1) 'Required TA lookup exists.'
Assert-Test (@($schema.table.fields | Where-Object logicalName -eq 'os_sr_avq_loc').Count -eq 1) 'Optional Location lookup exists.'
Assert-Test (@($schema.table.fields | Where-Object { $_.logicalName -match 'cand|intv' }).Count -eq 0) 'No Candidate or Interview Schedule fields exist.'
Assert-Test (@($schema.table.fields | Where-Object { $_.logicalName -match 'availabilityView|graph|email' }).Count -eq 0) 'No raw Graph or mailbox-address fields exist.'
Assert-Test (@($schema.table.fields | Where-Object logicalName -eq 'os_sr_avq_slts').Count -eq 1) 'Only computed slot results are persisted.'
Assert-Test (@($schema.table.relationships | ForEach-Object schemaName) -join ',' -eq 'os_sr_ta_avq,os_sr_loc_avq') 'Only TA and Location relationships exist.'
Assert-Test (@($schema.table.relationships | Where-Object { $_.cascadeDelete -ne 'Restrict' -or $_.cascadeAssign -ne 'NoCascade' -or $_.cascadeShare -ne 'NoCascade' -or $_.cascadeUnshare -ne 'NoCascade' -or $_.cascadeReparent -ne 'NoCascade' }).Count -eq 0) 'Relationship cascades are restrictive and non-cascading.'

$pathItems = @($connector.paths.Keys)
Assert-Test ($pathItems.Count -eq 1 -and $pathItems[0] -eq '/me/calendar/getSchedule') 'Connector exposes only getSchedule.'
Assert-Test (@($connector.paths['/me/calendar/getSchedule'].Keys) -join ',' -eq 'post') 'Connector has no event or email write method.'
Assert-Test ($connector.securityDefinitions.oauth2.scopes.Keys -join '' -eq 'https://graph.microsoft.com/Calendars.ReadBasic') 'Connector requests delegated Calendars.ReadBasic only.'
Assert-Test ((Get-Content -LiteralPath $connectorPath -Raw) -notmatch '(?i)clientSecret|clientId|accessToken|tenantId|Calendars\.ReadWrite|Mail\.Send|/events|sendMail') 'Connector source embeds no identity secret or out-of-scope operation.'

Assert-Test ($flow.trigger.concurrency -eq 1 -and $flow.trigger.condition -match 'Pending') 'Flow is Pending-only and serial.'
Assert-Test (@($flow.resultTransitions).Count -eq 3) 'Flow has exactly three terminal result transitions.'
Assert-Test (@($flow.actions | Where-Object { $_.operation -match '(?i)Candidate|os_sr_cact|os_sr_intv|Receipt|Status History|email|event' }).Count -eq 0) 'Flow actions exclude Candidate Core and business writes.'
Assert-Test ($flow.retry.'429' -match 'Retry-After' -and $flow.retry.'429' -match 'two retries') '429 policy is bounded and Retry-After aware.'
Assert-Test ($flow.retry.ambiguousTimeout -match 'No blind repeat') 'Ambiguous timeout does not retry blindly.'

Assert-Test ($environment.fixedConstants.timeZone -eq 'SE Asia Standard Time' -and $environment.fixedConstants.availabilityIntervalMinutes -eq 15) 'Timezone and interval are fixed constants.'
Assert-Test ($environment.fixedConstants.maximumHorizonDays -eq 61) 'Maximum horizon is 61 days.'
Assert-Test (@($environment.definitions | Where-Object { $_.defaultValue -ne $null }).Count -eq 0) 'No tenant runtime configuration is invented.'
Assert-Test (@($environment.definitions.schemaName | Sort-Object) -join ',' -eq 'os_sr_avq_bhrs,os_sr_avq_dom,os_sr_avq_durs,os_sr_avq_exp,os_sr_avq_hzn,os_sr_avq_lead') 'Only approved environment-variable definitions are included.'
Assert-Test ($retention.retentionDays -eq 30 -and $retention.cleanup.frequency -eq 'Daily') 'Approved 30-day daily cleanup policy is bounded.'
Assert-Test (-not $retention.cleanup.deleteBsoPrivilege) 'BSO has no cleanup Delete privilege.'
Assert-Test ($role.existingBsoRole.mustNotAdd -contains 'Any Candidate Core privilege') 'BSO role delta prohibits Candidate Core rights.'
Assert-Test (@($role.existingBsoRole.addPrivileges | Where-Object { $_.privilege -match 'Write|Delete|Assign|Share' }).Count -eq 0) 'BSO receives no Availability Query write/delete/assign/share.'
Assert-Test (@($role.integrationRole.privileges | Where-Object { $_.privilege -match 'os_sr_cact|os_sr_cand|os_sr_intv|os_sr_call|os_sr_csh|os_sr_oprc' }).Count -eq 0) 'Integration role has no Candidate Core business privilege.'
Assert-Test ($registration.packageId -eq 'os_sr_avqg_pkg' -and $registration.pluginType -eq 'os_sr_avqg.ProtectAvailabilityQuery') 'Guard package and plugin type are separate from Candidate Core.'
Assert-Test (@($registration.steps | Where-Object { $_.message -notin @('Create', 'Update') -or $_.stageNumber -ne 20 -or $_.mode -ne 'Synchronous' }).Count -eq 0) 'Both guard registrations are synchronous PreOperation steps.'
Assert-Test (@($registration.steps | Where-Object { $_.executionUser -ne 'Calling User' }).Count -eq 0) 'Guard steps run as Calling User.'

$plugin = Get-Content -LiteralPath $pluginPath -Raw
$rules = Get-Content -LiteralPath $rulesPath -Raw
$console = Get-Content -LiteralPath $consolePath -Raw
$html = Get-Content -LiteralPath $htmlPath -Raw
$config = Get-Content -LiteralPath $configPath -Raw
Assert-Test ($plugin -match 'class ProtectAvailabilityQuery' -and $plugin -match 'Stage != 20') 'Separate synchronous PreOperation guard exists.'
Assert-Test ($plugin -match 'IsCreateCaller' -and $plugin -match 'IsResultUpdateCaller') 'Guard applies independent creator and integration-user boundaries.'
Assert-Test ($plugin -notmatch 'os_sr_cact|os_sr_cand|os_sr_intv|os_sr_csh|os_sr_oprc') 'Availability plug-in has no Candidate Core references.'
Assert-Test ($rules -match 'TimeZoneId = "SE Asia Standard Time"' -and $rules -match 'IntervalMinutes = 15') 'Pure calculator fixes the approved timezone and interval.'
Assert-Test ($rules -match 'HardMaximumHorizonDays = 61' -and $rules -match 'IsTerminalTransition') 'Calculator enforces provider horizon and terminal transition rules.'
Assert-Test ($console -match 'availabilityEnabled !== true') 'Console panel is off unless explicitly configured.'
Assert-Test ($console -match 'createRecord\(TABLE\.query\.logicalName' -and $console -match 'retrieveRecord\(query\.logicalName') 'Console creates and polls only an Availability Query.'
Assert-Test ($console -match 'queryId !== lastQueryId') 'Superseded availability polling cannot overwrite a newer query.'
Assert-Test ($console -notmatch 'updateRecord|deleteRecord|os_sr_cact|os_sr_cand|os_sr_intv|os_sr_csh|os_sr_oprc|MarkRound1Scheduled|selectedCandidate') 'Console cannot mutate or select Candidate/schedule state.'
Assert-Test ($console -match 'Asia/Ho_Chi_Minh' -and $console -match 'Pending' -and $console -match 'NoSlots' -and $console -match 'Failed') 'Console displays supported states in Vietnam time.'
$panel = [regex]::Match($html, '(?s)<section class="panel" aria-labelledby="availability-heading">.*?</section>').Value
Assert-Test ($panel -match 'availability-form' -and $panel -match 'display-only' -and $panel -notmatch 'CandidateId|MarkRound1Scheduled|os_sr_cact') 'Panel is separate, display-only and Candidate-independent.'
Assert-Test ((Get-Content -LiteralPath $configPath -Raw) -notmatch 'availabilityEnabled\s*:\s*true') 'Current browser configuration does not enable availability.'
Assert-Test ($console -match 'allowsReference\(record\[table\.name\], config\.syntheticDataOnly\)') 'TA and Location choices follow the shared synthetic-reference policy.'
$secretScan = (@($pluginPath, $rulesPath, $consolePath, $connectorPath) | ForEach-Object {
    Get-Content -LiteralPath $_ -Raw
}) -join "`n"
Assert-Test ($secretScan -notmatch '(?i)(client_secret\s*[=:]\s*["''][^"'']+|Bearer\s+[A-Za-z0-9._-]{20,}|-----BEGIN (RSA |EC )?PRIVATE KEY-----)') 'No credentials, token or private key were introduced.'

Write-Output "Availability Query static checks passed: $script:checks"
