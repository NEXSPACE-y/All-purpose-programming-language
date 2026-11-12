# PHP 8.5.12 native extension binary ABI: evidence and approval proposal

Date: 2026-11-12 JST. Current status: **OPTION_A_APPROVED / IMPLEMENTATION_IN_PROGRESS / PHP_FULL_COMPATIBLE=false**.

## 2026-11-12 owner approval and implementation overlay

The owner explicitly approved option A after reviewing this proposal: ALL-owned native C/C++ ABI state and the C bridge, existing MSVC/Windows SDK, and the pinned PHP devel headers. Approved platform targets are **Windows 11 x64 and Linux x64**. Required Web targets are the **built-in development server, CGI, FastCGI and Apache**, plus **FPM on Linux**. These platform/SAPI choices are settled and recorded in `docs/COMPAT_TARGET.md`; they are no longer pending choices from the original section 6. Option B and additional source/dependency adoption remain unapproved.

Actual option A implementation now exists under `native/php85abi/` with a C# boundary under `tools/abi/`. It builds an ALL-owned `php8ts.dll` without linking or forwarding to stock PHP. Isolated child-process measurements have loaded the original `php_dl_test.dll`, called its native handlers, and compared selected outputs/errors with a separate stock-PHP oracle process. Current measured results and limitations are recorded in [the implementation report](../../reports/native-abi-implementation-20261112/README.md).

This is a first-module, selected-behaviour measurement, not full module/extension/PHP compatibility. Native object property read/write/enumeration and wider engine state remain unsupported; metadata registration is measured separately from object execution. Linux and every Web SAPI remain unverified until their actual runtime tests execute. The original proposal and static evidence below are retained as history; its phrases “after approval” describe the sequence that led to the now-approved A work, not a current request for A approval.

以下は案A承認前の提案・静的調査記録です。**既存DLLを無改変で受け入れるための、ALL所有のC/C++ ABI互換部と実際のZend互換状態管理の新設は、2026-11-12に所有者が承認済み**です。公式PHP本体への委譲は採用せず、DLLロード成功だけで完全互換とは認定しません。現在の実装・実行範囲は上記overlayと実装レポートを参照してください。

The owner's stage 1 goal includes PHP 8.5.12 CLI, Web, standard extensions and existing native extension **binary** compatibility. Stage 2 grows ALL itself to full PHP capability with bidirectional calls and shared data, after stage 1. This document addresses the stage 1 native ABI foundation; it does not begin stage 2.

For the original static investigation described below, no PHP runtime or extension DLL was loaded or executed. Its sole executed helper reported header layout constants and had no PHP imports. The later approved implementation measurements are separate and explicitly include actual extension execution; see the overlay. Installed ALL and the original oracle binaries have not been replaced.

## 1. Reproducible evidence and baseline

Repository base: `9d8171712828a0b57555b8eb1e1ca5c475391244`, continuation branch `work/php-core-compat`, isolated working branch `codex/php-8.5.12-full-compat-20261112`.

The current continuation is v3.16, despite retaining the filename `package/ALL_PHP_v3_12_adapter.ps1`. It already has Int64/Double values, exceptions/diagnostics and namespaces. The original public main baseline is not substituted for this continuation. At ABI inspection its adapter SHA-256 was `2f462dee734635968d540d1f8bf68fd30e0eebec662081c4ccb409bde57fc934`.

| Input | Observed evidence |
|---|---|
| Oracle directory | `C:\Users\rinpa\ALL_php_oracle\php-8.5.12-ts-x64` |
| Native extension directory | `ext/`, **36 DLLs**, all AMD64 PE32+ |
| Core binary | `php8ts.dll`, **6,158 named exports**; static reference inventory only |
| Imports used by the 36 DLLs | **985 unique php8ts.dll symbols**, including **59 data exports** |
| Statically decoded module entries | 36/36: size **168**, API **20250925**, ZTS **1**, debug **0**, build ID **API20250925,TS,VS17** |
| Source ZIP SHA-256 | `9dac05f72f328afd0a2b0e795a519ae4cb3d056bc3f3b55147bd048bd64e45e8` |
| Devel ZIP SHA-256 | `52cb020402c3165e7cb37ec0d96ae43e26997f01d0fdb5474aa92801246810e9` |
| Headers/import library | Exact devel headers available in Downloads ZIP; runtime also has `dev/php8ts.lib` |
| Existing native build tools | VS Build Tools 2022, MSVC toolset 14.44.35207, C compiler 19.44.35228 x64; Windows SDK 10.0.22621.0 |

