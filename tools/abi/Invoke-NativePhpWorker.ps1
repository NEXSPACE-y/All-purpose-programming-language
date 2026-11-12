# Actual PHP source execution through the isolated ALL evaluator + owned native ABI.
[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][string]$AdapterPath,
 [Parameter(Mandatory=$true)][string]$SourcePath,
 [Parameter(Mandatory=$true)][string]$CorePath,
 [Parameter(Mandatory=$true)][string]$ExtensionPath,
 [Parameter(Mandatory=$true)][string]$MetadataPath,
 [Parameter(Mandatory=$true)][string]$ExpectedCoreHash
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Utility\Microsoft.PowerShell.Utility.psd1') -ErrorAction Stop
[Console]::OutputEncoding=New-Object Text.UTF8Encoding($false)
[Console]::InputEncoding=New-Object Text.UTF8Encoding($false)
$utf8=New-Object Text.UTF8Encoding($false)
$bridge=$null;$started=$false;$status=[long]1;$failure=$null;$unsupported=$false;$pipelineCount=0
$metadata=[ordered]@{method='actual_ALL_evaluator_source_execution_preloaded_native_profile';native_context_parameter_verified=$false;failure=$null;native_unsupported=$false}
try {
 $source=(Resolve-Path -LiteralPath $SourcePath).ProviderPath
 $adapterFile=(Resolve-Path -LiteralPath $AdapterPath).ProviderPath
 $core=(Resolve-Path -LiteralPath $CorePath).ProviderPath
 $extension=(Resolve-Path -LiteralPath $ExtensionPath).ProviderPath
 $coreHash=(Get-FileHash -LiteralPath $core -Algorithm SHA256).Hash.ToLowerInvariant()
 if($coreHash-cne$ExpectedCoreHash.ToLowerInvariant()){throw 'Native core hash differs from the selected build'}
 $metadata.inputs_before=[ordered]@{source=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash;adapter=(Get-FileHash -LiteralPath $adapterFile -Algorithm SHA256).Hash;core=$coreHash;extension=(Get-FileHash -LiteralPath $extension -Algorithm SHA256).Hash}
 $adapter=& $adapterFile
 if($null-eq$adapter-or$adapter.Run-isnot[scriptblock]){throw 'Candidate did not return a Run scriptblock'}
 $names=@($adapter.Run.Ast.ParamBlock.Parameters|ForEach-Object{$_.Name.VariablePath.UserPath})
 if($names-notcontains'NativeContext'){throw 'Candidate Run has no declared NativeContext parameter; refusing silently ignored PowerShell arguments'}
 if($names-notcontains'CliContext'){throw 'Candidate Run has no declared CliContext parameter'}
 $metadata.native_context_parameter_verified=$true
 Add-Type -Path (Join-Path $PSScriptRoot 'AllNativeBridge.cs')
 $bridge=New-Object AllPhp85Abi.Bridge($core)
 $bridge.LoadExtension($extension)
 $metadata.core_path=$bridge.CorePath
 $metadata.loaded_php_modules=$bridge.LoadedPhpModules
 $metadata.function_catalog=ConvertFrom-Json -InputObject $bridge.FunctionCatalog
 $code=[IO.File]::ReadAllText($source,(New-Object Text.UTF8Encoding($false,$true)))
 $context=@{SourcePath=$source;ExitCode=[long]0;Terminated=$false}
 $bridge.Start();$started=$true
 try {
  $pipeline=@(& ($adapter.Run) -Code $code -CliContext $context -NativeContext $bridge)
  $pipelineCount=$pipeline.Count
  if($pipelineCount-ne0){throw 'Evaluator leaked unexpected host pipeline objects'}
 } finally {
  if($started){$bridge.End();$started=$false}
 }
 $status=[long]$context.ExitCode
 $metadata.cli_context=$context
} catch {
 $failure=$_.Exception.Message
 $exception=$_.Exception
 while($null-ne$exception){if($exception.Data.Contains('AllPhpNativeUnsupported')){$unsupported=$true};$exception=$exception.InnerException}
 [Console]::Error.WriteLine($failure)
 $status=[long]1
} finally {
 if($null-ne$bridge){
  try{if($started){$bridge.End();$started=$false};$bridge.Shutdown();$metadata.native_stats=ConvertFrom-Json -InputObject $bridge.Stats}
  catch{if($null-eq$failure){$failure=$_.Exception.Message;[Console]::Error.WriteLine($failure);$status=[long]1}}
 }
 $metadata.failure=$failure;$metadata.native_unsupported=$unsupported;$metadata.pipeline_count=$pipelineCount;$metadata.exit_code=$status
 if($metadata.Contains('inputs_before')){
  $metadata.inputs_after=[ordered]@{source=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash;adapter=(Get-FileHash -LiteralPath $adapterFile -Algorithm SHA256).Hash;core=(Get-FileHash -LiteralPath $core -Algorithm SHA256).Hash.ToLowerInvariant();extension=(Get-FileHash -LiteralPath $extension -Algorithm SHA256).Hash}
 }
 [IO.File]::WriteAllText([IO.Path]::GetFullPath($MetadataPath),($metadata|ConvertTo-Json -Depth 12)+[Environment]::NewLine,$utf8)
}
$bits=[uint32]$status
$signed=[BitConverter]::ToInt32([BitConverter]::GetBytes($bits),0)
[Environment]::Exit($signed)
