# Synchronous native diagnostic callbacks: fixed prototype evidence

2026-11-12. **Experimental subset measured; package adoption and full PHP compatibility are not complete.** All changes are confined to `native/php85abi-callback/`, `tools/candidates/php-native-callback/`, and this report tree. The original native core source/DLL, managed bridge, and frozen `47c8ed...` candidate retain their recorded hashes.

| Evidence | Result | Scope |
| --- | --- | --- |
| [Final same-source comparison](callback15-final/report.json) | 15/15 exact stdout/stderr/actual process exit | Actual ALL PHP evaluator + own core + unchanged original dl_test; separate stock PHP reference processes |
| [Final synthetic native contracts](control-contract-final/report.json) | 3/3 modes; 27/27 checks | Own-native safety/output probe; not PHP compatibility cases |
| [Final build](build-final/build.json) | Compiled/linked; stock PHP import absent | Windows x64 TS; runtime results are the separate rows above |
| [Final verification and hashes](final-verification.json) | Measured inputs stable; four frozen artifacts unchanged | Source/DLL/bridge/candidate pins, per-case counters and limits |
| [Supplementary private-candidate regression](private-regression/report.json) | 23/23 exact; 4/4 explicit unsupported guards | Sibling's frozen `2527cadd...` candidate and original native harness; not callback prototype evidence |

The 15 fixed PHP sources cover no handler, handler true/false/throw, `error_reporting(0)` with/without a handler, `@` with true/false, handler mask mismatch, native reentry, recursive diagnostics, a reentrant TypeError caught by the handler or escaping it, handler restoration, and handler `exit(7)`. Every candidate run records only the selected own `php8ts.dll` plus the original extension in loaded PHP modules. All input hashes stayed unchanged; controlled request/TLS counters balance, tracked request allocations are zero, and the callback lease is released after every case.

The real original extension's post-diagnostic `zend_strpprintf` call occurs once on ordinary return and zero times when the handler throws, an inner TypeError escapes, or the handler exits. Those three cases each record one own-native abort, proving the callback changes execution before the native function continues. The saved PHP throwable is rethrown after the P/Invoke return and is caught by PHP source where requested. Output and errors match the separate reference exactly.

The synthetic contract deliberately emits a native prefix before its diagnostic. Raw outputs are `N-beforeHN-afterE` (continue), `N-beforeHCaught` (throw), and `N-beforeHHello innerN-afterE` (reentry), with empty stderr and exit zero. The prefix flush is exactly eight bytes. On throw, the post-diagnostic side-effect counter stays zero. These strings are an own-native safety contract, not source taken from or behavioral claims about the extension.

The contract also directly calls native exports from another OS thread, bypassing managed guards: invoke, request start/end, callback clear, and shutdown all return `-1` before execution; native invocation counts do not increase. Same-thread request teardown while the callback lease is live is refused and the request ID remains unchanged. After explicit clearing/teardown, a new request gets a higher generation and successfully calls the unchanged extension. These guards prevent a lease surviving a legitimate request transition; deliberately corrupting TLS/request IDs was not tested.

The managed reverse delegates catch ordinary managed/PowerShell exceptions, save them in a nested invocation record, and return an abort result. The own core then throws/catches only its own C++ `CallbackAbort` within its native invocation and cleans up its argument/frame state. The original managed exception is rethrown after the native return. The output and diagnostic delegates both validate thread/request ownership and lease cookie; callback acquisition is atomic. No stock PHP execution core is linked, forwarded, or loaded in candidate processes, and no PHP `.c` implementations were copied.

The executable host accepts only extension hash `532b9f0944d482a704eb81ac1cb9af3b59aa0f54c753c53a5709c17f57d4e938`. Unwinding through that C DLL on this machine is measured. This does not establish compatibility or safety for arbitrary C++/`noexcept`/catch-all extension frames, unmanaged extension resources requiring a different bailout protocol, asynchronous callbacks, or process-fatal managed exceptions. This prototype is diagnostic-handler reentry, not a general native-to-PHP callable API. General lifecycle diagnostics/output, non-scalar/reference/object/resource identities, arbitrary binary strings, named native arguments, Linux, and Web/SAPI remain unverified or explicitly unsupported. Controlled counters are not a general memory-safety proof.

The frozen core/bridge/candidate and package were not changed here. Their existing safe user-handler rejection is retained. This prototype has not been adopted, and no B/C core migration is approved or performed.

The prototype evaluator is based on `47c8ed...`, not the integrated v3.19 package (`113d...` baseline). It does not include v3.19's private-Throwable/import/redeclaration fixes. Future adoption requires a reviewed minimal integration onto that newer baseline and renewed 74 native comparisons, 24 bridge contracts, all 965 package regressions, CLI/native integration checks, and callback measurements. Those combined-revision checks have not been run here.

Final pins:

| Artifact | SHA-256 |
| --- | --- |
| Native runtime source | `67d915c841c993d69cb3144947ac397e70ef62235ea8d903363312e13a8577a5` |
| Own prototype DLL | `88117b8f38dc77d20e638ce573bb83fc6f959c1ad6821f8803c5499969fe234b` |
| Managed prototype bridge | `8c37470ecafa4c00a41dbf8917295f88f76b7d2fbbd57645a91313bc833efda8` |
| Generated PHP source evaluator | `6ccacffa8b143f35a06c0213885f659773424ffc24bea62921de8e0c957437d2` |
| PHP callback fixture | `c2ac4a4f5777648389c81b5aacb2dfc64c04e4e43190ca36379970a8b83cf0fd` |

Review [native source changes](native-runtime.patch), [bridge header changes](native-header.patch), [managed bridge changes](managed-bridge.patch), and [evaluator changes](../../tools/candidates/php-native-callback/callback-context.patch). Reproduction commands and all scope restrictions are in [the prototype README](../../tools/candidates/php-native-callback/README.md). Native DLL/OBJ/LIB outputs remain locally ignored; build logs, import/export evidence, hashes, and original raw measurements are preserved. Earlier `smoke3`, `callback15-initial`, `control-contract`, and `build` are historical preliminary runs; `callback15-final`, `control-contract-final`, and `build-final` identify the final measured revision. The early comparison inherited an overly broad unsupported-callback description from the copied harness; the final report records the corrected experimental scope without altering those historical results.
