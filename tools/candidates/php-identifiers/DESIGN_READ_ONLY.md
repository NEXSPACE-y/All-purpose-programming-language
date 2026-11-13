# PHP identifier/byte comparison design evidence

**Proposal only. No lexer, comparer, value model or production package change is applied here.**

This work reads the observed v3.19 source113d and probes the pinned PHP8.5.12 reference
and Windows PowerShell5.1/.NET Framework APIs. The exact baseline snapshot remains
immutable while the parent integrates other work. It does not claim that the latest
parent package has been re-audited or that PHP compatibility is complete.

During this audit the root reported the owner's approval of the immutable-byte-value
and typed-key approach. This artifact still records read-only evidence: the separate
symbol-runtime component and any later source/registry migration have their own
implementation and verification state. The old audit is not retroactively called an
applied migration or a complete compatibility result.

## Confirmed requirements

The frozen official scanner defines a label byte as ASCII A-Z/a-z/underscore or
0x80..0xFF, followed by the same set plus ASCII digits. Its whitespace is ASCII
space/LF/CR/tab. This is a byte grammar, not Unicode Letter/Word/Whitespace.

- The real reference tokenizer classifies all256 byte values in both positions
  consistently with that rule: 512/512 classifications, 181 accepted start bytes and
  191 continuation bytes. This is tokenizer evidence, not all parser contexts.
- Actual execution accepts Japanese, emoji, a combining mark at the start, and NBSP
  inside names. Invalid-UTF8 identifier bytes80/FF also execute in reference PHP.
  The frozen candidate rejects these inputs; invalid UTF8 fails in its worker's
  ReadAllText before the lexer. A Unicode-letter regex alone cannot fulfill this.
- Actual function registration/lookup across15 pairs agrees with ASCII-byte folding.
  The reference strtolower/strtoupper map all256 byte values exactly as ASCII maps.
  No Unicode normalization or non-ASCII case folding is appropriate for symbol keys.

## Equality rules are context dependent

| Domain | Required lookup identity | Evidence boundary |
|---|---|---|
| Function and class names, method names, qualified namespace portions for them | ASCII fold; all other bytes unchanged | Actual function lookup matrix and ASCII registry rules; other contexts need full tests |
| Variable names, property names, parameter names, array string keys | Exact bytes, no fold or normalization | Variable controls/property API and raw-byte model; parameter contexts still need exhaustive tests |
| Global constant name | Exact leaf bytes | Native defined controls |
| Namespaced constant | ASCII-fold namespace prefix; exact constant leaf | Actual registry rules and zend_constants.c prefix-lowering source |
| Class constant | Class lookup uses its rule; leaf constant is byte-sensitive | Actual class-constant API rules |
| Function/class import aliases | Their symbol category's ASCII-fold rule | Existing source tables; full UTF8 import tests remain needed |
| Constant import aliases | Exact alias bytes; referenced fully qualified constant follows prefix/leaf rule | Existing source table plus namespace-constant tests |

Labels, enum cases, trait adaptations, internal metadata and all runtime string-name
APIs must be checked by their own contracts. Do not infer every rule from one table.
Lexical validation for a source label must not be blindly applied to dynamic API keys.
Some string-name APIs accept data that cannot appear as a lexical label.

Classes/interfaces/traits/enums share PHP's class-like name space; descriptor kinds
must not accidentally become noncolliding key domains. Import-alias tables are local
to their compiler scope and category. Runtime aliases must resolve their descriptor
before a class-member storage key is formed. Symbol keys do not perform array-style
numeric-string coercion or unmeasured root-separator/API validation.

Lookup keys and names used for display must be separate. `get_class(new cAt())`
after declaring `CaT` returns `CaT` in reference PHP; the baseline returns `cAt`.
Store original declaration bytes alongside a normalized lookup key. Other display
and diagnostic rules still require their individual PHP observations.

## Confirmed .NET mismatches

On the measured PS5.1/.NET4.0.30319, OrdinalIgnoreCase merges É/é and Σ/σ where PHP
function lookup distinguishes them. PowerShell -ieq is a different, broader relation.
Even -ceq equates K/Kelvin-sign and NFCé/NFDe+accent. It is not byte-sensitive merely
because it is case-sensitive. Fifteen pairs and exact UTF8 bytes are recorded.

The real baseline shows these are existing value bugs as well as future identifier risks:

- strtolower changes non-ASCII É/Σ when PHP leaves them unchanged.
- Strict string equality and strict array-key equality equate the Kelvin/NFC pairs.
- The loose string controls do distinguish those particular pairs.
- UTF16 ordinal ordering reverses the UTF8 byte ordering of U10000 versus UE000.

Dictionary Ordinal equality is compatible with identity for valid UTF8 strings, but
does not solve arbitrary non-UTF8 names. Its ordering is not PHP byte ordering.

## Dependency inventory

`source-dependencies.json` records118 text-search candidate sites against source113d,
including function/class/interface/trait maps, declaration sets, aliases, keyword and
prelude trigger sets, ASCII token checks, interpolation/parameter/member parsing and
ToLowerInvariant. The inventory is not a mechanically approved replacement list.

The change also reaches symbol-name comparisons using PS operators, properties and
class/owner checks, typed callable/type names, constant prefix construction, cached
resolved names, and value equality/order operations. Internal trusted AST-kind tags
are a different category and need not be globally rewritten.

The existing native core already has an explicit A-Z-only `lower(std::string)` for
function/class/method lookup. Preserve and test that behavior. C# OrdinalIgnoreCase
uses observed in the bridge are module/path identity checks; PHP symbol rules must
not replace OS-path rules indiscriminately. The managed name transport and JSON
catalog still need a raw-byte representation for non-UTF8 names.

## Proposed integration direction for owner review

1. Keep PHP source bytes authoritative and tokenize before optional text views.
   Record token byte offsets and source lines; do not normalize Unicode or drop NBSP.
   Distinguish single labels, qualified names, namespace-relative source names and
   runtime string-name lookup rather than one permissive regex.
2. Use the byte-value component proposed by the byte-string owner. Keep an explicit
   SymbolKey separate from array PhpKey. SymbolKey encodes the registry context and
   appropriate ASCII-folded and raw portions, with equality/hash over those bytes.
3. Store original names in descriptors; use normalized keys only for lookup. Keep
   caller spelling versus declaration spelling when an API requires that distinction.
4. Replace only classified symbol/value comparisons with explicit operations. Avoid
   PS -ceq/-ieq, culture-sensitive comparisons, Unicode lowercasing and normalization
   for PHP byte identity. Keep trusted infrastructure tags and host-path handling
   separate. Constant prefix folding is not the same as array-key equality.
5. Extend the native boundary for byte names/catalog fields without replacement
   decoding or silently truncated names. This remains within a reviewed independent
   boundary; it does not authorize a different execution core or PHP C reuse.
6. Verify the unchanged old965 contracts, the current actual-CLI/native profiles,
   these UTF8/raw-byte cases, every byte classifier and registry-specific/culture
   controls. Component protocol checks alone are not proof of lexer/symbol coverage.

A Unicode-regex-only extension plus a new string comparer could temporarily handle
some valid UTF8 inputs, but it leaves raw bytes, whitespace, value ordering and name
transport incomplete. It must not be substituted for the full requested end state.

This proposal changes lexical/value/key boundaries and therefore belongs to the
repository specification9.1 scope decision. Source dependencies, counterexamples,
benefits and impact are concrete; production application has intentionally not occurred.
Rollback is to keep the current package and omit this proposed migration. The exact
113d snapshot and original fixture definitions are preserved. No ALL stage2 work is included.
