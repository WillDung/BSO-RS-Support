#requires -Version 7.4
[CmdletBinding()]
param(
    [ValidateSet('Preflight', 'Apply', 'VerifiedAncestorApply', 'R4OWriteContextApply',
        'R4OServerRegistrationApply', 'MvpVerticalSlicePreflight',
        'MvpVerticalSliceApply')][string]$RuntimeMode = 'Preflight',
    [Parameter(Mandatory)][string]$EnvironmentName,
    [Parameter(Mandatory)][string]$OrganizationUrl,
    [Parameter(Mandatory)][string]$ExpectedEnvironmentId,
    [Parameter(Mandatory)][string]$ExpectedOrganizationId,
    [string]$ExpectedHandlerPackageUniqueName,
    [switch]$RequirePackageGuardSteps,
    [switch]$DevGuardBypass,
    [int]$ExpectedGuardStepCount,
    [string]$RuntimeEvidencePath
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$manifestPath = Join-Path $root 'docs\PHASE_3A_CANDIDATE_CORE_METADATA_PLAN.json'
$contractPath = Join-Path $root 'docs\PHASE_3C_API_CONTRACT.json'
$script:apiContract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
$expectedManifestHash = '63f56173f61265f539d23d6ceffb5631e23f438e4e254755c1e24c7d17eb1915'
$runtimeAuthorizationId = 'phase3d-r4m-owner-authorized-marker-propagation-runtime'
$writeContextAuthorization = $RuntimeMode -ceq 'R4OWriteContextApply'
$serverRegistrationAuthorization = $RuntimeMode -ceq 'R4OServerRegistrationApply'
$mvpVerticalSliceAuthorization = $RuntimeMode -in @(
    'MvpVerticalSlicePreflight', 'MvpVerticalSliceApply'
)
$mvpDevGuardBypassAuthorization = $mvpVerticalSliceAuthorization -and $DevGuardBypass
if ($DevGuardBypass -and ($RuntimeMode -cne 'MvpVerticalSliceApply')) {
    throw 'The DEV guard bypass is permitted only for the one-shot MVP apply mode.'
}
$verifiedAncestorAuthorization = $RuntimeMode -in @(
    'VerifiedAncestorApply', 'R4OWriteContextApply', 'R4OServerRegistrationApply'
)
if ($verifiedAncestorAuthorization) {
    $runtimeAuthorizationId = 'phase3d-owner-authorized-verified-ancestor-runtime'
    $RuntimeMode = 'Apply'
}
if ($writeContextAuthorization) {
    $runtimeAuthorizationId = 'phase3d-r4o-owner-authorized-write-context-runtime'
}
if ($serverRegistrationAuthorization) {
    $runtimeAuthorizationId = 'phase3d-r4o-server-registration-classifier-runtime'
}
if ($mvpVerticalSliceAuthorization) {
    $runtimeAuthorizationId = if ($mvpDevGuardBypassAuthorization) {
        'phase3d-vn-lmv-it-dev-guard-bypass'
    } else {
        'phase3d-mvp-visible-vertical-slice-runtime'
    }
    $verifiedAncestorAuthorization = $true
    $RuntimeMode = if ($RuntimeMode -ceq 'MvpVerticalSlicePreflight') { 'Preflight' } else { 'Apply' }
}
$expectedActionCalls = if ($mvpVerticalSliceAuthorization) { 5 } else { 8 }
$schedulingEvidenceChecks = @(
    [ordered]@{
        Action = 'MarkRound1Scheduled'; LiveResult = 'VERIFIED_FAIL_CLOSED_LIVE'
        CurrentStatus = 'Waiting Manual Scheduling'; ExpectedError = 'SCHEDULER_DEPENDENCY_UNAVAILABLE'
    }
    [ordered]@{
        Action = 'RecordPass'; LiveResult = 'NOT_APPLICABLE_CURRENT_STATE'
        CurrentStatus = 'Waiting Manual Scheduling'; OfflineMissingEvidenceResult = 'RESULT_OR_CANCELLATION_DEPENDENCY_UNAVAILABLE'
    }
    [ordered]@{
        Action = 'RecordFail'; LiveResult = 'NOT_APPLICABLE_CURRENT_STATE'
        CurrentStatus = 'Waiting Manual Scheduling'; OfflineMissingEvidenceResult = 'RESULT_OR_CANCELLATION_DEPENDENCY_UNAVAILABLE'
    }
    [ordered]@{
        Action = 'RequestReschedule'; LiveResult = 'NOT_APPLICABLE_CURRENT_STATE'
        CurrentStatus = 'Waiting Manual Scheduling'; OfflineMissingEvidenceResult = 'RESULT_OR_CANCELLATION_DEPENDENCY_UNAVAILABLE'
    }
)
if ($mvpVerticalSliceAuthorization) {
    $schedulingEvidenceChecks = @(
        [ordered]@{ Action = 'Scheduling-dependent operations'; LiveResult = 'NOT_RUN_MVP_SCOPE' }
    )
}
$script:runtimeRequestCounts = @{ GET = 0; POST = 0 }
$script:apiCalls = 0
$script:runtimeFailureClassification = $null
$script:journal = $null
$script:apiRoot = $OrganizationUrl.TrimEnd('/') + '/api/data/v9.2/'
$script:accessToken = $null
$script:actorId = $null
$script:candidateId = $null
$script:sets = @{}
$script:expectedReceiptEvidence = @{}
$script:expectedCounts = @{ Candidates = 0; Calls = 0; History = 0; Receipts = 0 }

$null = . (Join-Path $PSScriptRoot 'Provision-BsoRsOperationReceipt.ps1') -Mode PlanOnly `
    -EnvironmentName $EnvironmentName -OrganizationUrl $OrganizationUrl `
    -ExpectedEnvironmentId $ExpectedEnvironmentId -ExpectedOrganizationId $ExpectedOrganizationId

function Save-RuntimeJournal {
    $json = ConvertTo-Json -InputObject $script:journal -Depth 20
    $bytes = [Text.Encoding]::UTF8.GetBytes($json)
    $stream = [IO.File]::Open($RuntimeEvidencePath, [IO.FileMode]::Open, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $stream.SetLength(0); $stream.Write($bytes, 0, $bytes.Length); $stream.Flush($true) }
    finally { $stream.Dispose() }
}

function Get-RuntimeErrorCode {
    param([string]$Message)
    $coreWriteFailure = [regex]::Match($Message,
        '(?<![A-Z0-9_])DIRECT_WRITE_GUARD_REJECTED:(UNSUPPORTED_PROTECTED_WRITE|UNSUPPORTED_GUARD_REGISTRATION|GUARD_REGISTRATION_CONTEXT_MISMATCH|ASSOCIATION_PROJECT_RELATIONSHIP|ASSOCIATION_PROJECT_TABLE|ASSOCIATION_CONTAINS_PROJECT_TABLE)(?::CC_[A-Z_]+)?(?::0x[0-9A-F]{8})?(?![A-Z0-9_])')
    if ($coreWriteFailure.Success) { return $coreWriteFailure.Value }
    $trustedParentFailure = [regex]::Match($Message,
        '(?<![A-Z0-9_])DIRECT_WRITE_GUARD_REJECTED:(CANDIDATE_CREATE|CANDIDATE_UPDATE|CALL_LOG_CREATE|STATUS_HISTORY_CREATE|RECEIPT_CREATE):TRUSTED_PARENT:(API_MESSAGE_MISMATCH|STAGE_MISMATCH|MODE_MISMATCH|TRANSACTION_MISMATCH|DEPTH_MISMATCH|USER_CONTEXT_MISMATCH|INITIATING_USER_MISMATCH|ACTIONTYPE_MISSING|ACTIONTYPE_MISMATCH|MARKER_MISSING|MARKER_TYPE_MISMATCH|MARKER_FINGERPRINT_MISMATCH|ANCESTOR_BOUND_EXCEEDED|OWNING_EXTENSION_MISSING|OWNING_EXTENSION_TYPE_MISMATCH|HANDLER_TYPE_MISMATCH|ASSEMBLY_MISMATCH|PACKAGE_MISMATCH|REGISTRATION_READ_FAILED)(?::CC_[A-Z_]+)?(?::0x[0-9A-F]{8})?(?![A-Z0-9_])')
    if ($trustedParentFailure.Success) { return $trustedParentFailure.Value }
    $serviceFailure = [regex]::Match($Message,
        '(?<![A-Z0-9_])DATAVERSE_OPERATION_REJECTED:(CC_[A-Z_]+):0x[0-9A-F]{8}(?![A-Z0-9_])')
    if ($serviceFailure.Success) { return $serviceFailure.Value }
    $candidateCoreFailure = [regex]::Match($Message,
        '(?<![A-Z0-9_])CANDIDATE_CORE_FAILURE:(CC_[A-Z_]+):(TIMEOUT|PLUGIN_EXECUTION|INVALID_OPERATION|SERVICE_FAULT|OTHER)(?![A-Z0-9_])')
    if ($candidateCoreFailure.Success) { return $candidateCoreFailure.Value }
    $guardFailure = [regex]::Match($Message,
        '(?<![A-Z0-9_])DIRECT_WRITE_GUARD_REJECTED:(CANDIDATE_CREATE|CANDIDATE_UPDATE|CALL_LOG_CREATE|STATUS_HISTORY_CREATE|RECEIPT_CREATE):(PARENT_CONTEXT|CALLER_CONTEXT|CALLER_MARKER)(?::(CC_[A-Z_]+))?(?::0x[0-9A-F]{8})?(?![A-Z0-9_])')
    if ($guardFailure.Success) { return $guardFailure.Value }
    $legacyGuardFailure = [regex]::Match($Message,
        '(?<![A-Z0-9_])DIRECT_WRITE_GUARD_REJECTED:LEGACY_GENERIC_GUARD:(CC_[A-Z_]+):0x[0-9A-F]{8}(?![A-Z0-9_])')
    if ($legacyGuardFailure.Success) { return $legacyGuardFailure.Value }
    $unexpectedInput = [regex]::Match($Message,
        '(?<![A-Z0-9_])UNEXPECTED_INPUT:(SDK_ADAPTER|ACTION_REQUEST):([A-Za-z][A-Za-z0-9_]*)(?![A-Z0-9_])')
    if ($unexpectedInput.Success) { return $unexpectedInput.Value }
    $allowed = @(
        'INVALID_EMAIL', 'REQUIRED_TEXT', 'CORRELATION_CONFLICT', 'STALE_EXPECTED_STATUS',
        'SCHEDULER_DEPENDENCY_UNAVAILABLE', 'RESULT_OR_CANCELLATION_DEPENDENCY_UNAVAILABLE',
        'INVALID_TRANSITION', 'UNEXPECTED_INPUT',
        'DATAVERSE_OPERATION_REJECTED', 'UNSUPPORTED_EXECUTION_CONTEXT'
    )
    foreach ($code in $allowed) {
        if ($Message -match "(?<![A-Z0-9_])$([regex]::Escape($code))(?![A-Z0-9_])") { return $code }
    }
    return $null
}

function Invoke-RuntimeRequest {
    param(
        [Parameter(Mandatory)][ValidateSet('GET', 'POST')][string]$Method,
        [Parameter(Mandatory)][string]$Path,
        [object]$Body
    )
    $uri = [Uri]($script:apiRoot + $Path)
    if ($uri.Scheme -cne 'https' -or $uri.Authority -ine ([Uri]$OrganizationUrl).Authority -or
        $uri.AbsolutePath -notmatch '^/api/data/v9\.2/' -or $uri.UserInfo -or $uri.Fragment) {
        throw 'Runtime request target is outside the owner-confirmed Dataverse API.'
    }
    if ($Method -ceq 'POST' -and ($Path -cne 'os_sr_cact' -or $script:apiCalls -ge $expectedActionCalls)) {
        throw 'Runtime write is outside the single approved Custom API and eight-dispatch ceiling.'
    }
    $headers = @{
        Authorization = "Bearer $script:accessToken"
        Accept = 'application/json'
        'OData-Version' = '4.0'
        'OData-MaxVersion' = '4.0'
        Consistency = 'Strong'
    }
    $arguments = @{
        Uri = $uri
        Method = $Method
        Headers = $headers
        MaximumRetryCount = 0
        MaximumRedirection = 0
        TimeoutSec = 120
        SkipHttpErrorCheck = $true
    }
    if ($Method -ceq 'POST') {
        $json = ConvertTo-Json -InputObject $Body -Depth 20 -Compress
        $hash = Get-Sha256 -Bytes ([Text.Encoding]::UTF8.GetBytes($json))
        $entry = [ordered]@{
            Index = $script:apiCalls + 1
            Action = [string]$Body.ActionType
            PayloadSha256 = $hash
            State = 'PLANNED'
            HttpStatus = $null
            ResultCode = $null
        }
        $script:journal.Dispatches += $entry
        Save-RuntimeJournal
        $entry.State = 'DISPATCH_RESERVED'
        Save-RuntimeJournal
        $null = $script:apiCalls++
        $arguments.Body = $json
        $arguments.ContentType = 'application/json; charset=utf-8'
    }
    $null = $script:runtimeRequestCounts[$Method]++
    try { $response = Invoke-WebRequest @arguments }
    catch {
        if ($Method -ceq 'POST') {
            $entry.State = 'UNCERTAIN_WRITE_OUTCOME'
            Save-RuntimeJournal
        }
        throw 'Dataverse transport outcome is uncertain; no retry or resend is permitted.'
    }
    if ($Method -ceq 'POST') {
        $entry.HttpStatus = [int]$response.StatusCode
        if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 300) {
            $entry.State = 'ACKNOWLEDGED'
        } else {
            $entry.State = 'REJECTED'
        }
        Save-RuntimeJournal
    }
    if ($response.StatusCode -lt 200 -or $response.StatusCode -ge 300) {
        $parsed = $null
        try { $parsed = $response.Content | ConvertFrom-Json } catch { $parsed = $null }
        $safe = Get-SanitizedDataverseError -StatusCode $response.StatusCode -Response $parsed
        $code = Get-RuntimeErrorCode -Message $safe
        if ($Method -ceq 'POST') { $entry.ResultCode = $code; Save-RuntimeJournal }
        return [pscustomobject]@{ Success = $false; StatusCode = [int]$response.StatusCode; ErrorCode = $code; SafeError = $safe }
    }
    if ([string]::IsNullOrWhiteSpace($response.Content)) { return $null }
    if ($uri.AbsolutePath.EndsWith('/$count', [StringComparison]::Ordinal)) { return [string]$response.Content }
    try { $parsed = $response.Content | ConvertFrom-Json -ErrorAction Stop }
    catch { throw 'Dataverse returned an unreadable response; response content suppressed.' }
    if ($Method -ceq 'POST') {
        $entry.ResultCode = [string]$parsed.ResultCode
        $entry.State = 'GET_RECONCILE_PENDING'
        Save-RuntimeJournal
    }
    $parsed
}

