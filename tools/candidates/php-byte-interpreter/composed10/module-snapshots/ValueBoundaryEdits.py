"""Local PHP-owned value boundary fixes after json05 + SymbolEdits.

This isolated module never edits packages or executes another PHP runtime.
Metadata/source/OS paths and registry keys stay text. Only values exposed to PHP
are normalized to canonical PhpBytes. JSON functions belong to root and are not
edited here. Exact fragments/counts and original CRLF/LF are guarded.

Trace/match string arguments render bytes into an ASCII diagnostic view, using
the actual reference's escaped-byte/truncation rules. No raw value is decoded as
UTF8 merely to format it. StackTrace keeps valid-text path/frame metadata, and
Throwable's PHP-visible file/trace properties become PHP values. The existing
native Throwable byte renderer already consumes those properties with ToPhpBytes.
Raw symbol/path transport, full INI validation, huge text traces, enum weak/strict
argument coercion and full Throwable compatibility remain separate obligations.
"""

BASE_JSON05_SHA256 = '524ce86a322c0cd91d1f565a0c01a754842efbacd8521a47b6f3b4a56150bb8d'
SYMBOL_MODULE_SHA256 = '4853ac24f16c2a792dd5836bc8eaeba05335a9e255b9810b898999751ab634c3'

DIAGNOSTIC_HELPERS = r'''        function Get-PhpDiagnosticStringLimit {
            $limit=[long]15
            if ($state.Ini.ContainsKey('zend.exception_string_param_max_len')) {
                $configured=Get-PhpHostText (To-PhpBytes $state.Ini['zend.exception_string_param_max_len'])
                $parsed=[long]0
                if ([long]::TryParse($configured,[Globalization.NumberStyles]::Integer,[Globalization.CultureInfo]::InvariantCulture,[ref]$parsed) -and $parsed -ge 0) { $limit=$parsed }
            }
            return $limit
        }
        function Format-PhpDiagnosticString($value,[long]$limit) {
            $bytes=To-PhpBytes $value
            $take=[Math]::Min($bytes.LongLength,$limit)
            $text=[Text.StringBuilder]::new()
            [void]$text.Append("'")
            for($offset=[long]0;$offset-lt$take;$offset++) {
                $byte=$bytes.GetByte($offset)
                switch([int]$byte) {
                    9 { [void]$text.Append('\t') }
                    10 { [void]$text.Append('\n') }
                    11 { [void]$text.Append('\v') }
                    12 { [void]$text.Append('\f') }
                    13 { [void]$text.Append('\r') }
                    27 { [void]$text.Append('\e') }
                    92 { [void]$text.Append('\\') }
                    default {
                        if($byte-lt32-or$byte-ge127) { [void]$text.Append('\x'+$byte.ToString('X2',[Globalization.CultureInfo]::InvariantCulture)) }
                        else { [void]$text.Append([char]$byte) }
                    }
                }
            }
            if($bytes.LongLength-gt$take) { [void]$text.Append('...') }
            [void]$text.Append("'")
            return $text.ToString()
        }
'''


