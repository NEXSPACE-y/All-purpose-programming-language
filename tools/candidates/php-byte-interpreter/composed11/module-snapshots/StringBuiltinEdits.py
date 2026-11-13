"""Byte-preserving string builtins for the approved PhpBytes migration.

Input base is the pinned integrated5856687f candidate, after CoreByteEdits.
Only Invoke-PhpFunction's listed builtin arms and local helpers change.
PHP coercion/diagnostic policy stays in PowerShell; immutable storage stays in
the pinned AllPhp.ByteValues runtime. No oracle is invoked by generated code.

Primary references: php.net/manual/en/function.{strpos,trim,explode,str-replace}.php
Version-sensitive behavior was checked against the pinned local PHP8.5.12.
In particular, 8.5 trim defaults exclude form feed (added upstream in 8.6).
"""
import re
import hashlib
from textwrap import dedent, indent

BASE_SHA256 = '5856687f7abd1471b4af7af9827ca2d17a011e836ad2852bf1d7993298fddc9f'

BASE_ARM_HASHES = {'strlen': '5a8900575a9964d90e0ecbb07e0f3686bd71331a0f3d1572babf37e59c3808ea', 'strtoupper': '18f10ff9b8a9258af54bf5f8abb1d43ba91ded52ffe395700f06388fc99b4f88', 'strtolower': '3040b2f4c8a83f3b1c04dcfa11110da54bf9d3ae4100e81bad2d8d09762e47af', 'trim': '2cdb502f6d05c25795c1a9ece744e29f254f9916a5bc5ae4f8f0e4582d49bcc5', 'is_string': '2c794b040e34bfbb2b1cf064ebcc470712ee610b746c9a8a1506b99c5affdfe4', 'str_contains': '96b21b0e67c602595acbc28e341b27cc3f89ea22736875fc3d0d3af2a898e669', 'str_starts_with': 'a510f2d393fe73f7946a0f8a55ee5eefaebfd5a2116180ce76b54f564448bb8d', 'str_ends_with': 'b6f79cf4cb2d53513ff65a49ba68db3fb3d7b40939dc64eb0ef0bb123c94f273', 'strpos': '868777b11115d6c385d7ed694192a1d78584a2b6acebcb2f4ba9dde53380938b', 'substr': 'f03407ae5b9ddc775613b3cd957afb0909e71dd773e3e695054b78f0eedcbdf3', 'str_replace': '971d731ef7f531460321eb4f32e6f180a50c69432ea7e27a478664fbe1f83941', 'explode': 'bd0f71c419e26ff8b468f9121bb842a962b30ce014e5e55f47fec67f39071be9', 'implode': 'ea31b05a59c7e4cd067167d41a74c429855a4d66da018f0bcc0ad7d45aa5335b', 'str_repeat': 'f98f94c8a537c8995722f357e27b48f76142ee635c5636abaaf5f75c5c297c81', 'strval': '0e3a4bc145e0a5be058b5fa2141cb19fd522043e6755ece8b18a7eae93cc2145', 'gettype': '4ac7841e0dc2cb0ddab6f2a06b647732cb604196fdfb7a3a6e572bac23adcc0f'}

