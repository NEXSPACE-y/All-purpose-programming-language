# Reports pinned SDK structure layouts. No PHP library is linked or loaded.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$DevelZip,
    [Parameter(Mandatory=$true)][string]$OutputDirectory,
    [string]$BuildTools = 'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools',
    [string]$MsvcVersion = '14.44.35207',
    [string]$WindowsSdkVersion = '10.0.22621.0'
)
$ErrorActionPreference = 'Stop'
$expected = '52cb020402c3165e7cb37ec0d96ae43e26997f01d0fdb5474aa92801246810e9'
if ((Get-FileHash -LiteralPath $DevelZip -Algorithm SHA256).Hash.ToLowerInvariant() -cne $expected) {
    throw 'Devel ZIP does not match the pinned PHP 8.5.12 archive'
}
$outputRoot = [IO.Path]::GetFullPath($OutputDirectory)
[IO.Directory]::CreateDirectory($outputRoot) | Out-Null
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('ALL-abi-layout-' + [guid]::NewGuid().ToString('N'))
Expand-Archive -LiteralPath $DevelZip -DestinationPath $scratch
$include = Join-Path $scratch 'php-8.5.12-devel-vs17-x64\include'
$vc = Join-Path $BuildTools ('VC\Tools\MSVC\' + $MsvcVersion)
$compilerDirectory = Join-Path $vc 'bin\Hostx64\x64'
$compiler = Join-Path $compilerDirectory 'cl.exe'
$dumper = Join-Path $compilerDirectory 'dumpbin.exe'
$sdk = 'C:\Program Files (x86)\Windows Kits\10'
$savedInclude = $env:INCLUDE
$savedLib = $env:LIB
$savedPath = $env:PATH
$layoutExe = Join-Path $scratch 'Abi-Layout.exe'
$layoutObj = Join-Path $scratch 'Abi-Layout.obj'
$utf8 = New-Object Text.UTF8Encoding($false)
try {
    $env:PATH = $compilerDirectory + ';' + $savedPath
    $env:INCLUDE = (Join-Path $vc 'include') + ';' +
        (Join-Path $sdk ('Include\' + $WindowsSdkVersion + '\ucrt')) + ';' +
        (Join-Path $sdk ('Include\' + $WindowsSdkVersion + '\shared')) + ';' +
        (Join-Path $sdk ('Include\' + $WindowsSdkVersion + '\um'))
    $env:LIB = (Join-Path $vc 'lib\x64') + ';' +
        (Join-Path $sdk ('Lib\' + $WindowsSdkVersion + '\ucrt\x64')) + ';' +
        (Join-Path $sdk ('Lib\' + $WindowsSdkVersion + '\um\x64'))
    $compileArgs = @('/nologo','/MD','/O1','/DZTS','/DZEND_DEBUG=0','/DPHP_WIN32','/DZEND_WIN32',
        '/D_WIN32_WINNT=0x0601',('/I'+$include),('/I'+(Join-Path $include 'main')),
        ('/I'+(Join-Path $include 'Zend')),('/I'+(Join-Path $include 'TSRM')),
        ('/Fo'+$layoutObj),('/Fe'+$layoutExe),(Join-Path $PSScriptRoot 'Abi-Layout.c'))
    $buildLog = @(& $compiler @compileArgs 2>&1)
    $buildExit = $LASTEXITCODE
    [IO.File]::WriteAllLines((Join-Path $outputRoot 'header-layout-build.log'), [string[]]$buildLog, $utf8)
    if ($buildExit -ne 0) { throw ('Header layout compiler failed. See ' + (Join-Path $outputRoot 'header-layout-build.log')) }
    $imports = @(& $dumper /IMPORTS $layoutExe 2>&1)
    $dumpExit = $LASTEXITCODE
    [IO.File]::WriteAllLines((Join-Path $outputRoot 'header-layout-exe-imports.log'), [string[]]$imports, $utf8)
    if ($dumpExit -ne 0 -or ($imports -match '(?i)php8(?:ts)?\.dll')) {
        throw 'Layout program import check failed; executable will not be run'
    }
    $jsonText = [string](& $layoutExe)
    if ($LASTEXITCODE -ne 0) { throw 'Layout constant reporter failed' }
    $layout = $jsonText | ConvertFrom-Json
    $layout | Add-Member -NotePropertyName executable_sha256 -NotePropertyValue (Get-FileHash -LiteralPath $layoutExe -Algorithm SHA256).Hash.ToLowerInvariant()
    $layout | Add-Member -NotePropertyName devel_zip_sha256 -NotePropertyValue $expected
    $layout | Add-Member -NotePropertyName compiler_path -NotePropertyValue $compiler
    $layout | Add-Member -NotePropertyName windows_sdk_version -NotePropertyValue $WindowsSdkVersion
    $layout | Add-Member -NotePropertyName php_runtime_linked -NotePropertyValue $false
    $layout | Add-Member -NotePropertyName scratch_directory -NotePropertyValue $scratch
    $result = $layout | ConvertTo-Json -Depth 5
    [IO.File]::WriteAllText((Join-Path $outputRoot 'header-layout.json'), $result + [Environment]::NewLine, $utf8)
    $result
} finally {
    $env:INCLUDE = $savedInclude
    $env:LIB = $savedLib
    $env:PATH = $savedPath
}
