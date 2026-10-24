#requires -Version 7.4
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Preflight', 'Apply', 'Reconcile')][string]$DeploymentMode,
    [Parameter(Mandatory)][string]$EnvironmentName,
    [Parameter(Mandatory)][string]$OrganizationUrl,
    [Parameter(Mandatory)][string]$ExpectedEnvironmentId,
    [Parameter(Mandatory)][string]$ExpectedOrganizationId,
    [Parameter(Mandatory)][string]$DeploymentPlanPath,
    [string]$DispatchEvidencePath,
    [string]$ExpectedDeploymentPlanSha256
)

$ErrorActionPreference = 'Stop'
$deploymentRoot = Split-Path $PSScriptRoot
$deploymentScriptDirectory = $PSScriptRoot
$deploymentContractPath = Join-Path $deploymentRoot 'docs\PHASE_3C_API_CONTRACT.json'
$deploymentAssemblyPath = Join-Path $deploymentRoot 'solutions\CandidateCore\bin\Release\net462\os_sr_cact.dll'
$deploymentContract = Get-Content -Raw $deploymentContractPath | ConvertFrom-Json
$deploymentCounts = @{ GET = 0; POST = 0 }
$deploymentIndex = 0
$deploymentJournal = $null
$deploymentStorageGets = 0
$deploymentPlan = $null
# Import existing guarded read helpers without executing an older provisioning main.
$null = . (Join-Path $deploymentScriptDirectory 'Provision-BsoRsOperationReceipt.ps1') -Mode PlanOnly `
    -EnvironmentName $EnvironmentName -OrganizationUrl $OrganizationUrl `
    -ExpectedEnvironmentId $ExpectedEnvironmentId -ExpectedOrganizationId $ExpectedOrganizationId

function Invoke-DeploymentRequest {
    param([ValidateSet('GET', 'POST')][string]$Method, [string]$Path, [object]$Body)
    $uri = [Uri]($script:ApiRoot + $Path)
    if ($uri.Scheme -cne 'https' -or $uri.Authority -ine ([Uri]$OrganizationUrl).Authority -or
        $uri.AbsolutePath -notmatch '^/api/data/v9\.2/' -or $uri.UserInfo -or $uri.Fragment) { throw 'Foreign deployment API URL.' }
    $headers = @{ Authorization = "Bearer $script:AccessToken"; Accept = 'application/json'
        'OData-Version' = '4.0'; 'OData-MaxVersion' = '4.0'; Consistency = 'Strong' }
    $arguments = @{ Uri = $uri; Method = $Method; Headers = $headers; MaximumRetryCount = 0
        MaximumRedirection = 0; TimeoutSec = 120; SkipHttpErrorCheck = $true }
    if ($Method -ceq 'POST') {
        if ($Path -cnotin @('pluginassemblies', 'plugintypes', 'sdkmessageprocessingsteps', 'customapis',
            'customapirequestparameters', 'customapiresponseproperties')) { throw 'Non-registration write path rejected.' }
        if ($DeploymentMode -cne 'Apply' -or $null -eq $script:deploymentJournal -or
            $script:deploymentIndex -ge $script:deploymentPlan.Writes.Count) { throw 'Deployment write ceiling/mode guard.' }
        $expected = $script:deploymentPlan.Writes[$script:deploymentIndex]
        $entry = $script:deploymentJournal.Writes[$script:deploymentIndex]
        $json = ConvertTo-Json -InputObject $Body -Depth 80 -Compress
        if ($Path -cne $expected.Path -or $entry.State -cne 'PLANNED' -or
            (Get-Sha256 -Bytes ([Text.Encoding]::UTF8.GetBytes($json))) -cne $expected.PayloadSha256) {
            throw 'Deployment dispatch differs from pinned plan or was already consumed.'
        }
        $entry.State = 'DISPATCH_RESERVED'
        Save-DeploymentJournal
        $script:deploymentIndex++
        $headers['MSCRM.SolutionUniqueName'] = 'os_sr_bso_rs_support'
        $arguments.Body = $json
        $arguments.ContentType = 'application/json; charset=utf-8'
    }
    $script:deploymentCounts[$Method]++
    try { $response = Invoke-WebRequest @arguments }
    catch { throw 'UNCERTAIN_WRITE_OR_READ_TRANSPORT; reconcile and stop; no retry.' }
    if ($Method -ceq 'POST') {
        $entry.HttpStatus = [int]$response.StatusCode
        $entry.State = if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 300) { 'ACKNOWLEDGED' } else { 'REJECTED' }
        Save-DeploymentJournal
    }
    if ($response.StatusCode -lt 200 -or $response.StatusCode -ge 300) {
        $parsed = $null
        try { $parsed = $response.Content | ConvertFrom-Json } catch { $parsed = $null }
        throw (Get-SanitizedDataverseError -StatusCode $response.StatusCode -Response $parsed)
    }
    if (-not [string]::IsNullOrWhiteSpace($response.Content)) { $response.Content | ConvertFrom-Json }
}

