# Import alias collision candidate

Isolated source based on frozen native candidate `47c8edb9...`. Package and installed ALL were not changed by this generator.

The namespace pass now rejects duplicate aliases in the same symbol space before executing PHP statements. Class/function aliases use case-insensitive comparison; constant aliases use case-sensitive comparison. Separate symbol spaces and each new namespace declaration retain their own imports. The error is built from actual import tokens and their line metadata, rather than from reference output.

In CliContext the diagnostic and actual exit status are reported as a compilation fatal. Other callers receive an explicit error. This does not implement all namespace compilation errors, reserved aliases, declaration/import conflicts or invalid import placement.

`Build-ImportAliasCandidate.py` checks the complete input hash before building the candidate and a minimal patch. Final source hash: `c6dcc044e58682100eaba867381eb04f415364218ab981d04240d7fe8cdc016c`.

Same-source strict process comparisons against PHP 8.5.12 are preserved in `reports/php-import-alias-20261112/`:

- Before: 4/17 matched, 13 differences.
- First fix: 17/17 matched; additional line tests were 3/4, with a diagnostic line difference.
- Corrected final source: **23/23 matched**, including the line tests and split function/constant imports. All measured inputs were unchanged.

All stdout/stderr bytes and actual exit statuses are compared without normalization. These selected examples are not complete PHP compatibility.

```powershell
python -B tools/candidates/php-import-alias/Build-ImportAliasCandidate.py
python -B tools/candidates/php-v3_18/Compare-Cli.py --adapter tools/candidates/php-import-alias/ALL_PHP_import_alias_candidate.ps1 --cases tools/candidates/php-import-alias/final.cases.json --output reports/NEW-import-alias --timeout 30
```

Use a fresh report directory. Full default regression and integration with the other candidates are separate required checks.
