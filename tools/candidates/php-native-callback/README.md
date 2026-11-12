# Independent synchronous diagnostic callback prototype

2026-11-12. This is an option-A experiment. It is **not adopted into the package**. The frozen native core, managed bridge, native evaluator candidate, and package were not edited by this work.

`ALL_PHP_callback_candidate.ps1` is generated from frozen native candidate SHA-256 `47c8edb9e39bffe3ed5475f2aeed7e36673a798d2f72baf0cb60abc39695322d`. Its hash is `6ccacffa8b143f35a06c0213885f659773424ffc24bea62921de8e0c957437d2`. The generator validates the frozen input hash; `callback-context.patch` records its minimal evaluator changes. This candidate does not include the separate private-Throwable, native-redeclaration, or import-alias repairs being integrated by other agents.

The separate core is `native/php85abi-callback/src/Runtime.cpp`. `AllNativeCallbackBridge.cs` binds its ordinary-C exports. Native diagnostics synchronously enter the evaluator's existing `Write-PhpDiagnostic`; previously delivered events are excluded from later replay. A managed exception is caught inside the reverse delegate and stored in its invocation record. The callback returns an abort code, the own-native core throws/catches its own `CallbackAbort` within its native invocation, cleans up its frame/arguments, and returns. Only then does the managed bridge rethrow the saved exception. No managed/PowerShell exception is intentionally propagated through an unmanaged extension frame.

The core flushes pending native stdout once before the diagnostic callback. A transient-state guard preserves the outer native frame, return value, strictness, output, errors, and diagnostic events during reentry. Per-invocation managed records preserve nested exceptions. Callback registration owns one native thread and request generation. Managed and native invocation/lifecycle guards refuse another thread; teardown with a live lease is refused. Native lease acquisition uses atomic compare/exchange.

Any future adoption must port only the reviewed callback changes onto the integrated v3.19 package baseline identified by the parent as SHA-256 prefix `113d`, preserving its private-Throwable/import/redeclaration fixes. That combined revision must rerun the existing 74 native comparisons, 24 managed bridge contracts, all 965 package regressions, the CLI/native integration checks, and these callback experiments. None of that combined-revision validation is claimed by this prototype.

The managed prototype accepts **only the unchanged C `php_dl_test.dll` with SHA-256 `532b9f0944d482a704eb81ac1cb9af3b59aa0f54c753c53a5709c17f57d4e938`**. This is an executable scope restriction. The core itself remains a development DLL, not an unrestricted extension loader. Calling arbitrary exports or loading another DLL outside this managed host is outside this experiment.

From the repository root, with the pinned SDK ZIP and installed MSVC toolchain:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\native\php85abi-callback\Build-NativeAbi.ps1 -ReportDirectory .\reports\native-callback-20261112\rebuild-new
python .\tools\candidates\php-native-callback\Compare-CallbackPhp.py --output .\reports\native-callback-20261112\callback15-new
python .\tools\candidates\php-native-callback\Compare-CallbackContract.py --output .\reports\native-callback-20261112\control-contract-new
```

Choose fresh report directories. The comparison commands refuse to overwrite previous runs. Build outputs are ignored under `native/php85abi-callback/out/`; source, build logs, imports/exports, hashes, raw process evidence, and reports are retained. The build uses the SDK type/header contracts and MSVC runtime libraries, with no stock PHP import/forwarding. Stock `php.exe` is executed only in separate reference processes by `Compare-CallbackPhp.py`.

`callback-source.cases.json` contains the 15 fixed PHP sources. The harness compares exact stdout bytes, stderr bytes, and actual process exit without normalization. Each candidate child process loads the original extension and own core, executes the PHP source through the ALL evaluator, then records loaded module paths, input hashes, callback/native counters, and teardown state. This is a preloaded host profile; it does not implement ALL CLI extension flags.

`Compare-CallbackContract.py` is a separate synthetic own-native safety test. It is not evidence that the original extension implements its `N-before`/`N-after` probe. Its three modes verify byte order and absence of post-diagnostic work on abort, nested invocation, managed/raw-native wrong-thread rejection, live-lease teardown rejection, subsequent request usability, and balanced controlled counters.

Limits remain explicit:

- Windows x64 TS, the pinned C dl_test binary, selected scalar positional calls, and synchronous same-thread/request diagnostic callbacks only.
- C++ unwinding through the tested dl_test C frame is measured. Arbitrary extensions, `noexcept`/catch-all C++ frames, C extensions with unmanaged resources requiring other bailout contracts, asynchronous native callbacks, and process-fatal managed failures are unverified and unsupported.
- This is diagnostic-handler reentry, not arbitrary PHP callable invocation from native code. Reference/object/resource identity, populated arrays, named native arguments, arbitrary PHP byte strings, native return references, and standard object operations remain outside the bridge subset.
- Diagnostics outside an owned invoke are rejected by the callback path. General MINIT/RINIT/RSHUTDOWN/MSHUTDOWN callbacks and lifecycle output transport are not established; the tested dl_test has no relevant request hooks.
- The controlled allocation/TLS counters and child-process completion are not a general memory-safety proof. Linux and every Web/SAPI remain unverified here.
- The frozen runtime retains its prior safe rejection of native calls with a user error handler. No adoption decision or B/C execution-core migration is implied by passing this prototype.

See [the measurement report](../../../reports/native-callback-20261112/README.md) for fixed evidence and hashes.
