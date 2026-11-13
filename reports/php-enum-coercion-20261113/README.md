# Default weak-mode backed enum conversion

Official PHP 8.5.12 ran 104 weak and 104 strict observations over from/tryFrom,
two backing types and 26 inputs. Both processes exited zero with empty stderr;
warnings were captured separately. A third six-observation probe confirmed
canonical method names and NUL boundaries in error display.

In weak mode a string-backed enum accepts integer 7 as byte string '7'. Bool and
null prefer integer conversion; null emits a string|int deprecation. Fractional
finite floats prefer integer conversion with a precision-loss deprecation;
nonfinite string-backed inputs use string conversion and NAN warns. Existing
string inputs retain exact bytes, so '07' and '7.0' do not become '7'. Stringable
objects are accepted by string-backed enums. Integer-backed enums accept numeric
strings and reject Stringable objects. The own integer converter supplies that
numeric-string and precision-warning behavior.

Strict mode is materially different: string-backed from(7) rejects the int, and
integer-backed from('7') rejects the string. composed09 does not implement
declare/strict caller-file state. EnumCoercionEdits therefore corrects only the
supported default weak path and adds no nominal strict flag. The strict oracle
results remain evidence for the future caller-context implementation.

The isolated module normalizes from/tryFrom/cases lookup through ASCII-only
comparison, converts the argument before lookup, and preserves the original
ValueBoundary module and legacy error carrier text. Raw lookup bytes are never
trimmed. PHP's bad-string ValueError display, however, stops at its first NUL;
that diagnostic prefix is obtained with a bounded buffer and long offsets.

The candidate built on frozen composed09 passed exact apply/second-apply guards,
CRLF/LF equivalence and PowerShell 5.1 parsing. It is not runtime measured here.
Twelve new default-weak source cases are prepared without editing the original
composed07 forty inputs. Named arguments, full arity/evaluation-order handling,
all enum builtin call frames, resources, strict caller state, full enum
declaration semantics and full conformance remain incomplete.
