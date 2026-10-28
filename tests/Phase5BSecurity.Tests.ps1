#requires -Version 7.4
$ErrorActionPreference = 'Stop'
$source = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\scripts\Test-BsoRsPhase5BSecurity.ps1') -Raw
$count = 0
function Assert-Phase5B([bool]$Condition, [string]$Name) {
    if (-not $Condition) { throw "FAIL: $Name" }
    $script:count++
}
Assert-Phase5B ($source.Contains("[ValidateSet('Inspect', 'GrantAppAccess')]") -and $source.Contains("`$Mode = 'Inspect'")) 'Read-only default'
Assert-Phase5B ($source.Contains("https://org14938ec2.crm4.dynamics.com") -and $source.Contains("VN LMV IT")) 'Pinned DEV target'
Assert-Phase5B ($source.Contains('$script:PacUserEmail -ine $TargetUser') -and $source.Contains('$who.UserId -ine $script:ExpectedUserId')) 'Caller and target identity agreement'
Assert-Phase5B ($source.Contains('$users.Count -ne 1 -or $roles.Count -ne 1 -or $apps.Count -ne 1')) 'Unambiguous target resolution'
Assert-Phase5B ($source.Contains('teamroles_association') -and $source.Contains('systemuserroles_association')) 'Read both direct and team-derived roles'
Assert-Phase5B ($source.Contains('APP_ASSOCIATION_DISPATCH_RESERVED_DO_NOT_RETRY') -and $source.Contains('(Test-Path -LiteralPath $EvidencePath)')) 'Persist one-shot dispatch reservation'
Assert-Phase5B ([regex]::Matches($source, '-Method Post').Count -eq 1 -and $source.Contains('appmoduleroles_association/`$ref')) 'Only app-role association write'
Assert-Phase5B ($source.Contains('-MaximumRetryCount 0 -MaximumRedirection 0')) 'No transport retries or redirection'
Assert-Phase5B ($source.Contains('A pre-existing app role is missing.')) 'Preserve existing app roles'
Assert-Phase5B ($source.Contains('BSO_SECURITY_ACCEPTANCE_BLOCKED_BY_PREEXISTING_ELEVATED_ACCESS')) 'Elevated role blocks acceptance'
Assert-Phase5B (-not ($source -match '-Method (Delete|Patch)|PublishAllXml|admin assign-user|self-elevate')) 'No membership removal, broad grant, or assignment retry'
Assert-Phase5B ($source.Contains('@odata.nextLink') -and $source.Contains('Read pagination escaped')) 'Follow guarded pagination'
Write-Output "Phase 5B offline security-script checks passed: $count"