function Get-Rows {
    param([string]$Path)
    $page = Invoke-RuntimeRequest -Method GET -Path $Path
    if ($null -eq $page -or $null -eq $page.value) { throw 'Expected row collection was not returned.' }
    if ($page.'@odata.nextLink') { throw 'Unexpected result paging; stop rather than broaden the read.' }
    @($page.value)
}

function Assert-PackageBackedHandler {
    param([Parameter(Mandatory)][string]$PackageUniqueName)
    $api = @(Get-Rows -Path "customapis?%24select=customapiid,uniquename,executeprivilegename,bindingtype,isfunction,isprivate,allowedcustomprocessingsteptype,_plugintypeid_value&%24filter=uniquename eq '$($script:apiContract.uniqueName)'")
    if ($api.Count -ne 1 -or $api[0].uniquename -cne 'os_sr_cact') {
        throw 'Runtime Custom API inventory is missing or duplicated.'
    }
    $inputs = @(Get-Rows -Path "customapirequestparameters?%24filter=_customapiid_value eq $($api[0].customapiid)")
    $outputs = @(Get-Rows -Path "customapiresponseproperties?%24filter=_customapiid_value eq $($api[0].customapiid)")
    $expectedInputs = @($script:apiContract.inputs | ForEach-Object {
        '{0}|{1}|{2}' -f $_.name, [int]$_.type, [bool]$_.optional
    } | Sort-Object)
    $actualInputs = @($inputs | ForEach-Object {
        '{0}|{1}|{2}' -f $_.uniquename, [int]$_.type, [bool]$_.isoptional
    } | Sort-Object)
    $expectedOutputs = @($script:apiContract.outputs | ForEach-Object {
        '{0}|{1}' -f $_.name, [int]$_.type
    } | Sort-Object)
    $actualOutputs = @($outputs | ForEach-Object {
        '{0}|{1}' -f $_.uniquename, [int]$_.type
    } | Sort-Object)
    $guidInputsWithEntity = @($inputs | Where-Object {
        [int]$_.type -eq 12 -and -not [string]::IsNullOrWhiteSpace([string]$_.logicalentityname)
    })
    if ($api[0].executeprivilegename -cne $script:apiContract.executePrivilegeName -or
        [int]$api[0].bindingtype -ne [int]$script:apiContract.bindingType -or
        [bool]$api[0].isfunction -ne [bool]$script:apiContract.isFunction -or
        [bool]$api[0].isprivate -ne [bool]$script:apiContract.isPrivate -or
        [int]$api[0].allowedcustomprocessingsteptype -ne [int]$script:apiContract.allowedCustomProcessingStepType -or
        $inputs.Count -ne $script:apiContract.inputs.Count -or
        [string]::Join(';', $actualInputs) -cne [string]::Join(';', $expectedInputs) -or
        $outputs.Count -ne $script:apiContract.outputs.Count -or
        [string]::Join(';', $actualOutputs) -cne [string]::Join(';', $expectedOutputs) -or
        $guidInputsWithEntity.Count -ne 0) {
        throw 'Runtime Custom API contract or GUID logical-entity metadata differs from the approved contract.'
    }
    $typeId = [string]$api[0]._plugintypeid_value
    $type = Invoke-RuntimeRequest -Method GET -Path "plugintypes($typeId)?%24select=plugintypeid,typename,_pluginassemblyid_value"
    if ([string]$type.typename -cne $script:apiContract.handler -or
        -not [string]$type._pluginassemblyid_value) {
        throw 'Runtime Custom API handler type is not the approved package assembly handler.'
    }
    $assemblyId = [string]$type._pluginassemblyid_value
    $relationships = @(Get-Rows -Path "EntityDefinitions(LogicalName='pluginassembly')/ManyToOneRelationships?%24select=ReferencingAttribute,ReferencedEntity" |
        Where-Object ReferencedEntity -CEQ 'pluginpackage')
    if ($relationships.Count -ne 1 -or -not $relationships[0].ReferencingAttribute) {
        throw 'Runtime package-to-assembly relationship is missing or ambiguous.'
    }
    $packageLookup = "_$($relationships[0].ReferencingAttribute)_value"
    $assembly = Invoke-RuntimeRequest -Method GET -Path "pluginassemblies($assemblyId)?%24select=pluginassemblyid,name,version,$packageLookup"
    if ([string]$assembly.name -cne 'os_sr_cact' -or [string]$assembly.version -cne '1.0.0.0' -or
        -not [string]$assembly.$packageLookup) {
        throw 'Runtime handler assembly metadata is not package-backed.'
    }
    $packageId = [string]$assembly.$packageLookup
    $package = Invoke-RuntimeRequest -Method GET -Path "pluginpackages($packageId)?%24select=pluginpackageid,uniquename,version,modifiedon"
    $packagesByName = @(Get-Rows -Path "pluginpackages?%24select=pluginpackageid,name,uniquename,version,modifiedon&%24filter=uniquename eq '$PackageUniqueName'")
    if ($packagesByName.Count -ne 1 -or
        [string]$packagesByName[0].pluginpackageid -ine $packageId -or
        $packagesByName[0].name -cne $PackageUniqueName -or
        [string]$package.uniquename -cne $PackageUniqueName -or
        [string]$package.version -cne '1.0.0' -or
        [string]$packagesByName[0].version -cne '1.0.0') {
        throw 'Runtime handler does not resolve to the approved PluginPackage.'
    }
    $packageTypes = @(Get-Rows -Path "plugintypes?%24select=typename,_pluginassemblyid_value&%24filter=_pluginassemblyid_value eq $assemblyId")
    $expectedPackageTypes = @($script:apiContract.handler, $script:apiContract.guard) | Sort-Object
    $actualPackageTypes = @($packageTypes | ForEach-Object { [string]$_.typename } | Sort-Object)
    if ($packageTypes.Count -ne 2 -or
        [string]::Join('|', $actualPackageTypes) -cne [string]::Join('|', $expectedPackageTypes)) {
        throw 'Runtime package assembly does not contain exactly the approved handler and guard types.'
    }
    [ordered]@{
        ApiUniqueName = [string]$api[0].uniquename
        HandlerType = [string]$type.typename
        HandlerAssemblyId = $assemblyId.ToLowerInvariant()
        PackageId = $packageId.ToLowerInvariant()
        PackageUniqueName = [string]$package.uniquename
        PackageModifiedOn = [string]$package.modifiedon
        PackageCount = $packagesByName.Count
        PackageTypes = $actualPackageTypes
        RequestParameters = @($inputs | Sort-Object uniquename | ForEach-Object {
            [ordered]@{
                UniqueName = [string]$_.uniquename
                Type = [int]$_.type
                IsOptional = [bool]$_.isoptional
                LogicalEntityName = if ($_.logicalentityname) { [string]$_.logicalentityname } else { $null }
            }
        })
    }
}

