[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ManagedBuildDirectory,[Parameter(Mandatory=$true)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Utility\Microsoft.PowerShell.Utility.psd1') -ErrorAction Stop
if($PSVersionTable.PSEdition-ceq'Core'){throw 'Use Windows PowerShell5.1 existing compiler'}
$inputBuild=(Resolve-Path -LiteralPath $ManagedBuildDirectory).ProviderPath;$destination=[IO.Path]::GetFullPath($OutputDirectory)
if(Test-Path -LiteralPath $destination){throw 'Keep old getter host; choose fresh output'}
$paths=[ordered]@{source=(Join-Path $PSScriptRoot 'GetterContractHost.cs');runtime=(Join-Path $inputBuild 'AllPhp.ByteValues.Runtime.dll');bridge=(Join-Path $inputBuild 'AllPhp.NativeBytes.Bridges.dll');build=$PSCommandPath}
$before=[ordered]@{};foreach($key in $paths.Keys){$before[$key]=(Get-FileHash -LiteralPath $paths[$key] -Algorithm SHA256).Hash.ToLowerInvariant()}
[void][IO.Directory]::CreateDirectory($destination)
foreach($key in @('runtime','bridge')){[IO.File]::Copy($paths[$key],(Join-Path $destination ([IO.Path]::GetFileName($paths[$key]))))}
$provider=New-Object Microsoft.CSharp.CSharpCodeProvider;$parameters=New-Object CodeDom.Compiler.CompilerParameters
$parameters.GenerateExecutable=$true;$parameters.GenerateInMemory=$false;$parameters.OutputAssembly=Join-Path $destination 'getter-contract.exe';$parameters.CompilerOptions='/platform:x64 /optimize+ /langversion:5'
foreach($assembly in @('System.dll','System.Core.dll','System.Web.Extensions.dll',$paths.runtime,$paths.bridge)){[void]$parameters.ReferencedAssemblies.Add($assembly)}
$compiled=$provider.CompileAssemblyFromFile($parameters,$paths.source)
if($compiled.Errors.HasErrors){$compiled.Errors|ForEach-Object{[Console]::Error.WriteLine($_.ToString())};throw 'Getter contract host build failed'}
$after=[ordered]@{};foreach($key in $paths.Keys){$after[$key]=(Get-FileHash -LiteralPath $paths[$key] -Algorithm SHA256).Hash.ToLowerInvariant()}
$files=@(Get-ChildItem -LiteralPath $destination -File|ForEach-Object{[ordered]@{path=$_.Name;bytes=$_.Length;sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}})
$record=[ordered]@{status='BUILT_NOT_RUNTIME_VERIFIED';input_paths=$paths;inputs_before=$before;inputs_after=$after;files=$files;powerShell=$PSVersionTable.PSVersion.ToString();compiler_options=$parameters.CompilerOptions;scope='Synthetic getter contract, test-only own DLL; production source getter/copy unchanged'}
[IO.File]::WriteAllText((Join-Path $destination 'build.json'),($record|ConvertTo-Json -Depth 8)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false));Write-Output ('Built '+$parameters.OutputAssembly)