HELPERS = dedent(r'''
function Get-PhpBuiltinTypeName($value) {
    if (Is-PhpRefCell $value) { $value=$value.Value }
    if ($null -eq $value) { return 'null' }
    if (Is-PhpStringValue $value) { return 'string' }
    if ($value -is [long]) { return 'int' }
    if ($value -is [double]) { return 'float' }
    if ($value -is [bool]) { return 'bool' }
    if (Is-PhpArray $value) { return 'array' }
    if (Is-PhpObject $value) { return $value.Class }
    return $value.GetType().Name
}
function Assert-PhpStringBuiltinArity([string]$function, $arguments, [int]$minimum, [int]$maximum) {
    $actual=$arguments.Count
    if ($actual -ge $minimum -and $actual -le $maximum) { return }
    $mode=if($minimum -eq $maximum){'exactly'}elseif($actual -lt $minimum){'at least'}else{'at most'}
    $expected=if($actual -gt $maximum){$maximum}else{$minimum}
    $noun=if($expected -eq 1){'argument'}else{'arguments'}
    Throw-PhpError 'ArgumentCountError' ($function+'() expects '+$mode+' '+$expected+' '+$noun+', '+$actual+' given')
}
function ConvertTo-PhpBuiltinBytes($value, [string]$function, [int]$number, [string]$parameter, [string]$accepted='string') {
    if (Is-PhpRefCell $value) { $value=$value.Value }
    if ($null -eq $value) {
        Write-PhpDiagnostic 8192 ($function+'(): Passing null to parameter #'+$number+' ($'+$parameter+') of type '+$accepted+' is deprecated')
        return [AllPhp.ByteValues.PhpBytes]::Empty
    }
    if ((Is-PhpStringValue $value) -or (Is-PhpNum $value) -or $value -is [bool]) { return (To-PhpBytes $value) }
    if ((Is-PhpObject $value) -and $null -ne (Find-OptionalPhpMethod $value.Class '__toString')) { return (To-PhpBytes $value) }
    Throw-PhpError 'TypeError' ($function+'(): Argument #'+$number+' ($'+$parameter+') must be of type '+$accepted+', '+(Get-PhpBuiltinTypeName $value)+' given')
}
function ConvertTo-PhpBuiltinInteger($value, [string]$function, [int]$number, [string]$parameter) {
    if (Is-PhpRefCell $value) { $value=$value.Value }
    if ($value -is [long]) { return $value }
    if ($null -eq $value) {
        Write-PhpDiagnostic 8192 ($function+'(): Passing null to parameter #'+$number+' ($'+$parameter+') of type int is deprecated')
        return [long]0
    }
    if ($value -is [bool]) { if($value){return [long]1};return [long]0 }
    $numeric=$null;$fromString=Is-PhpStringValue $value
    if ($fromString) { $numeric=ConvertFrom-PhpNumericString $value $false }
    elseif ($value -is [double]) { $numeric=$value }
    if ($null -ne $numeric) {
        if ($numeric -is [long]) { return $numeric }
        if (-not [double]::IsNaN($numeric) -and -not [double]::IsInfinity($numeric) -and
            $numeric -ge -9223372036854775808.0 -and $numeric -lt 9223372036854775808.0) {
            $integer=To-PhpInt $numeric
            if ([double]$integer -ne $numeric) {
                $shown=if($fromString){'float-string "'+(Get-PhpHostText (To-PhpBytes $value))+'"'}else{'float '+(Format-PhpFloat $numeric 14)}
                Write-PhpDiagnostic 8192 ('Implicit conversion from '+$shown+' to int loses precision')
            }
            return [long]$integer
        }
    }
    Throw-PhpError 'TypeError' ($function+'(): Argument #'+$number+' ($'+$parameter+') must be of type int, '+(Get-PhpBuiltinTypeName $value)+' given')
}
function Test-PhpBytesAt($haystack, $needle, [long]$position) {
    if ($position -lt 0 -or $position -gt $haystack.Length -or $needle.Length -gt $haystack.Length-$position) { return $false }
    return $haystack.Slice($position,$needle.Length).Equals($needle)
}
function Find-PhpBytes($haystack, $needle, [long]$start) {
    if ($start -lt 0 -or $start -gt $haystack.Length) { throw 'ALL PHP byte builtin: invalid internal search start' }
    if ($needle.Length -eq 0) { return [long]$start }
    if ($needle.Length -gt $haystack.Length-$start) { return [long]-1 }
    $first=[byte]$needle.GetByte(0);$buffer=[byte[]]::new(65536)
    $last=[long]($haystack.Length-$needle.Length);$position=[long]$start
    while ($position -le $last) {
        $count=[int][Math]::Min([long]65536,$last-$position+1)
        $haystack.CopyTo($position,$buffer,0,$count);$cursor=0
        while ($cursor -lt $count) {
            $found=[Array]::IndexOf($buffer,$first,[int]$cursor,[int]($count-$cursor))
            if ($found -lt 0) { break }
            $absolute=[long]($position+$found)
            if (Test-PhpBytesAt $haystack $needle $absolute) { return $absolute }
            $cursor=$found+1
        }
        $position+=$count
    }
    return [long]-1
}
function New-PhpTrimMask($characters, [bool]$hasCharacters) {
    $mask=[bool[]]::new(256)
    if (-not $hasCharacters) { foreach($b in @(0,9,10,11,13,32)){$mask[$b]=$true};return ,$mask }
    $length=$characters.Length
    for($i=[long]0;$i -lt $length;$i++) {
        $byte=[int]$characters.GetByte($i)
        if($i+3 -lt $length -and $characters.GetByte($i+1)-eq46 -and $characters.GetByte($i+2)-eq46 -and $byte-le$characters.GetByte($i+3)) {
            $end=[int]$characters.GetByte($i+3)
            for($b=$byte;$b-le$end;$b++){$mask[$b]=$true}
            $i+=3;continue
        }
        $mask[$byte]=$true
        if($byte-eq46 -and $i+1-lt$length -and $characters.GetByte($i+1)-eq46) {
            $detail=''
            if($i-eq0){$detail=", no character to the left of '..'"}
            elseif($i+2-ge$length){$detail=", no character to the right of '..'"}
            elseif($characters.GetByte($i-1)-gt$characters.GetByte($i+2)){$detail=", '..'-range needs to be incrementing"}
            Write-PhpDiagnostic 2 ("trim(): Invalid '..'-range"+$detail)
            $i++
        }
    }
    return ,$mask
}
function Trim-PhpBytes($value, $mask) {
    $start=[long]0;$end=[long]$value.Length;$buffer=[byte[]]::new(65536)
    while($start-lt$end) {
        $count=[int][Math]::Min([long]65536,$end-$start);$value.CopyTo($start,$buffer,0,$count);$i=0
        while($i-lt$count -and $mask[[int]$buffer[$i]]){$i++}
        $start+=$i;if($i-lt$count){break}
    }
    while($end-gt$start) {
        $count=[int][Math]::Min([long]65536,$end-$start);$value.CopyTo($end-$count,$buffer,0,$count);$i=$count-1
        while($i-ge0 -and $mask[[int]$buffer[$i]]){$i--}
        $end-=($count-1-$i);if($i-ge0){break}
    }
    return $value.Slice($start,$end-$start)
}
function Replace-PhpByteSequence($subject, $needle, $replacement) {
    if ($needle.Length-eq0) { return $subject }
    $builder=[AllPhp.ByteValues.PhpByteBuilder]::new();$start=[long]0
    while($start-le$subject.Length) {
        $found=Find-PhpBytes $subject $needle $start
        if($found-lt0){$builder.Append($subject.Slice($start,$null));break}
        $builder.Append($subject.Slice($start,$found-$start));$builder.Append($replacement)
        $start=$found+$needle.Length
    }
    return $builder.ToPhpBytes()
}
function Invoke-PhpByteReplace($search, $replace, $subject) {
    $searchArray=Is-PhpArray $search;$replaceArray=Is-PhpArray $replace
    if(-not $searchArray -and $replaceArray) {
        Throw-PhpError 'TypeError' 'str_replace(): Argument #2 ($replace) must be of type string when argument #1 ($search) is a string'
    }
    $needles=[Collections.Generic.List[object]]::new();$replacements=[Collections.Generic.List[object]]::new()
    if($searchArray){foreach($k in $search.Items.Keys){[void]$needles.Add((To-PhpBytes $search.Items[$k]))}}
    else{[void]$needles.Add((ConvertTo-PhpBuiltinBytes $search 'str_replace' 1 'search' 'array|string'))}
    if($replaceArray){foreach($k in $replace.Items.Keys){[void]$replacements.Add((To-PhpBytes $replace.Items[$k]))}}
    else{[void]$replacements.Add((ConvertTo-PhpBuiltinBytes $replace 'str_replace' 2 'replace' 'array|string'))}
    $subjectArray=Is-PhpArray $subject
    if($subjectArray){$out=New-PhpArray;$keys=@($subject.Items.Keys)}else{$keys=@($null)}
    foreach($key in $keys) {
        $entry=if($subjectArray){To-PhpBytes $subject.Items[$key]}else{ConvertTo-PhpBuiltinBytes $subject 'str_replace' 3 'subject' 'array|string'}
        for($i=0;$i-lt$needles.Count;$i++) {
            $replacement=if(-not$replaceArray){$replacements[0]}elseif($i-lt$replacements.Count){$replacements[$i]}else{[AllPhp.ByteValues.PhpBytes]::Empty}
            $entry=Replace-PhpByteSequence $entry $needles[$i] $replacement
        }
        if($subjectArray){Set-PhpArrayItem $out (Get-PhpKeyValue $key) $entry $false}else{return $entry}
    }
    return $out
}
''').strip() + '\n'


