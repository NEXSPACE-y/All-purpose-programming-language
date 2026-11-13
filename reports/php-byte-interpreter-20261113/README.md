# Approved byte-model interpreter migration — active and incomplete

This work follows the owner's explicit option-1 approval recorded in
`docs/decisions/PHP_BYTE_MODEL_APPROVAL_20261113.md`. It is isolated from the
installed ALL and the package v3.20 checkpoint. The package source remains
`5856687f7abd1471b4af7af9827ca2d17a011e836ad2852bf1d7993298fddc9f`.

## Recorded candidate profiles

| Candidate | Actual evidence | Remaining observations |
| --- | --- | --- |
| core01, `db88bfe0...` | Scalar byte CLI 12/12 exact matches | No typed-key/string-builtin/native-byte composition yet |
| typed02, `07951c57...` | Typed arrays CLI 10/12 exact matches | Shared-reference `&` display missing; later argument mutation changes earlier by-value array |
| combined03, `4d120c8f...` | Generated and CLI host compiled; native source execution now being measured separately | Includes by-value builtin argument snapshots, typed keys, string builtins, byte native/diagnostic/Throwable wiring; no overall runtime verdict yet |
| offsets04, `257f9b94...` | PS5.1 syntax parse: 0 errors | Adds byte offsets; source execution not yet measured |
| json05, `524ce86a...` | PS5.1 syntax parse: 0 errors; CLI host compiled | Adds explicit JSON UTF8 boundaries; source execution not yet measured |
| composed06, `2c9e9813...` | 55/55 source comparisons; separate reference32/32 + additional4/4 | Scalar12, typed-array12, offset19 and JSON12; all exact raw channels/status and unchanged inputs |
| composed07, `2236abb1...` | Extra boundary40: 23/40 exact matches | Callback14+raw2 fail at the old trigger_error text conversion; Hex8/8 and other boundaries15/16 match, with string-enum weak coercion still different |
| composed08, `029b6f67...` | Generated only | Adds raw undefined-key diagnostics; superseded before execution |
| composed09, `6ee5992e...` | Critical3/3 exact matches, unchanged inputs | Adds the trigger_error byte callsite fix; complete40/default965 not yet remeasured |

Every generated candidate has its full source hash, module hashes, runtime pin,
patch and limitations in its `provenance.json`. Builds use the canonical own
immutable runtime DLL `18d50efb...66b`, with an absolute pinned path in these
isolated prototypes. Portable deployment has not been performed.

The first scalar12 invocation stopped before launching any PHP/candidate
process because the fixture schema used `source` instead of the driver's
`code` field. The aborted run and a schema-only correction note remain in
`core01-scalar12/`; actual 12/12 measurements are in
`core01-scalar12-schema2/`. All twelve program bodies were preserved.

The original typed02 10/12 result remains in `typed02-arrays12/report.json`.
Its two differences must not be overwritten by future repaired runs. The
by-value snapshot fix is present in combined03. Its actual correction, together
with reference display/separation, was confirmed on composed06's unchanged
12-array source programs. The further reference32+4 source comparisons are
recorded separately in `reports/php-reference-display-20261113/`.

## Verification boundaries

The byte runtime's 75 protocol comparisons, 4 raw outputs and 64-bit storage
contracts; symbol component's 218 actual lookups plus separate contracts; and
native byte bridge's 34 comparisons plus guards/contracts are **component
evidence**, not interpreter-source passes. Their reports live under their own
directories. Native ModuleInfo has two preserved raw-output differences; no
header stripping or normalization converts those into matches.

Official PHP 8.5.12 observations for 19 string-offset source programs are in
`string-offset-oracle01/`. That run invoked no candidate. The cases include
signed offsets, coercion/warnings, extending a string, assignment return values,
nested immutable values, empty/append/compound/reference errors. JSON fixtures
are similarly inputs for future strict source comparisons, not pass receipts.

Full PHP compatibility, exhaustive validation, all string/stdlib operations,
all byte diagnostics/traces/symbols/source and OS IO boundaries, complete
64-bit behavior, native modules/arrays/objects/resources/GC/lifetimes, Web SAPIs
and Linux execution remain incomplete. JSON retains the existing limited
one-argument encode/two-argument decode profile and still materializes text for
serialization/parsing. Full flags, JsonSerializable and giant streaming JSON
are not claimed. ALL stage 2 has not started.

The composed07 callback14+raw2 failures preserve the original PHP programs. A
previous draft note calling `\xFF` in these programs a literal backslash value
was wrong: those are PHP escape syntax that produces raw FF at execution. The
oracle output confirmed this. No program or expected output was changed to
avoid the failing conversion. Composed09's critical3 subsequently verifies a
raw variadic callback with four arguments, a builtin callback receiving four
arguments, and a raw FF undefined-key diagnostic. These three do not replace
the original failed40 run or prove the full40 was rerun.

The selected native integration on combined03 also completed: legacy23/23,
callback15/15, raw4/4 match, with guards4 separate. All source processes exited,
with unchanged inputs and controlled cleanup verified. Evidence is in
`native-integration-verification01/`. This predates Symbol/Reference/later value
changes and is not automatically certification of every later candidate.

Native/CLI tests are scheduled as separate bounded loops to limit interference.
The active goal remains active; this report is a checkpoint, not completion.