The ZIP hashes match the existing target record. Every inventoried binary and selected source/header member has its own SHA-256 in [the PE inventory](../../reports/native-abi-20261112/pe-inventory.json). `dumpbin` independently reports the same 6,158 exports in [its export log](../../reports/native-abi-20261112/dumpbin-php8ts-exports.log).

**The 985 imports are a lower bound, not an ABI completion denominator.** Inlined macros access structs directly. Extensions may look up symbols dynamically, create callbacks, retain pointers, or inspect execution state. Third-party binaries were not supplied in this local inventory; no claim of their successful operation follows from these 36 DLLs.

## 2. Exact ABI contracts exposed by these binaries

### 2.1 Loader and module lifecycle

Windows resolves a DLL's normal imports before application code can call its exported `get_module`. These existing binaries name **php8ts.dll**, so a source API wrapper with another interface does not satisfy their import tables.

`ext/standard/dl.c:187-250` obtains `get_module`, checks module API and build ID, registers the module, and calls startup hooks. `Zend/zend_modules.h:71-100` defines the actual entry layout and MINIT/MSHUTDOWN/RINIT/RSHUTDOWN/globals callbacks. Matching `get_module` alone does not implement this lifecycle.

The independent inspector recognises the MSVC x64 `lea rax,[rip+disp32]; ret` stub and reads its target bytes without executing `get_module`. It decoded all 36 entries. The compiled SDK check independently confirmed the offsets used by this decoder.

### 2.2 Calling conventions and exported names

In this source, `Zend/zend_portability.h:327-332` sets **ZEND_FASTCALL to `__vectorcall` on MSVC**. Actual imports include `_emalloc@@8`, `zend_hash_find@@16`, and `zend_wrong_parameter_error@@40`. Preserve exact exported spelling and the declared calling convention. Assuming every function is ordinary cdecl, or removing decoration when generating exports, is incorrect.

`zif_handler` receives `zend_execute_data *` and `zval *return_value` (`Zend/zend.h:49`, `Zend/zend_compile.h:568-572`). Some functions are varargs; some exported DATA entries hold function pointers. A flat collection of P/Invoke delegates does not supply this contract.

### 2.3 Real unmanaged structures, ownership and identity

[The compiler layout evidence](../../reports/native-abi-20261112/header-layout.json) was built from the pinned SDK, with ZTS and release definitions, without linking `php8ts.lib`:

| Type | sizeof, x64 bytes | Important offsets |
|---|---:|---|
| `zval` | 16 | value 0, type info 8, auxiliary word 12 |
| `zend_string` | 32 | refcount header 0, hash 8, length 16, inline bytes 24 |
| `zend_array` | 56 | HashTable layout is exposed in headers |
| `Bucket` | 32 | zval/key/hash storage is exposed |
| `zend_reference` | 32 | refcounted cell containing another zval |
| `zend_object` | 56 | class entry 16, handlers 24, properties 32, inline property table 40 |
| `zend_execute_data` | 80 | function 24, `This`/call flags/argument count 32, previous frame 48 |
| `zend_function_entry` | 48 | names, native handler, arginfo and frameless metadata |
| `zend_module_entry` | 168 | API 4, ZTS 9, name 32, functions 40, build ID 160 |
| `zend_extension` | 208 | Different engine-extension interface; API **420250925** |

The `zend_string` sizeof includes its one-byte tail and padding; allocation of a real string must accommodate the actual byte length and terminator. Copying a managed string does not reproduce arbitrary PHP bytes, lifetime or reference counting. Managed object addresses are not stable native Zend objects. Shared references, array mutations, object handlers, resource destructors and GC need coherent ownership.

### 2.4 DATA exports, TLS and execution hooks