function Get-DeploymentRows {
    param([string]$Path)
    do {
        $page = Invoke-DeploymentRequest -Method GET -Path $Path
        $page.value
        $next = [string]$page.'@odata.nextLink'
        if ($next) {
            if (-not $next.StartsWith($script:ApiRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Foreign registration continuation.' }
            $Path = $next.Substring($script:ApiRoot.Length)
        } else { $Path = $null }
    } while ($Path)
}

function Save-DeploymentJournal {
    $stream = [IO.File]::Open($DispatchEvidencePath, [IO.FileMode]::Open, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $script:deploymentJournal -Depth 80))
        $stream.SetLength(0); $stream.Write($bytes, 0, $bytes.Length); $stream.Flush($true)
    } finally { $stream.Dispose() }
}

function Get-RegistrationNavigation {
    param([string]$Table, [string]$Attribute, [string]$Target)
    $matches = @(Get-DeploymentRows -Path "EntityDefinitions(LogicalName='$Table')/ManyToOneRelationships?`$select=ReferencingAttribute,ReferencedEntity,ReferencingEntityNavigationPropertyName" |
        Where-Object { $_.ReferencingAttribute -ceq $Attribute -and $_.ReferencedEntity -ceq $Target })
    if ($matches.Count -ne 1 -or -not $matches[0].ReferencingEntityNavigationPropertyName) {
        throw "Cannot resolve supported registration navigation: $Table/$Attribute"
    }
    [string]$matches[0].ReferencingEntityNavigationPropertyName
}

function New-RegistrationWrite {
    param([string]$Path, [string]$IdColumn, [int]$ComponentType, [object]$Body)
    [ordered]@{ Path = $Path; IdColumn = $IdColumn; Id = [string]$Body.$IdColumn
        ComponentType = $ComponentType; Body = $Body
        PayloadSha256 = Get-Sha256 -Bytes ([Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $Body -Depth 80 -Compress))) }
}

function Get-RegistrationInventory {
    [ordered]@{
        Assemblies = @(Get-DeploymentRows -Path "pluginassemblies?`$select=pluginassemblyid,name&`$filter=name eq 'os_sr_cact'")
        Types = @(Get-DeploymentRows -Path "plugintypes?`$select=plugintypeid,typename&`$filter=typename eq 'os_sr_cact.ApplyCandidateAction' or typename eq 'os_sr_cact.ProtectCandidateCore'")
        APIs = @(Get-DeploymentRows -Path "customapis?`$select=customapiid,uniquename&`$filter=uniquename eq 'os_sr_cact'")
        Steps = @(Get-DeploymentRows -Path "sdkmessageprocessingsteps?`$select=sdkmessageprocessingstepid,name&`$filter=startswith(name,'os_sr_cact.guard.')")
    }
}

