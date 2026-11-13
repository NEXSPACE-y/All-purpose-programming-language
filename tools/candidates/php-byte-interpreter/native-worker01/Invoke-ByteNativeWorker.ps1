[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][ValidateSet('callback','legacy')][string]$Mode,
 [Parameter(Mandatory=$true)][string]$AdapterPath,
 [Parameter(Mandatory=$true)][string]$SourcePath,
 [Parameter(Mandatory=$true)][string]$CorePath,
 [Parameter(Mandatory=$true)][string]$ExtensionPath,
 [Parameter(Mandatory=$true)][string]$MetadataPath,
 [Parameter(Mandatory=$true)][string]$ExpectedCoreHash,
 [Parameter(Mandatory=$true)][string]$RuntimePath,
 [Parameter(Mandatory=$true)][string]$BridgePath,
 [Parameter(Mandatory=$true)][string]$ExpectedRuntimeHash,
 [Parameter(Mandatory=$true)][string]$ExpectedBridgeHash,
 [Parameter(Mandatory=$true)][string]$ExpectedAdapterHash
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Utility\Microsoft.PowerShell.Utility.psd1') -ErrorAction Stop
$utf8=New-Object Text.UTF8Encoding($false)
function Write-Phase([string]$phase){
 $item=[ordered]@{phase=$phase;utc=[DateTime]::UtcNow.ToString('o');pid=$PID;managed_thread=[Threading.Thread]::CurrentThread.ManagedThreadId}
 [IO.File]::AppendAllText(([IO.Path]::GetFullPath($MetadataPath)+'.phases.jsonl'),(($item|ConvertTo-Json -Compress)+[Environment]::NewLine),$utf8)
}
function Get-InputHashes($paths){
 $hashes=[ordered]@{};foreach($key in $paths.Keys){$hashes[$key]=(Get-FileHash -LiteralPath $paths[$key] -Algorithm SHA256).Hash.ToLowerInvariant()};return ,$hashes
}
Write-Phase 'worker-entered'
$bridge=$null;$started=$false;$status=[long]1;$failure=$null;$unsupported=$false;$pipelineCount=0
$metadata=[ordered]@{method='actual_ALL_source_byte_native_bridge_outer_Main';mode=$Mode;native_context_parameter_verified=$false;failure=$null;native_unsupported=$false;powerShell=$PSVersionTable.PSVersion.ToString();clr=[Environment]::Version.ToString();pid=$PID}
try {
 $paths=[ordered]@{
  source=(Resolve-Path -LiteralPath $SourcePath).ProviderPath
  adapter=(Resolve-Path -LiteralPath $AdapterPath).ProviderPath
  core=(Resolve-Path -LiteralPath $CorePath).ProviderPath
  extension=(Resolve-Path -LiteralPath $ExtensionPath).ProviderPath
  runtime=(Resolve-Path -LiteralPath $RuntimePath).ProviderPath
  bridge=(Resolve-Path -LiteralPath $BridgePath).ProviderPath
  worker=$PSCommandPath
  host=([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
 }
 $metadata.inputs_before=Get-InputHashes $paths
 foreach($pin in @(@('core',$ExpectedCoreHash),@('runtime',$ExpectedRuntimeHash),@('bridge',$ExpectedBridgeHash),@('adapter',$ExpectedAdapterHash))){if($metadata.inputs_before[$pin[0]]-cne$pin[1].ToLowerInvariant()){throw ('Selected '+$pin[0]+' hash mismatch')}}
 # Preload the canonical original assembly before the bridge can resolve its
 # dependency from a sibling build-output copy with the same assembly identity.
 Write-Phase 'before-canonical-runtime-load'
 $already='AllPhp.ByteValues.PhpBytes'-as[type]
 if($null-ne$already-and-not[string]::Equals([IO.Path]::GetFullPath($already.Assembly.Location),$paths.runtime,[StringComparison]::OrdinalIgnoreCase)){throw 'Byte runtime was preloaded from another location'}
 [void][Reflection.Assembly]::LoadFrom($paths.runtime)
 $byteType='AllPhp.ByteValues.PhpBytes'-as[type]
 if($null-eq$byteType-or-not[string]::Equals([IO.Path]::GetFullPath($byteType.Assembly.Location),$paths.runtime,[StringComparison]::OrdinalIgnoreCase)){throw 'Canonical byte runtime did not load from its selected original path'}
 $metadata.runtime_assembly_location=$byteType.Assembly.Location
 Write-Phase 'after-canonical-runtime-load'
 [void][Reflection.Assembly]::LoadFrom($paths.bridge)
 $typeName=if($Mode-ceq'callback'){'AllPhp85AbiCallbackByte.Bridge'}else{'AllPhp85AbiByte.Bridge'}
 $bridgeType=$typeName-as[type]
 if($null-eq$bridgeType){throw 'Selected byte bridge type was not loaded'}
 $metadata.bridge_assembly_location=$bridgeType.Assembly.Location
 Write-Phase 'after-byte-bridge-load'
 $adapter=& $paths.adapter
 if($null-eq$adapter-or$adapter.Run-isnot[scriptblock]){throw 'Candidate did not return a Run scriptblock'}
 $names=@($adapter.Run.Ast.ParamBlock.Parameters|ForEach-Object{$_.Name.VariablePath.UserPath})
 if($names-notcontains'NativeContext'-or$names-notcontains'CliContext'){throw 'Candidate lacks explicit NativeContext/CliContext parameters'}
 $metadata.native_context_parameter_verified=$true
 $bridge=[Activator]::CreateInstance($bridgeType,[object[]]@($paths.core))
 $bridge.LoadExtension($paths.extension)
 $metadata.core_path=$bridge.CorePath;$metadata.loaded_php_modules=$bridge.LoadedPhpModules
 $metadata.function_catalog=ConvertFrom-Json -InputObject $bridge.FunctionCatalog
 $code=[IO.File]::ReadAllText($paths.source,(New-Object Text.UTF8Encoding($false,$true)))
 $context=@{SourcePath=$paths.source;ExitCode=[long]0;Terminated=$false}
 Write-Phase 'before-native-start'
 $bridge.Start();$started=$true
 try {
  Write-Phase 'before-evaluator-run'
  $pipeline=@(& ($adapter.Run) -Code $code -CliContext $context -NativeContext $bridge)
  Write-Phase 'after-evaluator-run'
  $pipelineCount=$pipeline.Count
  if($pipelineCount-ne0){throw 'Evaluator leaked unexpected host pipeline objects'}
 } finally {
  if($started){Write-Phase 'before-native-end';$bridge.End();$started=$false;Write-Phase 'after-native-end'}
 }
 $status=[long]$context.ExitCode;$metadata.cli_context=$context
} catch {
 $failure=$_.Exception.Message;$exception=$_.Exception
 while($null-ne$exception){
  if($exception.Data.Contains('AllPhpNativeUnsupported')){$unsupported=$true}
  if($exception.Data.Contains('AllPhpNativeUnsupportedBytes')){$metadata.native_unsupported_message_base64=$exception.Data['AllPhpNativeUnsupportedBytes'].ToBase64()}
  $exception=$exception.InnerException
 }
 [Console]::Error.WriteLine($failure);$status=[long]1
} finally {
 if($null-ne$bridge){
  try{if($started){$bridge.End();$started=$false};Write-Phase 'before-native-shutdown';$bridge.Shutdown();Write-Phase 'after-native-shutdown';$metadata.native_stats=ConvertFrom-Json -InputObject $bridge.Stats;if($Mode-ceq'callback'){$metadata.callback_stats=ConvertFrom-Json -InputObject $bridge.CallbackStats}}
  catch{if($null-eq$failure){$failure=$_.Exception.Message;[Console]::Error.WriteLine($failure);$status=[long]1}}
 }
 $metadata.failure=$failure;$metadata.native_unsupported=$unsupported;$metadata.pipeline_count=$pipelineCount;$metadata.exit_code=$status
 if($metadata.Contains('inputs_before')){$metadata.inputs_after=Get-InputHashes $paths}
 Write-Phase 'before-metadata-write'
 [IO.File]::WriteAllText([IO.Path]::GetFullPath($MetadataPath),($metadata|ConvertTo-Json -Depth 14)+[Environment]::NewLine,$utf8)
 Write-Phase 'worker-returned-status'
}
[pscustomobject]@{ExitCode=[long]$status}
