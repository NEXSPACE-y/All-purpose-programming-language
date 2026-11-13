"""Connect approved long byte offsets to scalar and nested interpreter lvalues.

Apply after Core/TypedKey/NativeByte modules. Cases are first recorded by the
separate official-PHP oracle probe; this module is not itself verification.
String isset/empty/coalesce quiet-path semantics and general lvalue evaluation
order remain separate obligations until measured. No source/runtime delegation.
"""
HELPERS = r'''        function ConvertTo-PhpStringOffset($key) {
            if (Is-PhpRefCell $key) { $key=$key.Value }
            if ($key -is [long]) { return $key }
            if (Is-PhpStringValue $key) {
                $number=ConvertFrom-PhpNumericString $key $true
                # PHP permits integer syntax and integer-leading malformed
                # strings, but not floating syntax or integer overflow strings.
                if ($number -is [long]) {
                    $whole=ConvertFrom-PhpNumericString $key $false
                    if ($null -eq $whole -and $state.QuietDepth -eq 0) {
                        $builder=[AllPhp.ByteValues.PhpByteBuilder]::new()
                        $builder.AppendUtf8('Illegal string offset "')
                        $builder.Append((To-PhpBytes $key));$builder.AppendUtf8('"')
                        Write-PhpDiagnostic 2 ($builder.ToPhpBytes())
                    }
                    return $number
                }
                Throw-PhpError 'TypeError' 'Cannot access offset of type string on string'
            }
            if ($null -eq $key -or $key -is [bool] -or $key -is [double]) {
                if ($state.QuietDepth -eq 0) { Write-PhpDiagnostic 2 'String offset cast occurred' }
                return (To-PhpInt $key)
            }
            $type=if(Is-PhpArray $key){'array'}elseif(Is-PhpObject $key){$key.Class}else{'resource'}
            Throw-PhpError 'TypeError' ('Cannot access offset of type '+$type+' on string')
        }
        function Read-PhpStringOffset($value, $key) {
            $result=(To-PhpBytes $value).ReadOffset((ConvertTo-PhpStringOffset $key))
            if ($result.WarningLevel -gt 0 -and $state.QuietDepth -eq 0) {
                Write-PhpDiagnostic $result.WarningLevel $result.Message
            }
            return $result.Value
        }
'''


def apply(value: str) -> str:
    newline='\r\n' if '\r\n' in value else '\n'
    value=value.replace('\r\n','\n')

    def replace(old,new,count=1):
        nonlocal value
        found=value.count(old)
        if found!=count:
            raise ValueError(f'StringOffsetEdits anchor count {found}, expected {count}: {old[:90]!r}')
        value=value.replace(old,new)

    replace('        function Get-PhpArrayItem($array, $key) {\n',HELPERS+'        function Get-PhpArrayItem($array, $key) {\n            if (Is-PhpStringValue $array) { return (Read-PhpStringOffset $array $key) }\n')
    replace('        function Set-LValue($node, $value, [string]$op) {',
            '        function Set-LValue($node, $value, [string]$op, $AssignmentResult=$null) {\n            $hasResolvedIndexBase=$false;$resolvedIndexBase=$null')
    replace("""            if ($op -cne '=') {
                $previous = Get-LValue $node""", """            if ($op -cne '=') {
                if ($node.Kind -ceq 'index') {
                    $resolvedIndexBase=Invoke-PhpExpr $node.Base;$hasResolvedIndexBase=$true
                    if (Is-PhpStringValue $resolvedIndexBase) {
                        Throw-PhpError 'Error' 'Cannot use assign-op operators with string offsets'
                    }
                }
                $previous = Get-LValue $node""")
    replace("""                $base = Invoke-PhpExpr $node.Base
                $append = ($null -eq $node.Key)
                $key = $null
                if (-not $append) { $key = Invoke-PhpExpr $node.Key }
                Set-PhpArrayItem $base $key $value $append""", """                $base=if($hasResolvedIndexBase){$resolvedIndexBase}else{Invoke-PhpExpr $node.Base}
                $append = ($null -eq $node.Key)
                $key = $null
                if (-not $append) { $key = Invoke-PhpExpr $node.Key }
                if (Is-PhpStringValue $base) {
                    if ($append) { Throw-PhpError 'Error' '[] operator not supported for strings' }
                    $offset=ConvertTo-PhpStringOffset $key
                    $original=To-PhpBytes $base
                    $replacement=To-PhpBytes $value
                    $written=$original.WithOffset($offset,$replacement)
                    if ($written.ErrorClass.Length -gt 0) { Throw-PhpError $written.ErrorClass $written.Message }
                    if ($written.WarningLevel -gt 0) { Write-PhpDiagnostic $written.WarningLevel $written.Message }
                    Set-LValue $node.Base $written.Value '='
                    if ($null -ne $AssignmentResult) {
                        $AssignmentResult.IsStringOffset=$true
                        if($offset -lt 0 -and $offset -lt (-$original.Length)){$AssignmentResult.Value=$null}
                        else{$AssignmentResult.Value=$replacement.Slice(0,[long]1)}
                    }
                    return
                }
                Set-PhpArrayItem $base $key $value $append""")
    replace("""                    Set-LValue $node.Target $replacement $writeOp
                    if (($node.Target.Kind -eq 'index'""", """                    $assignmentResult=[pscustomobject]@{IsStringOffset=$false;Value=$null}
                    Set-LValue $node.Target $replacement $writeOp $assignmentResult
                    if($assignmentResult.IsStringOffset){return $assignmentResult.Value}
                    if (($node.Target.Kind -eq 'index'""")
    replace("                if (-not (Is-PhpArray $array)) { throw 'ALL PHP: Reference index requires array' }",
            "                if (Is-PhpStringValue $array) { Throw-PhpError 'Error' 'Cannot create references to/from string offsets' }\n                if (-not (Is-PhpArray $array)) { throw 'ALL PHP: Reference index requires array' }")
    return value.replace('\n',newline)
