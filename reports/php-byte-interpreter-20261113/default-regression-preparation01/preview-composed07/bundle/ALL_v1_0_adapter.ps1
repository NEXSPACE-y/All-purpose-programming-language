@{
    Name = 'ALL'
    Run = {
        param([string]$Code)
        $ErrorActionPreference = 'Stop'
        $culture = [System.Globalization.CultureInfo]::InvariantCulture

        if ($null -eq $Code) { throw 'ALL: Source is null' }
        if ($Code.Length -gt 100000) { throw 'ALL: Source is too long (limit: 100000 characters)' }
        # Natural Japanese surface grammar v0.6 (bounded, deterministic).
        # This is NOT unconstrained natural-language interpretation.
        # Only whole-line, specified Japanese constructions are lowered to
        # ALL's existing syntax before tokenization; untouched lines remain verbatim.
        function Quote-AllJapanese([string]$value) {
            # JSON escaping is compatible with the ordinary ALL string scanner
            # for the supported one-line Japanese quotation bodies.
            if ($value.Contains('"') -or $value.Contains('\') -or
                $value.Contains("`r") -or $value.Contains("`n") -or
                $value.Contains("`t")) {
                throw 'ALL Japanese Syntax Error: Escapes inside 「」 are not supported; use an ordinary quoted string'
            }
            return ('"' + $value + '"')
        }
        function Convert-AllJapaneseValue([string]$raw) {
            $item = $raw.Trim()
            if ($item -cmatch '^「(?<text>[^」]*)」$') {
                return (Quote-AllJapanese $Matches['text'])
            }
            $id = '[\p{L}_][\p{L}\p{M}\p{Nd}_]*'
            $m = [regex]::Match($item, ('^(?<owner>' + $id + ')の「(?<key>[^」]*)」$'))
            if ($m.Success) {
                return ($m.Groups['owner'].Value + '[' + (Quote-AllJapanese $m.Groups['key'].Value) + ']')
            }
            return $item
        }
        function Get-AllJapaneseComparison([string]$target, [string]$rhs, [string]$word) {
            $operators = @{
                '以上' = '>='; '以下' = '<='; '未満' = '<'; 'より大きい' = '>';
                'より小さい' = '<'; 'と等しい' = '=='; 'と異なる' = '!='
            }
            if (-not $operators.ContainsKey($word)) { throw 'ALL Japanese Syntax Error: Unsupported comparison' }
            return ($target + ' ' + $operators[$word] + ' ' + (Convert-AllJapaneseValue $rhs))
        }
        function Convert-AllNaturalJapanese([string]$source) {
            $names = '[\p{L}_][\p{L}\p{M}\p{Nd}_]*'
            $compare = '以上|以下|未満|より大きい|より小さい|と等しい|と異なる'
            $result = [System.Collections.Generic.List[string]]::new()
            $lines = [regex]::Split($source,'\r\n|\n|\r')
            foreach ($line in $lines) {
                $trim = $line.Trim()
                $indent = [regex]::Match($line,'^\s*').Value
                $converted = $null
                # Comment lines, blank lines, and standard ALL syntax are untouched.
                if ($trim.Length -eq 0 -or $trim.StartsWith('#') -or $trim.StartsWith('//')) {
                    [void]$result.Add($line)
                    continue
                }
                $m = [regex]::Match($trim,('^(?<owner>'+$names+')に「(?<key>[^」]*)」という項目があ(?:る場合|れば)\s*(?<brace>\{)?$'))
                if ($m.Success) {
                    $converted = 'if (has_key('+$m.Groups['owner'].Value+','+(Quote-AllJapanese $m.Groups['key'].Value)+'))'
                    if ($m.Groups['brace'].Success) { $converted+=' {' }
                }
                if ($null -eq $converted) {
                    $m = [regex]::Match($trim,'^そうでなければ\s*(?<brace>\{)?$')
                    if ($m.Success) {
                        $converted='else'
                        if ($m.Groups['brace'].Success) { $converted+=' {' }
                    }
                }
                if ($null -eq $converted) {
                    $m = [regex]::Match($trim,('^(?<prefix>もし\s*)?(?<name>'+$names+')が\s*(?<rhs>.+?)(?<op>'+ $compare +')(?:なら|だったら)\s*(?<brace>\{)?$'))
                    if ($m.Success) {
                        $cond = Get-AllJapaneseComparison $m.Groups['name'].Value $m.Groups['rhs'].Value $m.Groups['op'].Value
                        $converted='if ('+$cond+')'
                        if ($m.Groups['brace'].Success) { $converted+=' {' }
                    }
                }
                if ($null -eq $converted) {
                    $m = [regex]::Match($trim,('^(?<name>'+$names+')が\s*(?<rhs>.+?)(?<op>'+ $compare +')の間(?:繰り返す)?\s*(?<brace>\{)?$'))
                    if ($m.Success) {
                        $cond = Get-AllJapaneseComparison $m.Groups['name'].Value $m.Groups['rhs'].Value $m.Groups['op'].Value
                        $converted='while ('+$cond+')'
                        if ($m.Groups['brace'].Success) { $converted+=' {' }
                    }
                }
                if ($null -eq $converted) {
                    $m = [regex]::Match($trim,('^(?<source>.+?)\s*の各要素を\s*(?<name>'+$names+')\s*として繰り返す\s*(?<brace>\{)?$'))
                    if ($m.Success) {
                        $converted='foreach ('+$m.Groups['name'].Value+' in '+$m.Groups['source'].Value.Trim()+')'
                        if ($m.Groups['brace'].Success) { $converted+=' {' }
                    }
                }
                if ($null -eq $converted) {
                    $m = [regex]::Match($trim,('^(?<name>'+$names+')という変数を\s*(?<rhs>.+?)とする$'))
                    if ($m.Success) {
                        $converted='let '+$m.Groups['name'].Value+' = '+(Convert-AllJapaneseValue $m.Groups['rhs'].Value)
                    }
                }
                if ($null -eq $converted) {
                    $m = [regex]::Match($trim,('^(?<name>'+$names+')に\s*(?<rhs>.+?)を代入する$'))
                    if ($m.Success) {
                        $converted=$m.Groups['name'].Value+' = '+(Convert-AllJapaneseValue $m.Groups['rhs'].Value)
                    }
                }
                if ($null -eq $converted) {
                    $m = [regex]::Match($trim,('^(?<name>'+$names+')に\s*(?<rhs>.+?)を(?:足す|加える)$'))
                    if ($m.Success) {
                        $name=$m.Groups['name'].Value
                        $converted=$name+' = '+$name+' + '+(Convert-AllJapaneseValue $m.Groups['rhs'].Value)
                    }
                }
                if ($null -eq $converted) {
                    $m = [regex]::Match($trim,('^(?<name>'+$names+')から\s*(?<rhs>.+?)を引く$'))
                    if ($m.Success) {
                        $name=$m.Groups['name'].Value
                        $converted=$name+' = '+$name+' - '+(Convert-AllJapaneseValue $m.Groups['rhs'].Value)
                    }
                }
                if ($null -eq $converted) {
                    $m = [regex]::Match($trim,('^(?<expr>.+?)を(?:改行して|一行で)表示する$'))
                    if ($m.Success) { $converted='println('+(Convert-AllJapaneseValue $m.Groups['expr'].Value)+')' }
                }
                if ($null -eq $converted) {
                    $m = [regex]::Match($trim,('^(?<expr>.+?)(?:を|と)表示する$'))
                    if ($m.Success) { $converted='print('+(Convert-AllJapaneseValue $m.Groups['expr'].Value)+')' }
                }
                if ($null -eq $converted) {
                    $m = [regex]::Match($trim,('^(?<expr>.+?)を返す$'))
                    if ($m.Success) { $converted='return '+(Convert-AllJapaneseValue $m.Groups['expr'].Value) }
                }
                if ($null -eq $converted) { [void]$result.Add($line) }
                else { [void]$result.Add($indent+$converted) }
            }
            return [string]::Join("`n",$result.ToArray())
        }
        # v0.7: Deterministic, local-only source modules. Imports are allowed
        # only at the beginning of each .all source, before executable statements.
        # Modules share the caller's scope; isolated exports are not implemented.
        $moduleRoot = (Get-Location).ProviderPath
        if (-not [string]::IsNullOrWhiteSpace($env:ALL_MODULE_ROOT)) {
            $moduleRoot = $env:ALL_MODULE_ROOT
        }
        $moduleRoot = [System.IO.Path]::GetFullPath($moduleRoot)
        $loadedAllModules = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $activeAllModules = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        # Each expanded line retains the original file/line, including imported modules.
        # Natural Japanese lowering remains line-preserving and does not alter this list.
        $sourceOrigins = [System.Collections.Generic.List[object]]::new()
        $rootSourceFile = [Environment]::GetEnvironmentVariable('ALL_SOURCE_FILE','Process')
        if ([string]::IsNullOrWhiteSpace($rootSourceFile)) { $rootSourceFile = '<inline>' }
        else { $rootSourceFile = [System.IO.Path]::GetFullPath($rootSourceFile) }
        function Resolve-AllModulePath([string]$path, [string]$fromDirectory) {
            if ([string]::IsNullOrWhiteSpace($path)) { throw 'ALL Module Error: Empty module path' }
            if ($path.IndexOfAny([char[]]@(0,10,13)) -ge 0) { throw 'ALL Module Error: Invalid module path' }
            $normalized = $path.Replace('\',[System.IO.Path]::DirectorySeparatorChar).Replace('/',[System.IO.Path]::DirectorySeparatorChar)
            if ([System.IO.Path]::IsPathRooted($normalized)) { throw 'ALL Module Error: Absolute module path forbidden' }
            if ([System.IO.Path]::GetExtension($normalized) -cne '.all') { throw 'ALL Module Error: Expected .all module' }
            $full = [System.IO.Path]::GetFullPath((Join-Path $fromDirectory $normalized))
            $prefix = $moduleRoot.TrimEnd([char[]]@('\','/')) + [System.IO.Path]::DirectorySeparatorChar
            if (-not $full.StartsWith($prefix,[System.StringComparison]::OrdinalIgnoreCase)) {
                throw 'ALL Module Error: Module escapes project root'
            }
            if (-not [System.IO.File]::Exists($full)) { throw "ALL Module Error: Module not found: $path" }
            return $full
        }
        function Expand-AllModuleImports([string]$source,[string]$directory,[int]$depth,[string]$sourceFile) {
            if ($depth -gt 16) { throw 'ALL Module Error: Import depth limit exceeded (16)' }
            $chunks = [System.Collections.Generic.List[string]]::new()
            $inHeader = $true
            $originalLine = 0
            foreach ($line in [regex]::Split($source,'\r\n|\n|\r')) {
                $originalLine++
                $trim = $line.Trim()
                $english = [regex]::Match($trim,'^import\s+"(?<path>[^"\r\n]+)"$')
                $japanese = [regex]::Match($trim,'^「(?<path>[^」\r\n]+)」をモジュールとして読み込む$')
                if ($english.Success -or $japanese.Success) {
                    if (-not $inHeader) {
                        throw 'ALL Module Error: Imports must appear before executable statements'
                    }
                    $relative = if ($english.Success) { $english.Groups['path'].Value } else { $japanese.Groups['path'].Value }
                    $full = Resolve-AllModulePath $relative $directory
                    if ($activeAllModules.Contains($full)) { throw "ALL Module Error: Circular import: $relative" }
                    if ($loadedAllModules.Contains($full)) { continue }
                    if ($loadedAllModules.Count -ge 32) { throw 'ALL Module Error: Module count limit exceeded (32)' }
                    [void]$loadedAllModules.Add($full)
                    [void]$activeAllModules.Add($full)
                    try {
                        $body = [System.IO.File]::ReadAllText($full,[System.Text.UTF8Encoding]::new($false,$true))
                        $body = $body.TrimStart([char]0xFEFF)
                        $moduleText = Expand-AllModuleImports $body ([System.IO.Path]::GetDirectoryName($full)) ($depth+1) $full
                        [void]$chunks.Add($moduleText)
                    } finally {
                        [void]$activeAllModules.Remove($full)
                    }
                    continue
                }
                if ($trim -cmatch '^import\s+' -or $trim -cmatch '^「[^」]*」をモジュールとして読み込む') {
                    throw 'ALL Module Error: Malformed import statement'
                }
                if ($trim.Length -gt 0 -and -not $trim.StartsWith('#') -and -not $trim.StartsWith('//')) {
                    $inHeader = $false
                }
                [void]$chunks.Add($line)
                [void]$sourceOrigins.Add([pscustomobject]@{ File=$sourceFile; Line=$originalLine })
            }
            return [string]::Join("`n",$chunks.ToArray())
        }
        $Code = Expand-AllModuleImports $Code $moduleRoot 0 $rootSourceFile
        if ($Code.Length -gt 100000) { throw 'ALL Module Error: Expanded source too long (100000 characters)' }
        $Code = Convert-AllNaturalJapanese $Code
        # Pre-index line starts once. Original per-statement prefix scans were
        # quadratic in the number of lines and expensive for large ALL programs.
        $sourceLineStarts = [System.Collections.Generic.List[int]]::new()
        [void]$sourceLineStarts.Add(0)
        for ($i=0; $i -lt $Code.Length; $i++) {
            if ($Code[$i] -eq "`n") { [void]$sourceLineStarts.Add($i+1) }
        }
        if ($sourceOrigins.Count -ne $sourceLineStarts.Count) {
            throw 'ALL Module Error: Source line map mismatch'
        }
        $state = @{
            Tokens = @()
            Pos = 0
            Vars = [System.Collections.Generic.Dictionary[string,object]]::new([System.StringComparer]::Ordinal)
            Functions = [System.Collections.Generic.Dictionary[string,object]]::new([System.StringComparer]::Ordinal)
            KnownFunctions = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
            Count = 0
            Steps = 0
            Depth = 0
            LoopDepth = 0
            FunctionDepth = 0
            TokenOffsets = @()
            CurrentLine = 0
            CurrentSourceFile = $rootSourceFile
            CurrentOriginalLine = 0
            TraceWriter = $null
            DebugFunctions = [System.Collections.Generic.List[string]]::new()
            Breakpoints = @()
            DebugMode = $false
            LastDebugLine = 0
        }
        $constants = [System.Collections.Generic.Dictionary[string,object]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $constants['pi'] = [Math]::PI
        $constants['e'] = [Math]::E
        $constants['tau'] = 2.0 * [Math]::PI
        $constants['phi'] = (1.0 + [Math]::Sqrt(5.0)) / 2.0

        # Lexer rejects *every* unknown character. Newlines delimit top-level statements.
        function Tokenize-All([string]$source) {
            $items = [System.Collections.Generic.List[string]]::new()
            $offsets = [System.Collections.Generic.List[int]]::new()
            # Japanese spellings confirmed in ALL's language-design discussion.
            # Canonicalize keywords only: literals and comments remain untouched.
            $jpKeywords = [System.Collections.Generic.Dictionary[string,string]]::new([System.StringComparer]::Ordinal)
            $jpKeywords['表示'] = 'print'
            $jpKeywords['変数'] = 'let'
            $jpKeywords['もし'] = 'if'
            $jpKeywords['表示行'] = 'println'
            $jpKeywords['それ以外'] = 'else'
            $jpKeywords['繰り返す'] = 'while'
            $jpKeywords['反復'] = 'for'
            $jpKeywords['各要素'] = 'foreach'
            $jpKeywords['内'] = 'in'
            $jpKeywords['関数'] = 'fn'
            $jpKeywords['返す'] = 'return'
            $jpKeywords['中断'] = 'break'
            $jpKeywords['次へ'] = 'continue'
            $jpKeywords['試す'] = 'try'
            $jpKeywords['捕捉'] = 'catch'
            $jpKeywords['投げる'] = 'throw'
            $jpKeywords['HTTP取得'] = 'http_get'
            $jpKeywords['HTTP送信'] = 'http_post'
            $jpKeywords['JSON送信'] = 'http_post_json'
            $jpKeywords['HTTP配信'] = 'http_serve'
            $jpKeywords['名前空間'] = 'namespace'
            $jpKeywords['データ保存'] = 'kv_put'
            $jpKeywords['データ取得'] = 'kv_get'
            $jpKeywords['データ削除'] = 'kv_delete'
            $jpKeywords['データ一覧'] = 'kv_keys'
            $jpKeywords['並列実行'] = 'parallel_all'
            $jpKeywords['引数一覧'] = 'cli_args'
            $jpKeywords['HTTP連続配信'] = 'http_serve_batch'
            $jpKeywords['HTTP常時配信'] = 'http_serve_live'
            $jpKeywords['標準入力'] = 'stdin_text'
            $jpKeywords['標準エラー出力'] = 'stderr_text'
            $jpKeywords['終了コード設定'] = 'set_exit_code'
            $jpKeywords['SQL検索'] = 'sql_query'
            $jpKeywords['SQL実行'] = 'sql_exec'
            $jpKeywords['SQL一括処理'] = 'sql_transaction'
            $jpKeywords['SQL移行'] = 'sql_migrate'
            $pattern = @'
(?:[ \t]+|\r\n|\n|\r|\#[^\r\n]*|//[^\r\n]*|"(?:\\.|[^"\\\r\n])*"|'(?:\\.|[^'\\\r\n])*'|(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+\-]?\d+)?|[\p{L}_][\p{L}\p{M}\p{Nd}_]*(?:::[\p{L}_][\p{L}\p{M}\p{Nd}_]*)*|<=|>=|==|!=|&&|\|\||[+\-*/%^(),;=<>!\[\]{}:])
'@
            $regex = [regex]::new($pattern.Trim())
            $depth = 0
            for ($offset = 0; $offset -lt $source.Length;) {
                $hit = $regex.Match($source, $offset)
                if (-not $hit.Success -or $hit.Index -ne $offset) {
                    throw "ALL Syntax Error: Unknown token at position $offset"
                }
                $rawToken = $hit.Value
                $token = $rawToken
                if ($jpKeywords.ContainsKey($token)) { $token = $jpKeywords[$token] }
                if ($token -match '^(?:\r\n|\n|\r)$') {
                    if ($depth -eq 0 -and $items.Count -gt 0 -and $items[$items.Count-1] -cne ';') {
                        [void]$items.Add(';')
                        [void]$offsets.Add($offset)
                    }
                } elseif ($token -match '^[ \t]+$' -or $token.StartsWith('#') -or $token.StartsWith('//')) {
                    # whitespace or comments
                } else {
                    if ($token -ceq '(' -or $token -ceq '[') { $depth++ }
                    if ($token -ceq ')' -or $token -ceq ']') {
                        $depth--
                        if ($depth -lt 0) { throw 'ALL Syntax Error: Unexpected closing parenthesis' }
                    }
                    [void]$items.Add($token)
                    [void]$offsets.Add($offset)
                }
                # Always advance by the original source length, not the translated keyword.
                $offset += $rawToken.Length
                if ($items.Count -gt 15000) { throw 'ALL: Token limit exceeded (15000)' }
            }
            if ($depth -ne 0) { throw 'ALL Syntax Error: Missing closing parenthesis' }
            [void]$items.Add('(EOF)')
            [void]$offsets.Add($source.Length)
            $state.TokenOffsets=$offsets.ToArray()
            return ,($items.ToArray())
        }
        function Peek-All {
            return $state.Tokens[$state.Pos]
        }
        function Next-All {
            $token = Peek-All
            if ($token -cne '(EOF)') { $state.Pos++ }
            return $token
        }
        function Expect-All([string]$expected) {
            if ((Peek-All) -cne $expected) {
                throw "ALL Syntax Error: Expected '$expected', got '$(Peek-All)'"
            }
            [void](Next-All)
        }
        function Decode-AllString([string]$token) {
            $builder = [System.Text.StringBuilder]::new()
            for ($i = 1; $i -lt $token.Length-1; $i++) {
                $ch = $token[$i]
                if ($ch -eq '\') {
                    $i++
                    if ($i -ge $token.Length - 1) { throw 'ALL Syntax Error: Invalid string escape' }
                    $next = $token[$i]
                    switch ([string]$next) {
                        'n' { [void]$builder.Append("`n") }
                        'r' { [void]$builder.Append("`r") }
                        't' { [void]$builder.Append("`t") }
                        '\' { [void]$builder.Append('\') }
                        '"' { [void]$builder.Append('"') }
                        "'" { [void]$builder.Append("'") }
                        default { throw "ALL Syntax Error: Unsupported string escape '\$next'" }
                    }
                } else {
                    [void]$builder.Append($ch)
                }
            }
            return $builder.ToString()
        }
        function Read-AllArguments {
            Expect-All '('
            $params = [System.Collections.Generic.List[object]]::new()
            if ((Peek-All) -cne ')') {
                while ($true) {
                    [void]$params.Add((Read-AllExpr 1))
                    if ((Peek-All) -cne ',') { break }
                    [void](Next-All)
                }
            }
            Expect-All ')'
            return ,($params.ToArray())
        }
        function Read-AllPrimary {
            $tok = Peek-All
            if ($tok -ceq '(') {
                [void](Next-All)
                $sub = Read-AllExpr 1
                Expect-All ')'
                return $sub
            }
            if ($tok -ceq '[') {
                [void](Next-All)
                $elements = [System.Collections.Generic.List[object]]::new()
                if ((Peek-All) -cne ']') {
                    while ($true) {
                        [void]$elements.Add((Read-AllExpr 1))
                        if ((Peek-All) -cne ',') { break }
                        [void](Next-All)
                        if ((Peek-All) -ceq ']') { break }
                    }
                }
                Expect-All ']'
                return [pscustomobject]@{ Kind='list'; Items=$elements.ToArray() }
            }
            if ($tok -ceq '{') {
                [void](Next-All)
                $entries = [System.Collections.Generic.List[object]]::new()
                if ((Peek-All) -cne '}') {
                    while ($true) {
                        $key = Read-AllExpr 1
                        Expect-All ':'
                        $item = Read-AllExpr 1
                        [void]$entries.Add([pscustomobject]@{ Key=$key; Value=$item })
                        if ((Peek-All) -cne ',') { break }
                        [void](Next-All)
                        if ((Peek-All) -ceq '}') { break }
                    }
                }
                Expect-All '}'
                return [pscustomobject]@{ Kind='map-literal'; Entries=$entries.ToArray() }
            }
            if ($tok -match '^(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+\-]?\d+)?$') {
                [void](Next-All)
                $number = $null
                if ($tok -match '[eE]') {
                    $number = [double]::Parse($tok, [System.Globalization.NumberStyles]::Float, $culture)
                } else {
                    try {
                        $number = [decimal]::Parse($tok, [System.Globalization.NumberStyles]::Float, $culture)
                    } catch {
                        $number = [double]::Parse($tok, [System.Globalization.NumberStyles]::Float, $culture)
                    }
                }
                if ($number -is [double] -and
                    ([double]::IsInfinity($number) -or [double]::IsNaN($number))) {
                    throw "ALL Math Error: Numeric literal out of range: $tok"
                }
                return [pscustomobject]@{ Kind='literal'; Value=$number }
            }
            if ($tok.StartsWith('"') -or $tok.StartsWith("'")) {
                [void](Next-All)
                return [pscustomobject]@{ Kind='literal'; Value=(Decode-AllString $tok) }
            }
            if ($tok -cin @('true','false','null')) {
                [void](Next-All)
                if ($tok -ceq 'true') { return [pscustomobject]@{ Kind='literal'; Value=$true } }
                if ($tok -ceq 'false') { return [pscustomobject]@{ Kind='literal'; Value=$false } }
                return [pscustomobject]@{ Kind='literal'; Value=$null }
            }
            if ($tok -cmatch '^[\p{L}_][\p{L}\p{M}\p{Nd}_]*(?:::[\p{L}_][\p{L}\p{M}\p{Nd}_]*)*$') {
                [void](Next-All)
                if ((Peek-All) -ceq '(') {
                    $callParams = Read-AllArguments
                    return [pscustomobject]@{ Kind='call'; Name=$tok; Args=@($callParams) }
                }
                return [pscustomobject]@{ Kind='name'; Name=$tok }
            }
            throw "ALL Syntax Error: Unsupported expression starting at '$tok'"
        }
        function Read-AllPostfix {
            $node = Read-AllPrimary
            while ((Peek-All) -ceq '[') {
                [void](Next-All)
                $index = Read-AllExpr 1
                Expect-All ']'
                $node = [pscustomobject]@{ Kind='index'; Base=$node; Index=$index }
            }
            return $node
        }
        function Read-AllUnary {
            $tok = Peek-All
            if ($tok -in @('+','-','!')) {
                [void](Next-All)
                return [pscustomobject]@{ Kind='unary'; Op=$tok; Operand=(Read-AllExpr 6) }
            }
            return (Read-AllPostfix)
        }
        function Get-AllPriority([string]$op) {
            switch -CaseSensitive ($op) {
                '||' { return 1 }
                '&&' { return 2 }
                '==' { return 3 }
                '!=' { return 3 }
                '<' { return 3 }
                '<=' { return 3 }
                '>' { return 3 }
                '>=' { return 3 }
                '+' { return 4 }
                '-' { return 4 }
                '*' { return 5 }
                '/' { return 5 }
                '%' { return 5 }
                '^' { return 7 }
                default { return 0 }
            }
        }
        function Read-AllExpr([int]$minPriority) {
            $left = Read-AllUnary
            while ($true) {
                $operator = Peek-All
                $priority = Get-AllPriority $operator
                if ($priority -lt $minPriority) { break }
                [void](Next-All)
                $rightPriority = if ($operator -ceq '^') { $priority } else { $priority + 1 }
                $right = Read-AllExpr $rightPriority
                $left = [pscustomobject]@{ Kind='binary'; Op=$operator; Left=$left; Right=$right }
            }
            return $left
        }
        function Read-AllIdentifier([string]$context) {
            $identifier = Next-All
            if ($identifier -cnotmatch '^[\p{L}_][\p{L}\p{M}\p{Nd}_]*$' -or
                $identifier -cin @('true','false','null','let','if','else','while','for','foreach','in','fn','return','break','continue','try','catch','throw','print','println','namespace')) {
                throw "ALL Syntax Error: Invalid identifier in $context"
            }
            if ($constants.ContainsKey($identifier)) {
                throw "ALL Syntax Error: Cannot assign to mathematical constant '$identifier'"
            }
            return $identifier
        }
        function Skip-AllSeparators {
            while ((Peek-All) -ceq ';') { [void](Next-All) }
        }
        function Read-AllBlock {
            # A newline may occur between ')' and '{'.
            Skip-AllSeparators
            Expect-All '{'
            $nodes = [System.Collections.Generic.List[object]]::new()
            while ((Peek-All) -cne '}') {
                if ((Peek-All) -ceq '(EOF)') { throw 'ALL Syntax Error: Unterminated block' }
                if ((Peek-All) -ceq ';') { [void](Next-All); continue }
                [void]$nodes.Add((Read-AllStatement))
                if ((Peek-All) -cne '}' -and (Peek-All) -cne ';') {
                    throw "ALL Syntax Error: Expected statement separator, got '$(Peek-All)'"
                }
            }
            Expect-All '}'
            return ,($nodes.ToArray())
        }
        function Read-AllCondition {
            Expect-All '('
            $condition = Read-AllExpr 1
            Expect-All ')'
            return $condition
        }
        function Read-AllIf {
            Expect-All 'if'
            $condition = Read-AllCondition
            $thenBody = Read-AllBlock
            $beforeElse = $state.Pos
            Skip-AllSeparators
            $otherwise = @()
            if ((Peek-All) -ceq 'else') {
                [void](Next-All)
                Skip-AllSeparators
                if ((Peek-All) -ceq 'if') {
                    $otherwise = @((Read-AllIf))
                } else {
                    $otherwise = Read-AllBlock
                }
            } else {
                # Do not consume separators if no else branch follows.
                $state.Pos = $beforeElse
            }
            return [pscustomobject]@{ Kind='if'; Cond=$condition; Then=$thenBody; Else=$otherwise }
        }
        function Read-AllAssignment([bool]$declaration) {
            if ($declaration) { Expect-All 'let' }
            $id = Read-AllIdentifier 'assignment'
            if ((Peek-All) -ceq '[' -and -not $declaration) {
                [void](Next-All)
                $index = Read-AllExpr 1
                Expect-All ']'
                Expect-All '='
                $value = Read-AllExpr 1
                return [pscustomobject]@{ Kind='set-index'; Name=$id; Index=$index; Expr=$value }
            }
            Expect-All '='
            $expr = Read-AllExpr 1
            return [pscustomobject]@{ Kind=$(if($declaration){'declare'}else{'reassign'}); Name=$id; Expr=$expr }
        }
        function Read-AllStatementCore {
            $token = Peek-All
            if ($token -in @('print','println')) {
                [void](Next-All)
                $callParams = Read-AllArguments
                if ($token -ceq 'print' -and $callParams.Count -ne 1) {
                    throw 'ALL Syntax Error: print() requires one expression'
                }
                if ($token -ceq 'println' -and $callParams.Count -gt 1) {
                    throw 'ALL Syntax Error: println() accepts zero or one expression'
                }
                return [pscustomobject]@{ Kind='output'; Newline=($token -ceq 'println'); Args=@($callParams) }
            }
            if ($token -ceq 'namespace') {
                [void](Next-All)
                $ns = Read-AllIdentifier 'namespace'
                $body = Read-AllBlock
                if ($body.Count -eq 0) { throw 'ALL Namespace Error: Namespace needs at least one function' }
                foreach ($member in $body) {
                    if ($member.Kind -cne 'function') {
                        throw 'ALL Namespace Error: Only function declarations are supported in namespace blocks'
                    }
                    $member.Name = $ns + '::' + $member.Name
                    [void]$state.KnownFunctions.Add($member.Name)
                }
                return [pscustomobject]@{ Kind='namespace'; Name=$ns; Members=$body }
            }
            if ($token -ceq 'let') { return (Read-AllAssignment $true) }
            if ($token -ceq 'if') { return (Read-AllIf) }
            if ($token -ceq 'while') {
                [void](Next-All)
                $cond = Read-AllCondition
                $state.LoopDepth++
                try { $body = Read-AllBlock } finally { $state.LoopDepth-- }
                return [pscustomobject]@{ Kind='while'; Cond=$cond; Body=$body }
            }
            if ($token -ceq 'for') {
                [void](Next-All)
                Expect-All '('
                $initial = $null
                if ((Peek-All) -cne ';') {
                    if ((Peek-All) -ceq 'let') { $initial = Read-AllAssignment $true }
                    else { $initial = Read-AllAssignment $false }
                }
                Expect-All ';'
                $cond = $null
                if ((Peek-All) -cne ';') { $cond = Read-AllExpr 1 }
                Expect-All ';'
                $update = $null
                if ((Peek-All) -cne ')') { $update = Read-AllAssignment $false }
                Expect-All ')'
                $state.LoopDepth++
                try { $body = Read-AllBlock } finally { $state.LoopDepth-- }
                return [pscustomobject]@{ Kind='for'; Init=$initial; Cond=$cond; Update=$update; Body=$body }
            }
            if ($token -ceq 'foreach') {
                [void](Next-All)
                Expect-All '('
                $variable = Read-AllIdentifier 'foreach variable'
                Expect-All 'in'
                $source = Read-AllExpr 1
                Expect-All ')'
                $state.LoopDepth++
                try { $body = Read-AllBlock } finally { $state.LoopDepth-- }
                return [pscustomobject]@{ Kind='foreach'; Variable=$variable; Source=$source; Body=$body }
            }
            if ($token -ceq 'try') {
                [void](Next-All)
                $body = Read-AllBlock
                Skip-AllSeparators
                Expect-All 'catch'
                Expect-All '('
                $errorName = Read-AllIdentifier 'catch variable'
                Expect-All ')'
                $handler = Read-AllBlock
                return [pscustomobject]@{ Kind='try'; Body=$body; ErrorName=$errorName; Handler=$handler }
            }
            if ($token -ceq 'throw') {
                [void](Next-All)
                $reason = Read-AllExpr 1
                return [pscustomobject]@{ Kind='throw'; Expr=$reason }
            }
            if ($token -ceq 'fn') {
                if ($state.FunctionDepth -gt 0) { throw 'ALL Syntax Error: Nested functions are not supported' }
                [void](Next-All)
                $name = Read-AllIdentifier 'function declaration'
                [void]$state.KnownFunctions.Add($name)
                Expect-All '('
                $params = [System.Collections.Generic.List[string]]::new()
                if ((Peek-All) -cne ')') {
                    while ($true) {
                        $param = Read-AllIdentifier 'parameter list'
                        if ($params.Contains($param)) { throw "ALL Syntax Error: Duplicate parameter '$param'" }
                        [void]$params.Add($param)
                        if ((Peek-All) -cne ',') { break }
                        [void](Next-All)
                    }
                }
                Expect-All ')'
                $previousLoopDepth = $state.LoopDepth
                $state.LoopDepth = 0
                $state.FunctionDepth++
                try { $body = Read-AllBlock }
                finally { $state.FunctionDepth--; $state.LoopDepth = $previousLoopDepth }
                return [pscustomobject]@{ Kind='function'; Name=$name; Params=$params.ToArray(); Body=$body }
            }
            if ($token -ceq 'return') {
                if ($state.FunctionDepth -eq 0) { throw 'ALL Syntax Error: return outside function' }
                [void](Next-All)
                $expr = $null
                if ((Peek-All) -cne ';' -and (Peek-All) -cne '}') { $expr = Read-AllExpr 1 }
                return [pscustomobject]@{ Kind='return'; Expr=$expr }
            }
            if ($token -ceq 'break' -or $token -ceq 'continue') {
                if ($state.LoopDepth -eq 0) { throw "ALL Syntax Error: $token outside loop" }
                [void](Next-All)
                return [pscustomobject]@{ Kind=$token }
            }
            if ($token -cmatch '^[\p{L}_][\p{L}\p{M}\p{Nd}_]*(?:::[\p{L}_][\p{L}\p{M}\p{Nd}_]*)*$') {
                # Assignment may be followed by indexed writes. Calls in statement
                # position are allowed only for previously defined user functions or push().
                $nextToken = if (($state.Pos+1) -lt $state.Tokens.Count) { $state.Tokens[$state.Pos+1] } else { '(EOF)' }
                if ($nextToken -ceq '=' -or $nextToken -ceq '[') { return (Read-AllAssignment $false) }
                if ($nextToken -ceq '(') {
                    if ($token -cnotin @('push','pop','remove_key','write_text','append_text','write_json','input','http_serve','http_serve_batch','http_serve_live','kv_put','kv_delete','parallel_all','stderr_text','set_exit_code','sql_query','sql_exec','sql_transaction','sql_migrate') -and -not $state.KnownFunctions.Contains($token)) {
                        throw "ALL Syntax Error: Unknown statement '$token'"
                    }
                    $node = Read-AllExpr 1
                    return [pscustomobject]@{ Kind='call-statement'; Expr=$node; Name=$token }
                }
            }
            throw "ALL Syntax Error: Unknown statement '$token'"
        }

        function Read-AllStatement {
            $at=$state.Pos
            $node=Read-AllStatementCore
            if($null -ne $node -and $at -lt $state.TokenOffsets.Count){
                $offset=[int]$state.TokenOffsets[$at]
                if($offset -ge 0 -and $offset -le $Code.Length){
                    # Binary search into the line-start index; preserve original
                    # SourceLine/SourceColumn as preprocessed positions.
                    $lineIndex=$sourceLineStarts.BinarySearch($offset)
                    if($lineIndex -lt 0){$lineIndex = (-$lineIndex) - 2}
                    $line=$lineIndex+1
                    $column=$offset-$sourceLineStarts[$lineIndex]+1
                    $origin=$sourceOrigins[$lineIndex]
                    $node | Add-Member -NotePropertyName SourceLine -NotePropertyValue $line -Force
                    $node | Add-Member -NotePropertyName SourceColumn -NotePropertyValue $column -Force
                    $node | Add-Member -NotePropertyName OriginalSourceFile -NotePropertyValue $origin.File -Force
                    $node | Add-Member -NotePropertyName OriginalSourceLine -NotePropertyValue $origin.Line -Force
                }
            }
            return $node
        }
        $state.Tokens = Tokenize-All $Code
        $statements = [System.Collections.Generic.List[object]]::new()
        while ((Peek-All) -cne '(EOF)') {
            if ((Peek-All) -ceq ';') { [void](Next-All); continue }
            [void]$statements.Add((Read-AllStatement))
            if ((Peek-All) -cne '(EOF)' -and (Peek-All) -cne ';') {
                throw "ALL Syntax Error: Expected statement separator, got '$(Peek-All)'"
            }
        }

        # Debugger is opt-in. Structured JSONL trace never changes program values.
        $traceFile=[Environment]::GetEnvironmentVariable('ALL_TRACE_PATH','Process')
        if(-not [string]::IsNullOrWhiteSpace($traceFile)){
            $traceFile=[IO.Path]::GetFullPath($traceFile)
            $state.TraceWriter=[IO.StreamWriter]::new($traceFile,$false,[Text.UTF8Encoding]::new($false))
        }
        $bp=[Environment]::GetEnvironmentVariable('ALL_BREAKPOINT_LINES','Process')
        if(-not [string]::IsNullOrEmpty($bp)){
            $state.DebugMode=$true
            foreach($value in ($bp -split ',')){
                $number=0
                if(-not [int]::TryParse($value,[ref]$number) -or $number -lt 1){throw 'ALL Debugger Error: Invalid breakpoint line'}
                $state.Breakpoints+=($number)
            }
        }
        function Write-AllTrace([string]$eventName,$stmt,$extra=''){
            if($null -eq $state.TraceWriter){return}
            $entry=[ordered]@{
                utc=[DateTime]::UtcNow.ToString('o')
                event=$eventName
                line=$(if($null -ne $stmt -and $stmt.PSObject.Properties['SourceLine']){$stmt.SourceLine}else{$state.CurrentLine})
                column=$(if($null -ne $stmt -and $stmt.PSObject.Properties['SourceColumn']){$stmt.SourceColumn}else{0})
                source_file=$(if($null -ne $stmt -and $stmt.PSObject.Properties['OriginalSourceFile']){$stmt.OriginalSourceFile}else{$state.CurrentSourceFile})
                source_line=$(if($null -ne $stmt -and $stmt.PSObject.Properties['OriginalSourceLine']){$stmt.OriginalSourceLine}else{$state.CurrentOriginalLine})
                kind=$(if($null -ne $stmt){$stmt.Kind}else{''})
                step=$state.Steps
                function_stack=@($state.DebugFunctions.ToArray())
                detail=[string]$extra
            }
            $state.TraceWriter.WriteLine(($entry | ConvertTo-Json -Compress -Depth 6))
            $state.TraceWriter.Flush()
        }
        function Invoke-AllDebugPrompt($stmt) {
            if(-not $state.DebugMode -or $null -eq $stmt -or -not $stmt.PSObject.Properties['SourceLine']){return}
            $line=[int]$stmt.SourceLine
            if($line -eq $state.LastDebugLine){return}
            if($state.Breakpoints.Count -gt 0 -and $line -notin $state.Breakpoints){return}
            $state.LastDebugLine=$line
            while($true){
                [Console]::Error.WriteLine(('ALL DEBUG line='+$line+' kind='+$stmt.Kind+' commands: next | vars | stack | quit'))
                $cmd=[Console]::ReadLine()
                if($cmd -ceq 'next' -or $cmd -ceq 'continue' -or [string]::IsNullOrEmpty($cmd)){return}
                if($cmd -ceq 'stack'){
                    [Console]::Error.WriteLine(([string]::Join(' -> ',$state.DebugFunctions.ToArray())))
                } elseif($cmd -ceq 'vars'){
                    [Console]::Error.WriteLine(('Local variable names: '+[string]::Join(', ',@($state.Vars.Keys))))
                } elseif($cmd -ceq 'quit'){throw 'ALL Debugger: stopped by operator'}
                else {[Console]::Error.WriteLine('Unknown debugger command')}
            }
        }
        function Is-AllNumber($value) {
            return ($value -is [decimal] -or $value -is [double] -or
                    $value -is [int] -or $value -is [long])
        }
        function Require-AllNumber($value) {
            if (-not (Is-AllNumber $value)) { throw 'ALL Math Error: Numeric value required' }
            return $value
        }
        function To-AllDouble($value) {
            [void](Require-AllNumber $value)
            $num = [double]$value
            if ([double]::IsInfinity($num) -or [double]::IsNaN($num)) {
                throw 'ALL Math Error: Non-finite numeric input'
            }
            return $num
        }
        function To-AllInteger($value, [string]$name, [long]$minimum, [long]$maximum) {
            $num = To-AllDouble $value
            if ($num -ne [Math]::Truncate($num) -or $num -lt $minimum -or $num -gt $maximum) {
                throw "ALL Math Error: $name requires an integer in [$minimum, $maximum]"
            }
            return [long]$num
        }
        function Is-AllList($value) {
            return ($null -ne $value -and $value -is [pscustomobject] -and
                    $value.PSObject.Properties['AllType'] -and $value.AllType -ceq 'list')
        }
        function New-AllList($values) {
            $items = [System.Collections.Generic.List[object]]::new()
            foreach ($v in $values) { [void]$items.Add($v) }
            return [pscustomobject]@{ AllType='list'; Items=$items }
        }
        function Is-AllMap($value) {
            return ($null -ne $value -and $value -is [pscustomobject] -and
                    $value.PSObject.Properties['AllType'] -and $value.AllType -ceq 'map')
        }
        function New-AllMap {
            return [pscustomobject]@{ AllType='map'; Items=([System.Collections.Specialized.OrderedDictionary]::new([System.StringComparer]::Ordinal)) }
        }
        function Get-AllKey($key) {
            if ($key -isnot [string] -and -not (Is-AllNumber $key)) {
                throw 'ALL Type Error: Dictionary key must be a string or number'
            }
            return (To-AllText $key)
        }
        function Get-AllListItem($value, $index) {
            if (Is-AllMap $value) {
                $key = Get-AllKey $index
                if (-not $value.Items.Contains($key)) { throw "ALL Key Error: Missing key '$key'" }
                return $value.Items[$key]
            }
            if (-not (Is-AllList $value)) { throw 'ALL Type Error: Indexing requires a list or map' }
            $idx = To-AllInteger $index 'list index' 0 2147483647
            if ($idx -ge $value.Items.Count) { throw 'ALL Index Error: Index out of range' }
            return $value.Items[[int]$idx]
        }
        function Is-AllVector($value) {
            return ($null -ne $value -and $value.PSObject.Properties['AllType'] -and
                    $value.AllType -ceq 'vector')
        }
        function Is-AllMatrix($value) {
            return ($null -ne $value -and $value.PSObject.Properties['AllType'] -and
                    $value.AllType -ceq 'matrix')
        }
        function Format-AllNumber($number) {
            if ($number -is [decimal]) {
                return $number.ToString('0.############################', $culture)
            }
            if ($number -is [double]) {
                if ([double]::IsInfinity($number) -or [double]::IsNaN($number)) {
                    throw 'ALL Math Error: Non-finite result'
                }
                return $number.ToString('G15', $culture)
            }
            return ([string]::Format($culture, '{0}', $number))
        }
        function To-AllText($value) {
            if ($null -eq $value) { return 'null' }
            if ($value -is [bool]) { if ($value) { return 'true' } else { return 'false' } }
            if (Is-AllNumber $value) { return (Format-AllNumber $value) }
            if (Is-AllList $value) {
                $parts = [System.Collections.Generic.List[string]]::new()
                foreach ($v in $value.Items) { [void]$parts.Add((To-AllText $v)) }
                return ('[' + [string]::Join(',', $parts) + ']')
            }
            if (Is-AllMap $value) {
                $parts = [System.Collections.Generic.List[string]]::new()
                foreach ($key in $value.Items.Keys) {
                    [void]$parts.Add(('"' + [string]$key + '":' + (To-AllText $value.Items[$key])))
                }
                return ('{' + [string]::Join(',', $parts) + '}')
            }
            if (Is-AllVector $value) {
                $parts = [System.Collections.Generic.List[string]]::new()
                foreach ($v in $value.Values) { [void]$parts.Add((Format-AllNumber $v)) }
                return ('[' + [string]::Join(',', $parts) + ']')
            }
            if (Is-AllMatrix $value) {
                $rows = [System.Collections.Generic.List[string]]::new()
                for ($r=0; $r -lt $value.Rows; $r++) {
                    $cells = [System.Collections.Generic.List[string]]::new()
                    for ($c=0; $c -lt $value.Cols; $c++) {
                        [void]$cells.Add((Format-AllNumber $value.Values[$r * $value.Cols + $c]))
                    }
                    [void]$rows.Add(('[' + [string]::Join(',', $cells) + ']'))
                }
                return ('[' + [string]::Join(',', $rows) + ']')
            }
            if ($value -is [string]) { return $value }
            throw 'ALL Math Error: Unsupported output type'
        }
        function Is-AllTrue($value) {
            if ($null -eq $value) { return $false }
            if ($value -is [bool]) { return $value }
            if (Is-AllNumber $value) { return ((To-AllDouble $value) -ne 0) }
            if ($value -is [string]) { return ($value.Length -ne 0) }
            if (Is-AllList $value) { return ($value.Items.Count -gt 0) }
            if (Is-AllMap $value) { return ($value.Items.Count -gt 0) }
            throw 'ALL Math Error: Value cannot be used as condition'
        }
        function Apply-AllBinary($a, $b, [string]$operator) {
            if ($operator -in @('==','!=')) {
                if ((Is-AllNumber $a) -and (Is-AllNumber $b)) {
                    if ($a -isnot [double] -and $b -isnot [double]) {
                        $eq = ([decimal]$a -eq [decimal]$b)
                    } else {
                        $eq = ((To-AllDouble $a) -eq (To-AllDouble $b))
                    }
                } elseif ($a -is [string] -and $b -is [string]) {
                    $eq = ($a -ceq $b)
                } else {
                    $eq = ($a -ceq $b)
                }
                if ($operator -ceq '==') { return $eq }
                return (-not $eq)
            }
            if ($operator -in @('<','<=','>','>=')) {
                $a = To-AllDouble $a
                $b = To-AllDouble $b
                switch -CaseSensitive ($operator) {
                    '<' { return ($a -lt $b) }
                    '<=' { return ($a -le $b) }
                    '>' { return ($a -gt $b) }
                    '>=' { return ($a -ge $b) }
                }
            }
            [void](Require-AllNumber $a)
            [void](Require-AllNumber $b)
            if ($operator -ceq '^') {
                $result = [Math]::Pow((To-AllDouble $a), (To-AllDouble $b))
                if ([double]::IsNaN($result) -or [double]::IsInfinity($result)) {
                    throw 'ALL Math Error: Exponentiation domain/overflow error'
                }
                return $result
            }
            if ($operator -ceq '/' -or $operator -ceq '%') {
                if ([double]$b -eq 0.0) { throw 'ALL Math Error: Division by zero' }
            }
            if ($a -is [double] -or $b -is [double]) {
                $a = [double]$a
                $b = [double]$b
            } else {
                $a = [decimal]$a
                $b = [decimal]$b
            }
            switch -CaseSensitive ($operator) {
                '+' { $answer = $a + $b }
                '-' { $answer = $a - $b }
                '*' { $answer = $a * $b }
                '/' { $answer = $a / $b }
                '%' { $answer = $a % $b }
                default { throw "ALL Math Error: Unsupported operator '$operator'" }
            }
            if ($answer -is [double] -and
                ([double]::IsNaN($answer) -or [double]::IsInfinity($answer))) {
                throw 'ALL Math Error: Non-finite result'
            }
            return $answer
        }
        function Require-ArgCount([string]$name, $callParams, [int]$min, [int]$max) {
            if ($callParams.Count -lt $min -or $callParams.Count -gt $max) {
                throw "ALL Math Error: $name() accepts $min to $max argument(s), got $($callParams.Count)"
            }
        }
        function Require-AllVector($value) {
            if (-not (Is-AllVector $value)) { throw 'ALL Math Error: Vector argument required' }
            return $value
        }
        function Require-AllMatrix($value) {
            if (-not (Is-AllMatrix $value)) { throw 'ALL Math Error: Matrix argument required' }
            return $value
        }
        function New-AllVector($callParams) {
            if ($callParams.Count -gt 1024) { throw 'ALL Math Error: Vector length limited to 1024' }
            $values = [double[]]::new($callParams.Count)
            for ($idx=0; $idx -lt $callParams.Count; $idx++) {
                $values[$idx] = To-AllDouble $callParams[$idx]
            }
            return [pscustomobject]@{ AllType='vector'; Values=$values }
        }
        function New-AllMatrix([int]$rows, [int]$cols, [double[]]$values) {
            return [pscustomobject]@{ AllType='matrix'; Rows=$rows; Cols=$cols; Values=$values }
        }
        function Get-AllSeries($callParams, [string]$name) {
            if ($callParams.Count -eq 1 -and (Is-AllVector $callParams[0])) {
                $nums = $callParams[0].Values
            } else {
                $nums = [double[]]::new($callParams.Count)
                for ($i=0; $i -lt $callParams.Count; $i++) {
                    $nums[$i] = To-AllDouble $callParams[$i]
                }
            }
            if ($nums.Length -eq 0) { throw "ALL Math Error: $name() requires data" }
            return ,([double[]]$nums)
        }
        function Eval-AllExpression($node) {
            $state.Count++
            if ($state.Count -gt 100000) { throw 'ALL Math Error: Evaluation step limit exceeded' }
            switch ($node.Kind) {
                'literal' { return $node.Value }
                'list' {
                    $values = [System.Collections.Generic.List[object]]::new()
                    foreach ($item in $node.Items) { [void]$values.Add((Eval-AllExpression $item)) }
                    return (New-AllList ($values.ToArray()))
                }
                'map-literal' {
                    $dict = New-AllMap
                    foreach ($entry in $node.Entries) {
                        $key = Get-AllKey (Eval-AllExpression $entry.Key)
                        if ($dict.Items.Contains($key)) { throw "ALL Key Error: Duplicate key '$key'" }
                        $dict.Items.Add($key, (Eval-AllExpression $entry.Value))
                    }
                    return $dict
                }
                'index' {
                    $base = Eval-AllExpression $node.Base
                    $at = Eval-AllExpression $node.Index
                    return (Get-AllListItem $base $at)
                }
                'name' {
                    if ($constants.ContainsKey($node.Name)) { return $constants[$node.Name] }
                    if (-not $state.Vars.ContainsKey($node.Name)) {
                        throw "ALL Name Error: Undefined variable '$($node.Name)'"
                    }
                    return $state.Vars[$node.Name]
                }
                'unary' {
                    $number = Eval-AllExpression $node.Operand
                    switch -CaseSensitive ($node.Op) {
                        '+' { return (Require-AllNumber $number) }
                        '-' { return (-(Require-AllNumber $number)) }
                        '!' { return (-not (Is-AllTrue $number)) }
                    }
                }
                'binary' {
                    if ($node.Op -ceq '&&') {
                        $left = Eval-AllExpression $node.Left
                        if (-not (Is-AllTrue $left)) { return $false }
                        return (Is-AllTrue (Eval-AllExpression $node.Right))
                    }
                    if ($node.Op -ceq '||') {
                        $left = Eval-AllExpression $node.Left
                        if (Is-AllTrue $left) { return $true }
                        return (Is-AllTrue (Eval-AllExpression $node.Right))
                    }
                    $left = Eval-AllExpression $node.Left
                    $right = Eval-AllExpression $node.Right
                    return (Apply-AllBinary $left $right $node.Op)
                }
                'call' {
                    $values = [System.Collections.Generic.List[object]]::new()
                    foreach ($child in $node.Args) {
                        [void]$values.Add((Eval-AllExpression $child))
                    }
                    if ($state.Functions.ContainsKey($node.Name)) {
                        return (Invoke-AllFunction $node.Name ($values.ToArray()))
                    }
                    if ($node.Name -cin @('len','push','pop','concat','keys','values','has_key','remove_key',
                        'read_text','write_text','append_text','file_exists','json_encode','json_decode',
                        'read_json','write_json','input','http_get','http_post','http_post_json','http_serve',
                        'kv_put','kv_get','kv_delete','kv_keys','parallel_all','cli_args','http_serve_batch','http_serve_live','stdin_text','stderr_text','set_exit_code','sql_query','sql_exec','sql_transaction','sql_migrate')) {
                        return (Invoke-AllListBuiltin $node.Name ($values.ToArray()))
                    }
                    return (Invoke-AllMath $node.Name ($values.ToArray()))
                }
                default { throw "ALL Math Error: Unknown AST type '$($node.Kind)'" }
            }
            throw 'ALL Math Error: Expression did not return a value'
        }
        function Parse-AllSubExpression([string]$source) {
            $savedTokens = $state.Tokens
            $savedOffsets = $state.TokenOffsets
            $savedPos = $state.Pos
            try {
                $state.Tokens = Tokenize-All $source
                $state.Pos = 0
                $node = Read-AllExpr 1
                while ((Peek-All) -ceq ';') { [void](Next-All) }
                if ((Peek-All) -cne '(EOF)') { throw 'ALL Math Error: Calculus expression must be a single expression' }
                return $node
            } finally {
                $state.Tokens = $savedTokens
                $state.TokenOffsets = $savedOffsets
                $state.Pos = $savedPos
            }
        }
        function Eval-AllAtX($ast, [double]$x) {
            $hadX = $state.Vars.ContainsKey('x')
            $savedX = $null
            if ($hadX) { $savedX = $state.Vars['x'] }
            $state.Vars['x'] = $x
            try {
                return (To-AllDouble (Eval-AllExpression $ast))
            } finally {
                if ($hadX) { $state.Vars['x'] = $savedX }
                else { [void]$state.Vars.Remove('x') }
            }
        }
        function Invoke-AllMath([string]$name, $callParams) {
            $name = $name.ToLowerInvariant()
            switch ($name) {
                'abs' { Require-ArgCount $name $callParams 1 1; $n=Require-AllNumber $callParams[0]; if($n -is [decimal]){return [Math]::Abs([decimal]$n)}; return [Math]::Abs([double]$n) }
                'sqrt' { Require-ArgCount $name $callParams 1 1; $n=To-AllDouble $callParams[0]; if($n -lt 0){throw 'ALL Math Error: sqrt domain: x < 0'}; return [Math]::Sqrt($n) }
                'cbrt' { Require-ArgCount $name $callParams 1 1; $n=To-AllDouble $callParams[0]; return ([Math]::Sign($n)*[Math]::Pow([Math]::Abs($n), 1.0/3.0)) }
                'pow' { Require-ArgCount $name $callParams 2 2; return (Apply-AllBinary $callParams[0] $callParams[1] '^') }
                'floor' { Require-ArgCount $name $callParams 1 1; return [Math]::Floor((To-AllDouble $callParams[0])) }
                'ceil' { Require-ArgCount $name $callParams 1 1; return [Math]::Ceiling((To-AllDouble $callParams[0])) }
                'trunc' { Require-ArgCount $name $callParams 1 1; return [Math]::Truncate((To-AllDouble $callParams[0])) }
                'sign' { Require-ArgCount $name $callParams 1 1; return [decimal]([Math]::Sign((To-AllDouble $callParams[0]))) }
                'round' {
                    Require-ArgCount $name $callParams 1 2
                    $precision=0
                    if($callParams.Count -eq 2){$precision=[int](To-AllInteger $callParams[1] 'round precision' -10 10)}
                    $n=To-AllDouble $callParams[0]
                    if ($precision -ge 0) {
                        if ($precision -le 10) { return [Math]::Round($n, $precision, [System.MidpointRounding]::AwayFromZero) }
                    }
                    $scale = [Math]::Pow(10, -$precision)
                    return ([Math]::Round($n/$scale,0,[System.MidpointRounding]::AwayFromZero)*$scale)
                }
                'min' { $items=Get-AllSeries $callParams $name; $v=[double]::PositiveInfinity;foreach($n in $items){if($n -lt $v){$v=$n}};return $v }
                'max' { $items=Get-AllSeries $callParams $name; $v=[double]::NegativeInfinity;foreach($n in $items){if($n -gt $v){$v=$n}};return $v }
                'clamp' { Require-ArgCount $name $callParams 3 3; $v=To-AllDouble $callParams[0];$lo=To-AllDouble $callParams[1];$hi=To-AllDouble $callParams[2];if($lo -gt $hi){throw 'ALL Math Error: clamp minimum exceeds maximum'};return [Math]::Max($lo,[Math]::Min($hi,$v)) }
                'exp' { Require-ArgCount $name $callParams 1 1; $v=[Math]::Exp((To-AllDouble $callParams[0]));if([double]::IsInfinity($v)){throw 'ALL Math Error: exp overflow'};return $v }
                'log' {
                    Require-ArgCount $name $callParams 1 2
                    $n=To-AllDouble $callParams[0]
                    if($n -le 0){throw 'ALL Math Error: log domain: x <= 0'}
                    if($callParams.Count -eq 2){
                        $base=To-AllDouble $callParams[1]
                        if($base -le 0 -or $base -eq 1){throw 'ALL Math Error: Invalid log base'}
                        return [Math]::Log($n,$base)
                    }
                    return [Math]::Log($n)
                }
                'log10' { Require-ArgCount $name $callParams 1 1;$n=To-AllDouble $callParams[0];if($n -le 0){throw 'ALL Math Error: log10 domain'};return [Math]::Log10($n) }
                'log2' { Require-ArgCount $name $callParams 1 1;$n=To-AllDouble $callParams[0];if($n -le 0){throw 'ALL Math Error: log2 domain'};return [Math]::Log($n,2.0) }
                'sin' { Require-ArgCount $name $callParams 1 1;return [Math]::Sin((To-AllDouble $callParams[0])) }
                'cos' { Require-ArgCount $name $callParams 1 1;return [Math]::Cos((To-AllDouble $callParams[0])) }
                'tan' { Require-ArgCount $name $callParams 1 1;return [Math]::Tan((To-AllDouble $callParams[0])) }
                'asin' { Require-ArgCount $name $callParams 1 1;$n=To-AllDouble $callParams[0];if([Math]::Abs($n) -gt 1){throw 'ALL Math Error: asin domain'};return [Math]::Asin($n) }
                'acos' { Require-ArgCount $name $callParams 1 1;$n=To-AllDouble $callParams[0];if([Math]::Abs($n) -gt 1){throw 'ALL Math Error: acos domain'};return [Math]::Acos($n) }
                'atan' { Require-ArgCount $name $callParams 1 1;return [Math]::Atan((To-AllDouble $callParams[0])) }
                'atan2' { Require-ArgCount $name $callParams 2 2;return [Math]::Atan2((To-AllDouble $callParams[0]),(To-AllDouble $callParams[1])) }
                'sinh' { Require-ArgCount $name $callParams 1 1;return [Math]::Sinh((To-AllDouble $callParams[0])) }
                'cosh' { Require-ArgCount $name $callParams 1 1;return [Math]::Cosh((To-AllDouble $callParams[0])) }
                'tanh' { Require-ArgCount $name $callParams 1 1;return [Math]::Tanh((To-AllDouble $callParams[0])) }
                'rad' { Require-ArgCount $name $callParams 1 1;return ((To-AllDouble $callParams[0])*[Math]::PI/180.0) }
                'deg' { Require-ArgCount $name $callParams 1 1;return ((To-AllDouble $callParams[0])*180.0/[Math]::PI) }
                'hypot' { Require-ArgCount $name $callParams 2 2;$a=To-AllDouble $callParams[0];$b=To-AllDouble $callParams[1];return [Math]::Sqrt($a*$a+$b*$b) }
                'factorial' {
                    Require-ArgCount $name $callParams 1 1
                    $n=To-AllInteger $callParams[0] $name 0 27
                    $result=[decimal]1
                    for($i=2;$i -le $n;$i++){$result*=[decimal]$i}
                    return $result
                }
                'gcd' {
                    Require-ArgCount $name $callParams 2 2
                    $a=To-AllInteger $callParams[0] $name -1000000000 1000000000
                    $b=To-AllInteger $callParams[1] $name -1000000000 1000000000
                    $a=[Math]::Abs($a);$b=[Math]::Abs($b)
                    while($b -ne 0){$t=$b;$b=$a%$b;$a=$t}
                    return [decimal]$a
                }
                'lcm' {
                    Require-ArgCount $name $callParams 2 2
                    $a=To-AllInteger $callParams[0] $name -1000000000 1000000000
                    $b=To-AllInteger $callParams[1] $name -1000000000 1000000000
                    if($a -eq 0 -or $b -eq 0){return [decimal]0}
                    $x=[Math]::Abs($a);$y=[Math]::Abs($b)
                    while($y -ne 0){$t=$y;$y=$x%$y;$x=$t}
                    return [decimal](([Math]::Abs($a)/$x)*[Math]::Abs($b))
                }
                'choose' {
                    Require-ArgCount $name $callParams 2 2
                    $n=To-AllInteger $callParams[0] $name 0 27
                    $k=To-AllInteger $callParams[1] $name 0 27
                    if($k -gt $n){throw 'ALL Math Error: choose requires k <= n'}
                    $k=[Math]::Min($k,$n-$k)
                    $result=[decimal]1
                    for($i=1;$i -le $k;$i++){$result=$result*[decimal]($n-$k+$i)/[decimal]$i}
                    return [decimal]::Round($result,0,[System.MidpointRounding]::AwayFromZero)
                }
                'perm' {
                    Require-ArgCount $name $callParams 2 2
                    $n=To-AllInteger $callParams[0] $name 0 27
                    $k=To-AllInteger $callParams[1] $name 0 27
                    if($k -gt $n){throw 'ALL Math Error: perm requires k <= n'}
                    $result=[decimal]1
                    for($i=0;$i -lt $k;$i++){$result*=[decimal]($n-$i)}
                    return $result
                }
                'fib' {
                    Require-ArgCount $name $callParams 1 1
                    $n=To-AllInteger $callParams[0] $name 0 100
                    $a=[decimal]0;$b=[decimal]1
                    for($i=0;$i -lt $n;$i++){$t=$a+$b;$a=$b;$b=$t}
                    return $a
                }
                'isprime' {
                    Require-ArgCount $name $callParams 1 1
                    $n=To-AllInteger $callParams[0] $name 0 1000000000
                    if($n -lt 2){return $false}
                    if($n -eq 2){return $true}
                    if($n % 2 -eq 0){return $false}
                    for($i=3; $i*$i -le $n; $i+=2){if($n % $i -eq 0){return $false}}
                    return $true
                }
                'vec' { return (New-AllVector $callParams) }
                'dot' {
                    Require-ArgCount $name $callParams 2 2
                    $a=Require-AllVector $callParams[0];$b=Require-AllVector $callParams[1]
                    if($a.Values.Length -ne $b.Values.Length){throw 'ALL Math Error: Vector dimensions mismatch'}
                    $result=0.0
                    for($i=0;$i -lt $a.Values.Length;$i++){$result += $a.Values[$i]*$b.Values[$i]}
                    return $result
                }
                'norm' {
                    Require-ArgCount $name $callParams 1 1
                    $a=Require-AllVector $callParams[0];$sum=0.0
                    foreach($n in $a.Values){$sum+=$n*$n}
                    return [Math]::Sqrt($sum)
                }
                'distance' {
                    Require-ArgCount $name $callParams 2 2
                    $a=Require-AllVector $callParams[0];$b=Require-AllVector $callParams[1]
                    if($a.Values.Length -ne $b.Values.Length){throw 'ALL Math Error: Vector dimensions mismatch'}
                    $sum=0.0
                    for($i=0;$i -lt $a.Values.Length;$i++){$d=$a.Values[$i]-$b.Values[$i];$sum+=$d*$d}
                    return [Math]::Sqrt($sum)
                }
                'cross' {
                    Require-ArgCount $name $callParams 2 2
                    $a=Require-AllVector $callParams[0];$b=Require-AllVector $callParams[1]
                    if($a.Values.Length -ne 3 -or $b.Values.Length -ne 3){throw 'ALL Math Error: cross requires two 3D vectors'}
                    return (New-AllVector @(
                        ($a.Values[1]*$b.Values[2]-$a.Values[2]*$b.Values[1]),
                        ($a.Values[2]*$b.Values[0]-$a.Values[0]*$b.Values[2]),
                        ($a.Values[0]*$b.Values[1]-$a.Values[1]*$b.Values[0])
                    ))
                }
                'mat' {
                    if($callParams.Count -lt 2){throw 'ALL Math Error: mat(rows, cols, ...)'}
                    $rows=[int](To-AllInteger $callParams[0] 'matrix rows' 1 20)
                    $cols=[int](To-AllInteger $callParams[1] 'matrix cols' 1 20)
                    if($callParams.Count -ne ($rows*$cols+2)){throw 'ALL Math Error: Matrix element count mismatch'}
                    $values=[double[]]::new($rows*$cols)
                    for($i=0;$i -lt $values.Length;$i++){$values[$i]=To-AllDouble $callParams[$i+2]}
                    return (New-AllMatrix $rows $cols $values)
                }
                'transpose' {
                    Require-ArgCount $name $callParams 1 1
                    $a=Require-AllMatrix $callParams[0]
                    $values=[double[]]::new($a.Rows*$a.Cols)
                    for($r=0;$r -lt $a.Rows;$r++){for($c=0;$c -lt $a.Cols;$c++){
                        $values[$c*$a.Rows+$r]=$a.Values[$r*$a.Cols+$c]
                    }}
                    return (New-AllMatrix $a.Cols $a.Rows $values)
                }
                'matmul' {
                    Require-ArgCount $name $callParams 2 2
                    $a=Require-AllMatrix $callParams[0];$b=Require-AllMatrix $callParams[1]
                    if($a.Cols -ne $b.Rows){throw 'ALL Math Error: Matrix dimensions mismatch'}
                    $values=[double[]]::new($a.Rows*$b.Cols)
                    for($r=0;$r -lt $a.Rows;$r++){for($c=0;$c -lt $b.Cols;$c++){
                        $acc=0.0
                        for($k=0;$k -lt $a.Cols;$k++){$acc+=$a.Values[$r*$a.Cols+$k]*$b.Values[$k*$b.Cols+$c]}
                        $values[$r*$b.Cols+$c]=$acc
                    }}
                    return (New-AllMatrix $a.Rows $b.Cols $values)
                }
                'det' {
                    Require-ArgCount $name $callParams 1 1
                    $a=Require-AllMatrix $callParams[0]
                    if($a.Rows -ne $a.Cols){throw 'ALL Math Error: Determinant requires square matrix'}
                    $n=$a.Rows
                    $tmp=[double[]]::new($a.Values.Length)
                    [Array]::Copy($a.Values,$tmp,$tmp.Length)
                    $answer=1.0
                    for($k=0;$k -lt $n;$k++){
                        $pivot=$k
                        for($i=$k+1;$i -lt $n;$i++){if([Math]::Abs($tmp[$i*$n+$k]) -gt [Math]::Abs($tmp[$pivot*$n+$k])){$pivot=$i}}
                        if([Math]::Abs($tmp[$pivot*$n+$k]) -le 1e-12){return 0.0}
                        if($pivot -ne $k){for($j=0;$j -lt $n;$j++){$t=$tmp[$k*$n+$j];$tmp[$k*$n+$j]=$tmp[$pivot*$n+$j];$tmp[$pivot*$n+$j]=$t};$answer=-$answer}
                        $diag=$tmp[$k*$n+$k]
                        $answer*=$diag
                        for($i=$k+1;$i -lt $n;$i++){
                            $factor=$tmp[$i*$n+$k]/$diag
                            for($j=$k+1;$j -lt $n;$j++){$tmp[$i*$n+$j]-=$factor*$tmp[$k*$n+$j]}
                        }
                    }
                    return $answer
                }
                'sum' {
                    $series=Get-AllSeries $callParams $name;$acc=0.0
                    foreach($n in $series){$acc+=$n}
                    return $acc
                }
                'mean' {
                    $series=Get-AllSeries $callParams $name;$acc=0.0
                    foreach($n in $series){$acc+=$n}
                    return ($acc/$series.Length)
                }
                'median' {
                    $series=Get-AllSeries $callParams $name;$copy=[double[]]::new($series.Length)
                    [Array]::Copy($series,$copy,$series.Length);[Array]::Sort($copy)
                    $mid=[int][Math]::Floor($copy.Length/2)
                    if($copy.Length%2 -eq 1){return $copy[$mid]}
                    return (($copy[$mid-1]+$copy[$mid])/2.0)
                }
                'variance' {
                    $series=Get-AllSeries $callParams $name;$avg=0.0
                    foreach($n in $series){$avg+=$n};$avg/=$series.Length
                    $acc=0.0
                    foreach($n in $series){$d=$n-$avg;$acc+=$d*$d}
                    return ($acc/$series.Length)
                }
                'stdev' {
                    $series=Get-AllSeries $callParams $name;$avg=0.0
                    foreach($n in $series){$avg+=$n};$avg/=$series.Length
                    $acc=0.0
                    foreach($n in $series){$d=$n-$avg;$acc+=$d*$d}
                    return [Math]::Sqrt($acc/$series.Length)
                }
                'derivative' {
                    Require-ArgCount $name $callParams 2 2
                    if($callParams[0] -isnot [string]){throw 'ALL Math Error: derivative first argument must be an expression string'}
                    $ast=Parse-AllSubExpression $callParams[0]
                    $x=To-AllDouble $callParams[1]
                    $h=[Math]::Max(0.00001,[Math]::Abs($x)*0.00001)
                    return (((Eval-AllAtX $ast ($x+$h))-(Eval-AllAtX $ast ($x-$h)))/(2.0*$h))
                }
                'integrate' {
                    Require-ArgCount $name $callParams 3 4
                    if($callParams[0] -isnot [string]){throw 'ALL Math Error: integrate first argument must be an expression string'}
                    $ast=Parse-AllSubExpression $callParams[0]
                    $a=To-AllDouble $callParams[1];$b=To-AllDouble $callParams[2]
                    $steps=200
                    if($callParams.Count -eq 4){$steps=[int](To-AllInteger $callParams[3] 'integration intervals' 2 2000)}
                    if($steps%2 -ne 0){throw 'ALL Math Error: Simpson intervals must be even'}
                    $h=($b-$a)/$steps
                    $acc=(Eval-AllAtX $ast $a)+(Eval-AllAtX $ast $b)
                    for($i=1;$i -lt $steps;$i++){
                        $factor=if($i%2 -eq 0){2}else{4}
                        $acc+=$factor*(Eval-AllAtX $ast ($a+$i*$h))
                    }
                    return ($acc*$h/3.0)
                }
                default { throw "ALL Math Error: Unknown function '$name'" }
            }
        }

        # Control-flow execution is explicit, avoiding nonlocal PowerShell break/return.
        function Assert-AllStep {
            $state.Steps++
            if ($state.Steps -gt 100000) { throw 'ALL Runtime Error: Execution step limit exceeded' }
        }
        function Convert-AllToNative($value, [int]$level) {
            if ($level -gt 32) { throw 'ALL JSON Error: Nesting limit exceeded' }
            if (Is-AllList $value) {
                $result = [System.Collections.Generic.List[object]]::new()
                foreach ($item in $value.Items) { [void]$result.Add((Convert-AllToNative $item ($level+1))) }
                return ,($result.ToArray())
            }
            if (Is-AllMap $value) {
                $result = [System.Collections.Specialized.OrderedDictionary]::new([System.StringComparer]::Ordinal)
                foreach ($key in $value.Items.Keys) { $result[$key] = Convert-AllToNative $value.Items[$key] ($level+1) }
                return $result
            }
            if ($null -eq $value -or $value -is [string] -or $value -is [bool] -or (Is-AllNumber $value)) {
                return $value
            }
            throw 'ALL JSON Error: Unsupported value type'
        }
        function Convert-NativeToAll($value, [int]$level) {
            if ($level -gt 32) { throw 'ALL JSON Error: Nesting limit exceeded' }
            if ($null -eq $value) { return $null }
            if ($value -is [System.Collections.IDictionary]) {
                $dict = New-AllMap
                foreach ($key in $value.Keys) { $dict.Items.Add([string]$key, (Convert-NativeToAll $value[$key] ($level+1))) }
                return $dict
            }
            if ($value -is [array]) {
                $values = [System.Collections.Generic.List[object]]::new()
                foreach ($item in $value) { [void]$values.Add((Convert-NativeToAll $item ($level+1))) }
                return (New-AllList ($values.ToArray()))
            }
            if ($value -is [pscustomobject]) {
                $dict = New-AllMap
                foreach ($property in $value.PSObject.Properties) { $dict.Items.Add($property.Name, (Convert-NativeToAll $property.Value ($level+1))) }
                return $dict
            }
            if ($value -is [string] -or $value -is [bool] -or (Is-AllNumber $value)) { return $value }
            throw 'ALL JSON Error: Unsupported JSON data'
        }
        function Resolve-AllPath($value) {
            if ($value -isnot [string] -or [string]::IsNullOrWhiteSpace($value)) {
                throw 'ALL IO Error: Non-empty path string required'
            }
            if ($value.Length -gt 1024) { throw 'ALL IO Error: Path too long' }
            if ([System.IO.Path]::IsPathRooted($value)) { return [System.IO.Path]::GetFullPath($value) }
            return [System.IO.Path]::GetFullPath((Join-Path (Get-Location).ProviderPath $value))
        }
        # v0.8: HTTP client functions. No PHP/external CLI process is involved.
        # Deliberately bounded: UTF-8, 1 MiB response and 64 KiB request body.
        # 4xx/5xx are returned as response maps (not treated as transport failure).
        function Invoke-AllHttp([string]$method, [string]$url, [string]$requestBody, [string]$contentType) {
            if ([string]::IsNullOrWhiteSpace($url) -or $url.Length -gt 2048) {
                throw 'ALL HTTP Error: URL must be a nonempty string of at most 2048 characters'
            }
            $uri = $null
            if (-not [System.Uri]::TryCreate($url,[System.UriKind]::Absolute,[ref]$uri) -or
                $uri.Scheme -notin @('http','https') -or [string]::IsNullOrWhiteSpace($uri.Host) -or
                -not [string]::IsNullOrEmpty($uri.UserInfo)) {
                throw 'ALL HTTP Error: Absolute http/https URL without credentials required'
            }
            $encoding = [System.Text.UTF8Encoding]::new($false,$true)
            [byte[]]$payload = @()
            if ($null -ne $requestBody) { $payload = $encoding.GetBytes($requestBody) }
            if ($payload.Length -gt 65536) { throw 'ALL HTTP Error: Request body exceeds 65536 bytes' }
            $request = [System.Net.WebRequest]::Create($uri)
            if ($request -isnot [System.Net.HttpWebRequest]) { throw 'ALL HTTP Error: Unsupported request type' }
            $request.Method = $method
            $request.Timeout = 5000
            $request.ReadWriteTimeout = 5000
            $request.AllowAutoRedirect = $false
            $request.KeepAlive = $false
            # Avoid waiting for 100 Continue with minimal local HTTP test servers.
            $request.ServicePoint.Expect100Continue = $false
            $request.AutomaticDecompression = [System.Net.DecompressionMethods]::GZip -bor [System.Net.DecompressionMethods]::Deflate
            if ($method -ceq 'POST') {
                $request.ContentType = $contentType
                $request.ContentLength = $payload.Length
                $writer = $request.GetRequestStream()
                try { $writer.Write($payload,0,$payload.Length) }
                finally { $writer.Dispose() }
            }
            $response = $null
            try {
                try { $response = [System.Net.HttpWebResponse]$request.GetResponse() }
                catch {
                    # Windows PowerShell can wrap .NET exceptions in MethodInvocationException.
                    $webError = $_.Exception
                    while ($null -ne $webError -and $webError -isnot [System.Net.WebException]) {
                        $webError = $webError.InnerException
                    }
                    if ($null -ne $webError -and $webError.Response -is [System.Net.HttpWebResponse]) {
                        $response = [System.Net.HttpWebResponse]$webError.Response
                    } else {
                        throw ('ALL HTTP Error: ' + $_.Exception.Message)
                    }
                }
                if ($response.ContentLength -gt 1048576) {
                    throw 'ALL HTTP Error: Response exceeds 1048576 bytes'
                }
                $stream = $response.GetResponseStream()
                $memory = [System.IO.MemoryStream]::new()
                try {
                    $buffer = [byte[]]::new(8192)
                    while ($true) {
                        $n = $stream.Read($buffer,0,$buffer.Length)
                        if ($n -le 0) { break }
                        if ($memory.Length + $n -gt 1048576) {
                            throw 'ALL HTTP Error: Response exceeds 1048576 bytes'
                        }
                        $memory.Write($buffer,0,$n)
                    }
                    $body = $encoding.GetString($memory.ToArray())
                } finally {
                    $memory.Dispose()
                    if ($null -ne $stream) { $stream.Dispose() }
                }
                $responseMap = New-AllMap
                $responseMap.Items.Add('status',[decimal][int]$response.StatusCode)
                $responseMap.Items.Add('ok',([int]$response.StatusCode -ge 200 -and [int]$response.StatusCode -lt 300))
                $responseMap.Items.Add('body',$body)
                $responseMap.Items.Add('content_type',([string]$response.ContentType))
                return $responseMap
            } finally {
                if ($null -ne $response) { $response.Dispose() }
                $request.Abort()
            }
        }
        # v0.9: bounded single-threaded HTTP server. The ALL user function
        # determines the response. Only loopback is listened on; this is not a
        # public/production web server.
        function Invoke-AllHttpServe($portArg, $handlerArg, $countArg, [int]$maximumCount = 20, [int]$acceptIdleSeconds = 12, [bool]$recoverPerRequest = $false, [bool]$unbounded = $false) {
            if (-not (Is-AllNumber $portArg)) { throw 'ALL Server Error: Port must be an integer' }
            $port = [int](To-AllInteger $portArg 'http_serve port' 1024 65535)
            # Worker-level port binding, kept outside the ALL program's source.
            $portOverride=[Environment]::GetEnvironmentVariable('ALL_HTTP_PORT_OVERRIDE','Process')
            if(-not [string]::IsNullOrEmpty($portOverride)){
                if($portOverride -cnotmatch '^\d{4,5}$' -or [int]$portOverride -gt 65535 -or [int]$portOverride -lt 1024){throw 'ALL Server Error: Invalid worker port override'}
                $port=[int]$portOverride
            }
            if ($handlerArg -isnot [string] -or [string]::IsNullOrWhiteSpace($handlerArg)) {
                throw 'ALL Server Error: Handler must be a function-name string'
            }
            if (-not $state.Functions.ContainsKey($handlerArg)) {
                throw "ALL Server Error: Undefined handler '$handlerArg'"
            }
            if ($state.Functions[$handlerArg].Params.Count -ne 1) {
                throw 'ALL Server Error: Handler must accept exactly one request argument'
            }
            if (-not (Is-AllNumber $countArg)) { throw 'ALL Server Error: Request count must be an integer' }
            $requestCount = 0
            if (-not $unbounded) {
                $requestCount = [int](To-AllInteger $countArg 'http_serve count' 1 $maximumCount)
            }
            $encoder = [System.Text.UTF8Encoding]::new($false,$true)
            $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback,$port)
            try {
                $listener.Start()
                for ($i=0; $unbounded -or $i -lt $requestCount; $i++) {
                    # Optional operator-controlled stop file. This is checked while idle,
                    # and between requests; no remote shutdown endpoint is opened.
                    $stopFile = [Environment]::GetEnvironmentVariable('ALL_HTTP_STOP_FILE','Process')
                    if ($unbounded -and -not [string]::IsNullOrWhiteSpace($stopFile) -and
                        [System.IO.File]::Exists($stopFile)) { break }
                    $deadline = [DateTime]::UtcNow.AddSeconds($acceptIdleSeconds)
                    while (-not $listener.Pending()) {
                        if ($unbounded -and -not [string]::IsNullOrWhiteSpace($stopFile) -and
                            [System.IO.File]::Exists($stopFile)) { break }
                        if ($acceptIdleSeconds -gt 0 -and [DateTime]::UtcNow -gt $deadline) {
                            throw 'ALL Server Error: Accept timeout'
                        }
                        Start-Sleep -Milliseconds 20
                    }
                    if ($unbounded -and -not [string]::IsNullOrWhiteSpace($stopFile) -and
                        [System.IO.File]::Exists($stopFile)) { break }
                    $client = $listener.AcceptTcpClient()
                    try {
                        $requestParsed = $false
                        try {
                        $client.ReceiveTimeout = 5000
                        $client.SendTimeout = 5000
                        $stream = $client.GetStream()
                        $headerBytes = [System.Collections.Generic.List[byte]]::new()
                        while ($true) {
                            $b = $stream.ReadByte()
                            if ($b -lt 0) { throw 'ALL Server Error: Incomplete request header' }
                            [void]$headerBytes.Add([byte]$b)
                            $size = $headerBytes.Count
                            if ($size -gt 8192) { throw 'ALL Server Error: Headers exceed 8192 bytes' }
                            if ($size -ge 4 -and $headerBytes[$size-4] -eq 13 -and $headerBytes[$size-3] -eq 10 -and
                                $headerBytes[$size-2] -eq 13 -and $headerBytes[$size-1] -eq 10) { break }
                        }
                        $headerText = [System.Text.Encoding]::ASCII.GetString($headerBytes.ToArray())
                        $headerLines = $headerText.Split([string[]]@("`r`n"),[System.StringSplitOptions]::None)
                        $requestLine = [regex]::Match($headerLines[0], '^(GET|POST) (\S+) HTTP/1\.[01]$')
                        if (-not $requestLine.Success) { throw 'ALL Server Error: Unsupported request line' }
                        $method = $requestLine.Groups[1].Value
                        $path = $requestLine.Groups[2].Value
                        if ($path.Length -gt 2048 -or -not $path.StartsWith('/')) {
                            throw 'ALL Server Error: Invalid request path'
                        }
                        $contentLength = 0
                        $hasLength = $false
                        $contentType = ''
                        foreach ($header in $headerLines) {
                            if ($header -match '^Content-Length:\s*(\d+)\s*$') {
                                if ($hasLength) { throw 'ALL Server Error: Duplicate Content-Length' }
                                $hasLength = $true
                                if (-not [int]::TryParse($Matches[1], [ref]$contentLength)) {
                                    throw 'ALL Server Error: Invalid Content-Length'
                                }
                            } elseif ($header -match '^Content-Type:\s*(.*)$') {
                                $contentType = $Matches[1]
                            } elseif ($header -match '^Transfer-Encoding:') {
                                throw 'ALL Server Error: Chunked requests not supported'
                            }
                        }
                        if ($contentLength -gt 65536) { throw 'ALL Server Error: Request body exceeds 65536 bytes' }
                        if ($method -ceq 'GET' -and $contentLength -gt 0) {
                            throw 'ALL Server Error: GET body not supported'
                        }
                        $bodyBytes = [byte[]]::new($contentLength)
                        $readTotal=0
                        while ($readTotal -lt $contentLength) {
                            $received=$stream.Read($bodyBytes,$readTotal,$contentLength-$readTotal)
                            if ($received -le 0) { throw 'ALL Server Error: Incomplete body' }
                            $readTotal += $received
                        }
                        $request = New-AllMap
                        $request.Items.Add('method',$method)
                        $request.Items.Add('path',$path)
                        $request.Items.Add('body',($encoder.GetString($bodyBytes)))
                        $request.Items.Add('content_type',$contentType)
                        $requestParsed = $true
                        # The interpreter's evaluation budget applies to each request,
                        # rather than accumulating until a long-running server fails.
                        if ($unbounded) { $state.Count = 0 }
                        $answer = Invoke-AllFunction $handlerArg @($request)
                        if (-not (Is-AllMap $answer)) { throw 'ALL Server Error: Handler must return a response map' }
                        if (-not $answer.Items.Contains('status') -or -not $answer.Items.Contains('body')) {
                            throw 'ALL Server Error: Response requires status and body'
                        }
                        $status = [int](To-AllInteger $answer.Items['status'] 'http status' 200 599)
                        $responseBody = $answer.Items['body']
                        if ($responseBody -isnot [string]) { throw 'ALL Server Error: Response body must be a string' }
                        $responseContentType = 'text/plain; charset=utf-8'
                        if ($answer.Items.Contains('content_type')) {
                            $responseContentType = $answer.Items['content_type']
                            if ($responseContentType -isnot [string] -or
                                [string]::IsNullOrWhiteSpace($responseContentType) -or
                                $responseContentType.Length -gt 128 -or
                                $responseContentType.Contains("`r") -or $responseContentType.Contains("`n")) {
                                throw 'ALL Server Error: Invalid response content type'
                            }
                        }
                        $encodedBody = $encoder.GetBytes($responseBody)
                        if ($encodedBody.Length -gt 65536) { throw 'ALL Server Error: Response body exceeds 65536 bytes' }
                        $reason = switch ($status) { 200 {'OK'} 201 {'Created'} 204 {'No Content'}
                            400 {'Bad Request'} 404 {'Not Found'} 405 {'Method Not Allowed'}
                            500 {'Internal Server Error'} default {'Status'} }
                        $headers = "HTTP/1.1 $status $reason`r`nContent-Type: $responseContentType`r`nContent-Length: $($encodedBody.Length)`r`nConnection: close`r`n`r`n"
                        $headerOut = [System.Text.Encoding]::ASCII.GetBytes($headers)
                        $stream.Write($headerOut,0,$headerOut.Length)
                        $stream.Write($encodedBody,0,$encodedBody.Length)
                        $stream.Flush()
                        if ($unbounded -and [Environment]::GetEnvironmentVariable('ALL_HTTP_ACCESS_LOG','Process') -ceq '1') {
                            [Console]::Error.WriteLine('ALL_HTTP status=' + $status + ' method=' + $method)
                        }
                        } catch {
                            if (-not $recoverPerRequest) { throw }
                            # Return a generic protocol/handler error without leaking interpreter diagnostics.
                            # A malformed request is 400; an ALL handler failure is 500.
                            $statusCode = if ($requestParsed) { 500 } else { 400 }
                            if ($unbounded -and [Environment]::GetEnvironmentVariable('ALL_HTTP_ACCESS_LOG','Process') -ceq '1') {
                                [Console]::Error.WriteLine('ALL_HTTP status=' + $statusCode + ' method=error')
                            }
                            $reasonPhrase = if ($statusCode -eq 400) { 'Bad Request' } else { 'Internal Server Error' }
                            $responseText = if ($statusCode -eq 400) { 'Bad Request' } else { 'Internal Server Error' }
                            try {
                                $errorStream = $client.GetStream()
                                $encodedError = [System.Text.Encoding]::UTF8.GetBytes($responseText)
                                $errorHeaders = "HTTP/1.1 $statusCode $reasonPhrase`r`nContent-Type: text/plain; charset=utf-8`r`nContent-Length: $($encodedError.Length)`r`nConnection: close`r`n`r`n"
                                $headerOutput = [System.Text.Encoding]::ASCII.GetBytes($errorHeaders)
                                $errorStream.Write($headerOutput,0,$headerOutput.Length)
                                $errorStream.Write($encodedError,0,$encodedError.Length)
                                $errorStream.Flush()
                            } catch {
                                # Peer disconnects do not terminate the batch listener.
                            }
                        }
                    } finally {
                        if ($null -ne $client) { $client.Dispose() }
                    }
                }
                if ($unbounded) { return [decimal]$i }
                return [decimal]$requestCount
            } finally { $listener.Stop() }
        }
        # v1.0: Local JSON-backed KV store. A *.allkv file contains an explicit
        # version envelope. File.Replace performs atomic replacement on Windows.
        # No SQLite compatibility or multi-machine transaction guarantee.
        function Get-AllKvPath($value) {
            $path = Resolve-AllPath $value
            if ([System.IO.Path]::GetExtension($path) -cne '.allkv') {
                throw 'ALL KV Error: Expected .allkv file'
            }
            return $path
        }
        function With-AllKvLock([string]$path,[scriptblock]$action) {
            $lockPath = $path + '.lock'
            $handle = $null
            for ($attempt=0; $attempt -lt 100; $attempt++) {
                try {
                    $handle=[System.IO.FileStream]::new($lockPath,[System.IO.FileMode]::OpenOrCreate,
                        [System.IO.FileAccess]::ReadWrite,[System.IO.FileShare]::None)
                    break
                } catch [System.IO.IOException] {
                    if ($attempt -eq 99) { throw 'ALL KV Error: Lock acquisition timed out' }
                    Start-Sleep -Milliseconds 20
                }
            }
            try { return (& $action) }
            finally { if ($null -ne $handle) { $handle.Dispose() } }
        }
        function Read-AllKv([string]$path) {
            if (-not [System.IO.File]::Exists($path)) { return (New-AllMap) }
            $fileInfo=[System.IO.FileInfo]::new($path)
            if ($fileInfo.Length -gt 1048576) { throw 'ALL KV Error: Store exceeds 1 MiB limit' }
            $raw=[System.IO.File]::ReadAllText($path,[System.Text.UTF8Encoding]::new($false,$true))
            try {
                $container=ConvertFrom-Json -InputObject $raw -ErrorAction Stop
                if ($container.format -cne 'ALL_KV_1' -or $null -eq $container.values) {
                    throw 'Wrong ALL KV format'
                }
                $values=Convert-NativeToAll $container.values 0
                if (-not (Is-AllMap $values)) { throw 'KV values must be map' }
                return $values
            } catch { throw ('ALL KV Error: Corrupt or incompatible store: '+$_.Exception.Message) }
        }
        function Write-AllKv([string]$path, $values) {
            $native=Convert-AllToNative $values 0
            $envelope=[ordered]@{ format='ALL_KV_1'; values=$native }
            $json=ConvertTo-Json -InputObject $envelope -Depth 35 -Compress
            if ([System.Text.Encoding]::UTF8.GetByteCount($json) -gt 1048576) {
                throw 'ALL KV Error: Store exceeds 1 MiB limit'
            }
            $temp=$path+'.tmp.'+[guid]::NewGuid().ToString('N')
            try {
                [System.IO.File]::WriteAllText($temp,$json,[System.Text.UTF8Encoding]::new($false))
                if ([System.IO.File]::Exists($path)) {
                    $replaceBackup=$path+'.bak.'+[guid]::NewGuid().ToString('N')
                    [System.IO.File]::Replace($temp,$path,$replaceBackup)
                    if ([System.IO.File]::Exists($replaceBackup)) {
                        try { [System.IO.File]::Delete($replaceBackup) } catch { }
                    }
                }
                else { [System.IO.File]::Move($temp,$path) }
            } finally {
                if ([System.IO.File]::Exists($temp)) { [System.IO.File]::Delete($temp) }
            }
        }
        # Independent ALL programs use bounded PowerShell jobs; no shared state.
        # Output and errors are collected in submission order, and jobs are cleaned up.
        function Invoke-AllParallel($programs) {
            if (-not (Is-AllList $programs)) { throw 'ALL Parallel Error: Expected a list of ALL source strings' }
            if ($programs.Items.Count -lt 1 -or $programs.Items.Count -gt 4) {
                throw 'ALL Parallel Error: Expected 1 to 4 tasks'
            }
            $core=Join-Path $HOME 'ALL\ALL.ps1'
            if (-not [System.IO.File]::Exists($core)) { throw 'ALL Parallel Error: ALL core not found' }
            $jobs=[System.Collections.Generic.List[object]]::new()
            $results=[System.Collections.Generic.List[object]]::new()
            $cwd=(Get-Location).ProviderPath
            try {
                foreach ($program in $programs.Items) {
                    if ($program -isnot [string] -or $program.Length -gt 10000) {
                        throw 'ALL Parallel Error: Each task must be an ALL source string <= 10000 characters'
                    }
                    $job=Start-Job -ArgumentList $core,$program,$cwd -ScriptBlock {
                        param($coreFile,$snippet,$directory)
                        $ErrorActionPreference='Stop'
                        $writer=[System.IO.StringWriter]::new([System.Globalization.CultureInfo]::InvariantCulture)
                        $old=[Console]::Out
                        $errText=''
                        try {
                            Set-Location -LiteralPath $directory
                            [Console]::SetOut($writer)
                            & $coreFile -Language ALL -Code $snippet | Out-Null
                        } catch { $errText=$_.Exception.Message }
                        finally { [Console]::SetOut($old) }
                        $result=[pscustomobject]@{ Output=$writer.ToString(); Error=$errText }
                        $writer.Dispose()
                        return $result
                    }
                    [void]$jobs.Add($job)
                }
                $finished=Wait-Job -Job $jobs.ToArray() -Timeout 30
                if (@($finished).Count -ne $jobs.Count) { throw 'ALL Parallel Error: Task timeout (30 seconds)' }
                foreach ($job in $jobs) {
                    if ($job.State -cne 'Completed') { throw 'ALL Parallel Error: Task failed unexpectedly' }
                    $message=@(Receive-Job -Job $job -ErrorAction Stop)
                    if ($message.Count -ne 1) { throw 'ALL Parallel Error: Unexpected task response' }
                    $record=New-AllMap
                    $record.Items.Add('ok',([string]::IsNullOrEmpty([string]$message[0].Error)))
                    $record.Items.Add('output',[string]$message[0].Output)
                    $record.Items.Add('error',[string]$message[0].Error)
                    [void]$results.Add($record)
                }
                return (New-AllList ($results.ToArray()))
            } finally {
                foreach ($job in $jobs) {
                    if ($job.State -eq 'Running') { Stop-Job -Job $job -ErrorAction SilentlyContinue }
                    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
                }
            }
        }
        # ALL v1.4: SQLite database operations, parametrized queries,
        # atomic multi-statement transactions. Uses the Windows-supplied
        # winsqlite3.dll, not shell-based SQL execution or string interpolation.
        function Initialize-AllSqlite {
            if (-not ('AllSqliteDriver' -as [type])) {
                $platform = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)
                $sourceFile = if ($platform) { 'ALL_sqlite_driver.cs' } else { 'ALL_sqlite_driver_linux.cs' }
                $driverFile = Join-Path (Join-Path $HOME 'ALL/languages') $sourceFile
                if (-not [System.IO.File]::Exists($driverFile)) {
                    throw ('ALL SQL Error: driver source missing: ' + $sourceFile)
                }
                Add-Type -Path $driverFile -ErrorAction Stop
            }
        }
        function Get-AllSqlParams($parameters) {
            if (-not (Is-AllList $parameters)) {
                throw 'ALL SQL Error: SQL parameters must be an array'
            }
            $result = [System.Collections.Generic.List[object]]::new()
            foreach ($param in $parameters.Items) {
                if (Is-AllMap $param -or Is-AllList $param) {
                    throw 'ALL SQL Error: Nested SQL parameters not supported'
                }
                [void]$result.Add($param)
            }
            return ,($result.ToArray())
        }
        function Get-AllSqlDatabasePath($value) {
            $path=Resolve-AllPath $value
            if ([System.IO.Path]::GetExtension($path) -cnotin @('.sqlite','.db')) {
                throw 'ALL SQL Error: expected a .sqlite or .db file'
            }
            return $path
        }
        function Invoke-AllListBuiltin([string]$name, $callParams) {
            switch -CaseSensitive ($name) {
                'sql_query' {
                    Require-ArgCount $name $callParams 2 3
                    if ($callParams[1] -isnot [string]) { throw 'ALL SQL Error: SQL statement must be text' }
                    $path=Get-AllSqlDatabasePath $callParams[0]
                    $parameters=[object[]]@()
                    if ($callParams.Count -eq 3) { $parameters=[object[]](Get-AllSqlParams $callParams[2]) }
                    Initialize-AllSqlite
                    $output=[AllSqliteDriver]::Run($path,[string]$callParams[1],$parameters)
                    if (-not $output.IsQuery) { throw 'ALL SQL Error: sql_query requires SELECT or a row-producing statement' }
                    $records=[object[]]$output.Rows
                    return (Convert-NativeToAll $records 0)
                }
                'sql_exec' {
                    Require-ArgCount $name $callParams 2 3
                    if ($callParams[1] -isnot [string]) { throw 'ALL SQL Error: SQL statement must be text' }
                    $path=Get-AllSqlDatabasePath $callParams[0]
                    $parameters=[object[]]@()
                    if ($callParams.Count -eq 3) { $parameters=[object[]](Get-AllSqlParams $callParams[2]) }
                    Initialize-AllSqlite
                    $output=[AllSqliteDriver]::Run($path,[string]$callParams[1],$parameters)
                    if ($output.IsQuery) { throw 'ALL SQL Error: sql_exec must not return rows' }
                    return [decimal]$output.Changed
                }
                'sql_migrate' {
                    Require-ArgCount $name $callParams 2 2
                    $path=Get-AllSqlDatabasePath $callParams[0]
                    $folder=Resolve-AllPath $callParams[1]
                    Initialize-AllSqlite
                    return [decimal]([AllSqliteDriver]::Migrate($path,$folder))
                }
                'sql_transaction' {
                    Require-ArgCount $name $callParams 2 2
                    $path=Get-AllSqlDatabasePath $callParams[0]
                    if (-not (Is-AllList $callParams[1])) { throw 'ALL SQL Error: transaction requires an array of operations' }
                    $ops=[object[]](Convert-AllToNative $callParams[1] 0)
                    Initialize-AllSqlite
                    return [decimal]([AllSqliteDriver]::Transaction($path,$ops))
                }
                'stdin_text' {
                    Require-ArgCount $name $callParams 0 0
                    if (-not [Console]::IsInputRedirected) {
                        throw 'ALL CLI Error: stdin_text() requires redirected stdin'
                    }
                    $buffer = [char[]]::new(4096)
                    $builder = [System.Text.StringBuilder]::new()
                    while ($true) {
                        $n = [Console]::In.Read($buffer,0,$buffer.Length)
                        if ($n -le 0) { break }
                        if ($builder.Length + $n -gt 1048576) {
                            throw 'ALL CLI Error: stdin exceeds 1048576 characters'
                        }
                        [void]$builder.Append($buffer,0,$n)
                    }
                    return $builder.ToString()
                }
                'stderr_text' {
                    Require-ArgCount $name $callParams 1 1
                    if ($callParams[0] -isnot [string]) { throw 'ALL CLI Error: stderr_text() requires a string' }
                    [Console]::Error.WriteLine([string]$callParams[0])
                    return $null
                }
                'set_exit_code' {
                    Require-ArgCount $name $callParams 1 1
                    if (-not (Is-AllNumber $callParams[0])) { throw 'ALL CLI Error: exit code must be an integer 0..255' }
                    $code=[int](To-AllInteger $callParams[0] 'exit code' 0 255)
                    [Environment]::SetEnvironmentVariable('ALL_CLI_EXIT_CODE',[string]$code,'Process')
                    return $null
                }
                'cli_args' {
                    Require-ArgCount $name $callParams 0 0
                    $rawArgs = [Environment]::GetEnvironmentVariable('ALL_SCRIPT_ARGS_JSON','Process')
                    if ([string]::IsNullOrEmpty($rawArgs)) { return (New-AllList @()) }
                    if ($rawArgs.Length -gt 100000) { throw 'ALL CLI Error: Arguments payload too large' }
                    try {
                        $decoded = ConvertFrom-Json -InputObject $rawArgs -ErrorAction Stop
                        if ($null -eq $decoded -or $null -eq $decoded.arguments) {
                            throw 'Invalid CLI arguments envelope'
                        }
                        $argumentItems = [System.Collections.Generic.List[object]]::new()
                        foreach ($entry in @($decoded.arguments)) {
                            if ($entry -isnot [string] -or $entry.Length -gt 4096) {
                                throw 'Invalid CLI argument'
                            }
                            [void]$argumentItems.Add($entry)
                            if ($argumentItems.Count -gt 64) { throw 'Too many CLI arguments' }
                        }
                        return (New-AllList ($argumentItems.ToArray()))
                    } catch {
                        throw ('ALL CLI Error: Invalid arguments: ' + $_.Exception.Message)
                    }
                }
                'http_serve_live' {
                    Require-ArgCount $name $callParams 2 2
                    # Persistent loopback HTTP for a TLS-terminating reverse proxy.
                    # The handler still runs sequentially; do not claim concurrency.
                    return (Invoke-AllHttpServe $callParams[0] $callParams[1] 0 256 0 $true $true)
                }
                'http_serve_batch' {
                    Require-ArgCount $name $callParams 3 3
                    # Opt-in extension: legacy http_serve() remains capped at 20.
                    # Localhost-only, single threaded, max 256 requests, 30s idle timeout.
                    return (Invoke-AllHttpServe $callParams[0] $callParams[1] $callParams[2] 256 30 $true)
                }
                'parallel_all' {
                    Require-ArgCount $name $callParams 1 1
                    return (Invoke-AllParallel $callParams[0])
                }
                'kv_get' {
                    Require-ArgCount $name $callParams 2 3
                    if ($callParams[1] -isnot [string]) { throw 'ALL KV Error: Key must be string' }
                    $path=Get-AllKvPath $callParams[0]
                    $key=$callParams[1]
                    $fallback=$null
                    if ($callParams.Count -eq 3) { $fallback=$callParams[2] }
                    return (With-AllKvLock $path {
                        $map=Read-AllKv $path
                        if ($map.Items.Contains($key)) { return $map.Items[$key] }
                        return $fallback
                    })
                }
                'kv_put' {
                    Require-ArgCount $name $callParams 3 3
                    if ($callParams[1] -isnot [string]) { throw 'ALL KV Error: Key must be string' }
                    $path=Get-AllKvPath $callParams[0]
                    $key=$callParams[1]
                    $value=$callParams[2]
                    [void](With-AllKvLock $path {
                        $map=Read-AllKv $path
                        $map.Items[$key]=$value
                        Write-AllKv $path $map
                    })
                    return $null
                }
                'kv_delete' {
                    Require-ArgCount $name $callParams 2 2
                    if ($callParams[1] -isnot [string]) { throw 'ALL KV Error: Key must be string' }
                    $path=Get-AllKvPath $callParams[0]
                    $key=$callParams[1]
                    return (With-AllKvLock $path {
                        $map=Read-AllKv $path
                        if (-not $map.Items.Contains($key)) { return $false }
                        $map.Items.Remove($key)
                        Write-AllKv $path $map
                        return $true
                    })
                }
                'kv_keys' {
                    Require-ArgCount $name $callParams 1 1
                    $path=Get-AllKvPath $callParams[0]
                    return (With-AllKvLock $path {
                        $map=Read-AllKv $path
                        return (New-AllList @($map.Items.Keys))
                    })
                }
                'http_serve' {
                    Require-ArgCount $name $callParams 3 3
                    return (Invoke-AllHttpServe $callParams[0] $callParams[1] $callParams[2])
                }
                'http_get' {
                    Require-ArgCount $name $callParams 1 1
                    if ($callParams[0] -isnot [string]) { throw 'ALL HTTP Error: http_get URL must be a string' }
                    return (Invoke-AllHttp 'GET' $callParams[0] $null $null)
                }
                'http_post' {
                    Require-ArgCount $name $callParams 2 3
                    if ($callParams[0] -isnot [string] -or $callParams[1] -isnot [string]) {
                        throw 'ALL HTTP Error: http_post requires URL and body strings'
                    }
                    $contentType = 'text/plain; charset=utf-8'
                    if ($callParams.Count -eq 3) {
                        if ($callParams[2] -isnot [string] -or [string]::IsNullOrWhiteSpace($callParams[2])) {
                            throw 'ALL HTTP Error: Content-Type must be a nonempty string'
                        }
                        $contentType = $callParams[2]
                    }
                    return (Invoke-AllHttp 'POST' $callParams[0] $callParams[1] $contentType)
                }
                'http_post_json' {
                    Require-ArgCount $name $callParams 2 2
                    if ($callParams[0] -isnot [string]) { throw 'ALL HTTP Error: http_post_json URL must be a string' }
                    $native = Convert-AllToNative $callParams[1] 0
                    $json = ConvertTo-Json -InputObject $native -Depth 35 -Compress
                    return (Invoke-AllHttp 'POST' $callParams[0] ([string]$json) 'application/json; charset=utf-8')
                }
                'keys' {
                    Require-ArgCount $name $callParams 1 1
                    if (-not (Is-AllMap $callParams[0])) { throw 'ALL Type Error: keys() requires a map' }
                    return (New-AllList @($callParams[0].Items.Keys))
                }
                'values' {
                    Require-ArgCount $name $callParams 1 1
                    if (-not (Is-AllMap $callParams[0])) { throw 'ALL Type Error: values() requires a map' }
                    $items = [System.Collections.Generic.List[object]]::new()
                    foreach ($key in $callParams[0].Items.Keys) { [void]$items.Add($callParams[0].Items[$key]) }
                    return (New-AllList ($items.ToArray()))
                }
                'has_key' {
                    Require-ArgCount $name $callParams 2 2
                    if (-not (Is-AllMap $callParams[0])) { throw 'ALL Type Error: has_key() requires a map' }
                    return ([bool]$callParams[0].Items.Contains((Get-AllKey $callParams[1])))
                }
                'remove_key' {
                    Require-ArgCount $name $callParams 2 2
                    if (-not (Is-AllMap $callParams[0])) { throw 'ALL Type Error: remove_key() requires a map' }
                    $key = Get-AllKey $callParams[1]
                    if (-not $callParams[0].Items.Contains($key)) { return $false }
                    $callParams[0].Items.Remove($key)
                    return $true
                }
                'input' {
                    Require-ArgCount $name $callParams 0 1
                    if ($callParams.Count -eq 1) { [Console]::Write((To-AllText $callParams[0])) }
                    return [Console]::ReadLine()
                }
                'file_exists' {
                    Require-ArgCount $name $callParams 1 1
                    return [bool][System.IO.File]::Exists((Resolve-AllPath $callParams[0]))
                }
                'read_text' {
                    Require-ArgCount $name $callParams 1 1
                    $path = Resolve-AllPath $callParams[0]
                    return [System.IO.File]::ReadAllText($path,[System.Text.UTF8Encoding]::new($false,$true))
                }
                'write_text' {
                    Require-ArgCount $name $callParams 2 2
                    $path = Resolve-AllPath $callParams[0]
                    if ($callParams[1] -isnot [string]) { throw 'ALL Type Error: write_text() requires string contents' }
                    [System.IO.File]::WriteAllText($path,$callParams[1],[System.Text.UTF8Encoding]::new($false))
                    return $null
                }
                'append_text' {
                    Require-ArgCount $name $callParams 2 2
                    $path = Resolve-AllPath $callParams[0]
                    if ($callParams[1] -isnot [string]) { throw 'ALL Type Error: append_text() requires string contents' }
                    [System.IO.File]::AppendAllText($path,$callParams[1],[System.Text.UTF8Encoding]::new($false))
                    return $null
                }
                'json_encode' {
                    Require-ArgCount $name $callParams 1 1
                    $native = Convert-AllToNative $callParams[0] 0
                    return (ConvertTo-Json -InputObject $native -Depth 35 -Compress)
                }
                'json_decode' {
                    Require-ArgCount $name $callParams 1 1
                    if ($callParams[0] -isnot [string]) { throw 'ALL Type Error: json_decode() requires a string' }
                    # Windows PowerShell 5.1 does not reliably preserve root JSON scalars.
                    # Wrap the value in an object before parsing, then unwrap it.
                    $wrapped = '{"__all_json_root__":' + $callParams[0] + '}'
                    $obj = (ConvertFrom-Json -InputObject $wrapped).__all_json_root__
                    return (Convert-NativeToAll $obj 0)
                }
                'read_json' {
                    Require-ArgCount $name $callParams 1 1
                    $path = Resolve-AllPath $callParams[0]
                    $data = [System.IO.File]::ReadAllText($path,[System.Text.UTF8Encoding]::new($false,$true))
                    $wrapped = '{"__all_json_root__":' + $data + '}'
                    $obj = (ConvertFrom-Json -InputObject $wrapped).__all_json_root__
                    return (Convert-NativeToAll $obj 0)
                }
                'write_json' {
                    Require-ArgCount $name $callParams 2 2
                    $path = Resolve-AllPath $callParams[0]
                    $native = Convert-AllToNative $callParams[1] 0
                    $data = ConvertTo-Json -InputObject $native -Depth 35 -Compress
                    [System.IO.File]::WriteAllText($path,$data,[System.Text.UTF8Encoding]::new($false))
                    return $null
                }
                'len' {
                    Require-ArgCount $name $callParams 1 1
                    if (Is-AllList $callParams[0]) { return [decimal]$callParams[0].Items.Count }
                    if (Is-AllMap $callParams[0]) { return [decimal]$callParams[0].Items.Count }
                    if ($callParams[0] -is [string]) { return [decimal]$callParams[0].Length }
                    throw 'ALL Type Error: len() requires a list or string'
                }
                'push' {
                    Require-ArgCount $name $callParams 2 2
                    if (-not (Is-AllList $callParams[0])) { throw 'ALL Type Error: push() requires a list' }
                    if ($callParams[0].Items.Count -ge 10000) { throw 'ALL Runtime Error: List size limit exceeded' }
                    [void]$callParams[0].Items.Add($callParams[1])
                    return [decimal]$callParams[0].Items.Count
                }
                'pop' {
                    Require-ArgCount $name $callParams 1 1
                    if (-not (Is-AllList $callParams[0])) { throw 'ALL Type Error: pop() requires a list' }
                    $count = $callParams[0].Items.Count
                    if ($count -eq 0) { throw 'ALL Index Error: Cannot pop empty list' }
                    $item = $callParams[0].Items[$count-1]
                    $callParams[0].Items.RemoveAt($count-1)
                    return $item
                }
                'concat' {
                    Require-ArgCount $name $callParams 2 2
                    return ((To-AllText $callParams[0]) + (To-AllText $callParams[1]))
                }
            }
            throw "ALL Runtime Error: Unknown list builtin '$name'"
        }
        function Invoke-AllFunction([string]$name, $callParams) {
            $definition = $state.Functions[$name]
            if ($callParams.Count -ne $definition.Params.Count) {
                throw "ALL Type Error: $name() requires $($definition.Params.Count) argument(s)"
            }
            if ($state.Depth -ge 64) { throw 'ALL Runtime Error: Function recursion limit exceeded' }
            $originalVars = $state.Vars
            $locals = [System.Collections.Generic.Dictionary[string,object]]::new([System.StringComparer]::Ordinal)
            for ($i = 0; $i -lt $callParams.Count; $i++) { $locals[$definition.Params[$i]] = $callParams[$i] }
            $state.Vars = $locals
            $state.Depth++
            [void]$state.DebugFunctions.Add($name)
            try {
                $result = Invoke-AllBlock $definition.Body
                if ($null -ne $result -and $result.Flow -ceq 'return') { return $result.Value }
                return $null
            } finally {
                $state.Depth--
                if($state.DebugFunctions.Count -gt 0){$state.DebugFunctions.RemoveAt($state.DebugFunctions.Count-1)}
                $state.Vars = $originalVars
            }
        }
        function Invoke-AllBlock($body) {
            foreach ($statement in $body) {
                $result = Invoke-AllStatement $statement
                if ($null -ne $result) { return $result }
            }
            return $null
        }
        function Invoke-AllStatement($statement) {
            Assert-AllStep
            if($statement.PSObject.Properties['SourceLine']){$state.CurrentLine=[int]$statement.SourceLine}
            if($statement.PSObject.Properties['OriginalSourceFile']){
                $state.CurrentSourceFile=[string]$statement.OriginalSourceFile
                $state.CurrentOriginalLine=[int]$statement.OriginalSourceLine
            }
            Write-AllTrace 'statement' $statement
            Invoke-AllDebugPrompt $statement
            switch ($statement.Kind) {
                'declare' {
                    if ($state.Vars.ContainsKey($statement.Name)) {
                        throw "ALL Name Error: Variable '$($statement.Name)' already declared"
                    }
                    $state.Vars[$statement.Name] = Eval-AllExpression $statement.Expr
                    return $null
                }
                'reassign' {
                    if (-not $state.Vars.ContainsKey($statement.Name)) {
                        throw "ALL Name Error: Undefined variable '$($statement.Name)'"
                    }
                    $state.Vars[$statement.Name] = Eval-AllExpression $statement.Expr
                    return $null
                }
                'set-index' {
                    if (-not $state.Vars.ContainsKey($statement.Name)) {
                        throw "ALL Name Error: Undefined variable '$($statement.Name)'"
                    }
                    $list = $state.Vars[$statement.Name]
                    if (Is-AllMap $list) {
                        $key = Get-AllKey (Eval-AllExpression $statement.Index)
                        $list.Items[$key] = Eval-AllExpression $statement.Expr
                        return $null
                    }
                    $idx = To-AllInteger (Eval-AllExpression $statement.Index) 'list index' 0 2147483647
                    if (-not (Is-AllList $list)) { throw 'ALL Type Error: Indexed assignment requires a list or map' }
                    if ($idx -ge $list.Items.Count) { throw 'ALL Index Error: Index out of range' }
                    $list.Items[[int]$idx] = Eval-AllExpression $statement.Expr
                    return $null
                }
                'output' {
                    if ($statement.Args.Count -gt 0) {
                        $outputValue = Eval-AllExpression $statement.Args[0]
                        [Console]::Write((To-AllText $outputValue))
                    }
                    if ($statement.Newline) { [Console]::Write("`n") }
                    return $null
                }
                'if' {
                    if (Is-AllTrue (Eval-AllExpression $statement.Cond)) {
                        return (Invoke-AllBlock $statement.Then)
                    }
                    return (Invoke-AllBlock $statement.Else)
                }
                'while' {
                    while (Is-AllTrue (Eval-AllExpression $statement.Cond)) {
                        Assert-AllStep
                        $flow = Invoke-AllBlock $statement.Body
                        if ($null -ne $flow) {
                            if ($flow.Flow -ceq 'break') { break }
                            if ($flow.Flow -ceq 'return') { return $flow }
                        }
                    }
                    return $null
                }
                'for' {
                    if ($null -ne $statement.Init) { [void](Invoke-AllStatement $statement.Init) }
                    while ($true) {
                        Assert-AllStep
                        if ($null -ne $statement.Cond -and -not (Is-AllTrue (Eval-AllExpression $statement.Cond))) { break }
                        $flow = Invoke-AllBlock $statement.Body
                        if ($null -ne $flow) {
                            if ($flow.Flow -ceq 'break') { break }
                            if ($flow.Flow -ceq 'return') { return $flow }
                        }
                        if ($null -ne $statement.Update) { [void](Invoke-AllStatement $statement.Update) }
                    }
                    return $null
                }
                'foreach' {
                    $source = Eval-AllExpression $statement.Source
                    if (-not (Is-AllList $source)) { throw 'ALL Type Error: foreach requires a list' }
                    $had = $state.Vars.ContainsKey($statement.Variable)
                    $previous = $null
                    if ($had) { $previous = $state.Vars[$statement.Variable] }
                    try {
                        foreach ($entry in @($source.Items.ToArray())) {
                            Assert-AllStep
                            $state.Vars[$statement.Variable] = $entry
                            $flow = Invoke-AllBlock $statement.Body
                            if ($null -ne $flow) {
                                if ($flow.Flow -ceq 'break') { break }
                                if ($flow.Flow -ceq 'return') { return $flow }
                            }
                        }
                    } finally {
                        if ($had) { $state.Vars[$statement.Variable] = $previous }
                        else { [void]$state.Vars.Remove($statement.Variable) }
                    }
                    return $null
                }
                'try' {
                    try { return (Invoke-AllBlock $statement.Body) }
                    catch {
                        $had = $state.Vars.ContainsKey($statement.ErrorName)
                        $previous = $null
                        if ($had) { $previous = $state.Vars[$statement.ErrorName] }
                        $state.Vars[$statement.ErrorName] = [string]$_.Exception.Message
                        try { return (Invoke-AllBlock $statement.Handler) }
                        finally {
                            if ($had) { $state.Vars[$statement.ErrorName] = $previous }
                            else { [void]$state.Vars.Remove($statement.ErrorName) }
                        }
                    }
                }
                'throw' {
                    $message = Eval-AllExpression $statement.Expr
                    throw (To-AllText $message)
                }
                'namespace' {
                    foreach ($member in $statement.Members) { [void](Invoke-AllStatement $member) }
                    return $null
                }
                'function' {
                    if ($state.Functions.ContainsKey($statement.Name)) {
                        throw "ALL Name Error: Function '$($statement.Name)' already declared"
                    }
                    $state.Functions[$statement.Name] = $statement
                    return $null
                }
                'return' {
                    $value = $null
                    if ($null -ne $statement.Expr) { $value = Eval-AllExpression $statement.Expr }
                    return [pscustomobject]@{ Flow='return'; Value=$value }
                }
                'break' { return [pscustomobject]@{ Flow='break' } }
                'continue' { return [pscustomobject]@{ Flow='continue' } }
                'call-statement' {
                    # Keep v0.2.1 behavior: unknown(1) is an unknown statement.
                    if (-not $state.Functions.ContainsKey($statement.Name) -and $statement.Name -cnotin @('push','pop','remove_key','write_text','append_text','write_json','input','http_serve','http_serve_batch','http_serve_live','kv_put','kv_delete','parallel_all','cli_args','stderr_text','set_exit_code','sql_query','sql_exec','sql_transaction','sql_migrate')) {
                        throw "ALL Syntax Error: Unknown statement '$($statement.Name)'"
                    }
                    [void](Eval-AllExpression $statement.Expr)
                    return $null
                }
                default { throw "ALL Runtime Error: Unknown statement type '$($statement.Kind)'" }
            }
        }

        try {
            [void](Invoke-AllBlock $statements.ToArray())
        } catch {
            Write-AllTrace 'error' $null $_.Exception.Message
            if($state.DebugMode){
                [Console]::Error.WriteLine(('ALL DEBUG error at preprocessed line '+$state.CurrentLine+': '+$_.Exception.Message))
                [Console]::Error.WriteLine(('Call stack: '+[string]::Join(' -> ',$state.DebugFunctions.ToArray())))
            }
            throw
        } finally {
            if($null -ne $state.TraceWriter){$state.TraceWriter.Dispose()}
        }
    }
}