Observed DATA imports include `executor_globals_offset`, `compiler_globals_offset`, `core_globals_offset`, `sapi_globals_offset`, `module_registry`, `std_object_handlers`, `zend_ce_exception`, `zend_execute_ex`, `zend_execute_internal`, `zend_write`, and `zend_string_init_interned`. The inventory lists all 59 and each importing DLL.

Under ZTS, `TSRM/TSRM.h:138,170-184` exposes thread-local cache and offset macros. Extensions dereference that state using compiled offsets. Exporting zero-valued variables or providing one global dictionary is not equivalent to a correctly initialised per-thread request context.

`php_zend_test.dll` alone imports **207** core symbols, including `compile_string`, `zend_execute`, `zend_vm_stack_destroy`, observer registration, opcode handlers, fibers, and memory-manager functions. Some ordinary PHP modules therefore require execution-engine internals even without being a `zend_extension`. The 36 DLLs export `get_module`; their presence does not independently test the separate `zend_extension_entry`/op-array hook interface.

### 2.5 Dependencies and build variants

The inventory includes Windows/UCRT/MSVC libraries and distribution dependencies such as OpenSSL, ICU, SQLite and libpq. It also includes `fbclient.dll`, which was **not present at the oracle directory root during inspection**; other locations or loadability were not tested. Import inventory does not prove dependency resolution or database/network service availability.

The current measured target is AMD64/ZTS/release/VS17. NTS, x86, ARM64, debug, other module APIs, other operating systems and future PHP releases cannot be labelled compatible with this binary contract. They require their own approved targets and artefacts; this does not remove the project's broader goal.

## 3. Why the present evaluator does not yet supply this ABI

The continuation adapter holds variables, functions and classes in .NET dictionaries/PSCustomObjects, with reference-cell helpers and native .NET scalar values. Its user-call path is `Invoke-PhpCallable`, and its arrays/objects are created by PowerShell functions. No `zend_module_entry` loader, Zend export DLL, native zval heap, native execution-frame arena, TSRM context, or module lifecycle is implemented in this adapter. See `package/ALL_PHP_v3_12_adapter.ps1:20-77,2329-2515,3921-4149` at the stated baseline.

This is an observed missing interface, not a claim that PowerShell makes native compatibility mathematically impossible. Existing native binaries can be served by an independently implemented, ABI-compatible native component, while ALL keeps its own evaluator. The cost and correctness obligations of that component must be recognised and approved.

## 4. Options and recommendation for an approval decision

| Option | Concrete implementation | Goal fit and effect |
|---|---|---|
| **A — independently implemented native ABI component, incremental integration** | Build an ALL-owned x64/ZTS compatibility DLL with the required `php8ts.dll` name and exact exports/layouts; implement real heap/objects/TLS/module state; provide an ALL-specific C bridge to the current evaluator | **Recommended first foundation proposal.** Keeps evaluation under ALL. Requires a new native foundation and changes to value/call boundaries. Import closure and real behaviour can be verified module by module; full completion is not established by a first module |
| **B — ALL-owned native execution core with the same ABI** | Extend A so execution frames, compatible op arrays/hooks, callbacks, fibers and state execute primarily in an ALL-owned native core; preserve the existing ALL language and regression assets | Potentially required by deeper binary contracts. Much wider execution/value-model migration; needs a separate concrete design review after A's evidence. Not adopted here |
| **C — selective source reuse inside an ALL-owned ABI component** | Reuse explicitly named PHP/Zend utility components or headers under their licences, while ALL retains parsing/evaluation; record every component and dependency | Potentially reduces low-level duplication, but utility files have dependencies and do not confer full ABI correctness. **Separate dependency/source-adoption approval required.** No PHP source was incorporated into a runtime here |
| Stock `php.exe`, PHP-FPM, stock `php8ts.dll`/embed API, or forwarding exports to stock PHP | Execute the original runtime or forward compatibility calls to it | Does not satisfy the requested independent implementation and is **not proposed for adoption** |
| Recompile/change existing extension binaries or replace them with per-function wrappers | Avoid the original import table and ABI | Does not satisfy unchanged binary compatibility and is **not a substitute** |

The SDK import library `php8ts.lib` is a set of linker imports, not a standalone Zend implementation. Linking it normally requires the stock DLL; its availability does not solve the independent ABI problem.

