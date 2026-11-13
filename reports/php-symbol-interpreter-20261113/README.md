# Focused valid-UTF8 symbol interpreter evidence

Selected module: `tools/candidates/php-byte-interpreter/SymbolEdits.py`.
Selected candidate: `revision04/ALL_PHP_symbol_candidate.ps1`.
The actual starting adapter is root's immutable `typed02-cli` candidate; each
revision keeps its exact own `base.snapshot.ps1` and module snapshot. The package,
installed adapter, decoder, byte runtime and other agents' source were not edited.

| Measurement | Result | Meaning |
| --- | --- | --- |
| before10 | 0/10 | Actual pre-symbol candidate; all processes exited |
| revision02-critical3 | 3/3 | Initial compilation/runtime smoke controls |
| revision02-after40 | 38/40 | Two dynamic-variable PhpBytes rejection differences |
| revision04-recheck8 | 8/8 | Same two original failures plus six controls after local correction |

All listed measurements pin the actual source/binaries/worker, compare exact
stdout bytes, stderr bytes and actual process exits, and retain raw channels.
All inputs remained unchanged. Every oracle and candidate process exited;
none timed out. These are selected profiles, not full PHP compatibility or
whole-interpreter regression. There is no completed final same-hash 40-case run.

The final correction changes the dynamic-variable type check to recognize
PHP-owned PhpBytes and explicitly decodes the valid-UTF8 metadata boundary.
The successful 38 examples ran on revision02 and are not silently relabeled as
revision04 results. `combined03-static-composition03.json` confirms the final
module also composes through its exact guards on root's later combined03
candidate, but that composed result has not been executed by this agent.

The original 29 retained identifier examples are unchanged. Eleven new PHP
source examples test NFC-distinct parameters/properties/methods, Unicode class
separation, constant prefix/leaf rules, array callables, non-ASCII digit names,
Kelvin-sign keyword confusion and ASCII keyword case. Exclusions are explicit:
the existing raw-80/FF source failures remain in the frozen identifier audit,
and strtolower belongs to the separate byte-string builtin migration.

Revision01 and revision03 were built but not runtime measured. They are retained
as unselected drafts. `revision01/parse.json` records a parser harness invocation
failure (PowerShell -Command appended the filename as script text). The corrected
stdin-based `parse02.json` parsed the actual candidate successfully. It is not
an implementation failure or a fabricated PHP runtime result.

See `DESIGN.md` for the current metadata bridge and remaining raw-name, source,
native catalog, packaging, Linux, SAPI and conformance boundaries. The separate
raw byte-symbol component stays under `php-symbol-runtime`; its success does
not certify all-raw source lexer adoption here.
