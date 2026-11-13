[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$GeneratedDirectory,[Parameter(Mandatory=$true)][string]$RuntimeAssembly,[Parameter(Mandatory=$true)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Utility\Microsoft.PowerShell.Utility.psd1') -ErrorAction Stop
if($PSVersionTable.PSEdition-ceq'Core'){throw 'Use existing Windows PowerShell5.1 Framework compiler'}
$generated=(Resolve-Path -LiteralPath $GeneratedDirectory).ProviderPath;$runtime=(Resolve-Path -LiteralPath $RuntimeAssembly).ProviderPath;$destination=[IO.Path]::GetFullPath($OutputDirectory)
if(Test-Path -LiteralPath $destination){throw 'Preserve prior build; use fresh output'}
if((Get-FileHash -LiteralPath $runtime -Algorithm SHA256).Hash.ToLowerInvariant()-cne'18d50efb55d8a333424149e4ab37428e102b1ac938240e50358ee3c8ab89466b'){throw 'Canonical runtime01 hash mismatch'}
$inputs=[ordered]@{byte_runtime=$runtime;legacy_source=(Join-Path $generated 'bridge/AllNativeLegacyBridge.cs');callback_source=(Join-Path $generated 'bridge/AllNativeCallbackBridge.cs');probe_source=(Join-Path $PSScriptRoot 'AllNativeByteProbe.cs');build_source=$PSCommandPath}
$before=[ordered]@{};foreach($key in $inputs.Keys){$before[$key]=(Get-FileHash -LiteralPath $inputs[$key] -Algorithm SHA256).Hash.ToLowerInvariant()}
[void][IO.Directory]::CreateDirectory($destination);[IO.File]::Copy($runtime,(Join-Path $destination 'AllPhp.ByteValues.Runtime.dll'))
$provider=New-Object Microsoft.CSharp.CSharpCodeProvider;$library=New-Object CodeDom.Compiler.CompilerParameters
$library.GenerateExecutable=$false;$library.GenerateInMemory=$false;$library.OutputAssembly=Join-Path $destination 'AllPhp.NativeBytes.Bridges.dll';$library.CompilerOptions='/platform:x64 /optimize+ /langversion:5'
foreach($assembly in @('System.dll','System.Core.dll',$runtime)){[void]$library.ReferencedAssemblies.Add($assembly)}
$result=$provider.CompileAssemblyFromFile($library,[string[]]@($inputs.legacy_source,$inputs.callback_source))
if($result.Errors.HasErrors){$result.Errors|ForEach-Object{[Console]::Error.WriteLine($_.ToString())};throw 'Info v2 bridge build failed'}
$probe=New-Object CodeDom.Compiler.CompilerParameters;$probe.GenerateExecutable=$true;$probe.GenerateInMemory=$false;$probe.OutputAssembly=Join-Path $destination 'all-native-byte-probe.exe';$probe.CompilerOptions=$library.CompilerOptions
foreach($assembly in @('System.dll','System.Core.dll','System.Web.Extensions.dll',$runtime,$library.OutputAssembly)){[void]$probe.ReferencedAssemblies.Add($assembly)}
$result=$provider.CompileAssemblyFromFile($probe,$inputs.probe_source)
if($result.Errors.HasErrors){$result.Errors|ForEach-Object{[Console]::Error.WriteLine($_.ToString())};throw 'Info v2 new probe build failed'}
$after=[ordered]@{};foreach($key in $inputs.Keys){$after[$key]=(Get-FileHash -LiteralPath $inputs[$key] -Algorithm SHA256).Hash.ToLowerInvariant()}
$files=@(Get-ChildItem -LiteralPath $destination -File|ForEach-Object{[ordered]@{path=$_.Name;bytes=$_.Length;sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}})
$record=[ordered]@{status='BUILT_NOT_RUNTIME_VERIFIED';input_paths=$inputs;inputs_before=$before;inputs_after=$after;files=$files;powerShell=$PSVersionTable.PSVersion.ToString();clr=[Environment]::Version.ToString();pointer_bytes=[IntPtr]::Size;compiler_options=$library.CompilerOptions;profile='Info v2 copied bridges and fresh per-case host; old DLLs never loaded by this build'}
[IO.File]::WriteAllText((Join-Path $destination 'build.json'),($record|ConvertTo-Json -Depth 8)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false));Write-Output ('Built '+$probe.OutputAssembly)
