# Concrete next native batches under approved option A

This is a read-only proposal from frozen cores, the unchanged Windows PHP8.5.12 distribution, and the pinned local source/header contracts. No DLL was loaded, no extension function ran, and no runtime implementation/dependency was adopted. A name closure below is a loader prerequisite, not a compatibility result. Every implementation batch must use a new own-core/bridge revision and retain the existing fixtures, failures and frozen binaries.

## First: two bounded byte/output corrections

**Error-message length.** Current callback Runtime.cpp:389 returns `tls.error.c_str()` without size; the original core has the same contract. Byte bridge CopyNativeCString therefore cannot recover a NUL suffix and retains its16MiB scan limit. Add an own C export, preserving the old export and struct layout:

```c
const char *all_php_error_message_bytes(size_t *length);
```

Its independent implementation sets the output size to the actual owned string size and returns its borrowed data pointer. The byte bridge binds the sized getter in the new profile, copies through its existing synchronous FromStream route before another native operation/teardown, and never decodes the message as a PHP value. The legacy getter/API remains unchanged. A capability must distinguish the old C-string boundary from the sized contract; merely reading the old getter again is not a repair.

Acceptance: a separate native contract test supplies empty/FF/NUL/surrogate/all256/over16MiB messages, confirms length/copy after source overwrite and request end, and labels its injected errors synthetic. Existing real dl_test error/diagnostic/source fixtures must retain exact channels and statuses. Existing37 native cases, scalar contracts, legacy23+4 guards, callback15 and raw4 remain unchanged. This batch adds no native function retry or stock PHP delegation.

**Module-info50-byte difference.** The preserved two byte component cases produce335 own bytes versus385 oracle bytes; only two insertion ranges differ. They remain failed in the evidence. The pinned PHP8.5.12 source archive, rather than an evolving web branch, supplies the relevant contracts: `ext/standard/info.c:133,1062,1072,1131`, and `main/php_ini.c:115`. The source member hashes and line anchors are in source02/source-audit.json.

For a text-mode profile, the smallest coherent correction is four connected changes: emit a module heading before its info function; implement the text header cell formatter; make text table_end emit no bytes; and make display_ini_entries begin/header/end its table only when a matching entry exists. The current extra table_end newline partly masks the missing INI table_start, so hardcoding two text insertions would hide a second semantic difference. Use the actual module name and current INI entries, not a dl_test-specific output replacement.

Keep CLI text formatting explicitly separate from HTML/SAPI mode. INI displayer callbacks/original-value retention, registration order, empty/null values and diagnostic callbacks during MINFO are additional contracts; this correction must not claim them completed. In particular, current ModuleInfoBytes has no managed pending-call lease frame, so its callback/abort semantics cannot be inferred from the scalar call path.

Acceptance: rerun both unchanged failing raw-output cases with exact whole-channel comparison, then cover zero entries, multiple tables, empty cells and modified/master values. Preserve the original335/385 records. Test original and callback cores separately. No output trimming, prefix removal or expected-value rewrite is allowed.

## Then: a small second unchanged module

The current closest import-name closure is **php_gettext.dll**:12 core imports,8 already named,4 missing. Those4 are `virtual_getcwd`, `virtual_realpath`, `zend_argument_must_not_be_empty_error`, and `zend_argument_value_error`. Its statically decoded module entry has no MINIT/RINIT hooks or module globals. Its other normal imports are Windows, UCRT and MSVC libraries; this observation does not prove system loader resolution or successful execution.

Implement the two argument errors from the current native frame/arginfo as real ValueError production, including correct argument name/number and raw format bytes. Implement virtual paths using a real request/thread virtual-CWD contract. Mapping virtual_getcwd directly to a mutable process CWD is insufficient for concurrent ZTS requests. Preserve path failures and Windows path/encoding behavior; do not return a fabricated success path to satisfy the linker.

The exact binary/source import relationship is visible in the pinned gettext source: bindtextdomain uses VCWD_REALPATH/GETCWD at207/210, and domain/length/category checks call the two error producers. The selected C# loader guard must be extended only to the fixed reviewed gettext hash in a new bridge revision; do not weaken the frozen dl_test guard. Keep each module in a fresh process while the core still supports one module.

Acceptance after the four functions are real: static imports/exports and DATA kinds; original get_module/API/build ID; separate PHP comparisons for gettext/_/dgettext/ngettext/dngettext without a catalog, empty/zero/overlong domain and category errors, raw byte message identities, and bindtextdomain with an owned temporary path/current directory. Record untranslated-domain identity separately from actual catalog/plural/encoding translations. Use owned local data; do not install a locale or change a machine-wide setting. Loading this module is not module-wide semantic acceptance.