def _arm(name, body):
    return "                '" + name + "' {\n" + indent(dedent(body).strip() + '\n', ' ' * 20) + '                }'


ARMS = {
    'strlen': r'''
        Assert-PhpStringBuiltinArity 'strlen' $callArgs 1 1
        return [long](ConvertTo-PhpBuiltinBytes $callArgs[0] 'strlen' 1 'string').Length
    ''',
    'strtoupper': r'''
        Assert-PhpStringBuiltinArity 'strtoupper' $callArgs 1 1
        return (ConvertTo-PhpBuiltinBytes $callArgs[0] 'strtoupper' 1 'string').UpperAscii()
    ''',
    'strtolower': r'''
        Assert-PhpStringBuiltinArity 'strtolower' $callArgs 1 1
        return (ConvertTo-PhpBuiltinBytes $callArgs[0] 'strtolower' 1 'string').LowerAscii()
    ''',
    'trim': r'''
        Assert-PhpStringBuiltinArity 'trim' $callArgs 1 2
        $bytes=ConvertTo-PhpBuiltinBytes $callArgs[0] 'trim' 1 'string'
        $characters=$null
        if($callArgs.Count-eq2){$characters=ConvertTo-PhpBuiltinBytes $callArgs[1] 'trim' 2 'characters'}
        $mask=New-PhpTrimMask $characters ($callArgs.Count-eq2)
        return (Trim-PhpBytes $bytes $mask)
    ''',
    'is_string': r'''
        Assert-PhpStringBuiltinArity 'is_string' $callArgs 1 1
        return (Is-PhpStringValue $callArgs[0])
    ''',
    'str_contains': r'''
        Assert-PhpStringBuiltinArity 'str_contains' $callArgs 2 2
        $haystack=ConvertTo-PhpBuiltinBytes $callArgs[0] 'str_contains' 1 'haystack'
        $needle=ConvertTo-PhpBuiltinBytes $callArgs[1] 'str_contains' 2 'needle'
        return ((Find-PhpBytes $haystack $needle 0)-ge0)
    ''',
    'str_starts_with': r'''
        Assert-PhpStringBuiltinArity 'str_starts_with' $callArgs 2 2
        $haystack=ConvertTo-PhpBuiltinBytes $callArgs[0] 'str_starts_with' 1 'haystack'
        $needle=ConvertTo-PhpBuiltinBytes $callArgs[1] 'str_starts_with' 2 'needle'
        return (Test-PhpBytesAt $haystack $needle 0)
    ''',
    'str_ends_with': r'''
        Assert-PhpStringBuiltinArity 'str_ends_with' $callArgs 2 2
        $haystack=ConvertTo-PhpBuiltinBytes $callArgs[0] 'str_ends_with' 1 'haystack'
        $needle=ConvertTo-PhpBuiltinBytes $callArgs[1] 'str_ends_with' 2 'needle'
        return (Test-PhpBytesAt $haystack $needle ($haystack.Length-$needle.Length))
    ''',
    'strpos': r'''
        Assert-PhpStringBuiltinArity 'strpos' $callArgs 2 3
        $haystack=ConvertTo-PhpBuiltinBytes $callArgs[0] 'strpos' 1 'haystack'
        $needle=ConvertTo-PhpBuiltinBytes $callArgs[1] 'strpos' 2 'needle'
        $offset=[long]0
        if($callArgs.Count-eq3){$offset=ConvertTo-PhpBuiltinInteger $callArgs[2] 'strpos' 3 'offset'}
        if($offset-lt0){$offset=$haystack.Length+$offset}
        if($offset-lt0 -or $offset-gt$haystack.Length) {
            Throw-PhpError 'ValueError' 'strpos(): Argument #3 ($offset) must be contained in argument #1 ($haystack)'
        }
        $position=Find-PhpBytes $haystack $needle $offset
        if($position-lt0){return $false};return [long]$position
    ''',
    'substr': r'''
        Assert-PhpStringBuiltinArity 'substr' $callArgs 2 3
        $bytes=ConvertTo-PhpBuiltinBytes $callArgs[0] 'substr' 1 'string'
        $offset=ConvertTo-PhpBuiltinInteger $callArgs[1] 'substr' 2 'offset'
        $length=$null
        if($callArgs.Count-eq3 -and $null-ne$callArgs[2]){$length=ConvertTo-PhpBuiltinInteger $callArgs[2] 'substr' 3 'length'}
        return $bytes.Slice($offset,$length)
    ''',
    'str_replace': r'''
        # Fourth by-reference count is a separate call-binding obligation.
        if($callArgs.Count-ne3){throw 'ALL PHP: str_replace() count-reference binding is not implemented; three arguments are supported'}
        return (Invoke-PhpByteReplace $callArgs[0] $callArgs[1] $callArgs[2])
    ''',
    'explode': r'''
        Assert-PhpStringBuiltinArity 'explode' $callArgs 2 3
        $separator=ConvertTo-PhpBuiltinBytes $callArgs[0] 'explode' 1 'separator'
        $subject=ConvertTo-PhpBuiltinBytes $callArgs[1] 'explode' 2 'string'
        $limit=[long]::MaxValue
        if($callArgs.Count-eq3){$limit=ConvertTo-PhpBuiltinInteger $callArgs[2] 'explode' 3 'limit'}
        if($separator.Length-eq0){Throw-PhpError 'ValueError' 'explode(): Argument #1 ($separator) must not be empty'}
        if($limit-eq0){$limit=[long]1}
        $parts=[Collections.Generic.List[object]]::new();$start=[long]0
        while($start-le$subject.Length) {
            if($limit-gt0 -and [long]$parts.Count-ge$limit-1){[void]$parts.Add($subject.Slice($start,$null));break}
            $found=Find-PhpBytes $subject $separator $start
            if($found-lt0){[void]$parts.Add($subject.Slice($start,$null));break}
            [void]$parts.Add($subject.Slice($start,$found-$start));$start=$found+$separator.Length
        }
        $take=[long]$parts.Count
        if($limit-lt0){$take=[Math]::Max([long]0,$take+$limit)}
        $out=New-PhpArray
        for($i=0;$i-lt$take;$i++){Set-PhpArrayItem $out $null $parts[$i] $true}
        return $out
    ''',
    'implode': r'''
        Assert-PhpStringBuiltinArity 'implode' $callArgs 1 2
        $separator=[AllPhp.ByteValues.PhpBytes]::Empty;$items=$null
        if($callArgs.Count-eq1) {
            $items=$callArgs[0]
            if(-not(Is-PhpArray $items)){Throw-PhpError 'TypeError' ('implode(): Argument #1 ($array) must be of type array, '+(Get-PhpBuiltinTypeName $items)+' given')}
        } else {
            $separator=ConvertTo-PhpBuiltinBytes $callArgs[0] 'implode' 1 'separator' 'array|string'
            $items=$callArgs[1]
            if(-not(Is-PhpArray $items)){Throw-PhpError 'TypeError' ('implode(): Argument #2 ($array) must be of type ?array, '+(Get-PhpBuiltinTypeName $items)+' given')}
        }
        $builder=[AllPhp.ByteValues.PhpByteBuilder]::new();$first=$true
        foreach($key in $items.Items.Keys) {
            if(-not$first){$builder.Append($separator)};$first=$false
            $builder.Append((To-PhpBytes $items.Items[$key]))
        }
        return $builder.ToPhpBytes()
    ''',
    'str_repeat': r'''
        Assert-PhpStringBuiltinArity 'str_repeat' $callArgs 2 2
        $bytes=ConvertTo-PhpBuiltinBytes $callArgs[0] 'str_repeat' 1 'string'
        $times=ConvertTo-PhpBuiltinInteger $callArgs[1] 'str_repeat' 2 'times'
        if($times-lt0){Throw-PhpError 'ValueError' 'str_repeat(): Argument #2 ($times) must be greater than or equal to 0'}
        return $bytes.Repeat($times)
    ''',
    'strval': r'''
        Assert-PhpStringBuiltinArity 'strval' $callArgs 1 1
        return (To-PhpBytes $callArgs[0])
    ''',
    'gettype': r'''
        Assert-PhpStringBuiltinArity 'gettype' $callArgs 1 1
        $item=$callArgs[0]
        if(Is-PhpRefCell $item){$item=$item.Value}
        $type=if($null-eq$item){'NULL'}elseif($item-is[bool]){'boolean'}elseif($item-is[long]){'integer'}elseif($item-is[double]){'double'}elseif(Is-PhpStringValue $item){'string'}elseif(Is-PhpArray $item){'array'}else{'object'}
        return [AllPhp.ByteValues.PhpBytes]::FromUtf8($type)
    ''',
}


