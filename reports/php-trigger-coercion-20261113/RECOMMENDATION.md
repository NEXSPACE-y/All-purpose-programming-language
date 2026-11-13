# trigger_error / user_error boundary observations

The official reference executed 71 weak and 71 strict observations, each process
exiting zero with empty stderr. Diagnostics were captured independently of
exceptions. Calls include lowercase, uppercase and leading-backslash spellings.

For the supported weak mode, Root's direct To-PhpBytes repair preserves raw
messages but does not enforce PHP argument conversion. Null must emit E8192 then
become an empty message; array and non-Stringable objects produce TypeError
without an Array-to-string warning. Stringable objects may return raw FF. Scalar
values convert through the usual weak string conversion. Strict mode rejects
null/scalars/Stringable for the string parameter; strict caller state is still
unimplemented and must not be claimed covered by the weak helper.

Use the existing own ConvertTo-PhpBuiltinBytes for parameter 1 named `message`,
and ConvertTo-PhpBuiltinInteger for parameter 2 named `error_level`, with the own
arity helper for one to two arguments. Ordinary invalid level validation remains
after conversion. In weak mode a null level emits its int deprecation then the
existing ValueError; an array level raises TypeError, and 512.5 becomes 512 with
a precision-loss deprecation. Alias error names are canonical lowercase alias
names: trigger_error and user_error remain distinct even when called uppercase
or with a leading backslash. Logical builtin names at this interpreter boundary
already have leading qualification removed; ConvertTo-PhpAsciiLower preserves
the alias while canonicalizing ASCII case.

The other composed07 `To-PhpText $callArgs` sites were reviewed separately:

| Site | Existing role and remaining limit |
| --- | --- |
| define / defined / constant, three sites | Current valid-UTF8 symbol-name boundary; raw names need byte-symbol registry/API adoption |
| ini_set / ini_get name, two sites | Current configuration-name metadata; complete directive catalog/validation and byte name transport remain |
| ini_set value, one site | Currently text configuration metadata; PHP-visible raw INI values/defaults/extensions need their own byte boundary and return-value work |
| function_exists name, one site | Current valid-UTF8 function registry/native-catalog boundary; do not fabricate false for unsupported raw names |
| trigger_error message, one site | Actual PHP string data; must use typed builtin byte conversion |

These roles do not justify replacing every text callsite with bytes. Full INI
semantics, raw symbols, argument ordering and strictness remain separate work.
No interpreter source or fixture was modified by this reference audit; Root
owns the new diagnostic coercion module.