### Proposed scope of option A

Candidate-only paths, to be created **after approval**:

- `native/php85abi/include/`: approved pinned SDK type declarations and explicit ABI contracts, with provenance/licence information.
- `native/php85abi/src/`: module loader, exported symbols, heap/zvals/HashTables/objects, TLS/globals, function frames, diagnostics and lifecycle.
- `native/php85abi/Build-NativeAbi.ps1`: build with the existing MSVC/Windows SDK; no compiler installation.
- `tools/abi/AllNativeBridge.cs`: an ALL-specific ordinary-C boundary into the native component; calling-convention adaptation stays in compiled C/C++.
- `tools/abi/Invoke-NativeExtensionProbe.ps1` and fixtures: isolated child workers and real unchanged-DLL checks.
- A narrowly reviewed integration point in the PHP adapter for calls and values crossing the boundary. Existing pure managed behaviour and regression baselines remain available for comparison; no installed runtime is replaced during candidate testing.

Load the ALL-owned compatibility DLL by its absolute candidate path, verify its identity, and reject a worker if an unexpected `php8ts.dll` is already loaded. Then load an unchanged extension with an explicit dependency-search policy. The oracle directory is never a fallback DLL search path for the compatibility core. A failed symbol or unsupported operation must fail with evidence; returning a fabricated success from a stub is forbidden.

For native-reachable data, one authoritative identity/ownership model is required. Scalar copies are suitable only where PHP specifies value semantics. Arrays, references, objects, resources and retained native pointers need stable native handles and coherent mutations. A proposed integration invariant is: once a value is promoted to native-reachable storage in a request, reads/writes/destruction use its authoritative native representation until that request ends. The exact promotion and callback design is a foundation change requiring approval, not an implementation already made.

Native-to-user callbacks must re-enter the ALL evaluator on the correct request/thread, using compatible parameters, references, exceptions and output handling. Unrelated native-thread callbacks require an explicit scheduling contract. Native bailout/SEH/longjmp must terminate or unwind inside a controlled native worker boundary; it must not jump across managed/PowerShell frames.

## 5. First acceptance work after approval

The first target is the **existing, unchanged `php_dl_test.dll`**, hash pinned in the inventory. It is small but real: **29** PHP/Zend imports, internal classes, INI state and TLS. Source evidence is `ext/dl_test/dl_test.c:28-64,94-98,124-217` and generated arginfo in the pinned source ZIP.

1. Verify the candidate DLL's export names, DATA symbols, vectorcall entry points and header layouts; inspect child-process module paths to show that stock PHP is absent.
2. Load this original DLL and perform genuine module registration, MINIT, GINIT/RINIT and request teardown. Confirm API/build-ID mismatch rejection and missing-import rejection.
3. Exercise registered functions `dl_test_test1`, `dl_test_test2` and `dl_test_frameless`, argument failures, returned byte strings/integers, output, registered classes/methods and `dl_test.long`/`dl_test.string` INI behaviour. Compare independently captured oracle output/diagnostics and exit status.
4. Repeat request startup/shutdown and two isolated requests; check TLS separation, reference counts and retained-value/destructor behaviour. Detect leaks/crashes rather than treating process survival as semantic success.
5. Progress to real modules such as SQLite3 (83 imports), FFI (78) and zend_test (207), adding their actual DATA, callback, resource, memory and engine-state contracts. Inter-module dependencies are part of this work. No result for dl_test grants compatibility to these modules.

These are staged engineering checks, not a reduction of the completion condition. Stage 1 remains **NOT_COMPLETE** until the approved CLI/Web/standard-extension/unchanged-binary requirements and regression/differential/real-application gates are all met.

## 6. Historical approval proposal, superseded for option A by the overlay

At proposal time the specification's sections 9/14 required a foundation decision. The owner has since approved A and the platform/SAPI matrix stated above. The wording below records that original decision proposal; it is not a request to approve A again.

Suggested approval wording:

日本語での決裁案：

