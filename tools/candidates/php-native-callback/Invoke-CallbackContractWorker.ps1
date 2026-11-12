[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Core,[Parameter(Mandatory=$true)][string]$Extension,[Parameter(Mandatory=$true)][string]$Output,[ValidateSet('continue','throw','reenter')][string]$Mode='continue')
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=New-Object Text.UTF8Encoding($false)
Add-Type -Path (Join-Path $PSScriptRoot 'AllNativeCallbackBridge.cs')
$bridge=New-Object AllPhp85AbiCallback.Bridge([IO.Path]::GetFullPath($Core))
$bridge.LoadExtension([IO.Path]::GetFullPath($Extension))
$loadedPhpModules=$bridge.LoadedPhpModules
$checks=[ordered]@{}
try{$bridge.SetDiagnosticHandler([Action[long,string]]{param($l,$m)});$checks.registration_requires_active_request=$false}catch{$checks.registration_requires_active_request=$true}
$bridge.Start();$firstRequest=$bridge.CurrentRequestId
$action=[Action[long,string]]{
 param([long]$level,[string]$message)
 [Console]::Write('H')
 if($Mode-ceq'throw'){throw [InvalidOperationException]::new('callback-contract-stop')}
 if($Mode-ceq'reenter'){$inner=$bridge.InvokeScalar('dl_test_test2',[object[]]@('inner'),$false);[Console]::Write([string]$inner.Value)}
}
$bridge.SetDiagnosticHandler($action)
$before=($bridge.Stats|ConvertFrom-Json).native_invocations
$wrongThread=$bridge.ProbeWrongThread()
$rawWrongThread=$bridge.ProbeRawWrongThread()
$leaseEnd=$bridge.ProbeRawEndWithLease()
$after=($bridge.Stats|ConvertFrom-Json).native_invocations
$checks.wrong_thread_rejected_before_invocation=($before-eq$after-and$wrongThread-like'Callback prototype rejects another thread/request*')
$checks.native_exports_reject_wrong_thread=(@($rawWrongThread|Where-Object{$_-notlike'-1:Callback prototype rejects another native thread before execution'}).Count-eq0-and$rawWrongThread.Count-eq5)
$checks.lease_blocks_request_teardown=($leaseEnd-ceq'-1:Clear callback lease before request teardown'-and$bridge.CurrentRequestId-eq$firstRequest)
$caught=$null
try{$bridge.CallbackContractProbe();[Console]::Write('E')}catch{$caught=$_.Exception.Message;[Console]::Write('Caught')}
$callbackStats=ConvertFrom-Json -InputObject $bridge.CallbackStats
$checks.callback_control_result=if($Mode-ceq'throw'){$null-ne$caught-and$caught.Contains('callback-contract-stop')-and$callbackStats.contract_after_diagnostic-eq0-and$callbackStats.aborts-eq1}else{$null-eq$caught-and$callbackStats.contract_after_diagnostic-eq1-and$callbackStats.aborts-eq0}
$checks.prefix_flushed_exact_byte_count=($callbackStats.flushed_output_bytes-eq8)
$bridge.ClearDiagnosticHandler();$bridge.End();$bridge.Start()
$checks.request_generation_advances=($bridge.CurrentRequestId-gt$firstRequest)
$recovery=$bridge.InvokeScalar('dl_test_test2',[object[]]@('recovered'),$false)
$checks.request_after_abort_or_callback_usable=($recovery.Ok-and$recovery.Value-ceq'Hello recovered')
$bridge.End();$bridge.Shutdown()
$stats=ConvertFrom-Json -InputObject $bridge.Stats
$checks.request_teardown_balanced=($stats.rinit-eq$stats.rshutdown-and$stats.request_allocations_live-eq0-and$stats.tls_contexts_created-eq$stats.tls_contexts_destroyed)
$record=[ordered]@{status=if(@($checks.Values|Where-Object{-not$_}).Count-eq0){'PASS'}else{'FAIL'};scope='synthetic owned-native control/output contract; not a PHP compatibility comparison';mode=$Mode;checks=$checks;caught=$caught;raw_wrong_thread=$rawWrongThread;raw_end_with_lease=$leaseEnd;callback_stats=$callbackStats;native_stats=$stats;core_path=$bridge.CorePath;loaded_php_modules=$loadedPhpModules}
$utf8=New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText([IO.Path]::GetFullPath($Output),($record|ConvertTo-Json -Depth 9)+[Environment]::NewLine,$utf8)
if($record.status-cne'PASS'){exit 1}
