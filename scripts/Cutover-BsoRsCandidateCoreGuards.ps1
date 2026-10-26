#requires -Version 7.4
[CmdletBinding()]
param(
    [ValidateSet('Preflight', 'Apply', 'Continue', 'Reconcile', 'Rollback')][string]$Mode = 'Preflight',
    [Parameter(Mandatory)][string]$EnvironmentName,
    [Parameter(Mandatory)][string]$OrganizationUrl,
    [Parameter(Mandatory)][string]$ExpectedEnvironmentId,
    [Parameter(Mandatory)][string]$ExpectedOrganizationId,
    [string]$RollbackMapPath,
    [string]$ExpectedRollbackMapSha256,
    [string]$DispatchEvidencePath,
    [string]$PriorDispatchEvidencePath,
    [string]$ExpectedPriorDispatchSha256,
    [string]$ExpectedDispatchEvidenceSha256,
    [string]$RootDispatchEvidencePath,
    [string]$ExpectedRootDispatchSha256
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$sourceRunner = Join-Path $PSScriptRoot 'Provision-BsoRsCandidateChildTables.ps1'
$runtimeRunner = Join-Path $PSScriptRoot 'Test-BsoRsCandidateCoreRuntime.ps1'
$script:ApiRoot = $OrganizationUrl.TrimEnd('/') + '/api/data/v9.2/'
$script:AccessToken = $null
$script:ExpectedUserId = $null
$script:RequestCounts = @{ GET = 0; PATCH = 0 }
$script:EventHandlerNavigation = $null
$script:Journal = $null
$script:JournalPath = $DispatchEvidencePath
$script:ActiveWrites = @()
$script:WriteIndex = 0
$script:LegacyGuardTypeId = $null
$script:PackageGuardTypeId = $null

$sourceTokens = $null
$sourceErrors = $null
$sourceAst = [System.Management.Automation.Language.Parser]::ParseFile($sourceRunner, [ref]$sourceTokens, [ref]$sourceErrors)
if ($sourceErrors.Count) { throw 'Existing guarded identity helper has parser errors.' }
foreach ($name in @('Assert-TargetInput', 'Assert-PacIdentity', 'Get-ValidatedToken',
    'Get-Sha256', 'Get-SanitizedDataverseError', 'Get-SanitizedFailureMessage')) {
    $definitions = @($sourceAst.EndBlock.Statements | Where-Object {
        $_ -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $_.Name -ceq $name
    })
    if ($definitions.Count -ne 1) { throw "Guarded helper is missing or ambiguous: $name" }
    . ([scriptblock]::Create($definitions[0].Extent.Text))
}

function Assert-LocalPath {
    param([string]$Path, [switch]$MustNotExist)
    if (-not $Path -or -not [IO.Path]::IsPathFullyQualified($Path)) {
        throw 'Evidence paths must be absolute local paths.'
    }
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        throw 'Evidence parent directory must already exist.'
    }
    if ($MustNotExist -and (Test-Path -LiteralPath $Path)) {
        throw 'A new evidence path is required; existing evidence is never overwritten.'
    }
}

function Save-NewJson {
    param([string]$Path, [object]$Value)
    $bytes = [Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $Value -Depth 80))
    $stream = [IO.File]::Open($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $stream.Write($bytes, 0, $bytes.Length); $stream.Flush($true) }
    finally { $stream.Dispose() }
}

function Save-Journal {
    $temporaryPath = $script:JournalPath + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    try {
        [IO.File]::WriteAllText($temporaryPath, (ConvertTo-Json -InputObject $script:Journal -Depth 80),
            [Text.UTF8Encoding]::new($false))
        if (Test-Path -LiteralPath $script:JournalPath) {
            [IO.File]::Move($temporaryPath, $script:JournalPath, $true)
        } else {
            [IO.File]::Move($temporaryPath, $script:JournalPath)
        }
    } finally {
        if (Test-Path -LiteralPath $temporaryPath) { [IO.File]::Delete($temporaryPath) }
    }
}

function Invoke-GuardRequest {
    param(
        [Parameter(Mandatory)][ValidateSet('GET', 'PATCH')][string]$Method,
        [Parameter(Mandatory)][string]$Path,
        [object]$Body
    )
    if ($Method -ceq 'PATCH' -and
        ($Mode -notin @('Apply', 'Continue', 'Rollback') -or
            $Path -notmatch '^sdkmessageprocessingsteps\([0-9a-fA-F-]{36}\)$' -or
            $null -eq $script:Journal -or $script:WriteIndex -ge $script:ActiveWrites.Count)) {
        throw 'Only a journaled SDK message processing step EventHandler PATCH is permitted.'
    }
    if ($Method -ceq 'PATCH') {
        $entry = $script:ActiveWrites[$script:WriteIndex]
        $expectedPath = "sdkmessageprocessingsteps($($entry.StepId))"
        $expectedBody = [ordered]@{ "$($script:EventHandlerNavigation)@odata.bind" = "/plugintypes($($entry.NewHandlerId))" }
        $actualJson = ConvertTo-Json -InputObject $Body -Depth 10 -Compress
        $expectedJson = ConvertTo-Json -InputObject $expectedBody -Depth 10 -Compress
        if ($Path -cne $expectedPath -or $entry.State -cne 'PLANNED' -or
            $actualJson -cne $expectedJson -or $Body.Count -ne 1) {
            throw 'EventHandler PATCH differs from its exact one-shot journal entry.'
        }
        $entry.State = 'DISPATCH_RESERVED'
        Save-Journal
        $script:WriteIndex++
    }
    $uri = [Uri]($script:ApiRoot + $Path)
    if ($uri.Scheme -cne 'https' -or $uri.Authority -ine ([Uri]$OrganizationUrl).Authority -or
        $uri.AbsolutePath -notmatch '^/api/data/v9\.2/' -or $uri.UserInfo -or $uri.Fragment) {
        throw 'Guard registration request is outside the verified Dataverse API.'
    }
    $headers = @{
        Authorization = "Bearer $script:AccessToken"
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
    if ($Method -ceq 'PATCH') {
        $arguments.Body = ConvertTo-Json -InputObject $Body -Depth 10 -Compress
        $arguments.ContentType = 'application/json; charset=utf-8'
    }
    $script:RequestCounts[$Method]++
    try { $response = Invoke-WebRequest @arguments }
    catch {
        if ($Method -ceq 'PATCH') {
        $script:ActiveWrites[$script:WriteIndex - 1].State = 'UNCERTAIN_WRITE_OUTCOME'
            Save-Journal
            throw 'UNCERTAIN_WRITE_OUTCOME; stop and reconcile without retry.'
        }
        throw 'Guard registration read failed; no automatic retry.'
    }
    $parsed = $null
    if (-not [string]::IsNullOrWhiteSpace([string]$response.Content)) {
        try { $parsed = $response.Content | ConvertFrom-Json }
        catch { throw 'Guard registration response was not valid JSON.' }
    }
    [pscustomobject]@{ StatusCode = [int]$response.StatusCode; Body = $parsed; Content = [string]$response.Content }
}

function Get-GuardRecord {
    param([string]$Path)
    $response = Invoke-GuardRequest -Method GET -Path $Path
    if ($response.StatusCode -lt 200 -or $response.StatusCode -ge 300 -or $null -eq $response.Body) {
        throw 'Guard registration read returned an unsuccessful or empty response.'
    }
    $response.Body
}

function Get-GuardRows {
    param([string]$Path)
    do {
        $page = Get-GuardRecord -Path $Path
        foreach ($row in @($page.value)) { $row }
        $next = [string]$page.'@odata.nextLink'
        if ($next) {
            if (-not $next.StartsWith($script:ApiRoot, [StringComparison]::OrdinalIgnoreCase)) {
                throw 'Foreign registration continuation rejected.'
            }
            $Path = $next.Substring($script:ApiRoot.Length)
        } else { $Path = $null }
    } while ($Path)
}

function Get-GuardHash {
    param([byte[]]$Bytes)
    Get-Sha256 -Bytes $Bytes
}

function ConvertTo-GuardPropertyValue {
    param([object]$Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [guid]) { return $Value.ToString('D').ToLowerInvariant() }
    if ($Value -is [DateTime]) { return $Value.ToUniversalTime().ToString('O') }
    if ($Value -is [DateTimeOffset]) { return $Value.ToUniversalTime().ToString('O') }
    if ($Value -is [ValueType] -or $Value -is [string]) { return $Value }
    ConvertTo-Json -InputObject $Value -Depth 40 -Compress
}

function Get-GuardStepSnapshot {
    param([string]$StepId, [object[]]$Memberships)
    $row = Get-GuardRecord -Path "sdkmessageprocessingsteps($StepId)"
    $attributes = [ordered]@{}
    $configuration = if ($null -eq $row.configuration) { $null } else { [string]$row.configuration }
    $configurationHash = if ($null -eq $configuration) { $null } else {
        Get-GuardHash -Bytes ([Text.Encoding]::UTF8.GetBytes($configuration))
    }
    foreach ($property in @($row.PSObject.Properties | Sort-Object Name)) {
        $name = [string]$property.Name
        if ($name.Contains('@') -or $name -in @(
            'sdkmessageprocessingstepid', '_eventhandler_value', 'eventhandler', 'configuration',
            'modifiedon', 'modifiedby', 'versionnumber'
        )) { continue }
        $attributes[$name] = ConvertTo-GuardPropertyValue -Value $property.Value
    }
    $attributes['configurationSha256'] = $configurationHash
    $canonical = [ordered]@{}
    foreach ($name in @($attributes.Keys | Sort-Object -CaseSensitive)) { $canonical[$name] = $attributes[$name] }
    $canonicalBytes = [Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $canonical -Depth 50 -Compress))
    [ordered]@{
        StepId = ([string]$row.sdkmessageprocessingstepid).ToLowerInvariant()
        Name = [string]$row.name
        HandlerId = ([string]$row._eventhandler_value).ToLowerInvariant()
        MessageId = ([string]$row._sdkmessageid_value).ToLowerInvariant()
        FilterId = ([string]$row._sdkmessagefilterid_value).ToLowerInvariant()
        RunAsUserId = ([string]$row._impersonatinguserid_value).ToLowerInvariant()
        SecureConfigurationId = ([string]$row._sdkmessageprocessingstepsecureconfigid_value).ToLowerInvariant()
        ConfigurationSha256 = $configurationHash
        ProtectedPropertyNames = @($canonical.Keys)
        ProtectedPropertiesSha256 = Get-GuardHash -Bytes $canonicalBytes
        SolutionMemberships = @($Memberships | Sort-Object SolutionId, ComponentType, RootComponentBehavior)
    }
}

