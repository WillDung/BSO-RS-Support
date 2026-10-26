#requires -Version 7.4
[CmdletBinding()]
param(
    [ValidateSet('Preflight', 'Apply', 'InspectPackage', 'Reconcile', 'Rollback',
        'CutoverExistingPreflight', 'CutoverExistingApply', 'RollbackExistingCutover')][string]$Mode = 'Preflight',
    [Parameter(Mandatory)][string]$EnvironmentName,
    [Parameter(Mandatory)][string]$OrganizationUrl,
    [Parameter(Mandatory)][string]$ExpectedEnvironmentId,
    [Parameter(Mandatory)][string]$ExpectedOrganizationId,
    [Parameter(Mandatory)][string]$LegacyDeploymentPlanPath,
    [Parameter(Mandatory)][string]$LegacyDispatchEvidencePath,
    [Parameter(Mandatory)][string]$AssemblyUpdatePlanPath,
    [Parameter(Mandatory)][string]$AssemblyUpdateEvidencePath,
    [string]$EvidencePath,
    [string]$RuntimeEvidencePath
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$sourceRunner = Join-Path $PSScriptRoot 'Provision-BsoRsCandidateChildTables.ps1'
$receiptRunner = Join-Path $PSScriptRoot 'Provision-BsoRsOperationReceipt.ps1'
$legacyRunner = Join-Path $PSScriptRoot 'Deploy-BsoRsCandidateOperations.ps1'
$packagePath = Join-Path $root 'solutions\CandidateCorePackage\bin\Release\os_sr_cact_pkg.1.0.0.nupkg'
$contractPath = Join-Path $root 'docs\PHASE_3C_API_CONTRACT.json'
$manifestPath = Join-Path $root 'docs\PHASE_3A_CANDIDATE_CORE_METADATA_PLAN.json'
$expectedPackageSha256 = 'f0403d61e3cfa92595e469e1332716a609c8d597c9d047bfc8bcb9a9379941b8'
$expectedDllSha256 = 'fd5f46e9d2e9388c7f5fefb90dc327ef9d1d40d241b5897c7e2913a92f2113b0'
$expectedInventorySha256 = '9df64f69b291f880e4d379899729f46196c6626a1f71658f6cad3f3d0be0fe92'
$expectedLegacyAssemblySha256 = '089deb40816e7fd6d80d117ba3894b5d5dadbcf65ac8111e25bb0520ff6feb85'
$script:RequestCounts = @{ GET = 0; POST = 0; PATCH = 0 }
$script:Journal = $null
$script:WriteIndex = 0
$script:Result = $null
$script:RuntimePreflightGET = 0
$script:NestedGETCounts = @{ Storage = 0; StrictLegacy = 0; StrictStorage = 0 }
$script:ApiRoot = $OrganizationUrl.TrimEnd('/') + '/api/data/v9.2/'
$script:AccessToken = $null
$script:Solution = $null
$script:Contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
$script:PackageIdentity = [ordered]@{
    Name = 'os_sr_cact_pkg'
    UniqueName = 'os_sr_cact_pkg'
    Version = '1.0.0'
    Assembly = 'os_sr_cact'
    AssemblyVersion = '1.0.0.0'
    Handler = 'os_sr_cact.ApplyCandidateAction'
    Guard = 'os_sr_cact.ProtectCandidateCore'
}

$sourceTokens = $null
$sourceErrors = $null
$sourceAst = [System.Management.Automation.Language.Parser]::ParseFile($sourceRunner, [ref]$sourceTokens, [ref]$sourceErrors)
if ($sourceErrors.Count) { throw 'Candidate Core metadata runner has parser errors.' }
foreach ($name in @(
    'Get-Sha256', 'Get-SanitizedDataverseError', 'Get-SanitizedFailureMessage',
    'Assert-TargetInput', 'Assert-PacIdentity', 'Get-ValidatedToken'
)) {
    $definitions = @($sourceAst.EndBlock.Statements | Where-Object {
        $_ -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $_.Name -ceq $name
    })
    if ($definitions.Count -ne 1) { throw "Guarded identity helper is missing or ambiguous: $name" }
    . ([scriptblock]::Create($definitions[0].Extent.Text))
}

function Save-PackageJournal {
    $bytes = [Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $script:Journal -Depth 30))
    $stream = [IO.File]::Open($EvidencePath, [IO.FileMode]::Open, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $stream.SetLength(0); $stream.Write($bytes, 0, $bytes.Length); $stream.Flush($true) }
    finally { $stream.Dispose() }
}

function Invoke-PackageRequest {
    param(
        [Parameter(Mandatory)][ValidateSet('GET', 'POST', 'PATCH')][string]$Method,
        [Parameter(Mandatory)][string]$Path,
        [object]$Body
    )
    $uri = [Uri]($script:ApiRoot + $Path)
    if ($uri.Scheme -cne 'https' -or $uri.Authority -ine ([Uri]$OrganizationUrl).Authority -or
        $uri.AbsolutePath -notmatch '^/api/data/v9\.2/' -or $uri.UserInfo -or $uri.Fragment) {
        throw 'Package request target is outside the pinned Dataverse API.'
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
    if ($Method -in @('POST', 'PATCH')) {
        if ($null -eq $script:Journal -or $script:WriteIndex -ge $script:Journal.Writes.Count) {
            throw 'Package write has no unconsumed precomputed journal entry.'
        }
        $entry = $script:Journal.Writes[$script:WriteIndex]
        $json = ConvertTo-Json -InputObject $Body -Depth 20 -Compress
        if ($entry.Method -cne $Method -or $entry.Path -cne $Path -or $entry.State -cne 'PLANNED' -or
            (Get-Sha256 -Bytes ([Text.Encoding]::UTF8.GetBytes($json))) -cne $entry.PayloadSha256) {
            throw 'Package write differs from its exact one-shot journal entry.'
        }
        if (($Method -ceq 'POST' -and ($Mode -cne 'Apply' -or $Path -cne 'pluginpackages')) -or
            ($Method -ceq 'PATCH' -and ($Mode -notin @('Apply', 'Rollback', 'CutoverExistingApply', 'RollbackExistingCutover') -or
                $Path -notmatch '^customapis\([0-9a-fA-F-]{36}\)$'))) {
            throw 'Package migration write path or mode is not authorized.'
        }
        $entry.State = 'DISPATCH_RESERVED'
        Save-PackageJournal
        $script:WriteIndex++
        $headers['MSCRM.SolutionUniqueName'] = 'os_sr_bso_rs_support'
        $arguments.Body = $json
        $arguments.ContentType = 'application/json; charset=utf-8'
    }
    $script:RequestCounts[$Method]++
    try { $response = Invoke-WebRequest @arguments }
    catch { throw 'UNCERTAIN_WRITE_OR_READ_TRANSPORT; reconcile immediately and never resend.' }
    if ($Method -in @('POST', 'PATCH')) {
        $entry.HttpStatus = [int]$response.StatusCode
        $entry.State = if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 300) { 'ACKNOWLEDGED' } else { 'REJECTED' }
        Save-PackageJournal
    }
    if ($response.StatusCode -lt 200 -or $response.StatusCode -ge 300) {
        $parsed = $null
        try { $parsed = $response.Content | ConvertFrom-Json } catch { $parsed = $null }
        throw (Get-SanitizedDataverseError -StatusCode $response.StatusCode -Response $parsed)
    }
    if (-not [string]::IsNullOrWhiteSpace($response.Content)) { $response.Content | ConvertFrom-Json }
}

function Get-PackageRows {
    param([string]$Path)
    do {
        $page = Invoke-PackageRequest -Method GET -Path $Path
        foreach ($row in @($page.value)) { $row }
        $next = [string]$page.'@odata.nextLink'
        if ($next) {
            if (-not $next.StartsWith($script:ApiRoot, [StringComparison]::OrdinalIgnoreCase)) {
                throw 'Foreign OData continuation rejected.'
            }
            $Path = $next.Substring($script:ApiRoot.Length)
        } else { $Path = $null }
    } while ($Path)
}

function Get-PackageArtifact {
    if (-not (Test-Path -LiteralPath $packagePath -PathType Leaf)) { throw 'Frozen package artifact is missing.' }
    $packageBytes = [IO.File]::ReadAllBytes($packagePath)
    $packageHash = Get-Sha256 -Bytes $packageBytes
    if ($packageHash -cne $expectedPackageSha256) { throw 'Frozen package SHA-256 changed; do not rebuild or dispatch.' }
    $archive = [IO.Compression.ZipFile]::OpenRead($packagePath)
    try {
        $entries = @($archive.Entries | Sort-Object FullName)
        $names = @($entries | ForEach-Object FullName)
        $expectedNames = @(
            '[Content_Types].xml', '_rels/.rels', 'lib/net462/os_sr_cact.dll',
            'os_sr_cact_pkg.nuspec', 'package/services/metadata/core-properties/nuget.psmdcp'
        ) | Sort-Object
        if (([string]::Join('|', $names)) -cne ([string]::Join('|', $expectedNames)) -or
            @($entries | Where-Object FullName -Match '\.(pdb|snk|pfx|key)$').Count) {
            throw 'Frozen package inventory contains unexpected content or signing material.'
        }
        $inventory = ($entries | ForEach-Object { '{0}|{1}|{2}' -f $_.FullName, $_.Length, $_.CompressedLength }) -join "`n"
        $inventoryHash = Get-Sha256 -Bytes ([Text.Encoding]::UTF8.GetBytes($inventory))
        if ($inventoryHash -cne $expectedInventorySha256) { throw 'Frozen package inventory fingerprint changed.' }
        $nuspecEntry = $archive.GetEntry('os_sr_cact_pkg.nuspec')
        $reader = [IO.StreamReader]::new($nuspecEntry.Open())
        try { [xml]$nuspec = $reader.ReadToEnd() } finally { $reader.Dispose() }
        $namespace = [Xml.XmlNamespaceManager]::new($nuspec.NameTable)
        $namespace.AddNamespace('n', 'http://schemas.microsoft.com/packaging/2012/06/nuspec.xsd')
        $packageName = $nuspec.SelectSingleNode('/n:package/n:metadata/n:id', $namespace).InnerText
        $packageVersion = $nuspec.SelectSingleNode('/n:package/n:metadata/n:version', $namespace).InnerText
        if ($packageName -cne $script:PackageIdentity.UniqueName -or $packageVersion -cne $script:PackageIdentity.Version) {
            throw 'Frozen NuGet package identity differs from the approved package.'
        }
        $dllEntry = $archive.GetEntry('lib/net462/os_sr_cact.dll')
        $dllStream = $dllEntry.Open()
        $memory = [IO.MemoryStream]::new()
        try {
            try { $dllStream.CopyTo($memory); $dllHash = Get-Sha256 -Bytes $memory.ToArray() }
            finally { $memory.Dispose() }
        } finally { $dllStream.Dispose() }
        if ($dllHash -cne $expectedDllSha256) { throw 'Contained assembly SHA-256 differs from the approved package.' }
    }
    finally { $archive.Dispose() }
    [ordered]@{
        Path = $packagePath
        Name = $script:PackageIdentity.Name
        UniqueName = $packageName
        Version = $packageVersion
        Sha256 = $packageHash
        DllSha256 = $dllHash
        InventorySha256 = $inventoryHash
        Length = $packageBytes.Length
        Bytes = $packageBytes
    }
}

