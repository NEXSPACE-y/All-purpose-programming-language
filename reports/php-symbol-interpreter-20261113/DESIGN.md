# Valid UTF-8 symbol bridge

This isolated patch advances the approved byte-value model while keeping the
current strict text source decoder and text metadata. It does not apply the raw
PhpSymbolKey registry model or introduce another execution engine. The separate
byte-symbol component and its 226+22 observations remain independently pinned.

Existing valid-text registries receive two explicit StringComparer instances:
ASCII-only fold for functions/class-like names/methods/import aliases, and
namespace-prefix-only fold for named constants. Ordinal dictionaries continue
to store raw-sensitive variables, properties, parameters, class-constant leaves
and constant import aliases. Equality over strictly decoded UTF-8 text can use
UTF-16 ordinal equality without changing byte identity; culture comparison and
Unicode normalization cannot. Internal comparer hashes and its UTF-16 ordering
are not Zend hashes or PHP byte-value ordering and are not persistent IDs.

The 19 old OrdinalIgnoreCase sites are PHP-name tables and sets. Host paths,
modules, native catalogs and DLL validation retain their own rules. Three
full-name constant registries receive the prefix-aware comparer; per-class
constant tables keep exact leaves. Name comparisons outside dictionaries use
explicit ASCII or raw ordinal helpers for inheritance, traits, scope, properties
and named parameters. Source spelling stays on existing descriptors. A new
object stores its selected declaration's class spelling, so `new cAt()` after
`class CaT {}` reports `CaT` through `get_class`.

The existing text lexer and identifier checks accept U+0080..FFFF code units in
addition to ASCII letters/underscore/digits. For strict valid UTF-8 input, this
also preserves supplementary scalars as two accepted surrogate units. It admits
PHP's non-letter names such as emoji, combining marks and NBSP. Token whitespace
is limited to PHP's four source whitespace bytes; decimal token recognition is
ASCII-only so a non-ASCII digit can remain an identifier. Existing heredoc label
support already used this extended range. PHP-owned string callable array values
cross an explicit strict UTF-8 metadata boundary before class/method lookup.

The negative control `brea` followed by Kelvin sign must stay an identifier.
PowerShell's default comparison can merge it with keyword `break`, so selected
token keyword decisions and expected syntax tokens use ASCII helpers too.
This is an incremental parser correction; every reserved word, grammar context,
case-sensitive token decision, magic API and duplicate symbol context is not
certified by this profile.

The module has exact fragment/count guards and preserves original CRLF/LF.
Measured revisions copy both their actual starting adapter and exact module
source. The unchanged original identifier examples are retained, and new source
examples are separate entries. No historical expected result or report is edited.

Remaining work includes non-UTF8 source and symbol transport, byte token spans,
raw symbol registries and all dynamic lookup APIs, complete declaration/error
semantics and duplicate namespaces, native name catalogs, portable packaging,
Linux and SAPI execution, and whole-interpreter regression. Those boundaries
must not be certified from the focused symbol profile.