## The next value batch must begin with ownership

Current code is not safe to generalize by just accepting additional IS_* tags. `copy_value` retains strings only; arrays/objects are shallow copies. `destroy` frees array/object containers without recursive value/reference/resource/custom-object destruction. `value_in` permits only a zeroed empty array, and `value_out` rejects all arrays/objects/resources/references. The fixed metadata HashTables are not a general array implementation.

Introduce a versioned own value/handle API alongside the existing40-byte all_php_value. Each handle needs context identity, request generation, native type, ownership, retain/release and closed/expired state. Managed values must not retain borrowed pointers. Root's PhpBytes/PhpKey and RefCell/array/object state need an explicit conversion/writeback protocol; silently serializing objects or replacing all PHP arrays with one unmanaged pointer would lose PHP identity and alias behavior.

| Batch | Concrete implementation | Required evidence before opening its tag |
|---|---|---|
| V1: arrays and value lifetime | Real ABI HashTable/Bucket layout, string/int keys and order, grow/rehash/delete/holes, zval copy/move/destroy, COW, request-owned handle roots. Replace fixed-table helper reuse with an actual array store. | SDK layout/inlined access test; nested/empty/raw keys, overwrite/delete/reinsert, alias versus COW, ownership after callback/reentry and teardown. Keep cyclic/other values explicitly outside the accepted profile until their destruction is implemented. |
| V2: references and cycles | Actual zend_reference cell/source layout, refcounting and graph identity, same managed RefCell maps to one native reference, writeback on success **and** an exception/abort after mutation; cycle accounting/collection. | Two aliased arguments, nested references, typed property reference sources, mutation-before-throw/exit, self-cycle and multi-node cleanup, stale generation/thread rejection before invocation. |
| V3: object identity and handlers | Native object store and persistent per-request proxy handles; honor class create_object and custom handler offsets; keep the same object between method calls; implement standard property/method/type/visibility/dtor/free/get_gc contracts. | Real custom-layout object, property read/write/uninitialized/type/readonly behavior, constructor/destructor exactly once, aliasing, custom free offset, callback escape and shutdown. Metadata registration alone is insufficient. |
| V4: resources and streams | Actual zend_resource registry/type/destructor/refcount/closed state, ordinary versus persistent lifecycle, alias invalidation; then the stream wrapper/filter APIs required by resource-heavy modules. | Close through one alias, fetch wrong/closed type, exact destructor timing, request versus persistent cleanup, callback abort and double-close behavior. Own SDK fixtures are component evidence, not unchanged-module compatibility. |
| V5: coherent globals/module lifecycle | Per-module and per-thread globals/offsets, actual required DATA objects, transactional MINIT/RINIT failure rollback, module dependencies/unload barriers for attached threads, SAPI state. | Failed startup, repeated requests, two simultaneous threads, foreign attached thread at unload, module order/dependencies and real SAPI request lifecycle. Zero-filled globals are not a substitute. |

Typical missing array/destructor imports are present in the per-symbol inventory; inline macros make this list a lower bound. Do not create dummy exports for those names merely to make a larger DLL load. Stage each family with its full local retain/release contract. A synthetic own fixture can establish ABI component behavior; a separately measured unchanged module is needed to claim that module behavior.

`php_shmop.dll` is not an immediate four-function follow-up: it lacks20 names including object creation/store/destruction, compiler globals, known strings, attributes, generic parameter parsing and Windows SysV-shm compatibility functions. `php_bz2.dll` additionally requires resource/stream/filter contracts. SQLite3 requires64 missing names and libsqlite3 dependency handling; its callbacks, objects, arrays, resources and bailout path cannot be reduced to those64 names.

## Lifecycle and scope limits to preserve

The current module loader allows one DLL, sets resource id1/slot0 and uses a fixed16-slot TLS cache. Startup failures after registration do not transactionally undo all state. Request startup failure can leave active state, and shutdown only detaches the current thread. Allocation tracking records request/thread for selected allocations but is not a complete request heap, persistent heap or cycle collector. Those are source observations, not newly executed failure cases.

All of B0/gettext/value-state work above fits independent state and bridge work in the already approved native option A. This proposal does not request approval again for A. It does not adopt PHP implementation source or extra non-system dependencies. If full op-array execution, native observers/fibers or another broad engine route becomes necessary, the existing A/B design boundary must be reviewed with concrete evidence; a dummy implementation must not conceal that need.

Linux x64 remains an approved target with no Linux native binary/runtime evidence in this audit. Current loader/toolchain code is Windows-specific. Collect actual ELF binaries/build metadata and establish the Linux platform layer before running native compatibility tests there; Windows PE results do not certify FPM, Apache, CGI/FastCGI or any Linux extension.
