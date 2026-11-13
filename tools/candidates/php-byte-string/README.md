# Isolated PHP byte-value component

This is a design proof, **not an integrated PHP interpreter or a full-compatibility result**. No existing adapter, frozen literal candidate, native bridge or ALL implementation was changed by this task.

The proposal and approval boundary are in [PHP_BYTE_STRING_DESIGN.md](../../../docs/design/PHP_BYTE_STRING_DESIGN.md). The recommended representation is a sealed immutable byte value with typed array keys. The current proof uses a private managed array; a production64bit segmented/native backend remains necessary rather than treating its array limit as the PHP requirement.

`PhpByteValues.cs` implements explicit bytes, strict opt-in UTF8 decoding, concat, slice, integer-offset read/write results, byte equality/order, ASCII lower, bitwise operations, truthiness, string-key integer coercion, insertion-order overwrite and defensive copies. `ToString()` deliberately refuses implicit host-text conversion. Numeric/boolean loose comparison, every offset/type coercion, symbols/registry rules, PHP diagnostics formatting and interpreter integration are outside the component.

Final DLL SHA-256: `f5297c6522d4aa702424879c4d733c5de495b4fc18f040e0c88865771fba816f`.
Source SHA-256: `63bd6eeb6b903c2521d8b0500a8f9440d1ccba28ed4ee6f885c25cca2cd357f0`.

Actual Windows x64 / PS5.1 results:

- Final extended operation protocol: **75/75 match**, exact protocol stdout/stderr and real process exit status, all input hashes stable.
- Raw output: **4/4 match**, covering FF, NUL, surrogate encoding ED A0 80 and all256byte values.
- Separate synthetic ownership/encoding/capacity boundaries: **4/4 checks**. They are not PHP conformance cases.
- The initial component's67/70 comparison and subsequent70/70 run are preserved. The initial bug returned byte differences instead of the target Windows comparison result; the implementation was corrected, not the reference output.

The protocol workers consume the same JSON operation input. PHP is used only as the reference implementation of those operations. The C# worker loads the isolated DLL and does not parse/execute PHP source. This is intentionally distinct from the project's same-PHP-source interpreter comparisons. Protocol fields carry binary data asbase64; the separate raw-output tests compare actual bytes without any encoding or normalization.

```powershell
C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/candidates/php-byte-string/Build-ByteValues.ps1 -OutputDirectory tools/candidates/php-byte-string/out/NEW
python -B tools/candidates/php-byte-string/Compare-ByteValues.py --assembly tools/candidates/php-byte-string/out/NEW/PhpByteValues.dll --cases tools/candidates/php-byte-string/component-extended.cases.json --output reports/NEW-byte-component --timeout 30
C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/candidates/php-byte-string/Measure-ByteBoundaryContracts.ps1 -AssemblyPath tools/candidates/php-byte-string/out/NEW/PhpByteValues.dll -ReportPath C:\absolute\NEW-boundaries.json
python -B tools/candidates/php-byte-string/Inventory-ByteDependencies.py --adapter tools/candidates/php-cli-host/base113d.snapshot.ps1 --output reports/NEW-byte-dependencies.json
```

Choose fresh output paths. Build/DLL files remain locally available under ignored`out/`; source, build metadata, raw observations, failures and hash manifests are kept in the repository report tree.
