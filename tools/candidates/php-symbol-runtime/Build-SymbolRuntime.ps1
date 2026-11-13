[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ByteRuntimePath,
    [Parameter(Mandatory=$true)][string]$ByteRuntimeSha256,
    [Parameter(Mandatory=$true)][string]$OutputDirectory
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Utility\Microsoft.PowerShell.Utility.psd1') -ErrorAction Stop
if($PSVersionTable.PSEdition-ceq'Core'){throw 'Use existing Windows PowerShell 5.1 for this framework component build'}
$dependency=[IO.Path]::GetFullPath($ByteRuntimePath)
if((Get-FileHash -LiteralPath $dependency -Algorithm SHA256).Hash.ToLowerInvariant()-cne$ByteRuntimeSha256.ToLowerInvariant()){throw 'Canonical byte runtime hash mismatch'}
$destination=[IO.Path]::GetFullPath($OutputDirectory)
if(Test-Path -LiteralPath $destination){throw 'Preserve prior builds; choose a fresh output directory'}
[void][IO.Directory]::CreateDirectory($destination)
$source=Join-Path $PSScriptRoot 'PhpSymbolKey.cs'
$snapshot=Join-Path $destination 'PhpSymbolKey.source.cs'
[IO.File]::Copy($source,$snapshot,$false)
$provider=New-Object Microsoft.CSharp.CSharpCodeProvider
$parameters=New-Object CodeDom.Compiler.CompilerParameters
$parameters.GenerateExecutable=$false;$parameters.GenerateInMemory=$false
$parameters.OutputAssembly=Join-Path $destination 'AllPhp.Symbols.Runtime.dll'
$parameters.CompilerOptions='/platform:x64 /optimize+ /langversion:5'
[void]$parameters.ReferencedAssemblies.Add('System.dll');[void]$parameters.ReferencedAssemblies.Add('System.Core.dll')
[void]$parameters.ReferencedAssemblies.Add($dependency)
$result=$provider.CompileAssemblyFromFile($parameters,$snapshot)
if($result.Errors.HasErrors){$result.Errors|ForEach-Object{[Console]::Error.WriteLine($_.ToString())};throw 'Symbol candidate compilation failed'}
$record=[ordered]@{status='BUILT_NOT_RUNTIME_VERIFIED';source=$source;source_sha256=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant();source_snapshot=$snapshot;dependency=$dependency;dependency_sha256=(Get-FileHash -LiteralPath $dependency -Algorithm SHA256).Hash.ToLowerInvariant();dll=$parameters.OutputAssembly;dll_sha256=(Get-FileHash -LiteralPath $parameters.OutputAssembly -Algorithm SHA256).Hash.ToLowerInvariant();powerShell=$PSVersionTable.PSVersion.ToString();clr=[Environment]::Version.ToString();pointer_bytes=[IntPtr]::Size;compiler_options=$parameters.CompilerOptions}
[IO.File]::WriteAllText((Join-Path $destination 'build.json'),($record|ConvertTo-Json -Depth 5)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
Write-Output ('Built '+$parameters.OutputAssembly)
