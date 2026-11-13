"""Explicit UTF-8 JSON boundaries for the approved byte interpreter.

Apply after Core/TypedKey/NativeByte. This retains the existing one-argument
json_encode and two-argument json_decode profiles. Options, JsonSerializable,
streaming gigantic JSON and complete JSON parsing remain separate obligations.
"""
import re

ENCODE = r'''        function Throw-PhpJsonFailure([long]$code, [string]$message) {
            $jsonFailure=[InvalidOperationException]::new($message)
            $jsonFailure.Data['AllPhpJsonError']=$code
            throw $jsonFailure
        }
        function Encode-PhpJson($value, [int]$depth=0, $path=$null) {
            if(Is-PhpRefCell $value){$value=$value.Value}
            if($depth -ge 512){Throw-PhpJsonFailure 1 'Maximum stack depth exceeded'}
            if($null -eq $value){return 'null'}
            if($value -is [bool]){if($value){return 'true'};return 'false'}
            if($value -is [long]){return $value.ToString([Globalization.CultureInfo]::InvariantCulture)}
            if($value -is [double]){
                if([double]::IsNaN($value)-or[double]::IsInfinity($value)){Throw-PhpJsonFailure 7 'Inf and NaN cannot be JSON encoded'}
                return (Format-PhpFloat $value 0).Replace('E','e')
            }
            if(Is-PhpStringValue $value){return (Encode-JsonQuoted $value)}
            $array=Is-PhpArray $value
            $object=Is-PhpObject $value
            if(-not$array-and-not$object){Throw-PhpJsonFailure 8 'Type is not supported'}
            if($null -eq $path){$path=[Collections.Generic.List[object]]::new()}
            foreach($ancestor in $path){if([object]::ReferenceEquals($ancestor,$value)){Throw-PhpJsonFailure 6 'Recursion detected'}}
            [void]$path.Add($value)
            try {
                if($object-and$state.Classes.ContainsKey($value.Class)-and
                    $state.Classes[$value.Class].PSObject.Properties['Enum']-and$state.Classes[$value.Class].Enum){
                    if($null -eq $state.Classes[$value.Class].BackingType){Throw-PhpJsonFailure 11 'Non-backed enums have no default serialization'}
                    return (Encode-PhpJson $value.Props['value'] $depth $path)
                }
                $parts=[Collections.Generic.List[string]]::new()
                $list=$array
                if($array){
                    $index=[long]0
                    foreach($key in $value.Items.Keys){if(-not$key.IsInteger-or$key.IntegerValue-ne$index){$list=$false;break};$index++}
                    foreach($key in $value.Items.Keys){
                        $encoded=Encode-PhpJson $value.Items[$key] ($depth+1) $path
                        if($list){[void]$parts.Add($encoded)}
                        else{[void]$parts.Add((Encode-JsonQuoted (Get-PhpKeyValue $key))+':'+$encoded)}
                    }
                } else {
                    foreach($entry in (Get-PhpObjectDumpEntries $value)){
                        if(-not$entry.Present-or$entry.Suffix.Length-gt0){continue}
                        $encoded=Encode-PhpJson $entry.Value ($depth+1) $path
                        [void]$parts.Add((Encode-JsonQuoted $entry.Name)+':'+$encoded)
                    }
                }
                if($list){return ('['+[string]::Join(',',$parts.ToArray())+']')}
                return ('{'+[string]::Join(',',$parts.ToArray())+'}')
            } finally {$path.RemoveAt($path.Count-1)}
        }
'''


def apply(value: str) -> str:
    newline='\r\n' if '\r\n' in value else '\n'
    value=value.replace('\r\n','\n')

    def replace(old,new,count=1):
        nonlocal value
        found=value.count(old)
        if found!=count:
            raise ValueError(f'JsonByteEdits expected {count}, found {found}: {old[:85]!r}')
        value=value.replace(old,new)

    replace('        function Encode-JsonQuoted([string]$value) {\n', '''        function Encode-JsonQuoted($value) {
            $raw=To-PhpBytes $value
            $decoded=$null
            if(-not$raw.TryDecodeUtf8([ref]$decoded)){Throw-PhpJsonFailure 5 'Malformed UTF-8 characters, possibly incorrectly encoded'}
            $value=$decoded
''')
    replace('if ($code -lt 32 -or $code -gt 126)', 'if ($code -lt 32 -or $code -gt 127)')
    pattern=re.compile(r'^        function Encode-PhpJson\(.*?^        }\n',re.M|re.S)
    matches=list(pattern.finditer(value))
    if len(matches)!=1:raise ValueError('Expected one Encode-PhpJson function')
    match=matches[0]
    value=value[:match.start()]+ENCODE+value[match.end():]
    replace("""                    $encoded = Encode-PhpJson $callArgs[0]
                    $state.JsonError = 0
                    $state.JsonErrorMessage = 'No error'
                    return $encoded""", """                    try {
                        $encoded=Encode-PhpJson $callArgs[0]
                        $state.JsonError=0;$state.JsonErrorMessage='No error'
                        return (To-PhpBytes $encoded)
                    } catch {
                        if($isCli-and(Test-PhpCliExit $_)){throw}
                        $cause=$_.Exception
                        while($null-ne$cause-and-not$cause.Data.Contains('AllPhpJsonError')){$cause=$cause.InnerException}
                        if($null-eq$cause){throw}
                        $state.JsonError=[long]$cause.Data['AllPhpJsonError']
                        $state.JsonErrorMessage=$cause.Message
                        return $false
                    }""")
    replace('                    $json = To-PhpText $callArgs[0]', '''                    $json=$null
                    if(-not(To-PhpBytes $callArgs[0]).TryDecodeUtf8([ref]$json)){
                        $state.JsonError=5
                        $state.JsonErrorMessage='Malformed UTF-8 characters, possibly incorrectly encoded'
                        return $null
                    }''')
    replace('if ($value -is [bool] -or $value -is [string]) { return $value }',
            'if ($value -is [bool] -or $value -is [string]) { return (ConvertTo-PhpOwnedValue $value) }')
    return value.replace('\n',newline)
