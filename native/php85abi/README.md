# ALL-owned PHP 8.5 native ABI candidate

Option A was approved by the owner on 2026-11-12. This component is written for ALL and is not linked or forwarded to the stock PHP runtime. It uses the approved, pinned PHP devel **headers** and existing MSVC/Windows SDK. No PHP utility `.c` implementation was copied.

Current runtime target: Windows x64, ZTS/release/VS17, module API 20250925. Linux x64 and the approved Web SAPIs remain required and unverified. The source currently uses Windows loading APIs and is not presented as a Linux implementation.

Build from the repository root:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\native\php85abi\Build-NativeAbi.ps1
```

The build script verifies the SDK ZIP hash, extracts headers to a newly named temporary directory, compiles this source, and checks the resulting imports for PHP runtime dependencies. It does not install files or change PATH outside its process. `out/` is ignored by Git; build hashes/logs are recorded in `reports/native-abi-implementation-20261112/`.

Implemented foundation includes exact native scalar/zval/string storage, request allocation ownership checks, refcounted string copies, registered native functions and call frames, INI callbacks, module/global/request lifecycle, thread-local module globals, and the registration metadata needed by the unchanged `php_dl_test.dll`. The exported standard object-handler table has real lifetime/method/class-name helpers and explicit unsupported guards for property/dimension/cast/enumeration operations. Registered typed-property metadata does not establish property-execution compatibility.

See [the actual measurement report](../../reports/native-abi-implementation-20261112/README.md). The current measured scope is a selected first-module subset; PHP full compatibility is false.

## Evaluator integration contract

`tools/abi/AllNativeBridge.cs` exposes `AllPhp85Abi.Bridge`:

- Construct with the absolute candidate core path; it refuses a process already holding a PHP core. `LoadExtension` accepts an absolute unchanged extension path.
- `FunctionCatalog` returns names, arity, flags and parameter names from the actual registered module function table. `HasFunction(name)` is case-insensitive. There are no hard-coded PHP function-name dispatch branches.
- Call `Start()` once for an evaluator request and `End()` in its `finally` path. `Shutdown()` follows only after all requests/worker threads have ended.
- `InvokeScalar(name, object[] arguments, bool strict)` supports null, bool, Int64/Int32, Double and managed Unicode strings. It returns `ScalarInvocation` with `Ok`, `Status`, `Value`, raw `Output` bytes, structured `DiagnosticEvents` (`Level`, `Message`), `ErrorClass`, and `ErrorMessage`.
- A PHP error result must enter the evaluator's PHP error/exception path. A native `ALLNativeUnsupported`/negative status or a marshalling exception remains an explicit implementation gap. Do not retry through another execution path after a native call, because its side effects may already have occurred.
- Send `DiagnosticEvents` through the evaluator's own error-reporting/user-handler/source-context logic. The older `Diagnostics` bytes are canonical strings for the isolated comparison harness; they are **not raw CLI diagnostics with a source location or stack**.
- Input strings and native output/error/catalog strings use strict UTF-8 conversions. NUL within value bytes is length-preserved. The low-level `Call` API carries arbitrary bytes as Base64; the managed-scalar convenience API explicitly rejects unrepresentable arrays, objects, references, raw byte arrays, decimals and invalid UTF-16/UTF-8 rather than silently altering them.
- Function/scope/class/property/constant names and INI keys are validated before C-string marshalling. `HasFunction` returns false for names containing NUL; invocation rejects them before calling native code. Length-bearing argument values still allow NUL. The current separate NUL-terminated INI setter rejects a NUL-bearing value explicitly instead of truncating it.
- Initial calls are positional only. Catalogue parameter names do not imply named-argument, by-reference, resource, object or populated-array support. Native-to-PHP user callbacks and general Zend execution hooks are still missing.

The checks in `tools/abi/Invoke-NativeScalarBridgeProbe.ps1` test this boundary only. Actual source execution through the PHP evaluator is a separate integration claim and must be verified by the evaluator's own execution tests.
