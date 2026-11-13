[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Utility\Microsoft.PowerShell.Utility.psd1') -ErrorAction Stop
if($PSVersionTable.PSEdition-ceq'Core'){throw 'Build with Windows PowerShell 5.1 for the existing .NET Framework runtime'}
$destination=[IO.Path]::GetFullPath($OutputDirectory)
if(Test-Path -LiteralPath $destination){throw 'Output exists; preserve prior builds and select a fresh directory'}
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).ProviderPath
$inputs=[ordered]@{
 host_source=(Join-Path $PSScriptRoot 'AllNativePhpHost.cs')
 callback_worker=(Join-Path $PSScriptRoot 'Invoke-CallbackPhpWorker.ps1')
 legacy_worker=(Join-Path $root 'tools\abi\Invoke-NativePhpWorker.ps1')
 callback_bridge=(Join-Path $PSScriptRoot 'AllNativeCallbackBridge.cs')
 legacy_bridge=(Join-Path $root 'tools\abi\AllNativeBridge.cs')
}
$before=[ordered]@{};foreach($name in $inputs.Keys){$before[$name]=(Get-FileHash -LiteralPath $inputs[$name] -Algorithm SHA256).Hash.ToLowerInvariant()}
[void][IO.Directory]::CreateDirectory($destination)
$provider=New-Object Microsoft.CSharp.CSharpCodeProvider
$parameters=New-Object CodeDom.Compiler.CompilerParameters
$parameters.GenerateExecutable=$true;$parameters.GenerateInMemory=$false
$parameters.OutputAssembly=Join-Path $destination 'all-native-php-host.exe'
$parameters.CompilerOptions='/platform:x64 /optimize+ /langversion:5'
foreach($assembly in @('System.dll','System.Core.dll',[Management.Automation.PSObject].Assembly.Location)){[void]$parameters.ReferencedAssemblies.Add($assembly)}
$compiled=$provider.CompileAssemblyFromFile($parameters,$inputs.host_source)
if($compiled.Errors.HasErrors){$compiled.Errors|ForEach-Object{[Console]::Error.WriteLine($_.ToString())};throw 'Native diagnostic host compilation failed'}
$utf8=New-Object Text.UTF8Encoding($false)
foreach($mode in @('callback','legacy')){
 $source=[IO.File]::ReadAllText($inputs[($mode+'_worker')])
 $needle='[Environment]::Exit($signed)'
 if(([regex]::Matches($source,[regex]::Escape($needle))).Count-ne1){throw 'Expected one final worker exit call'}
 $source=$source.Replace($needle,'[pscustomobject]@{ExitCode=[long]$status}')
 [IO.File]::WriteAllText((Join-Path $destination ($mode+'-return-worker.ps1')),$source,$utf8)
}
[IO.File]::Copy($inputs.callback_bridge,(Join-Path $destination 'AllNativeCallbackBridge.cs'))
[IO.File]::Copy($inputs.legacy_bridge,(Join-Path $destination 'AllNativeBridge.cs'))
$after=[ordered]@{};foreach($name in $inputs.Keys){$after[$name]=(Get-FileHash -LiteralPath $inputs[$name] -Algorithm SHA256).Hash.ToLowerInvariant()}
$files=@(Get-ChildItem -LiteralPath $destination -File|ForEach-Object{[ordered]@{path=$_.Name;bytes=$_.Length;sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}})
$record=[ordered]@{status='BUILT_NOT_RUNTIME_VERIFIED';scope='Own outer Main and returned worker status; no stock PHP invocation';powerShell=$PSVersionTable.PSVersion.ToString();architecture='x64';compiler_options=$parameters.CompilerOptions;inputs_before=$before;inputs_after=$after;files=$files;worker_change='Only final Environment.Exit replaced by returned ExitCode object; original source workers unchanged'}
[IO.File]::WriteAllText((Join-Path $destination 'build.json'),($record|ConvertTo-Json -Depth 8)+[Environment]::NewLine,$utf8)
Write-Output ('Built '+$parameters.OutputAssembly)
