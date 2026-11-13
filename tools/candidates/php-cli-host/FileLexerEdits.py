"""CLI source lexing edits; source bytes are not rewritten into synthetic PHP."""
def apply(value):
    def replace(old,new):
        nonlocal value
        old=old.replace('\n','\r\n');new=new.replace('\n','\r\n')
        if value.count(old)!=1:raise ValueError('File lexer anchor is not unique: '+old[:90])
        value=value.replace(old,new)

    replace("CliContextCapabilities = @('source-body-v1','script-arguments-v1','initial-ini-v1')",
            "CliContextCapabilities = @('source-body-v1','script-arguments-v1','initial-ini-v1','source-tags-v1')")
    replace("""            ($CliContext['SourceMode'] -ceq 'body' -or
             ($CliContext['SourceMode'] -in @('file','stdin') -and $Code.Length -eq 0))) {""",
            """            $CliContext['SourceMode'] -in @('body','file','stdin')) {""")
    replace("""                NamespaceFallbacks = [System.Collections.Generic.Dictionary[int,string]]::new()
""", """                NamespaceFallbacks = [System.Collections.Generic.Dictionary[int,string]]::new()
                InlineHtml = [System.Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
""")
    start=value.index('        function ConvertTo-PhpTokens(')
    end=value.index('        # ---- Namespaces ',start)
    old=value[start:end]
    new=r'''        function ConvertTo-PhpTokens([string]$text, $tokens, $lines,
            [bool]$FileMode=$false, [bool]$StartsInPhp=$true) {
            $line = 1
            $insidePhp = $StartsInPhp
            $tokenRx = $rx
            $openRx = $null
            if ($FileMode) {
                $openPattern = '<\?(?:php(?=\s|$)|=)'
                if ($isCli -and ($CliContext.Keys -contains 'InitialIni') -and
                    ($CliContext['InitialIni'].Keys -contains 'short_open_tag') -and
                    $CliContext['InitialIni']['short_open_tag'] -ceq '1') {
                    $openPattern = '<\?(?:php(?=\s|$)|=)?'
                }
                $openRx = [regex]::new($openPattern, [Text.RegularExpressions.RegexOptions]::IgnoreCase)
                # A close tag ends a line comment, but not a quoted string or
                # block comment. Those stay whole tokens under the existing rx.
                $filePattern = $pattern.Replace('//[^\r\n]*','//(?:(?!\?>)[^\r\n])*').Replace('\#[^\r\n]*','\#(?:(?!\?>)[^\r\n])*')
                $tokenRx = [regex]::new($filePattern)
            }
            $initialOffset = 0
            if ($FileMode -and -not $StartsInPhp -and $text.StartsWith('#!')) {
                $firstNewline = [regex]::Match($text,"`r`n|`r|`n")
                if ($firstNewline.Success) { $initialOffset=$firstNewline.Index+$firstNewline.Length;$line=2 }
                else { $initialOffset=$text.Length }
            }
            for ($offset = $initialOffset; $offset -lt $text.Length;) {
                if ($FileMode -and -not $insidePhp) {
                    $opening = $openRx.Match($text,$offset)
                    $stop = if ($opening.Success) { $opening.Index } else { $text.Length }
                    if ($stop -gt $offset) {
                        $html = $text.Substring($offset,$stop-$offset)
                        $id = [string][char]30 + 'HTML:' + $state.InlineHtml.Count
                        $state.InlineHtml[$id] = $html
                        [void]$tokens.Add($id);[void]$lines.Add($line)
                        $line += [regex]::Matches($html,"`r`n|`r|`n").Count
                    }
                    $offset = $stop
                    if (-not $opening.Success) { break }
                    if ($opening.Value -ceq '<?=') {
                        [void]$tokens.Add('echo');[void]$lines.Add($line)
                    }
                    $offset += $opening.Length
                    $insidePhp = $true
                    continue
                }
                if ($FileMode -and $offset+1 -lt $text.Length -and
                    $text[$offset] -ceq '?' -and $text[$offset+1] -ceq '>') {
                    # A closing tag supplies the statement terminator and may
                    # consume one following newline. The next text is HTML.
                    [void]$tokens.Add(';');[void]$lines.Add($line)
                    $offset += 2
                    if ($offset -lt $text.Length -and $text[$offset] -ceq [char]13) {
                        $offset++;if ($offset -lt $text.Length -and $text[$offset] -ceq [char]10) { $offset++ };$line++
                    } elseif ($offset -lt $text.Length -and $text[$offset] -ceq [char]10) { $offset++;$line++ }
                    $insidePhp = $false
                    continue
                }
                $match = $tokenRx.Match($text, $offset)
                if (-not $match.Success -or $match.Index -ne $offset) {
                    throw "ALL PHP: Unknown character at offset $offset"
                }
                $token = $match.Value
                if (-not [string]::IsNullOrWhiteSpace($token) -and
                    -not $token.StartsWith('//') -and
                    -not $token.StartsWith('#') -and
                    -not $token.StartsWith('/*')) {
                    [void]$tokens.Add($token)
                    [void]$lines.Add($line)
                }
                if ($FileMode) { $line += [regex]::Matches($token,"`r`n|`r|`n").Count }
                elseif ($token.IndexOf([char]10) -ge 0) { $line += ($token.Split([char]10).Count - 1) }
                $offset += $token.Length
            }
            [void]$tokens.Add('(EOF)')
            [void]$lines.Add($line)
        }
'''.replace('\n','\r\n')
    if '        function Read-PhpDocToken' in value:
        hook="""                $doc = Read-PhpDocToken $text $offset $line
                if ($null -ne $doc) {
                    [void]$tokens.Add($doc.Token);[void]$lines.Add($line)
                    $offset += $doc.Length;$line += $doc.Newlines
                    continue
                }
""".replace('\n','\r\n')
        target='                $match = $tokenRx.Match($text, $offset)'
        if new.count(target)!=1:raise ValueError('Doc hook site is not unique')
        new=new.replace(target,hook+target)
    value=value[:start]+new+value[end:]
    source_call="""        if ($isCli -and ($CliContext.Keys -contains 'SourceMode') -and
            $CliContext['SourceMode'] -in @('body','file','stdin')) {
            ConvertTo-PhpTokens $source $state.Tokens $state.TokenLines $true ($CliContext['SourceMode'] -ceq 'body')
        } else { ConvertTo-PhpTokens $source $state.Tokens $state.TokenLines }
"""
    if '        try { ConvertTo-PhpTokens $source $state.Tokens $state.TokenLines }' in value:
        replace('        try { ConvertTo-PhpTokens $source $state.Tokens $state.TokenLines }',
                '        try {\n'+source_call+'        }')
    else:
        replace("""        ConvertTo-PhpTokens $source $state.Tokens $state.TokenLines
        # Only programs""",source_call+'        # Only programs')
    replace("""        function Read-StatementCore {
            $token = Peek-Token
""", """        function Read-StatementCore {
            $token = Peek-Token
            if ($isCli -and ($CliContext.Keys -contains 'SourceMode') -and
                $CliContext['SourceMode'] -ceq 'body' -and $state.Pos -eq 0 -and $token -ceq '<') {
                $message = 'syntax error, unexpected token "<", expecting end of file'
                $CliContext['CompileError'] = [pscustomobject]@{
                    Type='ParseError'; TokenKind='<'; TokenContent='<'; Message=$message
                    SourcePath=$state.ScriptName; Line=[long]$state.TokenLines[$state.Pos]
                }
                throw 'ALL PHP: structured code-body parse error'
            }
            if ($state.InlineHtml.ContainsKey($token)) {
                [void](Next-Token)
                return [pscustomobject]@{ Kind='inline_html'; Text=$state.InlineHtml[$token] }
            }
""")
    replace("""            switch ($node.Kind) {
                'constdecl' {""", """            switch ($node.Kind) {
                'inline_html' { [Console]::Write($node.Text); return }
                'constdecl' {""")
    replace("""$startsStatement = ($prev -ceq '' -or $prev -ceq ';' -or $prev -ceq '{' -or $prev -ceq '}')""",
            """$startsStatement = ($prev -ceq '' -or $prev -ceq ';' -or $prev -ceq '{' -or $prev -ceq '}' -or $state.InlineHtml.ContainsKey($prev))""")
    replace("""            foreach ($pass in 1, 2) {
                $ns = ''""", """            foreach ($pass in 1, 2) {
                $seenNamespace = $false
                $ns = ''""")
    replace(r'''                            # namespace A\B;   namespace A\B { ... }   namespace { ... }
                            $j = $i + 1''', r'''                            # namespace A\B;   namespace A\B { ... }   namespace { ... }
                            if (-not $seenNamespace -and $i -gt 0 -and $state.InlineHtml.ContainsKey($tokens[0])) {
                                $message = 'Namespace declaration statement has to be the very first statement or after any declare call in the script'
                                if ($isCli) {
                                    $CliContext['CompileError'] = [pscustomobject]@{
                                        Type='CompileError'; Reason='namespace_after_inline_html'; Message=$message
                                        SourcePath=$state.ScriptName; Line=[long]$lines[$i]
                                    }
                                }
                                throw ('ALL PHP: '+$message)
                            }
                            $seenNamespace = $true
                            $j = $i + 1''')
    replace("""            if ($expr.Kind -ceq 'class_name') {
                throw 'ALL PHP: Undefined constant in expression statement'
            }""", """            if ($expr.Kind -ceq 'class_name') {
                # Diagnose invalid syntax before the legacy bare-constant guard.
                # The existing structured parser reports the actual next token.
                if ($isCli -and (Peek-Token) -cne ';') { Expect-Token ';' }
                throw 'ALL PHP: Undefined constant in expression statement'
            }""")
    if '        foreach($literalWarning in $state.LiteralWarnings)' in value:
        warning_start=value.index('        foreach($literalWarning in $state.LiteralWarnings)')
        ini_start=value.index("        if ($isCli -and ($CliContext.Keys -contains 'InitialIni'))")
        load_start=value.index('        # Load the built-in exception classes')
        if not warning_start<ini_start<load_start:raise ValueError('Unexpected literal warning/init order')
        # Initial host INI must be active before scanner/compiler diagnostics.
        value=value[:warning_start]+value[ini_start:load_start]+value[warning_start:ini_start]+value[load_start:]
    return value
