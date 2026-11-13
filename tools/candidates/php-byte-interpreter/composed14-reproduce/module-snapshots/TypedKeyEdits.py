"""Isolated typed-array-key edits for the frozen 5856687f PHP adapter.

Root owns applying this module and measuring the combined byte interpreter.
This file does not read/write packages, load assemblies, execute PHP or mutate
reports. `apply(value)` requires every disjoint anchor/count exactly; it is not
an idempotent best-effort rewrite. The caller must first pin its base artifact.

Canonical dependency: AllPhp.ByteValues.Runtime runtime01, PhpKey.FromInteger,
PhpKey.FromString(PhpBytes), IsInteger/IntegerValue/BytesValue. Root supplies
Is-PhpStringValue, To-PhpBytes, Get-PhpKeyValue and Get-PhpKeyHostText helpers.
Host-text formatting/symbol boundaries stay explicit. Raw print_r and JSON
encoding/error migration remains with root's output/value work; this module
removes the typed-key-to-string casts in their legacy text paths too.

Audit: all encoded i:/s: key branches, key copies, strict array identity,
reference append paths, callback array indices/named arguments, text JSON/dump/
print_r keys, array builtins, literal unpack, union and foreach are covered.
Existing To-PhpKey callers in isset/empty/destructuring/unset/array_key_exists
already keep the key object and need no textual rewrite. Object-property/global
symbol dictionaries are host metadata and are not array PhpKey registries.
General argument unpack is absent in this base, so it is not claimed added.
NextIndex overflow/negative-key policy and non-key builtin behavior are retained.
"""

BASE_SHA256 = "5856687f7abd1471b4af7af9827ca2d17a011e836ad2852bf1d7993298fddc9f"
BYTE_RUNTIME_SHA256 = "18d50efb55d8a333424149e4ab37428e102b1ac938240e50358ee3c8ab89466b"

