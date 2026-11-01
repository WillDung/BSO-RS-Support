Set-StrictMode -Version Latest

function Get-BsoRsTestTargetAuthorizationEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw 'Test target authorization evidence file does not exist.'
    }

    $evidence = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    $expectedProperties = @(
        'purpose',
        'targetDisplayName',
        'authorizationScope',
        'syntheticDataPermitted',
        'productionOperationsProhibited',
        'unrelatedEnvironmentResourcesProhibited',
        'approvalSource',
        'approvalStatus'
    )
    $actualProperties = @($evidence.PSObject.Properties | Select-Object -ExpandProperty Name)
    if (@(Compare-Object $expectedProperties $actualProperties).Count -ne 0 -or
        $evidence.purpose -cne 'BSO-RS-Support Test rehearsal' -or
        $evidence.targetDisplayName -cne 'LMV BI DEV' -or
        $evidence.authorizationScope -cne 'BOUNDED_TEST_REHEARSAL' -or
        $evidence.syntheticDataPermitted -ne $true -or
        $evidence.productionOperationsProhibited -ne $true -or
        $evidence.unrelatedEnvironmentResourcesProhibited -ne $true -or
        $evidence.approvalSource -cne 'Explicit owner instruction in current project/session' -or
        $evidence.approvalStatus -cne 'APPROVED') {
        throw 'Test target authorization evidence does not match the bounded owner authorization.'
    }

    [pscustomobject]@{
        Status = 'TEST_TARGET_APPROVAL_EVIDENCE_SATISFIED'
        TargetDisplayName = $evidence.targetDisplayName
        AuthorizationScope = $evidence.authorizationScope
    }
}

Export-ModuleMember -Function Get-BsoRsTestTargetAuthorizationEvidence