function Assert-PackageGuardSteps {
    param([object]$PackageHandler, [int]$ExpectedCount)
    if ($ExpectedCount -le 0) { throw 'Package guard verification requires a positive expected step count.' }
    $guardTypes = @(Get-Rows -Path "plugintypes?%24select=plugintypeid,typename,_pluginassemblyid_value&%24filter=typename eq '$($script:apiContract.guard)' and _pluginassemblyid_value eq $($PackageHandler.HandlerAssemblyId)")
    if ($guardTypes.Count -ne 1 -or [string]$guardTypes[0].typename -cne $script:apiContract.guard) {
        throw 'Runtime package assembly does not resolve exactly one approved guard type.'
    }
    $steps = @(Get-Rows -Path "sdkmessageprocessingsteps?%24select=sdkmessageprocessingstepid,name,statecode,statuscode,stage,mode,_impersonatinguserid_value,_eventhandler_value,_sdkmessageid_value,_sdkmessagefilterid_value&%24filter=startswith(name,'os_sr_cact.guard.')")
    if ($steps.Count -ne $ExpectedCount -or
        @($steps | ForEach-Object { [string]$_.sdkmessageprocessingstepid } | Sort-Object -Unique).Count -ne $ExpectedCount -or
        @($steps | Where-Object { [string]$_._eventhandler_value -ine [string]$guardTypes[0].plugintypeid -or
            [int]$_.stage -ne 10 -or [int]$_.mode -ne 0 -or $_._impersonatinguserid_value }).Count -ne 0) {
        throw 'Candidate Core guard steps are not all mapped to the package-backed guard type.'
    }
    $inventory = Get-GuardRegistrationInventory -Steps $steps
    $expectedDisabled = @(
        'os_sr_cact.guard.os_sr_cand.Create',
        'os_sr_cact.guard.os_sr_call.Create',
        'os_sr_cact.guard.os_sr_cand.Update',
        'os_sr_cact.guard.os_sr_csh.Create',
        'os_sr_cact.guard.os_sr_oprc.Create'
    ) | Sort-Object
    $disabled = @($steps | Where-Object { [int]$_.statecode -eq 1 })
    if ($mvpDevGuardBypassAuthorization) {
        $disabledNames = @($disabled | ForEach-Object { [string]$_.name } | Sort-Object)
        $disabledInventory = @($inventory.Rows | Where-Object { $_.StepName -in $expectedDisabled })
        if ($disabled.Count -ne $expectedDisabled.Count -or
            [string]::Join('|', $disabledNames) -cne [string]::Join('|', $expectedDisabled) -or
            @($steps | Where-Object { [int]$_.statecode -notin @(0, 1) }).Count -ne 0 -or
            @($steps | Where-Object {
                if ([int]$_.statecode -eq 1) { [int]$_.statuscode -ne 2 }
                else { [int]$_.statuscode -ne 1 }
            }).Count -ne 0 -or
            $disabledInventory.Count -ne $expectedDisabled.Count -or
            @($disabledInventory | Where-Object { $_.Classification -ne 'CANONICAL_PROTECTED_WRITE' }).Count -ne 0) {
            throw 'VN_LMV_IT_DEV_GUARD_BYPASS registration state differs from the exact five-step allowlist.'
        }
    } elseif ($disabled.Count -ne 0 -or @($steps | Where-Object {
            [int]$_.statecode -ne 0 -or [int]$_.statuscode -ne 1
        }).Count -ne 0) {
        throw 'Candidate Core guard steps are not all enabled outside the explicitly authorized DEV bypass.'
    }
    [ordered]@{
        PackageGuardType = [string]$guardTypes[0].typename
        GuardStepCount = $steps.Count
        PackageBackedGuardSteps = @($steps | Where-Object { [int]$_.statecode -eq 0 }).Count
        DisabledDevBypassGuardSteps = if ($mvpDevGuardBypassAuthorization) { $expectedDisabled } else { @() }
        GuardRegistrationInventory = $inventory
    }
}

