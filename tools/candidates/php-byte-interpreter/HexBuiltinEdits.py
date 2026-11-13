"""ALL-owned bin2hex over immutable bytes, with bounded temporary chunks.

No PHP runtime/native extension provides this function. Apply after the byte
string builtin module so normal argument arity/coercion diagnostics are shared.
Output byte length and source offsets use Int64; each host text conversion is
at most a 64KiB input chunk, never a full-string UTF-8 decode.
"""
ARM = r'''                'bin2hex' {
                    Assert-PhpStringBuiltinArity 'bin2hex' $callArgs 1 1
                    $data=ConvertTo-PhpBuiltinBytes $callArgs[0] 'bin2hex' 1 'string'
                    if($data.Length -gt ([long]::MaxValue-shr1)) {
                        Throw-PhpError 'Error' 'Possible integer overflow in memory allocation'
                    }
                    $builder=[AllPhp.ByteValues.PhpByteBuilder]::new()
                    $buffer=[byte[]]::new(65536)
                    $position=[long]0
                    while($position-lt$data.Length) {
                        $count=[int][Math]::Min([long]65536,$data.Length-$position)
                        $data.CopyTo($position,$buffer,0,$count)
                        # BitConverter output is strictly ASCII hex. This lower
                        # operation never consumes a PHP string or symbol.
                        $chunk=[BitConverter]::ToString($buffer,0,$count).Replace('-','').ToLowerInvariant()
                        $builder.AppendAscii($chunk)
                        $position+=$count
                    }
                    return $builder.ToPhpBytes()
                }
'''


def apply(value: str) -> str:
    newline='\r\n' if '\r\n' in value else '\n'
    value=value.replace('\r\n','\n')
    registration="'json_encode','json_decode','json_last_error','json_last_error_msg','count','strlen',"
    dispatch="                'json_encode' {\n"
    if value.count(registration)!=1 or value.count(dispatch)!=1:
        raise ValueError('HexBuiltinEdits expects one registration and one dispatch anchor')
    value=value.replace(registration,"'bin2hex',"+registration)
    value=value.replace(dispatch,ARM+dispatch)
    return value.replace('\n',newline)
