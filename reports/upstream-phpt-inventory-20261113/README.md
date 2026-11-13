# Pinned PHP8.5.12 upstream test inventory

The test archive SHA-256 is `79df191cab418a5277e7ad504143255c7b7ead06a2e6ebfa3b5b24503e94a519`.
All **22,280 PHPT files** in it were inventoried, and the existing extracted source tree has the same file set and exact bytes. No files were removed according to feature support, extension/SAPI/OS, INI, SKIPIF or prior outcomes.

Every record in `run-01/upstream-phpt.jsonl` remains **UNVERIFIED**. This operation executed zero oracle/candidate tests. It establishes source identity and a complete file catalogue for this pinned archive, not complete PHP requirements or a conformance percentage.

SAPI/build/platform applicability still needs assessment. The catalogue includes tests that may be outside the owner's specified CLI/Web SAPI set or conditional for a different build; merely appearing here does not silently expand or shrink the approved target. A future runner must retain and explain each applicability/skip/unsupported condition rather than count it as a successful candidate test.

Header-shaped lines are scanned as bytes with their offsets. These are not interpreted PHPT sections: `FILEEOF`, nested delimiters, INI, request/environment/cleanup semantics and expected-output matching require the official format rules. `run-tests.reference.php` is an exact reference copy with its hash, accompanied by the upstream license; it is not part of the ALL runtime or an execution backend.

`run-01/summary.json` contains area/header scan counts, source/archive hashes, driver argv/hash and the inventory limitations. Individual source hashes must be rechecked before later execution.

```powershell
python -B tools/phpt/Inventory-PhpTests.py --output reports/NEW-upstream-inventory
```

The command refuses to overwrite an existing report or accept a different archive pin. Source files are read only.
