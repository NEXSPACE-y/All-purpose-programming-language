# composed07 first boundary measurement

The actual CLI adapter/source SHA256 is
`2236abb15caf624a0ed5c30c0d703d782e455d420d519912595603ff09f52aa9`.
One loop ran the actual CLI executable against official PHP 8.5.12 with the same
source bytes, raw stdout/stderr, actual process status and 30-second limits.
Every process exited; none timed out. No source/fixture/expected value was edited
and no automatic retry or fallback was performed. Comparator exit was 1.

| Group | Matched |
| --- | --- |
| Original callback14 | 0/14 |
| Additional raw callback2 | 0/2 |
| Root original hex8 | 8/8 |
| New value boundaries16 | 15/16 |
| Total | 23/40 |

All sixteen callback differences stop before the handler at the remaining
trigger_error callsite `To-PhpText $callArgs[0]`: the raw message is rejected by
the valid-UTF8 host-text boundary. These results do not certify or refute the new
handler argument-count patch because that path was not reached. The single
value difference is the explicit existing weak enum coercion control: official
PHP string-backed enum `from(7)` selects case A backed by '7'; composed07 throws
ValueError. The remaining enum/raw error, first-class callables, numeric strings,
instanceof, getter/constants, match/trace escaping and static reference examples
matched on their first execution.

Original callback sources preserve their PHP opening tags and are passed as
files. Original hex examples retain their existing body mode. The per-case
provenance records all original definitions and source hashes. The driver inputs
and 77 additional application/runtime/reference-distribution pins remained
unchanged. Standard OS/.NET transitive dependencies are not claimed enumerated
as loaded modules.

The earlier description of callback messages as a runtime literal backslash-xFF
was wrong. Their unchanged PHP source escape produces raw FF, as the official
handler's bin2hex output confirms. See the explicit correction at
`../composed07-boundaries-preparation/INPUT-INTERPRETATION-CORRECTION.md`.
The old frozen report is preserved. Later fixes belong to new candidates and
must not relabel this first failing measurement as a pass.

This focused CLI profile is not complete PHP/ABI/Linux/SAPI conformance.
