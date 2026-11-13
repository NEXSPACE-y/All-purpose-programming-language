[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][string]$Core,
 [Parameter(Mandatory=$true)][string]$Extension,
 [Parameter(Mandatory=$true)][string]$Cases,
 [Parameter(Mandatory=$true)][string]$Output,
 [switch]$Legacy
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Utility\Microsoft.PowerShell.Utility.psd1') -ErrorAction Stop
$utf8=New-Object Text.UTF8Encoding($false)
Add-Type -Path (Join-Path $PSScriptRoot 'AllNativeCallbackBridge.cs')
if($Legacy-and($env:PHP_DL_TEST_USE_OLD_REGISTER_INI_ENTRIES-cne'1'-or$env:PHP_DL_TEST_USE_REGISTER_FUNCTIONS_DIRECTLY-cne'1')){throw 'Legacy CRT getenv flags must be inherited when starting this child process'}
$bridge=New-Object AllPhp85AbiCallback.Bridge([IO.Path]::GetFullPath($Core))
$bridge.LoadExtension([IO.Path]::GetFullPath($Extension))
$bridge.Start()
$result=New-Object Collections.Generic.List[object]
foreach($case in (Get-Content -LiteralPath $Cases -Raw -Encoding UTF8|ConvertFrom-Json)){
 $arguments=New-Object 'Collections.Generic.List[AllPhp85AbiCallback.Argument]'
 foreach($a in @($case.args)){
  $arg=New-Object AllPhp85AbiCallback.Argument
  $arg.Type=[uint32]$a.type
  if($a.PSObject.Properties['integer']){$arg.Integer=[long]$a.integer}
  if($a.PSObject.Properties['real']){$arg.Real=[double]$a.real}
  if($a.PSObject.Properties['base64']){$arg.Base64=[string]$a.base64}
  $arguments.Add($arg)
 }
 $call=$bridge.Call([string]$case.scope,[string]$case.function,$arguments.ToArray(),[bool]$case.strict,[bool]$case.frameless)
 $result.Add([ordered]@{id=$case.id;result=$call})
}
$metadata=[ordered]@{constant=$bridge.Constant('DL_TEST_CONST');parent=$bridge.Parent('DlTestSubClass');property=$bridge.Property('DlTestSuperClass','a');inherited_property=$bridge.Property('DlTestSubClass','a');ini_long=$bridge.Ini('dl_test.long');ini_string=$bridge.Ini('dl_test.string');core_path=$bridge.CorePath;loaded_php_modules=$bridge.LoadedPhpModules}
$metadata.memory_probe=$bridge.MemoryProbe()|ConvertFrom-Json
$metadata.function_catalog=$bridge.FunctionCatalog|ConvertFrom-Json
if($Legacy){$metadata.direct_registration=$bridge.Call('','dl_test_use_register_functions_directly',[AllPhp85AbiCallback.Argument[]]@(),$false,$false)}
$bridge.SetIni('dl_test.long','97');$bridge.SetIni('dl_test.string','changed')
$metadata.ini_changed=@($bridge.Ini('dl_test.long'),$bridge.Ini('dl_test.string'))
$metadata.info_base64=$bridge.ModuleInfo()
$bridge.End();$bridge.Start();$metadata.ini_reset=@($bridge.Ini('dl_test.long'),$bridge.Ini('dl_test.string'));$bridge.End()
$threads=$bridge.RunThreadIsolation()
$before=$bridge.Stats|ConvertFrom-Json
$bridge.Shutdown()
$after=$bridge.Stats|ConvertFrom-Json
$record=[ordered]@{method='ALL_owned_native_ABI_existing_unmodified_DLL';cases=$result.ToArray();metadata=$metadata;thread_isolation=$threads;stats_before_shutdown=$before;stats_after_shutdown=$after}
[IO.File]::WriteAllText([IO.Path]::GetFullPath($Output),($record|ConvertTo-Json -Depth 12)+[Environment]::NewLine,$utf8)
Write-Output ('Native DLL worker completed '+$result.Count+' calls')
