"""Approved byte-value migration, isolated from the installed/package adapter.

The caller pins the input adapter and runtime. These edits cover value entry,
literal bytes, scalar operators, casts and raw output. Separate modules own
typed array keys and string builtins. Metadata/symbol/diagnostic text boundaries
remain explicit migration obligations; this module is not full compatibility.
"""
from pathlib import Path
import re

HERE = Path(__file__).resolve().parent


def apply(value: str, runtime_path: Path, runtime_sha256: str) -> str:
    newline = '\r\n' if '\r\n' in value else '\n'
    value = value.replace('\r\n', '\n')

    def replace(old, new, count=1):
        nonlocal value
        actual = value.count(old)
        if actual != count:
            raise ValueError(f'Core byte anchor count {actual}, expected {count}: {old[:90]!r}')
        value = value.replace(old, new)

    def edit_function(name, edit):
        nonlocal value
        pattern = re.compile(r'^        function ' + re.escape(name) + r'(?=[( {]).*?^        }\n', re.M | re.S)
        matches = list(pattern.finditer(value))
        if len(matches) != 1:
            raise ValueError(f'Expected one function {name}, found {len(matches)}')
        match = matches[0]
        body = edit(match.group())
        if body == match.group():
            raise ValueError(f'No edit made in function {name}')
        value = value[:match.start()] + body + value[match.end():]

    # Isolated candidate resolves an explicitly pinned assembly, never a runtime
    # installed by name or a stock PHP component. Packaging is a separate step.
    quoted = str(runtime_path.resolve(strict=True)).replace("'", "''")
    bootstrap = f"""        $phpByteRuntimePath = '{quoted}'
        $phpByteRuntimeHash = '{runtime_sha256}'
        if ((Get-FileHash -LiteralPath $phpByteRuntimePath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $phpByteRuntimeHash) {{
            throw 'ALL PHP byte runtime hash mismatch'
        }}
        $loadedByteType = 'AllPhp.ByteValues.PhpBytes' -as [type]
        if ($null -ne $loadedByteType) {{
            if ([IO.Path]::GetFullPath($loadedByteType.Assembly.Location) -cne [IO.Path]::GetFullPath($phpByteRuntimePath)) {{
                throw 'ALL PHP byte runtime was already loaded from a different location'
            }}
        }} else {{ Add-Type -Path $phpByteRuntimePath }}
"""
    helpers = (HERE / 'ByteValueHelpers.ps1.fragment').read_text(encoding='utf-8-sig').replace('\r\n', '\n')
    replace("        $ErrorActionPreference = 'Stop'\n", "        $ErrorActionPreference = 'Stop'\n" + bootstrap + helpers + '\n')

    # The source decoder still accepts UTF-8 source text. Once decoded, PHP
    # literals are bytes, including escape sequences producing invalid UTF-8.
    edit_function('Decode-PhpString', lambda s: s.replace('return $sb.ToString()', 'return [AllPhp.ByteValues.PhpBytes]::FromUtf8($sb.ToString())'))
    edit_function('Expand-PhpDoubleString', lambda s: s.replace(
        """                        if($point-ge0xd800-and$point-le0xdfff){
                            if($ValidateOnly){$i=$end;continue}
                            throw 'ALL PHP: Binary string containing a non-scalar UTF-8 codepoint is not supported'
                        }""",
        """                        if($point-ge0xd800-and$point-le0xdfff){
                            [void]$output.Add([byte](0xe0-bor($point-shr12)))
                            [void]$output.Add([byte](0x80-bor(($point-shr6)-band0x3f)))
                            [void]$output.Add([byte](0x80-bor($point-band0x3f)))
                            $i=$end;continue
                        }"""
    ).replace('Add-PhpLiteralText $output (To-PhpText (Get-PhpVariableValue $name))',
              '$output.AddRange((To-PhpBytes (Get-PhpVariableValue $name)).ToArray())').replace(
        """            try{return $phpLiteralUtf8.GetString($output.ToArray())}
            catch [Text.DecoderFallbackException]{throw 'ALL PHP: Arbitrary non-UTF8 PHP byte strings are not supported'}""",
        '            return [AllPhp.ByteValues.PhpBytes]::FromBytes($output.ToArray())'))
    replace("'literal' { return $node.Value }", "'literal' { return (ConvertTo-PhpOwnedValue $node.Value) }")
    edit_function('Copy-PhpValue', lambda s: s.replace(
        'if (-not (Is-PhpArray $value)) { return $value }',
        'if (-not (Is-PhpArray $value)) { return (ConvertTo-PhpOwnedValue $value) }'))
    edit_function('ConvertFrom-PhpNumericString', lambda s: s.replace(
        '([string]$text, [bool]$leadingOnly)', '($text, [bool]$leadingOnly)').replace(
        '            $m = if ($leadingOnly)', '            $text = Get-PhpNumericView $text\n            $m = if ($leadingOnly)'))
    edit_function('To-PhpText', lambda s: """        function To-PhpText($value) {
            # Explicit legacy host-text boundary. Raw PHP operations use bytes.
            # Never decode invalid data with replacement or implicit ToString().
            return (Get-PhpHostText (To-PhpBytes $value))
        }
""")
    edit_function('To-Number', lambda s: s.replace('$value -is [string]', '(Is-PhpStringValue $value)'))
    edit_function('Is-Truthy', lambda s: s.replace(
        """            if ($value -is [string]) {
                return ($value.Length -gt 0 -and $value -cne '0')
            }""",
        """            if (Is-PhpStringValue $value) { return (To-PhpBytes $value).Truthy }"""))
    edit_function('Convert-PhpCast', lambda s: s.replace('$value -is [string]', '(Is-PhpStringValue $value)').replace(
        '$phpLeadingNumericRx.Match($value)', '$phpLeadingNumericRx.Match((Get-PhpNumericView $value))').replace(
        "$value.TrimStart().StartsWith('-')", "(Get-PhpNumericView $value).TrimStart().StartsWith('-')").replace(
        "'string' { return (To-PhpText $value) }", "'string' { return (To-PhpBytes $value) }"))
    edit_function('Test-PhpTypeAtom', lambda s: s.replace(
        "'string' { return ($value -is [string]) }", "'string' { return (Is-PhpStringValue $value) }").replace(
        "if ($value -is [string]) { return ($state.Functions.ContainsKey($value) -or (Test-PhpNativeFunction $value)) }",
        "if (Is-PhpStringValue $value) { $symbol=Get-PhpHostText $value;return ($state.Functions.ContainsKey($symbol) -or (Test-PhpNativeFunction $symbol)) }"))
    edit_function('Convert-PhpTypedValue', lambda s: s.replace(
        '            if ([string]::IsNullOrEmpty($typeName))',
        '            $value=ConvertTo-PhpOwnedValue $value\n            if ([string]::IsNullOrEmpty($typeName))').replace(
        '$value -is [string]', '(Is-PhpStringValue $value)').replace('(To-PhpText $value)', '(To-PhpBytes $value)'))
    edit_function('Php-Equal', lambda s: s.replace(
        '                if ($a.GetType() -ne $b.GetType()) { return $false }\n                if ($a -is [string]) { return ($a -ceq $b) }',
        """                if ((Is-PhpStringValue $a) -or (Is-PhpStringValue $b)) {
                    if (-not (Is-PhpStringValue $a) -or -not (Is-PhpStringValue $b)) { return $false }
                    return (To-PhpBytes $a).Equals((To-PhpBytes $b))
                }
                if ($a.GetType() -ne $b.GetType()) { return $false }"""))
    edit_function('Compare-Values', lambda s: s.replace('$a -is [string]', '(Is-PhpStringValue $a)').replace(
        '$b -is [string]', '(Is-PhpStringValue $b)').replace(
        '[Math]::Sign([string]::CompareOrdinal($a, $b))', '(To-PhpBytes $a).CompareBinary((To-PhpBytes $b))').replace(
        '[Math]::Sign([string]::CompareOrdinal((To-PhpText $a),(To-PhpText $b)))',
        '(To-PhpBytes $a).CompareBinary((To-PhpBytes $b))'))

    replace("'.=' { $value = (To-PhpText $previous) + (To-PhpText $value) }",
            "'.=' { $value = (To-PhpBytes $previous).Concat((To-PhpBytes $value)) }")
    replace("'.' { return ((To-PhpText $a) + (To-PhpText $b)) }",
            "'.' { return (To-PhpBytes $a).Concat((To-PhpBytes $b)) }")
    for token, numeric in [('&', '-band'), ('|', '-bor'), ('^', '-bxor')]:
        replace(f"'{token}' {{ return [long]((To-PhpInt $a) {numeric} (To-PhpInt $b)) }}",
                f"'{token}' {{ if ((Is-PhpStringValue $a) -and (Is-PhpStringValue $b)) {{ return (To-PhpBytes $a).Bitwise((To-PhpBytes $b),[char]'{token}') }};return [long]((To-PhpInt $a) {numeric} (To-PhpInt $b)) }}")
        replace(f"'{token}=' {{ $value = [long]((To-PhpInt $previous) {numeric} (To-PhpInt $value)) }}",
                f"'{token}=' {{ if ((Is-PhpStringValue $previous) -and (Is-PhpStringValue $value)) {{ $value=(To-PhpBytes $previous).Bitwise((To-PhpBytes $value),[char]'{token}') }} else {{ $value = [long]((To-PhpInt $previous) {numeric} (To-PhpInt $value)) }} }}")
    replace("'~' { return [long](-bnot (To-PhpInt $value)) }",
            "'~' { if (Is-PhpStringValue $value) { return (To-PhpBytes $value).BitwiseNot() };return [long](-bnot (To-PhpInt $value)) }")

    # String callables are converted once at the currently UTF-8 symbol boundary.
    # Raw-byte symbol lookup is owned by the separate symbol component migration.
    for name in ['Assert-PhpValueCallable', 'Get-PhpValueCallableDefinition', 'Invoke-PhpValueCallable']:
        edit_function(name, lambda s: s.replace('\n', '\n            if (Is-PhpBytes $callee) { $callee=Get-PhpHostText $callee }\n', 1))
    replace('$klass=[string](Invoke-PhpExpr $node.Base)', '$klass=Get-PhpHostText (Invoke-PhpExpr $node.Base)', count=2)
    replace("""                    $callArgs = [System.Collections.Generic.List[object]]::new()
                    foreach ($arg in $node.Args) {
                        if ($arg.Kind -ceq 'named_argument') {
                            [void]$callArgs.Add([pscustomobject]@{
                                PhpType='named_argument'; Name=$arg.Name
                                Value=(Invoke-PhpExpr $arg.Expr)
                            })
                        } else {
                            [void]$callArgs.Add((Invoke-PhpExpr $arg))
                        }
                    }
                    return (Invoke-PhpFunction $callName ($callArgs.ToArray()))""",
            """                    $callArgs = Evaluate-PhpBuiltinArguments $node.Args $callName
                    return (Invoke-PhpFunction $callName $callArgs)""")

    replace('[Console]::Write((To-PhpText (Invoke-PhpExpr $e)))', 'Write-PhpBytes (Invoke-PhpExpr $e)')
    replace('[Console]::Write((To-PhpText (Invoke-PhpExpr $node.Expr)))', 'Write-PhpBytes (Invoke-PhpExpr $node.Expr)')
    replace("'inline_html' { [Console]::Write($node.Text); return }", "'inline_html' { Write-PhpBytes $node.Text; return }")
    replace("foreach ($item in $callArgs) { [Console]::Write((Format-PhpVarDump $item '')) }",
            "foreach ($item in $callArgs) { Write-PhpBytes (Format-PhpBytesDump $item '') }")
    replace('$printed = Format-PhpPrintR $callArgs[0] 0', '$printed = Format-PhpBytesPrintR $callArgs[0] 0')
    replace('[Console]::Write($printed)', 'Write-PhpBytes $printed')
    edit_function('Invoke-PhpCliExit', lambda s: s.replace(
        'elseif ($argument -is [string]) { [Console]::Write($argument) }',
        'elseif (Is-PhpStringValue $argument) { Write-PhpBytes $argument }').replace(
        "[Console]::Write('NAN')", "Write-PhpBytes 'NAN'").replace(
        '[Console]::Write((To-PhpText $argument))', 'Write-PhpBytes $argument'))

    return value.replace('\n', newline)
