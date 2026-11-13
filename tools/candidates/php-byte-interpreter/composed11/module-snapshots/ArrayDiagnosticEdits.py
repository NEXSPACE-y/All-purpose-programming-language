"""Preserve raw typed keys in PHP's undefined-key diagnostic.

Apply after TypedKey, StringBuiltin and NativeByte modules. The real lookup key
is never shortened. Official PHP formats this particular diagnostic with %s,
so only the displayed string-key fragment stops at its first NUL; FF/80 bytes
before that point remain raw. Integer keys use invariant decimal text.
"""


def apply(value: str) -> str:
    newline='\r\n' if '\r\n' in value else '\n'
    value=value.replace('\r\n','\n')
    old='''                    if ($keyString.IsInteger) { Write-PhpDiagnostic 2 ('Undefined array key ' + (Get-PhpKeyHostText $keyString)) }
                    else { Write-PhpDiagnostic 2 ('Undefined array key "' + (Get-PhpKeyHostText $keyString) + '"') }'''
    new='''                    $keyDiagnostic=[AllPhp.ByteValues.PhpByteBuilder]::new()
                    $keyDiagnostic.AppendUtf8('Undefined array key ')
                    if($keyString.IsInteger){$keyDiagnostic.AppendUtf8((Get-PhpKeyHostText $keyString))}
                    else{
                        $displayKey=$keyString.BytesValue
                        $nul=Find-PhpBytes $displayKey ([AllPhp.ByteValues.PhpBytes]::FromBytes([byte[]]@(0))) 0
                        if($nul-ge0){$displayKey=$displayKey.Slice(0,$nul)}
                        $keyDiagnostic.AppendUtf8('"');$keyDiagnostic.Append($displayKey);$keyDiagnostic.AppendUtf8('"')
                    }
                    Write-PhpDiagnostic 2 ($keyDiagnostic.ToPhpBytes())'''
    if value.count(old)!=1:
        raise ValueError('ArrayDiagnosticEdits expects one typed-key diagnostic block')
    return value.replace(old,new).replace('\n',newline)