function Get-StorageReconciliation {
    $output = @(& $receiptRunner -Mode Reconcile -EnvironmentName $EnvironmentName -OrganizationUrl $OrganizationUrl `
        -ExpectedEnvironmentId $ExpectedEnvironmentId -ExpectedOrganizationId $ExpectedOrganizationId 2>&1)
    if ($LASTEXITCODE -ne 0) { throw 'Fresh Operation Receipt/Candidate Core reconciliation failed.' }
    $result = ($output -join "`n") | ConvertFrom-Json
    if ($result.Result -cne 'OPERATION_RECEIPT_STORAGE_RECONCILED' -or $result.CandidateCore -cne 'EXACT' -or
        $result.Requests.POST -ne 0 -or $result.Requests.PUT -ne 0) {
        throw 'Fresh storage/identity gate is not exact.'
    }
    $result
}

function Get-RuntimeZeroRowGate {
    $runtimeRunner = Join-Path $PSScriptRoot 'Test-BsoRsCandidateCoreRuntime.ps1'
    $output = @(& $runtimeRunner -RuntimeMode Preflight -EnvironmentName $EnvironmentName `
        -OrganizationUrl $OrganizationUrl -ExpectedEnvironmentId $ExpectedEnvironmentId `
        -ExpectedOrganizationId $ExpectedOrganizationId 2>&1)
    if ($LASTEXITCODE -ne 0) { throw 'Fresh Candidate Core zero-row runtime preflight failed.' }
    $result = ($output -join "`n") | ConvertFrom-Json
    if ($result.Result -cne 'PHASE_3D_RUNTIME_PREFLIGHT_READY' -or
        @($result.FreshZeroRowCounts.PSObject.Properties | Where-Object { [int]$_.Value -ne 0 }).Count -ne 0 -or
        $result.CustomAPIInvocations -ne 0 -or $result.BusinessDataWrites -ne 0 -or
        $result.AutomaticRetries -ne 0) {
        throw 'Fresh Candidate Core business-row counts are nonzero or unknown.'
    }
    $script:RuntimePreflightGET = [int]$result.RequestGET
    $result
}

function Get-LegacyRegistrationReconciliation {
    foreach ($path in @($LegacyDeploymentPlanPath, $LegacyDispatchEvidencePath, $AssemblyUpdatePlanPath, $AssemblyUpdateEvidencePath)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'Retained legacy registration evidence is unavailable.' }
    }
    $plan = Get-Content -LiteralPath $LegacyDeploymentPlanPath -Raw | ConvertFrom-Json
    $update = Get-Content -LiteralPath $AssemblyUpdatePlanPath -Raw | ConvertFrom-Json
    $dispatch = Get-Content -LiteralPath $AssemblyUpdateEvidencePath -Raw | ConvertFrom-Json
    $planHash = (Get-FileHash -LiteralPath $LegacyDeploymentPlanPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $updateHash = (Get-FileHash -LiteralPath $AssemblyUpdatePlanPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $legacyDispatch = Get-Content -LiteralPath $LegacyDispatchEvidencePath -Raw | ConvertFrom-Json
    if ($update.DeploymentPlanSha256 -cne $planHash -or $dispatch.AssemblyUpdatePlanSha256 -cne $updateHash -or
        $legacyDispatch.DeploymentPlanSha256 -cne $planHash -or $legacyDispatch.AutomaticRetries -ne 0 -or
        @($legacyDispatch.Writes | Where-Object State -CNE 'GET_RECONCILED').Count -ne 0 -or
        $dispatch.AutomaticRetries -ne 0 -or $dispatch.Writes.Count -ne 1 -or
        $dispatch.Writes[0].State -cne 'GET_RECONCILED' -or
        $update.ExpectedNewAssemblySha256 -cne $expectedLegacyAssemblySha256) {
        throw 'Retained legacy registration evidence is inconsistent.'
    }
    $output = @(& $legacyRunner -DeploymentMode ReconcileAssemblyUpdate -EnvironmentName $EnvironmentName `
        -OrganizationUrl $OrganizationUrl -ExpectedEnvironmentId $ExpectedEnvironmentId `
        -ExpectedOrganizationId $ExpectedOrganizationId -DeploymentPlanPath $LegacyDeploymentPlanPath `
        -ExpectedDeploymentPlanSha256 $planHash -DispatchEvidencePath $AssemblyUpdateEvidencePath `
        -AssemblyUpdatePlanPath $AssemblyUpdatePlanPath -ExpectedAssemblyUpdatePlanSha256 $updateHash `
        -ExpectedCurrentAssemblySha256 $update.ExpectedCurrentAssemblySha256 `
        -ExpectedNewAssemblySha256 $update.ExpectedNewAssemblySha256 2>&1)
    if ($LASTEXITCODE -ne 0) { throw 'Strict legacy assembly/API/guard reconciliation failed.' }
    $result = ($output -join "`n") | ConvertFrom-Json
    if ($result.Result -cne 'CANDIDATE_CORE_ASSEMBLY_RECONCILED' -or
        $result.POST -ne 0 -or $result.PATCH -ne 0 -or $result.AutomaticRetries -ne 0) {
        throw 'Strict legacy assembly/API/guard reconciliation returned a non-exact result.'
    }
    [pscustomobject]@{ Result = $result; Plan = $plan; Update = $update; PlanHash = $planHash }
}

function Get-ApiSnapshot {
    $apis = @(Get-PackageRows -Path "customapis?`$select=customapiid,uniquename,name,displayname,description,executeprivilegename,bindingtype,isfunction,isprivate,allowedcustomprocessingsteptype,_plugintypeid_value&`$filter=uniquename eq '$($script:Contract.uniqueName)'")
    if ($apis.Count -ne 1) { throw 'Candidate Core Custom API inventory is missing or duplicated.' }
    $api = $apis[0]
    $inputs = @(Get-PackageRows -Path "customapirequestparameters?`$filter=_customapiid_value eq $($api.customapiid)")
    $outputs = @(Get-PackageRows -Path "customapiresponseproperties?`$filter=_customapiid_value eq $($api.customapiid)")
    $expectedInputs = @($script:Contract.inputs | ForEach-Object {
        '{0}|{1}|{2}' -f $_.name, [int]$_.type, [bool]$_.optional
    } | Sort-Object)
    $actualInputs = @($inputs | ForEach-Object {
        '{0}|{1}|{2}' -f $_.uniquename, [int]$_.type, [bool]$_.isoptional
    } | Sort-Object)
    $expectedOutputs = @($script:Contract.outputs | ForEach-Object {
        '{0}|{1}' -f $_.name, [int]$_.type
    } | Sort-Object)
    $actualOutputs = @($outputs | ForEach-Object {
        '{0}|{1}' -f $_.uniquename, [int]$_.type
    } | Sort-Object)
    if ($api.uniquename -cne $script:Contract.uniqueName -or
        $api.executeprivilegename -cne $script:Contract.executePrivilegeName -or
        [int]$api.bindingtype -ne [int]$script:Contract.bindingType -or
        [bool]$api.isfunction -ne [bool]$script:Contract.isFunction -or
        [bool]$api.isprivate -ne [bool]$script:Contract.isPrivate -or
        [int]$api.allowedcustomprocessingsteptype -ne [int]$script:Contract.allowedCustomProcessingStepType -or
        $inputs.Count -ne $script:Contract.inputs.Count -or
        ([string]::Join(';', $actualInputs) -cne [string]::Join(';', $expectedInputs)) -or
        $outputs.Count -ne $script:Contract.outputs.Count -or
        ([string]::Join(';', $actualOutputs) -cne [string]::Join(';', $expectedOutputs))) {
        throw 'Custom API contract differs from the current approved contract.'
    }
    $canonicalApi = [ordered]@{
        customapiid = [string]$api.customapiid
        uniquename = [string]$api.uniquename
        name = [string]$api.name
        displayname = [string]$api.displayname
        description = [string]$api.description
        executeprivilegename = [string]$api.executeprivilegename
        bindingtype = [int]$api.bindingtype
        isfunction = [bool]$api.isfunction
        isprivate = [bool]$api.isprivate
        allowedcustomprocessingsteptype = [int]$api.allowedcustomprocessingsteptype
        inputs = @($inputs | Sort-Object uniquename | ForEach-Object {
            [ordered]@{ uniquename = [string]$_.uniquename; type = [int]$_.type; isoptional = [bool]$_.isoptional }
        })
        outputs = @($outputs | Sort-Object uniquename | ForEach-Object {
            [ordered]@{ uniquename = [string]$_.uniquename; type = [int]$_.type }
        })
    }
    $json = ConvertTo-Json -InputObject $canonicalApi -Depth 15 -Compress
    [pscustomobject]@{
        Api = $api
        HandlerId = [string]$api._plugintypeid_value
        NonHandlerSha256 = Get-Sha256 -Bytes ([Text.Encoding]::UTF8.GetBytes($json))
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

function Get-PackageRowsByName {
    $rows = @(Get-PackageRows -Path "pluginpackages?`$select=pluginpackageid,name,uniquename,version,modifiedon,content&`$filter=uniquename eq '$($script:PackageIdentity.UniqueName)'")
    $rows
}

function Assert-PackageProcessingMetadata {
    $assemblyRelationships = @(Get-PackageRows -Path "EntityDefinitions(LogicalName='pluginassembly')/ManyToOneRelationships?`$select=ReferencingAttribute,ReferencedEntity,ReferencingEntityNavigationPropertyName" |
        Where-Object ReferencedEntity -CEQ 'pluginpackage')
    if ($assemblyRelationships.Count -ne 1 -or -not $assemblyRelationships[0].ReferencingAttribute -or
        -not $assemblyRelationships[0].ReferencingEntityNavigationPropertyName) {
        throw 'Package-to-assembly lookup relationship is missing or ambiguous before create.'
    }
    $sourceMetadata = Invoke-PackageRequest -Method GET -Path "EntityDefinitions(LogicalName='pluginassembly')/Attributes(LogicalName='sourcetype')/Microsoft.Dynamics.CRM.PicklistAttributeMetadata?`$select=LogicalName&`$expand=OptionSet"
    $packageSourceOptions = @($sourceMetadata.OptionSet.Options | Where-Object {
        $labels = @($_.Label.LocalizedLabels | ForEach-Object Label) + [string]$_.Label.UserLocalizedLabel.Label
        @($labels | Where-Object { $_ -match '(?i)package|file.?store' }).Count -gt 0
    })
    if ($sourceMetadata.LogicalName -cne 'sourcetype' -or $packageSourceOptions.Count -eq 0) {
        throw 'Live Plug-in Assembly SourceType does not expose a Package/FileStore option before create.'
    }
    $apiRelationships = @(Get-PackageRows -Path "EntityDefinitions(LogicalName='customapi')/ManyToOneRelationships?`$select=ReferencingAttribute,ReferencedEntity,ReferencingEntityNavigationPropertyName" |
        Where-Object { $_.ReferencedEntity -ceq 'plugintype' -and $_.ReferencingAttribute -ceq 'plugintypeid' })
    if ($apiRelationships.Count -ne 1 -or -not $apiRelationships[0].ReferencingEntityNavigationPropertyName) {
        throw 'Custom API handler navigation metadata is missing or ambiguous before create.'
    }
    [pscustomobject]@{
        PackageLookupAttribute = [string]$assemblyRelationships[0].ReferencingAttribute
        PackageNavigationProperty = [string]$assemblyRelationships[0].ReferencingEntityNavigationPropertyName
        PackageSourceTypeValues = @($packageSourceOptions | ForEach-Object { [int]$_.Value } | Sort-Object -Unique)
        HandlerNavigationProperty = [string]$apiRelationships[0].ReferencingEntityNavigationPropertyName
    }
}

function Assert-PackageReadback {
    param([object[]]$Rows, [string]$ExpectedPackageSha256 = $expectedPackageSha256)
    if ($Rows.Count -ne 1) { throw 'Exact package UniqueName did not resolve to one row.' }
    $row = $Rows[0]
    if ($row.name -cne $script:PackageIdentity.Name -or $row.uniquename -cne $script:PackageIdentity.UniqueName -or
        [string]$row.version -cne $script:PackageIdentity.Version -or [string]::IsNullOrWhiteSpace([string]$row.content)) {
        throw 'Live Plug-in Package metadata differs from the frozen package.'
    }
    $hash = Get-Sha256 -Bytes ([Convert]::FromBase64String([string]$row.content))
    if ($hash -cne $ExpectedPackageSha256) { throw 'Live Plug-in Package content hash differs from the frozen artifact.' }
    $row
}

function Get-PackageAssemblyAndTypes {
    param([string]$PackageId, [int]$MaximumReadChecks = 1)
    $relationships = @(Get-PackageRows -Path "EntityDefinitions(LogicalName='pluginassembly')/ManyToOneRelationships?`$select=ReferencingAttribute,ReferencedEntity,ReferencingEntityNavigationPropertyName" |
        Where-Object ReferencedEntity -CEQ 'pluginpackage')
    if ($relationships.Count -ne 1 -or -not $relationships[0].ReferencingAttribute) {
        throw 'Package-to-assembly lookup relationship is missing or ambiguous.'
    }
    $lookup = [string]$relationships[0].ReferencingAttribute
    $lookupValue = "_${lookup}_value"
    $assemblyRows = @()
    for ($attempt = 1; $attempt -le $MaximumReadChecks; $attempt++) {
        $assemblyRows = @(Get-PackageRows -Path "pluginassemblies?`$select=pluginassemblyid,name,version,publickeytoken,sourcetype,$lookupValue&`$filter=$lookupValue eq $PackageId")
        if ($assemblyRows.Count -gt 0 -or $attempt -eq $MaximumReadChecks) { break }
        Start-Sleep -Seconds 2
    }
    if ($assemblyRows.Count -ne 1) { throw 'PLUGIN_PACKAGE_PROCESSING_FAILED: package-backed assembly is absent or duplicated.' }
    $assembly = $assemblyRows[0]
    if ($assembly.name -cne $script:PackageIdentity.Assembly -or
        [string]$assembly.version -cne $script:PackageIdentity.AssemblyVersion -or
        [string]$assembly.$lookupValue -ine $PackageId) {
        throw 'Package-backed assembly identity or package relationship mismatch.'
    }
    $sourceMetadata = Invoke-PackageRequest -Method GET -Path "EntityDefinitions(LogicalName='pluginassembly')/Attributes(LogicalName='sourcetype')/Microsoft.Dynamics.CRM.PicklistAttributeMetadata?`$select=LogicalName&`$expand=OptionSet"
    $sourceOptions = @($sourceMetadata.OptionSet.Options | Where-Object { [int]$_.Value -eq [int]$assembly.sourcetype })
    $sourceLabels = @($sourceOptions | ForEach-Object {
        @($_.Label.LocalizedLabels | ForEach-Object Label) + [string]$_.Label.UserLocalizedLabel.Label
    } | Where-Object { $_ } | Sort-Object -Unique)
    if ($sourceOptions.Count -ne 1 -or
        @($sourceLabels | Where-Object { $_ -match '(?i)package|file.?store' }).Count -eq 0) {
        throw 'Package-backed assembly SourceType is not the live metadata Package/FileStore option.'
    }
    $types = @(Get-PackageRows -Path "plugintypes?`$select=plugintypeid,typename,_pluginassemblyid_value&`$filter=_pluginassemblyid_value eq $($assembly.pluginassemblyid)")
    $expectedTypes = @($script:PackageIdentity.Handler, $script:PackageIdentity.Guard) | Sort-Object
    $actualTypes = @($types | ForEach-Object { [string]$_.typename } | Sort-Object)
    if ($types.Count -ne 2 -or @($actualTypes | Select-Object -Unique).Count -ne 2 -or
        [string]::Join('|', $actualTypes) -cne [string]::Join('|', $expectedTypes)) {
        throw 'Package-backed PlugInType inventory is not exactly the approved handler and guard.'
    }
    [pscustomobject]@{ Assembly = $assembly; Types = $types; SourceTypeLabels = $sourceLabels }
}

function Assert-PackageSolutionMembership {
    param([string]$PackageId)
    $metadata = Invoke-PackageRequest -Method GET -Path "EntityDefinitions(LogicalName='pluginpackage')?`$select=EntitySetName,PrimaryIdAttribute,ObjectTypeCode"
    if ($metadata.EntitySetName -cne 'pluginpackages' -or $metadata.PrimaryIdAttribute -cne 'pluginpackageid' -or
        [int]$metadata.ObjectTypeCode -le 0) { throw 'Plug-in Package table metadata is not the supported expected entity.' }
    $solutionId = [string]$script:Solution.solutionid
    $rows = @(Get-PackageRows -Path "solutioncomponents?`$select=objectid,componenttype&`$filter=_solutionid_value eq $solutionId and objectid eq $PackageId")
    if ($rows.Count -ne 1 -or [string]$rows[0].objectid -ine $PackageId -or
        [int]$rows[0].componenttype -ne [int]$metadata.ObjectTypeCode) {
        throw 'Plug-in Package is not exactly a member of the approved unmanaged Solution.'
    }
}

function Assert-SolutionComponentMembership {
    param(
        [Parameter(Mandatory)][string]$EntityLogicalName,
        [Parameter(Mandatory)][string]$ComponentId,
        [int]$ExpectedComponentType = -1
    )
    $metadata = Invoke-PackageRequest -Method GET -Path "EntityDefinitions(LogicalName='$EntityLogicalName')?`$select=ObjectTypeCode,EntitySetName,PrimaryIdAttribute"
    if ([int]$metadata.ObjectTypeCode -le 0 -or -not $metadata.EntitySetName -or -not $metadata.PrimaryIdAttribute) {
        throw "Solution component metadata is incomplete: $EntityLogicalName."
    }
    if ($ExpectedComponentType -lt 0) { $ExpectedComponentType = [int]$metadata.ObjectTypeCode }
    $rows = @(Get-PackageRows -Path "solutioncomponents?`$select=objectid,componenttype&`$filter=_solutionid_value eq $($script:Solution.solutionid) and objectid eq $ComponentId")
    if ($rows.Count -ne 1 -or [string]$rows[0].objectid -ine $ComponentId -or
        [int]$rows[0].componenttype -ne $ExpectedComponentType) {
        $actualTypes = @($rows | ForEach-Object { [string]$_.componenttype }) -join ','
        throw "Component Solution membership mismatch for $EntityLogicalName (rows=$($rows.Count), expectedType=$ExpectedComponentType, actualTypes=$actualTypes)."
    }
}

function Get-LegacyHandlers {
    param([object]$Plan)
    $assemblyWrite = @($Plan.Writes | Where-Object Path -CEQ 'pluginassemblies')
    if ($assemblyWrite.Count -ne 1) { throw 'Retained plan does not identify exactly one legacy assembly.' }
    $assemblyId = [string]$assemblyWrite[0].Id
    $assembly = Invoke-PackageRequest -Method GET -Path "pluginassemblies($assemblyId)?`$select=pluginassemblyid,name,version,publickeytoken,isolationmode,sourcetype,content"
    if ([string]$assembly.pluginassemblyid -ine $assemblyId -or $assembly.name -cne 'os_sr_cact' -or
        $assembly.version -cne '1.0.0.0' -or
        (Get-Sha256 -Bytes ([Convert]::FromBase64String([string]$assembly.content))) -cne $expectedLegacyAssemblySha256) {
        throw 'Legacy signed assembly changed from its retained successful state.'
    }
    $typeRows = @(Get-PackageRows -Path "plugintypes?`$select=plugintypeid,typename,_pluginassemblyid_value&`$filter=_pluginassemblyid_value eq $assemblyId")
    $expectedNames = @($script:PackageIdentity.Handler, $script:PackageIdentity.Guard) | Sort-Object
    $actualNames = @($typeRows | ForEach-Object { [string]$_.typename } | Sort-Object)
    if ($typeRows.Count -ne 2 -or [string]::Join('|', $actualNames) -cne [string]::Join('|', $expectedNames)) {
        throw 'Legacy assembly PlugInType inventory differs from the retained plan.'
    }
    $guardType = @($typeRows | Where-Object typename -CEQ $script:PackageIdentity.Guard)
    if ($guardType.Count -ne 1) { throw 'Legacy guard type identity is ambiguous.' }
    $stepWrites = @($Plan.Writes | Where-Object Path -CEQ 'sdkmessageprocessingsteps')
    $liveSteps = @()
    foreach ($write in $stepWrites) {
        $step = Invoke-PackageRequest -Method GET -Path "sdkmessageprocessingsteps($($write.Id))?`$select=sdkmessageprocessingstepid,name,statecode,_eventhandler_value"
        if ([string]$step.sdkmessageprocessingstepid -ine [string]$write.Id -or
            $step.name -cne [string]$write.Body.name -or [int]$step.statecode -ne 0 -or
            [string]$step._eventhandler_value -ine [string]$guardType[0].plugintypeid) {
            throw 'Legacy guard-step topology differs from the retained approved registration.'
        }
        $liveSteps += $step
    }
    [pscustomobject]@{ Assembly = $assembly; AssemblyId = $assemblyId; Types = $typeRows; GuardType = $guardType[0]; Steps = $liveSteps }
}

function New-PackageJournal {
    param([object]$Artifact, [object]$Storage, [object]$Legacy, [object]$Api)
    $packageBody = [ordered]@{
        name = $script:PackageIdentity.Name
        uniquename = $script:PackageIdentity.UniqueName
        version = $script:PackageIdentity.Version
        content = [Convert]::ToBase64String([byte[]]$Artifact.Bytes)
    }
    $bodyHash = Get-Sha256 -Bytes ([Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $packageBody -Depth 5 -Compress)))
    [ordered]@{
        Authorization = 'phase3d-r4b-owner-authorized-plugin-package-cutover'
        PackageSha256 = $Artifact.Sha256
        ContainedDllSha256 = $Artifact.DllSha256
        PackageInventorySha256 = $Artifact.InventorySha256
        ContractSha256 = (Get-FileHash -LiteralPath $contractPath -Algorithm SHA256).Hash.ToLowerInvariant()
        CoreManifestSha256 = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
        StoragePlanSha256 = $Storage.PlanSha256
        LegacyAssemblySha256 = $expectedLegacyAssemblySha256
        LegacyAssemblyId = $Legacy.AssemblyId
        LegacyGuardTypeId = [string]$Legacy.GuardType.plugintypeid
        ApiId = [string]$Api.Api.customapiid
        LegacyHandlerTypeId = [string]$Api.HandlerId
        ApiNonHandlerSha256 = $Api.NonHandlerSha256
        PackageId = $null
        PackageAssemblyId = $null
        PackageHandlerTypeId = $null
        Writes = @([ordered]@{
            Method = 'POST'
            Path = 'pluginpackages'
            PayloadSha256 = $bodyHash
            State = 'PLANNED'
            HttpStatus = $null
        })
        AutomaticRetries = 0
        MaximumPackagePosts = 1
        MaximumHandlerPatches = 1
        RollbackAutomaticRetries = 0
    }
}

function Assert-IdentityAndSolution {
    Assert-TargetInput
    Assert-PacIdentity
    Get-ValidatedToken
    $script:ApiRoot = $OrganizationUrl.TrimEnd('/') + '/api/data/v9.2/'
    $who = Invoke-PackageRequest -Method GET -Path 'WhoAmI'
    if ([string]$who.OrganizationId -ine $ExpectedOrganizationId -or
        [string]$who.UserId -ine $script:ExpectedUserId -or
        [Environment]::GetEnvironmentVariable('BSO_RS_EXPECTED_USER_ID', 'Process') -cne $script:ExpectedUserId) {
        throw 'Dataverse WhoAmI does not match the pinned PAC identity and target.'
    }
    $solutions = @(Get-PackageRows -Path "solutions?`$select=solutionid,uniquename,ismanaged,_publisherid_value&`$filter=uniquename eq 'os_sr_bso_rs_support'")
    $publishers = @(Get-PackageRows -Path "publishers?`$select=publisherid,uniquename,customizationprefix&`$filter=uniquename eq 'os_bso_rs_support'")
    if ($solutions.Count -ne 1 -or [bool]$solutions[0].ismanaged -or $publishers.Count -ne 1 -or
        $publishers[0].customizationprefix -cne 'os' -or
        [string]$solutions[0]._publisherid_value -ine [string]$publishers[0].publisherid) {
        throw 'Approved Solution/Publisher target differs or is ambiguous.'
    }
    $script:Solution = $solutions[0]
}

function Invoke-StrictLegacyGate {
    param([object]$Storage)
    $legacy = Get-LegacyRegistrationReconciliation
    $liveLegacy = Get-LegacyHandlers -Plan $legacy.Plan
    $api = Get-ApiSnapshot
    if ([string]$api.HandlerId -ine [string](@($liveLegacy.Types | Where-Object typename -CEQ $script:PackageIdentity.Handler)[0].plugintypeid)) {
        throw 'Candidate Core Custom API no longer points to the retained legacy handler.'
    }
    [pscustomobject]@{ Legacy = $liveLegacy; API = $api; StrictResult = $legacy.Result; Storage = $Storage }
}

function Get-CutoverSnapshot {
    param([string]$ExpectedHandlerId, [string]$ExpectedPackageSha256 = $expectedPackageSha256, [int]$MaximumReadChecks = 1)
    $packages = @(Get-PackageRowsByName)
    $package = Assert-PackageReadback -Rows $packages -ExpectedPackageSha256 $ExpectedPackageSha256
    Assert-PackageSolutionMembership -PackageId ([string]$package.pluginpackageid)
    $derived = Get-PackageAssemblyAndTypes -PackageId ([string]$package.pluginpackageid) -MaximumReadChecks $MaximumReadChecks
    $handler = @($derived.Types | Where-Object typename -CEQ $script:PackageIdentity.Handler)
    if ($handler.Count -ne 1 -or [string]$handler[0].plugintypeid -ine $ExpectedHandlerId) {
        throw 'Package-backed API handler type differs from the retained cutover mapping.'
    }
    $api = Get-ApiSnapshot
    if ([string]$api.HandlerId -ine $ExpectedHandlerId) { throw 'Custom API handler is not package-backed.' }
    [pscustomobject]@{ Package = $package; Derived = $derived; Api = $api }
}

function New-HandlerPatchEntry {
    param([string]$ApiId, [string]$TypeId, [string]$NavigationProperty)
    $body = [ordered]@{ "$NavigationProperty@odata.bind" = "/plugintypes($TypeId)" }
    [ordered]@{
        Method = 'PATCH'
        Path = "customapis($ApiId)"
        PayloadSha256 = Get-Sha256 -Bytes ([Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $body -Depth 5 -Compress)))
        State = 'PLANNED'
        HttpStatus = $null
    }
}

function Get-ExistingPackageCutoverState {
    param([string]$ExpectedHandlerTypeId)
    $packages = @(Get-PackageRowsByName)
    if ($packages.Count -ne 1) { throw 'Existing package identity is missing or duplicated; never create or replace it.' }
    $package = $packages[0]
    if ($package.name -cne $script:PackageIdentity.Name -or
        $package.uniquename -cne $script:PackageIdentity.UniqueName -or
        [string]$package.version -cne $script:PackageIdentity.Version) {
        throw 'Existing PluginPackage identity differs from the approved artifact identity.'
    }
    $packageDetail = Invoke-PackageRequest -Method GET -Path "pluginpackages($($package.pluginpackageid))?`$select=pluginpackageid,name,uniquename,version"
    if ([string]$packageDetail.pluginpackageid -ine [string]$package.pluginpackageid -or
        $packageDetail.name -cne $script:PackageIdentity.Name -or
        $packageDetail.uniquename -cne $script:PackageIdentity.UniqueName -or
        [string]$packageDetail.version -cne $script:PackageIdentity.Version) {
        throw 'Direct PluginPackage read did not reconcile to the existing package identity.'
    }
    Assert-PackageSolutionMembership -PackageId ([string]$package.pluginpackageid)
    $derived = Get-PackageAssemblyAndTypes -PackageId ([string]$package.pluginpackageid)
    if (@($derived.SourceTypeLabels | Where-Object { $_ -match '(?i)^file\s*store$' }).Count -ne 1) {
        throw 'Package-backed assembly SourceType is not the reconciled File Store value.'
    }
    $legacyPlan = Get-Content -LiteralPath $LegacyDeploymentPlanPath -Raw | ConvertFrom-Json
    $legacyAssemblyPlan = @($legacyPlan.Writes | Where-Object Path -CEQ 'pluginassemblies')
    if ($legacyAssemblyPlan.Count -ne 1 -or [int]$legacyAssemblyPlan[0].ComponentType -ne 91) {
        throw 'Retained legacy plan does not pin the Dataverse Plug-in Assembly Solution component type.'
    }
    Assert-SolutionComponentMembership -EntityLogicalName 'pluginassembly' `
        -ComponentId ([string]$derived.Assembly.pluginassemblyid) `
        -ExpectedComponentType ([int]$legacyAssemblyPlan[0].ComponentType)
    $expectedTypeNames = @($script:PackageIdentity.Handler, $script:PackageIdentity.Guard) | Sort-Object
    $packageTypeNames = @($derived.Types | ForEach-Object { [string]$_.typename } | Sort-Object)
    if ($derived.Types.Count -ne 2 -or
        [string]::Join('|', $packageTypeNames) -cne [string]::Join('|', $expectedTypeNames) -or
        @($derived.Types | Where-Object { [string]$_._pluginassemblyid_value -ine [string]$derived.Assembly.pluginassemblyid }).Count -ne 0) {
        throw 'Package-backed PlugInType inventory or assembly membership differs from the approved types.'
    }
    $legacy = Get-LegacyHandlers -Plan $legacyPlan
    Assert-SolutionComponentMembership -EntityLogicalName 'pluginassembly' -ComponentId $legacy.AssemblyId `
        -ExpectedComponentType ([int]$legacyAssemblyPlan[0].ComponentType)
    $api = Get-ApiSnapshot
    Assert-SolutionComponentMembership -EntityLogicalName 'customapi' -ComponentId ([string]$api.Api.customapiid)
    $legacyHandler = @($legacy.Types | Where-Object typename -CEQ $script:PackageIdentity.Handler)
    $packageHandler = @($derived.Types | Where-Object typename -CEQ $script:PackageIdentity.Handler)
    if ($legacyHandler.Count -ne 1 -or $packageHandler.Count -ne 1) {
        throw 'Handler typename mapping is missing or ambiguous across legacy and package assemblies.'
    }
    $handlerNavigation = Assert-PackageProcessingMetadata
    $knownHandlerTypeIds = @([string]$legacyHandler[0].plugintypeid, [string]$packageHandler[0].plugintypeid)
    if ($ExpectedHandlerTypeId) {
        if ([string]$ExpectedHandlerTypeId -notin $knownHandlerTypeIds -or
            [string]$api.HandlerId -ine $ExpectedHandlerTypeId) {
            throw 'Custom API handler differs from the expected retained legacy/package mapping.'
        }
    } elseif ([string]$api.HandlerId -ine [string]$legacyHandler[0].plugintypeid) {
        throw 'Custom API no longer points to the exact retained legacy handler.'
    }
    [pscustomobject]@{
        Package = $package
        Assembly = $derived.Assembly
        AssemblySourceTypeLabels = $derived.SourceTypeLabels
        PackageTypes = $derived.Types
        PackageHandler = $packageHandler[0]
        PackageGuard = @($derived.Types | Where-Object typename -CEQ $script:PackageIdentity.Guard)[0]
        Legacy = $legacy
        LegacyHandler = $legacyHandler[0]
        API = $api
        HandlerNavigation = $handlerNavigation.HandlerNavigationProperty
        PackageTypeSolutionMembership = 'INCLUDED_WITH_PLUGIN_ASSEMBLY_COMPONENT'
    }
}

function New-ExistingCutoverJournal {
    param([object]$State)
    $entry = New-HandlerPatchEntry -ApiId ([string]$State.API.Api.customapiid) `
        -TypeId ([string]$State.PackageHandler.plugintypeid) `
        -NavigationProperty ([string]$State.HandlerNavigation)
    [ordered]@{
        Authorization = 'phase3d-r4f-owner-authorized-existing-package-handler-cutover'
        Result = 'PLUGIN_PACKAGE_PROCESSED_CUTOVER_PENDING'
        PackageId = [string]$State.Package.pluginpackageid
        PackageUniqueName = [string]$State.Package.uniquename
        PackageAssemblyId = [string]$State.Assembly.pluginassemblyid
        PackageAssemblyName = [string]$State.Assembly.name
        PackageAssemblySourceType = [string]::Join('|', [string[]]$State.AssemblySourceTypeLabels)
        PackageHandlerTypeId = [string]$State.PackageHandler.plugintypeid
        PackageGuardTypeId = [string]$State.PackageGuard.plugintypeid
        LegacyAssemblyId = [string]$State.Legacy.AssemblyId
        LegacyAssemblySha256 = $expectedLegacyAssemblySha256
        LegacyHandlerTypeId = [string]$State.LegacyHandler.plugintypeid
        LegacyHandlerTypeName = [string]$State.LegacyHandler.typename
        LegacyGuardTypeId = [string]$State.Legacy.GuardType.plugintypeid
        LegacyGuardStepCount = [int]$State.Legacy.Steps.Count
        ApiId = [string]$State.API.Api.customapiid
        ApiUniqueName = [string]$State.API.Api.uniquename
        ApiNonHandlerSha256 = [string]$State.API.NonHandlerSha256
        HandlerNavigation = [string]$State.HandlerNavigation
        CutoverMappings = @([ordered]@{
            UniqueName = [string]$State.API.Api.uniquename
            LegacyPluginTypeId = [string]$State.LegacyHandler.plugintypeid
            LegacyTypeName = [string]$State.LegacyHandler.typename
            PackagePluginTypeId = [string]$State.PackageHandler.plugintypeid
            PackageTypeName = [string]$State.PackageHandler.typename
        })
        Writes = @($entry)
        RollbackWrites = @()
        MaximumHandlerPatches = 1
        MaximumRollbackPatches = 1
        AutomaticRetries = 0
    }
}

try {
    if ($Mode -ceq 'InspectPackage') {
        Assert-IdentityAndSolution
        $packages = @(Get-PackageRowsByName)
        if ($packages.Count -ne 1) {
            [ordered]@{
                Result = 'PLUGIN_PACKAGE_POST_INSPECTION_INCOMPLETE'
                PackageMatches = $packages.Count
                GET = [int]$script:RequestCounts.GET
                POST = 0; PATCH = 0; AutomaticRetries = 0
            } | ConvertTo-Json -Depth 10
            return
        }
        $package = $packages[0]
        $packageDetail = Invoke-PackageRequest -Method GET -Path "pluginpackages($($package.pluginpackageid))?`$select=pluginpackageid,name,uniquename,version,modifiedon,content"
        $contentHash = if ([string]::IsNullOrWhiteSpace([string]$package.content)) {
            $null
        } else {
            Get-Sha256 -Bytes ([Convert]::FromBase64String([string]$package.content))
        }
        $detailContentHash = if ([string]::IsNullOrWhiteSpace([string]$packageDetail.content)) {
            $null
        } else {
            Get-Sha256 -Bytes ([Convert]::FromBase64String([string]$packageDetail.content))
        }
        $packageMetadata = Invoke-PackageRequest -Method GET -Path "EntityDefinitions(LogicalName='pluginpackage')?`$select=EntitySetName,PrimaryIdAttribute,ObjectTypeCode"
        $contentAttributes = @(Get-PackageRows -Path "EntityDefinitions(LogicalName='pluginpackage')/Attributes?`$select=LogicalName,AttributeType,IsValidForRead,IsValidForCreate,IsValidForUpdate" |
            Where-Object LogicalName -CEQ 'content')
        $solutionComponents = @(Get-PackageRows -Path "solutioncomponents?`$select=objectid,componenttype&`$filter=_solutionid_value eq $($script:Solution.solutionid) and objectid eq $($package.pluginpackageid)")
        $assemblyRelationships = @(Get-PackageRows -Path "EntityDefinitions(LogicalName='pluginassembly')/ManyToOneRelationships?`$select=ReferencingAttribute,ReferencedEntity,ReferencingEntityNavigationPropertyName" |
            Where-Object ReferencedEntity -CEQ 'pluginpackage')
        $assemblies = @()
        $types = @()
        $sourceTypeLabels = @()
        if ($assemblyRelationships.Count -eq 1 -and $assemblyRelationships[0].ReferencingAttribute) {
            $packageLookup = "_$($assemblyRelationships[0].ReferencingAttribute)_value"
            $assemblies = @(Get-PackageRows -Path "pluginassemblies?`$select=pluginassemblyid,name,version,modifiedon,sourcetype,$packageLookup&`$filter=$packageLookup eq $($package.pluginpackageid)")
            if ($assemblies.Count -eq 1) {
                $types = @(Get-PackageRows -Path "plugintypes?`$select=plugintypeid,typename,_pluginassemblyid_value&`$filter=_pluginassemblyid_value eq $($assemblies[0].pluginassemblyid)")
                $sourceMetadata = Invoke-PackageRequest -Method GET -Path "EntityDefinitions(LogicalName='pluginassembly')/Attributes(LogicalName='sourcetype')/Microsoft.Dynamics.CRM.PicklistAttributeMetadata?`$select=LogicalName&`$expand=OptionSet"
                $sourceOptions = @($sourceMetadata.OptionSet.Options | Where-Object { [int]$_.Value -eq [int]$assemblies[0].sourcetype })
                $sourceTypeLabels = @($sourceOptions | ForEach-Object {
                    @($_.Label.LocalizedLabels | ForEach-Object Label) + [string]$_.Label.UserLocalizedLabel.Label
                } | Where-Object { $_ } | Sort-Object -Unique)
            }
        }
        $legacyPlan = Get-Content -LiteralPath $LegacyDeploymentPlanPath -Raw | ConvertFrom-Json
        $legacy = Get-LegacyHandlers -Plan $legacyPlan
        $api = Get-ApiSnapshot
        $legacyHandler = @($legacy.Types | Where-Object typename -CEQ $script:PackageIdentity.Handler)
        $packageHandler = @($types | Where-Object typename -CEQ $script:PackageIdentity.Handler)
        $packageGuard = @($types | Where-Object typename -CEQ $script:PackageIdentity.Guard)
        [ordered]@{
            Result = 'PLUGIN_PACKAGE_POST_INSPECTION_COMPLETE'
            PackageMatches = $packages.Count
            PackageId = [string]$package.pluginpackageid
            PackageModifiedOn = [string]$package.modifiedon
            NameMatches = $package.name -ceq $script:PackageIdentity.Name
            UniqueNameMatches = $package.uniquename -ceq $script:PackageIdentity.UniqueName
            Version = [string]$package.version
            ExpectedVersionMatches = [string]$package.version -ceq $script:PackageIdentity.Version
            ContentPresent = -not [string]::IsNullOrWhiteSpace([string]$package.content)
            ContentSha256 = $contentHash
            ExpectedContentSha256Matches = $contentHash -ceq $expectedPackageSha256
            DirectReadContentPresent = -not [string]::IsNullOrWhiteSpace([string]$packageDetail.content)
            DirectReadContentSha256 = $detailContentHash
            DirectReadContentSha256Matches = $detailContentHash -ceq $expectedPackageSha256
            DirectReadMetadataMatches = ([string]$packageDetail.pluginpackageid -ieq [string]$package.pluginpackageid -and
                $packageDetail.name -ceq $script:PackageIdentity.Name -and
                $packageDetail.uniquename -ceq $script:PackageIdentity.UniqueName -and
                [string]$packageDetail.version -ceq $script:PackageIdentity.Version)
            DirectReadModifiedOn = [string]$packageDetail.modifiedon
            SolutionMembershipMatches = ($solutionComponents.Count -eq 1 -and
                [string]$solutionComponents[0].objectid -ieq [string]$package.pluginpackageid -and
                [int]$solutionComponents[0].componenttype -eq [int]$packageMetadata.ObjectTypeCode)
            PackageEntitySetMatches = $packageMetadata.EntitySetName -ceq 'pluginpackages'
            PackagePrimaryIdMatches = $packageMetadata.PrimaryIdAttribute -ceq 'pluginpackageid'
            ContentAttributeMetadata = @($contentAttributes | ForEach-Object {
                [ordered]@{
                    AttributeType = [string]$_.AttributeType
                    IsValidForRead = [bool]$_.IsValidForRead
                    IsValidForCreate = [bool]$_.IsValidForCreate
                    IsValidForUpdate = [bool]$_.IsValidForUpdate
                }
            })
            PackageAssemblyRelationshipCount = $assemblyRelationships.Count
            PackageAssemblyCount = $assemblies.Count
            PackageAssemblyId = [string]$assemblies[0].pluginassemblyid
            PackageAssemblyModifiedOn = [string]$assemblies[0].modifiedon
            PackageAssemblyNames = @($assemblies | ForEach-Object { [string]$_.name })
            PackageAssemblyVersions = @($assemblies | ForEach-Object { [string]$_.version })
            PackageAssemblySourceTypeLabels = $sourceTypeLabels
            PackagePluginTypes = @($types | ForEach-Object { [string]$_.typename } | Sort-Object)
            PackageHandlerTypeId = [string]$packageHandler[0].plugintypeid
            PackageHandlerTypeName = [string]$packageHandler[0].typename
            PackageGuardTypeId = [string]$packageGuard[0].plugintypeid
            PackageGuardTypeName = [string]$packageGuard[0].typename
            ApiId = [string]$api.Api.customapiid
            ApiUniqueName = [string]$api.Api.uniquename
            ApiHandlerTypeId = [string]$api.HandlerId
            ApiHandlerMatchesPackage = ($packageHandler.Count -eq 1 -and
                [string]$api.HandlerId -ieq [string]$packageHandler[0].plugintypeid)
            LegacyAssemblyId = [string]$legacy.AssemblyId
            LegacyHandlerTypeId = [string]$legacyHandler[0].plugintypeid
            LegacyHandlerTypeName = [string]$legacyHandler[0].typename
            LegacyGuardTypeId = [string]$legacy.GuardType.plugintypeid
            LegacyAssemblyHashMatches = $true
            LegacyGuardStepCount = $legacy.Steps.Count
            ApiContractMatches = $true
            ApiHandlerMatchesLegacy = ($legacyHandler.Count -eq 1 -and
                [string]$api.HandlerId -ieq [string]$legacyHandler[0].plugintypeid)
            GET = [int]$script:RequestCounts.GET
            POST = 0; PATCH = 0; AutomaticRetries = 0
        } | ConvertTo-Json -Depth 10
        return
    }
    if ($Mode -in @('CutoverExistingPreflight', 'CutoverExistingApply', 'RollbackExistingCutover')) {
        Assert-IdentityAndSolution
        $storage = Get-StorageReconciliation
        $script:NestedGETCounts.Storage = [int]$storage.Requests.GET
        if ($storage.Result -cne 'OPERATION_RECEIPT_STORAGE_RECONCILED' -or
            $storage.CandidateCore -cne 'EXACT' -or
            $storage.Requests.POST -ne 0 -or $storage.Requests.PUT -ne 0) {
            throw 'Candidate Core storage or active Operation Receipt key failed exact reconciliation.'
        }

        if ($Mode -ceq 'RollbackExistingCutover') {
            if (-not $EvidencePath -or -not (Test-Path -LiteralPath $EvidencePath -PathType Leaf)) {
                throw 'Package rollback requires the retained cutover journal.'
            }
            if (-not $RuntimeEvidencePath -or -not (Test-Path -LiteralPath $RuntimeEvidencePath -PathType Leaf)) {
                throw 'Package rollback requires the retained runtime failure evidence.'
            }
            $runtimeEvidence = Get-Content -LiteralPath $RuntimeEvidencePath -Raw | ConvertFrom-Json
            $allowedRuntimeDefects = @(
                'CREATECANDIDATE_RUNTIME_FAILURE', 'RUNTIME_RECORDCALL_FAILURE',
                'RUNTIME_UPDATECANDIDATE_FAILURE', 'IDEMPOTENCY_FAILURE', 'SCHEDULING_GUARD_FAILURE'
            )
            $expectedCutoverAuthorization = switch ([string]$runtimeEvidence.AuthorizationId) {
                'phase3d-r4d-owner-authorized-package-runtime' { 'phase3d-r4d-owner-authorized-existing-package-handler-cutover' }
                'phase3d-r4f-owner-authorized-package-runtime' { 'phase3d-r4f-owner-authorized-existing-package-handler-cutover' }
                default { $null }
            }
            if (-not $expectedCutoverAuthorization -or
                $runtimeEvidence.ManifestSha256 -cne '63f56173f61265f539d23d6ceffb5631e23f438e4e254755c1e24c7d17eb1915' -or
                $runtimeEvidence.ApiUniqueName -cne 'os_sr_cact' -or
                $runtimeEvidence.ExpectedHandlerPackageUniqueName -cne $script:PackageIdentity.UniqueName -or
                $runtimeEvidence.MaximumApiDispatches -ne 8 -or $runtimeEvidence.AutomaticRetries -ne 0 -or
                $runtimeEvidence.Result -notin $allowedRuntimeDefects -or
                $runtimeEvidence.RuntimeFailureClassification -cne $runtimeEvidence.Result -or
                @($runtimeEvidence.Dispatches | Where-Object State -CEQ 'UNCERTAIN_WRITE_OUTCOME').Count -ne 0 -or
                @($runtimeEvidence.Dispatches).Count -eq 0 -or @($runtimeEvidence.Dispatches).Count -gt 8 -or
                @($runtimeEvidence.Dispatches | Where-Object {
                    $_.State -notin @('GET_RECONCILED', 'ACKNOWLEDGED', 'GET_RECONCILE_PENDING', 'REJECTED')
                }).Count -ne 0) {
                throw 'Package rollback is permitted only for matching classified runtime and cutover evidence.'
            }
            $script:Journal = Get-Content -LiteralPath $EvidencePath -Raw | ConvertFrom-Json
            if ($script:Journal.Authorization -cne $expectedCutoverAuthorization -or
                $script:Journal.Result -cne 'PLUGIN_PACKAGE_CUTOVER_RECONCILED_RUNTIME_PENDING' -or
                $script:Journal.AutomaticRetries -ne 0 -or
                $script:Journal.MaximumRollbackPatches -ne 1 -or
                $script:Journal.RollbackWrites.Count -ne 0 -or
                $script:Journal.Writes.Count -ne 1 -or
                $script:Journal.Writes[0].Method -cne 'PATCH' -or
                $script:Journal.Writes[0].Path -cne "customapis($($script:Journal.ApiId))" -or
                $script:Journal.Writes[0].State -cne 'GET_RECONCILED' -or
                $script:Journal.CutoverMappings.Count -ne 1 -or
                $script:Journal.CutoverMappings[0].UniqueName -cne $script:Contract.uniqueName -or
                $script:Journal.CutoverMappings[0].LegacyPluginTypeId -cne $script:Journal.LegacyHandlerTypeId -or
                $script:Journal.CutoverMappings[0].PackagePluginTypeId -cne $script:Journal.PackageHandlerTypeId) {
                throw 'Package rollback journal is inconsistent, consumed, or outside its one-patch limit.'
            }
            $state = Get-ExistingPackageCutoverState -ExpectedHandlerTypeId ([string]$script:Journal.PackageHandlerTypeId)
            if ([string]$state.Package.pluginpackageid -ine [string]$script:Journal.PackageId -or
                [string]$state.Assembly.pluginassemblyid -ine [string]$script:Journal.PackageAssemblyId -or
                [string]$state.Legacy.AssemblyId -ine [string]$script:Journal.LegacyAssemblyId -or
                [string]$state.API.Api.customapiid -ine [string]$script:Journal.ApiId -or
                [string]$state.API.NonHandlerSha256 -cne [string]$script:Journal.ApiNonHandlerSha256 -or
                [string]$state.LegacyHandler.plugintypeid -ine [string]$script:Journal.LegacyHandlerTypeId) {
                throw 'Current package/legacy/API state differs from the retained rollback mapping.'
            }
            $rollbackEntry = New-HandlerPatchEntry -ApiId ([string]$script:Journal.ApiId) `
                -TypeId ([string]$script:Journal.LegacyHandlerTypeId) `
                -NavigationProperty ([string]$script:Journal.HandlerNavigation)
            $script:Journal.Writes += $rollbackEntry
            $script:Journal.RollbackWrites += $rollbackEntry
            $script:Journal.Result = 'PACKAGE_RUNTIME_DEFECT_ROLLBACK_PENDING'
            Save-PackageJournal
            $script:WriteIndex = 1
            $rollbackBody = [ordered]@{
                "$($script:Journal.HandlerNavigation)@odata.bind" = "/plugintypes($($script:Journal.LegacyHandlerTypeId))"
            }
            $rollbackError = $null
            try { $null = Invoke-PackageRequest -Method PATCH -Path ([string]$rollbackEntry.Path) -Body $rollbackBody }
            catch { $rollbackError = $_.Exception.Message }
            $rollbackReadback = $null
            $rollbackReadbackError = $null
            try {
                $rollbackReadback = Invoke-PackageRequest -Method GET -Path "customapis($($script:Journal.ApiId))?`$select=customapiid,uniquename,_plugintypeid_value"
            } catch { $rollbackReadbackError = $_.Exception.Message }
            if ($rollbackReadbackError) {
                $script:Journal.Writes[1].State = 'UNCERTAIN_WRITE_OUTCOME'
                $script:Journal.Result = 'UNCERTAIN_WRITE_OUTCOME'
                Save-PackageJournal
                throw 'R4D rollback readback failed after dispatch; stop without retry.'
            }
            if ([string]$rollbackReadback.customapiid -ine [string]$script:Journal.ApiId -or
                [string]$rollbackReadback._plugintypeid_value -ine [string]$script:Journal.LegacyHandlerTypeId) {
                $script:Journal.Writes[1].State = if ($rollbackError) { 'UNCERTAIN_WRITE_OUTCOME' } else { 'REJECTED_UNRECONCILED' }
                $script:Journal.Result = if ($rollbackError) { 'UNCERTAIN_WRITE_OUTCOME' } else { 'PLUGIN_PACKAGE_HANDLER_CUTOVER_FAILED' }
                Save-PackageJournal
                throw 'R4D handler rollback did not reconcile; no retry.'
            }
            if ($rollbackError) {
                $script:Journal.Writes[1].State = 'GET_RECONCILED_AFTER_UNCERTAIN_RESPONSE'
                $script:Journal.Result = 'UNCERTAIN_WRITE_OUTCOME'
                Save-PackageJournal
                throw 'R4D rollback response was uncertain despite matching readback; stop without retry.'
            }
            $script:Journal.Writes[1].State = 'GET_RECONCILED'
            $script:Journal.Result = 'PLUGIN_PACKAGE_CUTOVER_ROLLED_BACK'
            Save-PackageJournal
            $finalRollback = $null
            try {
                $finalRollback = Get-ExistingPackageCutoverState -ExpectedHandlerTypeId ([string]$script:Journal.LegacyHandlerTypeId)
                if ([string]$finalRollback.Package.pluginpackageid -ine [string]$script:Journal.PackageId -or
                    [string]$finalRollback.Assembly.pluginassemblyid -ine [string]$script:Journal.PackageAssemblyId -or
                    [string]$finalRollback.API.NonHandlerSha256 -cne [string]$script:Journal.ApiNonHandlerSha256 -or
                    [string]$finalRollback.Legacy.AssemblyId -ine [string]$script:Journal.LegacyAssemblyId -or
                    [string]$finalRollback.LegacyHandler.plugintypeid -ine [string]$script:Journal.LegacyHandlerTypeId -or
                    [int]$finalRollback.Legacy.Steps.Count -ne [int]$script:Journal.LegacyGuardStepCount) {
                    throw 'API contract or package/legacy topology changed during rollback reconciliation.'
                }
            } catch {
                $script:Journal.Result = 'UNCERTAIN_WRITE_OUTCOME'
                Save-PackageJournal
                throw 'R4D rollback handler matched immediately, but full reconciliation failed; stop without retry.'
            }
            $script:Journal.Result = 'PLUGIN_PACKAGE_CUTOVER_ROLLED_BACK'
            Save-PackageJournal
            [ordered]@{
                Result = 'PLUGIN_PACKAGE_CUTOVER_ROLLED_BACK'
                PackageId = [string]$finalRollback.Package.pluginpackageid
                PackageAssemblyId = [string]$finalRollback.Assembly.pluginassemblyid
                LegacyAssemblyRetained = $true
                PackageRetained = $true
                GET = [int]$script:RequestCounts.GET + [int]$storage.Requests.GET
                PackagePosts = 0; HandlerPatches = 0; RollbackPatches = [int]$script:RequestCounts.PATCH
                BusinessApiInvocations = 0; BusinessDataWrites = 0; AutomaticRetries = 0
                EvidencePath = $EvidencePath
            } | ConvertTo-Json -Depth 10
            return
        }

        $state = Get-ExistingPackageCutoverState
        if ($Mode -ceq 'CutoverExistingPreflight') {
            $zeroRows = Get-RuntimeZeroRowGate
            [ordered]@{
                Result = 'PLUGIN_PACKAGE_PROCESSED_CUTOVER_PREFLIGHT_READY'
                PackageId = [string]$state.Package.pluginpackageid
                PackageUniqueName = [string]$state.Package.uniquename
                PackageVersion = [string]$state.Package.version
                PackageContentHashVerified = $false
                PackageAssemblyId = [string]$state.Assembly.pluginassemblyid
                PackageAssemblyName = [string]$state.Assembly.name
                PackageAssemblySourceTypeLabels = $state.AssemblySourceTypeLabels
                PackageHandlerTypeId = [string]$state.PackageHandler.plugintypeid
                PackageHandlerTypeName = [string]$state.PackageHandler.typename
                PackageGuardTypeId = [string]$state.PackageGuard.plugintypeid
                PackageGuardTypeName = [string]$state.PackageGuard.typename
                PackageTypesSolutionMembership = $state.PackageTypeSolutionMembership
                LegacyAssemblyId = [string]$state.Legacy.AssemblyId
                LegacyAssemblyHashMatches = $true
                LegacyHandlerTypeId = [string]$state.LegacyHandler.plugintypeid
                LegacyHandlerTypeName = [string]$state.LegacyHandler.typename
                LegacyGuardTypeId = [string]$state.Legacy.GuardType.plugintypeid
                LegacyGuardStepCount = [int]$state.Legacy.Steps.Count
                ApiId = [string]$state.API.Api.customapiid
                ApiUniqueName = [string]$state.API.Api.uniquename
                ApiLegacyHandlerTypeId = [string]$state.API.HandlerId
                ApiNonHandlerSha256 = [string]$state.API.NonHandlerSha256
                ApiRequestParameters = $state.API.RequestParameters
                HandlerNavigation = [string]$state.HandlerNavigation
                Storage = $storage.Result
                FreshZeroRowCounts = $zeroRows.FreshZeroRowCounts
                PackagePosts = 0; HandlerPatches = 0; RollbackPatches = 0
                BusinessApiInvocations = 0; BusinessDataWrites = 0; AutomaticRetries = 0
                GET = [int]$script:RequestCounts.GET + [int]$storage.Requests.GET + [int]$script:RuntimePreflightGET
                EvidencePath = $null
            } | ConvertTo-Json -Depth 15
            return
        }

        if (-not $EvidencePath -or (Test-Path -LiteralPath $EvidencePath)) {
            throw 'R4D apply requires a new, absent one-shot rollback evidence path.'
        }
        $zeroRows = Get-RuntimeZeroRowGate
        $script:Journal = New-ExistingCutoverJournal -State $state
        $stream = [IO.File]::Open($EvidencePath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $stream.Dispose()
        Save-PackageJournal
        $patchBody = [ordered]@{
            "$($script:Journal.HandlerNavigation)@odata.bind" = "/plugintypes($($script:Journal.PackageHandlerTypeId))"
        }
        $patchError = $null
        $script:WriteIndex = 0
        try {
            $null = Invoke-PackageRequest -Method PATCH -Path ([string]$script:Journal.Writes[0].Path) -Body $patchBody
        } catch { $patchError = $_.Exception.Message }
        $readback = $null
        $readbackError = $null
        try {
            $readback = Invoke-PackageRequest -Method GET -Path "customapis($($script:Journal.ApiId))?`$select=customapiid,uniquename,_plugintypeid_value"
        } catch { $readbackError = $_.Exception.Message }
        if ($readbackError) {
            $script:Journal.Writes[0].State = 'UNCERTAIN_WRITE_OUTCOME'
            $script:Journal.Result = 'UNCERTAIN_WRITE_OUTCOME'
            Save-PackageJournal
            throw 'R4D handler readback failed after dispatch; stop without retry.'
        }
        if ([string]$readback.customapiid -ine [string]$script:Journal.ApiId -or
            [string]$readback.uniquename -cne [string]$script:Journal.ApiUniqueName -or
            [string]$readback._plugintypeid_value -ine [string]$script:Journal.PackageHandlerTypeId) {
            $script:Journal.Writes[0].State = if ($patchError) { 'UNCERTAIN_WRITE_OUTCOME' } else { 'REJECTED_UNRECONCILED' }
            $script:Journal.Result = if ($patchError) { 'UNCERTAIN_WRITE_OUTCOME' } else { 'PLUGIN_PACKAGE_HANDLER_CUTOVER_FAILED' }
            Save-PackageJournal
            throw 'R4D handler cutover did not reconcile; no retry.'
        }
        if ($patchError) {
            $script:Journal.Writes[0].State = 'GET_RECONCILED_AFTER_UNCERTAIN_RESPONSE'
            $script:Journal.Result = 'UNCERTAIN_WRITE_OUTCOME'
            Save-PackageJournal
            throw 'R4D PATCH response was uncertain despite matching readback; stop without retry.'
        }
        $script:Journal.Writes[0].State = 'GET_RECONCILED'
        Save-PackageJournal
        $final = $null
        try {
            $final = Get-ExistingPackageCutoverState -ExpectedHandlerTypeId ([string]$script:Journal.PackageHandlerTypeId)
            if ([string]$final.Package.pluginpackageid -ine [string]$script:Journal.PackageId -or
                [string]$final.Assembly.pluginassemblyid -ine [string]$script:Journal.PackageAssemblyId -or
                [string]$final.API.NonHandlerSha256 -cne [string]$script:Journal.ApiNonHandlerSha256 -or
                [string]$final.Legacy.AssemblyId -ine [string]$script:Journal.LegacyAssemblyId -or
                [string]$final.LegacyHandler.plugintypeid -ine [string]$script:Journal.LegacyHandlerTypeId -or
                [int]$final.Legacy.Steps.Count -ne [int]$script:Journal.LegacyGuardStepCount) {
                throw 'Full package handler cutover differs from retained package/API/legacy evidence.'
            }
        } catch {
            $script:Journal.Result = 'PLUGIN_PACKAGE_HANDLER_CUTOVER_FAILED'
            Save-PackageJournal
            throw 'Full package handler cutover reconciliation failed after the single PATCH; no retry.'
        }
        $script:Journal.Result = 'PLUGIN_PACKAGE_CUTOVER_RECONCILED_RUNTIME_PENDING'
        Save-PackageJournal
        [ordered]@{
            Result = [string]$script:Journal.Result
            PackageId = [string]$final.Package.pluginpackageid
            PackageAssemblyId = [string]$final.Assembly.pluginassemblyid
            PackageHandlerTypeId = [string]$final.PackageHandler.plugintypeid
            PackageGuardTypeId = [string]$final.PackageGuard.plugintypeid
            LegacyAssemblyId = [string]$final.Legacy.AssemblyId
            LegacyHandlerTypeId = [string]$final.LegacyHandler.plugintypeid
            ApiUniqueName = [string]$final.API.Api.uniquename
            ApiId = [string]$final.API.Api.customapiid
            ApiHandlerTypeId = [string]$final.API.HandlerId
            CutoverMap = $script:Journal.CutoverMappings
            GET = [int]$script:RequestCounts.GET + [int]$storage.Requests.GET + [int]$script:RuntimePreflightGET
            PackagePosts = 0; HandlerPatches = [int]$script:RequestCounts.PATCH; RollbackPatches = 0
            BusinessApiInvocations = 0; BusinessDataWrites = 0; AutomaticRetries = 0
            EvidencePath = $EvidencePath
        } | ConvertTo-Json -Depth 15
        return
    }
    if ($Mode -in @('Preflight', 'Apply')) {
        $storage = Get-StorageReconciliation
        $script:NestedGETCounts.Storage = [int]$storage.Requests.GET
        Assert-IdentityAndSolution
        $artifact = Get-PackageArtifact
        $strict = Invoke-StrictLegacyGate -Storage $storage
        $script:NestedGETCounts.StrictLegacy = [int]$strict.StrictResult.GET
        $script:NestedGETCounts.StrictStorage = [int]$strict.StrictResult.StorageGateGET
        $packageMetadata = Invoke-PackageRequest -Method GET -Path "EntityDefinitions(LogicalName='pluginpackage')?`$select=EntitySetName,PrimaryIdAttribute,ObjectTypeCode"
        if ($packageMetadata.EntitySetName -cne 'pluginpackages' -or $packageMetadata.PrimaryIdAttribute -cne 'pluginpackageid' -or
            [int]$packageMetadata.ObjectTypeCode -le 0) { throw 'Supported Plug-in Package entity metadata is not exact.' }
        $processingMetadata = Assert-PackageProcessingMetadata
        $existingPackages = @(Get-PackageRowsByName)
        if ($Mode -ceq 'Preflight') {
            if ($existingPackages.Count -ne 0) { throw 'Exact package already exists; do not create or overwrite it.' }
            $zeroRows = Get-RuntimeZeroRowGate
            [ordered]@{
                Result = 'PLUGIN_PACKAGE_PREFLIGHT_READY'
                PackageSha256 = $artifact.Sha256
                ContainedDllSha256 = $artifact.DllSha256
                PackageInventorySha256 = $artifact.InventorySha256
                StrictLegacyGET = [int]$strict.StrictResult.GET
                StorageGET = [int]$storage.Requests.GET
                PackageLookupAttribute = $processingMetadata.PackageLookupAttribute
                PackageSourceTypeValues = $processingMetadata.PackageSourceTypeValues
                HandlerNavigationProperty = $processingMetadata.HandlerNavigationProperty
                StrictLegacyStorageGateGET = [int]$strict.StrictResult.StorageGateGET
                RuntimeZeroRowGET = [int]$zeroRows.RequestGET
                PackageMatches = 0
                GET = [int]$script:RequestCounts.GET + [int]$storage.Requests.GET +
                    [int]$strict.StrictResult.GET + [int]$strict.StrictResult.StorageGateGET +
                    [int]$zeroRows.RequestGET
                POST = 0; PATCH = 0; AutomaticRetries = 0
                ZeroBusinessDataWrites = $true
            } | ConvertTo-Json -Depth 10
            return
        }
        if ($existingPackages.Count -ne 0) { throw 'Exact package appeared after preflight; stop without POST.' }
        $zeroRows = Get-RuntimeZeroRowGate
        if (@(Get-PackageRowsByName).Count -ne 0) {
            throw 'Exact package appeared after the zero-row gate; stop without POST.'
        }
        if (-not $EvidencePath -or (Test-Path -LiteralPath $EvidencePath)) {
            throw 'Apply requires a new, absent one-shot evidence path.'
        }
        $strictPlan = Get-Content -LiteralPath $LegacyDeploymentPlanPath -Raw | ConvertFrom-Json
        $script:Journal = New-PackageJournal -Artifact $artifact -Storage $storage -Legacy $strict.Legacy -Api $strict.API
        $script:Journal.Writes[0].PayloadSha256 = Get-Sha256 -Bytes ([Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject ([ordered]@{
            name = $script:PackageIdentity.Name
            uniquename = $script:PackageIdentity.UniqueName
            version = $script:PackageIdentity.Version
            content = [Convert]::ToBase64String([byte[]]$artifact.Bytes)
        }) -Depth 5 -Compress)))
        $script:Journal.LegacyGuardStepCount = $strict.Legacy.Steps.Count
        $stream = [IO.File]::Open($EvidencePath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $stream.Dispose()
        Save-PackageJournal
        $packageBody = [ordered]@{
            name = $script:PackageIdentity.Name
            uniquename = $script:PackageIdentity.UniqueName
            version = $script:PackageIdentity.Version
            content = [Convert]::ToBase64String([byte[]]$artifact.Bytes)
        }
        $dispatchError = $null
        try { $null = Invoke-PackageRequest -Method POST -Path 'pluginpackages' -Body $packageBody }
        catch { $dispatchError = $_.Exception.Message }
        $packages = @(Get-PackageRowsByName)
        if ($packages.Count -ne 1) {
            $script:Journal.Writes[0].State = if ($dispatchError) { 'UNCERTAIN_WRITE_OUTCOME' } else { 'REJECTED_UNRECONCILED' }
            Save-PackageJournal
            throw 'UNCERTAIN_WRITE_OUTCOME: package POST was not proven by exact GET; never resend.'
        }
        $package = Assert-PackageReadback -Rows $packages
        $script:Journal.Writes[0].State = 'GET_RECONCILED'
        $script:Journal.PackageId = [string]$package.pluginpackageid
        $script:Journal.Result = 'PLUGIN_PACKAGE_CREATED_CUTOVER_PENDING'
        Save-PackageJournal
        try { Assert-PackageSolutionMembership -PackageId ([string]$package.pluginpackageid) }
        catch {
            $script:Journal.Result = 'PLUGIN_PACKAGE_CREATED_CUTOVER_PENDING'
            $script:Journal.SolutionMembership = 'NOT_RECONCILED'
            Save-PackageJournal
            throw 'Package exists but approved Solution membership did not reconcile; no fallback write.'
        }
        try {
            $derived = Get-PackageAssemblyAndTypes -PackageId ([string]$package.pluginpackageid) -MaximumReadChecks 5
        } catch {
            $script:Journal.Result = 'PLUGIN_PACKAGE_PROCESSING_FAILED'
            Save-PackageJournal
            throw
        }
        $newHandler = @($derived.Types | Where-Object typename -CEQ $script:PackageIdentity.Handler)
        if ($newHandler.Count -ne 1) { throw 'Package handler type is missing or duplicated.' }
        $script:Journal.PackageAssemblyId = [string]$derived.Assembly.pluginassemblyid
        $script:Journal.PackageHandlerTypeId = [string]$newHandler[0].plugintypeid
        $apiMeta = Invoke-PackageRequest -Method GET -Path "EntityDefinitions(LogicalName='customapi')/ManyToOneRelationships?`$select=ReferencingAttribute,ReferencedEntity,ReferencingEntityNavigationPropertyName"
        $handlerNavigation = @($apiMeta.value | Where-Object {
            $_.ReferencedEntity -ceq 'plugintype' -and $_.ReferencingAttribute -ceq 'plugintypeid'
        })
        if ($handlerNavigation.Count -ne 1 -or -not $handlerNavigation[0].ReferencingEntityNavigationPropertyName) {
            throw 'Custom API handler navigation metadata is missing or ambiguous.'
        }
        $script:Journal.Writes += (New-HandlerPatchEntry -ApiId ([string]$strict.API.Api.customapiid) `
            -TypeId ([string]$newHandler[0].plugintypeid) `
            -NavigationProperty ([string]$handlerNavigation[0].ReferencingEntityNavigationPropertyName))
        $script:Journal.HandlerNavigation = [string]$handlerNavigation[0].ReferencingEntityNavigationPropertyName
        $script:Journal.Result = 'PLUGIN_PACKAGE_CREATED_CUTOVER_PENDING'
        Save-PackageJournal
        $freshApi = Get-ApiSnapshot
        if ([string]$freshApi.Api.customapiid -ine [string]$strict.API.Api.customapiid -or
            [string]$freshApi.HandlerId -ine [string]$script:Journal.LegacyHandlerTypeId -or
            $freshApi.NonHandlerSha256 -cne $script:Journal.ApiNonHandlerSha256) {
            throw 'Custom API changed after preflight; no handler PATCH dispatched.'
        }
        $patchBody = [ordered]@{ "$($script:Journal.HandlerNavigation)@odata.bind" = "/plugintypes($($script:Journal.PackageHandlerTypeId))" }
        $patchError = $null
        try { $null = Invoke-PackageRequest -Method PATCH -Path "customapis($($script:Journal.ApiId))" -Body $patchBody }
        catch { $patchError = $_.Exception.Message }
        $readback = Invoke-PackageRequest -Method GET -Path "customapis($($script:Journal.ApiId))?`$select=customapiid,uniquename,_plugintypeid_value"
        if ([string]$readback.customapiid -ine [string]$script:Journal.ApiId -or
            [string]$readback._plugintypeid_value -ine [string]$script:Journal.PackageHandlerTypeId) {
            $script:Journal.Writes[1].State = if ($patchError) { 'UNCERTAIN_WRITE_OUTCOME' } else { 'REJECTED_UNRECONCILED' }
            $script:Journal.Result = 'PLUGIN_PACKAGE_HANDLER_CUTOVER_FAILED'
            Save-PackageJournal
            throw 'PLUGIN_PACKAGE_HANDLER_CUTOVER_FAILED: handler PATCH did not reconcile; no retry.'
        }
        $script:Journal.Writes[1].State = 'GET_RECONCILED'
        Save-PackageJournal
        $final = Get-CutoverSnapshot -ExpectedHandlerId ([string]$script:Journal.PackageHandlerTypeId) -MaximumReadChecks 5
        if ($final.Api.NonHandlerSha256 -cne $script:Journal.ApiNonHandlerSha256) {
            throw 'Custom API properties other than PluginTypeId changed during cutover.'
        }
        $legacyAfter = Get-LegacyHandlers -Plan $strictPlan
        if ((Get-Sha256 -Bytes ([Convert]::FromBase64String([string]$legacyAfter.Assembly.content))) -cne $expectedLegacyAssemblySha256 -or
            $legacyAfter.Steps.Count -ne $script:Journal.LegacyGuardStepCount -or
            [string]$legacyAfter.GuardType.plugintypeid -ine [string]$script:Journal.LegacyGuardTypeId) {
            throw 'Legacy assembly or direct-write guard topology changed during package cutover.'
        }
        $script:Journal.Result = 'PLUGIN_PACKAGE_CUTOVER_RECONCILED_RUNTIME_PENDING'
        Save-PackageJournal
        [ordered]@{
            Result = 'PLUGIN_PACKAGE_CUTOVER_RECONCILED_RUNTIME_PENDING'
            PackageSha256 = $artifact.Sha256
            ContainedDllSha256 = $artifact.DllSha256
            PackageInventorySha256 = $artifact.InventorySha256
            PackagePosts = $script:RequestCounts.POST
            PackageGeneratedAssemblies = 1
            PackageGeneratedPluginTypes = $derived.Types.Count
            CustomApiHandlerPatches = $script:RequestCounts.PATCH
            RollbackHandlerPatches = 0
            GET = [int]$script:RequestCounts.GET + [int]$storage.Requests.GET +
                [int]$strict.StrictResult.GET + [int]$strict.StrictResult.StorageGateGET +
                [int]$zeroRows.RequestGET
            PackageGET = [int]$script:RequestCounts.GET
            StorageGET = [int]$storage.Requests.GET
            StrictLegacyGET = [int]$strict.StrictResult.GET
            StrictLegacyStorageGateGET = [int]$strict.StrictResult.StorageGateGET
            RuntimeZeroRowGET = [int]$zeroRows.RequestGET
            BusinessApiCalls = 0; BusinessRowWrites = 0; SchemaWrites = 0; AppWrites = 0; PublishXml = 0
            AutomaticRetries = 0
            HandlerMapping = 'PACKAGE_BACKED'
            LegacyAssemblyRetained = $true
            EvidencePath = $EvidencePath
        } | ConvertTo-Json -Depth 15
        return
    }

    Assert-IdentityAndSolution
    $storage = Get-StorageReconciliation
    if ($Mode -ceq 'Reconcile') {
        if (-not $EvidencePath -or -not (Test-Path -LiteralPath $EvidencePath)) {
            throw 'Reconcile requires the retained package cutover evidence.'
        }
        $script:Journal = Get-Content -LiteralPath $EvidencePath -Raw | ConvertFrom-Json
        if ($script:Journal.Authorization -cne 'phase3d-r4b-owner-authorized-plugin-package-cutover' -or
            $script:Journal.AutomaticRetries -ne 0 -or $script:Journal.PackageSha256 -cne $expectedPackageSha256) {
            throw 'Retained package evidence does not match this authorized cutover.'
        }
        $final = Get-CutoverSnapshot -ExpectedHandlerId ([string]$script:Journal.PackageHandlerTypeId) -MaximumReadChecks 5
        if ([string]$final.Package.pluginpackageid -ine [string]$script:Journal.PackageId -or
            [string]$final.Derived.Assembly.pluginassemblyid -ine [string]$script:Journal.PackageAssemblyId -or
            $final.Api.NonHandlerSha256 -cne $script:Journal.ApiNonHandlerSha256) {
            throw 'Live package/assembly/type/Custom API reconciliation differs from retained cutover evidence.'
        }
        $plan = Get-Content -LiteralPath $LegacyDeploymentPlanPath -Raw | ConvertFrom-Json
        $legacy = Get-LegacyHandlers -Plan $plan
        if ([string]$legacy.AssemblyId -ine [string]$script:Journal.LegacyAssemblyId -or
            [string]$legacy.GuardType.plugintypeid -ine [string]$script:Journal.LegacyGuardTypeId) {
            throw 'Retained legacy assembly or guard topology no longer matches cutover evidence.'
        }
        [ordered]@{
            Result = 'PLUGIN_PACKAGE_CUTOVER_RECONCILED'
            GET = [int]$script:RequestCounts.GET + [int]$storage.Requests.GET
            PackagePosts = 0; CustomApiHandlerPatches = 0; RollbackHandlerPatches = 0
            PackageGeneratedAssemblies = 1; PackageGeneratedPluginTypes = $final.Derived.Types.Count
            HandlerMapping = 'PACKAGE_BACKED'; LegacyAssemblyRetained = $true
            AutomaticRetries = 0; EvidencePath = $EvidencePath
        } | ConvertTo-Json -Depth 10
        return
    }
    if ($Mode -ceq 'Rollback') {
        if (-not $EvidencePath -or -not (Test-Path -LiteralPath $EvidencePath)) {
            throw 'Rollback requires the retained package cutover mapping.'
        }
        $script:Journal = Get-Content -LiteralPath $EvidencePath -Raw | ConvertFrom-Json
        if ($script:Journal.Authorization -cne 'phase3d-r4b-owner-authorized-plugin-package-cutover' -or
            $script:Journal.AutomaticRetries -ne 0 -or
            @($script:Journal.Writes | Where-Object { $_.Method -ceq 'PATCH' -and $_.State -ceq 'GET_RECONCILED' }).Count -ne 1) {
            throw 'Retained evidence does not authorize exactly one reconciled handler rollback.'
        }
        $plan = Get-Content -LiteralPath $LegacyDeploymentPlanPath -Raw | ConvertFrom-Json
        $legacy = Get-LegacyHandlers -Plan $plan
        if ([string]$legacy.AssemblyId -ine [string]$script:Journal.LegacyAssemblyId -or
            [string]$legacy.GuardType.plugintypeid -ine [string]$script:Journal.LegacyGuardTypeId) {
            throw 'Legacy handler target differs from the retained rollback map.'
        }
        $currentCutover = Get-CutoverSnapshot -ExpectedHandlerId ([string]$script:Journal.PackageHandlerTypeId)
        if ([string]$currentCutover.Package.pluginpackageid -ine [string]$script:Journal.PackageId -or
            [string]$currentCutover.Api.Api.customapiid -ine [string]$script:Journal.ApiId) {
            throw 'Package-backed runtime mapping no longer matches the retained rollback map.'
        }
        $api = Get-ApiSnapshot
        if ([string]$api.Api.customapiid -ine [string]$script:Journal.ApiId -or
            [string]$api.HandlerId -ine [string]$script:Journal.PackageHandlerTypeId -or
            $api.NonHandlerSha256 -cne $script:Journal.ApiNonHandlerSha256) {
            throw 'Current Custom API does not match the retained package handler rollback map.'
        }
        $body = [ordered]@{ "$($script:Journal.HandlerNavigation)@odata.bind" = "/plugintypes($($script:Journal.LegacyHandlerTypeId))" }
        $script:Journal.Writes += [ordered]@{
            Method = 'PATCH'
            Path = "customapis($($script:Journal.ApiId))"
            PayloadSha256 = Get-Sha256 -Bytes ([Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $body -Depth 5 -Compress)))
            State = 'PLANNED'
            HttpStatus = $null
        }
        $script:WriteIndex = $script:Journal.Writes.Count - 1
        Save-PackageJournal
        $errorMessage = $null
        try { $null = Invoke-PackageRequest -Method PATCH -Path $script:Journal.Writes[$script:WriteIndex].Path -Body $body }
        catch { $errorMessage = $_.Exception.Message }
        $readback = Invoke-PackageRequest -Method GET -Path "customapis($($script:Journal.ApiId))?`$select=customapiid,uniquename,_plugintypeid_value"
        if ([string]$readback._plugintypeid_value -ine [string]$script:Journal.LegacyHandlerTypeId) {
            $script:Journal.Writes[$script:WriteIndex].State = if ($errorMessage) { 'UNCERTAIN_WRITE_OUTCOME' } else { 'REJECTED_UNRECONCILED' }
            Save-PackageJournal
            throw 'UNCERTAIN_WRITE_OUTCOME: rollback handler mapping did not reconcile; no retry.'
        }
        $script:Journal.Writes[$script:WriteIndex].State = 'GET_RECONCILED'
        $script:Journal.Result = 'PLUGIN_PACKAGE_CUTOVER_ROLLED_BACK'
        Save-PackageJournal
        [ordered]@{
            Result = 'PLUGIN_PACKAGE_CUTOVER_ROLLED_BACK'
            GET = [int]$script:RequestCounts.GET + [int]$storage.Requests.GET
            PackagePosts = 0; CustomApiHandlerPatches = 0; RollbackHandlerPatches = $script:RequestCounts.PATCH
            HandlerMapping = 'LEGACY_BACKED'; PackageRetained = $true; LegacyAssemblyRetained = $true
            AutomaticRetries = 0; EvidencePath = $EvidencePath
        } | ConvertTo-Json -Depth 10
        return
    }
} catch {
    $safe = Get-SanitizedFailureMessage -Message $_.Exception.Message
    [ordered]@{
        Result = if ($script:Journal -and @($script:Journal.Writes | Where-Object State -CEQ 'UNCERTAIN_WRITE_OUTCOME').Count) {
            'UNCERTAIN_WRITE_OUTCOME'
        } elseif ($script:Journal -and $script:Journal.Result) { [string]$script:Journal.Result }
        elseif ($script:RequestCounts.PATCH -gt 0) {
            'PLUGIN_PACKAGE_HANDLER_CUTOVER_FAILED'
        } elseif ($script:RequestCounts.POST -gt 0) {
            'PLUGIN_PACKAGE_PROCESSING_FAILED'
        } else { 'LIVE_RUNTIME_BASELINE_DRIFT' }
        Error = $safe
        GET = [int]$script:RequestCounts.GET + [int]$script:NestedGETCounts.Storage +
            [int]$script:NestedGETCounts.StrictLegacy + [int]$script:NestedGETCounts.StrictStorage +
            [int]$script:RuntimePreflightGET
        PackageGET = [int]$script:RequestCounts.GET
        StorageGET = [int]$script:NestedGETCounts.Storage
        StrictLegacyGET = [int]$script:NestedGETCounts.StrictLegacy
        StrictLegacyStorageGateGET = [int]$script:NestedGETCounts.StrictStorage
        RuntimeZeroRowGET = [int]$script:RuntimePreflightGET
        PackagePosts = [int]$script:RequestCounts.POST
        CustomApiHandlerPatches = [int]$script:RequestCounts.PATCH
        RollbackHandlerPatches = 0
        AutomaticRetries = 0
    } | ConvertTo-Json -Depth 10
    throw "Candidate Core plug-in package operation stopped; no automatic retry. $safe"
} finally {
    $script:AccessToken = $null
    [Environment]::SetEnvironmentVariable('BSO_RS_EXPECTED_USER_ID', $null, 'Process')
}
