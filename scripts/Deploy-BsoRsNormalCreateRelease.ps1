#requires -Version 7.4
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Prepare', 'Metadata', 'Package', 'RecoverPackage', 'Console', 'ConsoleRecovery', 'Verify', 'VerifyRollback', 'Rollback')][string]$Mode,
    [Parameter(Mandatory)][string]$OrganizationUrl,
    [Parameter(Mandatory)][guid]$ExpectedOrganizationId,
    [Parameter(Mandatory)][guid]$ExpectedEnvironmentId,
    [Parameter(Mandatory)][string]$BundlePath,
    [string]$ExpectedBundleManifestSha256,
    [string]$ExpectedUnpublishedRecoverySha256,
    [ValidatePattern('^[a-z][a-z0-9-]{3,60}$')][string]$RecoveryJournalPrefix
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = Split-Path $PSScriptRoot -Parent
$OrganizationUrl = $OrganizationUrl.TrimEnd('/')
$bundle = [IO.Path]::GetFullPath($BundlePath)
if ($OrganizationUrl -notmatch '^https://[^/]+$' -or
    $ExpectedOrganizationId -eq [guid]::Empty -or $ExpectedEnvironmentId -eq [guid]::Empty -or
    $bundle.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'NORMAL_RELEASE_EXTERNAL_TARGET_AND_BUNDLE_REQUIRED'
}
$script:ApiRoot = "$OrganizationUrl/api/data/v9.2/"
$script:ReadRequestCount = 0
$script:DispatchCount = 0
$AssemblyOnlyPatch = $false

$helperPath = Join-Path $PSScriptRoot 'Update-BsoRsCandidatePluginPackage.ps1'
$tokens = $null
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($helperPath, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'NORMAL_RELEASE_HELPER_PARSE_FAILED' }
foreach ($name in @('Stop-PackageUpdater', 'Get-ValidatedDataverseToken', 'Get-PacExecutablePath',
    'Get-PacPushClassification', 'Invoke-PacPluginPush', 'ConvertTo-CanonicalGuid',
    'Get-Sha256FromBytes', 'Get-LiveRolePrivilegeMap', 'Get-DevRoleState', 'Get-UnchangedSecuritySnapshot')) {
    $definitions = @($ast.EndBlock.Statements | Where-Object {
        $_ -is [Management.Automation.Language.FunctionDefinitionAst] -and $_.Name -ceq $name
    })
    if ($definitions.Count -ne 1) { throw "NORMAL_RELEASE_HELPER_REQUIRED:$name" }
    . ([scriptblock]::Create($definitions[0].Extent.Text))
}