# Each tuple is (audit id, old fragment, new fragment, required occurrence count).
# Small key-only anchors allow root's unrelated literal/value/operator/output
# edits to be composed without replacing their containing functions.
EDITS = [
    ("callback-required-indices",
     "$callee.Items.Contains('i:0') -or -not $callee.Items.Contains('i:1')",
     "$callee.Items.Contains((New-PhpIntegerKey 0)) -or -not $callee.Items.Contains((New-PhpIntegerKey 1))", 1),
    ("callback-named-key-kind", "if ($key.StartsWith('s:')) {", "if (-not $key.IsInteger) {", 1),
    ("callback-named-symbol-boundary", "Name=$key.Substring(2);Value=$value", "Name=(Get-PhpHostText $key.BytesValue);Value=$value", 1),
    ("print-r-legacy-key-text", "([string]$key).Substring(2) + '] => '", "(Get-PhpKeyHostText $key) + '] => '", 1),
    ("copy-keys-without-coercion", "$copy.Items[[string]$key] = Copy-PhpValue", "$copy.Items[$key] = Copy-PhpValue", 1),
    ("reference-append-key", "$key='i:' + [string]$array.NextIndex", "$key=New-PhpIntegerKey $array.NextIndex", 1),
    ("reference-key-next-index", "if ($key.StartsWith('i:')) {\n                        $numeric=[long]$key.Substring(2)", "if ($key.IsInteger) {\n                        $numeric=[long]$key.IntegerValue", 1),
    ("json-list-key-test", 'if ([string]$key -cne "i:$index")', 'if (-not $key.IsInteger -or $key.IntegerValue -ne $index)', 1),
    ("json-object-key-legacy-text", """$name = if (([string]$key).StartsWith('i:')) {
                            ([string]$key).Substring(2)
                        } else { ([string]$key).Substring(2) }""", "$name = Get-PhpKeyHostText $key", 1),
    ("dump-legacy-key-text", """$name = [string]$key
                    if ($name.StartsWith('i:')) { [void]$sb.Append($pad + '  [' + $name.Substring(2) + "]=>`n") }
                    else { [void]$sb.Append($pad + '  ["' + $name.Substring(2) + "`\"]=>`n") }""", """$name = Get-PhpKeyHostText $key
                    if ($key.IsInteger) { [void]$sb.Append($pad + '  [' + $name + "]=>`n") }
                    else { [void]$sb.Append($pad + '  ["' + $name + "`\"]=>`n") }""", 1),
    ("key-conversion", """        function To-PhpKey($value) {
            if ($value -is [bool]) {
                if ($value) { return 'i:1' }
                return 'i:0'
            }
            if ($null -eq $value) { return 's:' }
            if ($value -is [long]) { return "i:$value" }
            if ($value -is [double]) {
                $num = To-PhpInt $value
                return "i:$num"
            }
            if ($value -is [string]) {
                if ($value -cmatch '^(?:0|-?[1-9][0-9]*)$') {
                    $num = [long]0
                    if ([long]::TryParse($value, [ref]$num)) { return "i:$num" }
                }
                return ('s:' + $value)
            }
            throw 'ALL PHP: Unsupported array key type'
        }""", """        function To-PhpKey($value) {
            if (Is-PhpRefCell $value) { $value=$value.Value }
            if ($value -is [bool]) {
                if ($value) { return (New-PhpIntegerKey 1) }
                return (New-PhpIntegerKey 0)
            }
            if ($null -eq $value) { return [AllPhp.ByteValues.PhpKey]::FromString([AllPhp.ByteValues.PhpBytes]::Empty) }
            if ($value -is [long]) { return (New-PhpIntegerKey $value) }
            if ($value -is [double]) { return (New-PhpIntegerKey (To-PhpInt $value)) }
            if (Is-PhpStringValue $value) { return [AllPhp.ByteValues.PhpKey]::FromString((To-PhpBytes $value)) }
            throw 'ALL PHP: Unsupported array key type'
        }""", 1),
    ("append-key", '$keyString = "i:$($array.NextIndex)"', '$keyString = New-PhpIntegerKey $array.NextIndex', 1),
    ("explicit-key-next-index", "if ($keyString.StartsWith('i:')) {\n                    $intKey = [long]$keyString.Substring(2)", "if ($keyString.IsInteger) {\n                    $intKey = [long]$keyString.IntegerValue", 1),
    ("missing-key-diagnostic", """if ($keyString.StartsWith('i:')) { Write-PhpDiagnostic 2 ('Undefined array key ' + $keyString.Substring(2)) }
                    else { Write-PhpDiagnostic 2 ('Undefined array key "' + $keyString.Substring(2) + '"') }""", """if ($keyString.IsInteger) { Write-PhpDiagnostic 2 ('Undefined array key ' + (Get-PhpKeyHostText $keyString)) }
                    else { Write-PhpDiagnostic 2 ('Undefined array key "' + (Get-PhpKeyHostText $keyString) + '"') }""", 1),
    ("missing-key-legacy-error", '''throw "ALL PHP: Undefined array key '$keyString'"''', '''$legacyKey = if ($keyString.IsInteger) { 'i:' + (Get-PhpKeyHostText $keyString) } else { 's:' + (Get-PhpKeyHostText $keyString) }
                throw "ALL PHP: Undefined array key '$legacyKey'"''', 1),
    ("strict-array-key-byte-identity", 'if ([string]$aKeys[$i] -cne [string]$bKeys[$i])', 'if (-not $aKeys[$i].Equals($bKeys[$i]))', 1),
    ("legacy-key-value-helper", """        function KeyString-ToValue([string]$encoded) {
            if ($encoded.StartsWith('i:')) { return [long]$encoded.Substring(2) }
            return $encoded.Substring(2)
        }""", """        function KeyString-ToValue($encoded) {
            return (Get-PhpKeyValue $encoded)
        }""", 1),
    ("array-pop-key", "$lastKey = [string]$keys[$arr.Items.Count - 1]", "$lastKey = $keys[$arr.Items.Count - 1]", 1),
    ("array-shift-key", "$firstKey = [string]$keys[0]", "$firstKey = $keys[0]", 1),
    ("array-builtins-index-key", "$k = [string]$keys[$i]", "$k = $keys[$i]", 2),
    ("array-builtins-integer-kind", "$k.StartsWith('i:')", "$k.IsInteger", 6),
    ("array-pop-high-key-value", "$number = [long]$k.Substring(2)", "$number = [long]$k.IntegerValue", 1),
    ("array-builtins-string-key-values", "KeyString-ToValue ([string]$k)", "Get-PhpKeyValue $k", 3),
    ("array-key-values-and-union", "KeyString-ToValue ([string]$key)", "Get-PhpKeyValue $key", 4),
    ("array-reverse-slice-preserved-values", "KeyString-ToValue $k", "Get-PhpKeyValue $k", 2),
    ("array-key-last-store", "$last = [string]$key", "$last = $key", 1),
    ("array-key-last-value", "KeyString-ToValue $last", "Get-PhpKeyValue $last", 1),
    ("literal-unpack-integer-kind", "([string]$key).StartsWith('i:')", "$key.IsInteger", 1),
    ("foreach-key-value", """                                if ($key.StartsWith('i:')) {
                                    Set-PhpVariableValue $node.KeyName ([long]$key.Substring(2))
                                } else {
                                    Set-PhpVariableValue $node.KeyName ($key.Substring(2))
                                }""", """                                Set-PhpVariableValue $node.KeyName (Get-PhpKeyValue $key)""", 1),
]

UNCHANGED_TYPED_CALLERS = (
    "Get-PhpCliQuietPath index isset/empty", "Read-PhpTargetValue index",
    "Set-LValue index", "Get-PhpLValueCell index", "destructuring source keys",
    "unset array index", "array_key_exists", "array_values/value-only traversal",
    "variadic named array insertion", "Convert-JsonToPhp array insertion",
)

def apply(value: str) -> str:
    if not isinstance(value, str):
        raise TypeError("TypedKeyEdits.apply requires the adapter source string")
    newline = "\r\n" if "\r\n" in value else "\n"
    value = value.replace("\r\n", "\n")
    for audit_id, old, new, required in EDITS:
        found = value.count(old)
        if found != required:
            raise ValueError(f"TypedKeyEdits {audit_id}: expected {required} exact anchors, found {found}")
        value = value.replace(old, new)
    return value.replace("\n", newline)