function Assert-RegistrationReadback {
    param([object]$Write)
    $row = Invoke-DeploymentRequest -Method GET -Path "$($Write.Path)($($Write.Id))"
    foreach ($property in $Write.Body.PSObject.Properties) {
        $name = $property.Name
        $wanted = $property.Value
        if ($name.EndsWith('@odata.bind')) {
            $nav = $name.Substring(0, $name.Length - '@odata.bind'.Length)
            $related = Invoke-DeploymentRequest -Method GET -Path "$($Write.Path)($($Write.Id))/$nav"
            $expectedId = [regex]::Match([string]$wanted, '\(([0-9a-fA-F-]{36})\)$').Groups[1].Value
            if (-not $expectedId -or [string]$related.'@odata.id' -and [string]$related.'@odata.id' -notlike "*($expectedId)") {
                throw 'Related registration identity differs.'
            }
            $guidFields = @($related.PSObject.Properties | Where-Object {
                $_.Name -match 'id$' -and [string]$_.Value -ieq $expectedId
            })
            if ($guidFields.Count -eq 0) { throw "Registration navigation failed readback: $nav" }
        } elseif ($name -ceq 'content') {
            $readHash = Get-Sha256 -Bytes ([Convert]::FromBase64String([string]$row.content))
            if ($readHash -cne $script:deploymentPlan.AssemblySha256) { throw 'Deployed assembly content hash differs.' }
        } elseif ($null -eq $wanted) {
            if ($null -ne $row.$name) { throw "Expected null registration property: $name" }
        } elseif ($wanted -is [bool]) {
            if ($row.$name -isnot [bool] -or $row.$name -ne $wanted) { throw "Registration Boolean mismatch: $name" }
        } elseif ([string]$row.$name -cne [string]$wanted) {
            throw "Registration property mismatch: $name"
        }
    }
    if ($Write.Path -ceq 'sdkmessageprocessingsteps' -and
        ([int]$row.statecode -ne 0 -or $null -ne $row._impersonatinguserid_value)) {
        throw 'Guard step must be enabled and execute as calling user.'
    }
}

function Assert-RegistrationMembership {
    $apiComponentTypes = @{}
    foreach ($mapping in @(
        @{ Path = 'customapis'; Table = 'customapi' },
        @{ Path = 'customapirequestparameters'; Table = 'customapirequestparameter' },
        @{ Path = 'customapiresponseproperties'; Table = 'customapiresponseproperty' }
    )) {
        $metadata = Invoke-DeploymentRequest -Method GET -Path "EntityDefinitions(LogicalName='$($mapping.Table)')?`$select=ObjectTypeCode"
        if ([int]$metadata.ObjectTypeCode -le 0) { throw 'Custom API Solution component code unavailable.' }
        $apiComponentTypes[$mapping.Path] = [int]$metadata.ObjectTypeCode
    }
    $filter = [Uri]::EscapeDataString("_solutionid_value eq $($script:Solution.solutionid)")
    $components = @(Get-DeploymentRows -Path "solutioncomponents?`$select=objectid,componenttype,rootcomponentbehavior&`$filter=$filter")
    foreach ($write in $script:deploymentPlan.Writes) {
        if ($write.Path -ceq 'plugintypes') { continue } # Types are subcomponents of the assembly root.
        $componentType = if ($apiComponentTypes.ContainsKey($write.Path)) { $apiComponentTypes[$write.Path] } else { $write.ComponentType }
        $matches = @($components | Where-Object { [string]$_.objectid -ieq $write.Id -and $_.componenttype -eq $componentType })
        if ($matches.Count -eq 0 -and $write.Path -cin @('customapirequestparameters', 'customapiresponseproperties')) {
            $apiWrite = @($script:deploymentPlan.Writes | Where-Object Path -CEQ 'customapis')[0]
            $apiRoots = @($components | Where-Object {
                [string]$_.objectid -ieq $apiWrite.Id -and $_.componenttype -eq $apiComponentTypes.customapis -and $_.rootcomponentbehavior -eq 0
            })
            if ($apiRoots.Count -eq 1) { continue }
        }
        if ($matches.Count -ne 1) { throw "Missing/duplicate Solution membership: $($write.Path)" }
        if ($write.Path -ceq 'pluginassemblies' -and $matches[0].rootcomponentbehavior -ne 0) {
            throw 'Assembly root must include its plugin types.'
        }
    }
}

