#requires -Version 7.4
[CmdletBinding()]
param(
    [ValidateSet('PlanOnly', 'Apply')][string]$Mode = 'PlanOnly',
    [Parameter(Mandatory)][string]$EnvironmentName,
    [Parameter(Mandatory)][string]$OrganizationUrl,
    [Parameter(Mandatory)][string]$ExpectedEnvironmentId,
    [Parameter(Mandatory)][string]$ExpectedOrganizationId,
    [string]$EvidencePath
)

$ErrorActionPreference = 'Stop'
$solutionUniqueName = 'os_sr_bso_rs_support'
$apiUniqueName = 'os_sr_cact'
$apiExecutionPrivilege = 'prvReados_sr_cand'
$roleName = 'BSO-RS Support - BSO'
$expectedCurrentApiPrivilege = 'prvWriteos_sr_cand'
$expectedRoleWritePrivileges = @(
    'prvCreateos_sr_cand',
    'prvWriteos_sr_cand',
    'prvCreateos_sr_call',
    'prvCreateos_sr_csh',
    'prvCreateos_sr_intv',
    'prvWriteos_sr_intv'
)
$forbiddenBusinessPrivileges = @(
    'prvCreateos_sr_cand', 'prvWriteos_sr_cand',
    'prvCreateos_sr_call', 'prvWriteos_sr_call',
    'prvCreateos_sr_csh', 'prvWriteos_sr_csh',
    'prvCreateos_sr_intv', 'prvWriteos_sr_intv'
)

if ($EnvironmentName -cne 'VN LMV IT' -or
    $OrganizationUrl.TrimEnd('/') -cne 'https://org14938ec2.crm4.dynamics.com' -or
    $ExpectedEnvironmentId -notmatch '^[0-9a-fA-F-]{36}$' -or
    $ExpectedOrganizationId -notmatch '^[0-9a-fA-F-]{36}$') {
    throw 'Only the explicitly designated VN LMV IT target is permitted.'
}
if ($Mode -ceq 'Apply' -and (-not $EvidencePath -or (Test-Path -LiteralPath $EvidencePath))) {
    throw 'Apply requires a new, empty evidence path; existing evidence is never overwritten.'
}

$helperPath = Join-Path $PSScriptRoot 'Provision-BsoRsCandidateChildTables.ps1'
$tokens = $null
$parseErrors = $null
$helperAst = [System.Management.Automation.Language.Parser]::ParseFile(
    $helperPath, [ref]$tokens, [ref]$parseErrors
)
if ($parseErrors.Count) { throw 'Existing PAC identity helper has parser errors.' }
foreach ($functionName in @('Assert-PacIdentity', 'Get-ValidatedToken')) {
    $definitions = @($helperAst.EndBlock.Statements | Where-Object {
        $_ -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $_.Name -ceq $functionName
    })
    if ($definitions.Count -ne 1) { throw "Required identity helper is missing or ambiguous: $functionName" }
    . ([scriptblock]::Create($definitions[0].Extent.Text))
}

$script:ApiRoot = $OrganizationUrl.TrimEnd('/') + '/api/data/v9.2/'
$script:AccessToken = $null
$script:WriteIndex = 0
$script:Journal = $null

function Get-Phase5ARows {
    param([Parameter(Mandatory)][string]$Path)
    $uri = [Uri]($script:ApiRoot + $Path)
    if ($uri.Scheme -cne 'https' -or $uri.Authority -ine ([Uri]$OrganizationUrl).Authority -or
        $uri.AbsolutePath -notmatch '^/api/data/v9\.2/' -or $uri.UserInfo -or $uri.Fragment) {
        throw 'Read target is outside the verified VN LMV IT organization.'
    }
    $response = Invoke-RestMethod -Uri $uri.AbsoluteUri -Method GET -Headers @{
        Authorization = 'Bearer ' + $script:AccessToken
        Accept = 'application/json'
        'OData-Version' = '4.0'
        'OData-MaxVersion' = '4.0'
        Consistency = 'Strong'
    } -MaximumRetryCount 0 -MaximumRedirection 0 -TimeoutSec 120 -ErrorAction Stop
    $collection = $response.PSObject.Properties['value']
    if ($null -ne $collection) { return @($collection.Value) }
    @($response)
}