function Get-GuardTopology {
    $packageRows = @(Get-GuardRows -Path "pluginpackages?`$select=pluginpackageid,name,uniquename,version&`$filter=uniquename eq 'os_sr_cact_pkg'")
    if ($packageRows.Count -ne 1 -or $packageRows[0].name -cne 'os_sr_cact_pkg' -or
        $packageRows[0].uniquename -cne 'os_sr_cact_pkg' -or [string]$packageRows[0].version -cne '1.0.0') {
        throw 'Existing Candidate Core plug-in package identity is absent, duplicated, or changed.'
    }
    $package = $packageRows[0]
    $packageId = ([string]$package.pluginpackageid).ToLowerInvariant()
    $packageRelations = @(Get-GuardRows -Path "EntityDefinitions(LogicalName='pluginassembly')/ManyToOneRelationships?`$select=ReferencingAttribute,ReferencedEntity,ReferencingEntityNavigationPropertyName" |
        Where-Object { $_.ReferencedEntity -ceq 'pluginpackage' })
    if ($packageRelations.Count -ne 1 -or -not $packageRelations[0].ReferencingAttribute) {
        throw 'Plug-in assembly package relationship is missing or ambiguous.'
    }
    $packageLookup = '_' + [string]$packageRelations[0].ReferencingAttribute + '_value'
    $packageAssemblies = @(Get-GuardRows -Path "pluginassemblies?`$select=pluginassemblyid,name,version,publickeytoken,sourcetype,$packageLookup&`$filter=$packageLookup eq $packageId")
    if ($packageAssemblies.Count -ne 1 -or $packageAssemblies[0].name -cne 'os_sr_cact' -or
        [string]$packageAssemblies[0].version -cne '1.0.0.0' -or
        [string]$packageAssemblies[0].$packageLookup -ine $packageId) {
        throw 'Package-backed Candidate Core assembly identity is not exact.'
    }
    $packageAssemblyId = ([string]$packageAssemblies[0].pluginassemblyid).ToLowerInvariant()
    $packageTypes = @(Get-GuardRows -Path "plugintypes?`$select=plugintypeid,typename,_pluginassemblyid_value&`$filter=_pluginassemblyid_value eq $packageAssemblyId")
    $expectedPackageTypeNames = @('os_sr_cact.ApplyCandidateAction', 'os_sr_cact.ProtectCandidateCore') | Sort-Object
    $actualPackageTypeNames = @($packageTypes | ForEach-Object { [string]$_.typename } | Sort-Object)
    if ($packageTypes.Count -ne 2 -or [string]::Join('|', $actualPackageTypeNames) -cne
        [string]::Join('|', $expectedPackageTypeNames)) {
        throw 'Package assembly PlugInType inventory is not exact.'
    }
    $packageHandler = @($packageTypes | Where-Object typename -CEQ 'os_sr_cact.ApplyCandidateAction')
    $packageGuard = @($packageTypes | Where-Object typename -CEQ 'os_sr_cact.ProtectCandidateCore')
    $packageHandlerId = ([string]$packageHandler[0].plugintypeid).ToLowerInvariant()
    $packageGuardId = ([string]$packageGuard[0].plugintypeid).ToLowerInvariant()

    $guardTypes = @(Get-GuardRows -Path "plugintypes?`$select=plugintypeid,typename,_pluginassemblyid_value&`$filter=typename eq 'os_sr_cact.ProtectCandidateCore'")
    $legacyGuardTypes = @($guardTypes | Where-Object { [string]$_._pluginassemblyid_value -ine $packageAssemblyId })
    if ($guardTypes.Count -ne 2 -or $legacyGuardTypes.Count -ne 1) {
        throw 'Legacy and package-backed guard PlugInType rollback targets are absent, duplicated, or unexpected.'
    }
    $legacyGuard = $legacyGuardTypes[0]
    $legacyGuardId = ([string]$legacyGuard.plugintypeid).ToLowerInvariant()
    $legacyAssemblyId = ([string]$legacyGuard._pluginassemblyid_value).ToLowerInvariant()
    if ($legacyAssemblyId -eq $packageAssemblyId) { throw 'Legacy and package-backed guard identities are not distinct.' }
    $legacyAssembly = Get-GuardRecord -Path "pluginassemblies($legacyAssemblyId)?`$select=pluginassemblyid,name,version,publickeytoken,$packageLookup"
    if ($legacyAssembly.name -cne 'os_sr_cact' -or [string]$legacyAssembly.version -cne '1.0.0.0' -or
        [string]$legacyAssembly.$packageLookup) {
        throw 'Legacy assembly rollback target is not the retained separate assembly.'
    }
    $legacyBinaryPath = Join-Path $root 'solutions\CandidateCore\bin\Release\net462\os_sr_cact.dll'
    $legacyBinaryHash = if (Test-Path -LiteralPath $legacyBinaryPath -PathType Leaf) {
        (Get-FileHash -LiteralPath $legacyBinaryPath -Algorithm SHA256).Hash.ToLowerInvariant()
    } else { $null }
    if ($legacyBinaryHash -cne '089deb40816e7fd6d80d117ba3894b5d5dadbcf65ac8111e25bb0520ff6feb85') {
        throw 'Retained legacy assembly fingerprint differs from the pinned rollback inventory.'
    }

    $apis = @(Get-GuardRows -Path "customapis?`$select=customapiid,uniquename,_plugintypeid_value&`$filter=uniquename eq 'os_sr_cact'")
    if ($apis.Count -ne 1 -or [string]$apis[0]._plugintypeid_value -ine $packageHandlerId) {
        throw 'Candidate Core Custom API is not mapped to the expected package-backed handler.'
    }
    $solutionRows = @(Get-GuardRows -Path "solutions?`$select=solutionid,uniquename,friendlyname,_publisherid_value&`$filter=uniquename eq 'os_sr_bso_rs_support'")
    if ($solutionRows.Count -ne 1) { throw 'Project Solution is absent or duplicated.' }
    $solution = $solutionRows[0]
    $publishers = @(Get-GuardRows -Path "publishers?`$select=publisherid,uniquename,customizationprefix&`$filter=publisherid eq $($solution._publisherid_value)")
    if ($publishers.Count -ne 1 -or [string]$publishers[0].customizationprefix -cne 'os') {
        throw 'Project Solution Publisher identity/prefix is not exact.'
    }
    $packageMetadata = Get-GuardRecord -Path "EntityDefinitions(LogicalName='pluginpackage')?`$select=ObjectTypeCode,EntitySetName,PrimaryIdAttribute"
    $packageComponents = @(Get-GuardRows -Path "solutioncomponents?`$select=objectid,componenttype,rootcomponentbehavior&`$filter=_solutionid_value eq $($solution.solutionid) and objectid eq $packageId")
    if ([int]$packageMetadata.ObjectTypeCode -le 0 -or
        $packageMetadata.EntitySetName -cne 'pluginpackages' -or
        $packageMetadata.PrimaryIdAttribute -cne 'pluginpackageid' -or
        $packageComponents.Count -ne 1 -or
        [string]$packageComponents[0].objectid -ine $packageId -or
        [int]$packageComponents[0].componenttype -ne [int]$packageMetadata.ObjectTypeCode) {
        throw 'Existing plug-in package is not an exact member of the project Solution.'
    }
    $eventHandlerRelationships = @(Get-GuardRows -Path "EntityDefinitions(LogicalName='sdkmessageprocessingstep')/ManyToOneRelationships?`$select=ReferencingAttribute,ReferencedEntity,ReferencingEntityNavigationPropertyName" |
        Where-Object { $_.ReferencingAttribute -ceq 'eventhandler' -and $_.ReferencedEntity -ceq 'plugintype' })
    if ($eventHandlerRelationships.Count -ne 1 -or
        -not $eventHandlerRelationships[0].ReferencingEntityNavigationPropertyName) {
        throw 'Supported SDK step EventHandler relationship is missing or ambiguous.'
    }
    $script:EventHandlerNavigation = [string]$eventHandlerRelationships[0].ReferencingEntityNavigationPropertyName

    $namedSteps = @(Get-GuardRows -Path "sdkmessageprocessingsteps?`$select=sdkmessageprocessingstepid,name,_eventhandler_value&`$filter=startswith(name,'os_sr_cact.guard.')")
    $handlerSteps = @(Get-GuardRows -Path "sdkmessageprocessingsteps?`$select=sdkmessageprocessingstepid,name,_eventhandler_value&`$filter=_eventhandler_value eq $legacyGuardId or _eventhandler_value eq $packageGuardId")
    $namedIds = @($namedSteps | ForEach-Object { ([string]$_.sdkmessageprocessingstepid).ToLowerInvariant() } | Sort-Object -Unique)
    $handlerIds = @($handlerSteps | ForEach-Object { ([string]$_.sdkmessageprocessingstepid).ToLowerInvariant() } | Sort-Object -Unique)
    if ($namedSteps.Count -eq 0 -or $namedSteps.Count -ne $namedIds.Count -or
        (Compare-Object $namedIds $handlerIds).Count -ne 0 -or
        @($handlerSteps | Where-Object { [string]$_.name -notlike 'os_sr_cact.guard.*' }).Count -ne 0) {
        throw 'Candidate Core guard step name/handler inventory is incomplete, duplicated, or unexpected.'
    }
    $contract = Get-Content -LiteralPath (Join-Path $root 'docs\PHASE_3C_API_CONTRACT.json') -Raw | ConvertFrom-Json
    $messages = @(Get-GuardRows -Path 'sdkmessages?$select=sdkmessageid,name')
    $expectedStepNames = [System.Collections.Generic.List[string]]::new()
    foreach ($table in @($contract.protectedTables)) {
        $filters = @(Get-GuardRows -Path "sdkmessagefilters?`$select=sdkmessagefilterid,_sdkmessageid_value,iscustomprocessingstepallowed&`$filter=primaryobjecttypecode eq '$table'")
        $supported = [System.Collections.Generic.List[string]]::new()
        foreach ($filter in $filters) {
            $message = @($messages | Where-Object { [string]$_.sdkmessageid -ieq [string]$filter._sdkmessageid_value })
            if ($message.Count -eq 1 -and $message[0].name -cin $contract.guardMessages -and $filter.iscustomprocessingstepallowed) {
                $supported.Add([string]$message[0].name)
                $expectedStepNames.Add("os_sr_cact.guard.$table.$($message[0].name)")
            }
        }
        foreach ($required in @('Create', 'Update', 'Delete')) {
            if ($required -cnotin $supported) { throw "Required direct-write guard hook unavailable: $table/$required" }
        }
    }
    foreach ($messageName in @('Associate', 'Disassociate')) {
        if (@($messages | Where-Object name -CEQ $messageName).Count -ne 1) {
            throw "Required relationship guard message is missing or ambiguous: $messageName"
        }
        $expectedStepNames.Add("os_sr_cact.guard.relationships.$messageName")
    }
    $expectedStepNames = @($expectedStepNames | Sort-Object -Unique)
    $actualStepNames = @($namedSteps | ForEach-Object { [string]$_.name } | Sort-Object -Unique)
    if ((Compare-Object $expectedStepNames $actualStepNames).Count -ne 0) {
        throw 'Live guard-step name inventory differs from the current approved message/table coverage.'
    }
    $stepSnapshots = foreach ($step in @($namedSteps | Sort-Object sdkmessageprocessingstepid)) {
        $stepId = ([string]$step.sdkmessageprocessingstepid).ToLowerInvariant()
        $memberships = @(Get-GuardRows -Path "solutioncomponents?`$select=objectid,componenttype,rootcomponentbehavior,_solutionid_value&`$filter=objectid eq $stepId and componenttype eq 92")
        $solutionMemberships = foreach ($membership in $memberships) {
            $membershipSolutionId = ([string]$membership._solutionid_value).ToLowerInvariant()
            $membershipSolution = Get-GuardRecord -Path "solutions($membershipSolutionId)?`$select=solutionid,uniquename"
            [ordered]@{
                SolutionId = $membershipSolutionId
                SolutionUniqueName = [string]$membershipSolution.uniquename
                ComponentType = [int]$membership.componenttype
                RootComponentBehavior = [int]$membership.rootcomponentbehavior
            }
        }
        if (@($solutionMemberships | Where-Object {
                $_.SolutionId -ieq [string]$solution.solutionid -and $_.ComponentType -eq 92
            }).Count -ne 1) {
            throw 'Guard step must have exactly one project Solution membership.'
        }
        $snapshot = Get-GuardStepSnapshot -StepId $stepId -Memberships @($solutionMemberships)
        if ($snapshot.Name -cnotlike 'os_sr_cact.guard.*' -or
            $snapshot.HandlerId -notin @($legacyGuardId, $packageGuardId)) {
            throw 'Guard step handler identity differs from both reconciled guard types.'
        }
        if ([int]$snapshot.ProtectedPropertiesSha256.Length -ne 64) {
            throw 'Guard step protected-property fingerprint is invalid.'
        }
        if ([string]$step.name -cne $snapshot.Name) { throw 'Guard step name changed during reconciliation.' }
        $detail = Get-GuardRecord -Path "sdkmessageprocessingsteps($stepId)?`$select=sdkmessageprocessingstepid,statecode,stage,mode,_impersonatinguserid_value"
        if ([int]$detail.statecode -ne 0 -or [int]$detail.stage -ne 10 -or [int]$detail.mode -ne 0 -or
            $null -ne $detail._impersonatinguserid_value) {
            throw 'Guard steps must remain enabled, synchronous, Pre-validation, and execute as the caller.'
        }
        $snapshot
    }
    [ordered]@{
        EnvironmentName = $EnvironmentName
        OrganizationUrl = $OrganizationUrl.TrimEnd('/')
        EnvironmentId = $ExpectedEnvironmentId.ToLowerInvariant()
        OrganizationId = $ExpectedOrganizationId.ToLowerInvariant()
        SolutionId = ([string]$solution.solutionid).ToLowerInvariant()
        SolutionUniqueName = [string]$solution.uniquename
        PublisherId = ([string]$publishers[0].publisherid).ToLowerInvariant()
        PublisherUniqueName = [string]$publishers[0].uniquename
        PublisherPrefix = [string]$publishers[0].customizationprefix
        PackageId = $packageId
        PackageSolutionComponentType = [int]$packageMetadata.ObjectTypeCode
        PackageSolutionRootBehavior = [int]$packageComponents[0].rootcomponentbehavior
        PackageUniqueName = [string]$package.uniquename
        PackageVersion = [string]$package.version
        PackageAssemblyId = $packageAssemblyId
        PackageHandlerTypeId = $packageHandlerId
        PackageGuardTypeId = $packageGuardId
        LegacyAssemblyId = $legacyAssemblyId
        LegacyGuardTypeId = $legacyGuardId
        LegacyAssemblySha256 = $legacyBinaryHash
        CreateCandidateApiId = ([string]$apis[0].customapiid).ToLowerInvariant()
        CreateCandidateApiHandlerTypeId = ([string]$apis[0]._plugintypeid_value).ToLowerInvariant()
        EventHandlerNavigation = $script:EventHandlerNavigation
        StepCount = @($stepSnapshots).Count
        Steps = @($stepSnapshots)
    }
}

