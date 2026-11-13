# Callback integration regression observations

**NOT_COMPLETE / NOT_ADOPTED.** The work is based on exact package v3.19 `113d0c2b...`, with its previous core repairs retained. The package, frozen core/bridge and original fixtures are unchanged.

| Measurement | Observation | Evidence |
| --- | --- | --- |
| Original native fixtures | 37 cases × 2 registration modes: **74/74 result records match** | `native-regression-run01/report.json` |
| Original scalar bridge contract | **24/24** | Same report and `scalar.json` |
| Original consistency criteria | **20/20**, with 4 thread records and registration metadata matched | Same report |
| Synthetic callback safety/output | **3/3 modes, 27/27 checks**; exact raw output | `contract3-run01/report.json` and each mode JSON |
| Existing default API subset | **73/73**, original expected values, process exit0 | `default73-revision02.json` and process record |
| First candidate on legacy NativeContext | **0/1**: missing SetDiagnosticHandler method | `legacy-before1/report.json` |
| First candidate callback source tests | **14/15**, one process timeout | `callback15-run01/report.json` |
| Revised candidate first callback run | **4/15**, all 11 differences are process timeouts | `callback15-revision02/report.json` |
| Revised candidate callback repetition | **15/15 exact match**, actual process exit0, unchanged inputs | `callback15-revision02-sequential-repeat/report.json` |
| Revised candidate first legacy profile run | **14/23**, 9 process timeouts; unsupported4 rejected before native invocation | `legacy27-revision02/report.json` |
| Revised candidate legacy repetition | **20/23**, 3 timeouts; 3/4 rejection guards met, one CLR exit escalation | `legacy27-revision02-sequential-repeat/report.json` |
| Diagnostic instrumented single run | **1/1**, process exit0, 14.75s, phases complete | `phase-trace1/report.json` |
| Diagnostic legacy guard trace | Expected engine rejection, actual exit1, 9.48s, phases complete | `legacy-guard-phase1/report.json` |
| Separate outer-Main host guard | Expected engine rejection, actual exit1, 10.40s | `managed-host-guard1/report.json` |
| Separate outer-Main host callback source | **15/15 exact match**, actual statuses, unchanged inputs | `managed-host-callback15/report.json` |
| Separate outer-Main host legacy source | **23/23 exact match**; unsupported4 rejected before invocation | `managed-host-legacy27/report.json` |

The original candidate's optional-interface defect was corrected only in separate `revision02`, SHA-256 `907171b658edb943a307f3dae32945a0105391f652fa477a4275b586385ce0bd`. Original candidates and failed runs were not overwritten. Native fixtures are compared by their original result/error/byte records; callback PHP source tests compare exact raw stdout/stderr and actual process status without normalization. Synthetic own-native probes are not counted as PHP compatibility cases.

The diagnostic phase run measured Add-Type around 2.15s, Run around 3.13s, followed by End, Shutdown, metadata and the exit call. No stall reproduced in that single run. It does not establish the cause of prior timeouts, nor a need to change the fixed compiler or timeout. Metadata exit values alone do not prove actual process exit. The uninstrumented callback repetition matched15/15 after the prior harnesses terminated, using the same source/candidate/core/bridge/worker and timeout30. It does not replace earlier timeout failures or establish a performance comparison with controlled host load.

The legacy repetition retained three timeouts and one actual exit code `2148732969` (`0x80131029`) on the installed-handler rejection guard. Microsoft's [official CLR code table](https://raw.githubusercontent.com/dotnet/coreclr/master/src/inc/corerror.xml) maps that numeric value to `HOST_E_EXITPROCESS_TIMEOUT`. This identifies the reported exit escalation, not its originating cause. A separate instrumented guard run subsequently completed its native request/module cleanup and actual exit1; the anomaly was not reproduced in that diagnostic run.

The separate `AllNativePhpHost.cs` copies the trusted worker logic but receives a returned `ExitCode` instead of calling `Environment.Exit` inside the PowerShell pipeline. Its outer Main disposes the runspace before returning the signed DWORD process status. It invokes the trusted worker file with `AddCommand`, preserving PSScriptRoot, and uses execution-policy Bypass in its initial runspace only. No system policy is changed. The first real guard run returned exit1 with native invocations0. The final new-host measurements matched callback15/15 and legacy23/23, with legacy guards4/4; each actual process ended within the unchanged30s guard. Candidate/core/bridge/extension/case hashes and PHP program bytes match the corresponding old-host inputs. The generated workers were verified to differ in text only at the final exit-to-return statement. This is a separate host implementation, not a retroactive reinterpretation of old timeouts or a controlled-load performance comparison.

The new-host build input hashes, generated workers and source are retained in `managed-host-build02/`. The actual executable remains locally in the ignored `tools/candidates/php-callback-v3_20/out/managed-host-02/` build directory; reproduction is source-based. [assessment.json](assessment.json) links the fixed evidence and retains every failed/timeout observation. Nothing here certifies original PowerShell-process shutdown as fixed or adopts the candidate into package.

The callback bridge restricts extension loading to the fixed dl_test binary. The `unsupported-load` record proves that profile rejection only, not a general native ABI missing-import rejection. Metadata property checks do not execute native property access. Controlled allocation/TLS counters are not a general memory-safety proof.

[Candidate implementation and reproduction](../../../tools/candidates/php-callback-v3_20/README.md). Full combined-package965, general ABI/value identity, arbitrary native modules/callables, lifecycle callbacks, Linux and all Web SAPIs remain required work.