function Get-Phase5ARolePrivileges {
    param([Parameter(Mandatory)][string]$RoleId)
    $uri = [Uri]($script:ApiRoot + "RetrieveRolePrivilegesRole(RoleId=$RoleId)")
    if ($uri.Scheme -cne 'https' -or $uri.Authority -ine ([Uri]$OrganizationUrl).Authority) {
        throw 'Role privilege read target is outside the verified VN LMV IT organization.'
    }
    $response = Invoke-RestMethod -Uri $uri.AbsoluteUri -Method GET -Headers @{
        Authorization = 'Bearer ' + $script:AccessToken
        Accept = 'application/json'
        'OData-Version' = '4.0'
        'OData-MaxVersion' = '4.0'
    } -MaximumRetryCount 0 -MaximumRedirection 0 -TimeoutSec 120 -ErrorAction Stop
    @($response.RolePrivileges)
}

function Save-Phase5AJournal {
    $json = ConvertTo-Json -InputObject $script:Journal -Depth 10
    $bytes = [Text.Encoding]::UTF8.GetBytes($json)
    $fileMode = if (Test-Path -LiteralPath $EvidencePath) {
        [IO.FileMode]::Open
    } else {
        [IO.FileMode]::CreateNew
    }
    $stream = [IO.File]::Open($EvidencePath, $fileMode, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
        $stream.SetLength(0)
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush($true)
    }
    finally { $stream.Dispose() }
}

