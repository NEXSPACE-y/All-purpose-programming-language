[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Utility\Microsoft.PowerShell.Utility.psd1') -ErrorAction Stop
if($PSVersionTable.PSEdition-ceq'Core'){throw 'Use Windows PowerShell5.1 and its existing Framework compiler'}
$destination=[IO.Path]::GetFullPath($OutputDirectory)
if(Test-Path -LiteralPath $destination){throw 'Preserve previous host output; choose a fresh directory'}
$paths=[ordered]@{host=(Join-Path $PSScriptRoot 'AllByteNativePhpHost.cs');worker=(Join-Path $PSScriptRoot 'Invoke-ByteNativeWorker.ps1');build=$PSCommandPath}
$before=[ordered]@{};foreach($key in $paths.Keys){$before[$key]=(Get-FileHash -LiteralPath $paths[$key] -Algorithm SHA256).Hash.ToLowerInvariant()}
[void][IO.Directory]::CreateDirectory($destination)
$provider=New-Object Microsoft.CSharp.CSharpCodeProvider
$parameters=New-Object CodeDom.Compiler.CompilerParameters
$parameters.GenerateExecutable=$true;$parameters.GenerateInMemory=$false;$parameters.OutputAssembly=Join-Path $destination 'all-byte-native-php-host.exe';$parameters.CompilerOptions='/platform:x64 /optimize+ /langversion:5'
foreach($assembly in @('System.dll','System.Core.dll',[Management.Automation.PSObject].Assembly.Location)){[void]$parameters.ReferencedAssemblies.Add($assembly)}
$compiled=$provider.CompileAssemblyFromFile($parameters,$paths.host)
if($compiled.Errors.HasErrors){$compiled.Errors|ForEach-Object{[Console]::Error.WriteLine($_.ToString())};throw 'Byte native source host build failed'}
[IO.File]::Copy($paths.worker,(Join-Path $destination 'byte-return-worker.ps1'))
$after=[ordered]@{};foreach($key in $paths.Keys){$after[$key]=(Get-FileHash -LiteralPath $paths[$key] -Algorithm SHA256).Hash.ToLowerInvariant()}
$files=@(Get-ChildItem -LiteralPath $destination -File|ForEach-Object{[ordered]@{path=$_.Name;bytes=$_.Length;sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}})
$record=[ordered]@{status='BUILT_NOT_RUNTIME_VERIFIED';input_paths=$paths;inputs_before=$before;inputs_after=$after;files=$files;powerShell=$PSVersionTable.PSVersion.ToString();clr=[Environment]::Version.ToString();pointer_bytes=[IntPtr]::Size;compiler_options=$parameters.CompilerOptions;host_exit='Return signed DWORD from outer Main after disposing PowerShell and Runspace; no Environment.Exit';runtime_load='Canonical original runtime first, byte bridge assembly second'}
[IO.File]::WriteAllText((Join-Path $destination 'build.json'),($record|ConvertTo-Json -Depth 8)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
Write-Output ('Built '+$parameters.OutputAssembly)
