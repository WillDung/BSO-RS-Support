#requires -Version 7.4
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$OrganizationUrl,
    [Parameter(Mandatory)][string]$ExpectedEnvironmentId,
    [Parameter(Mandatory)][string]$ExpectedOrganizationId,
    [Parameter(Mandatory)][string]$BaselinePath,
    [switch]$Restore
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$expectedUrl = 'https://org14938ec2.crm4.dynamics.com'
$expectedEnvironment = '92e44afb-6c3a-eb1a-8154-4ed51e1e6e42'
$expectedOrganization = '0706072c-54ea-f011-872b-000d3ab60060'
$expectedNames = @(
    'os_sr_cact.guard.os_sr_cand.Create',
    'os_sr_cact.guard.os_sr_call.Create',
    'os_sr_cact.guard.os_sr_cand.Update',
    'os_sr_cact.guard.os_sr_csh.Create'
) | Sort-Object
$baselineExpectedNames = @($expectedNames + 'os_sr_cact.guard.os_sr_oprc.Create') | Sort-Object
$script:ApiRoot = $expectedUrl + '/api/data/v9.2/'
$script:AccessToken = $null
$script:RequestCounts = @{ GET = 0; PATCH = 0 }

if ($OrganizationUrl.TrimEnd('/') -cne $expectedUrl -or
    $ExpectedEnvironmentId -ine $expectedEnvironment -or
    $ExpectedOrganizationId -ine $expectedOrganization -or
    -not (Test-Path -LiteralPath $BaselinePath -PathType Leaf)) {
    throw 'DEV guard bypass target or private pre-disable baseline is not exact.'
}

$baseline = Get-Content -LiteralPath $BaselinePath -Raw | ConvertFrom-Json
if ($baseline.EnvironmentName -cne 'VN LMV IT' -or
    $baseline.EnvironmentId -ine $expectedEnvironment -or
    $baseline.OrganizationId -ine $expectedOrganization -or
    $baseline.TotalGuardSteps -ne 50 -or $baseline.PackageBackedGuardSteps -ne 50) {
    throw 'Private pre-disable baseline identity or 50/50 guard inventory is invalid.'
}
$baselineTargets = @($baseline.Targets | Sort-Object Name)
$expectedPairs = @{
    'os_sr_cact.guard.os_sr_cand.Create' = 'Create|os_sr_cand'
    'os_sr_cact.guard.os_sr_call.Create' = 'Create|os_sr_call'
    'os_sr_cact.guard.os_sr_cand.Update' = 'Update|os_sr_cand'
    'os_sr_cact.guard.os_sr_csh.Create' = 'Create|os_sr_csh'
    'os_sr_cact.guard.os_sr_oprc.Create' = 'Create|os_sr_oprc'
}
if ($baselineTargets.Count -ne $baselineExpectedNames.Count -or
    [string]::Join('|', @($baselineTargets | ForEach-Object { [string]$_.Name })) -cne
    [string]::Join('|', $baselineExpectedNames) -or
    @($baselineTargets | Where-Object {
        [int]$_.StateCode -ne 0 -or [int]$_.StatusCode -ne 1 -or
        $expectedPairs[[string]$_.Name] -cne "$($_.Message)|$($_.EntityFilter)" -or
        $_.Handler -cne 'os_sr_cact.ProtectCandidateCore' -or
        [int]$_.Stage -ne 10 -or [int]$_.Mode -ne 0 -or
        $_.ProtectedPropertiesSha256 -notmatch '^[0-9a-f]{64}$'
    }).Count -ne 0) {
    throw 'Private pre-disable step snapshot does not match the exact authorized registration set.'
}
$targetsToChange = @($baselineTargets | Where-Object { $_.Name -in $expectedNames })
if ($targetsToChange.Count -ne $expectedNames.Count) {
    throw 'The exact four DEV-required guard registrations were not found in the baseline.'
}

function Get-Sha256 {
    param([byte[]]$Bytes)
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes)).ToLowerInvariant()
}

function ConvertTo-CanonicalValue {
    param([object]$Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [guid]) { return $Value.ToString('D').ToLowerInvariant() }
    if ($Value -is [DateTime]) { return $Value.ToUniversalTime().ToString('O') }
    if ($Value -is [DateTimeOffset]) { return $Value.ToUniversalTime().ToString('O') }
    if ($Value -is [ValueType] -or $Value -is [string]) { return $Value }
    ConvertTo-Json -InputObject $Value -Depth 40 -Compress
}

