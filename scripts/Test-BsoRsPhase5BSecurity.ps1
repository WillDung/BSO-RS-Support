#requires -Version 7.4
[CmdletBinding()]
param(
    [ValidateSet('Inspect', 'GrantAppAccess')][string]$Mode = 'Inspect',
    [Parameter(Mandatory)][string]$TargetUser,
    [Parameter(Mandatory)][string]$ExpectedEnvironmentId,
    [Parameter(Mandatory)][string]$ExpectedOrganizationId,
    [Parameter(Mandatory)][string]$EvidencePath
)

$ErrorActionPreference = 'Stop'
$EnvironmentName = 'VN LMV IT'
$OrganizationUrl = 'https://org14938ec2.crm4.dynamics.com'
$roleName = 'BSO-RS Support - BSO'
$appName = 'srapp'
if (-not [IO.Path]::IsPathFullyQualified($EvidencePath) -or
    (Test-Path -LiteralPath $EvidencePath) -or
    -not (Test-Path -LiteralPath (Split-Path -Parent $EvidencePath) -PathType Container)) {
    throw 'A new absolute local evidence path with an existing parent is required.'
}
$tokens = $null
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $PSScriptRoot 'Provision-BsoRsCandidateChildTables.ps1'), [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'Identity helper parser errors.' }
foreach ($name in @('Assert-PacIdentity', 'Get-ValidatedToken')) {
    $definition = @($ast.EndBlock.Statements | Where-Object {
        $_ -is [Management.Automation.Language.FunctionDefinitionAst] -and $_.Name -ceq $name
    })
    if ($definition.Count -ne 1) { throw 'Identity helper is missing or ambiguous.' }
    . ([scriptblock]::Create($definition[0].Extent.Text))
}
Assert-PacIdentity
if ($script:PacUserEmail -ine $TargetUser) { throw 'PAC caller must be the approved target user.' }
Get-ValidatedToken
$root = "$OrganizationUrl/api/data/v9.2/"
$headers = @{
    Authorization = 'Bearer ' + $script:AccessToken
    Accept = 'application/json'
    'OData-Version' = '4.0'
    'OData-MaxVersion' = '4.0'
    Consistency = 'Strong'
}
function Read-Phase5B {
    param([string]$Path)
    if ($Path -match '^[a-z]+:') { throw 'Only relative read paths are accepted.' }
    Invoke-RestMethod -Uri ($root + $Path) -Headers $headers -Method Get `
        -MaximumRetryCount 0 -MaximumRedirection 0 -TimeoutSec 120
}
function Read-Phase5BRows {
    param([string]$Path)
    $rows = [Collections.Generic.List[object]]::new()
    do {
        $result = Read-Phase5B $Path
        foreach ($row in $result.value) { $rows.Add($row) }
        $next = $result.PSObject.Properties['@odata.nextLink']
        $Path = if ($next -and $next.Value) {
            if (-not ([string]$next.Value).StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
                throw 'Read pagination escaped the approved organization.'
            }
            ([string]$next.Value).Substring($root.Length)
        } else { $null }
    } while ($Path)
    $rows.ToArray()
}
$who = Read-Phase5B 'WhoAmI'
if ($who.UserId -ine $script:ExpectedUserId -or $who.OrganizationId -ine $ExpectedOrganizationId) {
    throw 'PAC and WhoAmI disagree.'
}
$escapedUser = [Uri]::EscapeDataString($TargetUser.Replace("'", "''"))
$users = @(Read-Phase5BRows "systemusers?%24select=systemuserid,domainname,isdisabled,_businessunitid_value&%24filter=domainname%20eq%20'$escapedUser'")
$roles = @(Read-Phase5BRows "roles?%24select=roleid,name,_businessunitid_value&%24filter=name%20eq%20'BSO-RS%20Support%20-%20BSO'")
$apps = @(Read-Phase5BRows "appmodules?%24select=appmoduleid,uniquename&%24filter=uniquename%20eq%20'srapp'")
if ($users.Count -ne 1 -or $roles.Count -ne 1 -or $apps.Count -ne 1 -or
    $users[0].isdisabled -or $users[0].systemuserid -ine $who.UserId -or
    $users[0].domainname -ine $TargetUser -or $roles[0].name -cne $roleName -or
    $roles[0]._businessunitid_value -ine $users[0]._businessunitid_value -or
    $apps[0].uniquename -cne $appName) { throw 'User, role, app, or Business Unit resolution is ambiguous.' }
$userId = [string]$users[0].systemuserid
$roleId = [string]$roles[0].roleid
$appId = [string]$apps[0].appmoduleid
$direct = @(Read-Phase5BRows "systemusers($userId)/systemuserroles_association?%24select=roleid,name")
$teams = @(Read-Phase5BRows "systemusers($userId)/teammembership_association?%24select=teamid,teamtype,isdefault")
$teamRoles = @(
    foreach ($team in $teams) {
        $assigned = @(Read-Phase5BRows "teams($($team.teamid))/teamroles_association?%24select=name,roleid")
        [ordered]@{ TeamCategory = if ($team.isdefault) { 'Default owner team' } else { "Team type $($team.teamtype)" }; Roles = @($assigned | ForEach-Object name) }
    }
)
$appRoles = @(Read-Phase5BRows "appmodules($appId)/appmoduleroles_association?%24select=roleid,name")
$journal = [ordered]@{
    Environment = $EnvironmentName
    TargetUser = $TargetUser
    PacWhoAmIAgreement = $true
    DirectRoles = @($direct | ForEach-Object name)
    TeamRoles = $teamRoles
    BsoDirectAssignment = @($direct | Where-Object roleid -IEQ $roleId).Count -eq 1
    AppRolesBefore = @($appRoles | ForEach-Object name)
    AppAssociationWrites = 0
    AutomaticRetries = 0
    Result = 'INSPECTED'
}
function Save-Phase5B {
    $journal | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $EvidencePath -Encoding utf8
}
if ($Mode -ceq 'GrantAppAccess' -and @($appRoles | Where-Object roleid -IEQ $roleId).Count -eq 0) {
    if (-not $journal.BsoDirectAssignment) { throw 'The approved direct BSO assignment must be verified before app access.' }
    $journal.Result = 'APP_ASSOCIATION_DISPATCH_RESERVED_DO_NOT_RETRY'
    $journal.AppAssociationWrites = 1
    Save-Phase5B
    $body = @{ '@odata.id' = $root + "roles($roleId)" } | ConvertTo-Json -Compress
    Invoke-RestMethod -Uri ($root + "appmodules($appId)/appmoduleroles_association/`$ref") `
        -Headers $headers -Method Post -Body $body -ContentType 'application/json' `
        -MaximumRetryCount 0 -MaximumRedirection 0 -TimeoutSec 120 | Out-Null
}
$afterAppRoles = @(Read-Phase5BRows "appmodules($appId)/appmoduleroles_association?%24select=roleid,name")
if ($Mode -ceq 'GrantAppAccess' -and @($afterAppRoles | Where-Object roleid -IEQ $roleId).Count -ne 1) {
    throw 'App association outcome is uncertain; reconcile without repeating the write.'
}
foreach ($previous in $appRoles) {
    if ($previous.roleid -notin @($afterAppRoles.roleid)) { throw 'A pre-existing app role is missing.' }
}
$journal.AppRolesAfter = @($afterAppRoles | ForEach-Object name)
$effectiveNames = @($journal.DirectRoles) + @($teamRoles | ForEach-Object { $_.Roles })
$journal.Result = if (@($effectiveNames | Where-Object { $_ -in @('System Administrator', 'System Customizer') }).Count) {
    'BSO_SECURITY_ACCEPTANCE_BLOCKED_BY_PREEXISTING_ELEVATED_ACCESS'
} else {
    'ROLE_INVENTORY_ONLY_EFFECTIVE_PRIVILEGE_ACCEPTANCE_STILL_REQUIRED'
}
Save-Phase5B
$journal | ConvertTo-Json -Depth 10