function Assert-RegistrationInventoryExact {
    $inventory = Get-RegistrationInventory
    if ($inventory.Assemblies.Count -ne 1 -or $inventory.Types.Count -ne 2 -or $inventory.APIs.Count -ne 1) {
        throw 'Assembly/type/API inventory not exact.'
    }
    $expectedSteps = @($script:deploymentPlan.Writes | Where-Object Path -CEQ 'sdkmessageprocessingsteps')
    if ((Compare-Object @($expectedSteps.Id) @($inventory.Steps.sdkmessageprocessingstepid)).Count) {
        throw 'Guard-step inventory differs or includes duplicates.'
    }
    $apiWrite = @($script:deploymentPlan.Writes | Where-Object Path -CEQ 'customapis')[0]
    foreach ($table in @('customapirequestparameters', 'customapiresponseproperties')) {
        $rows = @(Get-DeploymentRows -Path "$table`?`$select=uniquename&`$filter=_customapiid_value eq $($apiWrite.Id)")
        $expectedNames = @($script:deploymentPlan.Writes | Where-Object Path -CEQ $table | ForEach-Object { $_.Body.uniquename })
        if ((Compare-Object $expectedNames @($rows.uniquename)).Count) { throw 'API parameter/response inventory differs or includes duplicates.' }
    }
}

