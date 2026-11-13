# Array next-index review of composed12-index

Reviewed candidate: SHA256
`79e39d1e05d2813e9c593b0761409075cb9bd87930907b5c560434e0c2f3f827`.
Reviewed frozen ArrayIndexEdits snapshot:
`32513c9b9ac645fa4d6e33b3872fa4ac2e684c47d6481f817e1f8c61d9fa5a97`.
The original 18+14 official observations are unchanged and are oracle-only.
No candidate was run or edited by this review. Root received the confirmed
correction before changing its separate latest module/candidate.

## Confirmed defect: zero-value array_unshift is not generally a no-op

The early return at composed12-index line5882 preserves numeric keys and old
NextIndex incorrectly. The original 32 examples have only a fresh empty array
and fresh string-only array for zero values. Those inputs cannot distinguish
the early return from PHP rebuilding an array with no numerical keys/history.

Four additional official-reference probes, all EXITED0/stderr empty, establish:

| Input before array_unshift($a) | Actual behavior after it and the next write |
| --- | --- |
| [-5=>'x'] | Existing key becomes 0; append uses 1 |
| [8=>'x'] | Existing key becomes 0; append uses 1 |
| Past integer8 deleted, remaining string key s | Old history resets; adding -5 then append uses -4 |
| Past integer8 deleted, now empty | Old history resets; adding -5 then append uses -4 |

The exact sources, outputs, status and hashes are in unshift-zero-reference.json.
PHP8.5.12 source ext/standard/array.c:3796-3830 always creates a new hash and
reinserts existing numerical keys sequentially. It has no zero-value early
return. Z_PARAM_VARIADIC_EX in Zend/zend_API.h:2169-2184 permits zero remaining
values; the historical '+' macro spelling is not a one-value requirement here.

The consequence extends beyond immediate visible keys: copying the resulting
array must copy its rebuilt history. Leaving the source array unchanged would
also make a later copy append at an incorrect index. Root should remove only
the zero-value shortcut and preserve the full ordinary unshift replacement path
and reference bookkeeping. The old candidate/32 cases remain separate evidence.

## Counter rules supported by fixed source

| Rule | Source and review |
| --- | --- |
| Fresh no-history value is MIN | zend_hash.c:291/305 initializes nNextFreeElement to ZEND_LONG_MIN |
| Append maps only MIN to zero | zend_hash.c:1275-1276 tests HASH_ADD_NEXT and MIN explicitly |
| Negative writes advance signed history | zend_hash.c:1374 casts h to zend_long before comparing |
| MAX stays MAX | zend_hash.c:1375 uses MAX saturation; Root avoids numeric overflow |
| Occupied append fails before advancing | Existing bucket + HASH_ADD returns NULL at 1287-1289; execute.c:2592-2594 raises the exact Error text |
| Pop retreats only removed==next-1 | array.c:3628-3629 and3653-3654; string keys do not retreat |
| Shift reindexes and sets next to numeric count | array.c:3735/3772; string-only remainder gives zero |
| Empty pop/shift return without reset | array.c:3608-3609/3679-3680; deleting the last key beforehand does not imply a reset |
| Copies preserve even empty-array history | zend_array_dup at hash.c:2673-2678 and other branches at2688/2705/2723 |

Root's Allocate-PhpAppendKey is used by both ordinary Set-PhpArrayItem append and
Resolve-PhpLValueSlot reference append. Copy-PhpValue retains typed key objects
and copies NextIndex explicitly. The MIN and MAX tests therefore avoid Int64
overflow in the reviewed counter helper. The pop MIN guard is safe for reachable
normal states: a live integer MIN insertion advances history to MIN+1 before
pop, and popping that value restores the MIN sentinel.

## COW, references and typed keys not certified by the 32 observations

The counter patch does not certify every surrounding mutation behavior:

- PHP shift/unshift maintain active hash iterators (array.c:3705-3729 and
  3815-3818). The interpreter by-reference foreach walks a captured key list;
  mutations that renumber keys during iteration require their own conformance
  probes. This is an existing iterator/model issue, not a counter formula fix.
- Copy-PhpValue preserves history, but COW/reference separation also depends on
  ReferenceBacking/ReferenceCellsKnownAbsent and actual owner roots. Rebuilding
  shift/unshift passes values through Set-PhpArrayItem/Copy-PhpValue, whereas PHP
  moves zvals with reference identities intact. Shared nested/reference cells,
  escaped reference variables and aliasing during rebuild are not in the32.
- Reference append and failed saturated append should be checked with an RHS
  that creates or mutates a variable, not only an already-existing scalar.
  zend_compile_assign_ref:3569-3586 delays parts of the LHS and protects RHS
  references. A counter test alone cannot establish all expression ordering.
- Canonical numeric-string keys at MIN/MAX, one-past-MAX string keys, negative
  zero, raw byte keys and float key diagnostics exercise PhpKey coercion before
  the counter. The32 use integer boundary constants; they do not certify that
  entire conversion boundary. Root's current typed factories remain unchanged.
- array_push at MAX with multiple values can partially insert before a later
  occupied append throws. The helper appears consistent with sequential pushes,
  but the32 only inspect direct append and a simple reference append.
- Empty arrays retaining history after unset plus pop/shift, copies of that
  history, union/reverse/slice preservation and nested lvalue arrays need explicit
  coverage. No recommendation is made to recompute next from current max keys.

Suggested new source controls are kept in recommended-extra-cases.json, marked
unexecuted for the candidate. They are not edits to the old fixtures or invented
expected values. The review and official source excerpts are read-only reference
evidence; no PHP implementation code is adopted into the independent runtime.