function Assert-RuntimePreflight {
    $output = @(& $runtimeRunner -RuntimeMode Preflight -EnvironmentName $EnvironmentName `
        -OrganizationUrl $OrganizationUrl -ExpectedEnvironmentId $ExpectedEnvironmentId `
        -ExpectedOrganizationId $ExpectedOrganizationId -ExpectedHandlerPackageUniqueName 'os_sr_cact_pkg' 2>&1)
    if ($LASTEXITCODE -ne 0) { throw 'Candidate Core runtime preflight process failed.' }
    $result = $null
    try { $result = ($output -join "`n") | ConvertFrom-Json }
    catch { throw 'Candidate Core runtime preflight did not return its expected result.' }
    if ($result.Result -cne 'PHASE_3D_RUNTIME_PREFLIGHT_READY' -or
        @($result.FreshZeroRowCounts.PSObject.Properties | Where-Object { [int]$_.Value -ne 0 }).Count -ne 0 -or
        [int]$result.CustomAPIInvocations -ne 0 -or [int]$result.BusinessDataWrites -ne 0 -or
        [int]$result.AutomaticRetries -ne 0) {
        throw 'Candidate Core runtime preflight or fresh zero-row gate failed.'
    }
    [ordered]@{
        Result = [string]$result.Result
        FreshZeroRowCounts = $result.FreshZeroRowCounts
        CustomAPIInvocations = [int]$result.CustomAPIInvocations
        BusinessDataWrites = [int]$result.BusinessDataWrites
        AutomaticRetries = [int]$result.AutomaticRetries
    }
}

