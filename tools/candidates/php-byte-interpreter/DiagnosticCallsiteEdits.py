"""Keep user-triggered diagnostic message bytes through the source callsite.

The byte diagnostic renderer/handler already accepts PhpBytes. The old builtin
dispatcher still decoded the argument before reaching it; replace that single
PHP-value boundary, leaving INI/OS/name metadata conversions separate.
"""


def apply(value: str) -> str:
    old='Write-PhpDiagnostic $level (To-PhpText $callArgs[0])'
    new='Write-PhpDiagnostic $level (To-PhpBytes $callArgs[0])'
    if value.count(old)!=1:
        raise ValueError('DiagnosticCallsiteEdits expects one user-error argument conversion')
    return value.replace(old,new)
