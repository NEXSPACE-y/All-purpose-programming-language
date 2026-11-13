# Dynamic callable resolution candidate

**Independent candidate; not adopted into package; not full PHP compatibility.**

The fixed base is the actual v3.19 package adapter, SHA-256
`113d0c2b967a8726cd9a9dec3f032a725ed9c98ee093c4aedd0a4830737f155b`.
The current revision06 source is
`3ab4d48af3eb26a69ebb99b45b93202dba453f752b966de7b0414c3d5d1ae36b`.
The generator rejects a changed base or an existing output directory. Revision06
retains the complete base, helper and generator snapshots and a minimal diff.

## Behavior changed

- Resolve and validate dynamic callee values before evaluating their arguments.
  Missing function names raise a catchable PHP Error; null/scalar, object and array
  callee failures use their measured PHP categories and messages. One leading
  namespace separator is removed for lookup. Runtime strings do not implicitly
  acquire the source namespace.
- Validate dynamic first-class callable creation immediately. Known function,
  instance-method and static-method callable values retain their selected target.
  An array target is bound before an argument can mutate the source array variable.
- Preserve the measured difference between a direct known-global/qualified/imported
  `call_user_func`/`call_user_func_array` call, which binds its callback first, and
  a dynamically invoked builtin or an unresolved namespace fallback, which first
  evaluates ordinary arguments. The frozen official compiler was read as reference
  (`zend_compile_func_cuf`/`cufa`); no PHP C implementation was adopted.
- Preserve names and reference cells in `call_user_func_array` argument arrays.
  A by-value argument sent through these callback APIs to a reference parameter
  produces the PHP warning and a temporary cell. A real reference cell remains shared.
- Parse array literal references to existing lvalues (`[&$x]`, `['key'=>&$x]`,
  `array(&$x)`) using the interpreter's existing refcell and lvalue operations.
  This supplies the actual shared cell required by `call_user_func_array`.

The default API's known undefined-function legacy exception text is retained through
`Throw-PhpError`'s legacy-text argument. Existing package fixtures and their expected
values are not edited. Full default regression is still a separate integration check.

## Evidence and preservation

See [measurements](../../../reports/php-dynamic-call-20261113/README.md).

- Actual base: 4/30 exact process matches, 26 differences.
- Revision03 critical control examples: 4/4 matches.
- Revision04: 46/52 matches. Four timeouts, an incorrect warning name and an existing
  unsupported array-reference expression were retained as non-PASS observations.
- Revision06: 13/13 rechecks/reference cases match exactly, with stable input hashes.
- Final revision06: **73/73** exact process matches, actual comparator exit0, inputs
  unchanged. All 73 source bytes and commands were independently rechecked against
  the original case definitions and exact revision06 adapter path.

The original private-Throwable14 sources are included unchanged in the final profile;
`final73-input-provenance.json` maps all source bytes to their original inputs.
The groups overlap and must not be summed as feature coverage or a compatibility rate.

Revision02 contained a generated empty `StartsWith` literal that removed an initial
character. Its two measurements were intentionally stopped after confirming that
implementation defect. The incomplete results and terminal process observations are
preserved separately; they are not reported as completed conformance runs or hangs.

## Reproduce

Choose fresh paths; preserve measured revisions.

```powershell
python -B tools/candidates/php-dynamic-call/Build-DynamicCallCandidate.py --output tools/candidates/php-dynamic-call/NEW-revision
python -B tools/candidates/php-v3_18/Compare-Cli.py --adapter tools/candidates/php-dynamic-call/NEW-revision/ALL_PHP_dynamic_call_candidate.ps1 --cases tools/candidates/php-dynamic-call/final73.cases.json --output reports/NEW-dynamic73 --timeout 30
```

The runtime does not execute stock PHP. The comparison tool runs stock PHP only in
the independent reference process and compares raw stdout, raw stderr and actual
exit status. No normalization, output replacement or fixture changes are used.

## Remaining boundaries

This is not complete callback semantics. Magic-method/autoload dispatch, complete
access-scope capture by first-class callables, relative/self/parent spellings,
closure diagnostic names/frames, every arity/type error, named outer builtin calls,
argument unpacking, general return references inside array literals, typed-reference
binding and all resource/native identities still require further work and evidence.
The existing typed-callable predicate and registration APIs are not comprehensively
replaced by this resolver. No Linux or Web/SAPI behavior is established here.

Rollback is to keep package113d and omit this patch. The original installed ALL,
package, old fixtures, frozen native core and other agents' candidates were not changed.