function Invoke-Phase5AWrite {
    param(
        [Parameter(Mandatory)][ValidateSet('PATCH', 'POST')][string]$Method,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Body,
        [Parameter(Mandatory)][string]$Operation
    )
    $allowed = if ($Method -ceq 'PATCH') {
        $Path -ceq "customapis($($script:ApiId))" -and
        $Operation -ceq 'SET_CANDIDATE_CORE_EXECUTE_PRIVILEGE' -and
        $Body.Count -eq 1 -and $Body.executeprivilegename -ceq $apiExecutionPrivilege
    }
    else {
        $Path -ceq "roles($($script:RoleId))/Microsoft.Dynamics.CRM.RemovePrivilegeRole" -and
        $Operation -match '^REMOVE_PROTECTED_PRIVILEGE:' -and
        $Body.Count -eq 1 -and
        $Body.Privilege.'@odata.type' -ceq 'Microsoft.Dynamics.CRM.privilege' -and
        $Body.Privilege.privilegeid -match '^[0-9a-fA-F-]{36}$' -and
        $Body.Privilege.privilegeid -in $script:AllowedPrivilegeIds
    }
    if (-not $allowed) { throw 'Write request is outside the fixed Phase 5A API/role allowlist.' }
    if ($script:WriteIndex -ge $script:Journal.Writes.Count) {
        throw 'Write has no unconsumed one-shot journal entry.'
    }

    $entry = $script:Journal.Writes[$script:WriteIndex]
    $payload = ConvertTo-Json -InputObject $Body -Depth 8 -Compress
    $payloadHash = [Convert]::ToHexString(
        [Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($payload))
    ).ToLowerInvariant()
    if ($entry.Method -cne $Method -or $entry.Operation -cne $Operation -or
        $entry.State -cne 'PLANNED' -or $entry.PayloadSha256 -cne $payloadHash) {
        throw 'Write differs from the exact planned Phase 5A journal entry.'
    }
    $entry.State = 'DISPATCH_RESERVED'
    Save-Phase5AJournal
    $script:WriteIndex++

    $uri = [Uri]($script:ApiRoot + $Path)
    if ($uri.Scheme -cne 'https' -or $uri.Authority -ine ([Uri]$OrganizationUrl).Authority -or
        $uri.AbsolutePath -notmatch '^/api/data/v9\.2/' -or $uri.UserInfo -or $uri.Fragment) {
        throw 'Write target is outside the verified VN LMV IT organization.'
    }
    $headers = @{
        Authorization = 'Bearer ' + $script:AccessToken
        Accept = 'application/json'
        'OData-Version' = '4.0'
        'OData-MaxVersion' = '4.0'
    }
    if ($Method -ceq 'PATCH') { $headers['MSCRM.SolutionUniqueName'] = $solutionUniqueName }
    try {
        $null = Invoke-RestMethod -Uri $uri.AbsoluteUri -Method $Method -Headers $headers `
            -ContentType 'application/json; charset=utf-8' -Body $payload `
            -MaximumRetryCount 0 -MaximumRedirection 0 -TimeoutSec 120 `
            -SkipHttpErrorCheck -StatusCodeVariable statusCode -ErrorAction Stop
    }
    catch {
        $entry.State = 'UNCERTAIN_WRITE_OUTCOME'
        Save-Phase5AJournal
        throw "$Operation transport outcome is uncertain; no write retry is permitted."
    }
    if ([int]$statusCode -lt 200 -or [int]$statusCode -ge 300) {
        $entry.State = 'REJECTED'
        $entry.HttpStatus = [int]$statusCode
        Save-Phase5AJournal
        throw "$Operation was rejected with HTTP $statusCode; no write retry is permitted."
    }
    $entry.State = 'ACKNOWLEDGED'
    $entry.HttpStatus = [int]$statusCode
    Save-Phase5AJournal
}

try {
    Assert-PacIdentity
    Get-ValidatedToken
    $apiRows = @(Get-Phase5ARows "customapis?%24select=customapiid,uniquename,executeprivilegename,isprivate,isfunction&%24filter=uniquename%20eq%20%27$apiUniqueName%27")
    $packageRows = @(Get-Phase5ARows "pluginpackages?%24select=pluginpackageid,uniquename,version&%24filter=uniquename%20eq%20%27os_sr_cact_pkg%27")
    $roleRows = @(Get-Phase5ARows "roles?%24select=roleid,name&%24filter=name%20eq%20%27BSO-RS%20Support%20-%20BSO%27&%24expand=systemuserroles_association(%24select=systemuserid),teamroles_association(%24select=teamid)")
    $solutionRows = @(Get-Phase5ARows "solutions?%24select=solutionid,uniquename&%24filter=uniquename%20eq%20%27$solutionUniqueName%27")
    if ($apiRows.Count -ne 1 -or $packageRows.Count -ne 1 -or $roleRows.Count -ne 1 -or
        $solutionRows.Count -ne 1 -or $apiRows[0].isprivate -ne $true -or
        $apiRows[0].isfunction -ne $false -or
        $packageRows[0].uniquename -cne 'os_sr_cact_pkg' -or
        [string]$packageRows[0].version -cne '1.0.0' -or
        $solutionRows[0].uniquename -cne $solutionUniqueName) {
        throw 'API, existing package, BSO role, or solution identity is missing or ambiguous.'
    }
    $script:ApiId = [string]$apiRows[0].customapiid
    $script:RoleId = [string]$roleRows[0].roleid
    if (@($roleRows[0].systemuserroles_association).Count -ne 0 -or
        @($roleRows[0].teamroles_association).Count -ne 0) {
        throw 'BSO role is assigned to a user or team; no security change is permitted.'
    }
    $solutionComponents = @(Get-Phase5ARows "solutioncomponents?%24select=componenttype,objectid,_solutionid_value&%24filter=objectid%20eq%20$($script:ApiId)%20and%20_solutionid_value%20eq%20$($solutionRows[0].solutionid)")
    if ($solutionComponents.Count -lt 1) { throw 'Candidate Core API is not in the existing solution.' }

    $rolePrivileges = @(Get-Phase5ARolePrivileges -RoleId $script:RoleId)
    $script:AllowedPrivilegeIds = @($rolePrivileges | Where-Object {
        $_.PrivilegeName -in $forbiddenBusinessPrivileges
    } | ForEach-Object { [string]$_.PrivilegeId })
    $presentForbidden = @($rolePrivileges | Where-Object {
        $_.PrivilegeName -in $forbiddenBusinessPrivileges
    } | ForEach-Object { [string]$_.PrivilegeName } | Sort-Object)
    $expectedForbidden = @($expectedRoleWritePrivileges | Sort-Object)
    if ([string]::Join('|', $presentForbidden) -cne [string]::Join('|', $expectedForbidden) -or
        @($rolePrivileges | Where-Object PrivilegeName -CEQ $apiExecutionPrivilege).Count -ne 1) {
        throw 'Current BSO role privilege set differs from the reviewed exact removal/execute baseline.'
    }
    $script:ExpectedRolePrivilegeNames = @($rolePrivileges | ForEach-Object {
        [string]$_.PrivilegeName
    } | Sort-Object)
    if ($apiRows[0].executeprivilegename -cne $expectedCurrentApiPrivilege -and
        $apiRows[0].executeprivilegename -cne $apiExecutionPrivilege) {
        throw 'Custom API execution privilege differs from the reviewed current/target values.'
    }
    if ($Mode -ceq 'PlanOnly') {
        [ordered]@{
            Result = 'PHASE_5A_SECURITY_BOUNDARY_PLAN_ONLY'
            Environment = $EnvironmentName
            ApiUniqueName = $apiUniqueName
            CurrentExecutePrivilege = [string]$apiRows[0].executeprivilegename
            TargetExecutePrivilege = $apiExecutionPrivilege
            RoleName = $roleName
            ProtectedCreateWritePrivilegesToRemove = $presentForbidden
            RoleAssignments = 0
            Writes = 0
            AutomaticRetries = 0
        } | ConvertTo-Json -Depth 6
        return
    }

    $script:Journal = [ordered]@{
        Authorization = 'phase5a-vn-lmv-it-candidate-core-role-boundary'
        EnvironmentName = $EnvironmentName
        ApiUniqueName = $apiUniqueName
        RoleName = $roleName
        TargetExecutePrivilege = $apiExecutionPrivilege
        Writes = @()
        AutomaticRetries = 0
    }
    $pending = @()
    if ($apiRows[0].executeprivilegename -cne $apiExecutionPrivilege) {
        $apiBody = [ordered]@{ executeprivilegename = $apiExecutionPrivilege }
        $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData(
            [Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $apiBody -Compress))
        )).ToLowerInvariant()
        $pending += [ordered]@{
            Method = 'PATCH'; Operation = 'SET_CANDIDATE_CORE_EXECUTE_PRIVILEGE'
            State = 'PLANNED'; PayloadSha256 = $hash
        }
    }
    foreach ($privilege in $rolePrivileges | Where-Object {
        $_.PrivilegeName -in $expectedRoleWritePrivileges
    } | Sort-Object PrivilegeName) {
        $body = [ordered]@{
            Privilege = [ordered]@{
                '@odata.type' = 'Microsoft.Dynamics.CRM.privilege'
                privilegeid = [string]$privilege.PrivilegeId
            }
        }
        $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData(
            [Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $body -Depth 8 -Compress))
        )).ToLowerInvariant()
        $pending += [ordered]@{
            Method = 'POST'; Operation = "REMOVE_PROTECTED_PRIVILEGE:$($privilege.PrivilegeName)"
            State = 'PLANNED'; PayloadSha256 = $hash
        }
    }
    $script:Journal.Writes = @($pending)

    if ($Mode -ceq 'Apply') {
        $stream = [IO.File]::Open($EvidencePath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $stream.Dispose()
        Save-Phase5AJournal
    }
    if ($apiRows[0].executeprivilegename -cne $apiExecutionPrivilege) {
        Invoke-Phase5AWrite -Method PATCH -Path "customapis($($script:ApiId))" `
            -Body ([ordered]@{ executeprivilegename = $apiExecutionPrivilege }) `
            -Operation 'SET_CANDIDATE_CORE_EXECUTE_PRIVILEGE'
        $apiReadback = @(Get-Phase5ARows "customapis($($script:ApiId))?%24select=customapiid,uniquename,executeprivilegename")
        if ($apiReadback.Count -ne 1 -or $apiReadback[0].uniquename -cne $apiUniqueName -or
            $apiReadback[0].executeprivilegename -cne $apiExecutionPrivilege) {
            throw 'Candidate Core ExecutePrivilegeName did not reconcile; stop without retry.'
        }
    }
    foreach ($privilege in $rolePrivileges | Where-Object {
        $_.PrivilegeName -in $expectedRoleWritePrivileges
    } | Sort-Object PrivilegeName) {
        $operation = "REMOVE_PROTECTED_PRIVILEGE:$($privilege.PrivilegeName)"
        $path = "roles($($script:RoleId))/Microsoft.Dynamics.CRM.RemovePrivilegeRole"
        $body = [ordered]@{
            Privilege = [ordered]@{
                '@odata.type' = 'Microsoft.Dynamics.CRM.privilege'
                privilegeid = [string]$privilege.PrivilegeId
            }
        }
        Invoke-Phase5AWrite -Method POST -Path $path -Body $body -Operation $operation
        $remaining = @(Get-Phase5ARolePrivileges -RoleId $script:RoleId)
        if (@($remaining | Where-Object PrivilegeName -CEQ $privilege.PrivilegeName).Count -ne 0) {
            throw "$($privilege.PrivilegeName) removal did not reconcile; stop without retry."
        }
    }

    $finalApi = @(Get-Phase5ARows "customapis($($script:ApiId))?%24select=customapiid,uniquename,executeprivilegename")
    $finalRole = @(Get-Phase5ARows "roles($($script:RoleId))?%24select=roleid,name&%24expand=systemuserroles_association(%24select=systemuserid),teamroles_association(%24select=teamid)")
    $finalPrivileges = @(Get-Phase5ARolePrivileges -RoleId $script:RoleId)
    $finalNames = @($finalPrivileges | ForEach-Object { [string]$_.PrivilegeName } | Sort-Object)
    $expectedRemaining = @($script:ExpectedRolePrivilegeNames | Where-Object {
        $_ -notin $expectedRoleWritePrivileges
    } | Sort-Object)
    $remainingForbidden = @($finalPrivileges | Where-Object {
        $_.PrivilegeName -in $forbiddenBusinessPrivileges
    })
    if ($finalApi.Count -ne 1 -or $finalApi[0].executeprivilegename -cne $apiExecutionPrivilege -or
        $finalRole.Count -ne 1 -or @($finalRole[0].systemuserroles_association).Count -ne 0 -or
        @($finalRole[0].teamroles_association).Count -ne 0 -or $remainingForbidden.Count -ne 0 -or
        [string]::Join('|', $finalNames) -cne [string]::Join('|', $expectedRemaining)) {
        throw 'Final API privilege or exact BSO role privilege reconciliation failed.'
    }
    [ordered]@{
        Result = 'PHASE_5A_SECURITY_BOUNDARY_RECONCILED_UNASSIGNED'
        ApiUniqueName = $apiUniqueName
        ExecutePrivilege = $apiExecutionPrivilege
        RoleName = $roleName
        RemovedProtectedCreateWritePrivileges = $expectedForbidden
        RemainingDirectProtectedCreateWritePrivileges = 0
        RoleAssignments = 0
        Writes = $script:WriteIndex
        AutomaticRetries = 0
        EvidencePath = if ($Mode -ceq 'Apply') { $EvidencePath } else { $null }
    } | ConvertTo-Json -Depth 6
}
finally {
    $script:AccessToken = $null
}
