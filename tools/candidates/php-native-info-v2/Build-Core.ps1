[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][ValidateSet('legacy','callback')][string]$Mode,
 [Parameter(Mandatory=$true)][string]$GeneratedDirectory,
 [Parameter(Mandatory=$true)][string]$SdkDirectory,
 [Parameter(Mandatory=$true)][string]$OutputDirectory,
 [Parameter(Mandatory=$true)][string]$ReportDirectory
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Utility\Microsoft.PowerShell.Utility.psd1') -ErrorAction Stop
$sdkRoot=(Resolve-Path -LiteralPath $SdkDirectory).ProviderPath
$generated=(Resolve-Path -LiteralPath $GeneratedDirectory).ProviderPath
$destination=[IO.Path]::GetFullPath($OutputDirectory);$report=[IO.Path]::GetFullPath($ReportDirectory)
if((Test-Path -LiteralPath $destination)-or(Test-Path -LiteralPath $report)){throw 'Preserve prior build/report; select fresh directories'}
$source=Join-Path $generated ($Mode+'/src/Runtime.cpp');$header=Join-Path $generated ($Mode+'/include/all_php_bridge.h')
$vc='C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Tools\MSVC\14.44.35207'
$bin=Join-Path $vc 'bin\Hostx64\x64';$windowsSdk='C:\Program Files (x86)\Windows Kits\10';$sdkVersion='10.0.22621.0'
$paths=[ordered]@{source=$source;header=$header;builder=$PSCommandPath;compiler=(Join-Path $bin 'cl.exe');dumpbin=(Join-Path $bin 'dumpbin.exe')}
foreach($name in @('main/php.h','Zend/zend_types.h','Zend/zend_modules.h','Zend/zend_ini.h','Zend/zend_object_handlers.h')){$paths[$name]=Join-Path $sdkRoot ('include/'+$name)}
$before=[ordered]@{};foreach($key in $paths.Keys){$before[$key]=(Get-FileHash -LiteralPath $paths[$key] -Algorithm SHA256).Hash.ToLowerInvariant()}
[void][IO.Directory]::CreateDirectory($destination);[void][IO.Directory]::CreateDirectory($report)
$savedInclude=$env:INCLUDE;$savedLib=$env:LIB;$savedPath=$env:PATH;$utf8=[Text.UTF8Encoding]::new($false)
try{
 $env:PATH=$bin+';'+$savedPath
 $env:INCLUDE=(Join-Path $vc 'include')+';'+(Join-Path $windowsSdk ('Include\'+$sdkVersion+'\ucrt'))+';'+(Join-Path $windowsSdk ('Include\'+$sdkVersion+'\shared'))+';'+(Join-Path $windowsSdk ('Include\'+$sdkVersion+'\um'))
 $env:LIB=(Join-Path $vc 'lib\x64')+';'+(Join-Path $windowsSdk ('Lib\'+$sdkVersion+'\ucrt\x64'))+';'+(Join-Path $windowsSdk ('Lib\'+$sdkVersion+'\um\x64'))
 $include=Join-Path $sdkRoot 'include'
 $arguments=@('/nologo','/LD','/EHsc','/MD','/std:c++17','/O2','/W3','/DZTS','/DZEND_DEBUG=0','/DPHP_WIN32','/DZEND_WIN32','/DLIBZEND_EXPORTS','/DPHP_EXPORTS','/DTSRM_EXPORTS','/D_WIN32_WINNT=0x0601',('/I'+$include),('/I'+(Join-Path $include 'main')),('/I'+(Join-Path $include 'Zend')),('/I'+(Join-Path $include 'TSRM')),('/I'+(Join-Path $generated ($Mode+'/include'))),('/Fo'+(Join-Path $destination 'Runtime.obj')),('/Fe'+(Join-Path $destination 'php8ts.dll')),$source,'/link',('/IMPLIB:'+(Join-Path $destination 'all_php85abi_info_v2.lib')))
 $log=@(& $paths.compiler @arguments 2>&1);$status=$LASTEXITCODE
 [IO.File]::WriteAllLines((Join-Path $report 'build.log'),[string[]]$log,$utf8)
 if($status-ne0){throw 'Info v2 core compilation failed; preserve build.log'}
 $imports=@(& $paths.dumpbin /NOLOGO /IMPORTS (Join-Path $destination 'php8ts.dll') 2>&1);$importStatus=$LASTEXITCODE
 [IO.File]::WriteAllLines((Join-Path $report 'imports.log'),[string[]]$imports,$utf8)
 $exports=@(& $paths.dumpbin /NOLOGO /EXPORTS (Join-Path $destination 'php8ts.dll') 2>&1);$exportStatus=$LASTEXITCODE
 [IO.File]::WriteAllLines((Join-Path $report 'exports.log'),[string[]]$exports,$utf8)
 if($importStatus-ne0-or$exportStatus-ne0-or($imports-match'(?i)^\s+php8(?:ts)?\.dll\s*$')){throw 'Static no-stock-PHP inspection failed'}
 $after=[ordered]@{};foreach($key in $paths.Keys){$after[$key]=(Get-FileHash -LiteralPath $paths[$key] -Algorithm SHA256).Hash.ToLowerInvariant()}
 $record=[ordered]@{status='BUILT_STATIC_INSPECTED_NOT_RUNTIME_VERIFIED';mode=$Mode;input_paths=$paths;inputs_before=$before;inputs_after=$after;candidate=(Join-Path $destination 'php8ts.dll');candidate_sha256=(Get-FileHash -LiteralPath (Join-Path $destination 'php8ts.dll') -Algorithm SHA256).Hash.ToLowerInvariant();compiler_arguments=$arguments;compiler_actual_status=$status;dumpbin_import_actual_status=$importStatus;dumpbin_export_actual_status=$exportStatus;sdk_directory=$sdkRoot;devel_zip_sha256='52cb020402c3165e7cb37ec0d96ae43e26997f01d0fdb5474aa92801246810e9';stock_php_linked=$false;runtime_executed=$false;original_outputs_overwritten=$false}
 [IO.File]::WriteAllText((Join-Path $report 'build.json'),($record|ConvertTo-Json -Depth 8)+[Environment]::NewLine,$utf8)
 Write-Output ('Built '+$record.candidate+' '+$record.candidate_sha256)
}finally{$env:INCLUDE=$savedInclude;$env:LIB=$savedLib;$env:PATH=$savedPath}
