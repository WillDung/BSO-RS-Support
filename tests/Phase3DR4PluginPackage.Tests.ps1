#requires -Version 7.4
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$projectPath = Join-Path $root 'solutions\CandidateCorePackage\CandidateCore.Package.csproj'
$packagePath = Join-Path $root 'solutions\CandidateCorePackage\bin\Release\os_sr_cact_pkg.1.0.0.nupkg'
$contractPath = Join-Path $root 'docs\PHASE_3C_API_CONTRACT.json'
$sdkPath = Join-Path $root 'tests\CandidateCoreSdk\bin\Release\net48\Microsoft.Xrm.Sdk.dll'
$project = Get-Content -Raw $projectPath
$contract = Get-Content -Raw $contractPath | ConvertFrom-Json
$script:Passed = 0

function Assert-Test([bool]$Condition, [string]$Name) {
    if (-not $Condition) { throw "FAIL: $Name" }
    $script:Passed++
}

Assert-Test ($project -match '<TargetFramework>net462</TargetFramework>' -and
    $project -match '<AssemblyName>os_sr_cact</AssemblyName>' -and
    $project -match '<PackageId>os_sr_cact_pkg</PackageId>' -and
    $project -match '<Version>1\.0\.0</Version>') 'Package and assembly identities are frozen'
Assert-Test ($project -match '<SignAssembly>false</SignAssembly>' -and
    $project -notmatch 'AssemblyOriginatorKeyFile|\.snk') 'Package build does not use or reference a signing key'
Assert-Test ($project -match 'Microsoft\.PowerApps\.MSBuild\.Plugin" Version="1\.52\.1"' -and
    $project -match 'Microsoft\.CrmSdk\.CoreAssemblies" Version="9\.0\.2\.60"') 'Package tooling and Dataverse SDK references are pinned'
Assert-Test ($project -match 'CandidateCore\\DataversePlugin\.cs' -and
    $project -match 'CandidateCore\\Operation\.cs' -and
    ([regex]::Matches($project, '<Compile Include=')).Count -eq 2) 'Only the approved Candidate Core source files are linked'
Assert-Test ($contract.assembly -ceq 'os_sr_cact' -and
    $contract.handler -ceq 'os_sr_cact.ApplyCandidateAction' -and
    $contract.guard -ceq 'os_sr_cact.ProtectCandidateCore') 'Package types match the current Phase 3C contract'
Assert-Test (Test-Path -LiteralPath $packagePath) 'Release NuGet package exists'

$temporaryDirectory = Join-Path ([IO.Path]::GetTempPath()) ('phase3dr4-package-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $temporaryDirectory
try {
    $archive = [IO.Compression.ZipFile]::OpenRead($packagePath)
    try {
        $expectedEntries = @(
            '[Content_Types].xml'
            '_rels/.rels'
            'lib/net462/os_sr_cact.dll'
            'os_sr_cact_pkg.nuspec'
            'package/services/metadata/core-properties/nuget.psmdcp'
        ) | Sort-Object
        $actualEntries = @($archive.Entries | ForEach-Object FullName | Sort-Object)
        Assert-Test (([string]::Join([Environment]::NewLine, $actualEntries)) -ceq
            ([string]::Join([Environment]::NewLine, $expectedEntries))) 'Package contains only expected NuGet metadata and one plug-in DLL'
        Assert-Test (@($archive.Entries | Where-Object { $_.FullName -match '\.(pdb|snk|pfx)$' }).Count -eq 0) 'Package contains no symbols or signing material'

        $nuspecEntry = $archive.GetEntry('os_sr_cact_pkg.nuspec')
        $nuspecReader = [IO.StreamReader]::new($nuspecEntry.Open())
        try { [xml]$nuspec = $nuspecReader.ReadToEnd() }
        finally { $nuspecReader.Dispose() }
        $namespace = [Xml.XmlNamespaceManager]::new($nuspec.NameTable)
        $namespace.AddNamespace('n', 'http://schemas.microsoft.com/packaging/2012/06/nuspec.xsd')
        $packageId = $nuspec.SelectSingleNode('/n:package/n:metadata/n:id', $namespace).InnerText
        $packageVersion = $nuspec.SelectSingleNode('/n:package/n:metadata/n:version', $namespace).InnerText
        Assert-Test ($packageId -ceq 'os_sr_cact_pkg' -and $packageVersion -ceq '1.0.0') 'NuGet package manifest identity is exact'

        $assemblyPath = Join-Path $temporaryDirectory 'os_sr_cact.dll'
        $assemblyEntry = $archive.GetEntry('lib/net462/os_sr_cact.dll')
        $inputStream = $assemblyEntry.Open()
        $outputStream = [IO.File]::Create($assemblyPath)
        try { $inputStream.CopyTo($outputStream) }
        finally { $outputStream.Dispose(); $inputStream.Dispose() }
    }
    finally { $archive.Dispose() }

    $assemblyName = [Reflection.AssemblyName]::GetAssemblyName($assemblyPath)
    $publicKeyToken = $assemblyName.GetPublicKeyToken()
    Assert-Test ($assemblyName.Name -ceq 'os_sr_cact' -and
        $assemblyName.Version -ceq [version]'1.0.0.0' -and
        ($null -eq $publicKeyToken -or $publicKeyToken.Length -eq 0)) 'Contained assembly identity is correct and unsigned'
    Assert-Test ((Test-Path -LiteralPath $sdkPath) -and
        ([IO.File]::ReadAllBytes($assemblyPath).Length -gt 0)) 'Reflection dependency and package assembly are available'

    $expectedTypesJson = ConvertTo-Json @($contract.handler, $contract.guard) -Compress
    $expectedTypesBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($expectedTypesJson))
    $sdkPathJson = ConvertTo-Json $sdkPath -Compress
    $assemblyPathJson = ConvertTo-Json $assemblyPath -Compress
    $reflectionLines = @(
        '$ProgressPreference = ''SilentlyContinue'''
        '[Reflection.Assembly]::LoadFrom(__SDK__) | Out-Null'
        '$expected = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(''__EXPECTED__'')) | ConvertFrom-Json'
        '$assembly = [Reflection.Assembly]::LoadFrom(__ASSEMBLY__)'
        '$assembly.GetTypes() | Where-Object { $_.FullName -in $expected } | ForEach-Object FullName'
    )
    $reflectionScript = [string]::Join([Environment]::NewLine, $reflectionLines).
        Replace('__SDK__', $sdkPathJson).
        Replace('__EXPECTED__', $expectedTypesBase64).
        Replace('__ASSEMBLY__', $assemblyPathJson)
    $encodedScript = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($reflectionScript))
    $reflectedTypes = @(& powershell.exe -NoLogo -NoProfile -NonInteractive -EncodedCommand $encodedScript)
    $expectedTypeNames = @($contract.handler, $contract.guard) | Sort-Object
    $actualTypeList = [string]::Join([Environment]::NewLine, @($reflectedTypes | Sort-Object))
    $expectedTypeList = [string]::Join([Environment]::NewLine, $expectedTypeNames)
    Assert-Test ($LASTEXITCODE -eq 0 -and $actualTypeList -ceq $expectedTypeList) 'Both approved plug-in types are present in the packaged assembly'
}
finally {
    Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force
}

"PASS: $script:Passed Phase 3D-R4 package assertions; local artifact only, no authentication/network."
