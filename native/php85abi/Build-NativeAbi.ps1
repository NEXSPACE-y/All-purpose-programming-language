[CmdletBinding()]
param(
    [string]$DevelZip = 'C:\Users\rinpa\Downloads\php-devel-pack-8.5.12-1-Win32-vs17-x64.zip',
    [string]$SdkDirectory,
    [string]$OutputDirectory,
    [string]$ReportDirectory,
    [string]$BuildTools = 'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools',
    [string]$MsvcVersion = '14.44.35207',
    [string]$WindowsSdkVersion = '10.0.22621.0'
)
$ErrorActionPreference='Stop'
if(-not $OutputDirectory){$OutputDirectory=Join-Path $PSScriptRoot 'out\windows-x64-ts'}
if(-not $ReportDirectory){$ReportDirectory=Join-Path $PSScriptRoot '..\..\reports\native-abi-implementation-20261112'}
$utf8=New-Object Text.UTF8Encoding($false)
$expected='52cb020402c3165e7cb37ec0d96ae43e26997f01d0fdb5474aa92801246810e9'
if((Get-FileHash -LiteralPath $DevelZip -Algorithm SHA256).Hash.ToLowerInvariant() -cne $expected){throw 'Pinned SDK ZIP hash mismatch'}
if(-not $SdkDirectory){
    $scratch=Join-Path ([IO.Path]::GetTempPath()) ('ALL-php85abi-sdk-'+[guid]::NewGuid().ToString('N'))
    Expand-Archive -LiteralPath $DevelZip -DestinationPath $scratch
    $SdkDirectory=Join-Path $scratch 'php-8.5.12-devel-vs17-x64'
}
$sdkRoot=[IO.Path]::GetFullPath($SdkDirectory)
$include=Join-Path $sdkRoot 'include'
if(-not(Test-Path -LiteralPath (Join-Path $include 'Zend\zend_modules.h'))){throw 'Pinned SDK headers not found'}
$out=[IO.Path]::GetFullPath($OutputDirectory)
$report=[IO.Path]::GetFullPath($ReportDirectory)
[IO.Directory]::CreateDirectory($out)|Out-Null
[IO.Directory]::CreateDirectory($report)|Out-Null
$vc=Join-Path $BuildTools ('VC\Tools\MSVC\'+$MsvcVersion)
$bin=Join-Path $vc 'bin\Hostx64\x64'
$windowsSdk='C:\Program Files (x86)\Windows Kits\10'
$savedInclude=$env:INCLUDE;$savedLib=$env:LIB;$savedPath=$env:PATH
try {
    $env:PATH=$bin+';'+$savedPath
    $env:INCLUDE=(Join-Path $vc 'include')+';'+(Join-Path $windowsSdk ('Include\'+$WindowsSdkVersion+'\ucrt'))+';'+(Join-Path $windowsSdk ('Include\'+$WindowsSdkVersion+'\shared'))+';'+(Join-Path $windowsSdk ('Include\'+$WindowsSdkVersion+'\um'))
    $env:LIB=(Join-Path $vc 'lib\x64')+';'+(Join-Path $windowsSdk ('Lib\'+$WindowsSdkVersion+'\ucrt\x64'))+';'+(Join-Path $windowsSdk ('Lib\'+$WindowsSdkVersion+'\um\x64'))
    $argsList=@('/nologo','/LD','/EHsc','/MD','/std:c++17','/O2','/W3','/DZTS','/DZEND_DEBUG=0','/DPHP_WIN32','/DZEND_WIN32','/DLIBZEND_EXPORTS','/DPHP_EXPORTS','/DTSRM_EXPORTS','/D_WIN32_WINNT=0x0601',('/I'+$include),('/I'+(Join-Path $include 'main')),('/I'+(Join-Path $include 'Zend')),('/I'+(Join-Path $include 'TSRM')),('/I'+(Join-Path $PSScriptRoot 'include')),('/Fo'+(Join-Path $out 'Runtime.obj')),('/Fe'+(Join-Path $out 'php8ts.dll')),(Join-Path $PSScriptRoot 'src\Runtime.cpp'),'/link',('/IMPLIB:'+(Join-Path $out 'all_php85abi.lib')))
    $log=@(& (Join-Path $bin 'cl.exe') @argsList 2>&1);$code=$LASTEXITCODE
    [IO.File]::WriteAllLines((Join-Path $report 'build.log'),[string[]]$log,$utf8)
    if($code -ne 0){$log|Write-Output;throw 'Native ABI candidate build failed'}
    $imports=@(& (Join-Path $bin 'dumpbin.exe') /IMPORTS (Join-Path $out 'php8ts.dll') 2>&1)
    [IO.File]::WriteAllLines((Join-Path $report 'candidate-imports.log'),[string[]]$imports,$utf8)
    if($LASTEXITCODE-ne0-or($imports-match '(?i)^\s+php8(?:ts)?\.dll\s*$')){throw 'Candidate links a PHP runtime or import verification failed'}
    $exports=@(& (Join-Path $bin 'dumpbin.exe') /EXPORTS (Join-Path $out 'php8ts.dll') 2>&1)
    [IO.File]::WriteAllLines((Join-Path $report 'candidate-exports.log'),[string[]]$exports,$utf8)
    if($LASTEXITCODE-ne0){throw 'Candidate export inspection failed'}
    $result=[ordered]@{status='BUILT_NOT_RUNTIME_VERIFIED';candidate=(Join-Path $out 'php8ts.dll');candidate_sha256=(Get-FileHash -LiteralPath (Join-Path $out 'php8ts.dll') -Algorithm SHA256).Hash.ToLowerInvariant();sdk_directory=$sdkRoot;devel_zip_sha256=$expected;stock_php_linked=$false;compiler=(Join-Path $bin 'cl.exe');windows_sdk_version=$WindowsSdkVersion;source_sha256=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'src\Runtime.cpp') -Algorithm SHA256).Hash.ToLowerInvariant()}
    $json=$result|ConvertTo-Json -Depth 4;[IO.File]::WriteAllText((Join-Path $report 'build.json'),$json+[Environment]::NewLine,$utf8);$json
} finally {$env:INCLUDE=$savedInclude;$env:LIB=$savedLib;$env:PATH=$savedPath}