function Get-RegisteredWriteCode {
    param([string]$MessageName, [string]$EntityName)
    switch -CaseSensitive ("$MessageName|$EntityName") {
        'Create|os_sr_cand' { 'CANDIDATE_CREATE'; break }
        'Update|os_sr_cand' { 'CANDIDATE_UPDATE'; break }
        'Create|os_sr_call' { 'CALL_LOG_CREATE'; break }
        'Create|os_sr_csh' { 'STATUS_HISTORY_CREATE'; break }
        'Create|os_sr_oprc' { 'RECEIPT_CREATE'; break }
        'Update|os_sr_oprc' { 'RECEIPT_UPDATE'; break }
        default { $null }
    }
}

function Get-GuardRegistrationInventory {
    param([object[]]$Steps)
    $messageIds = @($Steps | ForEach-Object { [string]$_._sdkmessageid_value } |
        Where-Object { $_ -match '^[0-9a-fA-F-]{36}$' } | Sort-Object -Unique)
    if ($messageIds.Count -eq 0) { throw 'GUARD_REGISTRATION_INVENTORY_UNRESOLVED' }
    $messageFilter = [string]::Join(' or ', @($messageIds | ForEach-Object {
        "sdkmessageid eq $_"
    }))
    $messages = @(Get-Rows -Path ("sdkmessages?%24select=sdkmessageid,name&%24filter=" +
        [Uri]::EscapeDataString($messageFilter)))
    $filterIds = @($Steps | ForEach-Object { [string]$_._sdkmessagefilterid_value } |
        Where-Object { $_ -match '^[0-9a-fA-F-]{36}$' } | Sort-Object -Unique)
    $filters = @()
    if ($filterIds.Count -gt 0) {
        $filterExpression = [string]::Join(' or ', @($filterIds | ForEach-Object {
            "sdkmessagefilterid eq $_"
        }))
        $filters = @(Get-Rows -Path ("sdkmessagefilters?%24select=sdkmessagefilterid,primaryobjecttypecode,_sdkmessageid_value&%24filter=" +
            [Uri]::EscapeDataString($filterExpression)))
    }
    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($step in $Steps) {
        $stepMessage = @($messages | Where-Object { [string]$_.sdkmessageid -ieq [string]$step._sdkmessageid_value })
        if ($stepMessage.Count -ne 1 -or [string]::IsNullOrWhiteSpace([string]$stepMessage[0].name)) {
            throw 'GUARD_REGISTRATION_INVENTORY_UNRESOLVED'
        }
        $messageName = [string]$stepMessage[0].name
        $filterId = [string]$step._sdkmessagefilterid_value
        if ($messageName -in @('Associate', 'Disassociate') -and [string]::IsNullOrWhiteSpace($filterId)) {
            $rows.Add([pscustomobject][ordered]@{
                StepName = [string]$step.name
                SdkMessage = $messageName
                PrimaryObjectTypeCode = $null
                WriteCode = $null
                Classification = 'RELATIONSHIP_GUARD'
            })
            continue
        }
        $filter = @($filters | Where-Object { [string]$_.sdkmessagefilterid -ieq $filterId })
        if ($filter.Count -ne 1 -or
            [string]$filter[0]._sdkmessageid_value -ine [string]$step._sdkmessageid_value -or
            [string]::IsNullOrWhiteSpace([string]$filter[0].primaryobjecttypecode)) {
            throw 'GUARD_REGISTRATION_INVENTORY_UNRESOLVED'
        }
        $entityName = [string]$filter[0].primaryobjecttypecode
        $writeCode = Get-RegisteredWriteCode -MessageName $messageName -EntityName $entityName
        $rows.Add([pscustomobject][ordered]@{
            StepName = [string]$step.name
            SdkMessage = $messageName
            PrimaryObjectTypeCode = $entityName
            WriteCode = $writeCode
            Classification = if ($writeCode) { 'CANONICAL_PROTECTED_WRITE' } else { 'UNSUPPORTED_GUARD_REGISTRATION' }
        })
    }
    $contradictory = @($rows | Where-Object PrimaryObjectTypeCode | Group-Object {
        "$($_.SdkMessage)|$($_.PrimaryObjectTypeCode)"
    } | Where-Object {
        @($_.Group | Select-Object -ExpandProperty WriteCode -Unique).Count -gt 1
    })
    if ($rows.Count -ne $Steps.Count -or $rows.Count -ne 50 -or $contradictory.Count -ne 0) {
        throw 'GUARD_REGISTRATION_INVENTORY_UNRESOLVED'
    }
    [ordered]@{
        StepCount = $rows.Count
        ResolvedCount = $rows.Count
        UnresolvedCount = 0
        ContradictoryMappingCount = $contradictory.Count
        CanonicalWriteCount = @($rows | Where-Object WriteCode).Count
        UnsupportedRegistrationCount = @($rows | Where-Object { $_.Classification -eq 'UNSUPPORTED_GUARD_REGISTRATION' }).Count
        RelationshipGuardCount = @($rows | Where-Object { $_.Classification -eq 'RELATIONSHIP_GUARD' }).Count
        Rows = @($rows)
    }
}

