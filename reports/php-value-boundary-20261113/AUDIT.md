# PHP value versus metadata boundary audit

Input is immutable json05 SHA256
`524ce86a322c0cd91d1f565a0c01a754842efbacd8521a47b6f3b4a56150bb8d`
after selected SymbolEdits SHA256
`4853ac24f16c2a792dd5836bc8eaeba05335a9e255b9810b898999751ab634c3`.
The exact post-symbol source is preserved. Its textual inventory has 430 hits;
that is a review index, not 430 defects or a proof of exhaustive dataflow review.

The local ValueBoundaryEdits patch addresses these PHP value paths:

| Boundary | Applied source change |
| --- | --- |
| is_numeric | Accept PHP-owned strings through the existing numeric parser |
| Enum case declaration | Accept PhpBytes, deduplicate by typed content equality without string casts, expose name as a PHP byte value |
| Backed enum lookup | Compare string backing bytes exactly; NFC/NFD and invalid UTF8 stay distinct |
| Enum ValueError | Keep a failed raw value in a byte-built message; preserve the old host legacy text |
| Match/trace argument text | Render byte content as escaped ASCII, truncate by byte count; never decode raw values as UTF8 |
| Throwable storage | Convert only PHP-visible file and __trace values to PhpBytes; state.ScriptName stays text |
| Getter/known constants | Normalize PHP-visible class and constant return values; registry metadata stays text |
| Static reference/first-class array callables | Explicitly convert selected class/method values at the current valid-UTF8 name boundary |
| instanceof dynamic RHS | Recognize a PHP string value, then cross the explicit name boundary |

The reference programs are oracle-only. No PHP binary is called by the
candidate. Actual PHP 8.5.12 observed 256 individual byte representations,
11 combined/control strings, limits 0/1/3/15 and argument suppression. It escapes
high bytes and controls into ASCII, leaves single quotes literal, escapes
backslashes, and counts source bytes before expanding escapes. Enum failure
messages retain raw bad-value bytes instead of using the trace escaping rule.
These are reference observations; the new interpreter patch has only been built
and parsed at this point, not run against those examples.

Format-PhpStackTrace remains a text builder over valid-text source/frame
metadata and the new ASCII argument representation. It is converted to the
PHP-owned __trace byte value at Throwable creation. Get-PhpThrowableString and
the new native/diagnostic byte path already consume these PHP values through
To-PhpBytes. No replacement decode or raw-value Get-PhpHostText is inserted in
the argument representation. The helper reads ordinary nonnegative integer
limits and common bool INI spellings from metadata; full INI validation is not
implemented by this patch.

The following hits were deliberately retained or remain pending:

- Source/token strings, AST kind tags, paths, dictionary registry names,
  declaration owners/types and native control fields are metadata.
- String callee checks after Assert-PhpValueCallable are valid-text metadata:
  Core already normalizes scalar names there, and Symbol handles array pairs.
- Get-PhpCallableArity receives a PHP value before that normalization. Simply
  decoding its string would revive the old truncation of a variadic error
  handler's four arguments to its one declared parameter. Callback argument
  count semantics require a separate correction; that check is not changed.
- Format-PhpVarDump remains an old text formatter reached by the object fallback
  from Format-PhpBytesDump. Raw PHP string object properties need a complete
  byte object renderer, not a strict UTF8 conversion added here.
- Stack trace records are currently rendered/cached at Throwable creation.
  Full getTrace/getTraceAsString semantics and changes to rendering INI after
  creation require structured trace records, not merely this boundary patch.
- Backed enum weak/strict argument coercion, invalid argument classes, duplicate
  declaration timing, builtin call frames and complete enum type diagnostics are
  not certified. The reference confirms string enum from(7) can select '7'; that
  pre-existing coercion gap is not hidden by the string-kind correction.
- A bare class_name AST node currently also carries class metadata. Its fallback
  name is not blindly converted into a PHP byte value. Known constant branches
  are normalized separately.
- Raw source/names, invalid OS name transport, huge text trace construction,
  native/SAPI/Linux validation and the complete PHP target remain unfinished.

JSON functions are owned by root and were not modified. Package/installed
adapter, root's source and the canonical byte runtime were not changed.
