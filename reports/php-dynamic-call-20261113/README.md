# Dynamic callable observations

**Selected examples only; full PHP compatibility NOT_COMPLETE.**

The base adapter is `113d0c2b...155b`. `before30/report.json` records **4/30**
matches and 26 actual differences with unchanged inputs. The source file on each
side is identical. Raw stdout/stderr and actual exit codes are preserved.

`oracle-observation/` and `callback-order-observation/` contain early reference
measurements. Three namespace examples in the latter were mistakenly placed inside
a try statement and are invalid PHP; their ParseErrors are retained and are not used
to establish callback evaluation order. `namespace-callback-order/` and the proper
namespace-first cases in the final profile supply the valid observations instead.
The fallback's first exploratory catch used an unqualified TypeError and did not
catch the global exception; its raw output still records the argument side effect.

`compiler-reference.json` identifies the pinned source archive, entry hash and
`zend_compile_func_cuf`/`cufa` reference functions. This is source reading, not PHP
component adoption or delegated runtime execution.

`revision02-interruption/` records an intentional stop of the known-bad generated
draft. It preserves process identities, terminal observations and the last observed
tool verdict output. The unfinished drivers had not written complete per-case JSON;
raw data for every interrupted case is therefore not claimed to exist. Only the
identified draft Python parents and their own workers were targeted. This was not a
pause of the project goal.

`revision03-critical4/report.json` is **4/4** matches. `revision04-52/report.json`
is **46/52**: four TIMEOUT observations plus two other mismatches. Two timeouts had
matching output, which does not prove process exit. The wrong `::f` warning prefix
was caused by treating a present-but-null Owner property as a method owner. The
array-reference case exposed the existing parser's unsupported `&` expression.
The callback-empty-array reason also needed the measured `array callback` wording.
Those revisions were not overwritten or treated as the final candidate.

`revision06-recheck13/report.json` is **13/13** exact matches, all actual processes
exited, all inputs unchanged. It includes all six previous failures and seven
reference-array cases. The repeated timeout cases use the same 30-second limit;
the old failures remain. No cause is assigned to the earlier timeouts.

`revision06-final73/` is the final full selected profile: **73/73 exact matches**, actual
comparator exit0 and all inputs unchanged. Every candidate/official process exited,
and all 73 actual adapter paths, identical source paths and original source hashes
were rechecked. `summary.json` retains the measured groups and limits.
It contains the original30 + extended22 + seven new reference-array programs + the
existing private-Throwable14, without changing source bytes or expected outputs.
See `tools/candidates/php-dynamic-call/final73-input-provenance.json` for that mapping.

Current source and integration limits are in the [candidate README](../../tools/candidates/php-dynamic-call/README.md).