try {
    # A fresh full storage/identity gate runs before registration discovery or dispatch.
    $storageText = @(& (Join-Path $deploymentScriptDirectory 'Provision-BsoRsOperationReceipt.ps1') -Mode Reconcile `
        -EnvironmentName $EnvironmentName -OrganizationUrl $OrganizationUrl `
        -ExpectedEnvironmentId $ExpectedEnvironmentId -ExpectedOrganizationId $ExpectedOrganizationId)
    $storage = ($storageText -join "`n") | ConvertFrom-Json
    $deploymentStorageGets = [int]$storage.Requests.GET + [int]$storage.CandidateGET
    if ($storage.Result -cne 'OPERATION_RECEIPT_STORAGE_RECONCILED' -or $storage.CandidateCore -cne 'EXACT' -or
        $storage.Requests.POST -ne 0 -or $storage.Requests.PUT -ne 0) { throw 'Storage pre-deployment gate failed.' }
    Assert-TargetInput
    Assert-PacIdentity
    Get-ValidatedToken
    $script:ApiRoot = $OrganizationUrl.TrimEnd('/') + '/api/data/v9.2/'
    $who = Invoke-DeploymentRequest -Method GET -Path 'WhoAmI'
    if ([string]$who.UserId -ine $script:ExpectedUserId -or [string]$who.OrganizationId -ine $ExpectedOrganizationId -or
        [Environment]::GetEnvironmentVariable('BSO_RS_EXPECTED_USER_ID', 'Process') -cne $script:ExpectedUserId) { throw 'Deployment WhoAmI mismatch.' }
    $solutionRows = @(Get-DeploymentRows -Path "solutions?`$select=solutionid,uniquename,ismanaged,_publisherid_value&`$filter=uniquename eq 'os_sr_bso_rs_support'")
    $publisherRows = @(Get-DeploymentRows -Path "publishers?`$select=publisherid,uniquename,customizationprefix&`$filter=uniquename eq 'os_bso_rs_support'")
    if ($solutionRows.Count -ne 1 -or $solutionRows[0].ismanaged -or $publisherRows.Count -ne 1 -or
        $publisherRows[0].customizationprefix -cne 'os' -or $solutionRows[0]._publisherid_value -ine $publisherRows[0].publisherid) { throw 'Deployment Solution/Publisher mismatch.' }
    $script:Solution = $solutionRows[0]
    $assemblyHash = (Get-FileHash -LiteralPath $deploymentAssemblyPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $contractHash = (Get-FileHash -LiteralPath $deploymentContractPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $inventory = Get-RegistrationInventory
    if ($DeploymentMode -ceq 'Preflight') {
        if ($inventory.Assemblies.Count -or $inventory.Types.Count -or $inventory.APIs.Count -or $inventory.Steps.Count) {
            throw 'Registration already exists; reconcile rather than repeat creates.'
        }
        $assemblyName = [Reflection.AssemblyName]::GetAssemblyName($deploymentAssemblyPath)
        $publicToken = [Convert]::ToHexString($assemblyName.GetPublicKeyToken()).ToLowerInvariant()
        if ($assemblyName.Name -cne 'os_sr_cact' -or [string]$assemblyName.Version -cne '1.0.0.0' -or $publicToken.Length -ne 16) {
            throw 'Assembly identity, version, or strong-name token differs.'
        }
        $writes = [System.Collections.Generic.List[object]]::new()
        $assemblyId = [Guid]::NewGuid().ToString()
        $mainId = [Guid]::NewGuid().ToString()
        $guardId = [Guid]::NewGuid().ToString()
        $apiId = [Guid]::NewGuid().ToString()
        $writes.Add((New-RegistrationWrite 'pluginassemblies' 'pluginassemblyid' 91 ([ordered]@{
            pluginassemblyid = $assemblyId; name = 'os_sr_cact'; version = '1.0.0.0'; culture = 'neutral'
            publickeytoken = $publicToken; isolationmode = 2; sourcetype = 0
            content = [Convert]::ToBase64String([IO.File]::ReadAllBytes($deploymentAssemblyPath))
        })))
        $assemblyNav = Get-RegistrationNavigation 'plugintype' 'pluginassemblyid' 'pluginassembly'
        foreach ($type in @(@{ Id = $mainId; Name = $deploymentContract.handler }, @{ Id = $guardId; Name = $deploymentContract.guard })) {
            $body = [ordered]@{ plugintypeid = $type.Id; typename = $type.Name; name = $type.Name
                friendlyname = $type.Name; description = 'Candidate Core server enforcement'
                "$assemblyNav@odata.bind" = "/pluginassemblies($assemblyId)" }
            $writes.Add((New-RegistrationWrite 'plugintypes' 'plugintypeid' 90 $body))
        }
        $messageNav = Get-RegistrationNavigation 'sdkmessageprocessingstep' 'sdkmessageid' 'sdkmessage'
        $filterNav = Get-RegistrationNavigation 'sdkmessageprocessingstep' 'sdkmessagefilterid' 'sdkmessagefilter'
        $handlerNav = Get-RegistrationNavigation 'sdkmessageprocessingstep' 'eventhandler' 'plugintype'
        $messages = @(Get-DeploymentRows -Path 'sdkmessages?$select=sdkmessageid,name')
        $guardCoverage = [System.Collections.Generic.List[object]]::new()
        foreach ($table in $deploymentContract.protectedTables) {
            $entityMetadata = Invoke-DeploymentRequest -Method GET -Path "EntityDefinitions(LogicalName='$table')?`$select=PrimaryIdAttribute"
            if ($entityMetadata.PrimaryIdAttribute -cne "$($table)id") { throw 'Guard primary-ID normalization differs from live table metadata.' }
            $filters = @(Get-DeploymentRows -Path "sdkmessagefilters?`$select=sdkmessagefilterid,_sdkmessageid_value,iscustomprocessingstepallowed&`$filter=primaryobjecttypecode eq '$table'")
            $supported = @()
            foreach ($filter in $filters) {
                $message = @($messages | Where-Object { [string]$_.sdkmessageid -ieq [string]$filter._sdkmessageid_value })
                if ($message.Count -eq 1 -and $message[0].name -cin $deploymentContract.guardMessages -and $filter.iscustomprocessingstepallowed) {
                    $supported += [string]$message[0].name
                    $stepName = "os_sr_cact.guard.$table.$($message[0].name)"
                    $body = [ordered]@{
                        sdkmessageprocessingstepid = [Guid]::NewGuid().ToString()
                        name = $stepName; stage = 10; mode = 0; rank = 1; supporteddeployment = 0
                        description = 'Reject direct Candidate Core mutations; permit only exact validated caller-context API intent.'
                        "$messageNav@odata.bind" = "/sdkmessages($($message[0].sdkmessageid))"
                        "$filterNav@odata.bind" = "/sdkmessagefilters($($filter.sdkmessagefilterid))"
                        "$handlerNav@odata.bind" = "/plugintypes($guardId)"
                    }
                    $writes.Add((New-RegistrationWrite 'sdkmessageprocessingsteps' 'sdkmessageprocessingstepid' 92 $body))
                }
            }
            foreach ($required in @('Create', 'Update', 'Delete')) {
                if ($required -cnotin $supported) { throw "Required direct-write guard hook unavailable: $table/$required" }
            }
            $guardCoverage.Add(@{ Table = $table; Messages = $supported })
        }
        foreach ($messageName in @('Associate', 'Disassociate')) {
            $message = @($messages | Where-Object name -CEQ $messageName)
            if ($message.Count -ne 1) { throw 'Association guard message missing/ambiguous.' }
            $body = [ordered]@{
                sdkmessageprocessingstepid = [Guid]::NewGuid().ToString()
                name = "os_sr_cact.guard.relationships.$messageName"; stage = 10; mode = 0; rank = 1; supporteddeployment = 0
                description = 'Protect project lookup associations only; unrelated tables/relationships are no-op.'
                "$messageNav@odata.bind" = "/sdkmessages($($message[0].sdkmessageid))"
                "$handlerNav@odata.bind" = "/plugintypes($guardId)"
            }
            $writes.Add((New-RegistrationWrite 'sdkmessageprocessingsteps' 'sdkmessageprocessingstepid' 92 $body))
        }
        $guardCoverage.Add(@{ Table = 'ProjectRelationshipsOnly'; Messages = @('Associate', 'Disassociate') })
        $apiHandlerNav = Get-RegistrationNavigation 'customapi' 'plugintypeid' 'plugintype'
        $apiComponentMetadata = Invoke-DeploymentRequest -Method GET -Path "EntityDefinitions(LogicalName='customapi')?`$select=ObjectTypeCode"
        $writes.Add((New-RegistrationWrite 'customapis' 'customapiid' ([int]$apiComponentMetadata.ObjectTypeCode) ([ordered]@{
            customapiid = $apiId; uniquename = 'os_sr_cact'; name = 'Apply Candidate Action'; displayname = 'Apply Candidate Action'
            description = 'Server-enforced Candidate Core action with durable replay evidence.'
            isfunction = $false; isprivate = $true; bindingtype = 0; allowedcustomprocessingsteptype = 0
            workflowsdkstepenabled = $false; executeprivilegename = 'prvWriteos_sr_cand'
            "$apiHandlerNav@odata.bind" = "/plugintypes($mainId)"
        })))
        foreach ($kind in @('inputs', 'outputs')) {
            $table = if ($kind -ceq 'inputs') { 'customapirequestparameter' } else { 'customapiresponseproperty' }
            $set = if ($kind -ceq 'inputs') { 'customapirequestparameters' } else { 'customapiresponseproperties' }
            $componentMetadata = Invoke-DeploymentRequest -Method GET -Path "EntityDefinitions(LogicalName='$table')?`$select=ObjectTypeCode"
            $componentType = [int]$componentMetadata.ObjectTypeCode
            $nav = Get-RegistrationNavigation $table 'customapiid' 'customapi'
            foreach ($parameter in $deploymentContract.$kind) {
                $body = [ordered]@{
                    "$($table)id" = [Guid]::NewGuid().ToString(); uniquename = $parameter.name
                    name = "os_sr_cact.$($parameter.name)"; displayname = $parameter.name
                    type = [int]$parameter.type; "$nav@odata.bind" = "/customapis($apiId)"
                }
                if ($kind -ceq 'inputs') { $body.isoptional = [bool]$parameter.optional }
                $writes.Add((New-RegistrationWrite $set "$($table)id" $componentType $body))
            }
        }
        $script:deploymentPlan = [ordered]@{ CoreManifestSha256 = $storage.CoreManifestSha256
            ReceiptPlanSha256 = $storage.PlanSha256; ContractSha256 = $contractHash; AssemblySha256 = $assemblyHash
            Writes = $writes.ToArray(); GuardCoverage = $guardCoverage.ToArray()
            AutomaticRetries = 0; BusinessDataWrites = 0; APIInvocations = 0 }
        $stream = [IO.File]::Open($DeploymentPlanPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try {
            $bytes = [Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $script:deploymentPlan -Depth 80))
            $stream.Write($bytes, 0, $bytes.Length); $stream.Flush($true)
        } finally { $stream.Dispose() }
    } else {
        $actualPlanHash = (Get-FileHash $DeploymentPlanPath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($ExpectedDeploymentPlanSha256 -cne $actualPlanHash) { throw 'Deployment plan hash guard failed.' }
        $script:deploymentPlan = Get-Content -Raw $DeploymentPlanPath | ConvertFrom-Json
        if ($deploymentPlan.AssemblySha256 -cne $assemblyHash -or $deploymentPlan.ContractSha256 -cne $contractHash -or
            $deploymentPlan.CoreManifestSha256 -cne $storage.CoreManifestSha256 -or $deploymentPlan.ReceiptPlanSha256 -cne $storage.PlanSha256) {
            throw 'Contract, storage plan, or assembly changed since precomputed deployment.'
        }
        if ($DeploymentMode -ceq 'Apply') {
            if ($inventory.Assemblies.Count -or $inventory.Types.Count -or $inventory.APIs.Count -or $inventory.Steps.Count -or -not $DispatchEvidencePath) {
                throw 'Existing registration or missing consumption evidence path; no create resend.'
            }
            $script:deploymentJournal = [ordered]@{ DeploymentPlanSha256 = $actualPlanHash
                Writes = @($deploymentPlan.Writes | ForEach-Object {
                    [ordered]@{ Path = $_.Path; IdReferenceSha256 = Get-Sha256 -Bytes ([Text.Encoding]::UTF8.GetBytes($_.Id))
                        PayloadSha256 = $_.PayloadSha256; State = 'PLANNED'; HttpStatus = $null }
                }); AutomaticRetries = 0 }
            $stream = [IO.File]::Open($DispatchEvidencePath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
            $stream.Dispose()
            Save-DeploymentJournal
            foreach ($write in $deploymentPlan.Writes) {
                try { $null = Invoke-DeploymentRequest -Method POST -Path $write.Path -Body $write.Body }
                catch {
                    $original = $_
                    try { Assert-RegistrationReadback -Write $write }
                    catch { Write-Warning 'One failed/uncertain registration GET reconciliation did not prove exact state.' }
                    throw $original
                }
                Assert-RegistrationReadback -Write $write
                $script:deploymentJournal.Writes[$script:deploymentIndex - 1].State = 'GET_RECONCILED'
                Save-DeploymentJournal
            }
        } else {
            foreach ($write in $deploymentPlan.Writes) { Assert-RegistrationReadback -Write $write }
        }
        Assert-RegistrationMembership
        Assert-RegistrationInventoryExact
    }
    $paths = @($deploymentPlan.Writes | ForEach-Object { [pscustomobject]@{ Path = $_.Path } } |
        Group-Object Path | ForEach-Object { @{ Path = $_.Name; Maximum = $_.Count } })
    [ordered]@{
        Result = if ($DeploymentMode -ceq 'Preflight') { 'CANDIDATE_API_DEPLOYMENT_PLAN_READY' } elseif ($storage.OrganizationAuditing) {
            'CANDIDATE_CORE_API_DEPLOYED'
        } else { 'CANDIDATE_CORE_API_DEPLOYED_AUDIT_ACTIVATION_PENDING' }
        DeploymentPlanSha256 = (Get-FileHash $DeploymentPlanPath -Algorithm SHA256).Hash.ToLowerInvariant()
        AssemblySha256 = $assemblyHash; ContractSha256 = $contractHash
        PlannedCounts = $paths; GuardCoverage = $deploymentPlan.GuardCoverage
        GET = $script:deploymentCounts.GET; StorageGateGET = $deploymentStorageGets; POST = $script:deploymentCounts.POST
        APIInvocations = 0; BusinessDataWrites = 0; AppWrites = 0; PublishXml = 0; AutomaticRetries = 0
    } | ConvertTo-Json -Depth 20
} catch {
    [ordered]@{ Result = if ($script:deploymentCounts.POST) { 'PARTIAL_API_METADATA_STATE' } else { 'PRE_DEPLOYMENT_GATE_BLOCKED' }
        Error = Get-SanitizedFailureMessage -Message $_.Exception.Message
        GET = $script:deploymentCounts.GET; StorageGateGET = $deploymentStorageGets; POST = $script:deploymentCounts.POST
        AutomaticRetries = 0; BusinessDataWrites = 0 } | ConvertTo-Json
    throw 'Candidate operation deployment stopped; no automatic retry.'
} finally {
    $script:AccessToken = $null
    [Environment]::SetEnvironmentVariable('BSO_RS_EXPECTED_USER_ID', $null, 'Process')
}
