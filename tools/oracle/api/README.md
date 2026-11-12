# PHP 8.5.12 reference API inventory

This tool collects metadata from the **official reference PHP process only**. It
does not execute the ALL candidate, implement an API, verify semantics, or prove
native-extension ABI compatibility.

```powershell
python -B tools/oracle/api/verify_encoding.py --php C:\Users\rinpa\ALL_php_oracle\php-8.5.12-ts-x64\php.exe --output reports/php-api-inventory-NEW/encoding
python -B tools/oracle/api/inventory.py --php C:\Users\rinpa\ALL_php_oracle\php-8.5.12-ts-x64\php.exe --output reports/php-api-inventory-NEW/run
```

The executable must match SHA-256
`0ac893499799256db6d3a54b0da73692e02311493922e6e4f86a062674a77d66`.
The collector expects exactly the 36 DLLs in this approved local distribution's
`ext` directory. It records the actual SHA-256 of each DLL; matching the pinned
php.exe is not presented as a separate signature/authenticity verification of
every DLL. Historical output directories are refused, never overwritten.

The base profile is `php -n -d display_errors=stderr -d error_reporting=-1 -d
date.timezone=UTC`. Every extension DLL is then supplied in a **separate fresh
process**, by one additional `-d extension=ABSOLUTE_DLL`. No prerequisites are
added to make a failed DLL load; no ini files or system configuration are changed.
There are no target API invocations, service probes, network tests, installations,
or combined-extension profiles. The process guard is 60 seconds by default;
timeouts and crashes remain unavailable profiles. The actual command and guard
are recorded. Reflection itself may evaluate a represented default expression;
the tool does not invoke target functions/methods or attribute constructors.

The worker enumerates only `isInternal()` functions/types and excludes user
constants. Its helper functions and self-test enum are never target APIs.
It records classes, interfaces, traits and enums, exposed method signatures
(including inherited/private/protected methods with visibility), class constants,
properties, global constants and INI entries. Callable signatures include ordered
parameters/types/defaults/reference/variadic flags, return and tentative-return
types, deprecation, extension and attribute metadata. Reflection does not expose
every overload/behavioral rule, error, side effect or execution constraint.

PHP string values and names retain their exact bytes as base64. Integers use
decimal strings, floats carry IEEE-754 bits and explicit NaN/infinity tags.
Arrays retain ordered typed keys. Enums retain class/case/backing values;
resources and arbitrary objects are explicitly described instead of serialized
or silently omitted. Unavailable defaults and reflection errors remain records.
The encoding check exercises these cases through actual pinned PHP.

`ini_get_all` supplies **profile startup global values** and current local values.
The global value already includes command-line overrides and must not be called
a compiled factory default. Compiled factory defaults remain `UNMEASURED`.
The worker does not change INI directives after process startup.

Each profile preserves raw stdout JSON, raw stderr bytes, exit code, warnings,
commands, full reflected metadata, and an API delta versus base. A zero process
exit code is insufficient to prove an extension loaded: loaded status uses the
actual module set difference. Load failures/dependency warnings are retained.
`summary.json` distinguishes profile availability from overall `NOT_COMPLETE`.

`api-leaves.jsonl` is a versioned, machine-derived input for future requirements
expansion. IDs derive from API kind and exact identifier bytes. Every row remains
`leaf_candidate`/`UNVERIFIED` with no candidate tests. Signature variants reference
the exact profile JSON and pointer. `requirements-linkage.json` records mechanical
parent candidates and the requirements file hash, but **does not modify or certify
the existing requirements matrix**. Semantic boundaries still need actual leaves.
Type-entity signature hashes exclude its separate methods/constants/properties
arrays; each exposed member has its own leaf and signature hash. The stored
profile pointer still identifies the complete reflected type object.

Linux x64, non-CLI SAPIs, combined extensions, failed-DLL API surfaces, arbitrary
third-party extensions, factory INI defaults and candidate behavior remain
unmeasured. The observed union is not a globally exhaustive PHP API inventory.

Official references used for Reflection and INI field meanings:

- [ReflectionFunctionAbstract](https://www.php.net/manual/en/class.reflectionfunctionabstract.php)
- [ReflectionParameter](https://www.php.net/manual/en/class.reflectionparameter.php)
- [ini_get_all](https://www.php.net/manual/en/function.ini-get-all.php)
