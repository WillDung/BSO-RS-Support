#requires -Version 7.4
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$script:Passed = 0

function Assert-Test([bool]$Condition, [string]$Name) {
    if (-not $Condition) { throw "FAIL: $Name" }
    $script:Passed++
}

function Read-Xml([string]$RelativePath) {
    $path = Join-Path $root $RelativePath
    [xml](Get-Content -LiteralPath $path -Raw)
}

function Get-FormFields([string]$RelativePath, [string]$ExpectedId) {
    $document = Read-Xml $RelativePath
    $form = $document.SelectSingleNode("//*[local-name()='systemform']")
    Assert-Test ($null -ne $form -and
        $form.SelectSingleNode("./*[local-name()='formid']").InnerText -ceq $ExpectedId) `
        "$RelativePath preserves its existing form identity"
    $fields = @($form.SelectNodes(".//*[local-name()='control']") |
        ForEach-Object { $_.GetAttribute('datafieldname') })
    $cellIds = @($form.SelectNodes(".//*[local-name()='cell']") |
        ForEach-Object { $_.GetAttribute('id') })
    Assert-Test (@($cellIds | Select-Object -Unique).Count -eq $cellIds.Count) `
        "$RelativePath has unique form cell IDs"
    $fields
}

$taMain = Get-FormFields `
    'solutions\Entities\os_sr_ta\FormXml\main\{e076f089-e35b-46f3-b123-9cf0463759e5}.xml' `
    '{e076f089-e35b-46f3-b123-9cf0463759e5}'
$taQuick = Get-FormFields `
    'solutions\Entities\os_sr_ta\FormXml\quick\{3e6402e0-dea6-4f3f-b27f-e3158478cbe2}.xml' `
    '{3e6402e0-dea6-4f3f-b27f-e3158478cbe2}'
$locMain = Get-FormFields `
    'solutions\Entities\os_sr_loc\FormXml\main\{aa697cca-4698-475e-8dd6-c08183fccfa8}.xml' `
    '{aa697cca-4698-475e-8dd6-c08183fccfa8}'
$locQuick = Get-FormFields `
    'solutions\Entities\os_sr_loc\FormXml\quick\{4a7ec083-1c0d-4740-a484-54a099616cf7}.xml' `
    '{4a7ec083-1c0d-4740-a484-54a099616cf7}'

Assert-Test ($taMain -contains 'os_sr_ta_nm' -and $taMain -contains 'os_sr_ta_eml' -and
    $taQuick -contains 'os_sr_ta_nm' -and $taQuick -contains 'os_sr_ta_eml') `
    'TA main and quick forms expose the name and email fields'
Assert-Test ($locMain -contains 'os_sr_loc_nm' -and $locMain -contains 'os_sr_loc_rmeml' -and
    $locMain -contains 'os_sr_loc_det' -and $locQuick -contains 'os_sr_loc_nm' -and
    $locQuick -contains 'os_sr_loc_rmeml' -and $locQuick -contains 'os_sr_loc_det') `
    'Location main and quick forms expose the name, room/resource email, and details fields'

$views = @(
    @{
        Path = 'solutions\Entities\os_sr_ta\SavedQueries\{2cb98672-8176-4337-af5e-d6aabcac8f2d}.xml'
        Fields = @('os_sr_ta_nm', 'os_sr_ta_eml', 'createdon')
    },
    @{
        Path = 'solutions\Entities\os_sr_loc\SavedQueries\{be4c932f-c13e-4b9a-9422-d7e9adf342c2}.xml'
        Fields = @('os_sr_loc_nm', 'os_sr_loc_rmeml', 'os_sr_loc_det', 'createdon')
    }
)
foreach ($view in $views) {
    $document = Read-Xml $view.Path
    $fetch = $document.SelectSingleNode("//*[local-name()='fetchxml']/*[local-name()='fetch']")
    $fields = @($fetch.SelectNodes(".//*[local-name()='attribute']") |
        ForEach-Object { $_.GetAttribute('name') })
    $layoutFields = @($document.SelectNodes("//*[local-name()='layoutxml']//*[local-name()='cell']") |
        ForEach-Object { $_.GetAttribute('name') })
    $activeFilter = $fetch.SelectSingleNode(".//*[local-name()='condition'][@attribute='statecode']")
    Assert-Test (@($view.Fields | Where-Object { $_ -notin $fields }).Count -eq 0 -and
        @($view.Fields | Where-Object { $_ -notin $layoutFields }).Count -eq 0 -and
        $null -ne $activeFilter -and $activeFilter.GetAttribute('operator') -ceq 'eq' -and
        $activeFilter.GetAttribute('value') -ceq '0') `
        "$($view.Path) shows the administration columns while preserving the Active filter"
}

Write-Output "Reference administration static checks passed: $script:Passed"