function Get-Count {
    param([string]$EntitySet, [string]$Filter)
    $path = "$EntitySet/`$count"
    if ($Filter) { $path += '?%24filter=' + [Uri]::EscapeDataString($Filter) }
    $value = Invoke-RuntimeRequest -Method GET -Path $path
    if ($null -ne $value -and $value.PSObject.Properties.Name -contains 'Success' -and -not $value.Success) {
        throw (Get-SanitizedFailureMessage -Message $value.SafeError)
    }
    $count = 0
    $countText = ([string]$value).Trim().TrimStart([char]0xFEFF).Trim()
    if (-not [int]::TryParse($countText, [ref]$count) -or $count -lt 0) {
        $kind = if ($null -eq $value) { 'null' } else { $value.GetType().Name }
        $sample = if ($null -eq $value) { '' } else {
            Get-SanitizedFailureMessage -Message ([string]$value)
        }
        throw "Count-only query returned an invalid $kind result: $sample"
    }
    $count
}

function Get-ScopedCounts {
    @{
        Candidates = Get-Count -EntitySet $script:sets.Candidate -Filter $null
        Calls = Get-Count -EntitySet $script:sets.Call -Filter $null
        History = Get-Count -EntitySet $script:sets.History -Filter $null
        Receipts = Get-Count -EntitySet $script:sets.Receipt -Filter $null
    }
}

function Assert-Counts {
    param([string]$Checkpoint)
    $actual = Get-ScopedCounts
    foreach ($name in @('Candidates', 'Calls', 'History', 'Receipts')) {
        if ($actual[$name] -ne $script:expectedCounts[$name]) {
            throw "Runtime evidence count mismatch at $Checkpoint; stopped without retry."
        }
    }
    if ($script:journal.Dispatches.Count -gt 0 -and
        $script:journal.Dispatches[-1].State -in @('GET_RECONCILE_PENDING', 'REJECTED')) {
        $script:journal.Dispatches[-1].State = 'GET_RECONCILED'
        Save-RuntimeJournal
    }
}

function New-Correlation {
    [Guid]::NewGuid().ToString('D').ToLowerInvariant()
}

function Invoke-Action {
    param([System.Collections.IDictionary]$Body, [string]$ExpectedFailure)
    $result = Invoke-RuntimeRequest -Method POST -Path 'os_sr_cact' -Body $Body
    if ($null -ne $result -and $result.PSObject.Properties.Name -contains 'Success') {
        if (-not $ExpectedFailure -or $result.ErrorCode -cne $ExpectedFailure) {
            if (-not $ExpectedFailure) {
                $script:runtimeFailureClassification = switch ([string]$Body.ActionType) {
                    'CreateCandidate' { 'CREATECANDIDATE_RUNTIME_FAILURE' }
                    'RecordCall' { 'RUNTIME_RECORDCALL_FAILURE' }
                    'ProceedToScheduling' { 'RUNTIME_UPDATECANDIDATE_FAILURE' }
                }
            } elseif ($result.ErrorCode -and
                $result.ErrorCode -notin @('UNSUPPORTED_EXECUTION_CONTEXT', 'DATAVERSE_OPERATION_REJECTED')) {
                $script:runtimeFailureClassification = switch ($ExpectedFailure) {
                    'CORRELATION_CONFLICT' { 'IDEMPOTENCY_FAILURE' }
                    'STALE_EXPECTED_STATUS' { 'RUNTIME_RECORDCALL_FAILURE' }
                    'SCHEDULER_DEPENDENCY_UNAVAILABLE' { 'SCHEDULING_GUARD_FAILURE' }
                }
            }
            throw (Get-SanitizedFailureMessage -Message $result.SafeError)
        }
        return $result
    }
    if ($ExpectedFailure) {
        $script:runtimeFailureClassification = switch ($ExpectedFailure) {
            'CORRELATION_CONFLICT' { 'IDEMPOTENCY_FAILURE' }
            'STALE_EXPECTED_STATUS' { 'RUNTIME_RECORDCALL_FAILURE' }
            'SCHEDULER_DEPENDENCY_UNAVAILABLE' { 'SCHEDULING_GUARD_FAILURE' }
        }
        throw "Expected rejection did not occur: $ExpectedFailure"
    }
    if ([string]$result.ResultCode -notin @('Applied', 'DuplicateReplay')) {
        throw 'Custom API returned an unexpected result code; response details suppressed.'
    }
    $result
}

function Assert-Status {
    param([int]$Expected)
    if (-not $script:candidateId) { throw 'Synthetic Candidate identity is unavailable.' }
    $path = "$($script:sets.Candidate)?%24select=os_sr_cand_stat&%24filter=$([Uri]::EscapeDataString("os_sr_candid eq $($script:candidateId)"))&%24top=2"
    $rows = Get-Rows -Path $path
    if ($rows.Count -ne 1 -or [int]$rows[0].os_sr_cand_stat -ne $Expected) {
        throw 'Synthetic Candidate status did not reconcile.'
    }
}

function Assert-OperationResult {
    param([object]$Result, [string]$ResultCode, [int]$CurrentStatus, [string]$ActionType)
    if ([string]$Result.ResultCode -cne $ResultCode -or [int]$Result.CurrentStatus -ne $CurrentStatus) {
        $script:runtimeFailureClassification = switch ($ActionType) {
            'CreateCandidate' { 'CREATECANDIDATE_RUNTIME_FAILURE' }
            'RecordCall' { if ($ResultCode -ceq 'DuplicateReplay') { 'IDEMPOTENCY_FAILURE' } else { 'RUNTIME_RECORDCALL_FAILURE' } }
            'ProceedToScheduling' { 'RUNTIME_UPDATECANDIDATE_FAILURE' }
        }
        throw 'Custom API result did not match the expected status/replay contract.'
    }
}

function Assert-NoEffect {
    param([string]$Checkpoint, [int]$ExpectedStatus)
    Assert-Counts -Checkpoint $Checkpoint
    Assert-Status -Expected $ExpectedStatus
}