function Assert-PlanHash {
    if (-not $RollbackMapPath -or -not (Test-Path -LiteralPath $RollbackMapPath -PathType Leaf) -or
        $ExpectedRollbackMapSha256 -notmatch '^[0-9a-fA-F]{64}$') {
        throw 'A retained rollback map and its SHA-256 are required.'
    }
    $hash = (Get-FileHash -LiteralPath $RollbackMapPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($hash -cne $ExpectedRollbackMapSha256.ToLowerInvariant()) {
        throw 'Rollback map SHA-256 differs from the preflight-pinned map.'
    }
    $plan = Get-Content -LiteralPath $RollbackMapPath -Raw | ConvertFrom-Json
    if ($plan.EnvironmentId -ine $ExpectedEnvironmentId -or $plan.OrganizationId -ine $ExpectedOrganizationId -or
        $plan.OrganizationUrl.TrimEnd('/') -ine $OrganizationUrl.TrimEnd('/') -or
        $plan.PackageUniqueName -cne 'os_sr_cact_pkg' -or [string]$plan.PackageVersion -cne '1.0.0' -or
        $plan.StepCount -ne @($plan.Steps).Count -or $plan.StepCount -le 0) {
        throw 'Rollback map target or package/step identities do not match the pinned baseline.'
    }
    $plan
}

function Assert-PlanTopology {
    param([object]$Plan, [object]$Current, [string]$ExpectedHandlerState)
    foreach ($property in @(
        'EnvironmentId', 'OrganizationId', 'SolutionId', 'SolutionUniqueName', 'PublisherId',
        'PublisherUniqueName', 'PublisherPrefix', 'PackageId', 'PackageUniqueName', 'PackageVersion',
        'PackageSolutionComponentType', 'PackageSolutionRootBehavior',
        'PackageAssemblyId', 'PackageHandlerTypeId', 'PackageGuardTypeId', 'LegacyAssemblyId',
        'LegacyGuardTypeId', 'LegacyAssemblySha256', 'CreateCandidateApiId',
        'CreateCandidateApiHandlerTypeId', 'EventHandlerNavigation'
    )) {
        if ([string]$Plan.$property -cne [string]$Current.$property) {
            throw "Live guard topology differs from the preflight rollback map: $property."
        }
    }
    if ($Plan.StepCount -ne $Current.StepCount) { throw 'Live guard-step count differs from rollback map.' }
    $currentById = @{}
    foreach ($step in $Current.Steps) { $currentById[[string]$step.StepId] = $step }
    foreach ($planned in $Plan.Steps) {
        $live = $currentById[[string]$planned.StepId]
        if ($null -eq $live -or $live.Name -cne $planned.Name -or
            $live.ProtectedPropertiesSha256 -cne $planned.ProtectedPropertiesSha256 -or
            $live.ConfigurationSha256 -cne $planned.ConfigurationSha256 -or
            (ConvertTo-Json @($live.SolutionMemberships) -Depth 20 -Compress) -cne
                (ConvertTo-Json @($planned.SolutionMemberships) -Depth 20 -Compress)) {
            throw 'Guard step protected properties or Solution membership changed since preflight.'
        }
        $allowedHandler = if ($ExpectedHandlerState -ceq 'LEGACY') {
            [string]$Plan.LegacyGuardTypeId
        } elseif ($ExpectedHandlerState -ceq 'PACKAGE_OR_LEGACY') {
            @([string]$Plan.LegacyGuardTypeId, [string]$Plan.PackageGuardTypeId)
        } else { throw 'Unsupported expected handler state.' }
        if ([string]$live.HandlerId -notin @($allowedHandler)) {
            throw 'Guard step EventHandler differs from the allowed live topology.'
        }
    }
    $Current
}

function Get-ContinuationProgress {
    param([object]$Plan, [object]$Current, [object]$Prior, [object]$Root)
    $rootFailed = @($Root.Writes | Where-Object State -CEQ 'RECONCILIATION_FAILED')
    $rootPlanned = @($Root.Writes | Where-Object State -CEQ 'PLANNED')
    if ($Root.Mode -cne 'R4L_GUARD_STEP_CUTOVER' -or
        $Root.RollbackMapSha256 -cne $ExpectedRollbackMapSha256.ToLowerInvariant() -or
        $Root.EnvironmentId -ine $ExpectedEnvironmentId -or
        $Root.OrganizationId -ine $ExpectedOrganizationId -or
        $Root.OrganizationUrl.TrimEnd('/') -ine $OrganizationUrl.TrimEnd('/') -or
        [int]$Root.GuardStepCount -ne [int]$Plan.StepCount -or
        [int]$Root.Counts.PATCH -ne 1 -or
        [int]$Root.AutomaticRetries -ne 0 -or
        @($Root.RollbackWrites).Count -ne 0 -or
        @($Root.Writes).Count -ne [int]$Plan.StepCount -or
        $rootFailed.Count -ne 1 -or
        $rootPlanned.Count -ne ([int]$Plan.StepCount - 1) -or
        @($Root.Writes | Where-Object State -CNE 'PLANNED' |
            Where-Object State -CNE 'RECONCILIATION_FAILED').Count -ne 0) {
        throw 'Root dispatch journal differs from the exact one-write R4L baseline.'
    }

    $plannedById = @{}
    foreach ($step in $Plan.Steps) { $plannedById[[string]$step.StepId] = $step }
    $rootFailedStepId = [string]$rootFailed[0].StepId
    foreach ($entry in $Root.Writes) {
        $stepId = [string]$entry.StepId
        if (-not $plannedById.ContainsKey($stepId)) {
            throw 'Root dispatch journal contains an unknown guard-step entry.'
        }
        $planned = $plannedById[$stepId]
        if ($entry.Name -cne $planned.Name -or
            $entry.OldHandlerId -ine $Plan.LegacyGuardTypeId -or
            $entry.NewHandlerId -ine $Plan.PackageGuardTypeId -or
            $entry.ExpectedProtectedPropertiesSha256 -cne $planned.ProtectedPropertiesSha256 -or
            (ConvertTo-Json @($entry.SolutionMemberships) -Depth 20 -Compress) -cne
                (ConvertTo-Json @($planned.SolutionMemberships) -Depth 20 -Compress)) {
            throw 'Root dispatch entry differs from the exact guard-step rollback map.'
        }
        if ($stepId -ceq $rootFailedStepId) {
            if ($entry.HttpStatus -lt 200 -or $entry.HttpStatus -ge 300 -or
                $entry.ReadBackHandlerId -ine $Plan.PackageGuardTypeId -or
                $entry.ReadBackProtectedPropertiesSha256 -cne $planned.ProtectedPropertiesSha256 -or
                $null -ne $planned.ConfigurationSha256 -or
                $null -ne $entry.ReadBackConfigurationSha256 -or
                $entry.ExpectedConfigurationSha256 -isnot [string] -or
                $entry.ExpectedConfigurationSha256.Length -ne 0) {
                throw 'Root readback does not match the exact null-configuration coercion case.'
            }
        } elseif ($null -ne $entry.HttpStatus -or $null -ne $entry.ReadBackHandlerId) {
            throw 'Root planned entry contains unexpected dispatch evidence.'
        }
    }

    $priorGet = @($Prior.Writes | Where-Object State -CEQ 'GET_RECONCILED')
    $priorReserved = @($Prior.Writes | Where-Object State -CEQ 'DISPATCH_RESERVED')
    $priorPlanned = @($Prior.Writes | Where-Object State -CEQ 'PLANNED')
    if ($Prior.Mode -cne 'R4L_GUARD_STEP_CUTOVER_CONTINUATION' -or
        $Prior.RollbackMapSha256 -cne $ExpectedRollbackMapSha256.ToLowerInvariant() -or
        $Prior.EnvironmentId -ine $ExpectedEnvironmentId -or
        $Prior.OrganizationId -ine $ExpectedOrganizationId -or
        $Prior.OrganizationUrl.TrimEnd('/') -ine $OrganizationUrl.TrimEnd('/') -or
        [int]$Prior.GuardStepCount -ne [int]$Plan.StepCount -or
        [int]$Prior.PreviouslyReconciledGuardSteps -ne 1 -or
        [int]$Prior.Counts.PATCH -ne $priorGet.Count -or
        [int]$Prior.AutomaticRetries -ne 0 -or
        @($Prior.RollbackWrites).Count -ne 0 -or
        @($Prior.Writes).Count -ne ([int]$Plan.StepCount - 1) -or
        $priorGet.Count -ne 14 -or $priorReserved.Count -ne 1 -or $priorPlanned.Count -ne 34 -or
        @($Prior.Writes | Where-Object State -CNE 'GET_RECONCILED' |
            Where-Object State -CNE 'DISPATCH_RESERVED' |
            Where-Object State -CNE 'PLANNED').Count -ne 0) {
        throw 'Continuation journal is not the exact 14-reconciled, one-undispatched, 34-planned state.'
    }

    $continuationCompletedIds = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase)
    $pendingIds = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase)
    $priorById = @{}
    foreach ($entry in $Prior.Writes) {
        $stepId = [string]$entry.StepId
        if ($priorById.ContainsKey($stepId) -or -not $plannedById.ContainsKey($stepId) -or
            $stepId -ceq $rootFailedStepId) {
            throw 'Continuation journal contains a duplicate, unknown, or already-completed guard-step entry.'
        }
        $planned = $plannedById[$stepId]
        if ($entry.Name -cne $planned.Name -or
            $entry.OldHandlerId -ine $Plan.LegacyGuardTypeId -or
            $entry.NewHandlerId -ine $Plan.PackageGuardTypeId -or
            $entry.ExpectedProtectedPropertiesSha256 -cne $planned.ProtectedPropertiesSha256 -or
            $null -ne $planned.ConfigurationSha256 -or
            $null -ne $entry.ExpectedConfigurationSha256 -or
            (ConvertTo-Json @($entry.SolutionMemberships) -Depth 20 -Compress) -cne
                (ConvertTo-Json @($planned.SolutionMemberships) -Depth 20 -Compress)) {
            throw 'Continuation entry differs from the exact guard-step rollback map.'
        }
        $priorById[$stepId] = $entry
        if ($entry.State -ceq 'GET_RECONCILED') {
            if ($entry.HttpStatus -lt 200 -or $entry.HttpStatus -ge 300 -or
                $entry.ReadBackHandlerId -ine $Plan.PackageGuardTypeId -or
                $entry.ReadBackProtectedPropertiesSha256 -cne $planned.ProtectedPropertiesSha256 -or
                $null -ne $entry.ReadBackConfigurationSha256) {
                throw 'Reconciled continuation entry has inconsistent readback evidence.'
            }
            $continuationCompletedIds.Add($stepId) > $null
        } elseif ($entry.State -in @('PLANNED', 'DISPATCH_RESERVED')) {
            if ($null -ne $entry.HttpStatus -or $null -ne $entry.ReadBackHandlerId -or
                $null -ne $entry.ReadBackProtectedPropertiesSha256 -or
                $null -ne $entry.ReadBackConfigurationSha256) {
                throw 'Undispatched continuation entry contains unexpected write/readback evidence.'
            }
            if ($entry.State -ceq 'DISPATCH_RESERVED') { $pendingIds.Add($stepId) > $null }
            else { $pendingIds.Add($stepId) > $null }
        } else {
            throw 'Continuation journal contains an unresolved or unsupported dispatch state.'
        }
    }
    if ((Compare-Object @($continuationCompletedIds) @($priorGet | ForEach-Object { [string]$_.StepId })).Count -ne 0 -or
        (Compare-Object @($pendingIds) @($priorReserved + $priorPlanned |
            ForEach-Object { [string]$_.StepId })).Count -ne 0) {
        throw 'Continuation journal step-state inventory is inconsistent.'
    }

    $completedIds = [System.Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase)
    $completedIds.Add($rootFailedStepId) > $null
    foreach ($stepId in $continuationCompletedIds) { $completedIds.Add($stepId) > $null }
    if ($completedIds.Count -ne 15 -or $pendingIds.Count -ne 35) {
        throw 'Continuation package/legacy step counts differ from the reconciled dispatch journals.'
    }
    $currentById = @{}
    foreach ($step in $Current.Steps) { $currentById[[string]$step.StepId] = $step }
    foreach ($planned in $Plan.Steps) {
        $stepId = [string]$planned.StepId
        $expectedHandler = if ($completedIds.Contains($stepId)) {
            [string]$Plan.PackageGuardTypeId
        } else {
            [string]$Plan.LegacyGuardTypeId
        }
        if ([string]$currentById[$stepId].HandlerId -ine $expectedHandler) {
            throw 'Fresh live handler assignment differs from per-step dispatch evidence.'
        }
    }

    [pscustomobject]@{
        CompletedGuardSteps = $completedIds.Count
        PendingGuardSteps = $pendingIds.Count
        ReservedButUndispatchedGuardSteps = $priorReserved.Count
        CompletedStepIds = @($completedIds)
        PendingStepIds = @($pendingIds)
    }
}

