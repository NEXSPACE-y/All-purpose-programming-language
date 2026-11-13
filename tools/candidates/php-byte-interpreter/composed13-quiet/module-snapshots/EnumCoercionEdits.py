"""Measured weak-mode backed-enum argument conversion; isolated patch only.

Based on official PHP8.5.12 weak/strict 208 observations. The current interpreter
does not parse declare(strict_types=1) or track caller-file strictness. This
module deliberately adds no nominal strict flag and makes no strict-mode claim.
It corrects the supported default weak-mode path, retaining source snapshots and
old legacy error carriers. Existing ValueBoundary/other modules are not changed.

Integer-backed enum numeric parsing reuses the own builtin integer converter.
String-backed enums preserve original byte strings, prefer integer conversion
for weak numeric scalars, and support Stringable objects. Null's deprecation has
the actual string|int signature. Raw bad-string display follows PHP's observed
C-string NUL boundary without truncating the actual lookup value.
"""

HELPERS = r'''        function ConvertTo-PhpWeakEnumArgument($value,$enum,[string]$method) {
            if(Is-PhpRefCell $value) { $value=$value.Value }
            $function=$enum.Name+'::'+$method
            $stringBacked=Test-PhpNameEqual $enum.BackingType 'string'
            if(Is-PhpStringValue $value) {
                if($stringBacked) { return (To-PhpBytes $value) }
                return (ConvertTo-PhpBuiltinInteger $value $function 1 'value')
            }
            if($value-is[long]) {
                if($stringBacked) { return (To-PhpBytes $value) }
                return $value
            }
            if($null-eq$value) {
                Write-PhpDiagnostic 8192 ($function+'(): Passing null to parameter #1 ($value) of type string|int is deprecated')
                if($stringBacked) { return (To-PhpBytes ([long]0)) }
                return [long]0
            }
            if($value-is[bool]) {
                $integer=if($value){[long]1}else{[long]0}
                if($stringBacked) { return (To-PhpBytes $integer) }
                return $integer
            }
            if($value-is[double]) {
                if(-not$stringBacked) { return (ConvertTo-PhpBuiltinInteger $value $function 1 'value') }
                if(-not[double]::IsNaN($value)-and-not[double]::IsInfinity($value)-and
                    $value-ge-9223372036854775808.0-and$value-lt9223372036854775808.0) {
                    return (To-PhpBytes (ConvertTo-PhpBuiltinInteger $value $function 1 'value'))
                }
                if([double]::IsNaN($value)) { Write-PhpDiagnostic 2 'unexpected NAN value was coerced to string' }
                return (To-PhpBytes $value)
            }
            if($stringBacked-and(Is-PhpObject $value)-and
                $null-ne(Find-OptionalPhpMethod $value.Class '__toString')) { return (To-PhpBytes $value) }
            $expected=if($stringBacked){'string|int'}else{'int'}
            Throw-PhpError 'TypeError' ($function+'(): Argument #1 ($value) must be of type '+$expected+', '+(Get-PhpBuiltinTypeName $value)+' given')
        }
        function Get-PhpEnumBadStringBytes($value) {
            $bytes=To-PhpBytes $value
            $offset=[long]0;$chunk=[byte[]]::new(65536)
            while($offset-lt$bytes.LongLength) {
                $count=[int][Math]::Min([long]$chunk.Length,$bytes.LongLength-$offset)
                $bytes.CopyTo($offset,$chunk,0,$count)
                for($i=0;$i-lt$count;$i++) { if($chunk[$i]-eq0) { return $bytes.Slice(0,$offset+$i) } }
                $offset+=$count
            }
            return $bytes
        }
'''


def apply(value: str) -> str:
    if not isinstance(value,str):raise TypeError('EnumCoercionEdits.apply requires source text')
    newline='\r\n' if '\r\n' in value else '\n';value=value.replace('\r\n','\n')
    def replace(audit_id,old,new,count=1):
        nonlocal value
        found=value.count(old)
        if found!=count:raise ValueError(f'EnumCoercionEdits {audit_id}: expected {count} exact anchors, found {found}')
        value=value.replace(old,new)
    replace('helpers','        function Get-PhpClassConstant([string]$className, [string]$constName) {',HELPERS+'        function Get-PhpClassConstant([string]$className, [string]$constName) {')
    replace('enum-case-method-name', "$node.Name -ceq 'cases'", "(Test-PhpNameEqual $node.Name 'cases')")
    replace('enum-conversion-method-name', "$node.Name -in @('from','tryFrom')", "(Test-PhpNameIn $node.Name @('from','tryFrom'))")
    replace('enum-convert-argument', '''                            $needle=Invoke-PhpExpr $node.Args[0]
                            foreach ($item in $enum.EnumCases) {''','''                            $enumMethod=if(Test-PhpNameEqual $node.Name 'tryFrom'){'tryFrom'}else{'from'}
                            $needle=ConvertTo-PhpWeakEnumArgument (Invoke-PhpExpr $node.Args[0]) $enum $enumMethod
                            foreach ($item in $enum.EnumCases) {''')
    replace('enum-tryfrom-name', "$node.Name -ceq 'tryFrom'", "(Test-PhpRawNameEqual $enumMethod 'tryFrom')")
    replace('enum-bad-string-message', '''if(Is-PhpStringValue $needle) { $message.AppendUtf8('"');$message.Append((To-PhpBytes $needle));$message.AppendUtf8('"') }''', '''if(Is-PhpStringValue $needle) { $message.AppendUtf8('"');$message.Append((Get-PhpEnumBadStringBytes $needle));$message.AppendUtf8('"') }''')
    return value.replace('\n',newline)