function Save-Json {
    param([string]$Path, [object]$Value, [switch]$New)
    $bytes = [Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $Value -Depth 60) + "`n")
    $fileMode = if ($New) { [IO.FileMode]::CreateNew } else { [IO.FileMode]::Create }
    $stream = [IO.File]::Open($Path, $fileMode, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $stream.Write($bytes, 0, $bytes.Length); $stream.Flush($true) } finally { $stream.Dispose() }
}
function Hash-File {
    param([string]$Path)
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
function Request {
    param([string]$Path, [ValidateSet('GET', 'POST', 'PATCH')][string]$Method = 'GET',
        [object]$Body, [string]$ETag)
    $uri = [Uri]($script:ApiRoot + $Path)
    if ($uri.Authority -ine ([Uri]$OrganizationUrl).Authority -or
        -not $uri.AbsolutePath.StartsWith('/api/data/v9.2/') -or $uri.Fragment -or $uri.UserInfo) {
        throw 'NORMAL_RELEASE_REQUEST_ORIGIN_REJECTED'
    }
    $headers = @{
        Authorization = "Bearer $script:AccessToken"; Accept = 'application/json'
        'OData-Version' = '4.0'; 'OData-MaxVersion' = '4.0'; Consistency = 'Strong'
    }
    $arguments = @{
        Uri = $uri; Method = $Method; Headers = $headers; TimeoutSec = 120
        MaximumRetryCount = 0; MaximumRedirection = 0; SkipHttpErrorCheck = $true
    }
    if ($Method -ne 'GET') {
        if ($Method -eq 'PATCH' -and -not $ETag) { throw 'NORMAL_RELEASE_CONDITIONAL_WRITE_REQUIRED' }
        if ($Method -eq 'POST') {
            if ($Path -notin @('environmentvariabledefinitions', 'environmentvariablevalues',
                'customapiresponseproperties', 'AddSolutionComponent', 'PublishXml')) {
                throw 'NORMAL_RELEASE_WRITE_OUTSIDE_DELTA'
            }
            if ($Path -eq 'environmentvariabledefinitions' -and
                ($Body.schemaname -cne 'os_sr_ncrcfg' -or $Body.type -ne 100000000)) {
                throw 'NORMAL_RELEASE_DEFINITION_WRITE_REJECTED'
            }
            if ($Path -eq 'environmentvariablevalues' -and
                $Body.value -cne "v1|enabled=false|organizationId=$($ExpectedOrganizationId.ToString('D'))") {
                throw 'NORMAL_RELEASE_VALUE_WRITE_REJECTED'
            }
            if ($Path -eq 'customapiresponseproperties' -and
                (($Body.uniquename -cne 'CreatedCandidateId' -or $Body.type -ne 12) -and
                 ($Body.uniquename -cne 'CandidateNumber' -or $Body.type -ne 10))) {
                throw 'NORMAL_RELEASE_OUTPUT_WRITE_REJECTED'
            }
            if ($Path -eq 'AddSolutionComponent' -and
                ($Body.ComponentId -notin @($plan.metadataWrites.id) -or
                 $Body.ComponentType -notin 380, 381, 10038 -or
                 $Body.SolutionUniqueName -cne 'os_sr_bso_rs_support' -or $Body.AddRequiredComponents)) {
                throw 'NORMAL_RELEASE_MEMBERSHIP_WRITE_REJECTED'
            }
            if ($Path -eq 'PublishXml') {
                $resourceIds = @($plan.baseline.resources | Where-Object name -in 'candidate-console.js', 'candidate-console.html' |
                    ForEach-Object { "<webresource>$($_.row.webresourceid)</webresource>" }) -join ''
                if ($Body.ParameterXml -cne "<importexportxml><webresources>$resourceIds</webresources></importexportxml>") {
                    throw 'NORMAL_RELEASE_PUBLICATION_WRITE_REJECTED'
                }
            }
        } else {
            $allowedPaths = @($plan.baseline.resources | Where-Object name -in 'candidate-console.js', 'candidate-console.html' |
                ForEach-Object { "webresourceset($($_.row.webresourceid))" })
            if ($Path -notin $allowedPaths) { throw 'NORMAL_RELEASE_WRITE_OUTSIDE_DELTA' }
        }
        $headers['MSCRM.SolutionUniqueName'] = 'os_sr_bso_rs_support'
        if ($ETag) { $headers['If-Match'] = $ETag }
        $arguments.Body = ConvertTo-Json -InputObject $Body -Depth 30 -Compress
        $arguments.ContentType = 'application/json; charset=utf-8'
    }
    $response = Invoke-WebRequest @arguments
    if ([int]$response.StatusCode -notin 200, 201, 204) {
        $operation = ($Path -split '[?(]')[0]
        throw "NORMAL_RELEASE_REQUEST_REJECTED:$Method`:$operation`:HTTP_$([int]$response.StatusCode)"
    }
    if ($response.Content) { $response.Content | ConvertFrom-Json }
}
function Invoke-DataverseGet { param([string]$Path) Request $Path }
function Get-PagedRows {
    param([string]$Path)
    $response = Request $Path
    if ($response.PSObject.Properties['@odata.nextLink']) { throw 'NORMAL_RELEASE_READ_NOT_BOUNDED' }
    @($response.value)
}
function One {
    param([object[]]$Rows, [string]$Label)
    if ($Rows.Count -ne 1) { throw "NORMAL_RELEASE_AMBIGUOUS:$Label" }
    $Rows[0]
}
function Bytes-Hash {
    param([byte[]]$Bytes)
    Get-Sha256FromBytes $Bytes
}
function Resource {
    param([string]$Name, [switch]$Current)
    $set = if ($Current) {
        'webresourceset/Microsoft.Dynamics.CRM.RetrieveUnpublishedMultiple()'
    } else { 'webresourceset' }
    One @(Get-PagedRows "$set`?`$select=webresourceid,name,content&`$filter=name eq '$Name'") $Name
}
function Resource-Hash {
    param([object]$Row)
    Bytes-Hash ([Convert]::FromBase64String($Row.content))
}
function Core {
    $api = One @(Get-PagedRows "customapis?`$select=customapiid,uniquename,executeprivilegename,isprivate,isfunction,bindingtype,_plugintypeid_value&`$filter=uniquename eq 'os_sr_cact'") 'API'
    $handler = Request "plugintypes($($api._plugintypeid_value))?`$select=plugintypeid,typename,version,_pluginassemblyid_value"
    $assembly = Request "pluginassemblies($($handler._pluginassemblyid_value))?`$select=pluginassemblyid,version,publickeytoken,isolationmode,_packageid_value"
    $package = One @(Get-PagedRows "pluginpackages?`$select=pluginpackageid,uniquename,version,modifiedon&`$filter=uniquename eq 'os_sr_cact_pkg'") 'PACKAGE'
    if ($assembly._packageid_value -ne $package.pluginpackageid -or $assembly.publickeytoken -notin @($null, '', 'null') -or
        $assembly.isolationmode -ne 2 -or $handler.typename -cne 'os_sr_cact.ApplyCandidateAction' -or
        $api.executeprivilegename -cne 'prvReados_sr_cand' -or -not $api.isprivate -or
        $api.isfunction -or $api.bindingtype -ne 0) { throw 'NORMAL_RELEASE_CORE_BOUNDARY_REJECTED' }
    [pscustomobject]@{ Api = $api; Handler = $handler; Assembly = $assembly; Package = $package }
}
function Assert-Core {
    param([string]$Version)
    $current = Core
    if ($current.Assembly.version -cne $Version -or $current.Handler.version -cne $Version -or
        $current.Api.customapiid -ne $plan.baseline.core.Api.customapiid -or
        $current.Handler.plugintypeid -ne $plan.baseline.core.Handler.plugintypeid -or
        $current.Assembly.pluginassemblyid -ne $plan.baseline.core.Assembly.pluginassemblyid -or
        $current.Package.pluginpackageid -ne $plan.baseline.core.Package.pluginpackageid) {
        throw 'NORMAL_RELEASE_CORE_IDENTITY_OR_VERSION_CHANGED'
    }
    $current
}
function Assert-Disabled {
    $definition = One @(Get-PagedRows "environmentvariabledefinitions?`$select=environmentvariabledefinitionid,schemaname,type,statecode&`$filter=schemaname eq 'os_sr_ncrcfg'") 'CONFIG_DEFINITION'
    $values = @(Get-PagedRows "environmentvariablevalues?`$select=environmentvariablevalueid,value,statecode&`$filter=_environmentvariabledefinitionid_value eq $($definition.environmentvariabledefinitionid)")
    $value = One $values 'CONFIG_VALUE'
    if ($definition.type -ne 100000000 -or $definition.statecode -ne 0 -or
        $value.statecode -ne 0 -or $value.value -cne $plan.disabledConfiguration) {
        throw 'NORMAL_RELEASE_CONFIGURATION_NOT_DISABLED'
    }
}
function Assert-Security {
    if ((Get-UnchangedSecuritySnapshot).Sha256 -cne $plan.baseline.securitySha256) {
        throw 'NORMAL_RELEASE_SECURITY_BASELINE_CHANGED'
    }
}
function Write-Step {
    param([string]$Name, [scriptblock]$Action)
    $journalPath = Join-Path $bundle "journals\$Name.json"
    Save-Json $journalPath ([ordered]@{
        step = $Name; manifestSha256 = $ExpectedBundleManifestSha256
        state = 'DISPATCH_RESERVED'; retryCount = 0; utc = [DateTime]::UtcNow.ToString('o')
    }) -New
    try {
        & $Action
        Save-Json $journalPath ([ordered]@{ step = $Name; manifestSha256 = $ExpectedBundleManifestSha256; state = 'ACKNOWLEDGED'; retryCount = 0 })
    } catch {
        throw "NORMAL_RELEASE_STOP_WITHOUT_RETRY:$Name`:$($_.Exception.Message)"
    }
}

$pacText = (& pac org who --environment $OrganizationUrl 2>&1) -join "`n"
if ($LASTEXITCODE -ne 0) { throw 'NORMAL_RELEASE_PAC_IDENTITY_FAILED' }
foreach ($entry in @(@('Org ID', $ExpectedOrganizationId), @('Environment ID', $ExpectedEnvironmentId), @('Org URL', $OrganizationUrl))) {
    $match = [regex]::Match($pacText, "(?m)^\s*$($entry[0]):\s*(\S+)")
    if (-not $match.Success -or $match.Groups[1].Value.TrimEnd('/') -ine [string]$entry[1]) {
        throw 'NORMAL_RELEASE_TARGET_IDENTITY_FAILED'
    }
}
$email = [regex]::Match($pacText, '(?m)^\s*User Email:\s*(\S+)').Groups[1].Value
$pacUser = [regex]::Match($pacText, '(?m)^\s*User ID:\s*(\S+)').Groups[1].Value
$script:AccessToken = Get-ValidatedDataverseToken -TargetUrl $OrganizationUrl -PacUserEmail $email
try {
    $who = Request 'WhoAmI'
    if ($who.OrganizationId -ne $ExpectedOrganizationId -or $who.UserId -ne $pacUser) {
        throw 'NORMAL_RELEASE_DATAVERSE_IDENTITY_FAILED'
    }
    $manifestPath = Join-Path $bundle 'manifest.json'
    if ($Mode -eq 'Prepare') {
        if (Test-Path -LiteralPath $bundle) { throw 'NORMAL_RELEASE_BUNDLE_ALREADY_EXISTS' }
        $source = Get-Content (Join-Path $root 'docs\CANDIDATE_CORE_NORMAL_CREATE_1.0.9_RELEASE_MANIFEST.json') -Raw | ConvertFrom-Json
        $solution = One @(Get-PagedRows "solutions?`$select=solutionid,uniquename,version,_publisherid_value&`$filter=uniquename eq 'os_sr_bso_rs_support'") 'SOLUTION'
        $publisher = Request "publishers($($solution._publisherid_value))?`$select=uniquename,customizationprefix"
        if ($publisher.customizationprefix -cne 'os') { throw 'NORMAL_RELEASE_PUBLISHER_REJECTED' }
        $core = Core
        if ($core.Assembly.version -cne '1.0.8.0') { throw 'NORMAL_RELEASE_UNEXPECTED_BASELINE_VERSION' }
        if (@(Get-PagedRows "environmentvariabledefinitions?`$select=environmentvariabledefinitionid&`$filter=schemaname eq 'os_sr_ncrcfg'").Count) {
            throw 'NORMAL_RELEASE_CONFIG_ALREADY_EXISTS_RECONCILE_FIRST'
        }
        $outputs = @(Get-PagedRows "customapiresponseproperties?`$select=uniquename,type&`$filter=_customapiid_value eq $($core.Api.customapiid)")
        $inputs = @(Get-PagedRows "customapirequestparameters?`$select=uniquename,type,isoptional&`$filter=_customapiid_value eq $($core.Api.customapiid)" |
            Select-Object uniquename,type,isoptional | Sort-Object uniquename)
        if ($inputs.Count -ne 22) { throw 'NORMAL_RELEASE_API_INPUT_BASELINE_CHANGED' }
        if ($outputs.Count -ne 7 -or @($outputs | Where-Object { $_.uniquename -in 'CreatedCandidateId', 'CandidateNumber' }).Count) {
            throw 'NORMAL_RELEASE_API_OUTPUT_BASELINE_CHANGED'
        }
        $security = Get-UnchangedSecuritySnapshot
        $app = One @(Get-PagedRows "appmodules?`$select=appmoduleid,uniquename&`$filter=uniquename eq 'srapp'") 'APP'
        $resources = @(
            foreach ($name in @('candidate-console.html', 'candidate-console.js', 'candidate-console-environment.js', 'candidate-console-policy.js')) {
                $published = Resource "os_/bso/$name"
                $current = Resource "os_/bso/$name" -Current
                if ((Resource-Hash $published) -cne (Resource-Hash $current)) { throw "NORMAL_RELEASE_UNPUBLISHED_DRIFT:$name" }
                [pscustomobject]@{ name = $name; row = $current; sha256 = Resource-Hash $published }
            }
        )
        $environmentText = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(($resources | Where-Object name -eq 'candidate-console-environment.js').row.content))
        if ($environmentText -notmatch '"?candidateOperationMode"?\s*:\s*"SingleUserDev"' -or
            $environmentText -notmatch '"?syntheticDataOnly"?\s*:\s*true' -or
            $environmentText -notmatch '"?devDirectWriteFallbackEnabled"?\s*:\s*false') { throw 'NORMAL_RELEASE_CONSOLE_BASELINE_NOT_ISOLATED' }
        $packagePath = [IO.Path]::GetFullPath((Join-Path "$root\docs" $source.build.packageFile))
        if ((Hash-File $packagePath) -cne $source.build.packageSha256) { throw 'NORMAL_RELEASE_PACKAGE_HASH_FAILED' }
        $null = New-Item -ItemType Directory -Path $bundle
        foreach ($directory in @('payloads', 'rollback', 'journals')) { $null = New-Item -ItemType Directory -Path (Join-Path $bundle $directory) }
        Copy-Item -LiteralPath $packagePath -Destination (Join-Path $bundle 'payloads\os_sr_cact_pkg.1.0.9.nupkg')
        foreach ($resource in $resources) {
            [IO.File]::WriteAllBytes((Join-Path $bundle "rollback\$($resource.name)"), [Convert]::FromBase64String($resource.row.content))
        }
        foreach ($name in @('candidate-console.js', 'candidate-console.html')) {
            $delta = One @($source.exactComponentDelta | Where-Object uniqueName -eq "os_/bso/$name") 'SOURCE_RESOURCE'
            $path = [IO.Path]::GetFullPath((Join-Path "$root\docs" $delta.sourceFile))
            if ((Hash-File $path) -cne $delta.sourceSha256) { throw "NORMAL_RELEASE_SOURCE_HASH_FAILED:$name" }
            Copy-Item -LiteralPath $path -Destination (Join-Path $bundle "payloads\$name")
        }
        $definitionId = [guid]::NewGuid().ToString('D')
        $valueId = [guid]::NewGuid().ToString('D')
        $disabled = "v1|enabled=false|organizationId=$($ExpectedOrganizationId.ToString('D'))"
        $writes = @(
            [ordered]@{ name = 'definition'; path = 'environmentvariabledefinitions'; id = $definitionId; componentType = 380; body = @{
                environmentvariabledefinitionid = $definitionId; schemaname = 'os_sr_ncrcfg'
                displayname = 'NORMAL Create Candidate configuration'; type = 100000000; isrequired = $false
                description = 'Server-controlled organization-bound NORMAL Create gate. Disabled until real-data controls are approved.'
            }},
            [ordered]@{ name = 'value'; path = 'environmentvariablevalues'; id = $valueId; componentType = 381; body = @{
                environmentvariablevalueid = $valueId; value = $disabled
                'EnvironmentVariableDefinitionId@odata.bind' = "/environmentvariabledefinitions($definitionId)"
            }}
        )
        foreach ($output in @(@('CreatedCandidateId', 12), @('CandidateNumber', 10))) {
            $id = [guid]::NewGuid().ToString('D')
            $writes += [ordered]@{ name = $output[0]; path = 'customapiresponseproperties'; id = $id; componentType = 10038; body = @{
                customapiresponsepropertyid = $id; uniquename = $output[0]; name = "os_sr_cact.$($output[0])"
                displayname = $output[0]; description = "Created Candidate $($output[0])"; type = $output[1]
                'CustomAPIId@odata.bind' = "/customapis($($core.Api.customapiid))"
            }}
        }
        $plan = [ordered]@{
            release = 'NORMAL Create Candidate 1.0.9'; packageType = 'EXACT_COMPONENT_DEPLOYMENT_BUNDLE_NOT_MANAGED_SOLUTION'
            organizationUrl = $OrganizationUrl; organizationId = $ExpectedOrganizationId.ToString('D')
            environmentId = $ExpectedEnvironmentId.ToString('D'); solutionUniqueName = $solution.uniquename
            disabledConfiguration = $disabled; realDataActivationAllowed = $false
            manualTestUrl = "$OrganizationUrl/main.aspx?appid=$($app.appmoduleid)"
            baseline = @{ core = $core; resources = $resources; outputs = $outputs; inputs = $inputs; securitySha256 = $security.Sha256 }
            metadataWrites = $writes; packageSha256 = $source.build.packageSha256
            payloadHashes = @{ 'candidate-console.js' = Hash-File (Join-Path $bundle 'payloads\candidate-console.js')
                'candidate-console.html' = Hash-File (Join-Path $bundle 'payloads\candidate-console.html') }
            rollback = @{
                strategy = 'Disable NORMAL configuration; retain protected 1.0.9 backend and additive outputs; restore previous Console pair.'
                assemblyRecoveryArtifact = 'payloads/os_sr_cact_pkg.1.0.9.nupkg'
                downgradeTo108Allowed = $false; preservesReadOnlyApiPrivilegeAndSingleUserDev = $true
            }
        }
        Save-Json $manifestPath $plan -New
        [pscustomobject]@{ Result = 'DISABLED_RELEASE_BUNDLE_PREPARED'; ManifestSha256 = Hash-File $manifestPath; SecuritySha256 = $security.Sha256 }
        return
    }
    if (-not $ExpectedBundleManifestSha256 -or (Hash-File $manifestPath) -cne $ExpectedBundleManifestSha256) { throw 'NORMAL_RELEASE_MANIFEST_PIN_REQUIRED' }
    $plan = Get-Content $manifestPath -Raw | ConvertFrom-Json
    if ($plan.organizationUrl -cne $OrganizationUrl -or $plan.organizationId -ne $ExpectedOrganizationId -or
        $plan.environmentId -ne $ExpectedEnvironmentId -or $plan.realDataActivationAllowed -or
        $plan.disabledConfiguration -cne "v1|enabled=false|organizationId=$($ExpectedOrganizationId.ToString('D'))") {
        throw 'NORMAL_RELEASE_TARGET_OR_ACTIVATION_REJECTED'
    }
    if ((Hash-File (Join-Path $bundle 'payloads\os_sr_cact_pkg.1.0.9.nupkg')) -cne $plan.packageSha256) { throw 'NORMAL_RELEASE_PACKAGE_DRIFT' }
    Assert-Security
    if ($Mode -eq 'Metadata') {
        $null = Assert-Core '1.0.8.0'
        foreach ($write in $plan.metadataWrites) {
            Write-Step "metadata-$($write.name)" { $null = Request $write.path 'POST' $write.body }
            $row = Request "$($write.path)($($write.id))"
            if ($null -eq $row) { throw 'NORMAL_RELEASE_METADATA_READBACK_FAILED' }
            $members = @(Get-PagedRows "solutioncomponents?`$select=objectid&`$filter=_solutionid_value eq $((One @(Get-PagedRows "solutions?`$select=solutionid&`$filter=uniquename eq 'os_sr_bso_rs_support'") 'SOLUTION').solutionid) and objectid eq $($write.id)")
            if ($members.Count -eq 0) {
                Write-Step "membership-$($write.name)" {
                    $null = Request 'AddSolutionComponent' 'POST' @{
                        ComponentId = $write.id; ComponentType = $write.componentType
                        SolutionUniqueName = 'os_sr_bso_rs_support'; AddRequiredComponents = $false
                    }
                }
            }
        }
        Assert-Disabled
    } elseif ($Mode -in 'Package', 'RecoverPackage') {
        Assert-Disabled
        $expectedVersion = if ($Mode -eq 'RecoverPackage') { '1.0.9.0' } else { '1.0.8.0' }
        $current = Assert-Core $expectedVersion
        if ($Mode -eq 'Package' -and $current.Package.modifiedon -cne $plan.baseline.core.Package.modifiedon) {
            throw 'NORMAL_RELEASE_PACKAGE_CHANGED'
        }
        Write-Step $Mode {
            $arguments = @('plugin', 'push', '--environment', $OrganizationUrl, '--pluginId', $current.Package.pluginpackageid,
                '--pluginFile', (Join-Path $bundle 'payloads\os_sr_cact_pkg.1.0.9.nupkg'), '--type', 'Nuget', '--configuration', 'Release')
            $result = Invoke-PacPluginPush 'pac' $arguments
            if ($result.Classification -cne 'PAC_SUCCESS_REPORTED') { throw "NORMAL_RELEASE_PACKAGE_$($result.Classification)" }
        }
        $null = Assert-Core '1.0.9.0'
    } elseif ($Mode -in 'Console', 'ConsoleRecovery', 'Rollback') {
        $null = Assert-Core '1.0.9.0'
        Assert-Disabled
        if ($Mode -eq 'ConsoleRecovery') {
            if ($ExpectedUnpublishedRecoverySha256 -notmatch '^[0-9a-f]{64}$' -or -not $RecoveryJournalPrefix) {
                throw 'NORMAL_RELEASE_RECOVERY_HASH_AND_FRESH_JOURNAL_REQUIRED'
            }
            $originalJournal = Get-Content (Join-Path $bundle 'journals\Console-candidate-console.js.json') -Raw | ConvertFrom-Json
            if ($originalJournal.state -cne 'ACKNOWLEDGED' -or
                $originalJournal.manifestSha256 -cne $ExpectedBundleManifestSha256 -or
                (Test-Path (Join-Path $bundle 'journals\Console-candidate-console.html.json')) -or
                (Test-Path (Join-Path $bundle 'journals\Console-publish.json'))) {
                throw 'NORMAL_RELEASE_RECOVERY_BASELINE_REJECTED'
            }
        }
        foreach ($name in @('candidate-console.js', 'candidate-console.html')) {
            $previous = One @($plan.baseline.resources | Where-Object name -eq $name) 'RESOURCE_BASELINE'
            $current = Resource "os_/bso/$name" -Current
            $published = Resource "os_/bso/$name"
            $expectedCurrent = if ($Mode -eq 'Rollback') { $plan.payloadHashes.$name } else { $previous.sha256 }
            $expectedPublished = $expectedCurrent
            if ($Mode -eq 'ConsoleRecovery' -and $name -ceq 'candidate-console.js') { $expectedCurrent = $ExpectedUnpublishedRecoverySha256 }
            if ((Resource-Hash $current) -cne $expectedCurrent -or (Resource-Hash $published) -cne $expectedPublished) {
                throw "NORMAL_RELEASE_CONSOLE_DRIFT:$name"
            }
            $conditionalRow = Request "webresourceset($($current.webresourceid))?`$select=webresourceid,name,content"
            if ((Resource-Hash $conditionalRow) -cne $expectedPublished) { throw 'NORMAL_RELEASE_CONDITIONAL_BASELINE_CHANGED' }
            $directory = if ($Mode -eq 'Rollback') { 'rollback' } else { 'payloads' }
            $path = Join-Path $bundle "$directory\$name"
            $expectedPayload = if ($Mode -eq 'Rollback') { $previous.sha256 } else { $plan.payloadHashes.$name }
            if ((Hash-File $path) -cne $expectedPayload) { throw 'NORMAL_RELEASE_RESOURCE_PAYLOAD_CHANGED' }
            $dispatchName = if ($Mode -eq 'ConsoleRecovery') { "$RecoveryJournalPrefix-$name" } else { "$Mode-$name" }
            Write-Step $dispatchName {
                $null = Request "webresourceset($($current.webresourceid))" 'PATCH' @{
                    content = [Convert]::ToBase64String([IO.File]::ReadAllBytes($path))
                } $conditionalRow.'@odata.etag'
            }
            if ((Resource-Hash (Resource "os_/bso/$name" -Current)) -cne $expectedPayload) { throw 'NORMAL_RELEASE_CURRENT_RESOURCE_READBACK_FAILED' }
        }
        $ids = @($plan.baseline.resources | Where-Object name -in 'candidate-console.js', 'candidate-console.html' | ForEach-Object {
            "<webresource>$($_.row.webresourceid)</webresource>"
        }) -join ''
        $publishDispatch = if ($Mode -eq 'ConsoleRecovery') { "$RecoveryJournalPrefix-publish" } else { "$Mode-publish" }
        Write-Step $publishDispatch { $null = Request 'PublishXml' 'POST' @{ ParameterXml = "<importexportxml><webresources>$ids</webresources></importexportxml>" } }
    } elseif ($Mode -in 'Verify', 'VerifyRollback') {
        $current = Assert-Core '1.0.9.0'
        Assert-Disabled
        $outputs = @(Get-PagedRows "customapiresponseproperties?`$select=uniquename,type&`$filter=_customapiid_value eq $($current.Api.customapiid)")
        if ($outputs.Count -ne 9) { throw 'NORMAL_RELEASE_OUTPUT_COUNT_FAILED' }
        foreach ($baselineOutput in $plan.baseline.outputs) {
            $row = One @($outputs | Where-Object uniquename -eq $baselineOutput.uniquename) 'COMPATIBLE_OUTPUT'
            if ($row.type -ne $baselineOutput.type) { throw 'NORMAL_RELEASE_EXISTING_OUTPUT_CHANGED' }
        }
        $inputs = @(Get-PagedRows "customapirequestparameters?`$select=uniquename,type,isoptional&`$filter=_customapiid_value eq $($current.Api.customapiid)" |
            Select-Object uniquename,type,isoptional | Sort-Object uniquename)
        if ((ConvertTo-Json -InputObject $inputs -Compress) -cne (ConvertTo-Json -InputObject $plan.baseline.inputs -Compress)) {
            throw 'NORMAL_RELEASE_EXISTING_INPUT_CHANGED'
        }
        $solution = One @(Get-PagedRows "solutions?`$select=solutionid&`$filter=uniquename eq 'os_sr_bso_rs_support'") 'SOLUTION'
        foreach ($write in $plan.metadataWrites) {
            $members = @(Get-PagedRows "solutioncomponents?`$select=objectid,componenttype&`$filter=_solutionid_value eq $($solution.solutionid) and objectid eq $($write.id)")
            if (@($members | Where-Object componenttype -eq $write.componentType).Count -ne 1) {
                throw "NORMAL_RELEASE_SOLUTION_MEMBERSHIP_MISSING:$($write.name)"
            }
        }
        foreach ($output in @(@('CreatedCandidateId', 12), @('CandidateNumber', 10))) {
            $row = One @($outputs | Where-Object uniquename -eq $output[0]) 'OUTPUT'
            if ($row.type -ne $output[1]) { throw 'NORMAL_RELEASE_OUTPUT_TYPE_FAILED' }
        }
        foreach ($resource in $plan.baseline.resources) {
            $name = $resource.name
            $expected = if ($Mode -eq 'Verify' -and $name -in 'candidate-console.js', 'candidate-console.html') {
                $plan.payloadHashes.$name
            } else { $resource.sha256 }
            if ((Resource-Hash (Resource "os_/bso/$name")) -cne $expected -or
                (Resource-Hash (Resource "os_/bso/$name" -Current)) -cne $expected) { throw "NORMAL_RELEASE_PUBLISHED_HASH_FAILED:$name" }
            $response = Invoke-WebRequest -Uri "$OrganizationUrl/WebResources/os_/bso/$name`?release=$ExpectedBundleManifestSha256" -Headers @{
                Authorization = "Bearer $script:AccessToken"; 'Cache-Control' = 'no-cache'
            } -MaximumRetryCount 0 -MaximumRedirection 0
            if ((Bytes-Hash $response.RawContentStream.ToArray()) -cne $expected) { throw "NORMAL_RELEASE_SERVED_HASH_FAILED:$name" }
        }
        $privilege = One @(Get-PagedRows "privileges?`$select=privilegeid,name&`$filter=name eq 'prvCreateos_sr_cand'") 'CREATE_PRIVILEGE'
        $effective = Request "systemusers($($who.UserId))/Microsoft.Dynamics.CRM.RetrieveUserSetOfPrivilegesByNames(PrivilegeNames=@names,ExcludeTeamBasic=false)?@names=%5B%22prvCreateos_sr_cand%22%5D"
        $hasCreate = @($effective.RolePrivileges | Where-Object PrivilegeId -eq $privilege.privilegeid).Count -gt 0
        Save-Json (Join-Path $bundle "$Mode-verification.json") ([ordered]@{
            installedAssemblyVersion = $current.Assembly.version; apiOutputCount = $outputs.Count
            configuration = 'EXACT_ORGANIZATION_BOUND_DISABLED'; normalCreateEnabled = $false
            consolePublishedAndServedHashesVerified = $true; securityFingerprintUnchanged = $true
            deploymentIdentityHasEffectiveCreate = $hasCreate; candidateActionInvoked = $false
            manualTestUrl = $plan.manualTestUrl
        })
    }
    Assert-Security
    [pscustomobject]@{ Result = "DISABLED_RELEASE_${Mode}_VERIFIED"; NormalCreateEnabled = $false }
} finally {
    $script:AccessToken = $null
}
