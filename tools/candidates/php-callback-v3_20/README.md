# Callback integration onto package v3.19

**Independent candidate. Package adoption and PHP full compatibility are not complete.**

The original candidate `aae17c00835fe5dbb9d33e1baae8e6e71fdaf2f2ea01401145035378f930c7b3` was already present when this task resumed. It applies the callback prototype's minimal evaluator edits to exact package input `113d0c2b967a8726cd9a9dec3f032a725ed9c98ee093c4aedd0a4830737f155b`, retaining v3.19 private Throwable, import and function registration repairs. Existing processes were checked before starting fresh measurements; no existing run was restarted or overwritten.

That first candidate unconditionally called `NativeContext.SetDiagnosticHandler`. An actual legacy-host reproduction failed because the original bridge does not provide that optional method. The independent `revision02/` candidate fixes this boundary by checking Set/Clear methods before installing the callback. Older contexts retain deferred events and their prior installed-handler rejection. The original scalar unsupported diagnostic prefix is retained as well.

The revised candidate SHA-256 is **`907171b658edb943a307f3dae32945a0105391f652fa477a4275b586385ce0bd`**. `Build-CallbackCandidate.py` validates exact package input, refuses an existing measured candidate, and writes its patch/provenance into a fresh selected directory. It never writes package.

All runtime calls use the frozen own callback DLL `88117b8f38dc77d20e638ce573bb83fc6f959c1ad6821f8803c5499969fe234b` and copied managed bridge `8c37470ecafa4c00a41dbf8917295f88f76b7d2fbbd57645a91313bc833efda8`. No frozen native source, DLL, bridge, old fixture or expected value was changed. Stock PHP is executed only by separate reference workers.

Reproduction uses fresh output directories:

```powershell
python -B tools/candidates/php-callback-v3_20/Build-CallbackCandidate.py --output-directory tools/candidates/php-callback-v3_20/NEW_REVISION
python -B tools/candidates/php-callback-v3_20/Compare-NativeRegression.py --output reports/NEW-native-regression --timeout 30
python -B tools/candidates/php-callback-v3_20/Compare-CallbackPhp.py --adapter tools/candidates/php-callback-v3_20/revision02/ALL_PHP_v3_20_callback_candidate.ps1 --output reports/NEW-callback15 --timeout 30
python -B tools/candidates/php-callback-v3_20/Compare-CallbackContract.py --output reports/NEW-contract3
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/candidates/php-callback-v3_20/Build-NativePhpHost.ps1 -OutputDirectory tools/candidates/php-callback-v3_20/out/NEW_HOST
python -B tools/candidates/php-callback-v3_20/Compare-ManagedNativePhp.py --host tools/candidates/php-callback-v3_20/out/NEW_HOST/all-native-php-host.exe --mode callback --output reports/NEW-managed-callback15 --timeout 30
python -B tools/candidates/php-callback-v3_20/Compare-ManagedNativePhp.py --host tools/candidates/php-callback-v3_20/out/NEW_HOST/all-native-php-host.exe --mode legacy --output reports/NEW-managed-legacy27 --timeout 30
```

`Compare-NativeRegression.py` repeats the original 37 cases in each of normal/legacy registration modes (74 result comparisons), original scalar bridge checks and original consistency criteria. It retains separate process results and canonical byte/diagnostic records; those worker stdout messages are not raw PHP CLI source output comparisons. The unchanged unsupported-module probe is rejected by the callback bridge's pinned-dl_test profile restriction; this does not establish the OS loader's missing-symbol path.

`Invoke-CallbackPhpTraceWorker.ps1` is a separate diagnostic-only copy. Its sidecar phase events leave PHP source and stdout/stderr untouched, but the instrumented run is not silently substituted for an uninstrumented conformance run. Timeout observations are preserved as failures, even when metadata says an exit was requested.

`AllNativePhpHost.cs` is a separately measured host implementation that receives the worker's returned status, disposes its runspace, then returns the signed DWORD from Main. It does not call PHP or spawn a PHP process. Its generated trusted workers differ from the corresponding source workers only at the final exit-to-return statement; bridge sources and DLLs are unchanged. The final host matched callback15 and legacy23, with legacy4 explicit rejection guards. Original PowerShell-worker timeouts and one CLR exit escalation remain unresolved historical observations, not new-host PASS cases. `managed-host-build02/` under the report tree retains source/build/worker records; executable outputs are locally ignored.

See [measurements and limits](../../../reports/native-callback-integration-20261113/README.md). Windows x64 TS, the pinned C dl_test binary, synchronous same-thread diagnostic handlers and selected scalar positional values are the measured subset. Arbitrary C++/noexcept/async extensions, native-to-PHP arbitrary callable API, full references/objects/resources/arrays/byte strings, lifecycle callbacks, Linux and Web remain unverified or unsupported. Full965 on the final combined package is a separate required check.