def apply(value: str) -> str:
    if not isinstance(value, str):
        raise TypeError('ValueBoundaryEdits.apply requires source text')
    newline='\r\n' if '\r\n' in value else '\n'
    value=value.replace('\r\n','\n')
    def replace(audit_id,old,new,count=1):
        nonlocal value
        actual=value.count(old)
        if actual!=count:
            raise ValueError(f'ValueBoundaryEdits {audit_id}: expected {count} exact anchors, found {actual}')
        value=value.replace(old,new)

    replace('diagnostic-helpers','        function Format-PhpTraceArgument($value) {',DIAGNOSTIC_HELPERS+'        function Format-PhpTraceArgument($value) {')
    replace('trace-owned-string-view', '''            if ($value -is [string]) {
                if ($value.Length -gt 15) { return ("'" + $value.Substring(0, 15) + "...'") }
                return ("'" + $value + "'")
            }''', '''            if (Is-PhpStringValue $value) { return (Format-PhpDiagnosticString $value (Get-PhpDiagnosticStringLimit)) }''')
    replace('match-owned-string-view', r'''            if ($value -is [string]) { return ("'" + $value.Replace('\', '\\').Replace("'", "\'") + "'") }''', '''            if (Is-PhpStringValue $value) {
                $limit=Get-PhpDiagnosticStringLimit
                if($limit-eq0) { return 'of type string' }
                return (Format-PhpDiagnosticString $value $limit)
            }''')
    replace('trace-argument-inclusion','''                foreach ($item in $frame.Args) { [void]$parts.Add((Format-PhpTraceArgument $item)) }''','''                $includeArguments=$true
                if($state.Ini.ContainsKey('zend.exception_ignore_args')) {
                    $setting=ConvertTo-PhpAsciiLower (Get-PhpHostText (To-PhpBytes $state.Ini['zend.exception_ignore_args']))
                    $includeArguments=$setting -cin @('','0','off','false','no','none')
                }
                if($includeArguments) { foreach ($item in $frame.Args) { [void]$parts.Add((Format-PhpTraceArgument $item)) } }''')
    replace('throwable-php-file-value', "$object.Props['file'] = $state.ScriptName", "$object.Props['file'] = To-PhpBytes $state.ScriptName")
    replace('throwable-php-trace-value', "$object.Props['__trace'] = Format-PhpStackTrace", "$object.Props['__trace'] = To-PhpBytes (Format-PhpStackTrace)")

    replace('numeric-string-kind', "if ($callArgs[0] -is [string]) {\n                        return ($null -ne (ConvertFrom-PhpNumericString $callArgs[0] $false))", "if (Is-PhpStringValue $callArgs[0]) {\n                        return ($null -ne (ConvertFrom-PhpNumericString $callArgs[0] $false))")
    replace('get-class-php-value', 'return [string]$callArgs[0].Class', 'return (To-PhpBytes ([string]$callArgs[0].Class))')
    replace('constant-state-php-value', "return $state.Constants[$constName]", "return (ConvertTo-PhpOwnedValue $state.Constants[$constName])")
    replace('constant-builtin-php-value', "return $phpConstants[$constName]", "return (ConvertTo-PhpOwnedValue $phpConstants[$constName])")
    replace('constant-expression-state-value', 'return $state.Constants[$constantName]', 'return (ConvertTo-PhpOwnedValue $state.Constants[$constantName])')
    replace('constant-expression-builtin-value', 'return $phpConstants[$constantName]', 'return (ConvertTo-PhpOwnedValue $phpConstants[$constantName])')
    replace('class-constant-php-value', 'return $entry.Value', 'return (ConvertTo-PhpOwnedValue $entry.Value)')
    replace('interface-constant-php-value', 'return $iface.Constants[$constName].Value', 'return (ConvertTo-PhpOwnedValue $iface.Constants[$constName].Value)',2)
    replace('class-keyword-php-value', "if ($constName -ceq 'class') { return $className }", "if (Test-PhpNameEqual $constName 'class') { return (To-PhpBytes $className) }")

    replace('reference-static-name-boundary', '$klass=Resolve-PhpClass ([string](Invoke-PhpExpr $node.Base))', '$klass=Resolve-PhpClass (Get-PhpHostText (Invoke-PhpExpr $node.Base))',3)
    replace('first-class-array-values', '$target=Get-PhpArrayItem $callable ([long]0);$member=Get-PhpArrayItem $callable ([long]1)', '$target=Get-PhpArrayItem $callable ([long]0);$member=Get-PhpArrayItem $callable ([long]1)\n                        if (Is-PhpStringValue $target) { $target=Get-PhpHostText $target }\n                        if (Is-PhpStringValue $member) { $member=Get-PhpHostText $member }')
    replace('instanceof-name-kind', "if ($b -isnot [string]) { throw 'ALL PHP: instanceof class name required' }\n                            return (Test-PhpInstanceOf $a.Class $b)", "if (-not (Is-PhpStringValue $b)) { throw 'ALL PHP: instanceof class name required' }\n                            return (Test-PhpInstanceOf $a.Class (Get-PhpHostText $b))")

    replace('enum-name-php-value', "$props['name']=$case.Name", "$props['name']=To-PhpBytes $case.Name")
    replace('enum-used-values-typed', '$usedValues=[System.Collections.Generic.HashSet[string]]::new(\n                        [System.StringComparer]::Ordinal)', '$usedValues=[System.Collections.Generic.HashSet[object]]::new()')
    replace('enum-backing-value-entry', '$backedValue=Invoke-PhpExpr $case.Value', '$backedValue=ConvertTo-PhpOwnedValue (Invoke-PhpExpr $case.Value)')
    replace('enum-string-kind', "$node.BackingType -eq 'string' -and $backedValue -isnot [string]", "$node.BackingType -eq 'string' -and -not (Is-PhpStringValue $backedValue)")
    replace('enum-value-identity', "$uniqueValue=$node.BackingType + ':' + [string]$backedValue", '$uniqueValue=$backedValue')
    replace('enum-string-lookup', "$enum.BackingType -eq 'string' -and $needle -is [string] -and\n                                    $item.Props['value'] -ceq $needle", "$enum.BackingType -eq 'string' -and (Is-PhpStringValue $needle) -and\n                                    (To-PhpBytes $item.Props['value']).Equals((To-PhpBytes $needle))")
    replace('enum-value-error-raw-message', '''                            $shown = if ($needle -is [string]) { '"' + $needle + '"' } else { To-PhpText $needle }
                            Throw-PhpError 'ValueError' ($shown + ' is not a valid backing value for enum ' + $enum.Name) 'ALL PHP: ValueError: invalid backing value for enum' '''.rstrip(),'''                            $message=[AllPhp.ByteValues.PhpByteBuilder]::new()
                            if(Is-PhpStringValue $needle) { $message.AppendUtf8('"');$message.Append((To-PhpBytes $needle));$message.AppendUtf8('"') }
                            else { $message.Append((To-PhpBytes $needle)) }
                            $message.AppendUtf8(' is not a valid backing value for enum '+$enum.Name)
                            Throw-PhpError 'ValueError' ($message.ToPhpBytes()) 'ALL PHP: ValueError: invalid backing value for enum' '''.rstrip())
    return value.replace('\n',newline)
