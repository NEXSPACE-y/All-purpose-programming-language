# PHP string literal candidate

Final isolated candidate: `revision05/ALL_PHP_string_literal_candidate.ps1`, SHA-256 `e150594bb520e984fcb61a9288b695a044271b11559dcc5d8ceda4fae9ab3bb2`.

The candidate adds whole-token heredoc/nowdoc lexing, flexible indentation and the verified error-order distinctions, quoted/binary prefixes, simple interpolation, and byte-accurate escape decoding when the resulting value has a strict UTF-8 representation. `\u{...}`, hex/octal byte sequences, NUL, CR/LF/CRLF payloads, unknown escapes and compiler diagnostics are covered by selected actual-process comparisons. PHP source is not rewritten or delegated to PHP.

**45/48 final examples match exactly; 3 non-UTF8 byte-value cases remain different. PHP compatibility is NOT_COMPLETE.** The three cases stay in the report total. Original default API v3.3 contracts and guards are unchanged and pass 52/52 on this exact candidate.

See [measurements, failed revisions and limits](../../../reports/php-string-literals-20261113/README.md) and [integration contract](INTEGRATION.md). Package has not been changed. Full965, composition with the root's CLI file lexer and callback/dynamic-call edits, native regressions, Linux and Web acceptance are separate work.

Generate only into a fresh directory:

```powershell
python -B tools/candidates/php-string-literals/Build-StringLiteralCandidate.py --output-directory tools/candidates/php-string-literals/NEW_REVISION
python -B tools/candidates/php-string-literals/Compare-Literals.py --adapter tools/candidates/php-string-literals/NEW_REVISION/ALL_PHP_string_literal_candidate.ps1 --cases tools/candidates/php-string-literals/final48.cases.json --output reports/NEW-literals --timeout 30
C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/candidates/php-string-literals/Check-DefaultStringContracts.ps1 -AdapterPath tools/candidates/php-string-literals/NEW_REVISION/ALL_PHP_string_literal_candidate.ps1 -ReportPath C:\absolute\NEW-default52.json
```

The generator checks the complete113d package input hash and preserves earlier candidate files. Its fragments and generator snapshot are retained in each later revision. Comparisons use exact stdout/stderr bytes and real process exit status; no normalization is performed. `Compare-Literals.py` is an owned copy of the strict CLI driver with an incremental raw case journal, not an alternative implementation or expected-output generator.
