"""Weak builtin argument coercion for trigger_error/user_error byte messages.

Apply after DiagnosticCallsiteEdits and the byte string/Symbol modules. Strict
caller mode and full E_USER_ERROR termination semantics remain separate gaps;
this change does not label either implemented merely by adding argument checks.
"""


def apply(value: str) -> str:
    newline='\r\n' if '\r\n' in value else '\n'
    value=value.replace('\r\n','\n')
    edits=[
        ('''                    if ($callArgs.Count -lt 1 -or $callArgs.Count -gt 2) { throw "ALL PHP: $name() requires one or two arguments" }
                    $level = [long]1024
                    if ($callArgs.Count -eq 2) { $level = To-PhpInt (To-Number $callArgs[1]) }''',
         '''                    $errorFunction=ConvertTo-PhpAsciiLower $name
                    Assert-PhpStringBuiltinArity $errorFunction $callArgs 1 2
                    $message=ConvertTo-PhpBuiltinBytes $callArgs[0] $errorFunction 1 'message'
                    $level = [long]1024
                    if ($callArgs.Count -eq 2) { $level = ConvertTo-PhpBuiltinInteger $callArgs[1] $errorFunction 2 'error_level' }'''),
        ("Throw-PhpError 'ValueError' 'trigger_error(): Argument #2 ($error_level) must be one of E_USER_ERROR, E_USER_WARNING, E_USER_NOTICE, or E_USER_DEPRECATED'",
         "Throw-PhpError 'ValueError' ($errorFunction+'(): Argument #2 ($error_level) must be one of E_USER_ERROR, E_USER_WARNING, E_USER_NOTICE, or E_USER_DEPRECATED')"),
        ('Write-PhpDiagnostic $level (To-PhpBytes $callArgs[0])','Write-PhpDiagnostic $level $message'),
    ]
    for old,new in edits:
        if value.count(old)!=1:raise ValueError('TriggerCoercionEdits expects one exact builtin argument anchor: '+old[:80])
        value=value.replace(old,new)
    return value.replace('\n',newline)
