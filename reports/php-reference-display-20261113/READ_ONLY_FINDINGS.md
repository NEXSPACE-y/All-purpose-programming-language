# PHP reference-display observations and smallest preserving model

Oracle run `oracle01/report.json` contains 32 unchanged PHP programs and their raw stdout/stderr/status from the pinned PHP 8.5.12 Windows binary. No candidate evaluator loop has been started for this task.

Observed conditions:

- Top-level scalar aliases are dumped as ordinary strings. Within arrays/objects, a shared reference gets `&string`; a cell with only one PHP owner does not.
- Removing a scalar alias changes the display immediately. The same applies when the second array slot, a closure capture, or a lingering foreach variable is removed.
- Suspended caller locals, reference parameters, function statics and live closure captures remain owners. A local reference left only in a returned array does not retain a second owner after its frame ends.
- Copy-on-write array backing matters. `$a=[&$v]; $b=$a; unset($v); var_dump($a,$b)` shows no ampersands. A write to `$b` before removing `$v` separates the backing and both arrays then retain a shared reference. The same write after removing `$v` leaves ordinary values. Two array slots pointing at one cell remain shared; two separate single-owner cells do not.
- Repeated arguments to var_dump do not manufacture shared cells. A self-reference prints `*RECURSION*`, without an ampersand before that marker.

Pinned source `5856687f7abd1471b4af7af9827ca2d17a011e836ad2852bf1d7993298fddc9f` copies arrays eagerly in `Copy-PhpValue`, while preserving every refcell object. It has no PHP owner count, no array backing identity, and it drops suspended local dictionaries from the visible state when entering a function. The byte dump helper currently dereferences every cell without checking whether it is shared. Counting live CLR references or simply counting cells across the eager array copies would therefore give false ampersands. The problem also reaches value behavior: a single-owner cell must separate when an array copy is written, rather than unexpectedly changing the other copy.

Proposed bounded implementation in `ReferenceDisplayEdits.py`:

1. Retain existing eager array value copies, PhpBytes, typed keys and refcell objects. Add a private logical backing token to New-PhpArray; Copy-PhpValue gives each eager copy the source token. Equal tokens mean the PHP hashtable has not logically separated. This token is metadata, never a PHP string/key/native handle.
2. Before existing array write/reference-bind/remove paths, detach that array's token. Build a live ownership snapshot, counting a cell once per storage slot and visiting each logical array backing once. If a cell has one logical owner at separation, copy its value into the separating array; preserve cells with multiple owners. This follows the observed before/after-unset separation and preserves the eager copy's independent nested values. Array mutators replacing their Items must also transfer/reset the token.
3. Scope a suspended-frame root list through Invoke-PhpCallable's existing try/finally; count active variables, globals, function/class statics, reachable object properties and closure captures, plus current dump arguments. Host trace caches and transient PS locals are not automatically PHP owners. Iterative visitation and identity checks prevent cycles and double counting. Caller/global/static binding names must not manufacture duplicate slots.
4. Build one owner snapshot per var_dump call. The raw byte formatter prefixes `&` only for a nested cell with count greater than one, preserves PhpByteBuilder output, and checks array/object recursion before emitting a reference mark. Recursive calls share the context and use path-local backing identities.

Expected edited surfaces are New-PhpArray, Copy-PhpValue, Resolve-PhpLValueSlot, Set-PhpArrayItem, unset/index removal, foreach-by-reference setup, the existing mutating array builtins, the typed variadic direct-array write, Invoke-PhpCallable frame lifetime, and Format-PhpBytesDump/var_dump. Each anchor must be pinned against the composed candidate and fail if another module changes it. New metadata must not flow through native execution or alter the immutable byte assembly.

This is larger than a formatting-only prefix: the separation hooks are necessary to avoid the measured false positives. It is still bounded to the existing array/refcell execution paths. A full Zend ownership system, GC/destructor timing, resources/native zval ownership, generators/fibers, exception trace retention, ReflectionReference identity and all PHP extensions remain outside this small model and require separate validation. No claim of full reference compatibility follows from the 32 oracle observations.

Rollback is to omit the new generator module and retain the recorded candidate/runtime pins. Existing 75 byte cases, 12 typed-array cases, package source and oracle inputs remain unchanged.
