# Byte-string design proof

**Isolated component only; PHP core adoption and full compatibility are not complete.**

[The concrete design](../../docs/design/PHP_BYTE_STRING_DESIGN.md) evaluates immutable tagged bytes, a Latin1 carrier string and native handles against the actual113d source dependencies. It recommends immutable typed bytes, separates raw array keys from context-dependent symbols, and records the approval,64bit storage, migration and rollback boundaries.

| Evidence | Actual result | Scope |
|---|---|---|
| `component01/report.json` | 67/70 protocol records match; raw4/4 | Initial implementation defect retained |
| `component02/report.json` | 70/70 records, exact channels and real exit match; raw4/4 | Corrected DLL, original input cases unchanged |
| `component02-extended75/report.json` | **75/75 records**, exact channels and real exit match; raw4/4; hashes stable | Adds actual byte strict equality and distinct Unicode array keys |
| `component02-boundaries.json` | **4/4 synthetic checks** | Immutable input/export copies, strict UTF8 boundary, implicit text refusal, explicit prototype storage capacity guard |
| `dependency-inventory-pinned113d.json` | Fixed-source static inventory | Review cues only, not an exhaustive dataflow analysis or implementation count |

The reference is fixed PHP8.5.12 Windows x64/ZTS, SHA-256 `0ac893499799256db6d3a54b0da73692e02311493922e6e4f86a062674a77d66`. Its worker performs the requested component operations on the same JSON input. The C# worker loads the independent managed DLL. Neither path is an ALL PHP source execution test. The protocol contract uses base64 payload fields and explicit warning/error records; its bytes are compared without normalization. Separate echo/raw-write processes compare actual FF/NUL/ED A0 80/all256bytes on stdout, empty stderr and process exit.

The initial three protocol differences were comparison return values: the component returned raw byte differences whereas the target PHP process returned±1. That implementation was corrected. Original67/70 records, DLL build metadata and source snapshots remain in`component01/`. The later protocol workers gained an equality operation; their preceding source revisions are preserved under`component02/` rather than rewriting the old evidence.

Negative controls demonstrate why existing host text APIs cannot silently serve as PHP bytes: Latin1 FF reencoded through UTF8 becomes C3 BF; carrier/ordinary Unicode lower alter bytes that PHP ASCII-only lower preserves; UTF16 ordinal ordering of U+10000/U+E000 is opposite to byte ordering. The values are recorded in`component02-boundaries.json`. These are evidence against accidental alternatives, not additional PHP feature passes.

No production adapter or frozen literal candidate was edited. The mutable package may advance through root's other work; dependency line references are pinned to immutable113d snapshot bytes. Linux, PHP parser/stdlib/type/array integration, native ownership/ABI, Web/SAPI, large/segmented storage, all offset coercions and ALL shared-data implementation remain unverified or incomplete.

`assessment.json` ties the design/proof hashes together. `artifact-manifest.json` is file integrity evidence, not a compatibility certificate.