function Invoke-GuardStepWrite {
    param(
        [object]$Write,
        [string]$ExpectedProtectedHash,
        [object[]]$ExpectedMemberships,
        [string]$JournalCollection
    )
    if ($JournalCollection -ceq 'RollbackWrites') {
        $script:ActiveWrites = @($script:Journal.RollbackWrites)
    } else {
        $script:ActiveWrites = @($script:Journal.Writes)
    }
    $script:WriteIndex = -1
    for ($index = 0; $index -lt $script:ActiveWrites.Count; $index++) {
        if ([string]$script:ActiveWrites[$index].StepId -ceq [string]$Write.StepId) {
            $script:WriteIndex = $index
            break
        }
    }
    if ($script:WriteIndex -lt 0) { throw 'Guard-step write does not belong to the durable journal.' }
    $path = "sdkmessageprocessingsteps($($Write.StepId))"
    $body = [ordered]@{ "$($script:EventHandlerNavigation)@odata.bind" = "/plugintypes($($Write.NewHandlerId))" }
    try { $response = Invoke-GuardRequest -Method PATCH -Path $path -Body $body }
    catch {
        if ($_.Exception.Message -notmatch 'UNCERTAIN_WRITE_OUTCOME') { throw }
        try {
            $uncertainReadback = Get-GuardStepSnapshot -StepId $Write.StepId -Memberships $ExpectedMemberships
            $Write.ReadBackHandlerId = $uncertainReadback.HandlerId
            $Write.ReadBackProtectedPropertiesSha256 = $uncertainReadback.ProtectedPropertiesSha256
            $Write.ReadBackConfigurationSha256 = $uncertainReadback.ConfigurationSha256
            $Write.ReadBackState = 'READ_AFTER_UNCERTAIN_WRITE'
        } catch {
            $Write.ReadBackState = 'READ_FAILED_AFTER_UNCERTAIN_WRITE'
            $Write.ReadBackError = Get-SanitizedFailureMessage -Message $_.Exception.Message
        }
        Save-Journal
        throw 'UNCERTAIN_WRITE_OUTCOME; immediate read attempted; stop without retry.'
    }
    $Write.HttpStatus = $response.StatusCode
    $Write.State = if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 300) {
        'ACKNOWLEDGED'
    } else { 'REJECTED' }
    Save-Journal
    $readback = Get-GuardStepSnapshot -StepId $Write.StepId -Memberships $ExpectedMemberships
    $Write.ReadBackHandlerId = $readback.HandlerId
    $Write.ReadBackProtectedPropertiesSha256 = $readback.ProtectedPropertiesSha256
    $Write.ReadBackConfigurationSha256 = $readback.ConfigurationSha256
    $Write.State = if ($readback.HandlerId -ieq $Write.NewHandlerId -and
        $readback.ProtectedPropertiesSha256 -ceq $ExpectedProtectedHash -and
        $readback.ConfigurationSha256 -ceq $Write.ExpectedConfigurationSha256 -and
        (ConvertTo-Json @($readback.SolutionMemberships) -Depth 20 -Compress) -ceq
            (ConvertTo-Json @($ExpectedMemberships) -Depth 20 -Compress) -and
        $response.StatusCode -ge 200 -and $response.StatusCode -lt 300) {
        'GET_RECONCILED'
    } else { 'RECONCILIATION_FAILED' }
    Save-Journal
    if ($Write.State -cne 'GET_RECONCILED') {
        throw 'GUARD_STEP_CUTOVER_RECONCILIATION_FAILED; stop without retry.'
    }
}