function Get-CanonicalStepSnapshot {
    param([object]$Row)
    $attributes = [ordered]@{}
    $configuration = if ($null -eq $Row.configuration) { $null } else { [string]$Row.configuration }
    foreach ($property in @($Row.PSObject.Properties | Sort-Object Name)) {
        $name = [string]$property.Name
        if ($name.Contains('@') -or $name -in @(
            'sdkmessageprocessingstepid', '_eventhandler_value', 'eventhandler', 'configuration',
            'modifiedon', 'modifiedby', 'versionnumber'
        )) { continue }
        $attributes[$name] = ConvertTo-CanonicalValue -Value $property.Value
    }
    $attributes['configurationSha256'] = if ($null -eq $configuration) { $null } else {
        Get-Sha256 -Bytes ([Text.Encoding]::UTF8.GetBytes($configuration))
    }
    $canonical = [ordered]@{}
    foreach ($name in @($attributes.Keys | Sort-Object -CaseSensitive)) {
        $canonical[$name] = $attributes[$name]
    }
    Get-Sha256 -Bytes ([Text.Encoding]::UTF8.GetBytes(
        (ConvertTo-Json -InputObject $canonical -Depth 50 -Compress)
    ))
}

function Invoke-DataverseRequest {
    param(
        [Parameter(Mandatory)][ValidateSet('GET', 'PATCH')][string]$Method,
        [Parameter(Mandatory)][string]$Path,
        [object]$Body,
        [string]$ETag
    )
    $uri = [Uri]($script:ApiRoot + $Path)
    if ($uri.Scheme -cne 'https' -or $uri.Authority -ine ([Uri]$expectedUrl).Authority -or
        $uri.AbsolutePath -notmatch '^/api/data/v9\.2/sdkmessageprocessingsteps\([0-9a-fA-F-]{36}\)$' -or
        $uri.UserInfo -or $uri.Fragment) {
        throw 'DEV guard bypass request is outside the exact SDK registration endpoint.'
    }
    $headers = @{
        Authorization = "Bearer $script:AccessToken"
        Accept = 'application/json'
        'OData-Version' = '4.0'
        'OData-MaxVersion' = '4.0'
        Consistency = 'Strong'
    }
    if ($ETag) { $headers['If-Match'] = $ETag }
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
        $allowedState = if ($Restore) { 0 } else { 1 }
        $allowedStatus = if ($Restore) { 1 } else { 2 }
        if ($null -eq $Body -or @($Body.Keys).Count -ne 2 -or
            [int]$Body.statecode -ne $allowedState -or [int]$Body.statuscode -ne $allowedStatus) {
            throw 'DEV guard bypass PATCH must contain only the exact authorized statecode/statuscode pair.'
        }
        $arguments.Body = ConvertTo-Json -InputObject $Body -Compress
        $arguments.ContentType = 'application/json; charset=utf-8'
        $script:RequestCounts.PATCH++
    } else {
        $script:RequestCounts.GET++
    }
    try { Invoke-WebRequest @arguments }
    catch {
        if ($Method -ceq 'PATCH') {
            throw 'DEV guard bypass PATCH outcome is uncertain; stop and reconcile manually without retry.'
        }
        throw 'DEV guard bypass registration GET failed; no write/retry was attempted.'
    }
}

function Get-DataverseStep {
    param([string]$StepId)
    $response = Invoke-DataverseRequest -Method GET -Path "sdkmessageprocessingsteps($StepId)"
    if ([int]$response.StatusCode -lt 200 -or [int]$response.StatusCode -ge 300) {
        throw 'DEV guard bypass registration GET returned an unsuccessful status.'
    }
    $response.Content | ConvertFrom-Json
}

try {
$pacOutput = @(& pac org who --json 2>&1)
if ($LASTEXITCODE -ne 0) { throw 'PAC identity check failed; no sign-in or environment switch was attempted.' }
$pac = ($pacOutput -join "`n") | ConvertFrom-Json
if ([string]$pac.OrgUrl.TrimEnd('/') -cne $expectedUrl -or
    [string]$pac.EnvironmentId -ine $expectedEnvironment -or
    [string]$pac.OrgId -ine $expectedOrganization) {
    throw 'PAC environment identity does not match the approved VN LMV IT target.'
}
if (-not (Get-Module -ListAvailable -Name Az.Accounts)) {
    throw 'Existing Az.Accounts module is required; no login or module installation attempted.'
}
Import-Module Az.Accounts -ErrorAction Stop
$context = Get-AzContext -ErrorAction Stop
if ($null -eq $context -or $context.Account.Type -ne 'User' -or
    $context.Account.Id -ine [string]$pac.UserEmail) {
    throw 'Existing Az.Accounts identity does not match PAC; no login or context switch attempted.'
}
$access = Get-AzAccessToken -ResourceUrl $expectedUrl -AsSecureString -ErrorAction Stop
if ($access.Token -isnot [Security.SecureString]) {
    throw 'Az.Accounts did not return a secure Dataverse token.'
}
$script:AccessToken = ConvertFrom-SecureString -SecureString $access.Token -AsPlainText
$tokenParts = $script:AccessToken.Split('.')
if ($tokenParts.Count -ne 3) { throw 'Dataverse credential was not a JWT.' }
$payload = $tokenParts[1].Replace('-', '+').Replace('_', '/')
switch ($payload.Length % 4) { 2 { $payload += '==' } 3 { $payload += '=' } }
$claims = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload)) | ConvertFrom-Json
$audience = [Uri]([string]$claims.aud)
if ($claims.tid -ine $context.Tenant.Id -or $audience.Authority -ine ([Uri]$expectedUrl).Authority -or
    'user_impersonation' -notin @(([string]$claims.scp) -split '\s+') -or
    [DateTimeOffset]::FromUnixTimeSeconds([long]$claims.exp) -le [DateTimeOffset]::UtcNow) {
    throw 'Dataverse credential audience, tenant, delegated scope, or expiry is invalid.'
}

