"""Preserve all four PHP error-handler actual arguments.

Apply to the byte diagnostic handler after current root modules. Do not infer
the number of actual arguments from the callback's declared parameter count.
Official PHP 8.5.12 supplies level/message/file/line to parameterless, fixed,
variadic, named, closure, first-class, method and invokable user handlers alike.
The builtin strlen callback independently reports receiving four arguments.

Get-PhpCallableArity remains unchanged; it is not used to truncate this call.
No new callbacks/ABI, source metadata conversion or existing fixture expected
values are introduced. The caller pins source/runtime and performs integration
measurement. This pure module keeps CRLF/LF and guards the exact old fragment.
"""

OLD = '''                $arity=Get-PhpCallableArity $state.ErrorHandler
                if ($arity -ge 0 -and $arity -lt 4) {
                    if ($arity -eq 0) { $handlerArgs=@() } else { $handlerArgs=@($handlerArgs[0..($arity-1)]) }
                }
'''
NEW = '''                # PHP supplies four actual arguments independently of the
                # user handler's declared fixed or variadic parameter count.
'''


def apply(value: str) -> str:
    if not isinstance(value, str):
        raise TypeError('CallbackArgumentEdits.apply requires source text')
    newline='\r\n' if '\r\n' in value else '\n'
    value=value.replace('\r\n','\n')
    if value.count(OLD)!=1:
        raise ValueError('CallbackArgumentEdits: expected exactly one byte-diagnostic truncation fragment')
    argument_anchor="$handlerArgs=@($level,$messageBytes,(To-PhpBytes ([string]$state.ScriptName)),[long]$state.Line)"
    if value.count(argument_anchor)!=1:
        raise ValueError('CallbackArgumentEdits: unknown diagnostic argument construction')
    value=value.replace(OLD,NEW)
    return value.replace('\n',newline)