function Assert-LiveEvidence {
    if ((Get-Count -EntitySet $script:sets.Candidate -Filter $null) -ne 1) { throw 'Expected exactly one synthetic Candidate.' }
    $candidateRows = Get-Rows -Path "$($script:sets.Candidate)?%24select=os_sr_cand_stat,_createdby_value,_ownerid_value&%24filter=$([Uri]::EscapeDataString("os_sr_candid eq $($script:candidateId)"))&%24top=2"
    if ($candidateRows.Count -ne 1 -or [int]$candidateRows[0].os_sr_cand_stat -ne 100010002 -or
        [string]$candidateRows[0]._createdby_value -cne $script:actorId -or
        [string]$candidateRows[0]._ownerid_value -cne $script:actorId) {
        throw 'Final Candidate status, creator, or owner evidence mismatch.'
    }
    $callRows = Get-Rows -Path "$($script:sets.Call)?%24select=os_sr_call_out,os_sr_call_corid,_os_sr_call_ctby_value,_os_sr_call_cand_value,_ownerid_value&%24filter=$([Uri]::EscapeDataString("_os_sr_call_cand_value eq $($script:candidateId)"))&%24top=10"
    $historyRows = Get-Rows -Path "$($script:sets.History)?%24select=os_sr_csh_prevstat,os_sr_csh_newstat,os_sr_csh_corid,os_sr_csh_cact,_os_sr_csh_actr_value,_os_sr_csh_cand_value,_ownerid_value&%24filter=$([Uri]::EscapeDataString("_os_sr_csh_cand_value eq $($script:candidateId)"))&%24top=10"
    $receiptRows = Get-Rows -Path "$($script:sets.Receipt)?%24select=os_sr_oprc_cact,os_sr_oprc_corid,os_sr_oprc_hash,os_sr_oprc_prevstat,os_sr_oprc_newstat,os_sr_oprc_callref,os_sr_oprc_histref,_os_sr_oprc_cand_value,_createdby_value,_ownerid_value&%24filter=$([Uri]::EscapeDataString("_os_sr_oprc_cand_value eq $($script:candidateId)"))&%24top=10"
    if ($callRows.Count -ne 2 -or $historyRows.Count -ne 2 -or $receiptRows.Count -ne 4) {
        throw 'Final business evidence cardinality mismatch.'
    }
    $outcomes = @($callRows | ForEach-Object { [int]$_.os_sr_call_out } | Sort-Object)
    if (($outcomes -join ',') -cne '100010000,100010001' -or
        @($callRows | Where-Object {
            [string]$_._os_sr_call_ctby_value -cne $script:actorId -or [string]$_._ownerid_value -cne $script:actorId
        }).Count -ne 0) {
        throw 'Call outcome or caller evidence mismatch.'
    }
    $transitions = @($historyRows | ForEach-Object { "$($_.os_sr_csh_prevstat)>$($_.os_sr_csh_newstat)" } | Sort-Object)
    if (($transitions -join ',') -cne '100010000>100010001,100010001>100010002' -or
        @($historyRows | Where-Object {
            [string]$_._os_sr_csh_actr_value -cne $script:actorId -or [string]$_._ownerid_value -cne $script:actorId
        }).Count -ne 0) {
        throw 'Candidate Status History transitions or caller evidence mismatch.'
    }
    if (@($receiptRows | Where-Object {
        [string]$_._os_sr_oprc_cand_value -cne $script:candidateId -or
        [string]$_._createdby_value -cne $script:actorId -or [string]$_._ownerid_value -cne $script:actorId -or
        [string]$_.os_sr_oprc_hash -notmatch '^[0-9a-f]{64}$'
    }).Count -ne 0) { throw 'Operation Receipt integrity evidence mismatch.' }
    $actions = @($receiptRows | ForEach-Object { [string]$_.os_sr_oprc_cact } | Sort-Object)
    if (($actions -join ',') -cne 'CreateCandidate,ProceedToScheduling,RecordCall,RecordCall') {
        throw 'Operation Receipt action inventory mismatch.'
    }
    if (@($receiptRows | ForEach-Object { [string]$_.os_sr_oprc_corid } | Sort-Object -Unique).Count -ne 4) {
        throw 'Operation Receipt correlation identities are not unique.'
    }
    foreach ($correlation in $script:expectedReceiptEvidence.Keys) {
        $expected = $script:expectedReceiptEvidence[$correlation]
        $receipt = @($receiptRows | Where-Object { [string]$_.os_sr_oprc_corid -ieq $correlation })
        if ($receipt.Count -ne 1 -or [string]$receipt[0].os_sr_oprc_cact -cne $expected.Action -or
            ([string]$receipt[0].os_sr_oprc_callref).ToLowerInvariant() -cne [string]$expected.CallId -or
            ([string]$receipt[0].os_sr_oprc_histref).ToLowerInvariant() -cne [string]$expected.HistoryId) {
            throw 'Operation Receipt replay/result references did not reconcile to original effects.'
        }
    }
    $historyActions = @($historyRows | ForEach-Object { [string]$_.os_sr_csh_cact } | Sort-Object)
    if (($historyActions -join ',') -cne 'ProceedToScheduling,RecordCall') {
        throw 'Status History action inventory mismatch.'
    }
}

