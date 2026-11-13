# Symbol identity boundary

`ForName(kind, logicalName)` receives a resolved registry name. `ForMember`
receives resolved class/container identity and a separate member name. Both
consume immutable PhpBytes. Neither decodes text, validates lexical grammar,
removes a leading backslash, expands an import alias, resolves inheritance,
or coerces numeric strings. Validation and qualification are caller operations.

| Domain | Lookup normalization |
| --- | --- |
| Function, ClassLike, Method, Namespace | ASCII A-Z to a-z only |
| FunctionImportAlias, ClassImportAlias, Keyword | ASCII A-Z to a-z only |
| Variable, Property, Parameter | All bytes exact |
| Constant | Namespace prefix ASCII fold; last name segment exact |
| ClassConstant, ConstantImportAlias | All leaf bytes exact |

ClassLike is shared by classes, interfaces, traits and enums. Those descriptor
kinds must not become separate registry identities. Method/property/class
constant container keys fold the resolved class bytes; methods fold the leaf,
properties and class constants retain exact leaf bytes. For a per-class table,
the owner may stay implicit and `ForName` can represent the leaf. Explicit and
implicit container keys are distinct. Private property ownership, class aliases
and inherited descriptors must be resolved by the caller before a container key
is formed. Compiler alias table scope/lifetime remains a separate concern.

Original declaration bytes must stay on descriptors: a dictionary may retain
the first equal key even after replacing its value. `OriginalParts` preserves
input bytes for inspection but is not authoritative declaration metadata.
Equality compares domain, container flag and normalized byte parts. Internal
hashes are not persistent IDs or Zend ABI hashes. Collisions use full equality.
Member parts are never flattened with a delimiter; embedded NUL/colon bytes do
not change tuple boundaries.

Full source migration must read source bytes without replacement decoding,
recognize identifier start `[A-Za-z_\x80-\xff]` and continuation with added
ASCII digits, and use PHP's byte whitespace rules. .NET `\w`, `\s`, Unicode
letter predicates, Unicode case conversion, normalization, PowerShell `-ceq`,
and OrdinalIgnoreCase do not implement these rules. Long byte offsets/token
spans must remain long until checked small interop. Every identifier-dependent
regex/interpolation/member/parameter/type reader in the frozen audit inventory
must be addressed; patching just dictionary comparers is insufficient.

Registry lookups should create these keys after source/runtime qualification,
store declaration spelling separately, and audit dynamic string-to-symbol APIs.
Host path/module identities and trusted internal AST tags retain their own
rules. Native ABI names/catalogs still transported as text require an explicit
byte boundary before invalid-UTF8 symbol coverage can be claimed. The existing
native C++ lower helper already folds ASCII only and should be retained.

The 218 direct oracle observations substantiate these domains for listed cases;
autoload, magic methods, private scopes, duplicate declarations, all reserved
words and every grammar context are not certified by this component. Production
byte lexer/registry adoption and whole-interpreter regression remain pending.
