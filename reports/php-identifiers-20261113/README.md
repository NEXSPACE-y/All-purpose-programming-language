# Identifier and comparison read-only audit

**No production comparer/lexer change. PHP full compatibility remains NOT_COMPLETE.**

The audited candidate is an exact frozen snapshot of observed package source113d,
SHA-256 `113d0c2b967a8726cd9a9dec3f032a725ed9c98ee093c4aedd0a4830737f155b`.
The parent may update its live package independently; this audit is not relabeled as
a measurement of later sources.

| Evidence | Actual result | Scope |
|---|---|---|
| baseline32/report.json | 8/32 matched; 24 differences; no timeouts; inputs unchanged | Actual identical source bytes, raw stdout/stderr and actual exit values |
| registry7/report.json | 1/7 matched; 2 output mismatches and 4 TIMEOUT observations | Additional constant-prefix controls; matching output on a timeout is not PASS |
| php-comparisons/report.json | 15 function-lookup pairs agree with ASCII-byte fold | Official PHP registration/lookup, not a candidate comparer implementation |
| dotnet51-comparisons.json |15 actual framework/operator observations | PS5.1.26100.9818, CLR4.0.30319.42000, current culture ja-JP |
| registry-rules/report.json | Namespace prefix/constant leaf/property/method distinctions recorded | Official reference API behavior |
| all-byte-case-reference/report.json | All256 lowercase and uppercase bytes equal ASCII-only maps | Official strtolower/strtoupper behavior |
| all-name-byte-reference/report.json |512/512 byte-position classifications agree with scanner LABEL | Official tokenizer only, not all parser contexts |

The baseline rejects valid Japanese/emoji/NBSP/combining/raw80/rawFF identifiers.
It also shows wrong non-ASCII strtolower, strict value/key equality, UTF16-versus-UTF8
ordering, and class declaration spelling. Dynamic Unicode variable/constant-key
controls preserve some distinctions, so the data must not be summarized as every
Unicode-related operation being broken.

The registry7 timeouts are retained as non-PASS. The constant namespace rule is
established separately by the successful native registry API observation, actual
stdout differences in two terminating candidates, and the pinned official source.
No timeout cause is inferred and no output is normalized to turn it into a pass.

The official scanner's byte LABEL/ASCII whitespace rules and constant-prefix lowering
are recorded in `official-source-reference.json` and `constant-prefix-source-reference.json`.
PHP C source was read as reference; no component was adopted or compiled here.
The baseline uses the own interpreter; stock PHP runs only in independent reference
processes. Inputs and all original source bytes were preserved.

See the [design proposal](../../tools/candidates/php-identifiers/DESIGN_READ_ONLY.md)
and [probe tools](../../tools/candidates/php-identifiers/README.md). These counts do
not form a PHP compatibility percentage or prove any complete feature family.