$whoResponse = Invoke-WebRequest -Uri ([Uri]($script:ApiRoot + 'WhoAmI')) -Method GET -Headers @{
    Authorization = "Bearer $script:AccessToken"
    Accept = 'application/json'
    'OData-Version' = '4.0'
    'OData-MaxVersion' = '4.0'
} -MaximumRetryCount 0 -MaximumRedirection 0 -TimeoutSec 120 -SkipHttpErrorCheck
if ([int]$whoResponse.StatusCode -lt 200 -or [int]$whoResponse.StatusCode -ge 300) {
    throw 'Dataverse WhoAmI did not succeed.'
}
$who = $whoResponse.Content | ConvertFrom-Json
if ([string]$who.UserId -ine [string]$pac.UserId -or
    [string]$who.OrganizationId -ine $expectedOrganization -or
    [string]$baseline.WhoAmIUserId -ine [string]$who.UserId) {
    throw 'Dataverse WhoAmI does not match the baseline and active PAC caller.'
}

$initialRows = foreach ($target in $targetsToChange) {
    $row = Get-DataverseStep -StepId ([string]$target.StepId)
    $stepName = [string]$row.name
    $handler = [string]$row._eventhandler_value
    $expectedState = if ($Restore) { 1 } else { 0 }
    $expectedStatus = if ($Restore) { 2 } else { 1 }
    if ($Restore) {
        $row.statecode = 0
        $row.statuscode = 1
    }
    if ($stepName -cne [string]$target.Name -or
        $handler -ine [string]$baseline.PackageGuardTypeId -or
        [int]$row.stage -ne 10 -or [int]$row.mode -ne 0 -or
        $row._impersonatinguserid_value -or
        (Get-CanonicalStepSnapshot -Row $row) -cne [string]$target.ProtectedPropertiesSha256) {
        throw "Pre-disable registration fingerprint or state changed: $stepName"
    }
    $live = Get-DataverseStep -StepId ([string]$target.StepId)
    if ([int]$live.statecode -ne $expectedState -or [int]$live.statuscode -ne $expectedStatus) {
        throw "Registration current state does not match the requested one-shot transition: $stepName"
    }
    [pscustomobject]@{ Baseline = $target; Row = $live }
}

foreach ($entry in $initialRows) {
    $target = $entry.Baseline
    $row = $entry.Row
    $etag = [string]$row.'@odata.etag'
    if ([string]::IsNullOrWhiteSpace($etag)) {
        throw 'Registration ETag is unavailable; no disable PATCH was sent.'
    }
    $nextState = if ($Restore) { 0 } else { 1 }
    $nextStatus = if ($Restore) { 1 } else { 2 }
    $response = Invoke-DataverseRequest -Method PATCH `
        -Path "sdkmessageprocessingsteps($($target.StepId))" `
        -Body ([ordered]@{ statecode = $nextState; statuscode = $nextStatus }) -ETag $etag
    if ([int]$response.StatusCode -lt 200 -or [int]$response.StatusCode -ge 300) {
        throw "DEV guard bypass PATCH failed for $($target.Name); stop without retry."
    }
    $reconciled = Get-DataverseStep -StepId ([string]$target.StepId)
    if ([string]$reconciled.name -cne [string]$target.Name -or
        [string]$reconciled._eventhandler_value -ine [string]$baseline.PackageGuardTypeId -or
        [int]$reconciled.statecode -ne $nextState -or [int]$reconciled.statuscode -ne $nextStatus -or
        [int]$reconciled.stage -ne 10 -or [int]$reconciled.mode -ne 0 -or
        $reconciled._impersonatinguserid_value) {
        throw "Immediate disabled-state reconciliation failed for $($target.Name); stop without retry."
    }
}

[ordered]@{
    Result = if ($Restore) { 'VN_LMV_IT_DEV_GUARD_BYPASS_RESTORED' } else { 'VN_LMV_IT_DEV_GUARD_BYPASS_RECONCILED' }
    Environment = 'VN LMV IT'
    GuardSteps = $expectedNames
    ReconciledStateCount = $script:RequestCounts.PATCH
    FinalState = if ($Restore) { 'ENABLED' } else { 'DISABLED' }
    RegistrationGET = $script:RequestCounts.GET
    AutomaticRetries = 0
    OtherRegistrationWrites = 0
    PackageOrApiWrites = 0
    SecurityRoleWrites = 0
} | ConvertTo-Json -Depth 8
}
finally {
    $script:AccessToken = $null
}
