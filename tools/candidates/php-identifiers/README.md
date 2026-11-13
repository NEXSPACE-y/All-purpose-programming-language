# Read-only identifier probes

No core implementation is changed. `baseline113d.snapshot.ps1` is an exact copy of
the already existing adapter, not a new implementation. Its hash is pinned in
`baseline-provenance.json`. The snapshot keeps this audit stable while other work
is integrated by the parent.

`Compare-Identifiers.py` runs the same PHP bytes against stock reference PHP8.5.12
and the frozen own adapter in separate actual processes. It preserves binary source,
raw stdout/stderr, exit status, source hashes and driver/worker/binary hashes. Invalid
UTF8 identifier programs are represented as base64 without replacement decoding.
It rejects reuse of an output directory.

`Probe-DotNetComparison.ps1` records existing framework/operator behavior; it does
not install or use a new production comparer. `Probe-PhpNameBytes.php` asks the
official reference tokenizer about each possible label byte; generated fragments
are tokenized, not executed. The paired function/model and registry API observations
are retained in the report tree with exact commands and source bytes.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/candidates/php-identifiers/Probe-DotNetComparison.ps1 -PairsPath tools/candidates/php-identifiers/comparison-pairs.json -OutputPath reports/NEW-identifiers/dotnet.json
python -B tools/candidates/php-identifiers/Compare-Identifiers.py --output reports/NEW-identifiers/baseline32 --timeout 30
python -B tools/candidates/php-identifiers/Compare-Identifiers.py --cases tools/candidates/php-identifiers/registry7.cases.json --output reports/NEW-identifiers/registry7 --timeout 30
```

See [current observations](../../../reports/php-identifiers-20261113/README.md) and
[proposal and boundaries](DESIGN_READ_ONLY.md). Application of the broader lexer/key
design requires the scope decision described there. This task does not implement ALL stage2.
