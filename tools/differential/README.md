# Strict process comparisons

`evaluate.py` runs the same PHP source file through the official oracle and ALL's
independent PowerShell candidate in separate child processes. Only the oracle
process executes php.exe. Candidate execution uses `PhpCandidateWorker.ps1`.

The comparison preserves stdout bytes, stderr bytes and exit status exactly.
Whitespace, CRLF, binary output, diagnostic paths and return codes are not
normalized. A timeout is never a pass, including matching partial timeouts.
Each report includes input hashes before/after, exact commands and source files.
Existing output directories are refused rather than overwritten.

The historical fixture and PHPT harnesses remain unchanged. Their old counts
must not be compared as if they used this stricter process protocol.

`core-smoke.cases.json` is a deliberately small diagnostic sample, not a complete
requirements inventory or a coverage denominator. Side effects, input streams,
Web SAPI, extensions, ABI, scheduling, performance and memory limits need further
dedicated measurement. Even a full pass of this sample is NOT_COMPLETE.

Comparator regression tests: `python -B -m unittest discover -s tools/differential`.
The worker explicitly loads the Windows PowerShell 5.1 Utility module, so a
PowerShell 7 module directory inherited from the launching environment cannot
replace that module by autoload.
