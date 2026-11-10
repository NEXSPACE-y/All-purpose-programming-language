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
            Interfaces = [System.Collections.Generic.Dictionary[string,object]]::new(
                [System.StringComparer]::OrdinalIgnoreCase)
            Traits = [System.Collections.Generic.Dictionary[string,object]]::new(
                [System.StringComparer]::OrdinalIgnoreCase)
            Flow = @{ Returned = $false; Value = $null; LoopControl=$null; LoopDepth=0 }
            CallDepth = 0
            Steps = 0
            JsonError = 0
            JsonErrorMessage = 'No error'
            MagicGetActive = [System.Collections.Generic.HashSet[string]]::new(
                [System.StringComparer]::Ordinal)
            MagicSetActive = [System.Collections.Generic.HashSet[string]]::new(
                [System.StringComparer]::Ordinal)
            Globals = $null
                GlobalBindings = [System.Collections.Generic.HashSet[string]]::new(
                    [System.StringComparer]::Ordinal)
                StaticBindings = [System.Collections.Generic.HashSet[string]]::new(
                    [System.StringComparer]::Ordinal)
                FunctionStatics = [System.Collections.Generic.Dictionary[string,object]]::new(
                    [System.StringComparer]::Ordinal)
                CurrentCallable = $null
                ClassContext = $null
        }

        $state.Globals = $state.Vars

        # Tokenize before parsing. Unknown characters produce an error, never disappear.
        $pattern = '(?:\s+|//[^\r\n]*|\#[^\r\n]*|/\*[\s\S]*?\*/|"(?:\\.|[^"\\])*"|''(?:\\.|[^''\\])*''|\$\$[A-Za-z_][A-Za-z_0-9]*|\$[A-Za-z_][A-Za-z_0-9]*|\$(?=\{)|\d+(?:\.\d+)?|[A-Za-z_][A-Za-z_0-9]*|<=>|::|\.\.\.|<<=|>>=|<<|>>|===|!==|==|!=|<=|>=|&&|\|\||=>|->|\*\*=|\*\*|\?\?=|\?\?|\?->|\+\+|--|\*=|/=|%=|&=|\|=|\^=|\+=|-=|\.=|[+\-*/%.=<>!?:;{},()\[\]&|^~])'
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
                    [void]$output.Append((To-PhpText (Get-PhpVariableValue $name)))
                }
                if ($braced) { $i = $end }
                else { $i = $end - 1 }
            }
            return $output.ToString()
        }
        function Take-PhpFirstClassCallableArgs {
            if ((Peek-Token) -cne '(' -or $state.Pos + 2 -ge $state.Tokens.Count) {
                return $false
            }
            if ($state.Tokens[$state.Pos + 1] -cne '...' -or
                $state.Tokens[$state.Pos + 2] -cne ')') { return $false }
            Expect-Token '('
            Expect-Token '...'
            Expect-Token ')'
            return $true
        }
        function Read-Arguments {
            Expect-Token '('
            $callArgs = [System.Collections.Generic.List[object]]::new()
            if ((Peek-Token) -cne ')') {
                while ($true) {
                    $first = Peek-Token
                    if ($first -cmatch '^[A-Za-z_][A-Za-z_0-9]*$' -and
                        $state.Pos + 1 -lt $state.Tokens.Count -and
                        $state.Tokens[$state.Pos + 1] -ceq ':') {
                        [void](Next-Token)
                        Expect-Token ':'
                        $valueExpr = Read-Expr 1
                        [void]$callArgs.Add([pscustomobject]@{
                            Kind='named_argument'; Name=$first; Expr=$valueExpr
                        })
                    } else {
                        [void]$callArgs.Add((Read-Expr 1))
                    }
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
                    $spread = $false
                    if ((Peek-Token) -ceq '...') {
                        [void](Next-Token)
                        $spread = $true
                    }
                    $first = Read-Expr 1
                    $key = $null
                    $value = $first
                    if ((Peek-Token) -ceq '=>') {
                        if ($spread) { throw 'ALL PHP: Spread cannot have explicit key' }
                        [void](Next-Token)
                        $key = $first
                        $value = Read-Expr 1
                    }
                    [void]$entries.Add([pscustomobject]@{ Key=$key; Value=$value; Spread=$spread })
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
            if ($token -cmatch '^\$\$[A-Za-z_][A-Za-z_0-9]*$') {
                [void](Next-Token)
                return [pscustomobject]@{
                    Kind='dynamic_variable'; NameExpr=[pscustomobject]@{
                        Kind='variable'; Name=$token.Substring(2)
                    }
                }
            }
            if ($token -ceq '$') {
                [void](Next-Token)
                Expect-Token '{'
                $nameExpression=Read-Expr 1
                Expect-Token '}'
                return [pscustomobject]@{
                    Kind='dynamic_variable'; NameExpr=$nameExpression
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
            if ($token -eq 'function' -or $token -eq 'fn') {
                $arrow=($token -eq 'fn')
                [void](Next-Token)
                if ($token -eq 'function' -and (Peek-Token) -ceq '&') {
                    throw 'ALL PHP: Closure return by reference is not yet supported'
                }
                $params=Read-Parameters
                $captures=[System.Collections.Generic.List[object]]::new()
                $body=$null
                $expr=$null
                if ($arrow) {
                    Expect-Token '=>'
                    $expr=Read-Expr 1
                } else {
                    if ((Peek-Token) -eq 'use') {
                        [void](Next-Token)
                        Expect-Token '('
                        while ((Peek-Token) -cne ')') {
                            $byRef=$false
                            if ((Peek-Token) -ceq '&') {
                                [void](Next-Token)
                                $byRef=$true
                            }
                            $name=Next-Token
                            if ($name -cnotmatch '^\$[A-Za-z_][A-Za-z_0-9]*$') {
                                throw 'ALL PHP: Invalid closure capture variable'
                            }
                            [void]$captures.Add([pscustomobject]@{
                                Name=$name.Substring(1); ByRef=$byRef
                            })
                            if ((Peek-Token) -cne ',') { break }
                            [void](Next-Token)
                        }
                        Expect-Token ')'
                    }
                    if ((Peek-Token) -cne '{') { throw 'ALL PHP: Closure body must be a block' }
                    $body=Read-Statement
                }
                return [pscustomobject]@{
                    Kind='closure'; Params=@($params); Body=$body; Expr=$expr
                    Captures=$captures.ToArray(); Arrow=$arrow
                    Name='(closure)'
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
                if ($token -eq 'stdClass') {
                    return [pscustomobject]@{ Kind='class_name'; Name=$token }
                }
                if ((Peek-Token) -ceq '(') {
                    if (Take-PhpFirstClassCallableArgs) {
                        return [pscustomobject]@{
                            Kind='first_class_function'; Name=$token
                        }
                    }
                    $callArgs = Read-Arguments
                    return [pscustomobject]@{ Kind='call'; Name=$token; Args=@($callArgs) }
                }
                return [pscustomobject]@{ Kind='class_name'; Name=$token }
            }
            throw "ALL PHP: Unsupported expression starting with '$token'"
        }
        function Read-Postfix {
            $expr = Read-Primary
            while ($true) {
                $token = Peek-Token
                if ($token -ceq '(') {
                    if (Take-PhpFirstClassCallableArgs) {
                        $expr=[pscustomobject]@{
                            Kind='first_class_invoke'; Callee=$expr
                        }
                    } else {
                        $callArgs=Read-Arguments
                        $expr=[pscustomobject]@{
                            Kind='invoke'; Callee=$expr; Args=@($callArgs)
                        }
                    }
                    continue
                }
                if ($token -ceq '[') {
                    [void](Next-Token)
                    $key = $null
                    if ((Peek-Token) -cne ']') { $key = Read-Expr 1 }
                    Expect-Token ']'
                    $expr = [pscustomobject]@{ Kind='index'; Base=$expr; Key=$key }
                    continue
                }
                if ($token -ceq '::') {
                    if ($expr.Kind -notin @('class_name','variable')) {
                        throw 'ALL PHP: Invalid static class reference'
                    }
                    [void](Next-Token)
                    $member = Next-Token
                    if ($member -cmatch '^\$[A-Za-z_][A-Za-z_0-9]*$') {
                        $expr = [pscustomobject]@{
                            Kind='static_property'; Base=$expr; Name=$member.Substring(1)
                        }
                    } elseif ($member -cmatch '^[A-Za-z_][A-Za-z_0-9]*$') {
                        if ((Peek-Token) -ceq '(') {
                            if (Take-PhpFirstClassCallableArgs) {
                                $expr=[pscustomobject]@{
                                    Kind='first_class_static'; Base=$expr; Name=$member
                                }
                            } else {
                                $callArgs = Read-Arguments
                                $expr = [pscustomobject]@{
                                    Kind='static_method'; Base=$expr; Name=$member; Args=@($callArgs)
                                }
                            }
                        } else {
                            $expr = [pscustomobject]@{
                                Kind='class_const'; Base=$expr; Name=$member
                            }
                        }
                    } else { throw 'ALL PHP: Invalid static member name' }
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
                        if (Take-PhpFirstClassCallableArgs) {
                            $expr = [pscustomobject]@{
                                Kind='first_class_method'; Base=$expr; Name=$member
                                NullSafe=$nullSafe
                            }
                        } else {
                            $callArgs = Read-Arguments
                            $expr = [pscustomobject]@{
                                Kind='method'; Base=$expr; Name=$member; Args=@($callArgs)
                                NullSafe=$nullSafe
                            }
                        }
                    } else {
                        $expr = [pscustomobject]@{
                            Kind='property'; Base=$expr; Name=$member
                            NullSafe=$nullSafe
                        }
                    }
                    continue
                }
                if ($token -in @('++','--')) {
                    if ($expr.Kind -notin @('variable','dynamic_variable','index','property','static_property')) {
                        throw 'ALL PHP: Invalid postfix update target'
                    }
                    [void](Next-Token)
                    $expr = [pscustomobject]@{
                        Kind='update'; Target=$expr; Op=$token; Prefix=$false
                    }
                    break
                }
                break
            }
            return $expr
        }
        function Read-Unary {
            $token = Peek-Token
            if ($token -ceq 'clone') {
                [void](Next-Token)
                return [pscustomobject]@{ Kind='clone'; Arg=(Read-Unary) }
            }
            if ($token -in @('++','--')) {
                [void](Next-Token)
                $target = Read-Postfix
                if ($target.Kind -notin @('variable','dynamic_variable','index','property','static_property')) {
                    throw 'ALL PHP: Invalid prefix update target'
                }
                return [pscustomobject]@{ Kind='update'; Target=$target; Op=$token; Prefix=$true }
            }
            if ($token -ceq '!') {
                # In PHP, ! binds less tightly than instanceof, but more tightly
                # than multiplication/comparison. Use the instanceof priority.
                [void](Next-Token)
                $arg = Read-Expr 14
                return [pscustomobject]@{ Kind='unary'; Op=$token; Arg=$arg }
            }
            if ($token -in @('+', '-', '~')) {
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
                '|'  { return 5 }
                '^'  { return 6 }
                '&'  { return 7 }
                '||' { return 3 }
                '&&' { return 4 }
                '==' { return 8 }
                '!=' { return 8 }
                '===' { return 8 }
                '!==' { return 8 }
                '<' { return 9 }
                '<=' { return 9 }
                '>' { return 9 }
                '>=' { return 9 }
                '.' { return 10 }
                '+' { return 12 }
                '-' { return 12 }
                '*' { return 13 }
                '/' { return 13 }
                '%' { return 13 }
                '<<' { return 11 }
                '>>' { return 11 }
                '<=>' { return 8 }
                'instanceof' { return 14 }
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
                (Peek-Token) -in @('=','+=','-=','.=','??=','*=','/=','%=','**=','&=','|=','^=','<<=','>>=')) {
                if ($left.Kind -notin @('variable','dynamic_variable','index','property','static_property','array')) {
                    throw 'ALL PHP: Invalid assignment expression target'
                }
                $assignmentOp = Next-Token
                if ($assignmentOp -ceq '=' -and (Peek-Token) -ceq '&') {
                    if ($left.Kind -notin @('variable','dynamic_variable','index','property','static_property')) {
                        throw 'ALL PHP: Invalid reference assignment target'
                    }
                    [void](Next-Token)
                    $refTarget=Read-Postfix
                    if ($refTarget.Kind -notin @('variable','dynamic_variable','index','property','static_property')) {
                        throw 'ALL PHP: Reference source must be a writable value'
                    }
                    if (($left.Kind -eq 'property' -and $left.NullSafe) -or
                        ($refTarget.Kind -eq 'property' -and $refTarget.NullSafe)) {
                        throw 'ALL PHP: Cannot create reference through nullsafe access'
                    }
                    return [pscustomobject]@{
                        Kind='assign_ref'; Target=$left; Source=$refTarget
                    }
                }
                if ($left.Kind -eq 'array' -and $assignmentOp -cne '=') {
                    throw 'ALL PHP: Destructuring supports only plain assignment'
                }
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
                if ($target.Kind -eq 'update') {
                    [void]$nodes.Add([pscustomobject]@{ Kind='exprstmt'; Expr=$target })
                    if ((Peek-Token) -cne ',') { break }
                    [void](Next-Token)
                    continue
                }
                if ($target.Kind -notin @('variable','dynamic_variable','index','property','static_property')) {
                    throw 'ALL PHP: Invalid for-loop mutation target'
                }
                $op = Next-Token
                if ($op -in @('++','--')) {
                    $op = if ($op -ceq '++') { '+=' } else { '-=' }
                    $value = [pscustomobject]@{ Kind='literal'; Value=[decimal]1 }
                } elseif ($op -in @('=','+=','-=','.=','??=','*=','/=','%=','**=','&=','|=','^=','<<=','>>=')) {
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
            if ($token -eq 'function' -and
                $state.Pos + 1 -lt $state.Tokens.Count -and
                $state.Tokens[$state.Pos + 1] -cmatch '^[A-Za-z_][A-Za-z_0-9]*$') {
                return (Read-Function)
            }
            if ($token -eq 'global') {
                [void](Next-Token)
                $names = [System.Collections.Generic.List[string]]::new()
                while ($true) {
                    $name = Next-Token
                    if ($name -cnotmatch '^\$[A-Za-z_][A-Za-z_0-9]*$') {
                        throw 'ALL PHP: Expected variable in global declaration'
                    }
                    [void]$names.Add($name.Substring(1))
                    if ((Peek-Token) -cne ',') { break }
                    [void](Next-Token)
                }
                Expect-Token ';'
                return [pscustomobject]@{ Kind='globaldecl'; Names=$names.ToArray() }
            }
            if ($token -eq 'static') {
                [void](Next-Token)
                $decls = [System.Collections.Generic.List[object]]::new()
                while ($true) {
                    $name = Next-Token
                    if ($name -cnotmatch '^\$[A-Za-z_][A-Za-z_0-9]*$') {
                        throw 'ALL PHP: Expected variable in static local declaration'
                    }
                    $init = $null
                    if ((Peek-Token) -ceq '=') {
                        [void](Next-Token)
                        $init = Read-Expr 1
                    }
                    [void]$decls.Add([pscustomobject]@{ Name=$name.Substring(1); Init=$init })
                    if ((Peek-Token) -cne ',') { break }
                    [void](Next-Token)
                }
                Expect-Token ';'
                return [pscustomobject]@{ Kind='staticdecl'; Decls=$decls.ToArray() }
            }
            if ($token -eq 'interface') {
                [void](Next-Token)
                $name = Next-Token
                if ($name -cnotmatch '^[A-Za-z_][A-Za-z_0-9]*$') {
                    throw 'ALL PHP: Expected interface name'
                }
                $parents = [System.Collections.Generic.List[string]]::new()
                if ((Peek-Token) -eq 'extends') {
                    [void](Next-Token)
                    while ($true) {
                        $parentName = Next-Token
                        if ($parentName -cnotmatch '^[A-Za-z_][A-Za-z_0-9]*$') {
                            throw 'ALL PHP: Expected parent interface name'
                        }
                        [void]$parents.Add($parentName)
                        if ((Peek-Token) -cne ',') { break }
                        [void](Next-Token)
                    }
                }
                Expect-Token '{'
                $methods = [System.Collections.Generic.List[object]]::new()
                $constants = [System.Collections.Generic.List[object]]::new()
                while ((Peek-Token) -cne '}') {
                    if ((Peek-Token) -ceq '(EOF)') { throw 'ALL PHP: Missing interface closing brace' }
                    $methodStatic=$false
                    $modifiers=[System.Collections.Generic.HashSet[string]]::new(
                        [System.StringComparer]::Ordinal)
                    while ((Peek-Token) -in @('public','static')) {
                        $modifier=Next-Token
                        if (-not $modifiers.Add($modifier)) {
                            throw 'ALL PHP: Duplicate interface member modifier'
                        }
                        if ($modifier -eq 'static') { $methodStatic=$true }
                    }
                    if ((Peek-Token) -eq 'function') {
                        $method=Read-Function $true
                        $method.Owner=$name
                        $method.Visibility='public'
                        $method.Abstract=$true
                        $method.Static=$methodStatic
                        [void]$methods.Add($method)
                    } elseif ((Peek-Token) -eq 'const') {
                        if ($methodStatic) { throw 'ALL PHP: Interface constants cannot be static' }
                        [void](Next-Token)
                        $constName=Next-Token
                        if ($constName -cnotmatch '^[A-Za-z_][A-Za-z_0-9]*$') {
                            throw 'ALL PHP: Expected interface constant name'
                        }
                        Expect-Token '='
                        $expr=Read-Expr 1
                        Expect-Token ';'
                        [void]$constants.Add([pscustomobject]@{
                            Name=$constName; Value=$expr; Visibility='public'
                        })
                    } else {
                        throw "ALL PHP: Unsupported interface member '$(Peek-Token)'"
                    }
                }
                Expect-Token '}'
                return [pscustomobject]@{
                    Kind='interfacedef'; Name=$name; Parents=$parents.ToArray()
                    Methods=$methods.ToArray(); Constants=$constants.ToArray()
                }
            }
            if ($token -eq 'enum') {
                [void](Next-Token)
                $enumName=Next-Token
                if ($enumName -cnotmatch '^[A-Za-z_][A-Za-z_0-9]*$') {
                    throw 'ALL PHP: Expected enum name'
                }
                $backingType=$null
                if ((Peek-Token) -ceq ':') {
                    [void](Next-Token)
                    $backingType=Next-Token
                    if ($backingType -notin @('string','int')) {
                        throw 'ALL PHP: Backed enum must be int or string'
                    }
                }
                $enumInterfaces=[System.Collections.Generic.List[string]]::new()
                if ((Peek-Token) -ceq 'implements') {
                    [void](Next-Token)
                    while ($true) {
                        $iface=Next-Token
                        if ($iface -cnotmatch '^[A-Za-z_][A-Za-z_0-9]*$') {
                            throw 'ALL PHP: Expected enum interface'
                        }
                        [void]$enumInterfaces.Add($iface)
                        if ((Peek-Token) -cne ',') { break }
                        [void](Next-Token)
                    }
                }
                Expect-Token '{'
                $enumCases=[System.Collections.Generic.List[object]]::new()
                $enumMethods=[System.Collections.Generic.List[object]]::new()
                while ((Peek-Token) -cne '}') {
                    if ((Peek-Token) -ceq '(EOF)') { throw 'ALL PHP: Missing enum closing brace' }
                    if ((Peek-Token) -ceq 'case') {
                        [void](Next-Token)
                        $caseName=Next-Token
                        if ($caseName -cnotmatch '^[A-Za-z_][A-Za-z_0-9]*$') {
                            throw 'ALL PHP: Expected enum case name'
                        }
                        $caseExpr=$null
                        if ((Peek-Token) -ceq '=') {
                            [void](Next-Token)
                            $caseExpr=Read-Expr 1
                        }
                        if ($null -eq $backingType -and $null -ne $caseExpr) {
                            throw 'ALL PHP: Unit enum cases cannot have values'
                        }
                        if ($null -ne $backingType -and $null -eq $caseExpr) {
                            throw 'ALL PHP: Backed enum cases require values'
                        }
                        Expect-Token ';'
                        [void]$enumCases.Add([pscustomobject]@{
                            Name=$caseName; Value=$caseExpr
                        })
                        continue
                    }
                    $static=$false
                    if ((Peek-Token) -ceq 'public') { [void](Next-Token) }
                    if ((Peek-Token) -ceq 'static') { [void](Next-Token); $static=$true }
                    if ((Peek-Token) -cne 'function') {
                        throw "ALL PHP: Unsupported enum member '$(Peek-Token)'"
                    }
                    $method=Read-Function
                    $method.Static=$static
                    $method.Visibility='public'
                    $method.Owner=$enumName
                    [void]$enumMethods.Add($method)
                }
                Expect-Token '}'
                return [pscustomobject]@{
                    Kind='enumdef'; Name=$enumName; BackingType=$backingType
                    Cases=$enumCases.ToArray(); Methods=$enumMethods.ToArray()
                    Interfaces=$enumInterfaces.ToArray()
                }
            }
            if ($token -in @('abstract','final','class','trait')) {
                $isAbstract=$false
                $isFinal=$false
                $isTrait=($token -eq 'trait')
                if ($token -eq 'abstract') { $isAbstract=$true; [void](Next-Token); Expect-Token 'class' }
                elseif ($token -eq 'final') { $isFinal=$true; [void](Next-Token); Expect-Token 'class' }
                else { [void](Next-Token) }
                $name = Next-Token
                if ($name -cnotmatch '^[A-Za-z_][A-Za-z_0-9]*$') {
                    throw 'ALL PHP: Expected class name'
                }
                $parent = $null
                if ((Peek-Token) -eq 'extends') {
                    [void](Next-Token)
                    $parent = Next-Token
                    if ($parent -cnotmatch '^[A-Za-z_][A-Za-z_0-9]*$') {
                        throw 'ALL PHP: Expected parent class name'
                    }
                }
                $interfaces=[System.Collections.Generic.List[string]]::new()
                if ((Peek-Token) -eq 'implements') {
                    [void](Next-Token)
                    while ($true) {
                        $iface = Next-Token
                        if ($iface -cnotmatch '^[A-Za-z_][A-Za-z_0-9]*$') {
                            throw 'ALL PHP: Expected implemented interface name'
                        }
                        [void]$interfaces.Add($iface)
                        if ((Peek-Token) -cne ',') { break }
                        [void](Next-Token)
                    }
                }
                Expect-Token '{'
                $methods = [System.Collections.Generic.List[object]]::new()
                $properties = [System.Collections.Generic.List[object]]::new()
                $constants = [System.Collections.Generic.List[object]]::new()
                $traits = [System.Collections.Generic.List[string]]::new()
                $traitUses = [System.Collections.Generic.List[object]]::new()
                while ((Peek-Token) -cne '}') {
                    if ((Peek-Token) -ceq '(EOF)') { throw 'ALL PHP: Missing class closing brace' }
                    if ((Peek-Token) -eq 'use') {
                        [void](Next-Token)
                        $usedNames=[System.Collections.Generic.List[string]]::new()
                        $adaptations=[System.Collections.Generic.List[object]]::new()
                        while ($true) {
                            $traitName=Next-Token
                            if ($traitName -cnotmatch '^[A-Za-z_][A-Za-z_0-9]*$') {
                                throw 'ALL PHP: Expected trait name'
                            }
                            [void]$traits.Add($traitName)
                            [void]$usedNames.Add($traitName)
                            if ((Peek-Token) -cne ',') { break }
                            [void](Next-Token)
                        }
                        if ((Peek-Token) -eq '{') {
                            [void](Next-Token)
                            while ((Peek-Token) -cne '}') {
                                if ((Peek-Token) -eq '(EOF)') {
                                    throw 'ALL PHP: Missing trait adaptation closing brace'
                                }
                                $sourceTrait=$null
                                $member=Next-Token
                                if ((Peek-Token) -ceq '::') {
                                    $sourceTrait=$member
                                    [void](Next-Token)
                                    $member=Next-Token
                                }
                                if ($member -cnotmatch '^[A-Za-z_][A-Za-z_0-9]*$') {
                                    throw 'ALL PHP: Expected trait method name'
                                }
                                $action=Next-Token
                                if ($action -eq 'insteadof') {
                                    if ($null -eq $sourceTrait) {
                                        throw 'ALL PHP: insteadof requires qualified trait method'
                                    }
                                    $excluded=[System.Collections.Generic.List[string]]::new()
                                    while ($true) {
                                        $loser=Next-Token
                                        if ($loser -cnotmatch '^[A-Za-z_][A-Za-z_0-9]*$') {
                                            throw 'ALL PHP: Expected excluded trait name'
                                        }
                                        [void]$excluded.Add($loser)
                                        if ((Peek-Token) -cne ',') { break }
                                        [void](Next-Token)
                                    }
                                    Expect-Token ';'
                                    [void]$adaptations.Add([pscustomobject]@{
                                        Kind='insteadof'; Trait=$sourceTrait
                                        Method=$member; Excluded=$excluded.ToArray()
                                    })
                                } elseif ($action -eq 'as') {
                                    $visibility=$null
                                    $alias=$null
                                    if ((Peek-Token) -in @('public','protected','private')) {
                                        $visibility=Next-Token
                                    }
                                    if ((Peek-Token) -cne ';') {
                                        $alias=Next-Token
                                        if ($alias -cnotmatch '^[A-Za-z_][A-Za-z_0-9]*$') {
                                            throw 'ALL PHP: Invalid trait alias name'
                                        }
                                    }
                                    if ($null -eq $visibility -and $null -eq $alias) {
                                        throw 'ALL PHP: Trait alias requires a name or visibility'
                                    }
                                    Expect-Token ';'
                                    [void]$adaptations.Add([pscustomobject]@{
                                        Kind='alias'; Trait=$sourceTrait
                                        Method=$member; Alias=$alias; Visibility=$visibility
                                    })
                                } else {
                                    throw 'ALL PHP: Expected as or insteadof in trait adaptation'
                                }
                            }
                            Expect-Token '}'
                        } else { Expect-Token ';' }
                        [void]$traitUses.Add([pscustomobject]@{
                            Names=$usedNames.ToArray(); Adaptations=$adaptations.ToArray()
                        })
                        continue
                    }
                    $visibility='public'
                    $isStatic=$false
                    $isAbstractMethod=$false
                    $isFinalMethod=$false
                    $modifiers=[System.Collections.Generic.HashSet[string]]::new(
                        [System.StringComparer]::Ordinal)
                    while ((Peek-Token) -in @('public','private','protected','static','abstract','final')) {
                        $modifier=Next-Token
                        if (-not $modifiers.Add($modifier)) {
                            throw 'ALL PHP: Duplicate class member modifier'
                        }
                        if ($modifier -in @('public','private','protected')) {
                            if ($modifiers.Contains('public') -and $modifier -cne 'public' -or
                                $modifiers.Contains('protected') -and $modifier -cne 'protected' -or
                                $modifiers.Contains('private') -and $modifier -cne 'private') {
                                throw 'ALL PHP: Conflicting visibility modifiers'
                            }
                            $visibility=$modifier
                        } elseif ($modifier -eq 'static') { $isStatic=$true }
                        elseif ($modifier -eq 'abstract') { $isAbstractMethod=$true }
                        elseif ($modifier -eq 'final') { $isFinalMethod=$true }
                    }
                    if ((Peek-Token) -eq 'function') {
                        if ($isAbstractMethod -and $isFinalMethod) {
                            throw 'ALL PHP: Method cannot be both abstract and final'
                        }
                        if ($isAbstractMethod -and -not $isAbstract) {
                            throw 'ALL PHP: Abstract methods require an abstract class'
                        }
                        if ($isAbstractMethod -and $visibility -eq 'private') {
                            throw 'ALL PHP: Abstract methods cannot be private'
                        }
                        $method = Read-Function $isAbstractMethod
                        $method.Visibility=$visibility
                        $method.Static=$isStatic
                        $method.Owner=$name
                        $method.Abstract=$isAbstractMethod
                        $method.Final=$isFinalMethod
                        [void]$methods.Add($method)
                    } elseif ((Peek-Token) -eq 'const') {
                        if ($isStatic -or $isAbstractMethod -or $isFinalMethod) {
                            throw 'ALL PHP: Unsupported constant modifier'
                        }
                        [void](Next-Token)
                        $constName = Next-Token
                        if ($constName -cnotmatch '^[A-Za-z_][A-Za-z_0-9]*$') {
                            throw 'ALL PHP: Expected class constant name'
                        }
                        Expect-Token '='
                        $constValue=Read-Expr 1
                        Expect-Token ';'
                        [void]$constants.Add([pscustomobject]@{
                            Name=$constName; Value=$constValue; Visibility=$visibility
                        })
                    } elseif ((Peek-Token) -cmatch '^\$[A-Za-z_][A-Za-z_0-9]*$') {
                        if ($isAbstractMethod -or $isFinalMethod) {
                            throw 'ALL PHP: Abstract/final modifier not valid for properties'
                        }
                        $propName = (Next-Token).Substring(1)
                        $defaultExpr = $null
                        if ((Peek-Token) -ceq '=') {
                            [void](Next-Token)
                            $defaultExpr = Read-Expr 1
                        }
                        Expect-Token ';'
                        [void]$properties.Add([pscustomobject]@{
                            Name=$propName; Default=$defaultExpr
                            Visibility=$visibility; Static=$isStatic; Owner=$name
                        })
                    } else {
                        throw "ALL PHP: Unsupported class member '$(Peek-Token)'"
                    }
                }
                Expect-Token '}'
                return [pscustomobject]@{
                    Kind=$(if ($isTrait) { 'traitdef' } else { 'classdef' }); Name=$name; Parent=$parent
                    Methods=$methods.ToArray(); Properties=$properties.ToArray()
                    Constants=$constants.ToArray(); Interfaces=$interfaces.ToArray()
                    Abstract=$isAbstract; Final=$isFinal; Traits=$traits.ToArray()
                    TraitUses=$traitUses.ToArray()
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
                $byReference = $false
                if ((Peek-Token) -ceq '&') {
                    [void](Next-Token)
                    $byReference = $true
                }
                $first = Next-Token
                if ($first -cnotmatch '^\$[A-Za-z_][A-Za-z_0-9]*$') {
                    throw 'ALL PHP: Expected foreach variable'
                }
                $keyName = $null
                $valueName = $first.Substring(1)
                if ((Peek-Token) -ceq '=>') {
                    if ($byReference) { throw 'ALL PHP: Foreach key cannot be a reference' }
                    [void](Next-Token)
                    $keyName = $valueName
                    if ((Peek-Token) -ceq '&') {
                        [void](Next-Token)
                        $byReference = $true
                    }
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
                    ValueName=$valueName; ByReference=$byReference; Body=$body
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
            $expr=Read-Expr 1
            if ($expr.Kind -ceq 'class_name') {
                throw 'ALL PHP: Undefined constant in expression statement'
            }
            Expect-Token ';'
            return [pscustomobject]@{ Kind='exprstmt'; Expr=$expr }

        }
        function Read-Parameters {
            Expect-Token '('
            $parameters = [System.Collections.Generic.List[object]]::new()
            $sawVariadic = $false
            if ((Peek-Token) -cne ')') {
                while ($true) {
                    if ($sawVariadic) { throw 'ALL PHP: Variadic parameter must be last' }
                    $byRef = $false
                    if ((Peek-Token) -ceq '&') {
                        $byRef = $true
                        [void](Next-Token)
                    }
                    $variadic = $false
                    if ((Peek-Token) -ceq '...') {
                        $variadic = $true
                        $sawVariadic = $true
                        [void](Next-Token)
                    }
                    $param = Next-Token
                    if ($param -cnotmatch '^\$[A-Za-z_][A-Za-z_0-9]*$') {
                        throw "ALL PHP: Expected parameter, got '$param'"
                    }
                    $default = $null
                    if ((Peek-Token) -ceq '=') {
                        if ($variadic) { throw 'ALL PHP: Variadic parameters cannot have defaults' }
                        [void](Next-Token)
                        $default = Read-Expr 1
                    }
                    foreach ($previous in $parameters) {
                        if ($previous.Name -ceq $param.Substring(1)) {
                            throw 'ALL PHP: Duplicate function parameter'
                        }
                    }
                    [void]$parameters.Add([pscustomobject]@{
                        Name=$param.Substring(1); Default=$default; Variadic=$variadic
                        ByRef=$byRef
                    })
                    if ((Peek-Token) -cne ',') { break }
                    [void](Next-Token)
                    if ((Peek-Token) -ceq ')') { break }
                }
            }
            Expect-Token ')'
            return ,($parameters.ToArray())
        }
        function Read-Function([bool]$declarationOnly = $false) {
            Expect-Token 'function'
            $name = Next-Token
            if ($name -cnotmatch '^[A-Za-z_][A-Za-z_0-9]*$') {
                throw 'ALL PHP: Expected function name'
            }
            $parameters = Read-Parameters
            $body=$null
            if ($declarationOnly) {
                Expect-Token ';'
            } else {
                if ((Peek-Token) -cne '{') { throw 'ALL PHP: Function body must be a block' }
                $body = Read-Statement
            }
            return [pscustomobject]@{
                Kind='functiondef'; Name=$name; Params=@($parameters); Body=$body
                Visibility='public'; Static=$false; Owner=$null
                Abstract=$declarationOnly; Final=$false
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
        function Get-PhpVariableSlot([string]$name) {
            if ($state.GlobalBindings.Contains($name)) {
                return [pscustomobject]@{ Store=$state.Globals; Key=$name }
            }
            if ($state.StaticBindings.Contains($name)) {
                return [pscustomobject]@{
                    Store=$state.FunctionStatics; Key=($state.CurrentCallable + '|' + $name)
                }
            }
            return [pscustomobject]@{ Store=$state.Vars; Key=$name }
        }
        function Is-PhpRefCell($value) {
            return ($null -ne $value -and $value.PSObject.Properties['PhpType'] -and
                $value.PhpType -ceq 'refcell')
        }
        function Get-PhpVariableValue([string]$name) {
            $slot=Get-PhpVariableSlot $name
            if (-not $slot.Store.ContainsKey($slot.Key)) {
                if ($state.GlobalBindings.Contains($name)) { return $null }
                throw "ALL PHP: Undefined variable '$name'"
            }
            $value=$slot.Store[$slot.Key]
            if (Is-PhpRefCell $value) { return $value.Value }
            return $value
        }
        function Set-PhpVariableValue([string]$name, $value) {
            $slot=Get-PhpVariableSlot $name
            if ($slot.Store.ContainsKey($slot.Key) -and
                (Is-PhpRefCell $slot.Store[$slot.Key])) {
                $slot.Store[$slot.Key].Value=Copy-PhpValue $value
            } else {
                $slot.Store[$slot.Key]=Copy-PhpValue $value
            }
        }
        function Get-PhpVariableCell([string]$name) {
            $slot=Get-PhpVariableSlot $name
            if ($slot.Store.ContainsKey($slot.Key)) {
                $value=$slot.Store[$slot.Key]
                if (Is-PhpRefCell $value) { return $value }
            } else { $value=$null }
            $cell=[pscustomobject]@{PhpType='refcell'; Value=(Copy-PhpValue $value)}
            $slot.Store[$slot.Key]=$cell
            return $cell
        }
        function Set-PhpVariableReference([string]$target, [string]$source) {
            $ref=Get-PhpVariableCell $source
            $slot=Get-PhpVariableSlot $target
            $slot.Store[$slot.Key]=$ref
        }
        function Resolve-PhpLValueSlot($node) {
            if ($node.Kind -eq 'variable') {
                return (Get-PhpVariableSlot $node.Name)
            }
            if ($node.Kind -eq 'dynamic_variable') {
                return (Get-PhpVariableSlot (Resolve-PhpDynamicVariableName $node))
            }
            if ($node.Kind -eq 'index') {
                if ($node.Base.Kind -in @('variable','dynamic_variable')) {
                    $baseName=if ($node.Base.Kind -eq 'variable') {
                        $node.Base.Name
                    } else { Resolve-PhpDynamicVariableName $node.Base }
                    $baseValue=$null
                    try { $baseValue=Get-PhpVariableValue $baseName }
                    catch {
                        if ($_.Exception.Message -notlike 'ALL PHP: Undefined variable*') { throw }
                    }
                    if ($null -eq $baseValue) { Set-PhpVariableValue $baseName (New-PhpArray) }
                }
                $array=Invoke-PhpExpr $node.Base
                if (-not (Is-PhpArray $array)) { throw 'ALL PHP: Reference index requires array' }
                if ($null -eq $node.Key) {
                    $key='i:' + [string]$array.NextIndex
                    $array.NextIndex++
                } else {
                    $key=To-PhpKey (Invoke-PhpExpr $node.Key)
                    if ($key.StartsWith('i:')) {
                        $numeric=[long]$key.Substring(2)
                        if ($numeric -ge $array.NextIndex) { $array.NextIndex=$numeric+1 }
                    }
                }
                return [pscustomobject]@{ Store=$array.Items; Key=$key }
            }
            if ($node.Kind -eq 'property') {
                if ($node.NullSafe) { throw 'ALL PHP: Nullsafe property is not a reference target' }
                $object=Invoke-PhpExpr $node.Base
                if (-not (Is-PhpObject $object)) { throw 'ALL PHP: Reference property requires object' }
                if ($object.PSObject.Properties['EnumCase']) {
                    throw 'ALL PHP: Enum case properties cannot be referenced'
                }
                if ($object.Class -ne 'stdClass') {
                    $declared=Find-PhpProperty $object.Class $node.Name $false
                    if ($null -ne $declared) {
                        Assert-PhpVisibility $declared.Visibility $declared.Owner
                    }
                }
                $present=if ($object.Props -is [System.Collections.Specialized.OrderedDictionary]) {
                    $object.Props.Contains($node.Name)
                } else { $object.Props.ContainsKey($node.Name) }
                if (-not $present -and
                    $null -ne (Find-OptionalPhpMethod $object.Class '__get')) {
                    throw 'ALL PHP: Cannot bind __get result by reference without reference return semantics'
                }
                return [pscustomobject]@{ Store=$object.Props; Key=$node.Name }
            }
            if ($node.Kind -eq 'static_property') {
                $klass=Resolve-PhpClass ([string](Invoke-PhpExpr $node.Base))
                $prop=Find-PhpProperty $klass $node.Name $true
                if ($null -eq $prop) { throw 'ALL PHP: Undefined static property reference' }
                Assert-PhpVisibility $prop.Visibility $prop.Owner
                return [pscustomobject]@{
                    Store=$state.Classes[$prop.Owner].StaticValues; Key=$node.Name
                }
            }
            throw 'ALL PHP: Reference requires a writable expression'
        }
        function Get-PhpLValueCell($node) {
            $slot=Resolve-PhpLValueSlot $node
            $present=if ($slot.Store -is [System.Collections.Specialized.OrderedDictionary]) {
                $slot.Store.Contains($slot.Key)
            } else { $slot.Store.ContainsKey($slot.Key) }
            $previous=$null
            if ($present) {
                $previous=$slot.Store[$slot.Key]
                if (Is-PhpRefCell $previous) { return $previous }
            }
            $cell=[pscustomobject]@{
                PhpType='refcell'; Value=(Copy-PhpValue $previous)
            }
            $slot.Store[$slot.Key]=$cell
            return $cell
        }
        function Set-PhpReferenceTarget($target, $cell) {
            if (-not (Is-PhpRefCell $cell)) { throw 'ALL PHP: Internal reference cell missing' }
            $slot=Resolve-PhpLValueSlot $target
            $slot.Store[$slot.Key]=$cell
        }
        function Evaluate-PhpUserArguments($expressions, $definition) {
            $args=[System.Collections.Generic.List[object]]::new()
            $position=0
            foreach ($arg in $expressions) {
                $name=$null
                $expr=$arg
                if ($arg.Kind -ceq 'named_argument') {
                    $name=$arg.Name
                    $expr=$arg.Expr
                }
                $param=$null
                if ($null -ne $name) {
                    foreach ($candidate in $definition.Params) {
                        if ($candidate.Name -ceq $name) { $param=$candidate; break }
                    }
                    if ($null -eq $param) {
                        foreach ($candidate in $definition.Params) {
                            if ($candidate.Variadic) { $param=$candidate; break }
                        }
                    }
                } else {
                    if ($position -lt $definition.Params.Count) {
                        $param=$definition.Params[$position]
                        if (-not $param.Variadic) { $position++ }
                    }
                }
                if ($null -ne $param -and $param.ByRef -and
                    $expr.Kind -in @('variable','dynamic_variable','index','property','static_property')) {
                    $cell=Get-PhpLValueCell $expr
                    $value=[pscustomobject]@{
                        PhpType='refargument'; Cell=$cell; Value=(Copy-PhpValue $cell.Value)
                    }
                } else { $value=Invoke-PhpExpr $expr }
                if ($null -ne $name) {
                    [void]$args.Add([pscustomobject]@{
                        PhpType='named_argument'; Name=$name; Value=$value
                    })
                } else { [void]$args.Add($value) }
            }
            return ,($args.ToArray())
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
            if (Is-PhpRefCell $value) { $value=$value.Value }
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
            if (Is-PhpObject $value) {
                $magic=Find-OptionalPhpMethod $value.Class '__toString'
                if ($null -ne $magic) {
                    $converted=Invoke-PhpMethod $value '__toString' @()
                    if ($converted -is [string]) { return $converted }
                    if ($converted -is [decimal] -or $converted -is [bool]) {
                        return (To-PhpText $converted)
                    }
                    throw 'ALL PHP: __toString must return string'
                }
                throw 'ALL PHP: Object to string conversion is not supported'
            }
            return [string]$value
        }
        function To-Number($value) {
            if (Is-PhpRefCell $value) { $value=$value.Value }
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
            if (Is-PhpRefCell $value) { $value=$value.Value }
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
            if ($array.Items.Contains($keyString) -and
                (Is-PhpRefCell $array.Items[$keyString])) {
                $array.Items[$keyString].Value = Copy-PhpValue $value
            } else {
                $array.Items[$keyString] = Copy-PhpValue $value
            }
        }
        function Get-PhpArrayItem($array, $key) {
            if (-not (Is-PhpArray $array)) { throw 'ALL PHP: Indexing requires array' }
            $keyString = To-PhpKey $key
            if (-not $array.Items.Contains($keyString)) {
                throw "ALL PHP: Undefined array key '$keyString'"
            }
            $value = $array.Items[$keyString]
            if (Is-PhpRefCell $value) { return $value.Value }
            return $value
        }
        function Compare-PhpArrays($a, $b, [bool]$strict, [int]$depth = 0) {
            if ($depth -ge 64) { throw 'ALL PHP: Array comparison recursion depth exceeded' }
            if ($a.Items.Count -ne $b.Items.Count) { return $false }
            if ($strict) {
                $aKeys = @($a.Items.Keys)
                $bKeys = @($b.Items.Keys)
                for ($i=0; $i -lt $aKeys.Count; $i++) {
                    if ([string]$aKeys[$i] -cne [string]$bKeys[$i]) { return $false }
                    $x = $a.Items[$aKeys[$i]]
                    $y = $b.Items[$bKeys[$i]]
                    if (-not (Php-Equal $x $y $true ($depth + 1))) { return $false }
                }
                return $true
            }
            foreach ($key in $a.Items.Keys) {
                if (-not $b.Items.Contains($key)) { return $false }
                if (-not (Php-Equal $a.Items[$key] $b.Items[$key] $false ($depth + 1))) {
                    return $false
                }
            }
            return $true
        }
        function Php-Equal($a, $b, [bool]$strict, [int]$depth = 0) {
            if (Is-PhpRefCell $a) { $a=$a.Value }
            if (Is-PhpRefCell $b) { $b=$b.Value }
            if ((Is-PhpArray $a) -or (Is-PhpArray $b)) {
                if (-not (Is-PhpArray $a) -or -not (Is-PhpArray $b)) { return $false }
                return (Compare-PhpArrays $a $b $strict $depth)
            }
            if ((Is-PhpObject $a) -or (Is-PhpObject $b)) {
                if (-not (Is-PhpObject $a) -or -not (Is-PhpObject $b)) { return $false }
                if ($strict) { return [object]::ReferenceEquals($a, $b) }
                if ($a.Class -cne $b.Class -or $a.Props.Count -ne $b.Props.Count) {
                    return $false
                }
                foreach ($key in $a.Props.Keys) {
                    $exists=if ($b.Props -is [System.Collections.Specialized.OrderedDictionary]) {
                        $b.Props.Contains($key)
                    } else { $b.Props.ContainsKey([string]$key) }
                    if (-not $exists) { return $false }
                    if (-not (Php-Equal $a.Props[$key] $b.Props[$key] $false ($depth + 1))) {
                        return $false
                    }
                }
                return $true
            }
            if ($strict) {
                if ($null -eq $a -or $null -eq $b) {
                    return ($null -eq $a -and $null -eq $b)
                }
                if ($a.GetType() -ne $b.GetType()) { return $false }
                if ($a -is [string]) { return ($a -ceq $b) }
                return ($a -eq $b)
            }
            return ((Compare-Values $a $b) -eq 0)
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
            return (Php-Equal $a $b $true)
        }
        function Resolve-PhpClass([string]$name) {
            if ($name -in @('self','parent','static')) {
                if ($null -eq $state.ClassContext) {
                    throw "ALL PHP: '$name' used outside class context"
                }
                if ($name -eq 'self') { return $state.ClassContext }
                if ($name -eq 'parent') {
                    $base=$state.Classes[$state.ClassContext]
                    if ($null -eq $base -or $null -eq $base.Parent) {
                        throw 'ALL PHP: No parent class'
                    }
                    return $base.Parent
                }
                if ($state.Vars.ContainsKey('this')) { return (Get-PhpVariableValue 'this').Class }
                return $state.ClassContext
            }
            return $name
        }
        function Copy-PhpTraitMethod($method, [string]$newName, [string]$visibility) {
            if ([string]::IsNullOrEmpty($visibility)) { $visibility=$method.Visibility }
            return [pscustomobject]@{
                Kind='functiondef'; Name=$newName
                Params=$method.Params; Body=$method.Body; Expr=$method.Expr
                Visibility=$visibility; Static=$method.Static
                Owner=$method.Owner; Abstract=$method.Abstract; Final=$method.Final
            }
        }
        function Get-PhpTraitComposition($declaration) {
            $resultMethods=[System.Collections.Generic.Dictionary[string,object]]::new(
                [System.StringComparer]::OrdinalIgnoreCase)
            $resultProperties=[System.Collections.Generic.List[object]]::new()
            foreach ($use in $declaration.TraitUses) {
                $selected=[System.Collections.Generic.Dictionary[string,object]]::new(
                    [System.StringComparer]::OrdinalIgnoreCase)
                $excluded=[System.Collections.Generic.HashSet[string]]::new(
                    [System.StringComparer]::OrdinalIgnoreCase)
                foreach ($traitName in $use.Names) {
                    if (-not $state.Traits.ContainsKey($traitName)) {
                        throw "ALL PHP: Undefined trait '$traitName'"
                    }
                }
                foreach ($rule in $use.Adaptations) {
                    if ($rule.Kind -ne 'insteadof') { continue }
                    if ($rule.Trait -notin $use.Names) {
                        throw 'ALL PHP: Trait selection names a trait not used in this group'
                    }
                    $winner=$state.Traits[$rule.Trait]
                    $winnerMethod=@($winner.Methods | Where-Object { $_.Name -ieq $rule.Method })
                    if ($winnerMethod.Count -eq 0) {
                        throw "ALL PHP: Trait method '$($rule.Method)' not defined"
                    }
                    foreach ($loserName in $rule.Excluded) {
                        if ($loserName -notin $use.Names -or $loserName -ieq $rule.Trait) {
                            throw 'ALL PHP: Invalid insteadof trait selection'
                        }
                        [void]$excluded.Add(($rule.Method + '|' + $loserName))
                    }
                }
                foreach ($traitName in $use.Names) {
                    $trait=$state.Traits[$traitName]
                    foreach ($method in $trait.Methods) {
                        if ($excluded.Contains(($method.Name + '|' + $traitName))) { continue }
                        $methodCopy=Copy-PhpTraitMethod $method $method.Name ''
                        foreach ($rule in $use.Adaptations) {
                            if ($rule.Kind -ne 'alias' -or $null -ne $rule.Alias) { continue }
                            if ($rule.Method -ine $method.Name) { continue }
                            if ($null -ne $rule.Trait -and $rule.Trait -ine $traitName) { continue }
                            $methodCopy.Visibility=$rule.Visibility
                        }
                        if ($resultMethods.ContainsKey($method.Name)) {
                            throw "ALL PHP: Conflicting trait method '$($method.Name)'"
                        }
                        $resultMethods[$method.Name]=$methodCopy
                    }
                    foreach ($prop in $trait.Properties) {
                        foreach ($prior in $resultProperties) {
                            if ($prior.Name -ceq $prop.Name) {
                                throw "ALL PHP: Conflicting trait property '$($prop.Name)'"
                            }
                        }
                        [void]$resultProperties.Add($prop)
                    }
                }
                foreach ($rule in $use.Adaptations) {
                    if ($rule.Kind -ne 'alias') { continue }
                    if ($null -eq $rule.Alias) { continue }
                    $origin=$null
                    foreach ($traitName in $use.Names) {
                        if ($null -ne $rule.Trait -and $rule.Trait -ine $traitName) { continue }
                        foreach ($method in $state.Traits[$traitName].Methods) {
                            if ($method.Name -ine $rule.Method) { continue }
                            if ($null -ne $origin) {
                                throw 'ALL PHP: Ambiguous unqualified trait alias'
                            }
                            $origin=$method
                        }
                    }
                    if ($null -eq $origin) { throw 'ALL PHP: Trait alias method not found' }
                    if ($resultMethods.ContainsKey($rule.Alias)) {
                        throw "ALL PHP: Conflicting trait method '$($rule.Alias)'"
                    }
                    $resultMethods[$rule.Alias]=Copy-PhpTraitMethod $origin $rule.Alias $rule.Visibility
                }
            }
            return [pscustomobject]@{
                Methods=@($resultMethods.Values); Properties=$resultProperties.ToArray()
            }
        }
        function Get-PhpClassChain([string]$className) {
            $name=Resolve-PhpClass $className
            $chain=[System.Collections.Generic.List[object]]::new()
            for ($depth=0; $depth -lt 64 -and $null -ne $name; $depth++) {
                if (-not $state.Classes.ContainsKey($name)) {
                    throw "ALL PHP: Undefined class '$name'"
                }
                $item=$state.Classes[$name]
                foreach ($prior in $chain) {
                    if ($prior.Name -ieq $item.Name) { throw 'ALL PHP: Cyclic class inheritance' }
                }
                [void]$chain.Add($item)
                $name=$item.Parent
            }
            if ($null -ne $name) { throw 'ALL PHP: Class inheritance depth exceeded' }
            return ,($chain.ToArray())
        }
        function Get-PhpInterfaceChain([string]$name) {
            $result=[System.Collections.Generic.List[object]]::new()
            $pending=[System.Collections.Generic.Queue[string]]::new()
            $seen=[System.Collections.Generic.HashSet[string]]::new(
                [System.StringComparer]::OrdinalIgnoreCase)
            $pending.Enqueue($name)
            while ($pending.Count -gt 0) {
                $item=$pending.Dequeue()
                if (-not $state.Interfaces.ContainsKey($item)) {
                    throw "ALL PHP: Undefined interface '$item'"
                }
                if (-not $seen.Add($item)) { continue }
                $iface=$state.Interfaces[$item]
                [void]$result.Add($iface)
                foreach ($parent in $iface.Parents) { $pending.Enqueue($parent) }
            }
            return ,($result.ToArray())
        }
        function Test-PhpImplements([string]$className, [string]$interfaceName) {
            foreach ($cls in (Get-PhpClassChain $className)) {
                foreach ($name in $cls.Interfaces) {
                    foreach ($iface in (Get-PhpInterfaceChain $name)) {
                        if ($iface.Name -ieq $interfaceName) { return $true }
                    }
                }
            }
            return $false
        }
        function Assert-PhpMethodSignature($implementation, $required, [string]$context) {
            if ([bool]$implementation.Static -ne [bool]$required.Static) {
                throw "ALL PHP: Static/non-static method mismatch for '$context'"
            }
            $requiredMin=0
            foreach ($param in $required.Params) {
                if (-not $param.Variadic -and $null -eq $param.Default) { $requiredMin++ }
            }
            $actualMin=0
            $actualVariadic=$false
            foreach ($param in $implementation.Params) {
                if ($param.Variadic) { $actualVariadic=$true }
                elseif ($null -eq $param.Default) { $actualMin++ }
            }
            if ($actualMin -gt $requiredMin) {
                throw "ALL PHP: Incompatible method signature for '$context'"
            }
            if (-not $actualVariadic -and $implementation.Params.Count -lt $required.Params.Count) {
                throw "ALL PHP: Incompatible method signature for '$context'"
            }
            if ($required.Visibility -eq 'public' -and $implementation.Visibility -ne 'public') {
                throw "ALL PHP: Cannot reduce method visibility for '$context'"
            }
            if ($required.Visibility -eq 'protected' -and $implementation.Visibility -eq 'private') {
                throw "ALL PHP: Cannot reduce method visibility for '$context'"
            }
        }
        function Test-PhpInstanceOf([string]$actual, [string]$target) {
            if ($actual -ieq $target) { return $true }
            if ($state.Classes.ContainsKey($actual) -and
                $state.Classes[$actual].PSObject.Properties['Enum'] -and
                $state.Classes[$actual].Enum) {
                if ($target -ieq 'UnitEnum') { return $true }
                if ($target -ieq 'BackedEnum') {
                    return ($null -ne $state.Classes[$actual].BackingType)
                }
            }
            if ($actual -eq 'stdClass') { return $false }
            foreach ($cls in (Get-PhpClassChain $actual)) {
                if ($cls.Name -ieq $target) { return $true }
            }
            if ($state.Interfaces.ContainsKey($target)) {
                return (Test-PhpImplements $actual $target)
            }
            return $false
        }
        function Find-PhpMethod([string]$className, [string]$methodName) {
            foreach ($cls in (Get-PhpClassChain $className)) {
                if ($cls.Methods.ContainsKey($methodName)) {
                    return $cls.Methods[$methodName]
                }
            }
            throw "ALL PHP: Undefined method '$methodName'"
        }
        function Find-OptionalPhpMethod([string]$className, [string]$methodName) {
            if ($className -eq 'stdClass') { return $null }
            try { return (Find-PhpMethod $className $methodName) }
            catch {
                if ($_.Exception.Message -notlike 'ALL PHP: Undefined method*') { throw }
                return $null
            }
        }
        function Find-PhpProperty([string]$className, [string]$propertyName, [bool]$staticOnly) {
            foreach ($cls in (Get-PhpClassChain $className)) {
                foreach ($prop in $cls.Properties) {
                    if ($prop.Name -ceq $propertyName -and [bool]$prop.Static -eq $staticOnly) {
                        return $prop
                    }
                }
            }
            return $null
        }
        function Assert-PhpVisibility([string]$visibility, [string]$owner) {
            if ($visibility -eq 'public') { return }
            if ($null -eq $state.ClassContext) {
                if ($visibility -eq 'private') { throw 'ALL PHP: Cannot access private member' }
                throw 'ALL PHP: Cannot access protected member'
            }
            if ($visibility -eq 'private' -and $state.ClassContext -ine $owner) {
                throw 'ALL PHP: Cannot access private member'
            }
            if ($visibility -eq 'protected' -and
                -not (Test-PhpInstanceOf $state.ClassContext $owner) -and
                -not (Test-PhpInstanceOf $owner $state.ClassContext)) {
                throw 'ALL PHP: Cannot access protected member'
            }
        }
        function Get-PhpStaticProperty($node) {
            $klass = Resolve-PhpClass ([string](Invoke-PhpExpr $node.Base))
            $prop = Find-PhpProperty $klass $node.Name $true
            if ($null -eq $prop) { throw "ALL PHP: Undefined static property '$($node.Name)'" }
            Assert-PhpVisibility $prop.Visibility $prop.Owner
            $result = $state.Classes[$prop.Owner].StaticValues[$node.Name]
            if (Is-PhpRefCell $result) { return $result.Value }
            return $result
        }
        function Set-PhpStaticProperty($node, $value) {
            $klass = Resolve-PhpClass ([string](Invoke-PhpExpr $node.Base))
            $prop = Find-PhpProperty $klass $node.Name $true
            if ($null -eq $prop) { throw "ALL PHP: Undefined static property '$($node.Name)'" }
            Assert-PhpVisibility $prop.Visibility $prop.Owner
            $store = $state.Classes[$prop.Owner].StaticValues
            if (Is-PhpRefCell $store[$node.Name]) {
                $store[$node.Name].Value = Copy-PhpValue $value
            } else { $store[$node.Name] = Copy-PhpValue $value }
        }
        function Resolve-PhpDynamicVariableName($node) {
            $value = Invoke-PhpExpr $node.NameExpr
            if ($null -eq $value) { return '' }
            if ($value -isnot [string] -and $value -isnot [decimal] -and
                $value -isnot [bool]) {
                throw 'ALL PHP: Invalid dynamic variable name type'
            }
            $name=To-PhpText $value
            if ($name -eq 'this') {
                throw 'ALL PHP: Cannot access $this dynamically'
            }
            return $name
        }
        function Get-LValue($node) {
            if ($node.Kind -eq 'dynamic_variable') {
                return (Get-PhpVariableValue (Resolve-PhpDynamicVariableName $node))
            }
            if ($node.Kind -eq 'variable') {
                return (Get-PhpVariableValue $node.Name)
            }
            if ($node.Kind -eq 'index') {
                if ($null -eq $node.Key) { throw 'ALL PHP: Cannot read an empty [] index' }
                return (Get-PhpArrayItem (Invoke-PhpExpr $node.Base) (Invoke-PhpExpr $node.Key))
            }
            if ($node.Kind -eq 'static_property') {
                return (Get-PhpStaticProperty $node)
            }
            if ($node.Kind -eq 'property') {
                $base = Invoke-PhpExpr $node.Base
                if ($node.NullSafe -and $null -eq $base) { return $null }
                if (-not (Is-PhpObject $base)) { throw 'ALL PHP: Property access requires object' }
                if ($base.Class -ne 'stdClass') {
                    $declared = Find-PhpProperty $base.Class $node.Name $false
                    if ($null -ne $declared) {
                        Assert-PhpVisibility $declared.Visibility $declared.Owner
                    }
                }
                $present = if ($base.Props -is [System.Collections.Specialized.OrderedDictionary]) {
                    $base.Props.Contains($node.Name)
                } else { $base.Props.ContainsKey($node.Name) }
                if (-not $present) {
                    $magic=Find-OptionalPhpMethod $base.Class '__get'
                    if ($null -ne $magic) {
                        $guardKey=([string]$base.GetHashCode() + ':' + $node.Name)
                        if (-not $state.MagicGetActive.Add($guardKey)) {
                            throw 'ALL PHP: Recursive __get property access'
                        }
                        try { return (Invoke-PhpMethod $base '__get' @($node.Name)) }
                        finally { [void]$state.MagicGetActive.Remove($guardKey) }
                    }
                    throw "ALL PHP: Undefined property '$($node.Name)'"
                }
                $value=$base.Props[$node.Name]
                if (Is-PhpRefCell $value) { return $value.Value }
                return $value
            }
            throw 'ALL PHP: Not a readable value'
        }
        function Set-LValue($node, $value, [string]$op) {
            if ($node.Kind -eq 'array') {
                if ($op -cne '=' -or -not (Is-PhpArray $value)) {
                    throw 'ALL PHP: Destructuring requires array and plain assignment'
                }
                $numeric = [decimal]0
                foreach ($item in $node.Entries) {
                    if ($item.Spread) { throw 'ALL PHP: Cannot unpack into a destructuring target' }
                    $key=$numeric
                    if ($null -ne $item.Key) { $key=Invoke-PhpExpr $item.Key }
                    else { $numeric++ }
                    if ($item.Value.Kind -notin @('variable','dynamic_variable','index','property','static_property','array')) {
                        throw 'ALL PHP: Invalid destructuring target'
                    }
                    $found=$false
                    $part=$null
                    try { $part=Get-PhpArrayItem $value $key; $found=$true }
                    catch {
                        if ($_.Exception.Message -notlike 'ALL PHP: Undefined array key*') { throw }
                    }
                    if (-not $found) { $part=$null }
                    Set-LValue $item.Value $part '='
                }
                return
            }
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
                    '&=' { $value = [decimal]([long](To-Number $previous) -band [long](To-Number $value)) }
                    '|=' { $value = [decimal]([long](To-Number $previous) -bor [long](To-Number $value)) }
                    '^=' { $value = [decimal]([long](To-Number $previous) -bxor [long](To-Number $value)) }
                    '<<=' { $value = [decimal]([long](To-Number $previous) -shl [int](To-Number $value)) }
                    '>>=' { $value = [decimal]([long](To-Number $previous) -shr [int](To-Number $value)) }
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
            if ($node.Kind -eq 'dynamic_variable') {
                Set-PhpVariableValue (Resolve-PhpDynamicVariableName $node) $value
                return
            }
            if ($node.Kind -eq 'variable') {
                Set-PhpVariableValue $node.Name $value
                return
            }
            if ($node.Kind -eq 'static_property') {
                Set-PhpStaticProperty $node $value
                return
            }
            if ($node.Kind -eq 'index') {
                if ($node.Base.Kind -in @('variable','dynamic_variable')) {
                    $baseName=if ($node.Base.Kind -eq 'variable') {
                        $node.Base.Name
                    } else { Resolve-PhpDynamicVariableName $node.Base }
                    $baseValue=$null
                    try { $baseValue=Get-PhpVariableValue $baseName }
                    catch {
                        if ($_.Exception.Message -notlike 'ALL PHP: Undefined variable*') { throw }
                    }
                    if ($null -eq $baseValue) {
                        Set-PhpVariableValue $baseName (New-PhpArray)
                    }
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
                if ($base.PSObject.Properties['EnumCase']) {
                    throw 'ALL PHP: Cannot modify enum case property'
                }
                $declared=$null
                if ($base.Class -ne 'stdClass') {
                    $declared = Find-PhpProperty $base.Class $node.Name $false
                    if ($null -ne $declared) {
                        Assert-PhpVisibility $declared.Visibility $declared.Owner
                    }
                }
                $present=if ($base.Props -is [System.Collections.Specialized.OrderedDictionary]) {
                    $base.Props.Contains($node.Name)
                } else { $base.Props.ContainsKey($node.Name) }
                if ($null -eq $declared -and -not $present) {
                    $magic=Find-OptionalPhpMethod $base.Class '__set'
                    if ($null -ne $magic) {
                        $guardKey=([string]$base.GetHashCode() + ':' + $node.Name)
                        if ($state.MagicSetActive.Add($guardKey)) {
                            try {
                                [void](Invoke-PhpMethod $base '__set' @($node.Name, (Copy-PhpValue $value)))
                                return
                            } finally { [void]$state.MagicSetActive.Remove($guardKey) }
                        }
                    }
                }
                if ($present -and (Is-PhpRefCell $base.Props[$node.Name])) {
                    $base.Props[$node.Name].Value = Copy-PhpValue $value
                } else { $base.Props[$node.Name] = Copy-PhpValue $value }
                return
            }
            throw 'ALL PHP: Invalid assignment target'
        }
        function Invoke-PhpCallable($definition, $callArgs, $object, [string]$owner = '', $closure = $null) {
            if ($definition.Abstract) { throw 'ALL PHP: Cannot invoke an abstract method' }
            if ($state.CallDepth -ge 64) { throw 'ALL PHP: Call depth limit reached (64)' }
            $oldVars = $state.Vars
            $oldFlow = $state.Flow
            $oldGlobals = $state.GlobalBindings
            $oldStatics = $state.StaticBindings
            $oldCallable = $state.CurrentCallable
            $oldContext = $state.ClassContext
            $state.Vars = [System.Collections.Generic.Dictionary[string,object]]::new(
                [System.StringComparer]::Ordinal)
            $state.Flow = @{ Returned=$false; Value=$null; LoopControl=$null; LoopDepth=0 }
            $state.GlobalBindings = [System.Collections.Generic.HashSet[string]]::new(
                [System.StringComparer]::Ordinal)
            $state.StaticBindings = [System.Collections.Generic.HashSet[string]]::new(
                [System.StringComparer]::Ordinal)
            $state.ClassContext = if ($owner.Length -gt 0) { $owner } else { $null }
            $state.CurrentCallable = if ($owner.Length -gt 0) { $owner + '::' + $definition.Name } else { $definition.Name }
            $state.CallDepth++
            try {
                if ($null -ne $closure) {
                    $state.ClassContext=$closure.ClassContext
                    foreach ($capturedName in $closure.Captures.Keys) {
                        $captured=$closure.Captures[$capturedName]
                        if (Is-PhpRefCell $captured) {
                            $state.Vars[$capturedName]=$captured
                        } else {
                            $state.Vars[$capturedName]=Copy-PhpValue $captured
                        }
                    }
                }
                $bound = [System.Collections.Generic.Dictionary[string,object]]::new(
                    [System.StringComparer]::Ordinal)
                $position = 0
                $namedStarted = $false
                $extra = [System.Collections.Generic.List[object]]::new()
                foreach ($arg in $callArgs) {
                    if ($null -ne $arg -and $arg.PSObject.Properties['PhpType'] -and
                        $arg.PhpType -ceq 'named_argument') {
                        $namedStarted = $true
                        $known = $false
                        foreach ($param in $definition.Params) {
                            if ($param.Name -ceq $arg.Name) { $known=$true; break }
                        }
                        if (-not $known) {
                            $variadicParam=$null
                            foreach ($candidate in $definition.Params) {
                                if ($candidate.Variadic) { $variadicParam=$candidate; break }
                            }
                            if ($null -eq $variadicParam) {
                                throw "ALL PHP: Unknown named parameter '$($arg.Name)'"
                            }
                            [void]$extra.Add($arg)
                            continue
                        }
                        if ($bound.ContainsKey($arg.Name)) { throw 'ALL PHP: Named parameter overwrites previous argument' }
                        $bound[$arg.Name] = Copy-PhpValue $arg.Value
                    } else {
                        if ($namedStarted) { throw 'ALL PHP: Positional argument after named argument' }
                        if ($position -lt $definition.Params.Count) {
                            $param = $definition.Params[$position]
                            if ($param.Variadic) { [void]$extra.Add((Copy-PhpValue $arg)) }
                            else { $bound[$param.Name] = Copy-PhpValue $arg; $position++ }
                        } else { [void]$extra.Add((Copy-PhpValue $arg)) }
                    }
                }
                foreach ($param in $definition.Params) {
                    if ($param.Variadic) {
                        $varargs = New-PhpArray
                        foreach ($extraArg in $extra) {
                            $element=$extraArg
                            $key=$null
                            if ($null -ne $extraArg -and $extraArg.PSObject.Properties['PhpType'] -and
                                $extraArg.PhpType -ceq 'named_argument') {
                                $key=$extraArg.Name
                                $element=$extraArg.Value
                            }
                            $isReferenceArgument=($null -ne $element -and
                                $element.PSObject.Properties['PhpType'] -and
                                $element.PhpType -ceq 'refargument')
                            if ($param.ByRef) {
                                if (-not $isReferenceArgument) {
                                    throw "ALL PHP: must be a variable passed by reference (argument '$($param.Name)')"
                                }
                                $element=$element.Cell
                            } elseif ($isReferenceArgument) { $element=$element.Value }
                            Set-PhpArrayItem $varargs $key $element ($null -eq $key)
                        }
                        if ($bound.ContainsKey($param.Name)) {
                            $named=$bound[$param.Name]
                            if ($param.ByRef -and ($null -eq $named -or
                                $named.PhpType -cne 'refargument')) {
                                throw "ALL PHP: must be a variable passed by reference (argument '$($param.Name)')"
                            }
                            if ($param.ByRef) { $named=$named.Cell }
                            Set-PhpArrayItem $varargs $param.Name $named $false
                        }
                        $state.Vars[$param.Name] = $varargs
                    } elseif ($bound.ContainsKey($param.Name)) {
                        $provided=$bound[$param.Name]
                        $isReferenceArgument=($null -ne $provided -and
                            $provided.PSObject.Properties['PhpType'] -and
                            $provided.PhpType -ceq 'refargument')
                        if ($param.ByRef) {
                            if (-not $isReferenceArgument) {
                                throw "ALL PHP: must be a variable passed by reference (argument '$($param.Name)')"
                            }
                            $state.Vars[$param.Name]=$provided.Cell
                        } else {
                            if ($isReferenceArgument) { $provided=$provided.Value }
                            $state.Vars[$param.Name] = Copy-PhpValue $provided
                        }
                    } elseif ($null -ne $param.Default) {
                        $state.Vars[$param.Name] = Copy-PhpValue (Invoke-PhpExpr $param.Default)
                    } else {
                        throw "ALL PHP: Too few arguments for $($definition.Name)"
                    }
                }
                if ($null -ne $object) { $state.Vars['this'] = $object }
                if ($null -ne $definition.Expr) {
                    return (Invoke-PhpExpr $definition.Expr)
                }
                Invoke-PhpStatement $definition.Body
                return $state.Flow.Value
            } finally {
                $state.CallDepth--
                $state.Vars = $oldVars
                $state.Flow = $oldFlow
                $state.GlobalBindings = $oldGlobals
                $state.StaticBindings = $oldStatics
                $state.CurrentCallable = $oldCallable
                $state.ClassContext = $oldContext
            }
        }
        function KeyString-ToValue([string]$encoded) {
            if ($encoded.StartsWith('i:')) { return [decimal]$encoded.Substring(2) }
            return $encoded.Substring(2)
        }
        function Invoke-PhpFunction([string]$name, $callArgs) {
            if (-not $state.Functions.ContainsKey($name)) {
                foreach ($arg in $callArgs) {
                    if ($null -ne $arg -and $arg.PSObject.Properties['PhpType'] -and
                        $arg.PhpType -ceq 'named_argument') {
                        throw 'ALL PHP: Named arguments for builtins are not yet supported'
                    }
                }
            }
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
                    if (Is-PhpRefCell $lastValue) { return $lastValue.Value }
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
                    if (Is-PhpRefCell $firstValue) { return $firstValue.Value }
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
                        $value=$callArgs[0].Items[$key]
                        if (Is-PhpRefCell $value) { return $value.Value }
                        return $value
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
                    if (Is-PhpRefCell $last) { return $last.Value }
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
            if ($object.Class -eq 'stdClass') { throw 'ALL PHP: stdClass does not define methods' }
            $method=Find-PhpMethod $object.Class $name
            Assert-PhpVisibility $method.Visibility $method.Owner
            if ($method.Static) {
                return (Invoke-PhpCallable $method $callArgs $null $method.Owner)
            }
            return (Invoke-PhpCallable $method $callArgs $object $method.Owner)
        }
        function Invoke-PhpStaticMethod([string]$className, [string]$methodName, $callArgs) {
            $className=Resolve-PhpClass $className
            $method=Find-PhpMethod $className $methodName
            Assert-PhpVisibility $method.Visibility $method.Owner
            if ($method.Static) { return (Invoke-PhpCallable $method $callArgs $null $method.Owner) }
            if ($state.Vars.ContainsKey('this')) {
                $object=Get-PhpVariableValue 'this'
                if (Is-PhpObject $object) {
                    return (Invoke-PhpCallable $method $callArgs $object $method.Owner)
                }
            }
            throw 'ALL PHP: Non-static method cannot be called statically'
        }
        function Get-PhpClassConstant([string]$className, [string]$constName) {
            $className=Resolve-PhpClass $className
            if ($constName -ceq 'class') { return $className }
            if ($state.Classes.ContainsKey($className)) {
                foreach ($cls in (Get-PhpClassChain $className)) {
                    if ($cls.Constants.ContainsKey($constName)) {
                        $entry=$cls.Constants[$constName]
                        Assert-PhpVisibility $entry.Visibility $entry.Owner
                        return $entry.Value
                    }
                }
                foreach ($cls in (Get-PhpClassChain $className)) {
                    foreach ($name in $cls.Interfaces) {
                        foreach ($iface in (Get-PhpInterfaceChain $name)) {
                            if ($iface.Constants.ContainsKey($constName)) {
                                return $iface.Constants[$constName].Value
                            }
                        }
                    }
                }
            } elseif ($state.Interfaces.ContainsKey($className)) {
                foreach ($iface in (Get-PhpInterfaceChain $className)) {
                    if ($iface.Constants.ContainsKey($constName)) {
                        return $iface.Constants[$constName].Value
                    }
                }
            }
            throw "ALL PHP: Undefined class constant '$constName'"
        }
        function Invoke-PhpExpr($node) {
            switch ($node.Kind) {
                'literal' { return $node.Value }
                'class_name' { return $node.Name }
                'closure' {
                    $cap=[System.Collections.Generic.Dictionary[string,object]]::new(
                        [System.StringComparer]::Ordinal)
                    if ($node.Arrow) {
                        foreach ($name in @($state.Vars.Keys)) {
                            if ($name -eq 'this') { continue }
                            $cap[$name]=Copy-PhpValue (Get-PhpVariableValue $name)
                        }
                    } else {
                        foreach ($capture in $node.Captures) {
                            if ($capture.Name -eq 'this') { continue }
                            if ($capture.ByRef) {
                                $cap[$capture.Name]=Get-PhpVariableCell $capture.Name
                            } else {
                                $cap[$capture.Name]=Copy-PhpValue (Get-PhpVariableValue $capture.Name)
                            }
                        }
                    }
                    $bound=$null
                    if ($state.Vars.ContainsKey('this')) { $bound=Get-PhpVariableValue 'this' }
                    return [pscustomobject]@{
                        PhpType='closure'; Definition=$node; Captures=$cap
                        BoundThis=$bound; ClassContext=$state.ClassContext
                    }
                }
                'first_class_function' {
                    # Defer builtin argument evaluation until the closure is invoked.
                    return [pscustomobject]@{
                        PhpType='first_class_callable'; Mode='function'; Name=$node.Name
                    }
                }
                'first_class_method' {
                    $object=Invoke-PhpExpr $node.Base
                    if ($node.NullSafe -and $null -eq $object) { return $null }
                    if (-not (Is-PhpObject $object)) {
                        throw 'ALL PHP: First-class method callable requires object'
                    }
                    if ($null -eq (Find-OptionalPhpMethod $object.Class $node.Name)) {
                        throw "ALL PHP: Undefined method '$($node.Name)'"
                    }
                    return [pscustomobject]@{
                        PhpType='first_class_callable'; Mode='method'
                        Name=$node.Name; BoundThis=$object
                    }
                }
                'first_class_static' {
                    $klass=Resolve-PhpClass ([string](Invoke-PhpExpr $node.Base))
                    if ($null -eq (Find-OptionalPhpMethod $klass $node.Name)) {
                        throw "ALL PHP: Undefined static method '$($node.Name)'"
                    }
                    return [pscustomobject]@{
                        PhpType='first_class_callable'; Mode='static'
                        Name=$node.Name; Class=$klass
                    }
                }
                'first_class_invoke' {
                    $callable=Invoke-PhpExpr $node.Callee
                    if ($null -ne $callable -and $callable -is [string]) {
                        return [pscustomobject]@{
                            PhpType='first_class_callable'; Mode='function'; Name=$callable
                        }
                    }
                    if ($null -ne $callable -and $callable.PSObject.Properties['PhpType'] -and
                        $callable.PhpType -eq 'closure') { return $callable }
                    if (Is-PhpObject $callable) {
                        if ($null -eq (Find-OptionalPhpMethod $callable.Class '__invoke')) {
                            throw 'ALL PHP: Value is not callable'
                        }
                        return [pscustomobject]@{
                            PhpType='first_class_callable'; Mode='method'
                            Name='__invoke'; BoundThis=$callable
                        }
                    }
                    throw 'ALL PHP: Value is not callable'
                }
                'invoke' {
                    $callee=Invoke-PhpExpr $node.Callee
                    if ($null -ne $callee -and $callee.PSObject.Properties['PhpType'] -and
                        $callee.PhpType -ceq 'closure') {
                        $args=Evaluate-PhpUserArguments $node.Args $callee.Definition
                        return (Invoke-PhpCallable $callee.Definition $args $callee.BoundThis '' $callee)
                    }
                    if ($null -ne $callee -and $callee.PSObject.Properties['PhpType'] -and
                        $callee.PhpType -eq 'first_class_callable') {
                        if ($callee.Mode -eq 'function') {
                            if ($state.Functions.ContainsKey($callee.Name)) {
                                $def=$state.Functions[$callee.Name]
                                $args=Evaluate-PhpUserArguments $node.Args $def
                                return (Invoke-PhpCallable $def $args $null)
                            }
                            $args=[System.Collections.Generic.List[object]]::new()
                            foreach ($arg in $node.Args) {
                                if ($arg.Kind -eq 'named_argument') {
                                    [void]$args.Add([pscustomobject]@{
                                        PhpType='named_argument'; Name=$arg.Name
                                        Value=(Invoke-PhpExpr $arg.Expr)
                                    })
                                } else { [void]$args.Add((Invoke-PhpExpr $arg)) }
                            }
                            return (Invoke-PhpFunction $callee.Name ($args.ToArray()))
                        }
                        if ($callee.Mode -eq 'method') {
                            $def=Find-OptionalPhpMethod $callee.BoundThis.Class $callee.Name
                            $args=Evaluate-PhpUserArguments $node.Args $def
                            return (Invoke-PhpMethod $callee.BoundThis $callee.Name $args)
                        }
                        if ($callee.Mode -eq 'static') {
                            $def=Find-OptionalPhpMethod $callee.Class $callee.Name
                            $args=Evaluate-PhpUserArguments $node.Args $def
                            return (Invoke-PhpStaticMethod $callee.Class $callee.Name $args)
                        }
                        throw 'ALL PHP: Unknown first-class callable kind'
                    }
                    if (Is-PhpObject $callee) {
                        $magic=Find-OptionalPhpMethod $callee.Class '__invoke'
                        if ($null -eq $magic) { throw 'ALL PHP: Object is not callable' }
                        $args=Evaluate-PhpUserArguments $node.Args $magic
                        return (Invoke-PhpMethod $callee '__invoke' $args)
                    }
                    if ($callee -is [string] -and $state.Functions.ContainsKey($callee)) {
                        $args=Evaluate-PhpUserArguments $node.Args $state.Functions[$callee]
                        return (Invoke-PhpCallable $state.Functions[$callee] $args $null)
                    }
                    if ($callee -is [string]) {
                        $args=[System.Collections.Generic.List[object]]::new()
                        foreach ($arg in $node.Args) {
                            if ($arg.Kind -ceq 'named_argument') {
                                [void]$args.Add([pscustomobject]@{
                                    PhpType='named_argument'; Name=$arg.Name
                                    Value=(Invoke-PhpExpr $arg.Expr)
                                })
                            } else { [void]$args.Add((Invoke-PhpExpr $arg)) }
                        }
                        return (Invoke-PhpFunction $callee ($args.ToArray()))
                    }
                    throw 'ALL PHP: Value is not callable'
                }
                'static_property' { return (Get-LValue $node) }
                'class_const' {
                    $klass=[string](Invoke-PhpExpr $node.Base)
                    return (Get-PhpClassConstant $klass $node.Name)
                }
                'static_method' {
                    $klass=[string](Invoke-PhpExpr $node.Base)
                    $klass=Resolve-PhpClass $klass
                    if ($state.Classes.ContainsKey($klass) -and
                        $state.Classes[$klass].PSObject.Properties['Enum'] -and
                        $state.Classes[$klass].Enum) {
                        $enum=$state.Classes[$klass]
                        if ($node.Name -ceq 'cases') {
                            if ($node.Args.Count -ne 0) { throw 'ALL PHP: cases() takes no arguments' }
                            $result=New-PhpArray
                            foreach ($item in $enum.EnumCases) {
                                Set-PhpArrayItem $result $null $item $true
                            }
                            return $result
                        }
                        if ($node.Name -in @('from','tryFrom')) {
                            if ($null -eq $enum.BackingType) {
                                throw 'ALL PHP: Unit enums have no from() or tryFrom()'
                            }
                            if ($node.Args.Count -ne 1) {
                                throw 'ALL PHP: Enum from() requires one argument'
                            }
                            $needle=Invoke-PhpExpr $node.Args[0]
                            foreach ($item in $enum.EnumCases) {
                                if ($enum.BackingType -eq 'string' -and $needle -is [string] -and
                                    $item.Props['value'] -ceq $needle) { return $item }
                                if ($enum.BackingType -eq 'int' -and $needle -is [decimal] -and
                                    $item.Props['value'] -eq $needle) { return $item }
                            }
                            if ($node.Name -ceq 'tryFrom') { return $null }
                            throw 'ALL PHP: ValueError: invalid backing value for enum'
                        }
                    }
                    $def=Find-OptionalPhpMethod $klass $node.Name
                    if ($null -ne $def) {
                        $args=Evaluate-PhpUserArguments $node.Args $def
                        return (Invoke-PhpStaticMethod $klass $node.Name $args)
                    }
                    $magic=Find-OptionalPhpMethod $klass '__callStatic'
                    if ($null -eq $magic) { throw "ALL PHP: Undefined method '$($node.Name)'" }
                    $collected=New-PhpArray
                    foreach ($arg in $node.Args) {
                        if ($arg.Kind -ceq 'named_argument') {
                            Set-PhpArrayItem $collected $arg.Name (Invoke-PhpExpr $arg.Expr) $false
                        } else {
                            Set-PhpArrayItem $collected $null (Invoke-PhpExpr $arg) $true
                        }
                    }
                    return (Invoke-PhpStaticMethod $klass '__callStatic' @($node.Name,$collected))
                }
                'clone' {
                    $original=Invoke-PhpExpr $node.Arg
                    if (-not (Is-PhpObject $original)) { throw 'ALL PHP: Cannot clone non-object' }
                    if ($original.PSObject.Properties['EnumCase']) {
                        throw 'ALL PHP: Trying to clone an uncloneable object of class enum'
                    }
                    if ($original.Props -is [System.Collections.Specialized.OrderedDictionary]) {
                        $props=[System.Collections.Specialized.OrderedDictionary]::new(
                            [System.StringComparer]::Ordinal)
                    } else {
                        $props=[System.Collections.Generic.Dictionary[string,object]]::new(
                            [System.StringComparer]::Ordinal)
                    }
                    foreach ($key in $original.Props.Keys) {
                        $props[$key]=Copy-PhpValue $original.Props[$key]
                    }
                    $copy=[pscustomobject]@{
                        PhpType='object'; Class=$original.Class; Props=$props
                    }
                    if ($original.Class -ne 'stdClass') {
                        $hook=$null
                        try { $hook=Find-PhpMethod $original.Class '__clone' }
                        catch {
                            if ($_.Exception.Message -notlike 'ALL PHP: Undefined method*') { throw }
                        }
                        if ($null -ne $hook) { [void](Invoke-PhpMethod $copy '__clone' @()) }
                    }
                    return $copy
                }
                'update' {
                    $before = Get-LValue $node.Target
                    $diff = if ($node.Op -ceq '++') { [decimal]1 } else { [decimal]-1 }
                    Set-LValue $node.Target $diff '+='
                    if ($node.Prefix) { return (Get-LValue $node.Target) }
                    return $before
                }
                'assign_ref' {
                    $cell=Get-PhpLValueCell $node.Source
                    Set-PhpReferenceTarget $node.Target $cell
                    return $cell.Value
                }
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
                    if (($node.Target.Kind -eq 'index' -and $null -eq $node.Target.Key) -or
                        $node.Target.Kind -eq 'array' -or
                        ($node.Target.Kind -eq 'property' -and $node.Op -ceq '=')) {
                        return $replacement
                    }
                    return (Get-LValue $node.Target)
                }
                'double_string' { return (Expand-PhpDoubleString $node.Raw) }
                'variable' { return (Get-LValue $node) }
                'dynamic_variable' { return (Get-LValue $node) }
                'index' { return (Get-LValue $node) }
                'property' { return (Get-LValue $node) }
                'array' {
                    $array = New-PhpArray
                    foreach ($entry in $node.Entries) {
                        $value = Invoke-PhpExpr $entry.Value
                        if ($entry.Spread) {
                            if (-not (Is-PhpArray $value)) {
                                throw 'ALL PHP: Only arrays can be unpacked in array literals'
                            }
                            foreach ($key in $value.Items.Keys) {
                                if (([string]$key).StartsWith('i:')) {
                                    Set-PhpArrayItem $array $null $value.Items[$key] $true
                                } else {
                                    Set-PhpArrayItem $array (KeyString-ToValue ([string]$key)) $value.Items[$key] $false
                                }
                            }
                            continue
                        }
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
                            if ($arg.Kind -eq 'property') {
                                $object=Invoke-PhpExpr $arg.Base
                                if ($null -ne $object -and (Is-PhpObject $object)) {
                                    $present=if ($object.Props -is [System.Collections.Specialized.OrderedDictionary]) {
                                        $object.Props.Contains($arg.Name)
                                    } else { $object.Props.ContainsKey($arg.Name) }
                                    if (-not $present) {
                                        $issetMethod=Find-OptionalPhpMethod $object.Class '__isset'
                                        if ($null -ne $issetMethod) {
                                            $found=Is-Truthy (Invoke-PhpMethod $object '__isset' @($arg.Name))
                                            if ($node.Name -ceq 'isset' -and -not $found) { return $false }
                                            if ($node.Name -ceq 'isset' -and $found) { continue }
                                            if ($node.Name -ceq 'empty' -and -not $found) { return $true }
                                        }
                                    }
                                }
                            }
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
                            if ($arg.Kind -in @('variable','dynamic_variable')) {
                                $varName=if ($arg.Kind -eq 'variable') {
                                    $arg.Name
                                } else { Resolve-PhpDynamicVariableName $arg }
                                if ($state.GlobalBindings.Contains($varName)) {
                                    [void]$state.Globals.Remove($varName)
                                } elseif ($state.StaticBindings.Contains($varName)) {
                                    [void]$state.FunctionStatics.Remove($state.CurrentCallable + '|' + $varName)
                                    [void]$state.StaticBindings.Remove($varName)
                                } else { [void]$state.Vars.Remove($varName) }
                            } elseif ($arg.Kind -eq 'index') {
                                $array = Invoke-PhpExpr $arg.Base
                                if (-not (Is-PhpArray $array)) { throw 'ALL PHP: unset index requires array' }
                                if ($null -eq $arg.Key) { throw 'ALL PHP: unset requires array key' }
                                $key = To-PhpKey (Invoke-PhpExpr $arg.Key)
                                if ($array.Items.Contains($key)) { $array.Items.Remove($key) }
                            } elseif ($arg.Kind -eq 'property') {
                                $object = Invoke-PhpExpr $arg.Base
                                if (-not (Is-PhpObject $object)) { throw 'ALL PHP: unset property requires object' }
                                if ($object.PSObject.Properties['EnumCase']) {
                                    throw 'ALL PHP: Cannot unset enum case property'
                                }
                                $present=if ($object.Props -is [System.Collections.Specialized.OrderedDictionary]) {
                                    $object.Props.Contains($arg.Name)
                                } else { $object.Props.ContainsKey($arg.Name) }
                                if ($present) {
                                    if ($object.Class -ne 'stdClass') {
                                        $declared=Find-PhpProperty $object.Class $arg.Name $false
                                        if ($null -ne $declared) {
                                            Assert-PhpVisibility $declared.Visibility $declared.Owner
                                        }
                                    }
                                    [void]$object.Props.Remove($arg.Name)
                                } else {
                                    $magic=Find-OptionalPhpMethod $object.Class '__unset'
                                    if ($null -ne $magic) {
                                        [void](Invoke-PhpMethod $object '__unset' @($arg.Name))
                                    }
                                }
                            } else { throw 'ALL PHP: unset() requires variable or element' }
                        }
                        return $null
                    }
                    if ($state.Functions.ContainsKey($node.Name)) {
                        $args=Evaluate-PhpUserArguments $node.Args $state.Functions[$node.Name]
                        return (Invoke-PhpCallable $state.Functions[$node.Name] $args $null)
                    }
                    $callArgs = [System.Collections.Generic.List[object]]::new()
                    foreach ($arg in $node.Args) {
                        if ($arg.Kind -ceq 'named_argument') {
                            [void]$callArgs.Add([pscustomobject]@{
                                PhpType='named_argument'; Name=$arg.Name
                                Value=(Invoke-PhpExpr $arg.Expr)
                            })
                        } else {
                            [void]$callArgs.Add((Invoke-PhpExpr $arg))
                        }
                    }
                    return (Invoke-PhpFunction $node.Name ($callArgs.ToArray()))
                }
                'method' {
                    $base = Invoke-PhpExpr $node.Base
                    if ($node.NullSafe -and $null -eq $base) { return $null }
                    if (-not (Is-PhpObject $base)) { throw 'ALL PHP: Method call requires object' }
                    $def=Find-OptionalPhpMethod $base.Class $node.Name
                    if ($null -ne $def) {
                        $args=Evaluate-PhpUserArguments $node.Args $def
                        return (Invoke-PhpMethod $base $node.Name $args)
                    }
                    $magic=Find-OptionalPhpMethod $base.Class '__call'
                    if ($null -eq $magic) { throw "ALL PHP: Undefined method '$($node.Name)'" }
                    $collected=New-PhpArray
                    foreach ($arg in $node.Args) {
                        if ($arg.Kind -ceq 'named_argument') {
                            $item=Invoke-PhpExpr $arg.Expr
                            Set-PhpArrayItem $collected $arg.Name $item $false
                        } else {
                            $item=Invoke-PhpExpr $arg
                            Set-PhpArrayItem $collected $null $item $true
                        }
                    }
                    return (Invoke-PhpMethod $base '__call' @($node.Name,$collected))
                }
                'new' {
                    $className=Resolve-PhpClass $node.Name
                    if ($state.Classes.ContainsKey($className) -and
                        $state.Classes[$className].PSObject.Properties['Enum'] -and
                        $state.Classes[$className].Enum) {
                        throw 'ALL PHP: Cannot instantiate enum'
                    }
                    if ($className -eq 'stdClass') {
                        if ($node.Args.Count -gt 0) {
                            throw 'ALL PHP: stdClass constructor takes no arguments'
                        }
                        return (New-PhpStdObject)
                    }
                    $chain=Get-PhpClassChain $className
                    if ($state.Classes[$className].Abstract) {
                        throw "ALL PHP: Cannot instantiate abstract class '$className'"
                    }
                    $object=[pscustomobject]@{
                        PhpType='object'; Class=$className
                        Props=[System.Collections.Generic.Dictionary[string,object]]::new(
                            [System.StringComparer]::Ordinal)
                    }
                    # Ancestors first, derived declarations last.
                    for ($i=$chain.Count - 1; $i -ge 0; $i--) {
                        foreach ($prop in $chain[$i].Properties) {
                            if ($prop.Static) { continue }
                            $val=$null
                            if ($null -ne $prop.Default) { $val=Invoke-PhpExpr $prop.Default }
                            $object.Props[$prop.Name]=Copy-PhpValue $val
                        }
                    }
                    $construct=$null
                    try { $construct=Find-PhpMethod $className '__construct' }
                    catch {
                        if ($_.Exception.Message -notlike 'ALL PHP: Undefined method*') { throw }
                    }
                    if ($null -ne $construct) {
                        $callArgs=Evaluate-PhpUserArguments $node.Args $construct
                        [void](Invoke-PhpMethod $object '__construct' $callArgs)
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
                        '~' { return [decimal](-bnot [long](To-Number $value)) }
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
                        '+' {
                            if ((Is-PhpArray $a) -and (Is-PhpArray $b)) {
                                $union = Copy-PhpValue $a
                                foreach ($key in $b.Items.Keys) {
                                    if (-not $union.Items.Contains($key)) {
                                        Set-PhpArrayItem $union (KeyString-ToValue ([string]$key)) $b.Items[$key] $false
                                    }
                                }
                                return $union
                            }
                            return ((To-Number $a) + (To-Number $b))
                        }
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
                        '==' { return (Php-Equal $a $b $false) }
                        '!=' { return (-not (Php-Equal $a $b $false)) }
                        '===' { return (Is-StrictEqual $a $b) }
                        '!==' { return (-not (Is-StrictEqual $a $b)) }
                        '<' { return ((Compare-Values $a $b) -lt 0) }
                        '<=' { return ((Compare-Values $a $b) -le 0) }
                        '>' { return ((Compare-Values $a $b) -gt 0) }
                        '>=' { return ((Compare-Values $a $b) -ge 0) }
                        '<=>' { return [decimal](Compare-Values $a $b) }
                        '<<' { return [decimal]([long](To-Number $a) -shl [int](To-Number $b)) }
                        '>>' { return [decimal]([long](To-Number $a) -shr [int](To-Number $b)) }
                        '&' { return [decimal]([long](To-Number $a) -band [long](To-Number $b)) }
                        '|' { return [decimal]([long](To-Number $a) -bor [long](To-Number $b)) }
                        '^' { return [decimal]([long](To-Number $a) -bxor [long](To-Number $b)) }
                        'instanceof' {
                            if (-not (Is-PhpObject $a)) { return $false }
                            if ($b -isnot [string]) { throw 'ALL PHP: instanceof class name required' }
                            return (Test-PhpInstanceOf $a.Class $b)
                        }
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
                'globaldecl' {
                    if ($state.CallDepth -le 0) {
                        throw 'ALL PHP: Global declaration outside function'
                    }
                    foreach ($name in $node.Names) { [void]$state.GlobalBindings.Add($name) }
                    return
                }
                'staticdecl' {
                    if ($state.CallDepth -le 0) {
                        throw 'ALL PHP: Static local declaration outside function'
                    }
                    foreach ($decl in $node.Decls) {
                        $key = $state.CurrentCallable + '|' + $decl.Name
                        if (-not $state.FunctionStatics.ContainsKey($key)) {
                            $init = $null
                            if ($null -ne $decl.Init) { $init = Invoke-PhpExpr $decl.Init }
                            $state.FunctionStatics[$key] = Copy-PhpValue $init
                        }
                        [void]$state.StaticBindings.Add($decl.Name)
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
                'enumdef' {
                    if ($state.Classes.ContainsKey($node.Name) -or
                        $state.Interfaces.ContainsKey($node.Name) -or
                        $state.Traits.ContainsKey($node.Name)) {
                        throw "ALL PHP: Type already declared '$($node.Name)'"
                    }
                    foreach ($iface in $node.Interfaces) {
                        if (-not $state.Interfaces.ContainsKey($iface)) {
                            throw "ALL PHP: Undefined interface '$iface'"
                        }
                    }
                    $methods=[System.Collections.Generic.Dictionary[string,object]]::new(
                        [System.StringComparer]::OrdinalIgnoreCase)
                    foreach ($method in $node.Methods) {
                        if ($methods.ContainsKey($method.Name) -or
                            $method.Name -in @('cases','from','tryFrom')) {
                            throw 'ALL PHP: Reserved or duplicate enum method'
                        }
                        $methods[$method.Name]=$method
                    }
                    $constants=[System.Collections.Generic.Dictionary[string,object]]::new(
                        [System.StringComparer]::Ordinal)
                    $enumCases=[System.Collections.Generic.List[object]]::new()
                    $usedValues=[System.Collections.Generic.HashSet[string]]::new(
                        [System.StringComparer]::Ordinal)
                    foreach ($case in $node.Cases) {
                        if ($constants.ContainsKey($case.Name)) {
                            throw "ALL PHP: Duplicate enum case '$($case.Name)'"
                        }
                        $props=[System.Collections.Specialized.OrderedDictionary]::new(
                            [System.StringComparer]::Ordinal)
                        $props['name']=$case.Name
                        if ($null -ne $node.BackingType) {
                            $backedValue=Invoke-PhpExpr $case.Value
                            if ($node.BackingType -eq 'string' -and $backedValue -isnot [string]) {
                                throw 'ALL PHP: Backed enum string case expects a string'
                            }
                            if ($node.BackingType -eq 'int' -and
                                ($backedValue -isnot [decimal] -or
                                 [decimal]::Truncate($backedValue) -ne $backedValue)) {
                                throw 'ALL PHP: Backed enum int case expects an integer'
                            }
                            $uniqueValue=$node.BackingType + ':' + [string]$backedValue
                            if (-not $usedValues.Add($uniqueValue)) {
                                throw 'ALL PHP: Duplicate backed enum case value'
                            }
                            $props['value']=$backedValue
                        }
                        $caseObject=[pscustomobject]@{
                            PhpType='object'; Class=$node.Name; Props=$props
                            EnumCase=$case.Name
                        }
                        [void]$enumCases.Add($caseObject)
                        $constants[$case.Name]=[pscustomobject]@{
                            Value=$caseObject; Owner=$node.Name; Visibility='public'
                        }
                    }
                    $state.Classes[$node.Name]=[pscustomobject]@{
                        Name=$node.Name; Parent=$null; Methods=$methods
                        Properties=@(); StaticValues=[System.Collections.Generic.Dictionary[string,object]]::new(
                            [System.StringComparer]::Ordinal)
                        Constants=$constants; Interfaces=$node.Interfaces
                        Abstract=$false; Final=$true; Enum=$true
                        BackingType=$node.BackingType; EnumCases=$enumCases.ToArray()
                    }
                    return
                }
                'interfacedef' {
                    if ($state.Classes.ContainsKey($node.Name) -or
                        $state.Interfaces.ContainsKey($node.Name) -or
                        $state.Traits.ContainsKey($node.Name)) {
                        throw "ALL PHP: Type already declared '$($node.Name)'"
                    }
                    $methods=[System.Collections.Generic.Dictionary[string,object]]::new(
                        [System.StringComparer]::OrdinalIgnoreCase)
                    foreach ($method in $node.Methods) {
                        if ($methods.ContainsKey($method.Name)) {
                            throw "ALL PHP: Duplicate interface method '$($method.Name)'"
                        }
                        $methods[$method.Name]=$method
                    }
                    $constants=[System.Collections.Generic.Dictionary[string,object]]::new(
                        [System.StringComparer]::Ordinal)
                    foreach ($const in $node.Constants) {
                        if ($constants.ContainsKey($const.Name)) { throw 'ALL PHP: Duplicate interface constant' }
                        $constants[$const.Name]=[pscustomobject]@{
                            Value=(Invoke-PhpExpr $const.Value); Owner=$node.Name
                            Visibility='public'
                        }
                    }
                    foreach ($parent in $node.Parents) {
                        if (-not $state.Interfaces.ContainsKey($parent)) {
                            throw "ALL PHP: Undefined parent interface '$parent'"
                        }
                    }
                    $state.Interfaces[$node.Name]=[pscustomobject]@{
                        Name=$node.Name; Parents=$node.Parents
                        Methods=$methods; Constants=$constants
                    }
                    return
                }
                'traitdef' {
                    if ($state.Classes.ContainsKey($node.Name) -or
                        $state.Interfaces.ContainsKey($node.Name) -or
                        $state.Traits.ContainsKey($node.Name)) {
                        throw "ALL PHP: Type already declared '$($node.Name)'"
                    }
                    if ($null -ne $node.Parent -or $node.Interfaces.Count -gt 0) {
                        throw "ALL PHP: Expected '{' after trait name; traits cannot extend classes or implement interfaces"
                    }
                    if ($node.Traits.Count -gt 0) {
                        $composition=Get-PhpTraitComposition $node
                        $names=[System.Collections.Generic.HashSet[string]]::new(
                            [System.StringComparer]::OrdinalIgnoreCase)
                        $merged=[System.Collections.Generic.List[object]]::new()
                        foreach ($method in $node.Methods) {
                            [void]$names.Add($method.Name)
                            [void]$merged.Add($method)
                        }
                        foreach ($method in $composition.Methods) {
                            if ($names.Add($method.Name)) { [void]$merged.Add($method) }
                        }
                        $props=[System.Collections.Generic.List[object]]::new()
                        foreach ($prop in $node.Properties) { [void]$props.Add($prop) }
                        foreach ($prop in $composition.Properties) { [void]$props.Add($prop) }
                        $node.Methods=$merged.ToArray()
                        $node.Properties=$props.ToArray()
                    }
                    $state.Traits[$node.Name]=$node
                    return
                }
                'classdef' {
                    if ($state.Classes.ContainsKey($node.Name) -or
                        $state.Interfaces.ContainsKey($node.Name) -or
                        $state.Traits.ContainsKey($node.Name)) {
                        throw "ALL PHP: Type already declared '$($node.Name)'"
                    }
                    if ($null -ne $node.Parent -and
                        -not $state.Classes.ContainsKey($node.Parent)) {
                        throw "ALL PHP: Parent class not defined '$($node.Parent)'"
                    }
                    if ($null -ne $node.Parent -and $state.Classes[$node.Parent].Final) {
                        throw "ALL PHP: Cannot extend final class '$($node.Parent)'"
                    }
                    foreach ($iface in $node.Interfaces) {
                        if (-not $state.Interfaces.ContainsKey($iface)) {
                            throw "ALL PHP: Undefined interface '$iface'"
                        }
                    }
                    $methods=[System.Collections.Generic.Dictionary[string,object]]::new(
                        [System.StringComparer]::OrdinalIgnoreCase)
                    foreach ($method in $node.Methods) {
                        if ($methods.ContainsKey($method.Name)) {
                            throw "ALL PHP: Duplicate method '$($method.Name)'"
                        }
                        if ($null -ne $node.Parent) {
                            $parentMethod=$null
                            try { $parentMethod=Find-PhpMethod $node.Parent $method.Name }
                            catch {
                                if ($_.Exception.Message -notlike 'ALL PHP: Undefined method*') { throw }
                            }
                            if ($null -ne $parentMethod) {
                                if ($parentMethod.Final) {
                                    throw "ALL PHP: Cannot override final method '$($method.Name)'"
                                }
                                if ($parentMethod.Visibility -ne 'private') {
                                    Assert-PhpMethodSignature $method $parentMethod $method.Name
                                }
                            }
                        }
                        $methods[$method.Name]=$method
                    }
                    $effectiveProperties=[System.Collections.Generic.List[object]]::new()
                    foreach ($prop in $node.Properties) { [void]$effectiveProperties.Add($prop) }
                    $traitMethods=[System.Collections.Generic.HashSet[string]]::new(
                        [System.StringComparer]::OrdinalIgnoreCase)
                    $composition=Get-PhpTraitComposition $node
                    foreach ($method in $composition.Methods) {
                            if ($methods.ContainsKey($method.Name)) {
                                if ($traitMethods.Contains($method.Name)) {
                                    throw "ALL PHP: Conflicting trait method '$($method.Name)'"
                                }
                                # The class method takes precedence over a trait method.
                                continue
                            }
                            if (-not $traitMethods.Add($method.Name)) {
                                throw "ALL PHP: Conflicting trait method '$($method.Name)'"
                            }
                            $imported=[pscustomobject]@{
                                Kind='functiondef'; Name=$method.Name
                                Params=$method.Params; Body=$method.Body; Expr=$method.Expr
                                Visibility=$method.Visibility; Static=$method.Static
                                Owner=$node.Name; Abstract=$method.Abstract; Final=$method.Final
                            }
                            if ($null -ne $node.Parent) {
                                $inherited=$null
                                try { $inherited=Find-PhpMethod $node.Parent $method.Name }
                                catch {
                                    if ($_.Exception.Message -notlike 'ALL PHP: Undefined method*') { throw }
                                }
                                if ($null -ne $inherited) {
                                    if ($inherited.Final) { throw 'ALL PHP: Cannot override final method via trait' }
                                    if ($inherited.Visibility -ne 'private') {
                                        Assert-PhpMethodSignature $imported $inherited $method.Name
                                    }
                                }
                            }
                            $methods[$method.Name]=$imported
                    }
                    foreach ($prop in $composition.Properties) {
                            $duplicate=$false
                            foreach ($existing in $effectiveProperties) {
                                if ($existing.Name -ceq $prop.Name) { $duplicate=$true; break }
                            }
                            if ($duplicate) { throw "ALL PHP: Conflicting trait property '$($prop.Name)'" }
                            [void]$effectiveProperties.Add([pscustomobject]@{
                                Name=$prop.Name; Default=$prop.Default
                                Visibility=$prop.Visibility; Static=$prop.Static
                                Owner=$node.Name
                            })
                    }
                    $statics=[System.Collections.Generic.Dictionary[string,object]]::new(
                        [System.StringComparer]::Ordinal)
                    foreach ($prop in $effectiveProperties) {
                        if ($prop.Static) {
                            $default=$null
                            if ($null -ne $prop.Default) { $default=Invoke-PhpExpr $prop.Default }
                            $statics[$prop.Name]=Copy-PhpValue $default
                        }
                    }
                    $constants=[System.Collections.Generic.Dictionary[string,object]]::new(
                        [System.StringComparer]::Ordinal)
                    foreach ($const in $node.Constants) {
                        if ($constants.ContainsKey($const.Name)) {
                            throw "ALL PHP: Duplicate constant '$($const.Name)'"
                        }
                        $constants[$const.Name]=[pscustomobject]@{
                            Value=(Invoke-PhpExpr $const.Value); Visibility=$const.Visibility
                            Owner=$node.Name
                        }
                    }
                    $state.Classes[$node.Name]=[pscustomobject]@{
                        Name=$node.Name; Parent=$node.Parent; Methods=$methods
                        Properties=$effectiveProperties.ToArray(); StaticValues=$statics
                        Constants=$constants; Interfaces=$node.Interfaces
                        Abstract=$node.Abstract; Final=$node.Final
                    }
                    # A concrete class must supply every abstract ancestor and
                    # declared-interface method. Validation stays inside registration
                    # so incomplete classes cannot be instantiated.
                    if (-not $node.Abstract) {
                        foreach ($cls in (Get-PhpClassChain $node.Name)) {
                            foreach ($required in $cls.Methods.Values) {
                                if ($required.Abstract) {
                                    $implementation=Find-PhpMethod $node.Name $required.Name
                                    if ($implementation.Abstract) {
                                        throw "ALL PHP: Concrete class has abstract method '$($required.Name)'"
                                    }
                                    Assert-PhpMethodSignature $implementation $required $required.Name
                                }
                            }
                            foreach ($ifaceName in $cls.Interfaces) {
                                foreach ($iface in (Get-PhpInterfaceChain $ifaceName)) {
                                    foreach ($required in $iface.Methods.Values) {
                                        $implementation=$null
                                        try { $implementation=Find-PhpMethod $node.Name $required.Name }
                                        catch {
                                            if ($_.Exception.Message -notlike 'ALL PHP: Undefined method*') { throw }
                                        }
                                        if ($null -eq $implementation -or $implementation.Abstract) {
                                            throw "ALL PHP: Interface method not implemented '$($required.Name)'"
                                        }
                                        Assert-PhpMethodSignature $implementation $required $required.Name
                                    }
                                }
                            }
                        }
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
                    if ($node.ByReference -and
                        $node.Iter.Kind -notin @('variable','dynamic_variable','index','property','static_property')) {
                        throw 'ALL PHP: By-reference foreach requires a writable array'
                    }
                    # A by-value traversal takes a value snapshot; a reference
                    # traversal works on the original cells and leaves the last alias.
                    $walk=$arr
                    if (-not $node.ByReference) { $walk=Copy-PhpValue $arr }
                    $state.Flow.LoopDepth++
                    try {
                        foreach ($key in @($walk.Items.Keys)) {
                            if ($state.Flow.Returned) { break }
                            $value=$walk.Items[$key]
                            if ($node.ByReference) {
                                if (-not (Is-PhpRefCell $value)) {
                                    $value=[pscustomobject]@{
                                        PhpType='refcell'; Value=(Copy-PhpValue $value)
                                    }
                                    $walk.Items[$key]=$value
                                }
                                $slot=Get-PhpVariableSlot $node.ValueName
                                $slot.Store[$slot.Key]=$value
                            } else {
                                if (Is-PhpRefCell $value) { $value=$value.Value }
                                Set-PhpVariableValue $node.ValueName $value
                            }
                            if ($null -ne $node.KeyName) {
                                if ($key.StartsWith('i:')) {
                                    Set-PhpVariableValue $node.KeyName ([decimal]$key.Substring(2))
                                } else {
                                    Set-PhpVariableValue $node.KeyName ($key.Substring(2))
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