> PHP 8.5.12のAMD64/ZTS/release/VS17を最初の検証対象とし、既存MSVC/Windows SDKとハッシュ固定したPHP開発ヘッダーを使って、ALL所有のネイティブABI互換DLLとC接続部を候補環境内に実装する案Aを承認する。無改変の拡張DLLに必要な実際のZend互換状態管理と、それに伴うPHPアダプタの値・呼出し境界変更を対象とする。公式PHPランタイムへの委譲、既存ALLの上書き、main反映は行わない。案Bへの全面移行、追加ソース・依存・OSの採用は別途判断する。PHP全体の承認済み条件がすべて満たされるまでNOT_COMPLETEとする。

> Approve option A as an isolated native ABI implementation candidate for PHP 8.5.12 AMD64/ZTS/release/VS17: use the already installed MSVC/Windows SDK and pinned PHP devel headers to build an ALL-owned compatibility DLL and C bridge; implement the real Zend-compatible state needed by unchanged extension binaries, without stock PHP runtime delegation. Approve the reviewed PHP adapter value/call boundary changes needed by this candidate. Keep installed ALL and main untouched. Do not adopt option B, additional source components, new dependencies or additional OS targets without their own review. Report each tested module/behaviour explicitly and keep stage 1 NOT_COMPLETE until all approved requirements pass.

Additional acceptance targets to record with the owner, while existing authorised work continues:

- Exact OS/architecture and TS/NTS matrix. This evidence establishes the current Windows AMD64/ZTS ABI only; **Windows-only success is not automatically project-wide completion**.
- Exact Web SAPI coverage and deployment environment: CGI/FastCGI, Apache-module and other required interfaces have different host/lifecycle contracts. CLI success does not establish Web success.
- The concrete third-party extension binaries/builds to inventory and validate, in addition to the current 36 bundled modules; separate engine-extension hooks if those binaries use them. No absent binary is marked compatible.
- Approval for non-system native dependency distribution/use when an extension requires it, including missing client libraries and environment/service prerequisites. Merely finding a DLL in the oracle package does not adopt it as an ALL runtime dependency.

## 7. Impact, rollback and feasibility boundary

Option A affects ABI-exposed memory ownership, request/thread globals, calls, exceptions and native module lifecycle. It can be developed in the isolated candidate tree and child processes without replacing installed ALL. Before each integration step, record the adapter hash and regression evidence; on failure, disable the candidate integration or return to the recorded pre-step commit. Preserve results and original binaries; do not repair a failing test by overwriting installed files or oracle DLLs.

The evidence proves that the native contract is concrete and measurable and that build tooling/headers are available. It does **not** prove implementation feasibility for every requested existing extension, completion time, or complete compatibility. An independently implemented ABI component is a technically viable route to investigate. The 59 DATA imports and execution/observer/fiber interfaces show why a function-name shim alone is insufficient; option A may expose a need for the separately approved wider execution-core work in B.

Current acceptance flags: `native_binary_load_verified=false`, `native_function_semantics_verified=false`, `native_request_lifecycle_verified=false`, `third_party_extensions_verified=false`, `web_sapi_verified=false`, `PHP_FULL_COMPATIBLE=false`.

## 8. Reproduction and generated files

```powershell
python .\tools\abi\Inspect-NativeAbi.py --runtime C:\Users\rinpa\ALL_php_oracle\php-8.5.12-ts-x64 --source-zip C:\Users\rinpa\Downloads\php-8.5.12-1-src.zip --devel-zip C:\Users\rinpa\Downloads\php-devel-pack-8.5.12-1-Win32-vs17-x64.zip --output .\reports\native-abi-20261112\pe-inventory.json
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\abi\Measure-HeaderLayout.ps1 -DevelZip C:\Users\rinpa\Downloads\php-devel-pack-8.5.12-1-Win32-vs17-x64.zip -OutputDirectory .\reports\native-abi-20261112
```

The layout script verifies the devel ZIP hash, extracts the SDK to a newly named temporary directory, compiles the constants reporter, checks its imports for PHP DLLs, then runs it. The scratch directory is recorded and retained; there is no dependency installation or recursive cleanup. The standard-library PE inspector only reads binary bytes. Re-running these commands regenerates evidence; it does not run PHP or extension code.

Generated evidence is under `reports/native-abi-20261112/`: `pe-inventory.json`, `header-layout.json`, layout build/import logs, independent dumpbin import/export logs, and `assessment.json`.
