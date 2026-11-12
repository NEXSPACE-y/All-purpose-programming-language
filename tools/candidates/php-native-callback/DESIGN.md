# Synchronous native diagnostic callback prototype

2026-11-12. **Independent prototype, not adopted into the frozen runtime/package.**

The frozen runtime's `diagnostic()` stores TLS events; its managed bridge reads them after the native function returns. That supports ordinary reporting but cannot implement a PHP handler that throws or changes state before the native function continues. The frozen evaluator therefore continues to reject native calls with installed user handlers.

This separate option-A prototype adds a request/thread-owned diagnostic callback and output sink. The reverse P/Invoke delegate catches managed/PowerShell exceptions and stores the original exception in its managed invocation record. It returns an abort result. Only then does ALL-owned C++ throw its own `CallbackAbort`, catch it at the owned invocation boundary, release temporary values/frame state, and return to managed code. The saved managed exception is rethrown only after that native boundary has fully returned.

The PowerShell callback invokes the existing `Write-PhpDiagnostic` synchronously. Its current handler true/false, error_reporting, suppression and `InErrorHandler` logic remain responsible for PHP reporting. Delivered events are marked so they are not replayed after return. Native output pending before the diagnostic is flushed once before entering the PHP handler.

Reentrant native calls from a handler require preservation of the outer call's current frame, strict flag, return zval, errors, output and diagnostic records. A native transient-state guard saves and restores those fields around the managed callback. Global/request state such as INI changes is deliberately not rolled back.

Registration binds the native and managed owning thread and active request generation. Calls or registration from another thread/request are rejected before native function execution. The experimental host accepts only the pinned original C `php_dl_test.dll` hash. C++ unwinding across its actual native C frame is to be measured; this does not establish safety for arbitrary C++ extensions with catch-all/noexcept boundaries or asynchronous native threads.

The initial same-source measurement passed all 15 cases: handler true/false; handler throw with native work after the diagnostic absent; reporting/suppression; handler native reentry and recursive diagnostic handling; handler replacement and exit. A separate synthetic own-native probe passed output/side-effect ordering and abort/reentry checks. The final guarded revision additionally measures direct raw-native wrong-thread invoke/start/end/clear/shutdown rejection and live-lease teardown refusal. Exact final evidence is linked in [the report](../../../reports/native-callback-20261112/README.md).

Any unmeasured or failing path remains unsupported. No official runtime delegation, PHP `.c` reuse, broad execution-core migration, or frozen artefact edits are authorised by this prototype. Passing this isolated experiment does not change the package's safe rejection or approve adopting it.
