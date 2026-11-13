[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$AdapterPath,[Parameter(Mandatory=$true)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Utility\Microsoft.PowerShell.Utility.psd1') -ErrorAction Stop
if($PSVersionTable.PSEdition-ceq'Core'){throw 'Build using Windows PowerShell 5.1 for the existing .NET Framework host'}
$destination=[IO.Path]::GetFullPath($OutputDirectory)
if(Test-Path -LiteralPath $destination){throw 'Output directory exists; choose a fresh build directory'}
$adapterFile=(Resolve-Path -LiteralPath $AdapterPath).ProviderPath
$adapterHash=(Get-FileHash -LiteralPath $adapterFile -Algorithm SHA256).Hash.ToLowerInvariant()
[void][IO.Directory]::CreateDirectory($destination)
$provider=New-Object Microsoft.CSharp.CSharpCodeProvider
$parameters=New-Object CodeDom.Compiler.CompilerParameters
$parameters.GenerateExecutable=$true;$parameters.GenerateInMemory=$false
$parameters.OutputAssembly=Join-Path $destination 'all-php.exe'
$parameters.CompilerOptions='/platform:x64 /optimize+ /langversion:5'
[void]$parameters.ReferencedAssemblies.Add('System.dll')
[void]$parameters.ReferencedAssemblies.Add('System.Core.dll')
[void]$parameters.ReferencedAssemblies.Add([Management.Automation.PSObject].Assembly.Location)
$compilation=$provider.CompileAssemblyFromFile($parameters,(Join-Path $PSScriptRoot 'AllPhpCli.cs'))
if($compilation.Errors.HasErrors){$compilation.Errors|ForEach-Object{[Console]::Error.WriteLine($_.ToString())};throw 'ALL PHP CLI compile failed'}
[IO.File]::Copy($adapterFile,(Join-Path $destination 'ALL_PHP_adapter.ps1'))
[IO.File]::Copy((Join-Path $PSScriptRoot 'AllPhpCli.ps1'),(Join-Path $destination 'AllPhpCli.ps1'))
$files=@(Get-ChildItem -LiteralPath $destination -File|ForEach-Object{[ordered]@{path=$_.Name;bytes=$_.Length;sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}})
$record=[ordered]@{status='BUILT_NOT_RUNTIME_VERIFIED';powerShell=$PSVersionTable.PSVersion.ToString();architecture='x64';adapter_source=$adapterFile;adapter_sha256=$adapterHash;stock_php_execution_delegation=$false;files=$files;source_sha256=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'AllPhpCli.cs') -Algorithm SHA256).Hash.ToLowerInvariant();build_script_sha256=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant();compiler_options=$parameters.CompilerOptions;automation_assembly=[Management.Automation.PSObject].Assembly.Location}
[IO.File]::WriteAllText((Join-Path $destination 'build.json'),($record|ConvertTo-Json -Depth 6)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
Write-Output ('Built '+$parameters.OutputAssembly)
