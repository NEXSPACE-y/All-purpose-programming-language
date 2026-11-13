# PHP literal measurements

**Final candidate e150594b: 45/48 exact process matches, 3 byte-model differences retained. Full PHP compatibility remains NOT_COMPLETE.**

The fixed Windows x64/ZTS PHP8.5.12 oracle is a separate process, SHA-256 `0ac893499799256db6d3a54b0da73692e02311493922e6e4f86a062674a77d66`. The independent candidate executes in the explicit Windows PowerShell5.1 worker. Same PHP source paths are supplied to both, and stdout/stderr raw bytes and actual process status are compared without substitution, trimming or newline conversion. Each process has the original30-second timeout.

| Revision / observation | Result | Meaning |
|---|---:|---|
| base113d / original33 | 1/33 match | `baseline33/report.json`, original inputs retained |
| revision01 60f2ea88 / original33 | 28/33 match | One TIMEOUT, three byte limitations and one indentation diagnostic difference retained |
| revision04 e20751fe / extended42 | 38/42 match | Three byte limitations and a newly exposed diagnostic-order difference |
| final revision05 e150594b / final48 | **45/48 match** | `revision05-48/report.json`; all measured inputs unchanged, no timeout |
| final revision05 / original49 v3.3 plus3 guards | **52/52 PASS** | `revision05-default52.json`; original expected values and fixture hashes unchanged |

The first revision's `literal.unicode-unknown` process timed out with no captured output. It remains a failed observation. The later final candidate matches the same source with actual exit0; the timeout cause is not established, and these runs were not a controlled performance comparison. Earlier reports were not overwritten.

The final three differences are `literal.octal-ascii`, `literal.binary-invalid-byte` and `literal.binary-surrogate`. The first historical ID includes an octal overflow producing byteFF; it is not an all-ASCII case despite that ID. The official oracle returns byteFF or UTF-8 surrogate encoding ED A0 80. The .NET-string candidate explicitly rejects those values. These are **not conformance passes**, and are not removed from48 or from the project's remaining requirements. Valid UTF-8 hex/octal sequences and an overflow producing NUL are separately verified. No replacement character or official-PHP fallback is used by the literal implementation.

The additional six `mixed-indent-oracle/` cases are official-process-only probes used to establish compiler error precedence. Final48 includes the same sources on both processors. A heredoc's literal segments before interpolation can fail indentation checks before a malformed closing marker is reached; nowdoc/non-interpolated bodies detect the malformed marker before committing the pending token newline count. Both diagnostic text and source lines are measured. The fixed official source archive and scanner entry hashes are in `official-source-reference.json`; source was read for specification evidence, and no PHP C component was adopted.

The original52 contracts include3 fail-closed guards, including the existing refusal of unsupported complex interpolation. Their pass count is a regression result, not52 successful PHP language features. The default API's quiet undefined interpolation result remains `xy`; CliContext/PhpDiagnostics correctly expose the missing-variable warning. Literal escape validation does not execute interpolation or reject unsupported interpolation in unexecuted branches.

The final candidate has not been copied into package. Full default965 regression and composition with CLI file modes, dynamic calls, native callbacks, all native/module profiles, Linux and Web remain separate/unverified. Other arbitrary byte strings, complex interpolation and all malformed lexer/parser diagnostics are not established by these examples. See [candidate/integration instructions](../../tools/candidates/php-string-literals/INTEGRATION.md).

`assessment.json` records verified hashes and counts. `artifact-manifest.json` indexes this task's files except itself; it is integrity evidence, not a full compatibility certificate.