try {
    if ((Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $expectedManifestHash) {
        throw 'Current Candidate Core manifest fingerprint differs from the authorized baseline.'
    }
    if ($script:apiContract.uniqueName -cne 'os_sr_cact') {
        throw 'Approved Custom API contract identity mismatch.'
    }
    if ($RuntimeMode -ceq 'Apply' -and
        (-not $RuntimeEvidencePath -or -not (Test-Path -LiteralPath $RuntimeEvidencePath) -or (Get-Item -LiteralPath $RuntimeEvidencePath).Length -ne 0)) {
        throw 'A new empty one-shot runtime evidence file is required.'
    }
    Assert-TargetInput
    Assert-PacIdentity
    Get-ValidatedToken
    $script:apiRoot = $OrganizationUrl.TrimEnd('/') + '/api/data/v9.2/'
    $who = Invoke-RuntimeRequest -Method GET -Path 'WhoAmI'
    if ([string]$who.UserId -ine $script:ExpectedUserId -or [string]$who.OrganizationId -ine $ExpectedOrganizationId) {
        throw 'Runtime WhoAmI/expected-user guard failed.'
    }
    $script:actorId = [string]$who.UserId
    if ($verifiedAncestorAuthorization) {
        if ($ExpectedHandlerPackageUniqueName -cne 'os_sr_cact_pkg' -or
            -not $RequirePackageGuardSteps -or $ExpectedGuardStepCount -ne 50) {
            throw 'Verified-ancestor acceptance requires the exact package and 50 package-backed guards.'
        }
        $organization = Invoke-RuntimeRequest -Method GET -Path "organizations($ExpectedOrganizationId)?%24select=plugintracelogsetting"
        if ($organization.plugintracelogsetting -ne 0) { throw 'TRACE_SETTING_BASELINE_DRIFT' }
        $profilerTypes = @(Get-Rows -Path "plugintypes?%24select=plugintypeid&%24filter=typename eq 'PluginProfiler.Plugins.ProfilerPlugin'")
        foreach ($profiler in $profilerTypes) {
            $wrappers = @(Get-Rows -Path "sdkmessageprocessingsteps?%24select=name&%24filter=_eventhandler_value eq $($profiler.plugintypeid) and statecode eq 0" |
                Where-Object { $_.name -like '*os_sr_cact*' })
            if ($wrappers.Count) { throw 'Active Candidate Core Profiler wrapper blocks acceptance.' }
        }
    }
    foreach ($logicalName in @('os_sr_cand', 'os_sr_call', 'os_sr_csh', 'os_sr_oprc')) {
        $metadata = Invoke-RuntimeRequest -Method GET -Path "EntityDefinitions(LogicalName='$logicalName')?%24select=EntitySetName,PrimaryIdAttribute"
        if (-not $metadata.EntitySetName -or $metadata.PrimaryIdAttribute -cne "$logicalName`id") {
            throw "Runtime table identity mismatch: $logicalName"
        }
        $key = switch ($logicalName) {
            'os_sr_cand' { 'Candidate' }
            'os_sr_call' { 'Call' }
            'os_sr_csh' { 'History' }
            'os_sr_oprc' { 'Receipt' }
        }
        $script:sets[$key] = [string]$metadata.EntitySetName
    }
    if ($RuntimeMode -ceq 'Apply' -and -not $ExpectedHandlerPackageUniqueName) {
        throw 'Runtime Apply requires the reconciled package-backed handler identity.'
    }
    $packageHandler = if ($ExpectedHandlerPackageUniqueName) {
        Assert-PackageBackedHandler -PackageUniqueName $ExpectedHandlerPackageUniqueName
    } else { $null }
    $packageGuard = if ($RequirePackageGuardSteps) {
        if ($null -eq $packageHandler) { throw 'Package-backed guard verification requires the package handler gate.' }
        Assert-PackageGuardSteps -PackageHandler $packageHandler -ExpectedCount $ExpectedGuardStepCount
    } else { $null }
    $script:expectedCounts = Get-ScopedCounts
    if (@($script:expectedCounts.Values | Where-Object { $_ -ne 0 }).Count -ne 0) {
        throw 'Zero-row safety gate failed; no business API invocation was sent.'
    }
    if ($RuntimeMode -ceq 'Preflight') {
        [ordered]@{
            Result = 'PHASE_3D_RUNTIME_PREFLIGHT_READY'
            FreshZeroRowCounts = $script:expectedCounts
            RequestGET = $script:runtimeRequestCounts.GET
            CustomAPIInvocations = 0
            BusinessDataWrites = 0
            OrganizationAuditSettingWrites = 0
            AutomaticRetries = 0
            PackageHandler = $packageHandler
            PackageGuard = $packageGuard
        } | ConvertTo-Json -Depth 10
        return
    }
    $lockRoot = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'BSO-RS-Support'
    $null = New-Item -ItemType Directory -Path $lockRoot -Force
    $targetFingerprint = Get-Sha256 -Bytes ([Text.Encoding]::UTF8.GetBytes(
        "$ExpectedOrganizationId|$expectedManifestHash|$runtimeAuthorizationId"))
    $lockPath = Join-Path $lockRoot "phase3d-r-runtime-$targetFingerprint.lock"
    $lockStream = [IO.File]::Open($lockPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
        $marker = [Text.Encoding]::UTF8.GetBytes("one-shot runtime authorization consumed; manifest=$expectedManifestHash; retries=0")
        $lockStream.Write($marker, 0, $marker.Length); $lockStream.Flush($true)
    } finally { $lockStream.Dispose() }
    $script:journal = [ordered]@{
        Test = 'Candidate Core synthetic runtime acceptance'
        AuthorizationId = $runtimeAuthorizationId
        CandidateLabel = '[SYNTHETIC-E2E]'
        ManifestSha256 = $expectedManifestHash
        ApiUniqueName = 'os_sr_cact'
        ExpectedHandlerPackageUniqueName = $ExpectedHandlerPackageUniqueName
        RequirePackageGuardSteps = [bool]$RequirePackageGuardSteps
        ExpectedGuardStepCount = $ExpectedGuardStepCount
        MaximumApiDispatches = $expectedActionCalls
        AutomaticRetries = 0
        Dispatches = @()
    }
    $stream = [IO.File]::Open($RuntimeEvidencePath, [IO.FileMode]::Open, [IO.FileAccess]::Write, [IO.FileShare]::None)
    $stream.Dispose()
    Save-RuntimeJournal

    $creationCorrelation = New-Correlation
    $name = '[SYNTHETIC-E2E] Candidate Core Acceptance'
    $email = 'bso-rs-candidatecore-' + [Guid]::NewGuid().ToString('N') + '@example.invalid'
    $create = [ordered]@{
        ActionType = 'CreateCandidate'
        CorrelationId = $creationCorrelation
        CandidateName = $name
        CandidateEmail = $email
    }
    $result = Invoke-Action -Body $create
    Assert-OperationResult $result 'Applied' 100010000 'CreateCandidate'
    $script:expectedReceiptEvidence[$creationCorrelation] = @{ Action = 'CreateCandidate'; CallId = ''; HistoryId = '' }
    $script:expectedCounts.Candidates = 1
    $script:expectedCounts.Receipts = 1
    $candidateRows = Get-Rows -Path "$($script:sets.Candidate)?%24select=os_sr_candid,os_sr_cand_stat,os_sr_cand_cnum,_createdby_value,_ownerid_value,_os_sr_cand_pos_value,_os_sr_cand_csrc_value&%24filter=$([Uri]::EscapeDataString("os_sr_cand_corid eq '$creationCorrelation'"))&%24top=2"
    if ($candidateRows.Count -ne 1 -or [string]$candidateRows[0].os_sr_cand_cnum -notmatch '^CAND-[0-9]{8}$' -or
        $candidateRows[0]._createdby_value -ine $script:actorId -or $candidateRows[0]._ownerid_value -ine $script:actorId -or
        $candidateRows[0]._os_sr_cand_pos_value -or $candidateRows[0]._os_sr_cand_csrc_value) {
        throw 'Created synthetic Candidate did not resolve uniquely or its AutoNumber did not reconcile.'
    }
    $script:candidateId = ([string]$candidateRows[0].os_sr_candid).ToLowerInvariant()
    Assert-Counts 'CreateCandidate'
    Assert-Status 100010000
    $creationReceipts = @(Get-Rows -Path "$($script:sets.Receipt)?%24select=os_sr_oprc_cact,os_sr_oprc_newstat,_os_sr_oprc_cand_value,_createdby_value,_ownerid_value,os_sr_oprc_hash&%24filter=$([Uri]::EscapeDataString("os_sr_oprc_corid eq '$creationCorrelation'"))&%24top=2")
    if ($creationReceipts.Count -ne 1 -or $creationReceipts[0].os_sr_oprc_cact -cne 'CreateCandidate' -or
        $creationReceipts[0].os_sr_oprc_newstat -ne '100010000' -or
        $creationReceipts[0]._os_sr_oprc_cand_value -ine $script:candidateId -or
        $creationReceipts[0]._createdby_value -ine $script:actorId -or $creationReceipts[0]._ownerid_value -ine $script:actorId -or
        $creationReceipts[0].os_sr_oprc_hash -cnotmatch '^[0-9a-f]{64}$') {
        throw 'CreateCandidate receipt did not reconcile before the runtime matrix.'
    }

    $noAnswer = [ordered]@{
        ActionType = 'RecordCall'; CorrelationId = (New-Correlation); CandidateId = $script:candidateId
        ExpectedStatus = 100010000; CallOutcome = 100010001; ContactedAt = [DateTime]::UtcNow.ToString('o')
    }
    $result = Invoke-Action -Body $noAnswer
    Assert-OperationResult $result 'Applied' 100010000 'RecordCall'
    $noAnswerCorrelation = [string]$noAnswer.CorrelationId
    $script:expectedCounts.Calls = 1
    $script:expectedCounts.Receipts = 2
    $firstNoAnswerCall = [string]$result.CallLogId
    $script:expectedReceiptEvidence[$noAnswerCorrelation] = @{
        Action = 'RecordCall'; CallId = $firstNoAnswerCall.ToLowerInvariant(); HistoryId = ''
    }
    Assert-Counts 'RecordCall no answer'
    Assert-Status 100010000
    $result = Invoke-Action -Body $noAnswer
    Assert-OperationResult $result 'DuplicateReplay' 100010000 'RecordCall'
    if ([string]$result.CallLogId -cne $firstNoAnswerCall) {
        $script:runtimeFailureClassification = 'IDEMPOTENCY_FAILURE'
        throw 'No-answer replay did not return original Call Log evidence.'
    }
    Assert-Counts 'RecordCall no-answer replay'
    if (-not $mvpVerticalSliceAuthorization) {
        $noAnswerConflict = $noAnswer.Clone()
        $noAnswerConflict.CallOutcome = 100010002
        $null = Invoke-Action -Body $noAnswerConflict -ExpectedFailure 'CORRELATION_CONFLICT'
        Assert-Counts 'RecordCall no-answer conflict'
    }

    $answered = [ordered]@{
        ActionType = 'RecordCall'; CorrelationId = (New-Correlation); CandidateId = $script:candidateId
        ExpectedStatus = 100010000; CallOutcome = 100010000; ContactedAt = [DateTime]::UtcNow.ToString('o')
    }
    $result = Invoke-Action -Body $answered
    Assert-OperationResult $result 'Applied' 100010001 'RecordCall'
    $answeredCorrelation = [string]$answered.CorrelationId
    $script:expectedCounts.Calls = 2
    $script:expectedCounts.History = 1
    $script:expectedCounts.Receipts = 3
    $firstAnsweredCall = [string]$result.CallLogId
    $firstAnsweredHistory = [string]$result.StatusHistoryId
    $script:expectedReceiptEvidence[$answeredCorrelation] = @{
        Action = 'RecordCall'; CallId = $firstAnsweredCall.ToLowerInvariant(); HistoryId = $firstAnsweredHistory.ToLowerInvariant()
    }
    Assert-Counts 'RecordCall answered'
    Assert-Status 100010001

    $proceed = [ordered]@{
        ActionType = 'ProceedToScheduling'; CorrelationId = (New-Correlation); CandidateId = $script:candidateId
        ExpectedStatus = 100010001
    }
    $result = Invoke-Action -Body $proceed
    Assert-OperationResult $result 'Applied' 100010002 'ProceedToScheduling'
    $proceedCorrelation = [string]$proceed.CorrelationId
    $script:expectedCounts.History = 2
    $script:expectedCounts.Receipts = 4
    $firstProceedHistory = [string]$result.StatusHistoryId
    $script:expectedReceiptEvidence[$proceedCorrelation] = @{
        Action = 'ProceedToScheduling'; CallId = ''; HistoryId = $firstProceedHistory.ToLowerInvariant()
    }
    Assert-Counts 'ProceedToScheduling'
    Assert-Status 100010002

    if (-not $mvpVerticalSliceAuthorization) {
        $stale = [ordered]@{
            ActionType = 'RecordCall'; CorrelationId = (New-Correlation); CandidateId = $script:candidateId
            ExpectedStatus = 100010001; CallOutcome = 100010001; ContactedAt = [DateTime]::UtcNow.ToString('o')
        }
        $null = Invoke-Action -Body $stale -ExpectedFailure 'STALE_EXPECTED_STATUS'
        Assert-NoEffect 'Stale-state rejection' 100010002

        $markScheduled = [ordered]@{
            ActionType = 'MarkRound1Scheduled'; CorrelationId = (New-Correlation)
            CandidateId = $script:candidateId; ExpectedStatus = 100010002
        }
        $null = Invoke-Action -Body $markScheduled -ExpectedFailure 'SCHEDULER_DEPENDENCY_UNAVAILABLE'
        Assert-NoEffect 'MarkRound1Scheduled without trusted scheduler evidence' 100010002
    }

    Assert-LiveEvidence
    Assert-Counts 'Final reconciliation'
    $resultClassification = if ($mvpDevGuardBypassAuthorization) {
        'CANDIDATE_CORE_MVP_RUNTIME_ACCEPTED_DEV_GUARD_BYPASS'
    } elseif ($mvpVerticalSliceAuthorization) {
        'CANDIDATE_CORE_MVP_RUNTIME_ACCEPTED'
    } else {
        'PHASE_3D_SYNTHETIC_RUNTIME_ACCEPTED'
    }
    $script:journal.Result = $resultClassification
    $script:journal.Dispatches = @($script:journal.Dispatches | ForEach-Object {
        [ordered]@{
            Index = $_.Index; Action = $_.Action; PayloadSha256 = $_.PayloadSha256
            State = $_.State; HttpStatus = $_.HttpStatus; ResultCode = $_.ResultCode
        }
    })
    $script:journal.CandidateIdSha256 = Get-Sha256 -Bytes ([Text.Encoding]::UTF8.GetBytes($script:candidateId))
    $script:journal.ActorIdSha256 = Get-Sha256 -Bytes ([Text.Encoding]::UTF8.GetBytes($script:actorId))
    $script:journal.FinalCounts = Get-ScopedCounts
    Save-RuntimeJournal
    [ordered]@{
        Result = $resultClassification
        AuthorizationId = $runtimeAuthorizationId
        CandidateFixtureCount = 1
        SyntheticName = '[SYNTHETIC-E2E] Candidate Core Acceptance'
        EmailDomain = '.invalid'
        RetainedCandidate = $true
        RetentionReason = 'Direct-delete guard and restrictive relationship policy remain intact.'
        RequestGET = $script:runtimeRequestCounts.GET
        CustomAPIInvocations = $script:apiCalls
        CandidateWrites = 1; CallLogWrites = 2; StatusHistoryWrites = 2; ReceiptWrites = 4
        TotalBusinessRecordWrites = 9
        Replays = 1
        Conflicts = if ($mvpVerticalSliceAuthorization) { 0 } else { 1 }
        ExpectedRejections = if ($mvpVerticalSliceAuthorization) { 0 } else { 2 }
        SchedulingEvidenceChecks = $schedulingEvidenceChecks
        PackageGuard = $packageGuard
        FinalCounts = $script:journal.FinalCounts
        CandidateIdReferenceSha256 = $script:journal.CandidateIdSha256
        ActorIdReferenceSha256 = $script:journal.ActorIdSha256
        AutomaticRetries = 0; AppWrites = 0; RoleWrites = 0; AuditSettingWrites = 0; PublishXml = 0
        DispatchEvidencePath = $RuntimeEvidencePath
    } | ConvertTo-Json -Depth 20
} catch {
    $safe = Get-SanitizedFailureMessage -Message $_.Exception.Message
    if ($script:journal) {
        $uncertain = @($script:journal.Dispatches | Where-Object State -CEQ 'UNCERTAIN_WRITE_OUTCOME').Count -gt 0
        $script:journal.Result = if ($uncertain) { 'UNCERTAIN_WRITE_OUTCOME' }
            elseif ($script:runtimeFailureClassification) { $script:runtimeFailureClassification }
            else { 'PHASE_3D_RUNTIME_STOPPED' }
        $script:journal.RuntimeFailureClassification = $script:runtimeFailureClassification
        $script:journal.Error = $safe
        $script:journal.CandidateIdSha256 = if ($script:candidateId) { Get-Sha256 -Bytes ([Text.Encoding]::UTF8.GetBytes($script:candidateId)) } else { $null }
        Save-RuntimeJournal
    }
    [ordered]@{
        Result = if ($script:journal -and $script:journal.Result) { [string]$script:journal.Result }
            else { 'PHASE_3D_RUNTIME_STOPPED' }
        Error = $safe
        RequestGET = $script:runtimeRequestCounts.GET
        CustomAPIInvocations = $script:apiCalls
        AutomaticRetries = 0
        RecordIdsPersisted = $false
        AppWrites = 0; RoleWrites = 0; AuditSettingWrites = 0; PublishXml = 0
    } | ConvertTo-Json -Depth 10
    throw "Candidate Core runtime acceptance stopped; no automatic retry or API resend. $safe"
} finally {
    $script:accessToken = $null
    [Environment]::SetEnvironmentVariable('BSO_RS_EXPECTED_USER_ID', $null, 'Process')
}
