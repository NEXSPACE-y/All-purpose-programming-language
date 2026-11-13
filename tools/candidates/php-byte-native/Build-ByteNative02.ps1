[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][string]$ByteRuntimeAssembly,
 [Parameter(Mandatory=$true)][string]$GeneratedSourceDirectory,
 [Parameter(Mandatory=$true)][string]$OutputDirectory
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Utility\Microsoft.PowerShell.Utility.psd1') -ErrorAction Stop
if($PSVersionTable.PSEdition-ceq'Core'){throw 'Build with Windows PowerShell 5.1 and its existing framework compiler'}
$runtime=(Resolve-Path -LiteralPath $ByteRuntimeAssembly).ProviderPath
$sources=(Resolve-Path -LiteralPath $GeneratedSourceDirectory).ProviderPath
$destination=[IO.Path]::GetFullPath($OutputDirectory)
if(Test-Path -LiteralPath $destination){throw 'Preserve prior build; choose a fresh output directory'}
$inputs=[ordered]@{
 byte_runtime=$runtime
 legacy_source=(Join-Path $sources 'AllNativeLegacyBridge.cs')
 callback_source=(Join-Path $sources 'AllNativeCallbackBridge.cs')
 probe_source=(Join-Path $PSScriptRoot 'revision02/AllNativeByteProbe.cs')
 contract_source=(Join-Path $PSScriptRoot 'AllByteCallbackContractProbe.cs')
 build_source=$PSCommandPath
}
$before=[ordered]@{};foreach($name in $inputs.Keys){$before[$name]=(Get-FileHash -LiteralPath $inputs[$name] -Algorithm SHA256).Hash.ToLowerInvariant()}
[void][IO.Directory]::CreateDirectory($destination)
[IO.File]::Copy($runtime,(Join-Path $destination 'AllPhp.ByteValues.Runtime.dll'))
$provider=New-Object Microsoft.CSharp.CSharpCodeProvider
$parameters=New-Object CodeDom.Compiler.CompilerParameters
$parameters.GenerateExecutable=$false;$parameters.GenerateInMemory=$false
$parameters.OutputAssembly=Join-Path $destination 'AllPhp.NativeBytes.Bridges.dll'
$parameters.CompilerOptions='/platform:x64 /optimize+ /langversion:5'
foreach($assembly in @('System.dll','System.Core.dll',$runtime)){[void]$parameters.ReferencedAssemblies.Add($assembly)}
$compiled=$provider.CompileAssemblyFromFile($parameters,[string[]]@($inputs.legacy_source,$inputs.callback_source))
if($compiled.Errors.HasErrors){$compiled.Errors|ForEach-Object{[Console]::Error.WriteLine($_.ToString())};throw 'Byte native bridge build failed'}
$probe=New-Object CodeDom.Compiler.CompilerParameters
$probe.GenerateExecutable=$true;$probe.GenerateInMemory=$false
$probe.OutputAssembly=Join-Path $destination 'all-native-byte-probe.exe'
$probe.CompilerOptions=$parameters.CompilerOptions
foreach($assembly in @('System.dll','System.Core.dll','System.Web.Extensions.dll',$runtime,$parameters.OutputAssembly)){[void]$probe.ReferencedAssemblies.Add($assembly)}
$compiled=$provider.CompileAssemblyFromFile($probe,$inputs.probe_source)
if($compiled.Errors.HasErrors){$compiled.Errors|ForEach-Object{[Console]::Error.WriteLine($_.ToString())};throw 'Byte native probe build failed'}
$probe.OutputAssembly=Join-Path $destination 'all-byte-callback-contract-probe.exe'
$compiled=$provider.CompileAssemblyFromFile($probe,$inputs.contract_source)
if($compiled.Errors.HasErrors){$compiled.Errors|ForEach-Object{[Console]::Error.WriteLine($_.ToString())};throw 'Byte callback contract probe build failed'}
$after=[ordered]@{};foreach($name in $inputs.Keys){$after[$name]=(Get-FileHash -LiteralPath $inputs[$name] -Algorithm SHA256).Hash.ToLowerInvariant()}
$files=@(Get-ChildItem -LiteralPath $destination -File|ForEach-Object{[ordered]@{path=$_.Name;bytes=$_.Length;sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}})
$record=[ordered]@{status='BUILT_NOT_RUNTIME_VERIFIED';powerShell=$PSVersionTable.PSVersion.ToString();clr=[Environment]::Version.ToString();pointer_bytes=[IntPtr]::Size;compiler_options=$parameters.CompilerOptions;input_paths=$inputs;inputs_before=$before;inputs_after=$after;files=$files;canonical_type='AllPhp.ByteValues.PhpBytes';native_core_changes=$false}
[IO.File]::WriteAllText((Join-Path $destination 'build.json'),($record|ConvertTo-Json -Depth 8)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
Write-Output ('Built '+$probe.OutputAssembly)
