# Isolated PHP symbol keys

`PhpSymbolKey.cs` supplies `AllPhp.Symbols.PhpSymbolKey`, a separate typed key
over canonical `AllPhp.ByteValues.PhpBytes`. It is independent of `PhpKey`,
which applies PHP array-key integer coercion. No production interpreter,
source lexer, registry, package, native bridge or approval ledger was changed.

The runtime01 build is pinned in `out/runtime01/build.json`. It targets the
existing Windows x64 .NET Framework compiler and canonical Byte Runtime01.
Linux execution is unverified. The source snapshot is kept beside its DLL.
The candidate never starts PHP; `Probe-PhpSymbols.php` is an oracle-only probe.

226/226 component observations passed in
`reports/php-symbol-runtime-20261113/component01/report.json`: 218 actual
PHP 8.5.12 registration/lookup observations and eight key-contract examples.
The latter include NUL/invalid lexical names and are not claims that a PHP
source/API accepts those names. Twelve registry domains, non-ASCII case pairs,
normalization/confusable controls, raw bytes 80/FF, namespace constant folding,
and class-container rules are covered. The keyword-domain check is a component
ASCII-fold contract, not a full PHP keyword lexer test.

22/22 final invariant checks passed in `invariants02/report.json`. These cover
cross-domain identity, structured container parts, readonly parts, defensive
input, colliding dictionary hashes, storage-shape equality/hash, and real byte
readback beyond Int32 length. The huge value was not fully hashed/serialized.
`invariants01` is preserved: three harness observations hit PowerShell's enum
conversion/collection-index checks before reaching CLR boundaries. The final
harness calls those boundaries through the pinned `SymbolTestHelpers.cs`.
No production/component implementation or expectation was changed for them.

The earlier frozen identifier audit remains under
`reports/php-identifiers-20261113/`: baseline32 was 8/32 and registry7 was 1/7
with four TIMEOUT observations. The symbol component results do not repair or
replace those interpreter measurements.

The report manifest excludes itself. Build products are ignored by Git and
remain at their absolute recorded paths; source/build hashes permit rebuilding.
