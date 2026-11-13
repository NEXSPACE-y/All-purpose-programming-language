[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$GeneratedDirectory,[Parameter(Mandatory=$true)][string]$RuntimeAssembly,[Parameter(Mandatory=$true)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Utility\Microsoft.PowerShell.Utility.psd1') -ErrorAction Stop
if($PSVersionTable.PSEdition-ceq'Core'){throw 'Use installed Windows PowerShell5.1 Framework compiler'}
$generated=(Resolve-Path -LiteralPath $GeneratedDirectory).ProviderPath;$runtime=(Resolve-Path -LiteralPath $RuntimeAssembly).ProviderPath;$destination=[IO.Path]::GetFullPath($OutputDirectory)
if(Test-Path -LiteralPath $destination){throw 'Preserve prior output; use fresh directory'}
if((Get-FileHash -LiteralPath $runtime -Algorithm SHA256).Hash.ToLowerInvariant()-cne'18d50efb55d8a333424149e4ab37428e102b1ac938240e50358ee3c8ab89466b'){throw 'Canonical runtime01 hash mismatch'}
$inputs=[ordered]@{runtime=$runtime;bridge=(Join-Path $generated 'bridge/AllNativeCallbackBridge.cs');host=(Join-Path $PSScriptRoot 'GettextProbe.cs');builder=$PSCommandPath}
$before=[ordered]@{};foreach($key in $inputs.Keys){$before[$key]=(Get-FileHash -LiteralPath $inputs[$key] -Algorithm SHA256).Hash.ToLowerInvariant()}
[void][IO.Directory]::CreateDirectory($destination);[IO.File]::Copy($runtime,(Join-Path $destination 'AllPhp.ByteValues.Runtime.dll'))
$provider=New-Object Microsoft.CSharp.CSharpCodeProvider
$library=New-Object CodeDom.Compiler.CompilerParameters;$library.GenerateExecutable=$false;$library.GenerateInMemory=$false;$library.OutputAssembly=Join-Path $destination 'AllPhp.NativeGettext.Bridges.dll';$library.CompilerOptions='/platform:x64 /optimize+ /langversion:5'
foreach($assembly in @('System.dll','System.Core.dll',$runtime)){[void]$library.ReferencedAssemblies.Add($assembly)}
$result=$provider.CompileAssemblyFromFile($library,$inputs.bridge)
if($result.Errors.HasErrors){$result.Errors|ForEach-Object{[Console]::Error.WriteLine($_.ToString())};throw 'Gettext bridge compilation failed'}
$host=New-Object CodeDom.Compiler.CompilerParameters;$host.GenerateExecutable=$true;$host.GenerateInMemory=$false;$host.OutputAssembly=Join-Path $destination 'all-native-gettext-probe.exe';$host.CompilerOptions=$library.CompilerOptions
foreach($assembly in @('System.dll','System.Core.dll','System.Web.Extensions.dll',$runtime,$library.OutputAssembly)){[void]$host.ReferencedAssemblies.Add($assembly)}
$result=$provider.CompileAssemblyFromFile($host,$inputs.host)
if($result.Errors.HasErrors){$result.Errors|ForEach-Object{[Console]::Error.WriteLine($_.ToString())};throw 'Gettext host compilation failed'}
$after=[ordered]@{};foreach($key in $inputs.Keys){$after[$key]=(Get-FileHash -LiteralPath $inputs[$key] -Algorithm SHA256).Hash.ToLowerInvariant()}
$files=@(Get-ChildItem -LiteralPath $destination -File|ForEach-Object{[ordered]@{path=$_.Name;bytes=$_.Length;sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}})
$record=[ordered]@{status='BUILT_NOT_RUNTIME_VERIFIED';input_paths=$inputs;inputs_before=$before;inputs_after=$after;files=$files;powerShell=$PSVersionTable.PSVersion.ToString();clr=[Environment]::Version.ToString();pointer_bytes=[IntPtr]::Size;compiler_options=$library.CompilerOptions;extension_loaded=$false;stock_core_linked=$false}
[IO.File]::WriteAllText((Join-Path $destination 'build.json'),($record|ConvertTo-Json -Depth 8)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false));Write-Output ('Built '+$host.OutputAssembly)
