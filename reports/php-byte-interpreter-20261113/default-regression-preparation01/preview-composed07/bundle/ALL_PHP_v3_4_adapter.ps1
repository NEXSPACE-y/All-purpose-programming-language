@{
    Name = 'PHP'
    Run = {
        param([string]$Code)
        $ErrorActionPreference = 'Stop'

        # ALL's own PHP subset interpreter. No PHP executable, eval, or Invoke-Expression.
        $source = $Code.Trim()
        if ($source -notmatch '^<\?php(?:\s|$)') {
            throw 'ALL PHP: A <?php opening tag is required'
        }
        $source = [regex]::Replace($source, '^<\?php\b', '')
        $source = $source.TrimEnd()
        if ($source.EndsWith('?>')) {
            $source = $source.Substring(0, $source.Length - 2)
        }

        $state = @{
            Tokens = [System.Collections.Generic.List[string]]::new()
            Pos = 0
            Vars = [System.Collections.Generic.Dictionary[string,object]]::new(
                [System.StringComparer]::Ordinal)
            Functions = [System.Collections.Generic.Dictionary[string,object]]::new(
                [System.StringComparer]::OrdinalIgnoreCase)
            Classes = [System.Collections.Generic.Dictionary[string,object]]::new(
                [System.StringComparer]::OrdinalIgnoreCase)
            Flow = @{ Returned = $false; Value = $null; LoopControl=$null; LoopDepth=0 }
            CallDepth = 0
            Steps = 0
            JsonError = 0
            JsonErrorMessage = 'No error'
        }

        # Tokenize before parsing. Unknown characters produce an error, never disappear.
        $pattern = '(?:\s+|//[^\r\n]*|\#[^\r\n]*|/\*[\s\S]*?\*/|"(?:\\.|[^"\\])*"|''(?:\\.|[^''\\])*''|\$[A-Za-z_][A-Za-z_0-9]*|\d+(?:\.\d+)?|[A-Za-z_][A-Za-z_0-9]*|===|!==|==|!=|<=|>=|&&|\|\||=>|->|\*\*=|\*\*|\?\?=|\?\?|\?->|\+\+|--|\*=|/=|%=|\+=|-=|\.=|[+\-*/%.=<>!?:;{},()\[\]])'
        $rx = [regex]::new($pattern)
        for ($offset = 0; $offset -lt $source.Length;) {
            $match = $rx.Match($source, $offset)
            if (-not $match.Success -or $match.Index -ne $offset) {
                throw "ALL PHP: Unknown character at offset $offset"
            }
            $token = $match.Value
            if (-not [string]::IsNullOrWhiteSpace($token) -and
                -not $token.StartsWith('//') -and
                -not $token.StartsWith('#') -and
                -not $token.StartsWith('/*')) {
                [void]$state.Tokens.Add($token)
            }
            $offset += $token.Length
        }
        [void]$state.Tokens.Add('(EOF)')

        function Peek-Token {
            return $state.Tokens[$state.Pos]
        }
        function Next-Token {
            $token = Peek-Token
            if ($token -ne '(EOF)') { $state.Pos++ }
            return $token
        }
        function Expect-Token([string]$expected) {
            if ((Peek-Token) -cne $expected) {
                throw "ALL PHP: Expected '$expected', got '$(Peek-Token)'"
            }
            [void](Next-Token)
        }
        function Decode-PhpString([string]$text) {
            $quote = $text[0]
            $sb = [System.Text.StringBuilder]::new()
            for ($i = 1; $i -lt $text.Length - 1; $i++) {
                $ch = $text[$i]
                if ($ch -eq '\') {
                    if ($i + 1 -ge $text.Length - 1) {
                        throw 'ALL PHP: Unterminated string escape'
                    }
                    $i++
                    $next = $text[$i]
                    if ($quote -eq "'") {
                        if ($next -eq "'" -or $next -eq '\') {
                            [void]$sb.Append($next)
                        } else {
                            [void]$sb.Append('\')
                            [void]$sb.Append($next)
                        }
                    } else {
                        switch ([string]$next) {
                            'n' { [void]$sb.Append("`n") }
                            'r' { [void]$sb.Append("`r") }
                            't' { [void]$sb.Append("`t") }
                            '\' { [void]$sb.Append('\') }
                            '"' { [void]$sb.Append('"') }
                            '$' { [void]$sb.Append('$') }
                            default {
                                [void]$sb.Append('\')
                                [void]$sb.Append($next)
                            }
                        }
                    }
                } elseif ($ch -eq '$' -and $quote -eq '"') {
                    throw 'ALL PHP: String interpolation is not implemented'
                } else {
                    [void]$sb.Append($ch)
                }
            }
            return $sb.ToString()
        }
        function Expand-PhpDoubleString([string]$token) {
            $body = $token.Substring(1, $token.Length - 2)
            $output = [System.Text.StringBuilder]::new()
            for ($i=0; $i -lt $body.Length; $i++) {
                $ch = $body[$i]
                if ($ch -eq '\') {
                    if ($i + 1 -ge $body.Length) {
                        [void]$output.Append('\')
                        continue
                    }
                    $next = $body[$i + 1]
                    if ([string]$next -cmatch '[0-7xu]') {
                        throw 'ALL PHP: Hexadecimal, octal and Unicode string escapes are not implemented'
                    }
                    $recognized = $true
                    switch ([string]$next) {
                        'n' { [void]$output.Append("`n") }
                        'r' { [void]$output.Append("`r") }
                        't' { [void]$output.Append("`t") }
                        'v' { [void]$output.Append([char]11) }
                        'e' { [void]$output.Append([char]27) }
                        'f' { [void]$output.Append([char]12) }
                        '\' { [void]$output.Append('\') }
                        '"' { [void]$output.Append('"') }
                        '$' { [void]$output.Append('$') }
                        default { $recognized = $false }
                    }
                    if ($recognized) { $i++; continue }
                    [void]$output.Append('\')
                    continue
                }
                if ($ch -eq '$' -and $i + 1 -lt $body.Length -and
                    $body[$i + 1] -eq '{') {
                    throw 'ALL PHP: Legacy ${...} interpolation is not implemented'
                }
                $braced = $false
                $start = $i
                if ($ch -eq '{' -and $i + 1 -lt $body.Length -and $body[$i + 1] -eq '$') {
                    $braced = $true
                    $start++
                } elseif ($ch -ne '$') {
                    [void]$output.Append($ch)
                    continue
                }
                if ($start + 1 -ge $body.Length -or
                    -not ([string]$body[$start + 1] -cmatch '[A-Za-z_]')) {
                    [void]$output.Append($ch)
                    continue
                }
                $end = $start + 2
                while ($end -lt $body.Length -and
                    ([string]$body[$end] -cmatch '[A-Za-z_0-9]')) { $end++ }
                if ($braced) {
                    if ($end -ge $body.Length -or $body[$end] -ne '}') {
                        throw 'ALL PHP: Complex braced string interpolation is not implemented'
                    }
                } elseif ($end -lt $body.Length -and
                         ($body[$end] -eq '[' -or
                         ($end + 1 -lt $body.Length -and
                          $body.Substring($end, 2) -ceq '->'))) {
                    throw 'ALL PHP: Complex string interpolation is not implemented'
                }
                $name = $body.Substring($start + 1, $end - $start - 1)
                if ($state.Vars.ContainsKey($name)) {
                    [void]$output.Append((To-PhpText $state.Vars[$name]))
                }
                if ($braced) { $i = $end }
                else { $i = $end - 1 }
            }
            return $output.ToString()
        }
        function Read-Arguments {
            Expect-Token '('
            $callArgs = [System.Collections.Generic.List[object]]::new()
            if ((Peek-Token) -cne ')') {
                while ($true) {
                    [void]$callArgs.Add((Read-Expr 1))
                    if ((Peek-Token) -cne ',') { break }
                    [void](Next-Token)
                    if ((Peek-Token) -ceq ')') { break }
                }
            }
            Expect-Token ')'
            return ,($callArgs.ToArray())
        }
        function Read-Array([string]$close) {
            $entries = [System.Collections.Generic.List[object]]::new()
            if ((Peek-Token) -cne $close) {
                while ($true) {
                    $first = Read-Expr 1
                    $key = $null
                    $value = $first
                    if ((Peek-Token) -ceq '=>') {
                        [void](Next-Token)
                        $key = $first
                        $value = Read-Expr 1
                    }
                    [void]$entries.Add([pscustomobject]@{ Key=$key; Value=$value })
                    if ((Peek-Token) -cne ',') { break }
                    [void](Next-Token)
                    if ((Peek-Token) -ceq $close) { break }
                }
            }
            Expect-Token $close
            return [pscustomobject]@{ Kind='array'; Entries=$entries.ToArray() }
        }
        function Read-Primary {
            $token = Peek-Token
            if ($token -ceq '(') {
                [void](Next-Token)
                $expr = Read-Expr 1
                Expect-Token ')'
                return $expr
            }
            if ($token -ceq '[') {
                [void](Next-Token)
                return (Read-Array ']')
            }
            if ($token -match '^\d+(?:\.\d+)?$') {
                [void](Next-Token)
                $num = [decimal]::Parse($token,
                    [System.Globalization.CultureInfo]::InvariantCulture)
                return [pscustomobject]@{ Kind='literal'; Value=$num }
            }
            if ($token.StartsWith('"')) {
                [void](Next-Token)
                return [pscustomobject]@{ Kind='double_string'; Raw=$token }
            }
            if ($token.StartsWith("'")) {
                [void](Next-Token)
                return [pscustomobject]@{
                    Kind='literal'; Value=(Decode-PhpString $token)
                }
            }
            if ($token -cmatch '^\$[A-Za-z_][A-Za-z_0-9]*$') {
                [void](Next-Token)
                return [pscustomobject]@{ Kind='variable'; Name=$token.Substring(1) }
            }
            if ($token -eq 'match') {
                [void](Next-Token)
                Expect-Token '('
                $subject = Read-Expr 1
                Expect-Token ')'
                Expect-Token '{'
                $arms = [System.Collections.Generic.List[object]]::new()
                while ((Peek-Token) -cne '}') {
                    $patterns = [System.Collections.Generic.List[object]]::new()
                    $isDefault = $false
                    if ((Peek-Token) -eq 'default') {
                        [void](Next-Token)
                        $isDefault = $true
                    } else {
                        [void]$patterns.Add((Read-Expr 1))
                        while ((Peek-Token) -ceq ',') {
                            [void](Next-Token)
                            if ((Peek-Token) -ceq '=>') { break }
                            [void]$patterns.Add((Read-Expr 1))
                        }
                    }
                    Expect-Token '=>'
                    $valueExpr = Read-Expr 1
                    [void]$arms.Add([pscustomobject]@{
                        IsDefault=$isDefault; Patterns=$patterns.ToArray(); Value=$valueExpr
                    })
                    if ((Peek-Token) -cne ',') { break }
                    [void](Next-Token)
                    if ((Peek-Token) -ceq '}') { break }
                }
                Expect-Token '}'
                return [pscustomobject]@{
                    Kind='match'; Subject=$subject; Arms=$arms.ToArray()
                }
            }
            if ($token -eq 'new') {
                [void](Next-Token)
                $className = Next-Token
                if ($className -cnotmatch '^[A-Za-z_][A-Za-z_0-9]*$') {
                    throw "ALL PHP: Expected class name, got '$className'"
                }
                $callArgs = @()
                if ((Peek-Token) -ceq '(') { $callArgs = Read-Arguments }
                return [pscustomobject]@{ Kind='new'; Name=$className; Args=@($callArgs) }
            }
            if ($token -eq 'array') {
                [void](Next-Token)
                Expect-Token '('
                return (Read-Array ')')
            }
            switch ($token) {
                'true'  { [void](Next-Token); return [pscustomobject]@{ Kind='literal'; Value=$true } }
                'false' { [void](Next-Token); return [pscustomobject]@{ Kind='literal'; Value=$false } }
                'null'  { [void](Next-Token); return [pscustomobject]@{ Kind='literal'; Value=$null } }
            }
            if ($token -cmatch '^[A-Za-z_][A-Za-z_0-9]*$') {
                [void](Next-Token)
                if ((Peek-Token) -ceq '(') {
                    $callArgs = Read-Arguments
                    return [pscustomobject]@{ Kind='call'; Name=$token; Args=@($callArgs) }
                }
            }
            throw "ALL PHP: Unsupported expression starting with '$token'"
        }
        function Read-Postfix {
            $expr = Read-Primary
            while ($true) {
                $token = Peek-Token
                if ($token -ceq '[') {
                    [void](Next-Token)
                    $key = $null
                    if ((Peek-Token) -cne ']') { $key = Read-Expr 1 }
                    Expect-Token ']'
                    $expr = [pscustomobject]@{ Kind='index'; Base=$expr; Key=$key }
                    continue
                }
                if ($token -ceq '->' -or $token -ceq '?->') {
                    [void](Next-Token)
                    $nullSafe = ($token -ceq '?->')
                    $member = Next-Token
                    if ($member -cnotmatch '^[A-Za-z_][A-Za-z_0-9]*$') {
                        throw "ALL PHP: Expected member name, got '$member'"
                    }
                    if ((Peek-Token) -ceq '(') {
                        $callArgs = Read-Arguments
                        $expr = [pscustomobject]@{
                            Kind='method'; Base=$expr; Name=$member; Args=@($callArgs)
                            NullSafe=$nullSafe
                        }
                    } else {
                        $expr = [pscustomobject]@{
                            Kind='property'; Base=$expr; Name=$member
                            NullSafe=$nullSafe
                        }
                    }
                    continue
                }
                break
            }
            return $expr
        }
        function Read-Unary {
            $token = Peek-Token
            if ($token -in @('!', '+', '-')) {
                [void](Next-Token)
                $arg = Read-Unary
                return [pscustomobject]@{ Kind='unary'; Op=$token; Arg=$arg }
            }
            return (Read-Power)
        }
        function Read-Power {
            $left = Read-Postfix
            if ((Peek-Token) -ceq '**') {
                [void](Next-Token)
                $right = Read-Unary
                return [pscustomobject]@{
                    Kind='binary'; Op='**'; Left=$left; Right=$right
                }
            }
            return $left
        }
        function Operator-Priority([string]$op) {
            switch ($op) {
                '??' { return 2 }
                '||' { return 3 }
                '&&' { return 4 }
                '==' { return 5 }
                '!=' { return 5 }
                '===' { return 5 }
                '!==' { return 5 }
                '<' { return 6 }
                '<=' { return 6 }
                '>' { return 6 }
                '>=' { return 6 }
                '.' { return 7 }
                '+' { return 8 }
                '-' { return 8 }
                '*' { return 9 }
                '/' { return 9 }
                '%' { return 9 }
                default { return 0 }
            }
        }
        function Read-Expr([int]$minPriority) {
            $left = Read-Unary
            while ($true) {
                $op = Peek-Token
                $priority = Operator-Priority $op
                if ($priority -lt $minPriority) { break }
                [void](Next-Token)
                if ($op -ceq '??') {
                    $right = Read-Expr $priority
                } else {
                    $right = Read-Expr ($priority + 1)
                }
                $left = [pscustomobject]@{
                    Kind='binary'; Op=$op; Left=$left; Right=$right
                }
            }
            # PHP 8+ ternary is non-associative. Keep chained forms unsupported
            # unless the author explicitly groups them with parentheses.
            if ($minPriority -eq 1 -and (Peek-Token) -ceq '?') {
                [void](Next-Token)
                $ifTrue = $null
                if ((Peek-Token) -cne ':') { $ifTrue = Read-Expr 1 }
                Expect-Token ':'
                $ifFalse = Read-Expr 1
                $left = [pscustomobject]@{
                    Kind='ternary'; Test=$left; Yes=$ifTrue; No=$ifFalse
                }
            }
            if ($minPriority -eq 1 -and
                (Peek-Token) -in @('=','+=','-=','.=','??=','*=','/=','%=','**=')) {
                if ($left.Kind -notin @('variable','index','property')) {
                    throw 'ALL PHP: Invalid assignment expression target'
                }
                $assignmentOp = Next-Token
                $right = Read-Expr 1
                $left = [pscustomobject]@{
                    Kind='assign_expr'; Target=$left; Op=$assignmentOp; Value=$right
                }
            }
            return $left
        }
        # A deliberately bounded for-header parser: variable, array, or property
        # assignment; postfix ++ / --; comma-separated mutations.
        function Read-ForMutations([string]$endToken) {
            $nodes = [System.Collections.Generic.List[object]]::new()
            while ((Peek-Token) -cne $endToken) {
                $target = Read-Postfix
                if ($target.Kind -notin @('variable','index','property')) {
                    throw 'ALL PHP: Invalid for-loop mutation target'
                }
                $op = Next-Token
                if ($op -in @('++','--')) {
                    $op = if ($op -ceq '++') { '+=' } else { '-=' }
                    $value = [pscustomobject]@{ Kind='literal'; Value=[decimal]1 }
                } elseif ($op -in @('=','+=','-=','.=','??=','*=','/=','%=','**=')) {
                    $value = Read-Expr 1
                } else {
                    throw "ALL PHP: Unsupported for-loop mutation '$op'"
                }
                [void]$nodes.Add([pscustomobject]@{
                    Kind='assign'; Target=$target; Op=$op; Value=$value
                })
                if ((Peek-Token) -cne ',') { break }
                [void](Next-Token)
            }
            Expect-Token $endToken
            return ,($nodes.ToArray())
        }
        function Read-Statement {
            $token = Peek-Token
            if ($token -ceq '{') {
                [void](Next-Token)
                $body = [System.Collections.Generic.List[object]]::new()
                while ((Peek-Token) -cne '}') {
                    if ((Peek-Token) -ceq '(EOF)') {
                        throw 'ALL PHP: Missing closing brace'
                    }
                    [void]$body.Add((Read-Statement))
                }
                Expect-Token '}'
                return [pscustomobject]@{ Kind='block'; Body=$body.ToArray() }
            }
            if ($token -ceq ';') {
                [void](Next-Token)
                return [pscustomobject]@{ Kind='block'; Body=@() }
            }
            if ($token -eq 'function') {
                return (Read-Function)
            }
            if ($token -eq 'class') {
                [void](Next-Token)
                $name = Next-Token
                if ($name -cnotmatch '^[A-Za-z_][A-Za-z_0-9]*$') {
                    throw 'ALL PHP: Expected class name'
                }
                Expect-Token '{'
                $methods = [System.Collections.Generic.List[object]]::new()
                $properties = [System.Collections.Generic.List[object]]::new()
                while ((Peek-Token) -cne '}') {
                    if ((Peek-Token) -ceq '(EOF)') { throw 'ALL PHP: Missing class closing brace' }
                    if ((Peek-Token) -in @('public','private','protected')) {
                        [void](Next-Token)
                    }
                    if ((Peek-Token) -eq 'function') {
                        [void]$methods.Add((Read-Function))
                    } elseif ((Peek-Token) -cmatch '^\$[A-Za-z_][A-Za-z_0-9]*$') {
                        $propName = (Next-Token).Substring(1)
                        $defaultExpr = $null
                        if ((Peek-Token) -ceq '=') {
                            [void](Next-Token)
                            $defaultExpr = Read-Expr 1
                        }
                        Expect-Token ';'
                        [void]$properties.Add([pscustomobject]@{
                            Name=$propName; Default=$defaultExpr
                        })
                    } else {
                        throw "ALL PHP: Unsupported class member '$(Peek-Token)'"
                    }
                }
                Expect-Token '}'
                return [pscustomobject]@{
                    Kind='classdef'; Name=$name
                    Methods=$methods.ToArray(); Properties=$properties.ToArray()
                }
            }
            if ($token -eq 'switch') {
                [void](Next-Token)
                Expect-Token '('
                $subject = Read-Expr 1
                Expect-Token ')'
                Expect-Token '{'
                $cases = [System.Collections.Generic.List[object]]::new()
                $defaultSeen = $false
                while ((Peek-Token) -cne '}') {
                    $label = Peek-Token
                    if ($label -ceq '(EOF)') { throw 'ALL PHP: Missing switch closing brace' }
                    if ($label -ne 'case' -and $label -ne 'default') {
                        throw "ALL PHP: Expected case or default, got '$label'"
                    }
                    [void](Next-Token)
                    $isDefault = ($label -eq 'default')
                    $test = $null
                    if ($isDefault) {
                        if ($defaultSeen) { throw 'ALL PHP: Duplicate switch default' }
                        $defaultSeen = $true
                    } else {
                        $test = Read-Expr 1
                    }
                    Expect-Token ':'
                    $body = [System.Collections.Generic.List[object]]::new()
                    while ((Peek-Token) -notin @('case','default','}', '(EOF)')) {
                        [void]$body.Add((Read-Statement))
                    }
                    [void]$cases.Add([pscustomobject]@{
                        IsDefault=$isDefault; Test=$test; Body=$body.ToArray()
                    })
                }
                Expect-Token '}'
                return [pscustomobject]@{
                    Kind='switch'; Subject=$subject; Cases=$cases.ToArray()
                }
            }
            if ($token -eq 'return') {
                [void](Next-Token)
                $expr = $null
                if ((Peek-Token) -cne ';') { $expr = Read-Expr 1 }
                Expect-Token ';'
                return [pscustomobject]@{ Kind='return'; Expr=$expr }
            }
            if ($token -eq 'if' -or $token -eq 'elseif') {
                [void](Next-Token)
                Expect-Token '('
                $condition = Read-Expr 1
                Expect-Token ')'
                $yes = Read-Statement
                $no = $null
                if ((Peek-Token) -eq 'elseif') {
                    $no = Read-Statement
                } elseif ((Peek-Token) -eq 'else') {
                    [void](Next-Token)
                    $no = Read-Statement
                }
                return [pscustomobject]@{
                    Kind='if'; Test=$condition; Yes=$yes; No=$no
                }
            }
            if ($token -eq 'break' -or $token -eq 'continue') {
                [void](Next-Token)
                Expect-Token ';'
                return [pscustomobject]@{ Kind='loopcontrol'; Action=$token }
            }
            if ($token -eq 'for') {
                [void](Next-Token)
                Expect-Token '('
                $init = Read-ForMutations ';'
                $condition = $null
                if ((Peek-Token) -cne ';') { $condition = Read-Expr 1 }
                Expect-Token ';'
                $update = Read-ForMutations ')'
                $body = Read-Statement
                return [pscustomobject]@{
                    Kind='for'; Init=@($init); Test=$condition; Update=@($update); Body=$body
                }
            }
            if ($token -eq 'do') {
                [void](Next-Token)
                $body = Read-Statement
                Expect-Token 'while'
                Expect-Token '('
                $condition = Read-Expr 1
                Expect-Token ')'
                Expect-Token ';'
                return [pscustomobject]@{ Kind='do'; Test=$condition; Body=$body }
            }
            if ($token -eq 'while') {
                [void](Next-Token)
                Expect-Token '('
                $condition = Read-Expr 1
                Expect-Token ')'
                $body = Read-Statement
                return [pscustomobject]@{
                    Kind='while'; Test=$condition; Body=$body
                }
            }
            if ($token -eq 'foreach') {
                [void](Next-Token)
                Expect-Token '('
                $iter = Read-Expr 1
                if ((Peek-Token) -ne 'as') { throw 'ALL PHP: Expected as in foreach' }
                [void](Next-Token)
                $first = Next-Token
                if ($first -cnotmatch '^\$[A-Za-z_][A-Za-z_0-9]*$') {
                    throw 'ALL PHP: Expected foreach variable'
                }
                $keyName = $null
                $valueName = $first.Substring(1)
                if ((Peek-Token) -ceq '=>') {
                    [void](Next-Token)
                    $keyName = $valueName
                    $second = Next-Token
                    if ($second -cnotmatch '^\$[A-Za-z_][A-Za-z_0-9]*$') {
                        throw 'ALL PHP: Expected foreach value variable'
                    }
                    $valueName = $second.Substring(1)
                }
                Expect-Token ')'
                $body = Read-Statement
                return [pscustomobject]@{
                    Kind='foreach'; Iter=$iter; KeyName=$keyName
                    ValueName=$valueName; Body=$body
                }
            }
            if ($token -eq 'echo') {
                [void](Next-Token)
                $callArgs = [System.Collections.Generic.List[object]]::new()
                [void]$callArgs.Add((Read-Expr 1))
                while ((Peek-Token) -ceq ',') {
                    [void](Next-Token)
                    [void]$callArgs.Add((Read-Expr 1))
                }
                Expect-Token ';'
                return [pscustomobject]@{ Kind='echo'; Args=$callArgs.ToArray() }
            }
            if ($token -eq 'print') {
                [void](Next-Token)
                $expr = Read-Expr 1
                Expect-Token ';'
                return [pscustomobject]@{ Kind='print'; Expr=$expr }
            }
            $expr = Read-Postfix
            if ((Peek-Token) -in @('=','+=','-=','.=','??=','*=','/=','%=','**=')) {
                if ($expr.Kind -notin @('variable','index','property')) {
                    throw 'ALL PHP: Invalid assignment target'
                }
                $op = Next-Token
                $value = Read-Expr 1
                Expect-Token ';'
                return [pscustomobject]@{
                    Kind='assign'; Target=$expr; Op=$op; Value=$value
                }
            }
            if ((Peek-Token) -in @('++','--')) {
                if ($expr.Kind -notin @('variable','index','property')) {
                    throw 'ALL PHP: Invalid increment target'
                }
                $op = Next-Token
                Expect-Token ';'
                return [pscustomobject]@{
                    Kind='assign'; Target=$expr
                    Op=$(if ($op -ceq '++') { '+=' } else { '-=' })
                    Value=[pscustomobject]@{ Kind='literal'; Value=[decimal]1 }
                }
            }
            if ($expr.Kind -in @('call','method')) {
                Expect-Token ';'
                return [pscustomobject]@{ Kind='exprstmt'; Expr=$expr }
            }
            throw "ALL PHP: Unsupported statement starting with '$token'"
        }
        function Read-Function {
            Expect-Token 'function'
            $name = Next-Token
            if ($name -cnotmatch '^[A-Za-z_][A-Za-z_0-9]*$') {
                throw 'ALL PHP: Expected function name'
            }
            Expect-Token '('
            $parameters = [System.Collections.Generic.List[string]]::new()
            if ((Peek-Token) -cne ')') {
                while ($true) {
                    $param = Next-Token
                    if ($param -cnotmatch '^\$[A-Za-z_][A-Za-z_0-9]*$') {
                        throw "ALL PHP: Expected parameter, got '$param'"
                    }
                    [void]$parameters.Add($param.Substring(1))
                    if ((Peek-Token) -cne ',') { break }
                    [void](Next-Token)
                }
            }
            Expect-Token ')'
            if ((Peek-Token) -cne '{') { throw 'ALL PHP: Function body must be a block' }
            $body = Read-Statement
            return [pscustomobject]@{
                Kind='functiondef'; Name=$name; Params=$parameters.ToArray(); Body=$body
            }
        }

        # Parse the entire program first, before emitting any output.
        $statements = [System.Collections.Generic.List[object]]::new()
        while ((Peek-Token) -cne '(EOF)') {
            [void]$statements.Add((Read-Statement))
        }

        function New-PhpArray {
            return [pscustomobject]@{
                PhpType='array'
                Items=[System.Collections.Specialized.OrderedDictionary]::new()
                NextIndex=[long]0
            }
        }
        function Is-PhpArray($value) {
            return ($null -ne $value -and $value.PSObject.Properties['PhpType'] -and
                $value.PhpType -ceq 'array')
        }
        function Is-PhpObject($value) {
            return ($null -ne $value -and $value.PSObject.Properties['PhpType'] -and
                $value.PhpType -ceq 'object')
        }
        function Copy-PhpValue($value, [int]$depth = 0) {
            if (-not (Is-PhpArray $value)) { return $value }
            if ($depth -ge 64) {
                throw 'ALL PHP: Array nesting exceeds supported copy depth (64)'
            }
            $copy = New-PhpArray
            # Clone directly to preserve insertion order and NextIndex. Do not
            # call Set-PhpArrayItem, which also copies incoming array values.
            foreach ($key in $value.Items.Keys) {
                $copy.Items[[string]$key] = Copy-PhpValue $value.Items[$key] ($depth + 1)
            }
            $copy.NextIndex = $value.NextIndex
            return $copy
        }
        function Encode-JsonQuoted([string]$value) {
            $sb = [System.Text.StringBuilder]::new()
            [void]$sb.Append('"')
            for ($i = 0; $i -lt $value.Length; $i++) {
                $ch = $value[$i]
                $code = [int]$ch
                $escape = $null
                switch ($code) {
                    34 { $escape = '\"' }
                    92 { $escape = '\\' }
                    47 { $escape = '\/' }
                    8  { $escape = '\b' }
                    9  { $escape = '\t' }
                    10 { $escape = '\n' }
                    12 { $escape = '\f' }
                    13 { $escape = '\r' }
                }
                if ($null -ne $escape) {
                    [void]$sb.Append($escape)
                    continue
                }
                if ($code -lt 32 -or $code -gt 126) {
                    [void]$sb.Append(('\u{0:x4}' -f $code))
                } else {
                    [void]$sb.Append($ch)
                }
            }
            [void]$sb.Append('"')
            return $sb.ToString()
        }
        function Encode-PhpJson($value, [int]$depth = 0) {
            if ($depth -ge 64) { throw 'ALL PHP: JSON nesting depth exceeded (64)' }
            if ($null -eq $value) { return 'null' }
            if ($value -is [bool]) {
                if ($value) { return 'true' }
                return 'false'
            }
            if ($value -is [decimal]) { return (To-PhpText $value) }
            if ($value -is [string]) { return (Encode-JsonQuoted $value) }
            if (Is-PhpArray $value) {
                $index = [long]0
                $isList = $true
                foreach ($key in $value.Items.Keys) {
                    if ([string]$key -cne "i:$index") { $isList = $false; break }
                    $index++
                }
                $parts = [System.Collections.Generic.List[string]]::new()
                foreach ($key in $value.Items.Keys) {
                    $encoded = Encode-PhpJson $value.Items[$key] ($depth + 1)
                    if ($isList) {
                        [void]$parts.Add($encoded)
                    } else {
                        $name = if (([string]$key).StartsWith('i:')) {
                            ([string]$key).Substring(2)
                        } else { ([string]$key).Substring(2) }
                        [void]$parts.Add((Encode-JsonQuoted $name) + ':' + $encoded)
                    }
                }
                if ($isList) { return ('[' + [string]::Join(',', $parts.ToArray()) + ']') }
                return ('{' + [string]::Join(',', $parts.ToArray()) + '}')
            }
            if (Is-PhpObject $value) {
                $parts = [System.Collections.Generic.List[string]]::new()
                foreach ($key in $value.Props.Keys) {
                    $encoded = Encode-PhpJson $value.Props[$key] ($depth + 1)
                    [void]$parts.Add((Encode-JsonQuoted ([string]$key)) + ':' + $encoded)
                }
                return ('{' + [string]::Join(',', $parts.ToArray()) + '}')
            }
            throw 'ALL PHP: Unsupported JSON value type'
        }
        function New-PhpStdObject {
            return [pscustomobject]@{
                PhpType='object'; Class='stdClass'
                Props=[System.Collections.Specialized.OrderedDictionary]::new(
                    [System.StringComparer]::Ordinal)
            }
        }
        function Convert-JsonToPhp($value, [bool]$assoc, [int]$depth = 0) {
            if ($depth -ge 64) { throw 'ALL PHP: JSON nesting depth exceeded (64)' }
            if ($null -eq $value) { return $null }
            if ($value -is [bool] -or $value -is [string]) { return $value }
            if ($value -is [System.ValueType]) {
                $text = [string]::Format(
                    [System.Globalization.CultureInfo]::InvariantCulture, '{0}', $value)
                $parsed = [decimal]0
                if (-not [decimal]::TryParse($text,
                    [System.Globalization.NumberStyles]::Float,
                    [System.Globalization.CultureInfo]::InvariantCulture,
                    [ref]$parsed)) {
                    throw 'ALL PHP: JSON number outside supported decimal range'
                }
                return $parsed
            }
            if ($value -is [array] -or $value -is [System.Collections.ArrayList]) {
                $array = New-PhpArray
                foreach ($item in $value) {
                    Set-PhpArrayItem $array $null (Convert-JsonToPhp $item $assoc ($depth + 1)) $true
                }
                return $array
            }
            if ($value -is [pscustomobject] -or $value -is [System.Collections.IDictionary]) {
                if ($assoc) { $result = New-PhpArray }
                else { $result = New-PhpStdObject }
                if ($value -is [System.Collections.IDictionary]) {
                    foreach ($key in $value.Keys) {
                        $converted = Convert-JsonToPhp $value[$key] $assoc ($depth + 1)
                        if ($assoc) { Set-PhpArrayItem $result ([string]$key) $converted $false }
                        else { $result.Props[[string]$key] = Copy-PhpValue $converted }
                    }
                } else {
                    foreach ($pair in $value.PSObject.Properties) {
                        if ($pair.MemberType -ne 'NoteProperty') { continue }
                        $converted = Convert-JsonToPhp $pair.Value $assoc ($depth + 1)
                        if ($assoc) { Set-PhpArrayItem $result ([string]$pair.Name) $converted $false }
                        else { $result.Props[[string]$pair.Name] = Copy-PhpValue $converted }
                    }
                }
                return $result
            }
            throw 'ALL PHP: Unsupported decoded JSON type'
        }
        function To-PhpText($value) {
            if ($null -eq $value) { return '' }
            if ($value -is [bool]) {
                if ($value) { return '1' }
                return ''
            }
            if ($value -is [decimal]) {
                return $value.ToString('0.############################',
                    [System.Globalization.CultureInfo]::InvariantCulture)
            }
            if (Is-PhpArray $value) { throw 'ALL PHP: Array to string conversion is not supported' }
            if (Is-PhpObject $value) { throw 'ALL PHP: Object to string conversion is not supported' }
            return [string]$value
        }
        function To-Number($value) {
            if ($value -is [decimal]) { return $value }
            if ($null -eq $value) { return [decimal]0 }
            if ($value -is [bool]) {
                if ($value) { return [decimal]1 }
                return [decimal]0
            }
            if ($value -is [string] -and
                $value -match '^\s*[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?\s*$') {
                $num = [decimal]0
                if ([decimal]::TryParse($value,
                    [System.Globalization.NumberStyles]::Float,
                    [System.Globalization.CultureInfo]::InvariantCulture,
                    [ref]$num)) { return $num }
            }
            throw 'ALL PHP: Unsupported numeric operand'
        }
        function Is-Truthy($value) {
            if ($null -eq $value) { return $false }
            if ($value -is [bool]) { return $value }
            if ($value -is [decimal]) { return ($value -ne 0) }
            if ($value -is [string]) {
                return ($value.Length -gt 0 -and $value -cne '0')
            }
            if (Is-PhpArray $value) { return ($value.Items.Count -gt 0) }
            return $true
        }
        function To-PhpKey($value) {
            if ($value -is [bool]) {
                if ($value) { return 'i:1' }
                return 'i:0'
            }
            if ($null -eq $value) { return 's:' }
            if ($value -is [decimal]) {
                $num = [long][decimal]::Truncate($value)
                return "i:$num"
            }
            if ($value -is [string]) {
                if ($value -cmatch '^(?:0|-?[1-9][0-9]*)$') {
                    $num = [long]0
                    if ([long]::TryParse($value, [ref]$num)) { return "i:$num" }
                }
                return ('s:' + $value)
            }
            throw 'ALL PHP: Unsupported array key type'
        }
        function Set-PhpArrayItem($array, $key, $value, [bool]$append) {
            if (-not (Is-PhpArray $array)) { throw 'ALL PHP: Index assignment requires array' }
            if ($append) {
                $keyString = "i:$($array.NextIndex)"
                $array.NextIndex++
            } else {
                $keyString = To-PhpKey $key
                if ($keyString.StartsWith('i:')) {
                    $intKey = [long]$keyString.Substring(2)
                    if ($intKey -ge $array.NextIndex) { $array.NextIndex = $intKey + 1 }
                }
            }
            $array.Items[$keyString] = Copy-PhpValue $value
        }
        function Get-PhpArrayItem($array, $key) {
            if (-not (Is-PhpArray $array)) { throw 'ALL PHP: Indexing requires array' }
            $keyString = To-PhpKey $key
            if (-not $array.Items.Contains($keyString)) {
                throw "ALL PHP: Undefined array key '$keyString'"
            }
            return $array.Items[$keyString]
        }
        function Compare-Values($a, $b) {
            if ($null -eq $a -and $null -eq $b) { return 0 }
            if ($a -is [bool] -or $b -is [bool] -or
                $null -eq $a -or $null -eq $b) {
                $av = [int][bool](Is-Truthy $a)
                $bv = [int][bool](Is-Truthy $b)
                return $av.CompareTo($bv)
            }
            if ($a -is [decimal] -and $b -is [decimal]) {
                return [decimal]::Compare($a, $b)
            }
            if ($a -is [string] -and $b -is [string]) {
                if ($a -match '^\s*[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?\s*$' -and
                    $b -match '^\s*[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?\s*$') {
                    return [decimal]::Compare((To-Number $a),(To-Number $b))
                }
                return [string]::CompareOrdinal($a, $b)
            }
            if (($a -is [decimal] -and $b -is [string]) -or
                ($a -is [string] -and $b -is [decimal])) {
                $text = if ($a -is [string]) { $a } else { $b }
                if ($text -match '^\s*[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?\s*$') {
                    return [decimal]::Compare((To-Number $a),(To-Number $b))
                }
                return [string]::CompareOrdinal((To-PhpText $a),(To-PhpText $b))
            }
            throw 'ALL PHP: Comparison for these types is not supported'
        }
        function Is-StrictEqual($a, $b) {
            if ($null -eq $a -or $null -eq $b) { return ($null -eq $a -and $null -eq $b) }
            if ($a.GetType() -ne $b.GetType()) { return $false }
            if ($a -is [decimal]) { return ($a -eq $b) }
            if ($a -is [string]) { return ($a -ceq $b) }
            if ($a -is [bool]) { return ($a -eq $b) }
            if ((Is-PhpArray $a) -or (Is-PhpObject $a)) {
                throw 'ALL PHP: Strict collection comparisons are not implemented'
            }
            return $false
        }
        function Get-LValue($node) {
            if ($node.Kind -eq 'variable') {
                if (-not $state.Vars.ContainsKey($node.Name)) {
                    throw "ALL PHP: Undefined variable '$($node.Name)'"
                }
                return $state.Vars[$node.Name]
            }
            if ($node.Kind -eq 'index') {
                if ($null -eq $node.Key) { throw 'ALL PHP: Cannot read an empty [] index' }
                return (Get-PhpArrayItem (Invoke-PhpExpr $node.Base) (Invoke-PhpExpr $node.Key))
            }
            if ($node.Kind -eq 'property') {
                $base = Invoke-PhpExpr $node.Base
                if ($node.NullSafe -and $null -eq $base) { return $null }
                if (-not (Is-PhpObject $base)) { throw 'ALL PHP: Property access requires object' }
                $present = if ($base.Props -is [System.Collections.Specialized.OrderedDictionary]) {
                    $base.Props.Contains($node.Name)
                } else { $base.Props.ContainsKey($node.Name) }
                if (-not $present) {
                    throw "ALL PHP: Undefined property '$($node.Name)'"
                }
                return $base.Props[$node.Name]
            }
            throw 'ALL PHP: Not a readable value'
        }
        function Set-LValue($node, $value, [string]$op) {
            if ($node.Kind -eq 'property' -and $node.NullSafe) {
                throw 'ALL PHP: Cannot use nullsafe access as assignment target'
            }
            if ($op -cne '=') {
                $previous = Get-LValue $node
                switch ($op) {
                    '+=' { $value = (To-Number $previous) + (To-Number $value) }
                    '-=' { $value = (To-Number $previous) - (To-Number $value) }
                    '.=' { $value = (To-PhpText $previous) + (To-PhpText $value) }
                    '*=' { $value = (To-Number $previous) * (To-Number $value) }
                    '/=' {
                        if ((To-Number $value) -eq 0) { throw 'ALL PHP: Division by zero' }
                        $value = (To-Number $previous) / (To-Number $value)
                    }
                    '%=' {
                        $divisor = [long][decimal]::Truncate((To-Number $value))
                        if ($divisor -eq 0) { throw 'ALL PHP: Division by zero' }
                        $dividend = [long][decimal]::Truncate((To-Number $previous))
                        $value = [decimal]($dividend % $divisor)
                    }
                    '**=' {
                        $power = [Math]::Pow([double](To-Number $previous),
                                             [double](To-Number $value))
                        if ([double]::IsNaN($power) -or [double]::IsInfinity($power)) {
                            throw 'ALL PHP: Power result outside supported numeric range'
                        }
                        try { $value = [decimal]$power }
                        catch { throw 'ALL PHP: Power result outside supported numeric range' }
                    }
                }
            }
            if ($node.Kind -eq 'variable') {
                $state.Vars[$node.Name] = Copy-PhpValue $value
                return
            }
            if ($node.Kind -eq 'index') {
                if ($node.Base.Kind -eq 'variable' -and
                    -not $state.Vars.ContainsKey($node.Base.Name)) {
                    $state.Vars[$node.Base.Name] = New-PhpArray
                }
                $base = Invoke-PhpExpr $node.Base
                $append = ($null -eq $node.Key)
                $key = $null
                if (-not $append) { $key = Invoke-PhpExpr $node.Key }
                Set-PhpArrayItem $base $key $value $append
                return
            }
            if ($node.Kind -eq 'property') {
                $base = Invoke-PhpExpr $node.Base
                if (-not (Is-PhpObject $base)) { throw 'ALL PHP: Property assignment requires object' }
                $base.Props[$node.Name] = Copy-PhpValue $value
                return
            }
            throw 'ALL PHP: Invalid assignment target'
        }
        function Invoke-PhpCallable($definition, $callArgs, $object) {
            if ($state.CallDepth -ge 64) { throw 'ALL PHP: Call depth limit reached (64)' }
            if ($callArgs.Count -lt $definition.Params.Count) {
                throw "ALL PHP: Too few arguments for $($definition.Name)"
            }
            $oldVars = $state.Vars
            $oldFlow = $state.Flow
            $state.Vars = [System.Collections.Generic.Dictionary[string,object]]::new(
                [System.StringComparer]::Ordinal)
            $state.Flow = @{ Returned=$false; Value=$null; LoopControl=$null; LoopDepth=0 }
            $state.CallDepth++
            try {
                for ($i=0; $i -lt $definition.Params.Count; $i++) {
                    $state.Vars[$definition.Params[$i]] = Copy-PhpValue $callArgs[$i]
                }
                if ($null -ne $object) { $state.Vars['this'] = $object }
                Invoke-PhpStatement $definition.Body
                return $state.Flow.Value
            } finally {
                $state.CallDepth--
                $state.Vars = $oldVars
                $state.Flow = $oldFlow
            }
        }
        function KeyString-ToValue([string]$encoded) {
            if ($encoded.StartsWith('i:')) { return [decimal]$encoded.Substring(2) }
            return $encoded.Substring(2)
        }
        function Invoke-PhpFunction([string]$name, $callArgs) {
            switch ($name.ToLowerInvariant()) {
                'json_encode' {
                    if ($callArgs.Count -ne 1) {
                        throw 'ALL PHP: json_encode() supports one argument; options are not implemented'
                    }
                    $encoded = Encode-PhpJson $callArgs[0]
                    $state.JsonError = 0
                    $state.JsonErrorMessage = 'No error'
                    return $encoded
                }
                'json_decode' {
                    if ($callArgs.Count -lt 1 -or $callArgs.Count -gt 2) {
                        throw 'ALL PHP: json_decode() supports one or two arguments'
                    }
                    $json = To-PhpText $callArgs[0]
                    $assoc = $false
                    if ($callArgs.Count -eq 2) { $assoc = Is-Truthy $callArgs[1] }
                    try {
                        # Windows PowerShell 5.1 emits a JSON array as one
                        # array object. Wrapping the cmdlet in @() would introduce
                        # a false extra nesting level on that runtime.
                        $parsed = ConvertFrom-Json -InputObject $json -ErrorAction Stop
                        # PowerShell 7 may instead unwrap a singleton/empty array.
                        # Reconstruct only when the JSON root really was an array.
                        if ($json.TrimStart().StartsWith('[') -and
                            $parsed -isnot [System.Collections.IList]) {
                            if ($null -eq $parsed) { $parsed = @() }
                            else { $parsed = ,$parsed }
                        }
                        $output = Convert-JsonToPhp $parsed $assoc
                        $state.JsonError = 0
                        $state.JsonErrorMessage = 'No error'
                        return $output
                    } catch {
                        # Invalid JSON is not an interpreter error in PHP without THROW_ON_ERROR.
                        $state.JsonError = 4
                        $state.JsonErrorMessage = 'Syntax error'
                        return $null
                    }
                }
                'json_last_error' {
                    if ($callArgs.Count -ne 0) { throw 'ALL PHP: json_last_error() expects no arguments' }
                    return [decimal]$state.JsonError
                }
                'json_last_error_msg' {
                    if ($callArgs.Count -ne 0) { throw 'ALL PHP: json_last_error_msg() expects no arguments' }
                    return $state.JsonErrorMessage
                }
                'count' {
                    if ($callArgs.Count -ne 1 -or -not (Is-PhpArray $callArgs[0])) {
                        throw 'ALL PHP: count() requires one array argument'
                    }
                    return [decimal]$callArgs[0].Items.Count
                }
                'strlen' {
                    if ($callArgs.Count -ne 1) { throw 'ALL PHP: strlen() requires one argument' }
                    return [decimal]([System.Text.Encoding]::UTF8.GetByteCount((To-PhpText $callArgs[0])))
                }
                'strtoupper' {
                    if ($callArgs.Count -ne 1) { throw 'ALL PHP: strtoupper() requires one argument' }
                    return (To-PhpText $callArgs[0]).ToUpperInvariant()
                }
                'strtolower' {
                    if ($callArgs.Count -ne 1) { throw 'ALL PHP: strtolower() requires one argument' }
                    return (To-PhpText $callArgs[0]).ToLowerInvariant()
                }
                'trim' {
                    if ($callArgs.Count -ne 1) { throw 'ALL PHP: trim() supports one argument' }
                    return (To-PhpText $callArgs[0]).Trim(@([char]32,[char]9,[char]10,[char]13,[char]0,[char]11))
                }
                'abs' {
                    if ($callArgs.Count -ne 1) { throw 'ALL PHP: abs() requires one argument' }
                    return [Math]::Abs([decimal](To-Number $callArgs[0]))
                }
                'array_sum' {
                    if ($callArgs.Count -ne 1 -or -not (Is-PhpArray $callArgs[0])) {
                        throw 'ALL PHP: array_sum() requires one array argument'
                    }
                    $sum = [decimal]0
                    foreach ($key in $callArgs[0].Items.Keys) {
                        $sum += (To-Number $callArgs[0].Items[$key])
                    }
                    return $sum
                }
                'array_key_exists' {
                    if ($callArgs.Count -ne 2 -or -not (Is-PhpArray $callArgs[1])) {
                        throw 'ALL PHP: array_key_exists() requires key and array'
                    }
                    $key = To-PhpKey $callArgs[0]
                    return $callArgs[1].Items.Contains($key)
                }
                'is_array' {
                    if ($callArgs.Count -ne 1) { throw 'ALL PHP: is_array() requires one argument' }
                    return (Is-PhpArray $callArgs[0])
                }
                'is_string' {
                    if ($callArgs.Count -ne 1) { throw 'ALL PHP: is_string() requires one argument' }
                    return ($callArgs[0] -is [string])
                }
                'is_bool' {
                    if ($callArgs.Count -ne 1) { throw 'ALL PHP: is_bool() requires one argument' }
                    return ($callArgs[0] -is [bool])
                }
                'array_push' {
                    if ($callArgs.Count -lt 1 -or -not (Is-PhpArray $callArgs[0])) {
                        throw 'ALL PHP: array_push() expects an array'
                    }
                    for ($i=1; $i -lt $callArgs.Count; $i++) {
                        Set-PhpArrayItem $callArgs[0] $null $callArgs[$i] $true
                    }
                    return [decimal]$callArgs[0].Items.Count
                }
                'array_pop' {
                    if ($callArgs.Count -ne 1 -or -not (Is-PhpArray $callArgs[0])) {
                        throw 'ALL PHP: array_pop() expects one array'
                    }
                    $arr = $callArgs[0]
                    if ($arr.Items.Count -eq 0) { return $null }
                    $keys = @($arr.Items.Keys)
                    $lastKey = [string]$keys[$arr.Items.Count - 1]
                    $lastValue = $arr.Items[$lastKey]
                    $arr.Items.Remove($lastKey)
                    # PHP resets the next free index after array_pop().
                    $high = [long]-1
                    foreach ($k in $arr.Items.Keys) {
                        if ($k.StartsWith('i:')) {
                            $number = [long]$k.Substring(2)
                            if ($number -gt $high) { $high = $number }
                        }
                    }
                    $arr.NextIndex = $high + 1
                    return $lastValue
                }
                'array_shift' {
                    if ($callArgs.Count -ne 1 -or -not (Is-PhpArray $callArgs[0])) {
                        throw 'ALL PHP: array_shift() expects one array'
                    }
                    $arr = $callArgs[0]
                    if ($arr.Items.Count -eq 0) { return $null }
                    $keys = @($arr.Items.Keys)
                    $firstKey = [string]$keys[0]
                    $firstValue = $arr.Items[$firstKey]
                    $arr.Items.Remove($firstKey)
                    $replacement = New-PhpArray
                    foreach ($k in $arr.Items.Keys) {
                        $v = $arr.Items[$k]
                        if ($k.StartsWith('i:')) {
                            Set-PhpArrayItem $replacement $null $v $true
                        } else {
                            Set-PhpArrayItem $replacement (KeyString-ToValue ([string]$k)) $v $false
                        }
                    }
                    $arr.Items = $replacement.Items
                    $arr.NextIndex = $replacement.NextIndex
                    return $firstValue
                }
                'array_unshift' {
                    if ($callArgs.Count -lt 1 -or -not (Is-PhpArray $callArgs[0])) {
                        throw 'ALL PHP: array_unshift() expects an array'
                    }
                    $arr = $callArgs[0]
                    $replacement = New-PhpArray
                    for ($i=1; $i -lt $callArgs.Count; $i++) {
                        Set-PhpArrayItem $replacement $null $callArgs[$i] $true
                    }
                    foreach ($k in $arr.Items.Keys) {
                        $v = $arr.Items[$k]
                        if ($k.StartsWith('i:')) {
                            Set-PhpArrayItem $replacement $null $v $true
                        } else {
                            Set-PhpArrayItem $replacement (KeyString-ToValue ([string]$k)) $v $false
                        }
                    }
                    $arr.Items = $replacement.Items
                    $arr.NextIndex = $replacement.NextIndex
                    return [decimal]$arr.Items.Count
                }
                'array_reverse' {
                    if ($callArgs.Count -lt 1 -or $callArgs.Count -gt 2 -or
                        -not (Is-PhpArray $callArgs[0])) {
                        throw 'ALL PHP: array_reverse() expects array and optional bool'
                    }
                    $preserve = $false
                    if ($callArgs.Count -eq 2) { $preserve = Is-Truthy $callArgs[1] }
                    $out = New-PhpArray
                    $keys = @($callArgs[0].Items.Keys)
                    for ($i=$keys.Count - 1; $i -ge 0; $i--) {
                        $k = [string]$keys[$i]
                        $v = $callArgs[0].Items[$k]
                        if (-not $preserve -and $k.StartsWith('i:')) {
                            Set-PhpArrayItem $out $null $v $true
                        } else {
                            Set-PhpArrayItem $out (KeyString-ToValue $k) $v $false
                        }
                    }
                    return $out
                }
                'array_merge' {
                    $out = New-PhpArray
                    foreach ($arr in $callArgs) {
                        if (-not (Is-PhpArray $arr)) {
                            throw 'ALL PHP: array_merge() requires arrays'
                        }
                        foreach ($k in $arr.Items.Keys) {
                            $v = $arr.Items[$k]
                            if ($k.StartsWith('i:')) {
                                Set-PhpArrayItem $out $null $v $true
                            } else {
                                Set-PhpArrayItem $out (KeyString-ToValue ([string]$k)) $v $false
                            }
                        }
                    }
                    return $out
                }
                'array_slice' {
                    if ($callArgs.Count -lt 2 -or $callArgs.Count -gt 4 -or
                        -not (Is-PhpArray $callArgs[0])) {
                        throw 'ALL PHP: array_slice() expects array, offset, optional length/bool'
                    }
                    $arr = $callArgs[0]
                    $count = $arr.Items.Count
                    $start = [int](To-Number $callArgs[1])
                    if ($start -lt 0) { $start = [Math]::Max(0, $count + $start) }
                    if ($start -gt $count) { $start = $count }
                    $end = $count
                    if ($callArgs.Count -ge 3 -and $null -ne $callArgs[2]) {
                        $len = [int](To-Number $callArgs[2])
                        if ($len -ge 0) { $end = [Math]::Min($end, $start + $len) }
                        else { $end = [Math]::Max($start, $count + $len) }
                    }
                    $preserve = $false
                    if ($callArgs.Count -eq 4) { $preserve = Is-Truthy $callArgs[3] }
                    $out = New-PhpArray
                    $keys = @($arr.Items.Keys)
                    for ($i=$start; $i -lt $end; $i++) {
                        $k = [string]$keys[$i]
                        $v = $arr.Items[$k]
                        if ($k.StartsWith('i:') -and -not $preserve) {
                            Set-PhpArrayItem $out $null $v $true
                        } else {
                            Set-PhpArrayItem $out (KeyString-ToValue $k) $v $false
                        }
                    }
                    return $out
                }
                'array_keys' {
                    if ($callArgs.Count -ne 1 -or -not (Is-PhpArray $callArgs[0])) {
                        throw 'ALL PHP: array_keys() requires one array argument'
                    }
                    $output = New-PhpArray
                    foreach ($key in $callArgs[0].Items.Keys) {
                        Set-PhpArrayItem $output $null (KeyString-ToValue ([string]$key)) $true
                    }
                    return $output
                }
                'array_values' {
                    if ($callArgs.Count -ne 1 -or -not (Is-PhpArray $callArgs[0])) {
                        throw 'ALL PHP: array_values() requires one array argument'
                    }
                    $output = New-PhpArray
                    foreach ($key in $callArgs[0].Items.Keys) {
                        Set-PhpArrayItem $output $null $callArgs[0].Items[$key] $true
                    }
                    return $output
                }
                'array_key_first' {
                    if ($callArgs.Count -ne 1 -or -not (Is-PhpArray $callArgs[0])) {
                        throw 'ALL PHP: array_key_first() requires one array argument'
                    }
                    foreach ($key in $callArgs[0].Items.Keys) {
                        return (KeyString-ToValue ([string]$key))
                    }
                    return $null
                }
                'array_key_last' {
                    if ($callArgs.Count -ne 1 -or -not (Is-PhpArray $callArgs[0])) {
                        throw 'ALL PHP: array_key_last() requires one array argument'
                    }
                    $last = $null
                    foreach ($key in $callArgs[0].Items.Keys) { $last = [string]$key }
                    if ($null -ne $last) { return (KeyString-ToValue $last) }
                    return $null
                }
                'array_first' {
                    # PHP 8.5: returns the first value, or null for an empty array.
                    if ($callArgs.Count -ne 1 -or -not (Is-PhpArray $callArgs[0])) {
                        throw 'ALL PHP: array_first() requires one array argument'
                    }
                    foreach ($key in $callArgs[0].Items.Keys) {
                        return $callArgs[0].Items[$key]
                    }
                    return $null
                }
                'array_last' {
                    # PHP 8.5: returns the last value, or null for an empty array.
                    if ($callArgs.Count -ne 1 -or -not (Is-PhpArray $callArgs[0])) {
                        throw 'ALL PHP: array_last() requires one array argument'
                    }
                    $last = $null
                    foreach ($key in $callArgs[0].Items.Keys) { $last = $callArgs[0].Items[$key] }
                    return $last
                }
                'in_array' {
                    if ($callArgs.Count -lt 2 -or $callArgs.Count -gt 3 -or
                        -not (Is-PhpArray $callArgs[1])) {
                        throw 'ALL PHP: in_array() requires value and array'
                    }
                    $strict = $false
                    if ($callArgs.Count -eq 3) { $strict = Is-Truthy $callArgs[2] }
                    foreach ($key in $callArgs[1].Items.Keys) {
                        $entry = $callArgs[1].Items[$key]
                        if ($strict) {
                            if (Is-StrictEqual $callArgs[0] $entry) { return $true }
                        } else {
                            if ((Compare-Values $callArgs[0] $entry) -eq 0) { return $true }
                        }
                    }
                    return $false
                }
                'str_contains' {
                    if ($callArgs.Count -ne 2) { throw 'ALL PHP: str_contains() requires two arguments' }
                    $haystack = To-PhpText $callArgs[0]
                    $needle = To-PhpText $callArgs[1]
                    return ($haystack.IndexOf($needle, [StringComparison]::Ordinal) -ge 0)
                }
                'str_starts_with' {
                    if ($callArgs.Count -ne 2) { throw 'ALL PHP: str_starts_with() requires two arguments' }
                    return (To-PhpText $callArgs[0]).StartsWith(
                        (To-PhpText $callArgs[1]), [StringComparison]::Ordinal)
                }
                'str_ends_with' {
                    if ($callArgs.Count -ne 2) { throw 'ALL PHP: str_ends_with() requires two arguments' }
                    return (To-PhpText $callArgs[0]).EndsWith(
                        (To-PhpText $callArgs[1]), [StringComparison]::Ordinal)
                }
                'strpos' {
                    if ($callArgs.Count -lt 2 -or $callArgs.Count -gt 3) {
                        throw 'ALL PHP: strpos() requires two or three arguments'
                    }
                    $haystack = To-PhpText $callArgs[0]
                    $needle = To-PhpText $callArgs[1]
                    $offset = 0
                    if ($callArgs.Count -eq 3) { $offset = [int](To-Number $callArgs[2]) }
                    if ($offset -lt 0) { $offset = [Math]::Max(0, $haystack.Length + $offset) }
                    if ($offset -gt $haystack.Length) { throw 'ALL PHP: strpos offset is out of range' }
                    $pos = $haystack.IndexOf($needle, $offset, [StringComparison]::Ordinal)
                    if ($pos -lt 0) { return $false }
                    return [decimal]$pos
                }
                'substr' {
                    if ($callArgs.Count -lt 2 -or $callArgs.Count -gt 3) {
                        throw 'ALL PHP: substr() requires two or three arguments'
                    }
                    $s = To-PhpText $callArgs[0]
                    $start = [int](To-Number $callArgs[1])
                    if ($start -lt 0) { $start = [Math]::Max(0, $s.Length + $start) }
                    if ($start -gt $s.Length) { $start = $s.Length }
                    $end = $s.Length
                    if ($callArgs.Count -eq 3 -and $null -ne $callArgs[2]) {
                        $size = [int](To-Number $callArgs[2])
                        if ($size -ge 0) { $end = [Math]::Min($end, $start + $size) }
                        else { $end = [Math]::Max($start, $end + $size) }
                    }
                    return $s.Substring($start, [Math]::Max(0, $end - $start))
                }
                'str_replace' {
                    if ($callArgs.Count -ne 3) { throw 'ALL PHP: str_replace() supports three scalar arguments' }
                    $needle = To-PhpText $callArgs[0]
                    $replacement = To-PhpText $callArgs[1]
                    $subject = To-PhpText $callArgs[2]
                    return $subject.Replace($needle, $replacement)
                }
                'explode' {
                    if ($callArgs.Count -ne 2) { throw 'ALL PHP: explode() supports two arguments' }
                    $separator = To-PhpText $callArgs[0]
                    if ($separator.Length -eq 0) { throw 'ALL PHP: explode separator cannot be empty' }
                    $subject = To-PhpText $callArgs[1]
                    $parts = $subject.Split([string[]]@($separator), [StringSplitOptions]::None)
                    $out = New-PhpArray
                    foreach ($part in $parts) { Set-PhpArrayItem $out $null $part $true }
                    return $out
                }
                'implode' {
                    if ($callArgs.Count -ne 2 -or -not (Is-PhpArray $callArgs[1])) {
                        throw 'ALL PHP: implode() requires separator and array'
                    }
                    $separator = To-PhpText $callArgs[0]
                    $items = [System.Collections.Generic.List[string]]::new()
                    foreach ($key in $callArgs[1].Items.Keys) {
                        [void]$items.Add((To-PhpText $callArgs[1].Items[$key]))
                    }
                    return [string]::Join($separator, $items.ToArray())
                }
                'strval' {
                    if ($callArgs.Count -ne 1) { throw 'ALL PHP: strval() requires one argument' }
                    return (To-PhpText $callArgs[0])
                }
            }
            if (-not $state.Functions.ContainsKey($name)) {
                throw "ALL PHP: Undefined function '$name'"
            }
            return (Invoke-PhpCallable $state.Functions[$name] $callArgs $null)
        }
        function Invoke-PhpMethod($object, [string]$name, $callArgs) {
            if (-not (Is-PhpObject $object)) { throw 'ALL PHP: Method call requires object' }
            $definition = $state.Classes[$object.Class]
            if (-not $definition.Methods.ContainsKey($name)) {
                throw "ALL PHP: Undefined method '$name'"
            }
            return (Invoke-PhpCallable $definition.Methods[$name] $callArgs $object)
        }
        function Invoke-PhpExpr($node) {
            switch ($node.Kind) {
                'literal' { return $node.Value }
                'assign_expr' {
                    if ($node.Op -ceq '??=') {
                        $current = $null
                        try { $current = Get-LValue $node.Target }
                        catch {
                            if ($_.Exception.Message -notlike 'ALL PHP: Undefined *') { throw }
                        }
                        if ($null -ne $current) { return $current }
                    }
                    $replacement = Invoke-PhpExpr $node.Value
                    $writeOp = if ($node.Op -ceq '??=') { '=' } else { $node.Op }
                    Set-LValue $node.Target $replacement $writeOp
                    if ($node.Target.Kind -eq 'index' -and $null -eq $node.Target.Key) {
                        return $replacement
                    }
                    return (Get-LValue $node.Target)
                }
                'double_string' { return (Expand-PhpDoubleString $node.Raw) }
                'variable' { return (Get-LValue $node) }
                'index' { return (Get-LValue $node) }
                'property' { return (Get-LValue $node) }
                'array' {
                    $array = New-PhpArray
                    foreach ($entry in $node.Entries) {
                        $value = Invoke-PhpExpr $entry.Value
                        if ($null -eq $entry.Key) {
                            Set-PhpArrayItem $array $null $value $true
                        } else {
                            $key = Invoke-PhpExpr $entry.Key
                            Set-PhpArrayItem $array $key $value $false
                        }
                    }
                    return $array
                }
                'call' {
                    if ($node.Name -ceq 'isset' -or $node.Name -ceq 'empty') {
                        if ($node.Name -ceq 'isset' -and $node.Args.Count -lt 1) {
                            throw 'ALL PHP: isset() requires an argument'
                        }
                        if ($node.Name -ceq 'empty' -and $node.Args.Count -ne 1) {
                            throw 'ALL PHP: empty() expects one argument'
                        }
                        foreach ($arg in $node.Args) {
                            $found = $true
                            $value = $null
                            try {
                                $value = Invoke-PhpExpr $arg
                            } catch {
                                if ($_.Exception.Message -like 'ALL PHP: Undefined *') {
                                    $found = $false
                                } else { throw }
                            }
                            $isset = ($found -and $null -ne $value)
                            if ($node.Name -ceq 'isset' -and -not $isset) { return $false }
                            if ($node.Name -ceq 'empty') { return (-not $found -or -not (Is-Truthy $value)) }
                        }
                        return $true
                    }
                    if ($node.Name -ceq 'unset') {
                        foreach ($arg in $node.Args) {
                            if ($arg.Kind -eq 'variable') {
                                [void]$state.Vars.Remove($arg.Name)
                            } elseif ($arg.Kind -eq 'index') {
                                $array = Invoke-PhpExpr $arg.Base
                                if (-not (Is-PhpArray $array)) { throw 'ALL PHP: unset index requires array' }
                                if ($null -eq $arg.Key) { throw 'ALL PHP: unset requires array key' }
                                $key = To-PhpKey (Invoke-PhpExpr $arg.Key)
                                if ($array.Items.Contains($key)) { $array.Items.Remove($key) }
                            } elseif ($arg.Kind -eq 'property') {
                                $object = Invoke-PhpExpr $arg.Base
                                if (-not (Is-PhpObject $object)) { throw 'ALL PHP: unset property requires object' }
                                [void]$object.Props.Remove($arg.Name)
                            } else { throw 'ALL PHP: unset() requires variable or element' }
                        }
                        return $null
                    }
                    $callArgs = [System.Collections.Generic.List[object]]::new()
                    foreach ($arg in $node.Args) { [void]$callArgs.Add((Invoke-PhpExpr $arg)) }
                    return (Invoke-PhpFunction $node.Name ($callArgs.ToArray()))
                }
                'method' {
                    $base = Invoke-PhpExpr $node.Base
                    if ($node.NullSafe -and $null -eq $base) { return $null }
                    $callArgs = [System.Collections.Generic.List[object]]::new()
                    foreach ($arg in $node.Args) { [void]$callArgs.Add((Invoke-PhpExpr $arg)) }
                    return (Invoke-PhpMethod $base $node.Name ($callArgs.ToArray()))
                }
                'new' {
                    if (-not $state.Classes.ContainsKey($node.Name)) {
                        throw "ALL PHP: Undefined class '$($node.Name)'"
                    }
                    $class = $state.Classes[$node.Name]
                    $object = [pscustomobject]@{
                        PhpType='object'
                        Class=$class.Name
                        Props=[System.Collections.Generic.Dictionary[string,object]]::new(
                            [System.StringComparer]::Ordinal)
                    }
                    foreach ($prop in $class.Properties) {
                        $value = $null
                        if ($null -ne $prop.Default) { $value = Invoke-PhpExpr $prop.Default }
                        $object.Props[$prop.Name] = $value
                    }
                    if ($class.Methods.ContainsKey('__construct')) {
                        $callArgs = [System.Collections.Generic.List[object]]::new()
                        foreach ($arg in $node.Args) { [void]$callArgs.Add((Invoke-PhpExpr $arg)) }
                        [void](Invoke-PhpMethod $object '__construct' ($callArgs.ToArray()))
                    } elseif ($node.Args.Count -gt 0) {
                        throw 'ALL PHP: Constructor arguments without __construct are not supported'
                    }
                    return $object
                }
                'unary' {
                    $value = Invoke-PhpExpr $node.Arg
                    switch ($node.Op) {
                        '!' { return (-not (Is-Truthy $value)) }
                        '+' { return (To-Number $value) }
                        '-' { return (-(To-Number $value)) }
                    }
                }
                'ternary' {
                    $testValue = Invoke-PhpExpr $node.Test
                    if (Is-Truthy $testValue) {
                        if ($null -eq $node.Yes) { return $testValue }
                        return (Invoke-PhpExpr $node.Yes)
                    }
                    return (Invoke-PhpExpr $node.No)
                }
                'match' {
                    $subjectValue = Invoke-PhpExpr $node.Subject
                    $defaultArm = $null
                    foreach ($arm in $node.Arms) {
                        if ($arm.IsDefault) {
                            $defaultArm = $arm
                            continue
                        }
                        foreach ($pattern in $arm.Patterns) {
                            if (Is-StrictEqual $subjectValue (Invoke-PhpExpr $pattern)) {
                                return (Invoke-PhpExpr $arm.Value)
                            }
                        }
                    }
                    if ($null -ne $defaultArm) { return (Invoke-PhpExpr $defaultArm.Value) }
                    throw 'ALL PHP: UnhandledMatchError'
                }
                'binary' {
                    if ($node.Op -ceq '??') {
                        $leftValue = $null
                        try { $leftValue = Invoke-PhpExpr $node.Left }
                        catch {
                            if ($_.Exception.Message -notlike 'ALL PHP: Undefined *') { throw }
                        }
                        if ($null -ne $leftValue) { return $leftValue }
                        return (Invoke-PhpExpr $node.Right)
                    }
                    if ($node.Op -ceq '&&') {
                        if (-not (Is-Truthy (Invoke-PhpExpr $node.Left))) { return $false }
                        return (Is-Truthy (Invoke-PhpExpr $node.Right))
                    }
                    if ($node.Op -ceq '||') {
                        if (Is-Truthy (Invoke-PhpExpr $node.Left)) { return $true }
                        return (Is-Truthy (Invoke-PhpExpr $node.Right))
                    }
                    $a = Invoke-PhpExpr $node.Left
                    $b = Invoke-PhpExpr $node.Right
                    switch ($node.Op) {
                        '**' {
                            $result = [Math]::Pow([double](To-Number $a), [double](To-Number $b))
                            if ([double]::IsNaN($result) -or [double]::IsInfinity($result)) {
                                throw 'ALL PHP: Power result outside supported numeric range'
                            }
                            try { return [decimal]$result }
                            catch { throw 'ALL PHP: Power result outside supported numeric range' }
                        }
                        '.' { return ((To-PhpText $a) + (To-PhpText $b)) }
                        '+' { return ((To-Number $a) + (To-Number $b)) }
                        '-' { return ((To-Number $a) - (To-Number $b)) }
                        '*' { return ((To-Number $a) * (To-Number $b)) }
                        '/' {
                            if ((To-Number $b) -eq 0) { throw 'ALL PHP: Division by zero' }
                            return ((To-Number $a) / (To-Number $b))
                        }
                        '%' {
                            $divisor = [long][decimal]::Truncate((To-Number $b))
                            if ($divisor -eq 0) { throw 'ALL PHP: Division by zero' }
                            $dividend = [long][decimal]::Truncate((To-Number $a))
                            return [decimal]($dividend % $divisor)
                        }
                        '==' { return ((Compare-Values $a $b) -eq 0) }
                        '!=' { return ((Compare-Values $a $b) -ne 0) }
                        '===' { return (Is-StrictEqual $a $b) }
                        '!==' { return (-not (Is-StrictEqual $a $b)) }
                        '<' { return ((Compare-Values $a $b) -lt 0) }
                        '<=' { return ((Compare-Values $a $b) -le 0) }
                        '>' { return ((Compare-Values $a $b) -gt 0) }
                        '>=' { return ((Compare-Values $a $b) -ge 0) }
                    }
                }
            }
            throw 'ALL PHP: Internal expression error'
        }
        function Invoke-PhpStatement($node) {
            $state.Steps++
            if ($state.Steps -gt 100000) {
                throw 'ALL PHP: Statement limit reached (100000)'
            }
            switch ($node.Kind) {
                'block' {
                    foreach ($s in $node.Body) {
                        if ($state.Flow.Returned -or $null -ne $state.Flow.LoopControl) { break }
                        Invoke-PhpStatement $s
                    }
                    return
                }
                'functiondef' {
                    if ($state.Functions.ContainsKey($node.Name)) {
                        throw "ALL PHP: Function already declared '$($node.Name)'"
                    }
                    $state.Functions[$node.Name] = $node
                    return
                }
                'classdef' {
                    if ($state.Classes.ContainsKey($node.Name)) {
                        throw "ALL PHP: Class already declared '$($node.Name)'"
                    }
                    $methods = [System.Collections.Generic.Dictionary[string,object]]::new(
                        [System.StringComparer]::OrdinalIgnoreCase)
                    foreach ($method in $node.Methods) {
                        if ($methods.ContainsKey($method.Name)) {
                            throw "ALL PHP: Duplicate method '$($method.Name)'"
                        }
                        $methods[$method.Name] = $method
                    }
                    $state.Classes[$node.Name] = [pscustomobject]@{
                        Name=$node.Name; Methods=$methods; Properties=$node.Properties
                    }
                    return
                }
                'loopcontrol' {
                    if ($state.Flow.LoopDepth -le 0) {
                        throw "ALL PHP: $($node.Action) outside loop"
                    }
                    $state.Flow.LoopControl = $node.Action
                    return
                }
                'return' {
                    if ($state.CallDepth -eq 0) { throw 'ALL PHP: Return outside function' }
                    $value = $null
                    if ($null -ne $node.Expr) { $value = Invoke-PhpExpr $node.Expr }
                    $state.Flow.Value = $value
                    $state.Flow.Returned = $true
                    return
                }
                'assign' {
                    if ($node.Op -ceq '??=') {
                        $current = $null
                        try { $current = Get-LValue $node.Target }
                        catch {
                            if ($_.Exception.Message -notlike 'ALL PHP: Undefined *') { throw }
                        }
                        if ($null -ne $current) { return }
                        $replacement = Invoke-PhpExpr $node.Value
                        Set-LValue $node.Target $replacement '='
                        return
                    }
                    $value = Invoke-PhpExpr $node.Value
                    Set-LValue $node.Target $value $node.Op
                    return
                }
                'exprstmt' {
                    [void](Invoke-PhpExpr $node.Expr)
                    return
                }
                'echo' {
                    foreach ($e in $node.Args) {
                        [Console]::Write((To-PhpText (Invoke-PhpExpr $e)))
                    }
                    return
                }
                'print' {
                    [Console]::Write((To-PhpText (Invoke-PhpExpr $node.Expr)))
                    return
                }
                'if' {
                    if (Is-Truthy (Invoke-PhpExpr $node.Test)) {
                        Invoke-PhpStatement $node.Yes
                    } elseif ($null -ne $node.No) {
                        Invoke-PhpStatement $node.No
                    }
                    return
                }
                'switch' {
                    $subject = Invoke-PhpExpr $node.Subject
                    $start = -1
                    $fallback = -1
                    for ($c=0; $c -lt $node.Cases.Count; $c++) {
                        $entry = $node.Cases[$c]
                        if ($entry.IsDefault) {
                            $fallback = $c
                        } elseif ((Compare-Values $subject (Invoke-PhpExpr $entry.Test)) -eq 0) {
                            $start = $c
                            break
                        }
                    }
                    if ($start -lt 0) { $start = $fallback }
                    if ($start -ge 0) {
                        $state.Flow.LoopDepth++
                        try {
                            $exitSwitch = $false
                            for ($c=$start; $c -lt $node.Cases.Count; $c++) {
                                foreach ($item in $node.Cases[$c].Body) {
                                    if ($state.Flow.Returned) { $exitSwitch = $true; break }
                                    Invoke-PhpStatement $item
                                    if ($null -ne $state.Flow.LoopControl) {
                                        # In PHP, continue targeting a switch behaves as break.
                                        $state.Flow.LoopControl = $null
                                        $exitSwitch = $true
                                        break
                                    }
                                    if ($state.Flow.Returned) { $exitSwitch = $true; break }
                                }
                                if ($exitSwitch) { break }
                            }
                        } finally { $state.Flow.LoopDepth-- }
                    }
                    return
                }
                'while' {
                    $state.Flow.LoopDepth++
                    try {
                        while (-not $state.Flow.Returned -and
                            (Is-Truthy (Invoke-PhpExpr $node.Test))) {
                            Invoke-PhpStatement $node.Body
                            if ($state.Flow.LoopControl -ceq 'break') {
                                $state.Flow.LoopControl = $null
                                break
                            }
                            if ($state.Flow.LoopControl -ceq 'continue') {
                                $state.Flow.LoopControl = $null
                                continue
                            }
                        }
                    } finally { $state.Flow.LoopDepth-- }
                    return
                }
                'do' {
                    $state.Flow.LoopDepth++
                    try {
                        do {
                            Invoke-PhpStatement $node.Body
                            if ($state.Flow.Returned) { break }
                            if ($state.Flow.LoopControl -ceq 'break') {
                                $state.Flow.LoopControl = $null
                                break
                            }
                            if ($state.Flow.LoopControl -ceq 'continue') {
                                $state.Flow.LoopControl = $null
                            }
                        } while (Is-Truthy (Invoke-PhpExpr $node.Test))
                    } finally { $state.Flow.LoopDepth-- }
                    return
                }
                'for' {
                    foreach ($mutation in $node.Init) { Invoke-PhpStatement $mutation }
                    $state.Flow.LoopDepth++
                    try {
                        while (-not $state.Flow.Returned) {
                            if ($null -ne $node.Test -and
                                -not (Is-Truthy (Invoke-PhpExpr $node.Test))) { break }
                            Invoke-PhpStatement $node.Body
                            if ($state.Flow.Returned) { break }
                            if ($state.Flow.LoopControl -ceq 'break') {
                                $state.Flow.LoopControl = $null
                                break
                            }
                            if ($state.Flow.LoopControl -ceq 'continue') {
                                $state.Flow.LoopControl = $null
                            }
                            foreach ($mutation in $node.Update) {
                                Invoke-PhpStatement $mutation
                            }
                        }
                    } finally { $state.Flow.LoopDepth-- }
                    return
                }
                'foreach' {
                    $arr = Invoke-PhpExpr $node.Iter
                    if (-not (Is-PhpArray $arr)) { throw 'ALL PHP: foreach requires an array' }
                    $state.Flow.LoopDepth++
                    try {
                        foreach ($key in @($arr.Items.Keys)) {
                            if ($state.Flow.Returned) { break }
                            $value = $arr.Items[$key]
                            $state.Vars[$node.ValueName] = Copy-PhpValue $value
                            if ($null -ne $node.KeyName) {
                                if ($key.StartsWith('i:')) {
                                    $state.Vars[$node.KeyName] = [decimal]$key.Substring(2)
                                } else {
                                    $state.Vars[$node.KeyName] = $key.Substring(2)
                                }
                            }
                            Invoke-PhpStatement $node.Body
                            if ($state.Flow.LoopControl -ceq 'break') {
                                $state.Flow.LoopControl = $null
                                break
                            }
                            if ($state.Flow.LoopControl -ceq 'continue') {
                                $state.Flow.LoopControl = $null
                                continue
                            }
                        }
                    } finally { $state.Flow.LoopDepth-- }
                    return
                }
            }
            throw 'ALL PHP: Internal statement error'
        }
        foreach ($statement in $statements) {
            if ($state.Flow.Returned) { break }
            Invoke-PhpStatement $statement
        }
    }
}