try {
    if ($EnvironmentName -cne 'VN LMV IT' -or ([Uri]$OrganizationUrl).Scheme -cne 'https') {
        throw 'R4L target must use the owner-confirmed VN LMV IT environment and an HTTPS organization URL.'
    }
    Assert-TargetInput
    Assert-PacIdentity
    Get-ValidatedToken
    $who = Get-GuardRecord -Path 'WhoAmI'
    if ([string]$who.UserId -ine $script:ExpectedUserId -or
        [string]$who.OrganizationId -ine $ExpectedOrganizationId) {
        throw 'Dataverse WhoAmI does not match the PAC expected-user and organization guards.'
    }

    if ($Mode -ceq 'Preflight') {
        Assert-LocalPath -Path $RollbackMapPath -MustNotExist
        $topology = Get-GuardTopology
        if (@($topology.Steps | Where-Object HandlerId -NE $topology.LegacyGuardTypeId).Count -ne 0) {
            throw 'R4L preflight expected every guard step to remain on the exact legacy handler.'
        }
        $runtimePreflight = Assert-RuntimePreflight
        Save-NewJson -Path $RollbackMapPath -Value $topology
        $mapHash = (Get-FileHash -LiteralPath $RollbackMapPath -Algorithm SHA256).Hash.ToLowerInvariant()
        [ordered]@{
            Result = 'GUARD_STEP_PREFLIGHT_READY'
            Environment = 'VN LMV IT'
            WhoAmIExpectedUserMatch = $true
            PackageUniqueName = $topology.PackageUniqueName
            PackageVersion = $topology.PackageVersion
            PackageBackedTypes = @('os_sr_cact.ApplyCandidateAction', 'os_sr_cact.ProtectCandidateCore')
            CreateCandidateHandlerPackageBacked = ($topology.CreateCandidateApiHandlerTypeId -ceq $topology.PackageHandlerTypeId)
            GuardStepCount = $topology.StepCount
            InitialGuardHandler = 'LEGACY'
            ProjectSolutionMemberships = $topology.StepCount
            RuntimePreflight = $runtimePreflight
            RollbackMapPath = $RollbackMapPath
            RollbackMapSha256 = $mapHash
            GET = $script:RequestCounts.GET
            PATCH = 0
            AutomaticRetries = 0
        } | ConvertTo-Json -Depth 20
        return
    }

    $plan = Assert-PlanHash
    $script:LegacyGuardTypeId = [string]$plan.LegacyGuardTypeId
    $script:PackageGuardTypeId = [string]$plan.PackageGuardTypeId
    $script:EventHandlerNavigation = [string]$plan.EventHandlerNavigation
    if ($Mode -ceq 'Reconcile') {
        $current = Get-GuardTopology
        $null = Assert-PlanTopology -Plan $plan -Current $current -ExpectedHandlerState 'PACKAGE_OR_LEGACY'
        if ($DispatchEvidencePath) {
            Assert-LocalPath -Path $DispatchEvidencePath
            Assert-LocalPath -Path $RootDispatchEvidencePath
            if (-not (Test-Path -LiteralPath $DispatchEvidencePath -PathType Leaf) -or
                -not (Test-Path -LiteralPath $RootDispatchEvidencePath -PathType Leaf) -or
                $ExpectedDispatchEvidenceSha256 -notmatch '^[0-9a-fA-F]{64}$' -or
                $ExpectedRootDispatchSha256 -notmatch '^[0-9a-fA-F]{64}$') {
                throw 'Journal-aware reconciliation requires both dispatch journals and their pinned SHA-256 values.'
            }
            $dispatchHash = (Get-FileHash -LiteralPath $DispatchEvidencePath -Algorithm SHA256).Hash.ToLowerInvariant()
            $rootHash = (Get-FileHash -LiteralPath $RootDispatchEvidencePath -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($dispatchHash -cne $ExpectedDispatchEvidenceSha256.ToLowerInvariant() -or
                $rootHash -cne $ExpectedRootDispatchSha256.ToLowerInvariant()) {
                throw 'Dispatch journal SHA-256 differs from its pinned evidence.'
            }
            $prior = Get-Content -LiteralPath $DispatchEvidencePath -Raw | ConvertFrom-Json
            $rootJournal = Get-Content -LiteralPath $RootDispatchEvidencePath -Raw | ConvertFrom-Json
            if ($prior.PriorDispatchSha256 -cne $rootHash) {
                throw 'Continuation journal is not linked to the pinned root dispatch journal.'
            }
            $progress = Get-ContinuationProgress -Plan $plan -Current $current -Prior $prior -Root $rootJournal
            [ordered]@{
                Result = 'GUARD_STEP_DISPATCH_PROGRESS_RECONCILED'
                GuardStepCount = $current.StepCount
                PackageBackedGuardSteps = $progress.CompletedGuardSteps
                LegacyGuardSteps = $progress.PendingGuardSteps
                PreviouslyReconciledGuardSteps = $progress.CompletedGuardSteps
                ReservedButUndispatchedGuardSteps = $progress.ReservedButUndispatchedGuardSteps
                ProtectedPropertiesChanged = 0
                SolutionMembershipsChanged = 0
                GET = $script:RequestCounts.GET
                PATCH = 0
                AutomaticRetries = 0
            } | ConvertTo-Json -Depth 10
            return
        }
        [ordered]@{
            Result = 'GUARD_STEP_TOPOLOGY_RECONCILED'
            GuardStepCount = $current.StepCount
            PackageBackedGuardSteps = @($current.Steps | Where-Object HandlerId -CEQ $plan.PackageGuardTypeId).Count
            LegacyGuardSteps = @($current.Steps | Where-Object HandlerId -CEQ $plan.LegacyGuardTypeId).Count
            ProtectedPropertiesChanged = 0
            SolutionMembershipsChanged = 0
            GET = $script:RequestCounts.GET
            PATCH = 0
            AutomaticRetries = 0
        } | ConvertTo-Json -Depth 10
        return
    }

    if ($Mode -ceq 'Continue') {
        Assert-LocalPath -Path $DispatchEvidencePath -MustNotExist
        Assert-LocalPath -Path $PriorDispatchEvidencePath
        if (-not (Test-Path -LiteralPath $PriorDispatchEvidencePath -PathType Leaf) -or
            $ExpectedPriorDispatchSha256 -notmatch '^[0-9a-fA-F]{64}$' -or
            [IO.Path]::GetFullPath($PriorDispatchEvidencePath) -ceq
                [IO.Path]::GetFullPath($DispatchEvidencePath)) {
            throw 'Continuation requires a distinct prior journal with a pinned SHA-256.'
        }
        $priorHash = (Get-FileHash -LiteralPath $PriorDispatchEvidencePath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($priorHash -cne $ExpectedPriorDispatchSha256.ToLowerInvariant()) {
            throw 'Prior dispatch journal SHA-256 differs from its pinned evidence.'
        }
        $prior = Get-Content -LiteralPath $PriorDispatchEvidencePath -Raw | ConvertFrom-Json
        if ($prior.Mode -ceq 'R4L_GUARD_STEP_CUTOVER_CONTINUATION') {
            Assert-LocalPath -Path $RootDispatchEvidencePath
            if (-not (Test-Path -LiteralPath $RootDispatchEvidencePath -PathType Leaf) -or
                $ExpectedRootDispatchSha256 -notmatch '^[0-9a-fA-F]{64}$' -or
                [IO.Path]::GetFullPath($RootDispatchEvidencePath) -ceq
                    [IO.Path]::GetFullPath($PriorDispatchEvidencePath)) {
                throw 'Continuation-of-continuation requires the distinct pinned root dispatch journal.'
            }
            $rootHash = (Get-FileHash -LiteralPath $RootDispatchEvidencePath -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($rootHash -cne $ExpectedRootDispatchSha256.ToLowerInvariant() -or
                $prior.PriorDispatchSha256 -cne $rootHash) {
                throw 'Continuation journal chain does not match the pinned root dispatch evidence.'
            }
            $rootJournal = Get-Content -LiteralPath $RootDispatchEvidencePath -Raw | ConvertFrom-Json
            $current = Get-GuardTopology
            $null = Assert-PlanTopology -Plan $plan -Current $current -ExpectedHandlerState 'PACKAGE_OR_LEGACY'
            $progress = Get-ContinuationProgress -Plan $plan -Current $current -Prior $prior -Root $rootJournal
            $runtimePreflight = Assert-RuntimePreflight
            $completedIds = [System.Collections.Generic.HashSet[string]]::new(
                [System.StringComparer]::OrdinalIgnoreCase)
            foreach ($stepId in $progress.CompletedStepIds) { $completedIds.Add([string]$stepId) > $null }
            $pendingSteps = @($plan.Steps | Where-Object { -not $completedIds.Contains([string]$_.StepId) } |
                Sort-Object StepId)
            if ($pendingSteps.Count -ne $progress.PendingGuardSteps) {
                throw 'Pending continuation step count differs from the journal-aware live reconciliation.'
            }
            $writes = @($pendingSteps | ForEach-Object {
                [ordered]@{
                    StepId = [string]$_.StepId
                    Name = [string]$_.Name
                    OldHandlerId = [string]$plan.LegacyGuardTypeId
                    NewHandlerId = [string]$plan.PackageGuardTypeId
                    ExpectedProtectedPropertiesSha256 = [string]$_.ProtectedPropertiesSha256
                    ExpectedConfigurationSha256 = $_.ConfigurationSha256
                    SolutionMemberships = @($_.SolutionMemberships)
                    State = 'PLANNED'
                    HttpStatus = $null
                    ReadBackHandlerId = $null
                }
            })
            $script:Journal = [ordered]@{
                SchemaVersion = 1
                Mode = 'R4L_GUARD_STEP_CUTOVER_CONTINUATION'
                EnvironmentName = $plan.EnvironmentName
                EnvironmentId = $plan.EnvironmentId
                OrganizationId = $plan.OrganizationId
                OrganizationUrl = $plan.OrganizationUrl
                RollbackMapSha256 = $ExpectedRollbackMapSha256.ToLowerInvariant()
                PriorDispatchSha256 = $priorHash
                RootDispatchSha256 = $rootHash
                PreviouslyReconciledGuardSteps = $progress.CompletedGuardSteps
                GuardStepCount = $plan.StepCount
                Writes = $writes
                RollbackWrites = @()
                Counts = @{ GET = $script:RequestCounts.GET; PATCH = 0 }
                AutomaticRetries = 0
                Result = 'DISPATCH_NOT_STARTED'
            }
            Save-NewJson -Path $DispatchEvidencePath -Value $script:Journal
            foreach ($write in $script:Journal.Writes) {
                Invoke-GuardStepWrite -Write $write `
                    -ExpectedProtectedHash ([string]$write.ExpectedProtectedPropertiesSha256) `
                    -ExpectedMemberships @($write.SolutionMemberships) -JournalCollection 'Writes'
                $script:Journal.Counts.PATCH = [int]$script:Journal.Counts.PATCH + 1
                $script:Journal.Counts.GET = $script:RequestCounts.GET
                Save-Journal
            }
            $final = Get-GuardTopology
            $null = Assert-PlanTopology -Plan $plan -Current $final -ExpectedHandlerState 'PACKAGE_OR_LEGACY'
            if (@($final.Steps | Where-Object HandlerId -NE $plan.PackageGuardTypeId).Count -ne 0) {
                throw 'Not all Candidate Core guard steps are package-backed after continuation.'
            }
            $script:Journal.Counts.GET = $script:RequestCounts.GET
            $script:Journal.Counts.PATCH = $script:RequestCounts.PATCH
            $script:Journal.Result = 'GUARD_STEP_CUTOVER_RECONCILED'
            Save-Journal
            [ordered]@{
                Result = 'GUARD_STEP_CUTOVER_RECONCILED'
                GuardStepCount = $plan.StepCount
                PreviouslyReconciledGuardSteps = $progress.CompletedGuardSteps
                ReservedButUndispatchedGuardSteps = $progress.ReservedButUndispatchedGuardSteps
                GuardStepPatches = $script:RequestCounts.PATCH
                PackageBackedGuardSteps = @($final.Steps).Count
                RuntimePreflight = $runtimePreflight
                GET = $script:RequestCounts.GET
                AutomaticRetries = 0
                RollbackMapPath = $RollbackMapPath
                DispatchEvidencePath = $DispatchEvidencePath
                PriorDispatchSha256 = $priorHash
                RootDispatchSha256 = $rootHash
            } | ConvertTo-Json -Depth 20
            return
        }
        if ($prior.Mode -cne 'R4L_GUARD_STEP_CUTOVER' -or
            $prior.RollbackMapSha256 -cne $ExpectedRollbackMapSha256.ToLowerInvariant() -or
            $prior.EnvironmentId -ine $ExpectedEnvironmentId -or
            $prior.OrganizationId -ine $ExpectedOrganizationId -or
            $prior.OrganizationUrl.TrimEnd('/') -ine $OrganizationUrl.TrimEnd('/') -or
            [int]$prior.GuardStepCount -ne [int]$plan.StepCount -or
            [int]$prior.AutomaticRetries -ne 0 -or
            @($prior.RollbackWrites).Count -ne 0 -or
            @($prior.Writes).Count -ne [int]$plan.StepCount) {
            throw 'Prior dispatch journal does not match this exact R4L rollback map and target.'
        }

        $plannedById = @{}
        foreach ($step in $plan.Steps) { $plannedById[[string]$step.StepId] = $step }
        $priorById = @{}
        foreach ($entry in $prior.Writes) {
            $stepId = [string]$entry.StepId
            if ($priorById.ContainsKey($stepId) -or -not $plannedById.ContainsKey($stepId)) {
                throw 'Prior dispatch journal has a duplicate or unknown guard-step entry.'
            }
            $planned = $plannedById[$stepId]
            if ($entry.Name -cne $planned.Name -or
                $entry.OldHandlerId -ine $plan.LegacyGuardTypeId -or
                $entry.NewHandlerId -ine $plan.PackageGuardTypeId -or
                $entry.ExpectedProtectedPropertiesSha256 -cne $planned.ProtectedPropertiesSha256 -or
                (ConvertTo-Json @($entry.SolutionMemberships) -Depth 20 -Compress) -cne
                    (ConvertTo-Json @($planned.SolutionMemberships) -Depth 20 -Compress)) {
                throw 'Prior dispatch entry differs from the exact guard-step rollback map.'
            }
            $priorById[$stepId] = $entry
        }
        $failedEntries = @($prior.Writes | Where-Object State -CEQ 'RECONCILIATION_FAILED')
        $plannedEntries = @($prior.Writes | Where-Object State -CEQ 'PLANNED')
        if ($failedEntries.Count -ne 1 -or
            $plannedEntries.Count -ne ([int]$plan.StepCount - 1) -or
            @($prior.Writes | Where-Object State -CNE 'PLANNED' |
                Where-Object State -CNE 'RECONCILIATION_FAILED').Count -ne 0) {
            throw 'Continuation is allowed only for one verified first-step readback mismatch and untouched planned entries.'
        }
        $failedEntry = $failedEntries[0]
        $failedPlan = $plannedById[[string]$failedEntry.StepId]
        if ($failedEntry.HttpStatus -lt 200 -or $failedEntry.HttpStatus -ge 300 -or
            $failedEntry.ReadBackHandlerId -ine $plan.PackageGuardTypeId -or
            $failedEntry.ExpectedProtectedPropertiesSha256 -cne $failedPlan.ProtectedPropertiesSha256 -or
            $failedEntry.ReadBackProtectedPropertiesSha256 -cne $failedPlan.ProtectedPropertiesSha256 -or
            $null -ne $failedPlan.ConfigurationSha256 -or
            $null -ne $failedEntry.ReadBackConfigurationSha256 -or
            $failedEntry.ExpectedConfigurationSha256 -isnot [string] -or
            $failedEntry.ExpectedConfigurationSha256.Length -ne 0) {
            throw 'Prior failed readback does not match the narrowly permitted null-configuration coercion case.'
        }

        $current = Get-GuardTopology
        $null = Assert-PlanTopology -Plan $plan -Current $current -ExpectedHandlerState 'PACKAGE_OR_LEGACY'
        $currentById = @{}
        foreach ($step in $current.Steps) { $currentById[[string]$step.StepId] = $step }
        foreach ($planned in $plan.Steps) {
            $expectedHandler = if ([string]$planned.StepId -ceq [string]$failedEntry.StepId) {
                [string]$plan.PackageGuardTypeId
            } else {
                [string]$plan.LegacyGuardTypeId
            }
            if ([string]$currentById[[string]$planned.StepId].HandlerId -ine $expectedHandler -or
                ($expectedHandler -ceq $plan.PackageGuardTypeId -and
                    [string]$currentById[[string]$planned.StepId].ConfigurationSha256 -cne
                    [string]$planned.ConfigurationSha256)) {
                throw 'Fresh topology does not match the one completed step and untouched continuation baseline.'
            }
        }
        $runtimePreflight = Assert-RuntimePreflight
        $writes = @($plannedEntries | Sort-Object StepId | ForEach-Object {
            $planned = $plannedById[[string]$_.StepId]
            [ordered]@{
                StepId = [string]$planned.StepId
                Name = [string]$planned.Name
                OldHandlerId = [string]$plan.LegacyGuardTypeId
                NewHandlerId = [string]$plan.PackageGuardTypeId
                ExpectedProtectedPropertiesSha256 = [string]$planned.ProtectedPropertiesSha256
                ExpectedConfigurationSha256 = $planned.ConfigurationSha256
                SolutionMemberships = @($planned.SolutionMemberships)
                State = 'PLANNED'
                HttpStatus = $null
                ReadBackHandlerId = $null
            }
        })
        $script:Journal = [ordered]@{
            SchemaVersion = 1
            Mode = 'R4L_GUARD_STEP_CUTOVER_CONTINUATION'
            EnvironmentName = $plan.EnvironmentName
            EnvironmentId = $plan.EnvironmentId
            OrganizationId = $plan.OrganizationId
            OrganizationUrl = $plan.OrganizationUrl
            RollbackMapSha256 = $ExpectedRollbackMapSha256.ToLowerInvariant()
            PriorDispatchSha256 = $priorHash
            PreviouslyReconciledGuardSteps = 1
            GuardStepCount = $plan.StepCount
            Writes = $writes
            RollbackWrites = @()
            Counts = @{ GET = $script:RequestCounts.GET; PATCH = 0 }
            AutomaticRetries = 0
            Result = 'DISPATCH_NOT_STARTED'
        }
        Save-NewJson -Path $DispatchEvidencePath -Value $script:Journal
        foreach ($write in $script:Journal.Writes) {
            Invoke-GuardStepWrite -Write $write `
                -ExpectedProtectedHash ([string]$write.ExpectedProtectedPropertiesSha256) `
                -ExpectedMemberships @($write.SolutionMemberships) -JournalCollection 'Writes'
            $script:Journal.Counts.PATCH = [int]$script:Journal.Counts.PATCH + 1
            $script:Journal.Counts.GET = $script:RequestCounts.GET
            Save-Journal
        }
        $final = Get-GuardTopology
        $null = Assert-PlanTopology -Plan $plan -Current $final -ExpectedHandlerState 'PACKAGE_OR_LEGACY'
        if (@($final.Steps | Where-Object HandlerId -NE $plan.PackageGuardTypeId).Count -ne 0) {
            throw 'Not all Candidate Core guard steps are package-backed after continuation.'
        }
        $script:Journal.Counts.GET = $script:RequestCounts.GET
        $script:Journal.Counts.PATCH = $script:RequestCounts.PATCH
        $script:Journal.Result = 'GUARD_STEP_CUTOVER_RECONCILED'
        Save-Journal
        [ordered]@{
            Result = 'GUARD_STEP_CUTOVER_RECONCILED'
            GuardStepCount = $plan.StepCount
            PreviouslyReconciledGuardSteps = 1
            GuardStepPatches = $script:RequestCounts.PATCH
            PackageBackedGuardSteps = @($final.Steps).Count
            RuntimePreflight = $runtimePreflight
            GET = $script:RequestCounts.GET
            AutomaticRetries = 0
            RollbackMapPath = $RollbackMapPath
            DispatchEvidencePath = $DispatchEvidencePath
            PriorDispatchSha256 = $priorHash
        } | ConvertTo-Json -Depth 20
        return
    }

    if ($Mode -ceq 'Apply') {
        Assert-LocalPath -Path $DispatchEvidencePath -MustNotExist
        $current = Get-GuardTopology
        $null = Assert-PlanTopology -Plan $plan -Current $current -ExpectedHandlerState 'LEGACY'
        $runtimePreflight = Assert-RuntimePreflight
        $writes = @($plan.Steps | Sort-Object StepId | ForEach-Object {
            [ordered]@{
                StepId = [string]$_.StepId
                Name = [string]$_.Name
                OldHandlerId = [string]$_.HandlerId
                NewHandlerId = [string]$plan.PackageGuardTypeId
                ExpectedProtectedPropertiesSha256 = [string]$_.ProtectedPropertiesSha256
                ExpectedConfigurationSha256 = $_.ConfigurationSha256
                SolutionMemberships = @($_.SolutionMemberships)
                State = 'PLANNED'
                HttpStatus = $null
                ReadBackHandlerId = $null
            }
        })
        $script:Journal = [ordered]@{
            SchemaVersion = 1
            Mode = 'R4L_GUARD_STEP_CUTOVER'
            EnvironmentName = $plan.EnvironmentName
            EnvironmentId = $plan.EnvironmentId
            OrganizationId = $plan.OrganizationId
            OrganizationUrl = $plan.OrganizationUrl
            RollbackMapSha256 = $ExpectedRollbackMapSha256.ToLowerInvariant()
            GuardStepCount = $plan.StepCount
            Writes = $writes
            RollbackWrites = @()
            Counts = @{ GET = $script:RequestCounts.GET; PATCH = 0 }
            AutomaticRetries = 0
            Result = 'DISPATCH_NOT_STARTED'
        }
        Save-NewJson -Path $DispatchEvidencePath -Value $script:Journal
        foreach ($write in $script:Journal.Writes) {
            Invoke-GuardStepWrite -Write $write `
                -ExpectedProtectedHash ([string]$write.ExpectedProtectedPropertiesSha256) `
                -ExpectedMemberships @($write.SolutionMemberships) -JournalCollection 'Writes'
            $script:Journal.Counts.PATCH = [int]$script:Journal.Counts.PATCH + 1
            $script:Journal.Counts.GET = $script:RequestCounts.GET
            Save-Journal
        }
        $final = Get-GuardTopology
        $null = Assert-PlanTopology -Plan $plan -Current $final -ExpectedHandlerState 'PACKAGE_OR_LEGACY'
        if (@($final.Steps | Where-Object HandlerId -NE $plan.PackageGuardTypeId).Count -ne 0) {
            throw 'Not all Candidate Core guard steps are package-backed after cutover.'
        }
        $script:Journal.Counts.GET = $script:RequestCounts.GET
        $script:Journal.Counts.PATCH = $script:RequestCounts.PATCH
        $script:Journal.Result = 'GUARD_STEP_CUTOVER_RECONCILED'
        Save-Journal
        [ordered]@{
            Result = 'GUARD_STEP_CUTOVER_RECONCILED'
            GuardStepCount = $plan.StepCount
            GuardStepPatches = $script:RequestCounts.PATCH
            PackageBackedGuardSteps = @($final.Steps).Count
            RuntimePreflight = $runtimePreflight
            GET = $script:RequestCounts.GET
            AutomaticRetries = 0
            RollbackMapPath = $RollbackMapPath
            DispatchEvidencePath = $DispatchEvidencePath
        } | ConvertTo-Json -Depth 20
        return
    }

    if ($Mode -ceq 'Rollback') {
        if (-not $DispatchEvidencePath -or -not (Test-Path -LiteralPath $DispatchEvidencePath -PathType Leaf)) {
            throw 'Rollback requires the retained R4L dispatch journal.'
        }
        $script:Journal = Get-Content -LiteralPath $DispatchEvidencePath -Raw | ConvertFrom-Json
        if ($script:Journal.RollbackMapSha256 -cne $ExpectedRollbackMapSha256.ToLowerInvariant() -or
            $script:Journal.EnvironmentId -ine $ExpectedEnvironmentId) {
            throw 'Rollback journal does not match the pinned map and active environment.'
        }
        $current = Get-GuardTopology
        $null = Assert-PlanTopology -Plan $plan -Current $current -ExpectedHandlerState 'PACKAGE_OR_LEGACY'
        if (@($script:Journal.RollbackWrites).Count -eq 0) {
            $rollbackCandidates = @($current.Steps | Where-Object HandlerId -CEQ $plan.PackageGuardTypeId)
            $script:Journal.RollbackWrites = @($rollbackCandidates | Sort-Object StepId | ForEach-Object {
                [ordered]@{
                    StepId = [string]$_.StepId
                    Name = [string]$_.Name
                    OldHandlerId = [string]$plan.PackageGuardTypeId
                    NewHandlerId = [string]$plan.LegacyGuardTypeId
                    ExpectedProtectedPropertiesSha256 = [string]$_.ProtectedPropertiesSha256
                    ExpectedConfigurationSha256 = $_.ConfigurationSha256
                    SolutionMemberships = @($_.SolutionMemberships)
                    State = 'PLANNED'
                    HttpStatus = $null
                    ReadBackHandlerId = $null
                }
            })
            $script:Journal.Counts.RollbackPatches = 0
            Save-Journal
        } else {
            foreach ($write in $script:Journal.RollbackWrites) {
                if ($write.State -in @('DISPATCH_RESERVED', 'UNCERTAIN_WRITE_OUTCOME', 'RECONCILIATION_FAILED', 'REJECTED')) {
                    throw 'Prior rollback attempt is unresolved; no rollback PATCH may be repeated.'
                }
                $plannedStep = @($plan.Steps | Where-Object StepId -CEQ $write.StepId)
                if ($plannedStep.Count -ne 1 -or
                    $write.NewHandlerId -ine $plan.LegacyGuardTypeId -or
                    $write.ExpectedProtectedPropertiesSha256 -cne $plannedStep[0].ProtectedPropertiesSha256) {
                    throw 'Retained rollback journal differs from the exact original step map.'
                }
            }
            $currentIds = @($current.Steps | Where-Object HandlerId -CEQ $plan.PackageGuardTypeId |
                ForEach-Object StepId | Sort-Object)
            $plannedRollbackIds = @($script:Journal.RollbackWrites |
                ForEach-Object { if ($_.State -eq 'PLANNED') { [string]$_.StepId } } | Sort-Object)
            if ((Compare-Object $currentIds $plannedRollbackIds).Count -ne 0) {
                throw 'Current package-backed guard steps differ from unconsumed rollback entries.'
            }
        }
        foreach ($write in $script:Journal.RollbackWrites) {
            if ($write.State -eq 'GET_RECONCILED') { continue }
            Invoke-GuardStepWrite -Write $write `
                -ExpectedProtectedHash ([string]$write.ExpectedProtectedPropertiesSha256) `
                -ExpectedMemberships @($write.SolutionMemberships) -JournalCollection 'RollbackWrites'
            $script:Journal.Counts.RollbackPatches = [int]$script:Journal.Counts.RollbackPatches + 1
            $script:Journal.Counts.GET = $script:RequestCounts.GET
            Save-Journal
        }
        $final = Get-GuardTopology
        $null = Assert-PlanTopology -Plan $plan -Current $final -ExpectedHandlerState 'PACKAGE_OR_LEGACY'
        if (@($final.Steps | Where-Object HandlerId -NE $plan.LegacyGuardTypeId).Count -ne 0) {
            throw 'Guard-step rollback did not restore every package-backed guard to its exact legacy type.'
        }
        $script:Journal.Counts.GET = $script:RequestCounts.GET
        $script:Journal.Counts.PATCH = $script:RequestCounts.PATCH
        $script:Journal.Result = 'GUARD_STEP_CUTOVER_ROLLED_BACK'
        Save-Journal
        [ordered]@{
            Result = 'GUARD_STEP_CUTOVER_ROLLED_BACK'
            RestoredGuardSteps = $script:Journal.Counts.RollbackPatches
            GET = $script:RequestCounts.GET
            AutomaticRetries = 0
            DispatchEvidencePath = $DispatchEvidencePath
        } | ConvertTo-Json -Depth 10
        return
    }
} catch {
    $safe = Get-SanitizedFailureMessage -Message $_.Exception.Message
    if ($script:Journal) {
        $script:Journal.Counts.GET = $script:RequestCounts.GET
        $script:Journal.Counts.PATCH = $script:RequestCounts.PATCH
        $script:Journal.Result = if ($safe -match 'UNCERTAIN_WRITE_OUTCOME') {
            'UNCERTAIN_WRITE_OUTCOME'
        } else { 'GUARD_STEP_CUTOVER_STOPPED' }
        $script:Journal.Error = $safe
        Save-Journal
    }
    [ordered]@{
        Result = if ($safe -match 'UNCERTAIN_WRITE_OUTCOME') { 'UNCERTAIN_WRITE_OUTCOME' }
            else { 'GUARD_STEP_CUTOVER_STOPPED' }
        Error = $safe
        GET = $script:RequestCounts.GET
        PATCH = $script:RequestCounts.PATCH
        AutomaticRetries = 0
    } | ConvertTo-Json -Depth 8
    throw 'Candidate Core guard-step migration stopped; no automatic retry or next step.'
} finally {
    $script:AccessToken = $null
    [Environment]::SetEnvironmentVariable('BSO_RS_EXPECTED_USER_ID', $null, 'Process')
}