def apply(value: str) -> str:
    newline = '\r\n' if '\r\n' in value else '\n'
    value = value.replace('\r\n', '\n')
    expression = re.compile(r'^        function Invoke-PhpFunction\(\[string\]\$name, \$callArgs\) \{.*?^        }\n', re.M | re.S)
    matches = list(expression.finditer(value))
    if len(matches) != 1:
        raise ValueError(f'Expected one Invoke-PhpFunction, found {len(matches)}')
    match = matches[0]
    body = match.group()
    for name, replacement in ARMS.items():
        case = re.compile(r"^                '" + re.escape(name) + r"' \{.*?^                }", re.M | re.S)
        anchors = list(case.finditer(body))
        if len(anchors) != 1:
            raise ValueError(f'Expected one string builtin {name}, found {len(anchors)}')
        anchor = anchors[0]
        if hashlib.sha256(anchor.group().encode('utf-8')).hexdigest() != BASE_ARM_HASHES[name]:
            raise ValueError(f'String builtin {name} changed since pinned base; refuse to overwrite')
        body = body[:anchor.start()] + _arm(name, replacement) + body[anchor.end():]
    helper_names = re.findall(r'^function ([^ (]+)', HELPERS, re.M)
    if any(re.search(r'^        function '+re.escape(name)+r'(?=[ (])',value,re.M) for name in helper_names):
        raise ValueError('String builtin helpers already present; refuse duplicate migration')
    value = value[:match.start()] + indent(HELPERS, ' '*8) + body + value[match.end():]
    return value.replace('\n', newline)
