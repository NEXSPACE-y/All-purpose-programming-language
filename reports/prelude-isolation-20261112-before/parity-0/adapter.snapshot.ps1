@{
    Name = 'PHP'
    Run = {
        # -PhpDiagnostics: report an uncaught PHP exception the way the PHP CLI does (text on the
        # output stream) instead of surfacing it as a PowerShell error. Default behaviour is unchanged.
        param([string]$Code, [switch]$PhpDiagnostics)
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
            PropertyHookActive = [System.Collections.Generic.HashSet[string]]::new(
                [System.StringComparer]::Ordinal)
            Globals = $null
                GlobalBindings = [System.Collections.Generic.HashSet[string]]::new(
                    [System.StringComparer]::Ordinal)
                StaticBindings = [System.Collections.Generic.HashSet[string]]::new(
                    [System.StringComparer]::Ordinal)
                FunctionStatics = [System.Collections.Generic.Dictionary[string,object]]::new(
                    [System.StringComparer]::Ordinal)
                CurrentCallable = $null
                ReturnByRef = $false
                ClassContext = $null
                TokenLines = [System.Collections.Generic.List[int]]::new()
                Line = 0
                ScriptName = 'Command line code'
                CallStack = [System.Collections.Generic.List[object]]::new()
                ThrownObjects = @{}
                ThrownSeq = 0
                PreludeLoaded = $false
                ObjectSeq = 0
                DumpStack = [System.Collections.Generic.List[object]]::new()
                Constants = [System.Collections.Generic.Dictionary[string,object]]::new(
                    [System.StringComparer]::Ordinal)
                QuietDepth = 0
                SilenceDepth = 0
                ErrorReporting = [long]-1
                ErrorHandler = $null
                ErrorHandlerMask = [long]-1
                ErrorHandlerStack = [System.Collections.Generic.List[object]]::new()
                InErrorHandler = $false
                ExceptionHandler = $null
                ExceptionHandlerStack = [System.Collections.Generic.List[object]]::new()
                Ini = @{}
                NamespaceFallbacks = [System.Collections.Generic.Dictionary[int,string]]::new()
        }

        $state.Globals = $state.Vars

        # Predefined constants. PHP_EOL is CRLF because the compatibility target is PHP on Windows.
        $phpConstants = [System.Collections.Generic.Dictionary[string,object]]::new(
            [System.StringComparer]::Ordinal)
        $phpConstants['PHP_EOL'] = "`r`n"
        $phpConstants['PHP_INT_MAX'] = [long]::MaxValue
        $phpConstants['PHP_INT_MIN'] = [long]::MinValue
        $phpConstants['PHP_INT_SIZE'] = [long]8
        $phpConstants['PHP_FLOAT_EPSILON'] = [double]2.220446049250313E-16
        $phpConstants['PHP_FLOAT_MAX'] = [double]::MaxValue
        $phpConstants['PHP_FLOAT_MIN'] = [double]2.2250738585072014E-308
        $phpConstants['PHP_FLOAT_DIG'] = [long]15
        $phpConstants['INF'] = [double]::PositiveInfinity
        $phpConstants['NAN'] = [double]::NaN
        $phpConstants['M_PI'] = [Math]::PI
        $phpConstants['M_E'] = [Math]::E
        $phpConstants['E_ERROR'] = [long]1
        $phpConstants['E_WARNING'] = [long]2
        $phpConstants['E_PARSE'] = [long]4
        $phpConstants['E_NOTICE'] = [long]8
        $phpConstants['E_CORE_ERROR'] = [long]16
        $phpConstants['E_CORE_WARNING'] = [long]32
        $phpConstants['E_COMPILE_ERROR'] = [long]64
        $phpConstants['E_COMPILE_WARNING'] = [long]128
        $phpConstants['E_USER_ERROR'] = [long]256
        $phpConstants['E_USER_WARNING'] = [long]512
        $phpConstants['E_USER_NOTICE'] = [long]1024
        $phpConstants['E_RECOVERABLE_ERROR'] = [long]4096
        $phpConstants['E_DEPRECATED'] = [long]8192
        $phpConstants['E_USER_DEPRECATED'] = [long]16384
        $phpConstants['E_ALL'] = [long]30719
        # The compatibility target (see docs/COMPAT_TARGET.md).
        $phpConstants['PHP_VERSION'] = '8.5.12'
        $phpConstants['PHP_MAJOR_VERSION'] = [long]8
        $phpConstants['PHP_MINOR_VERSION'] = [long]5
        $phpConstants['PHP_RELEASE_VERSION'] = [long]12
        $phpConstants['PHP_VERSION_ID'] = [long]80512
        $phpConstants['PHP_OS'] = 'WINNT'
        $phpConstants['PHP_OS_FAMILY'] = 'Windows'
        $phpConstants['DIRECTORY_SEPARATOR'] = '\'

        # Names backed by the builtin dispatcher below. Unlike declarations collected while
        # parsing, these functions exist before execution, even if a call raises an exception.
        $phpBuiltinNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($builtinName in @(
            'json_encode','json_decode','json_last_error','json_last_error_msg','count','strlen',
            'strtoupper','strtolower','trim','abs','array_sum','array_key_exists','is_array',
            'is_string','is_bool','array_push','array_pop','array_shift','array_unshift',
            'array_reverse','array_merge','array_slice','array_keys','array_values',
            'array_key_first','array_key_last','array_first','array_last','in_array',
            'str_contains','str_starts_with','str_ends_with','strpos','substr','str_replace',
            'explode','implode','__all_throwable_string','print_r','define','defined','constant',
            'error_reporting','ini_set','ini_get','set_error_handler','restore_error_handler',
            'set_exception_handler','restore_exception_handler','trigger_error','user_error',
            'str_repeat','function_exists','call_user_func','call_user_func_array','get_class',
            'var_dump','gettype','is_int','is_integer','is_long','is_float','is_double',
            'is_null','is_numeric','intval','floatval','doubleval','boolval','intdiv','fdiv',
            'pow','sqrt','floor','ceil','is_nan','is_infinite','is_finite','strval'
        )) { [void]$phpBuiltinNames.Add($builtinName) }

        # Tokenize before parsing. Unknown characters produce an error, never disappear.
        $pattern = '(?:\s+|//[^\r\n]*|\#[^\r\n]*|/\*[\s\S]*?\*/|"(?:\\.|[^"\\])*"|''(?:\\.|[^''\\])*''|\$\$[A-Za-z_][A-Za-z_0-9]*|\$[A-Za-z_][A-Za-z_0-9]*|\$(?=\{)|0[xX][0-9a-fA-F_]+|0[bB][01_]+|0[oO][0-7_]+|(?:\d[\d_]*(?:\.[\d_]*)?|\.\d[\d_]*)(?:[eE][+-]?\d[\d_]*)?|\\?[A-Za-z_][A-Za-z_0-9]*(?:\\[A-Za-z_][A-Za-z_0-9]*)*\\?|<=>|::|\.\.\.|<<=|>>=|<<|>>|===|!==|==|!=|<=|>=|&&|\|\||=>|->|\*\*=|\*\*|\?\?=|\?\?|\?->|\+\+|--|\*=|/=|%=|&=|\|=|\^=|\+=|-=|\.=|[+\-*/%.=<>!?:;{},()\[\]&|^~@])'
        $rx = [regex]::new($pattern)
        function ConvertTo-PhpTokens([string]$text, $tokens, $lines) {
            $line = 1
            for ($offset = 0; $offset -lt $text.Length;) {
                $match = $rx.Match($text, $offset)
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
                if ($token.IndexOf([char]10) -ge 0) { $line += ($token.Split([char]10).Count - 1) }
                $offset += $token.Length
            }
            [void]$tokens.Add('(EOF)')
            [void]$lines.Add($line)
        }
        # ---- Namespaces -------------------------------------------------------------------------
        # Names are resolved once, on the token stream, before parsing: "namespace" and "use"
        # statements are consumed and every class, function and constant name is rewritten to its
        # fully qualified form without a leading backslash (the form PHP itself reports).
        $phpNameRx = [regex]::new('^\\?[A-Za-z_][A-Za-z_0-9]*(?:\\[A-Za-z_][A-Za-z_0-9]*)*\\?$')
        $phpReservedNames = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::OrdinalIgnoreCase)
        foreach ($word in @('abstract','and','array','as','break','callable','case','catch','class','clone','const',
            'continue','declare','default','do','echo','else','elseif','empty','enddeclare','endfor','endforeach',
            'endif','endswitch','endwhile','enum','exit','die','extends','final','finally','fn','for','foreach',
            'function','global','goto','if','implements','include','include_once','instanceof','insteadof',
            'interface','isset','list','match','namespace','new','or','print','private','protected','public',
            'readonly','require','require_once','return','static','switch','throw','trait','try','unset','use',
            'var','while','xor','yield','from','true','false','null','self','parent','int','float','string',
            'bool','iterable','object','mixed','void','never')) { [void]$phpReservedNames.Add($word) }
        function Resolve-PhpNamespaceTokens($tokens, $lines) {
            $total = $tokens.Count
            $declFunctions = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            $declConsts = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
            $outTokens = [System.Collections.Generic.List[string]]::new()
            $outLines = [System.Collections.Generic.List[int]]::new()
            $outFallbacks = [System.Collections.Generic.Dictionary[int,string]]::new()
            foreach ($pass in 1, 2) {
                $ns = ''
                $depth = 0
                $classStack = [System.Collections.Generic.Stack[int]]::new()
                $nsStack = [System.Collections.Generic.Stack[int]]::new()
                $pendingClass = $false
                $classList = $false
                $useClass = [System.Collections.Generic.Dictionary[string,string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                $useFunc = [System.Collections.Generic.Dictionary[string,string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                $useConst = [System.Collections.Generic.Dictionary[string,string]]::new([System.StringComparer]::Ordinal)
                $prefix = { param($name) if ($ns.Length -gt 0) { return ($ns + '\' + $name) }; return $name }
                $qualify = {
                    param($name)   # shared rules for names that are not unqualified
                    if ($name.StartsWith('\')) { return $name.Substring(1) }
                    if ($name.StartsWith('namespace\', [System.StringComparison]::OrdinalIgnoreCase)) {
                        return (& $prefix $name.Substring(10))
                    }
                    $cut = $name.IndexOf('\')
                    if ($cut -gt 0) {
                        $head = $name.Substring(0, $cut)
                        if ($useClass.ContainsKey($head)) { return ($useClass[$head] + $name.Substring($cut)) }
                        return (& $prefix $name)
                    }
                    return $null
                }
                $resolveClass = {
                    param($name)
                    $q = & $qualify $name
                    if ($null -ne $q) { return $q }
                    if ($phpReservedNames.Contains($name)) { return $name }
                    if ($useClass.ContainsKey($name)) { return $useClass[$name] }
                    return (& $prefix $name)
                }
                $resolveFunc = {
                    param($name)
                    $q = & $qualify $name
                    if ($null -ne $q) { return $q }
                    if ($useFunc.ContainsKey($name)) { return $useFunc[$name] }
                    return (& $prefix $name)
                }
                $resolveConst = {
                    param($name)
                    $q = & $qualify $name
                    if ($null -ne $q) { return $q }
                    if ($useConst.ContainsKey($name)) { return $useConst[$name] }
                    return (& $prefix $name)
                }
                for ($i = 0; $i -lt $total; $i++) {
                    $t = $tokens[$i]
                    $prev = if ($i -gt 0) { $tokens[$i - 1] } else { '' }
                    $next = if ($i + 1 -lt $total) { $tokens[$i + 1] } else { '' }
                    $inClass = ($classStack.Count -gt 0)
                    $atMember = ($inClass -and $depth -eq $classStack.Peek())
                    $emit = $t
                    $fallback = $null
                    if ($t -ceq '{') {
                        $depth++
                        if ($pendingClass) { $classStack.Push($depth); $pendingClass = $false }
                        $classList = $false
                    } elseif ($t -ceq '}') {
                        if ($nsStack.Count -gt 0 -and $depth -eq $nsStack.Peek()) {
                            [void]$nsStack.Pop()
                            $ns = ''
                            $useClass.Clear(); $useFunc.Clear(); $useConst.Clear()
                            continue
                        }
                        if ($inClass -and $depth -eq $classStack.Peek()) { [void]$classStack.Pop() }
                        $depth--
                    } elseif ($t -ceq ';') {
                        $classList = $false
                    } elseif ($phpNameRx.IsMatch($t)) {
                        $lower = $t.ToLowerInvariant()
                        # Reserved words are legal as constant, method and member names ("const USE",
                        # "function namespace()", "namespace as bar"); in those positions they are plain names.
                        $isMember = ($prev -ceq '->' -or $prev -ceq '?->' -or $prev -ceq '::')
                        $plainName = ($prev -ieq 'const' -or $prev -ieq 'function' -or $prev -ieq 'as' -or
                            $prev -ieq 'case' -or ($inClass -and ($next -ieq 'as' -or $next -ieq 'insteadof')))
                        $startsStatement = ($prev -ceq '' -or $prev -ceq ';' -or $prev -ceq '{' -or $prev -ceq '}')
                        if (-not $isMember -and -not $plainName -and $startsStatement -and
                            $lower -ceq 'namespace' -and $next -cne '(') {
                            # namespace A\B;   namespace A\B { ... }   namespace { ... }
                            $j = $i + 1
                            $name = ''
                            if ($j -lt $total -and $tokens[$j] -cne '{' -and $tokens[$j] -cne ';') { $name = $tokens[$j]; $j++ }
                            $ns = $name.TrimStart('\')
                            $useClass.Clear(); $useFunc.Clear(); $useConst.Clear()
                            if ($j -lt $total -and $tokens[$j] -ceq '{') { $nsStack.Push($depth) }
                            $i = $j
                            continue
                        }
                        if (-not $isMember -and -not $plainName -and $startsStatement -and
                            $lower -ceq 'use' -and -not $inClass -and $next -cne '(') {
                            # use A\B;  use A\B as C;  use function A\f;  use const A\C;  use A\{B, C as D};
                            $kind = 'class'
                            $j = $i + 1
                            if ($tokens[$j] -ieq 'function') { $kind = 'function'; $j++ }
                            elseif ($tokens[$j] -ieq 'const') { $kind = 'const'; $j++ }
                            $group = ''
                            while ($j -lt $total -and $tokens[$j] -cne ';') {
                                $item = $tokens[$j]
                                if ($item -ceq ',' ) { $j++; continue }
                                if ($item -ceq '}') { $group = ''; $j++; continue }
                                $itemKind = $kind
                                if ($item -ieq 'function' -and $group.Length -gt 0) { $itemKind = 'function'; $j++; $item = $tokens[$j] }
                                elseif ($item -ieq 'const' -and $group.Length -gt 0) { $itemKind = 'const'; $j++; $item = $tokens[$j] }
                                if ($j + 1 -lt $total -and $tokens[$j + 1] -ceq '{') {
                                    $group = $item.TrimStart('\')
                                    if (-not $group.EndsWith('\')) { $group += '\' }
                                    $j += 2
                                    continue
                                }
                                $target = $group + $item.TrimStart('\')
                                $alias = $target.Substring($target.LastIndexOf('\') + 1)
                                $j++
                                if ($j + 1 -lt $total -and $tokens[$j] -ieq 'as') { $alias = $tokens[$j + 1]; $j += 2 }
                                if ($itemKind -eq 'function') { $useFunc[$alias] = $target }
                                elseif ($itemKind -eq 'const') { $useConst[$alias] = $target }
                                else { $useClass[$alias] = $target }
                            }
                            $i = $j
                            continue
                        }
                        if ($isMember) {
                            # member name: never resolved
                        } elseif ($lower -ceq '__namespace__' -and -not $plainName) {
                            $emit = "'" + $ns.Replace('\', '\\') + "'"
                        } elseif (-not $plainName -and -not $t.Contains('\') -and $phpReservedNames.Contains($t)) {
                            if ($lower -in @('class','interface','trait','enum')) {
                                if ($lower -ne 'enum' -or $phpNameRx.IsMatch($next)) { $pendingClass = $true }
                            }
                            if ($lower -in @('extends','implements')) { $classList = $true }
                            if ($lower -ceq 'use' -and $atMember) { $classList = $true }
                        } elseif ($next -ceq '::') {
                            $resolved = & $resolveClass $t
                            if ($i + 2 -lt $total -and $tokens[$i + 2] -ieq 'class' -and
                                -not $phpReservedNames.Contains($t)) {
                                $emit = "'" + $resolved.Replace('\', '\\') + "'"
                                if ($pass -eq 2) { [void]$outTokens.Add($emit); [void]$outLines.Add($lines[$i]) }
                                $i += 2
                                continue
                            }
                            $emit = $resolved
                        } elseif ($prev -ieq 'class' -or $prev -ieq 'interface' -or $prev -ieq 'trait' -or $prev -ieq 'enum') {
                            $emit = & $prefix $t
                        } elseif ($prev -ieq 'function' -or ($prev -ceq '&' -and $i -gt 1 -and $tokens[$i - 2] -ieq 'function')) {
                            if (-not $inClass) {
                                $emit = & $prefix $t
                                if ($pass -eq 1) { [void]$declFunctions.Add($emit) }
                            }
                        } elseif ($prev -ieq 'const') {
                            if (-not $inClass) {
                                $emit = & $prefix $t
                                if ($pass -eq 1) { [void]$declConsts.Add($emit) }
                            }
                        } elseif ($classList -or $prev -ieq 'new' -or $prev -ieq 'instanceof' -or
                                  $prev -ieq 'extends' -or $prev -ieq 'implements' -or $prev -ieq 'insteadof') {
                            $emit = & $resolveClass $t
                        } elseif ($prev -ieq 'goto' -or ($next -ceq ':' -and ($prev -ceq '(' -or $prev -ceq ','))) {
                            # label or named argument
                        } elseif ($prev -ieq 'case' -and $atMember) {
                            # enum case name
                        } elseif ($inClass -and ($lower -ceq 'get' -or $lower -ceq 'set') -and
                                  ($next -ceq '{' -or $next -ceq '=>' -or $next -ceq ';' -or $next -ceq '(')) {
                            # property hook
                        } else {
                            # A type? Look right for "... $variable", look left for "): Type" or "catch (Type".
                            $isType = $false
                            $k = $i + 1
                            while ($k + 1 -lt $total -and ($tokens[$k] -ceq '|' -or $tokens[$k] -ceq '&') -and
                                   ($phpNameRx.IsMatch($tokens[$k + 1]) -or $tokens[$k + 1] -ceq '?')) { $k += 2 }
                            if ($k -lt $total) {
                                $after = $tokens[$k]
                                if ($after.StartsWith('$')) { $isType = $true }
                                elseif (($after -ceq '&' -or $after -ceq '...') -and $k + 1 -lt $total -and
                                        $tokens[$k + 1].StartsWith('$')) { $isType = $true }
                                elseif ($after -ceq '...' -and $k + 1 -lt $total -and $tokens[$k + 1].StartsWith('$')) { $isType = $true }
                            }
                            if (-not $isType) {
                                $k = $i - 1
                                while ($k -gt 1 -and ($tokens[$k] -ceq '|' -or $tokens[$k] -ceq '&') -and
                                       $phpNameRx.IsMatch($tokens[$k - 1])) { $k -= 2 }
                                if ($k -ge 1 -and $tokens[$k] -ceq '?') { $k-- }
                                if ($k -ge 1 -and $tokens[$k] -ceq ':' -and $tokens[$k - 1] -ceq ')') {
                                    # "): Type" is a return type only when the parentheses belong to a
                                    # function signature (otherwise it is the else branch of a ternary).
                                    $m = $k - 1
                                    $nesting = 0
                                    while ($m -ge 0) {
                                        if ($tokens[$m] -ceq ')') { $nesting++ }
                                        elseif ($tokens[$m] -ceq '(') { $nesting--; if ($nesting -eq 0) { break } }
                                        $m--
                                    }
                                    if ($m -ge 1) {
                                        $before = $tokens[$m - 1]
                                        if ($before -ieq 'function' -or $before -ieq 'fn' -or $before -ieq 'use') { $isType = $true }
                                        elseif ($m -ge 2 -and $tokens[$m - 2] -ieq 'function') { $isType = $true }
                                        elseif ($m -ge 3 -and $tokens[$m - 2] -ceq '&' -and $tokens[$m - 3] -ieq 'function') { $isType = $true }
                                        elseif ($before -ceq '&' -and $m -ge 2 -and ($tokens[$m - 2] -ieq 'function' -or $tokens[$m - 2] -ieq 'fn')) { $isType = $true }
                                    }
                                }
                                elseif ($k -ge 1 -and $tokens[$k] -ceq '(' -and $tokens[$k - 1] -ieq 'catch') { $isType = $true }
                            }
                            if ($isType) { $emit = & $resolveClass $t }
                            elseif ($next -ceq '(') {
                                $emit = & $resolveFunc $t
                                if ($ns.Length -gt 0 -and -not $t.Contains('\') -and -not $useFunc.ContainsKey($t)) {
                                    $fallback = $t
                                }
                            } else {
                                $emit = & $resolveConst $t
                                if ($ns.Length -gt 0 -and -not $t.Contains('\') -and -not $useConst.ContainsKey($t)) {
                                    $fallback = $t
                                }
                            }
                        }
                    }
                    if ($pass -eq 2) {
                        if ($null -ne $fallback) { $outFallbacks[$outTokens.Count] = $fallback }
                        [void]$outTokens.Add($emit); [void]$outLines.Add($lines[$i])
                    }
                }
            }
            return [pscustomobject]@{ Tokens=$outTokens; Lines=$outLines; Fallbacks=$outFallbacks }
        }
        ConvertTo-PhpTokens $source $state.Tokens $state.TokenLines
        # Only programs that actually use namespaces, imports or qualified names take this pass.
        $needsNameResolution = $false
        for ($scan = 0; $scan -lt $state.Tokens.Count; $scan++) {
            $candidate = $state.Tokens[$scan]
            if ($candidate.Length -eq 0) { continue }
            $firstChar = $candidate[0]
            if ($firstChar -eq [char]'"' -or $firstChar -eq [char]"'" -or $firstChar -eq [char]'$') { continue }
            if ($candidate.Contains('\') -or $candidate -ieq 'namespace' -or $candidate -ieq '__NAMESPACE__') {
                $needsNameResolution = $true; break
            }
            if ($candidate -ieq 'use' -and $scan + 1 -lt $state.Tokens.Count -and
                $state.Tokens[$scan + 1] -cne '(') { $needsNameResolution = $true; break }
        }
        if ($needsNameResolution) {
            $resolvedNames = Resolve-PhpNamespaceTokens $state.Tokens $state.TokenLines
            $state.Tokens = $resolvedNames.Tokens
            $state.NamespaceFallbacks = $resolvedNames.Fallbacks
            $state.TokenLines = $resolvedNames.Lines
        }

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
                    if ($first -cmatch '^[A-Za-z_][A-Za-z_0-9\\]*$' -and
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
        # PHP numeric literal -> System.Int64 (PHP int) or System.Double (PHP float).
        # Integer literals that do not fit in 64 bits become floats, as in PHP.
        # Correctly rounded (round-half-even) conversion of a non-negative BigInteger to a double.
        function ConvertTo-PhpDoubleFromBigInt($big) {
            if ($big.Sign -lt 0) { return (-1.0 * (ConvertTo-PhpDoubleFromBigInt ([bigint]::Negate($big)))) }
            if ($big.IsZero) { return [double]0 }
            $bytes = $big.ToByteArray()
            $top = $bytes.Length - 1
            while ($top -gt 0 -and $bytes[$top] -eq 0) { $top-- }
            $bitLength = $top * 8
            $lead = [int]$bytes[$top]
            while ($lead -gt 0) { $bitLength++; $lead = $lead -shr 1 }
            $shift = $bitLength - 53
            if ($shift -le 0) { return [double][long]$big }
            $scale = [bigint]::Pow(2, $shift)
            $quotient = [bigint]::Divide($big, $scale)
            $remainder = $big - ($quotient * $scale)
            $half = [bigint]::Pow(2, $shift - 1)
            if ($remainder -gt $half -or ($remainder -eq $half -and -not $quotient.IsEven)) {
                $quotient = $quotient + 1
            }
            return ([double][long]$quotient * [Math]::Pow(2, $shift))
        }
        function ConvertFrom-PhpNumberLiteral([string]$token) {
            $text = $token.Replace('_', '')
            $inv = [System.Globalization.CultureInfo]::InvariantCulture
            $radix = 0
            $body = ''
            if ($text -match '^0[xX]') { $radix = 16; $body = $text.Substring(2) }
            elseif ($text -match '^0[bB]') { $radix = 2; $body = $text.Substring(2) }
            elseif ($text -match '^0[oO]') { $radix = 8; $body = $text.Substring(2) }
            elseif ($text -match '^0[0-7]+$') { $radix = 8; $body = $text.Substring(1) }
            if ($radix -ne 0) {
                $big = [bigint]::Zero
                foreach ($ch in $body.ToCharArray()) {
                    $digit = [Convert]::ToInt32([string]$ch, 16)
                    if ($digit -ge $radix) { throw "ALL PHP: Invalid numeric literal '$token'" }
                    $big = $big * $radix + $digit
                }
                if ($big -le [bigint][long]::MaxValue) { return [long]$big }
                return (ConvertTo-PhpDoubleFromBigInt $big)
            }
            if ($text -match '^\d+$') {
                $n = [long]0
                if ([long]::TryParse($text, [System.Globalization.NumberStyles]::None, $inv, [ref]$n)) {
                    return $n
                }
                return (ConvertTo-PhpDoubleFromBigInt ([bigint]::Parse($text, $inv)))
            }
            try { return [double]::Parse($text, [System.Globalization.NumberStyles]::Float, $inv) }
            catch { return [double]::PositiveInfinity }
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
            $fallbackName = $null
            if ($state.NamespaceFallbacks.ContainsKey($state.Pos)) {
                $fallbackName = $state.NamespaceFallbacks[$state.Pos]
            }
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
            if ($token -cmatch '^(?:\d|\.\d)') {
                [void](Next-Token)
                return [pscustomobject]@{
                    Kind='literal'; Value=(ConvertFrom-PhpNumberLiteral $token)
                }
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
                $returnByRef=$false
                if ((Peek-Token) -ceq '&') {
                    [void](Next-Token)
                    $returnByRef=$true
                }
                $params=Read-Parameters
                $returnType=''
                $captures=[System.Collections.Generic.List[object]]::new()
                $body=$null
                $expr=$null
                if ($arrow) {
                    if ((Peek-Token) -ceq ':') {
                        [void](Next-Token)
                        $returnType=Read-PhpTypeAnnotation
                    }
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
                    if ((Peek-Token) -ceq ':') {
                        [void](Next-Token)
                        $returnType=Read-PhpTypeAnnotation
                    }
                    if ((Peek-Token) -cne '{') { throw 'ALL PHP: Closure body must be a block' }
                    $body=Read-Statement
                }
                return [pscustomobject]@{
                    Kind='closure'; Params=@($params); Body=$body; Expr=$expr
                    Captures=$captures.ToArray(); Arrow=$arrow
                    ReturnByRef=$returnByRef; ReturnType=$returnType
                    Name='(closure)'
                }
            }
            if ($token -eq 'throw') {
                [void](Next-Token)
                return [pscustomobject]@{ Kind='throw'; Arg=(Read-Expr 1) }
            }
            if ($token -eq 'new') {
                [void](Next-Token)
                $className = Next-Token
                if ($className -cnotmatch '^[A-Za-z_][A-Za-z_0-9\\]*$') {
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
            if ($token -cmatch '^[A-Za-z_][A-Za-z_0-9\\]*$') {
                [void](Next-Token)
                if ($token -eq 'stdClass') {
                    return [pscustomobject]@{ Kind='class_name'; Name=$token }
                }
                if ((Peek-Token) -ceq '(') {
                    if (Take-PhpFirstClassCallableArgs) {
                        return [pscustomobject]@{
                            Kind='first_class_function'; Name=$token; Fallback=$fallbackName; ResolvedName=$null
                        }
                    }
                    $callArgs = Read-Arguments
                    return [pscustomobject]@{ Kind='call'; Name=$token; Args=@($callArgs); Fallback=$fallbackName; ResolvedName=$null }
                }
                return [pscustomobject]@{ Kind='class_name'; Name=$token; Fallback=$fallbackName; ResolvedName=$null }
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
                    } elseif ($member -cmatch '^[A-Za-z_][A-Za-z_0-9\\]*$') {
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
                    if ($member -cnotmatch '^[A-Za-z_][A-Za-z_0-9\\]*$') {
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
            if ($token -ceq '@') {
                [void](Next-Token)
                return [pscustomobject]@{ Kind='silence'; Arg=(Read-Unary) }
            }
            if ($token -ceq '!') {
                # In PHP, ! binds less tightly than instanceof, but more tightly
                # than multiplication/comparison. Use the instanceof priority.
                [void](Next-Token)
                $arg = Read-Expr 14
                return [pscustomobject]@{ Kind='unary'; Op=$token; Arg=$arg }
            }
            if ($token -ceq '(' -and ($state.Pos + 2) -lt $state.Tokens.Count -and
                $state.Tokens[$state.Pos + 2] -ceq ')' -and
                $state.Tokens[$state.Pos + 1] -in @('int','integer','float','double','string','bool','boolean')) {
                [void](Next-Token)
                $castType = (Next-Token).ToLowerInvariant()
                [void](Next-Token)
                return [pscustomobject]@{ Kind='cast'; Type=$castType; Arg=(Read-Unary) }
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
                    if ($refTarget.Kind -notin @('variable','dynamic_variable','index','property','static_property','call','method','static_method','invoke')) {
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
                    $value = [pscustomobject]@{ Kind='literal'; Value=[long]1 }
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
        # Every statement node records the source line it starts on.
        function Read-Statement {
            $line = $state.TokenLines[$state.Pos]
            $node = Read-StatementCore
            if ($null -ne $node -and -not $node.PSObject.Properties['Line']) {
                $node | Add-Member -NotePropertyName Line -NotePropertyValue $line
            }
            return $node
        }
        function Read-StatementCore {
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
                ($state.Tokens[$state.Pos + 1] -cmatch '^[A-Za-z_][A-Za-z_0-9\\]*$' -or
                 ($state.Tokens[$state.Pos + 1] -ceq '&' -and
                  $state.Pos + 2 -lt $state.Tokens.Count -and
                  $state.Tokens[$state.Pos + 2] -cmatch '^[A-Za-z_][A-Za-z_0-9\\]*$'))) {
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
                if ($name -cnotmatch '^[A-Za-z_][A-Za-z_0-9\\]*$') {
                    throw 'ALL PHP: Expected interface name'
                }
                $parents = [System.Collections.Generic.List[string]]::new()
                if ((Peek-Token) -eq 'extends') {
                    [void](Next-Token)
                    while ($true) {
                        $parentName = Next-Token
                        if ($parentName -cnotmatch '^[A-Za-z_][A-Za-z_0-9\\]*$') {
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
                        if ($constName -cnotmatch '^[A-Za-z_][A-Za-z_0-9\\]*$') {
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
                if ($enumName -cnotmatch '^[A-Za-z_][A-Za-z_0-9\\]*$') {
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
                        if ($iface -cnotmatch '^[A-Za-z_][A-Za-z_0-9\\]*$') {
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
                        if ($caseName -cnotmatch '^[A-Za-z_][A-Za-z_0-9\\]*$') {
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
            if ($token -in @('abstract','final','readonly','class','trait')) {
                $isAbstract=$false
                $isFinal=$false
                $isTrait=($token -eq 'trait')
                $isReadonlyClass=$false
                if ($token -eq 'readonly') { $isReadonlyClass=$true; [void](Next-Token); Expect-Token 'class' }
                elseif ($token -eq 'abstract') { $isAbstract=$true; [void](Next-Token); Expect-Token 'class' }
                elseif ($token -eq 'final') { $isFinal=$true; [void](Next-Token); Expect-Token 'class' }
                else { [void](Next-Token) }
                $name = Next-Token
                if ($name -cnotmatch '^[A-Za-z_][A-Za-z_0-9\\]*$') {
                    throw 'ALL PHP: Expected class name'
                }
                $parent = $null
                if ((Peek-Token) -eq 'extends') {
                    [void](Next-Token)
                    $parent = Next-Token
                    if ($parent -cnotmatch '^[A-Za-z_][A-Za-z_0-9\\]*$') {
                        throw 'ALL PHP: Expected parent class name'
                    }
                }
                $interfaces=[System.Collections.Generic.List[string]]::new()
                if ((Peek-Token) -eq 'implements') {
                    [void](Next-Token)
                    while ($true) {
                        $iface = Next-Token
                        if ($iface -cnotmatch '^[A-Za-z_][A-Za-z_0-9\\]*$') {
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
                            if ($traitName -cnotmatch '^[A-Za-z_][A-Za-z_0-9\\]*$') {
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
                                if ($member -cnotmatch '^[A-Za-z_][A-Za-z_0-9\\]*$') {
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
                                        if ($loser -cnotmatch '^[A-Za-z_][A-Za-z_0-9\\]*$') {
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
                                        if ($alias -cnotmatch '^[A-Za-z_][A-Za-z_0-9\\]*$') {
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
                    $isReadonlyProperty=$false
                    $modifiers=[System.Collections.Generic.HashSet[string]]::new(
                        [System.StringComparer]::Ordinal)
                    while ((Peek-Token) -in @('public','private','protected','static','abstract','final','readonly')) {
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
                        elseif ($modifier -eq 'readonly') { $isReadonlyProperty=$true }
                    }
                    if ((Peek-Token) -eq 'function') {
                        if ($isReadonlyProperty) { throw 'ALL PHP: readonly modifier cannot be applied to method' }
                        if ($isAbstractMethod -and $isFinalMethod) {
                            throw 'ALL PHP: Method cannot be both abstract and final'
                        }
                        if ($isAbstractMethod -and -not $isAbstract) {
                            throw 'ALL PHP: Abstract methods require an abstract class'
                        }
                        if ($isAbstractMethod -and $visibility -eq 'private') {
                            throw 'ALL PHP: Abstract methods cannot be private'
                        }
                        $method = Read-Function $isAbstractMethod $true
                        $method.Visibility=$visibility
                        $method.Static=$isStatic
                        $method.Owner=$name
                        $method.Abstract=$isAbstractMethod
                        $method.Final=$isFinalMethod
                        [void]$methods.Add($method)
                        if ($method.Name -ieq '__construct') {
                            foreach ($parameter in $method.Params) {
                                if (-not $parameter.Promoted) { continue }
                                if ($isReadonlyClass -and [string]::IsNullOrEmpty($parameter.TypeName)) {
                                    throw 'ALL PHP: readonly class promoted property requires a type'
                                }
                                [void]$properties.Add([pscustomobject]@{
                                    Name=$parameter.Name; Default=$null
                                    Visibility=$parameter.Visibility; Static=$false
                                    Owner=$name; TypeName=$parameter.TypeName
                                    Readonly=([bool]$parameter.Readonly -or $isReadonlyClass)
                                })
                            }
                        }
                    } elseif ((Peek-Token) -eq 'const') {
                        if ($isStatic -or $isAbstractMethod -or $isFinalMethod -or $isReadonlyProperty) {
                            throw 'ALL PHP: Unsupported constant modifier'
                        }
                        [void](Next-Token)
                        $constName = Next-Token
                        if ($constName -cnotmatch '^[A-Za-z_][A-Za-z_0-9\\]*$') {
                            throw 'ALL PHP: Expected class constant name'
                        }
                        Expect-Token '='
                        $constValue=Read-Expr 1
                        Expect-Token ';'
                        [void]$constants.Add([pscustomobject]@{
                            Name=$constName; Value=$constValue; Visibility=$visibility
                        })
                    } else {
                        $propertyType=''
                        if ((Peek-Token) -ceq '?' -or
                            (Peek-Token) -cmatch '^[A-Za-z_][A-Za-z_0-9\\]*$') {
                            $propertyType=Read-PhpTypeAnnotation
                        }
                        if ((Peek-Token) -cnotmatch '^\$[A-Za-z_][A-Za-z_0-9]*$') {
                            throw "ALL PHP: Unsupported class member '$(Peek-Token)'"
                        }
                        if ($isAbstractMethod -or $isFinalMethod) {
                            throw 'ALL PHP: Abstract/final modifier not valid for properties'
                        }
                        if ($propertyType -in @('void','never')) {
                            throw 'ALL PHP: void/never cannot be used as property types'
                        }
                        $isReadOnly=($isReadonlyProperty -or $isReadonlyClass)
                        if ($isReadOnly -and $isStatic) {
                            throw 'ALL PHP: readonly static property is not allowed'
                        }
                        if ($isReadOnly -and [string]::IsNullOrEmpty($propertyType)) {
                            throw 'ALL PHP: readonly property requires a type'
                        }
                        $propName = (Next-Token).Substring(1)
                        $defaultExpr = $null
                        if ((Peek-Token) -ceq '=') {
                            [void](Next-Token)
                            $defaultExpr = Read-Expr 1
                        }
                        if ($isReadOnly -and $null -ne $defaultExpr) {
                            throw 'ALL PHP: readonly property cannot have a default value'
                        }
                        $getHook=$null
                        $setHook=$null
                        # Hook names must be unique even when their bodies are empty.
                        # Check the declaration names independently of hook objects.
                        $seenHookNames=[System.Collections.Generic.HashSet[string]]::new(
                            [System.StringComparer]::Ordinal)
                        $hookBacked=($null -ne $defaultExpr)
                        if ((Peek-Token) -ceq '{') {
                            if ($isStatic) { throw 'ALL PHP: Static property hooks are not supported by PHP' }
                            if ($isReadOnly) { throw 'ALL PHP: readonly property cannot declare hooks' }
                            Expect-Token '{'
                            while ((Peek-Token) -cne '}') {
                                if ((Peek-Token) -ceq '(EOF)') {
                                    throw 'ALL PHP: Missing property hook closing brace'
                                }
                                $hookName=Next-Token
                                if ($hookName -notin @('get','set')) {
                                    throw "ALL PHP: Unknown property hook '$hookName'"
                                }
                                if (-not $seenHookNames.Add($hookName)) {
                                    throw 'ALL PHP: Duplicate property hook'
                                }
                                if ($hookName -ceq 'get' -and $null -ne $getHook -or
                                    $hookName -ceq 'set' -and $null -ne $setHook) {
                                    throw 'ALL PHP: Duplicate property hook'
                                }
                                $hookParams=@()
                                if ((Peek-Token) -ceq '(') {
                                    if ($hookName -ceq 'get') {
                                        throw 'ALL PHP: Getter hook takes no arguments'
                                    }
                                    $hookParams=Read-Parameters $false
                                    if ($hookParams.Count -ne 1 -or
                                        $hookParams[0].ByRef -or $hookParams[0].Variadic -or
                                        $null -ne $hookParams[0].Default) {
                                        throw 'ALL PHP: Setter hook must have one regular parameter'
                                    }
                                }
                                $body=$null
                                $expr=$null
                                $arrow=$false
                                $hookSourceStart=$state.Pos
                                if ((Peek-Token) -ceq '=>') {
                                    Expect-Token '=>'
                                    $expr=Read-Expr 1
                                    Expect-Token ';'
                                    $arrow=$true
                                } elseif ((Peek-Token) -ceq '{') {
                                    $body=Read-Statement
                                } else {
                                    throw 'ALL PHP: Expected property hook body'
                                }
                                if ($hookName -ceq 'set' -and $arrow) {
                                    $hookBacked=$true
                                }
                                for ($hi=$hookSourceStart; $hi + 2 -lt $state.Pos; $hi++) {
                                    if ($state.Tokens[$hi] -ceq '$this' -and
                                        $state.Tokens[$hi + 1] -ceq '->' -and
                                        $state.Tokens[$hi + 2] -ceq $propName) {
                                        $hookBacked=$true
                                    }
                                }
                                $hook=[pscustomobject]@{
                                    Body=$body; Expr=$expr; Arrow=$arrow; Params=$hookParams
                                }
                                if ($hookName -ceq 'get') { $getHook=$hook }
                                else { $setHook=$hook }
                            }
                            Expect-Token '}'
                        } else {
                            Expect-Token ';'
                        }
                        [void]$properties.Add([pscustomobject]@{
                            Name=$propName; Default=$defaultExpr
                            Visibility=$visibility; Static=$isStatic; Owner=$name
                            TypeName=$propertyType; Readonly=$isReadOnly
                            GetHook=$getHook; SetHook=$setHook; HookBacked=$hookBacked
                        })
                    }
                }
                Expect-Token '}'
                return [pscustomobject]@{
                    Kind=$(if ($isTrait) { 'traitdef' } else { 'classdef' }); Name=$name; Parent=$parent
                    Methods=$methods.ToArray(); Properties=$properties.ToArray()
                    Constants=$constants.ToArray(); Interfaces=$interfaces.ToArray()
                    Abstract=$isAbstract; Final=$isFinal; Readonly=$isReadonlyClass; Traits=$traits.ToArray()
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
            if ($token -eq 'const' -and $state.Pos + 2 -lt $state.Tokens.Count -and
                $state.Tokens[$state.Pos + 1] -cmatch '^[A-Za-z_][A-Za-z_0-9\\]*$' -and
                $state.Tokens[$state.Pos + 2] -ceq '=') {
                [void](Next-Token)
                $decls = [System.Collections.Generic.List[object]]::new()
                while ($true) {
                    $constName = Next-Token
                    if ($constName -cnotmatch '^[A-Za-z_][A-Za-z_0-9\\]*$') {
                        throw "ALL PHP: Expected constant name, got '$constName'"
                    }
                    Expect-Token '='
                    [void]$decls.Add([pscustomobject]@{ Name=$constName; Value=(Read-Expr 1) })
                    if ((Peek-Token) -cne ',') { break }
                    [void](Next-Token)
                }
                Expect-Token ';'
                return [pscustomobject]@{ Kind='constdecl'; Decls=$decls.ToArray() }
            }
            if ($token -eq 'try') {
                [void](Next-Token)
                if ((Peek-Token) -cne '{') { throw "ALL PHP: Expected '{', got '$(Peek-Token)'" }
                $body = Read-Statement
                $catches = [System.Collections.Generic.List[object]]::new()
                while ((Peek-Token) -eq 'catch') {
                    [void](Next-Token)
                    Expect-Token '('
                    $types = [System.Collections.Generic.List[string]]::new()
                    while ($true) {
                        $typeName = Next-Token
                        if ($typeName -cnotmatch '^[A-Za-z_][A-Za-z_0-9\\]*$') {
                            throw "ALL PHP: Expected class name in catch, got '$typeName'"
                        }
                        [void]$types.Add($typeName)
                        if ((Peek-Token) -cne '|') { break }
                        [void](Next-Token)
                    }
                    $varName = $null
                    if ((Peek-Token) -cmatch '^\$[A-Za-z_][A-Za-z_0-9]*$') {
                        $varName = (Next-Token).Substring(1)
                    }
                    Expect-Token ')'
                    if ((Peek-Token) -cne '{') { throw "ALL PHP: Expected '{', got '$(Peek-Token)'" }
                    $handler = Read-Statement
                    [void]$catches.Add([pscustomobject]@{
                        Types=$types.ToArray(); Var=$varName; Body=$handler
                    })
                }
                $finallyBody = $null
                if ((Peek-Token) -eq 'finally') {
                    [void](Next-Token)
                    if ((Peek-Token) -cne '{') { throw "ALL PHP: Expected '{', got '$(Peek-Token)'" }
                    $finallyBody = Read-Statement
                }
                if ($catches.Count -eq 0 -and $null -eq $finallyBody) {
                    throw 'ALL PHP: Cannot use try without catch or finally'
                }
                return [pscustomobject]@{
                    Kind='try'; Body=$body; Catches=$catches.ToArray(); Finally=$finallyBody
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
        function Read-PhpTypeAnnotation {
            $first = Peek-Token
            $prefix = ''
            if ($first -ceq '?') {
                [void](Next-Token)
                $prefix = '?'
                $first = Peek-Token
            }
            if ($first -cnotmatch '^[A-Za-z_][A-Za-z_0-9\\]*$') {
                throw 'ALL PHP: Expected type name'
            }
            $typeText = $prefix + (Next-Token)
            while ((Peek-Token) -in @('|','&')) {
                $separator = Peek-Token
                if ($separator -eq '&') {
                    # An ampersand before a variable is a by-reference parameter,
                    # not an intersection type separator.
                    if ($state.Pos + 1 -ge $state.Tokens.Count -or
                        $state.Tokens[$state.Pos + 1] -cnotmatch '^[A-Za-z_][A-Za-z_0-9\\]*$') {
                        break
                    }
                }
                [void](Next-Token)
                $part = Next-Token
                if ($part -cnotmatch '^[A-Za-z_][A-Za-z_0-9\\]*$') {
                    throw 'ALL PHP: Expected type name after union/intersection separator'
                }
                $typeText += $separator + $part
            }
            if ($typeText -cmatch '^\?mixed$' -or
                ($typeText -match '(?i)\bmixed\b' -and $typeText.Contains('|'))) {
                throw 'ALL PHP: mixed cannot be nullable or part of union'
            }
            if ($typeText -cmatch '^\?(?:void|never)$') {
                throw 'ALL PHP: void and never cannot be nullable'
            }
            return $typeText
        }
        function Read-Parameters([bool]$allowPromotion = $false) {
            Expect-Token '('
            $parameters = [System.Collections.Generic.List[object]]::new()
            $sawVariadic = $false
            if ((Peek-Token) -cne ')') {
                while ($true) {
                    if ($sawVariadic) { throw 'ALL PHP: Variadic parameter must be last' }
                    $visibility = ''
                    $promotedReadonly = $false
                    if ($allowPromotion) {
                        while ((Peek-Token) -in @('public','protected','private','readonly')) {
                            $modifier=Next-Token
                            if ($modifier -eq 'readonly') {
                                if ($promotedReadonly) { throw 'ALL PHP: Duplicate readonly parameter modifier' }
                                $promotedReadonly=$true
                            } elseif (-not [string]::IsNullOrEmpty($visibility)) {
                                throw 'ALL PHP: Duplicate promoted parameter visibility'
                            } else { $visibility=$modifier }
                        }
                        if ($promotedReadonly -and [string]::IsNullOrEmpty($visibility)) {
                            $visibility='public'
                        }
                    }
                    $typeName = ''
                    if ((Peek-Token) -ceq '?' -or
                        (Peek-Token) -cmatch '^[A-Za-z_][A-Za-z_0-9\\]*$') {
                        $typeName=Read-PhpTypeAnnotation
                        if ($typeName -in @('void','never')) {
                            throw 'ALL PHP: void and never are return-only types'
                        }
                    }
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
                    if (-not [string]::IsNullOrEmpty($visibility) -and
                        [string]::IsNullOrEmpty($typeName) -and $promotedReadonly) {
                        throw 'ALL PHP: Promoted readonly property must have a type'
                    }
                    if (-not [string]::IsNullOrEmpty($visibility) -and $variadic) {
                        throw 'ALL PHP: Promoted property cannot be variadic'
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
                        ByRef=$byRef; TypeName=$typeName
                        Promoted=(-not [string]::IsNullOrEmpty($visibility))
                        Visibility=$visibility; Readonly=$promotedReadonly
                    })
                    if ((Peek-Token) -cne ',') { break }
                    [void](Next-Token)
                    if ((Peek-Token) -ceq ')') { break }
                }
            }
            Expect-Token ')'
            return ,($parameters.ToArray())
        }
        function Read-Function([bool]$declarationOnly = $false, [bool]$allowPromotion = $false) {
            Expect-Token 'function'
            $returnByRef=$false
            if ((Peek-Token) -ceq '&') {
                [void](Next-Token)
                $returnByRef=$true
            }
            $name = Next-Token
            if ($name -cnotmatch '^[A-Za-z_][A-Za-z_0-9\\]*$') {
                throw 'ALL PHP: Expected function name'
            }
            $parameters = Read-Parameters $allowPromotion
            if ($name -ine '__construct') {
                foreach ($p in $parameters) {
                    if ($p.Promoted) { throw 'ALL PHP: Only constructor parameters may be promoted' }
                }
            }
            $returnType=''
            if ((Peek-Token) -ceq ':') {
                [void](Next-Token)
                $returnType=Read-PhpTypeAnnotation
            }
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
                ReturnByRef=$returnByRef; ReturnType=$returnType
            }
        }

        # Parse the entire program first, before emitting any output.
        $statements = [System.Collections.Generic.List[object]]::new()
        while ((Peek-Token) -cne '(EOF)') {
            [void]$statements.Add((Read-Statement))
        }

        # ---- PHP exceptions --------------------------------------------------------------------
        # Built-in Throwable hierarchy, written in PHP and parsed by this interpreter on first use.
        $phpPreludeBody = @"
    protected `$message = '';
    protected `$code = 0;
    protected `$file = '';
    protected `$line = 0;
    protected `$previous = null;
    protected `$__trace = '';
    public function __construct(`$message = null, `$code = null, `$previous = null) {
        if (`$message !== null) { `$this->message = `$message; }
        if (`$code !== null) { `$this->code = `$code; }
        `$this->previous = `$previous;
    }
    public function getMessage() { return `$this->message; }
    public function getCode() { return `$this->code; }
    public function getPrevious() { return `$this->previous; }
    public function getFile() { return `$this->file; }
    public function getLine() { return `$this->line; }
    public function getTraceAsString() { return `$this->__trace; }
    public function __toString() { return __all_throwable_string(`$this); }
"@
        $phpPreludeSource = "interface Stringable {}`ninterface Throwable extends Stringable {}`n" +
            "class Exception implements Throwable {`n$phpPreludeBody`n}`n" +
            "class Error implements Throwable {`n$phpPreludeBody`n}`n" + @"
class ErrorException extends Exception {}
class RuntimeException extends Exception {}
class LogicException extends Exception {}
class BadFunctionCallException extends LogicException {}
class BadMethodCallException extends BadFunctionCallException {}
class DomainException extends LogicException {}
class InvalidArgumentException extends LogicException {}
class LengthException extends LogicException {}
class OutOfRangeException extends LogicException {}
class OutOfBoundsException extends RuntimeException {}
class OverflowException extends RuntimeException {}
class RangeException extends RuntimeException {}
class UnderflowException extends RuntimeException {}
class UnexpectedValueException extends RuntimeException {}
class JsonException extends Exception {}
class TypeError extends Error {}
class ArgumentCountError extends TypeError {}
class ValueError extends Error {}
class ArithmeticError extends Error {}
class DivisionByZeroError extends ArithmeticError {}
class AssertionError extends Error {}
class UnhandledMatchError extends Error {}
"@
        $phpPreludeTriggers = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::OrdinalIgnoreCase)
        foreach ($word in @('try','catch','throw','Throwable','Stringable','Exception','Error','ErrorException',
            'RuntimeException','LogicException','BadFunctionCallException','BadMethodCallException',
            'DomainException','InvalidArgumentException','LengthException','OutOfRangeException',
            'OutOfBoundsException','OverflowException','RangeException','UnderflowException',
            'UnexpectedValueException','JsonException','TypeError','ArgumentCountError','ValueError',
            'ArithmeticError','DivisionByZeroError','AssertionError','UnhandledMatchError')) {
            [void]$phpPreludeTriggers.Add($word)
        }
        function Ensure-PhpPrelude {
            if ($state.PreludeLoaded) { return }
            $state.PreludeLoaded = $true
            if ($null -eq $script:ALLPhpPreludeAst) {
                $savedTokens = $state.Tokens
                $savedLines = $state.TokenLines
                $savedPos = $state.Pos
                try {
                    $state.Tokens = [System.Collections.Generic.List[string]]::new()
                    $state.TokenLines = [System.Collections.Generic.List[int]]::new()
                    $state.Pos = 0
                    ConvertTo-PhpTokens $phpPreludeSource $state.Tokens $state.TokenLines
                    $nodes = [System.Collections.Generic.List[object]]::new()
                    while ((Peek-Token) -cne '(EOF)') { [void]$nodes.Add((Read-Statement)) }
                    $script:ALLPhpPreludeAst = $nodes.ToArray()
                } finally {
                    $state.Tokens = $savedTokens
                    $state.TokenLines = $savedLines
                    $state.Pos = $savedPos
                }
            }
            $savedLine = $state.Line
            $savedSteps = $state.Steps
            foreach ($node in $script:ALLPhpPreludeAst) { Invoke-PhpStatement $node }
            $state.Line = $savedLine
            $state.Steps = $savedSteps
        }
        function Format-PhpTraceArgument($value) {
            if ($null -ne $value -and $value.PSObject.Properties['PhpType'] -and
                $value.PhpType -ceq 'named_argument') { $value = $value.Value }
            if (Is-PhpRefCell $value) { $value = $value.Value }
            if ($null -eq $value) { return 'NULL' }
            if ($value -is [bool]) { if ($value) { return 'true' }; return 'false' }
            if ($value -is [long]) { return $value.ToString([System.Globalization.CultureInfo]::InvariantCulture) }
            if ($value -is [double]) { return (Format-PhpFloat $value 0) }
            if ($value -is [string]) {
                if ($value.Length -gt 15) { return ("'" + $value.Substring(0, 15) + "...'") }
                return ("'" + $value + "'")
            }
            if (Is-PhpArray $value) { return 'Array' }
            if (Is-PhpObject $value) { return ('Object(' + $value.Class + ')') }
            return 'Object'
        }
        function Format-PhpStackTrace {
            $sb = [System.Text.StringBuilder]::new()
            $index = 0
            for ($i = $state.CallStack.Count - 1; $i -ge 0; $i--) {
                $frame = $state.CallStack[$i]
                $parts = [System.Collections.Generic.List[string]]::new()
                foreach ($item in $frame.Args) { [void]$parts.Add((Format-PhpTraceArgument $item)) }
                [void]$sb.Append('#' + $index + ' ' + $state.ScriptName + '(' + $frame.Line + '): ' +
                    $frame.Name + '(' + [string]::Join(', ', $parts.ToArray()) + ")`n")
                $index++
            }
            [void]$sb.Append('#' + $index + ' {main}')
            return $sb.ToString()
        }
        # Called for every freshly created object: Throwables remember where they were created.
        function Initialize-PhpThrowable($object) {
            $object.Props['file'] = $state.ScriptName
            $object.Props['line'] = [long]$state.Line
            $object.Props['__trace'] = Format-PhpStackTrace
        }
        function Get-PhpThrowableString($object) {
            $text = $object.Class + ': ' + (To-PhpText $object.Props['message']) + ' in ' +
                (To-PhpText $object.Props['file']) + ':' + (To-PhpText $object.Props['line']) +
                "`nStack trace:`n" + (To-PhpText $object.Props['__trace'])
            $previous = $object.Props['previous']
            if (Is-PhpObject $previous) { return ((Get-PhpThrowableString $previous) + "`n`nNext " + $text) }
            return $text
        }
        # A thrown PHP object travels inside a .NET exception. The message is what a caller that does
        # not understand PHP exceptions sees (and what the legacy regression fixtures match on).
        function Throw-PhpObject($object, [string]$legacyText = '') {
            if ($legacyText.Length -eq 0) {
                $legacyText = 'ALL PHP: Uncaught ' + $object.Class + ': ' + (To-PhpText $object.Props['message'])
            }
            $state.ThrownSeq++
            $id = [string]$state.ThrownSeq
            $state.ThrownObjects[$id] = $object
            $signal = [System.Exception]::new($legacyText)
            $signal.Data['PhpThrowableId'] = $id
            throw $signal
        }
        function Get-PhpThrown($errorRecord) {
            $ex = $errorRecord.Exception
            while ($null -ne $ex) {
                if ($ex.Data.Contains('PhpThrowableId')) {
                    $id = [string]$ex.Data['PhpThrowableId']
                    if ($state.ThrownObjects.ContainsKey($id)) { return $state.ThrownObjects[$id] }
                }
                $ex = $ex.InnerException
            }
            return $null
        }
        # Raise a built-in PHP error from inside the interpreter.
        function Throw-PhpError([string]$className, [string]$message, [string]$legacyText = '') {
            Ensure-PhpPrelude
            $object = Invoke-PhpExpr ([pscustomobject]@{
                Kind='new'; Name=$className
                Args=@([pscustomobject]@{ Kind='literal'; Value=$message })
            })
            Throw-PhpObject $object $legacyText
        }
        function Format-PhpMatchValue($value) {
            if (Is-PhpRefCell $value) { $value = $value.Value }
            if ($null -eq $value) { return 'NULL' }
            if ($value -is [bool]) { if ($value) { return 'true' }; return 'false' }
            if ($value -is [long]) { return $value.ToString([System.Globalization.CultureInfo]::InvariantCulture) }
            if ($value -is [double]) { return (Format-PhpFloat $value 0) }
            if ($value -is [string]) { return ("'" + $value.Replace('\', '\\').Replace("'", "\'") + "'") }
            if (Is-PhpObject $value) { return ('of type ' + $value.Class) }
            return 'of type array'
        }
        function New-PhpObjectId {
            $state.ObjectSeq++
            return $state.ObjectSeq
        }
        # Call a PHP callable value (closure, function name, [object, method], invokable object)
        # with already evaluated arguments.
        function Invoke-PhpValueCallable($callee, $values) {
            $values = @($values)
            if ($null -ne $callee -and $callee.PSObject.Properties['PhpType']) {
                if ($callee.PhpType -ceq 'closure') {
                    return (Invoke-PhpCallable $callee.Definition $values $callee.BoundThis '' $callee)
                }
                if ($callee.PhpType -ceq 'first_class_callable') {
                    if ($callee.Mode -eq 'function') {
                        if ($state.Functions.ContainsKey($callee.Name)) {
                            return (Invoke-PhpCallable $state.Functions[$callee.Name] $values $null)
                        }
                        return (Invoke-PhpFunction $callee.Name $values)
                    }
                    if ($callee.Mode -eq 'method') { return (Invoke-PhpMethod $callee.BoundThis $callee.Name $values) }
                    return (Invoke-PhpStaticMethod $callee.Class $callee.Name $values)
                }
            }
            if (Is-PhpObject $callee) {
                if ($null -eq (Find-OptionalPhpMethod $callee.Class '__invoke')) { throw 'ALL PHP: Object is not callable' }
                return (Invoke-PhpMethod $callee '__invoke' $values)
            }
            if (Is-PhpArray $callee) {
                $pair = @($callee.Items.Values)
                if ($pair.Count -eq 2 -and $pair[1] -is [string]) {
                    if (Is-PhpObject $pair[0]) { return (Invoke-PhpMethod $pair[0] $pair[1] $values) }
                    if ($pair[0] -is [string]) { return (Invoke-PhpStaticMethod $pair[0] $pair[1] $values) }
                }
                throw 'ALL PHP: Array is not a valid callable'
            }
            if ($callee -is [string]) {
                $split = $callee.IndexOf('::')
                if ($split -gt 0) {
                    return (Invoke-PhpStaticMethod $callee.Substring(0, $split) $callee.Substring($split + 2) $values)
                }
                if ($state.Functions.ContainsKey($callee)) {
                    return (Invoke-PhpCallable $state.Functions[$callee] $values $null)
                }
                return (Invoke-PhpFunction $callee $values)
            }
            throw 'ALL PHP: Value is not callable'
        }
        # Number of parameters a user callable declares, or -1 when unknown (builtins, methods).
        function Get-PhpCallableArity($callee) {
            if ($null -ne $callee -and $callee.PSObject.Properties['PhpType'] -and
                $callee.PhpType -ceq 'closure') { return @($callee.Definition.Params).Count }
            if ($callee -is [string] -and $state.Functions.ContainsKey($callee)) {
                return @($state.Functions[$callee].Params).Count
            }
            return -1
        }
        # Raise a PHP diagnostic (E_WARNING, E_NOTICE, E_DEPRECATED, E_USER_*).
        # A user error handler sees it first. Otherwise it is printed in the PHP CLI format, but only
        # when the adapter runs with -PhpDiagnostics; the default mode stays silent.
        function Write-PhpDiagnostic([long]$level, [string]$message) {
            if ($null -ne $state.ErrorHandler -and -not $state.InErrorHandler -and
                (($state.ErrorHandlerMask -band $level) -ne 0)) {
                $handlerArgs = @($level, $message, [string]$state.ScriptName, [long]$state.Line)
                $arity = Get-PhpCallableArity $state.ErrorHandler
                if ($arity -ge 0 -and $arity -lt 4) {
                    if ($arity -eq 0) { $handlerArgs = @() } else { $handlerArgs = @($handlerArgs[0..($arity - 1)]) }
                }
                $state.InErrorHandler = $true
                $handled = $null
                $savedLine = $state.Line
                try { $handled = Invoke-PhpValueCallable $state.ErrorHandler $handlerArgs }
                finally { $state.InErrorHandler = $false; $state.Line = $savedLine }
                if (-not ($handled -is [bool] -and -not $handled)) { return }
            }
            if (-not $PhpDiagnostics) { return }
            if ($state.SilenceDepth -gt 0) { return }
            if (($state.ErrorReporting -band $level) -eq 0) { return }
            $label = 'Warning'
            if ($level -eq 8 -or $level -eq 1024) { $label = 'Notice' }
            elseif ($level -eq 8192 -or $level -eq 16384) { $label = 'Deprecated' }
            elseif ($level -eq 256) { $label = 'Fatal error' }
            [Console]::Write("`n" + $label + ': ' + $message + ' in ' + $state.ScriptName + ' on line ' + $state.Line + "`n")
        }
        function Test-PhpObjectHasProp($object, [string]$name) {
            if ($object.Props -is [System.Collections.Specialized.OrderedDictionary]) {
                return $object.Props.Contains($name)
            }
            return $object.Props.ContainsKey($name)
        }
        # Instance properties in PHP's order: declared ones (ancestors first), then dynamic ones.
        function Get-PhpObjectDumpEntries($object) {
            $entries = [System.Collections.Generic.List[object]]::new()
            $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
            if ($object.Class -ne 'stdClass' -and $state.Classes.ContainsKey($object.Class)) {
                $chain = Get-PhpClassChain $object.Class
                for ($i = $chain.Count - 1; $i -ge 0; $i--) {
                    foreach ($prop in $chain[$i].Properties) {
                        if ($prop.Static) { continue }
                        if (-not $seen.Add([string]$prop.Name)) { continue }
                        $declared = Find-PhpProperty $object.Class $prop.Name $false
                        if ($null -eq $declared) { $declared = $prop }
                        $present = Test-PhpObjectHasProp $object $prop.Name
                        $suffix = ''
                        $plain = ''
                        if ($declared.Visibility -eq 'protected') { $suffix = ':protected'; $plain = ':protected' }
                        elseif ($declared.Visibility -eq 'private') {
                            $suffix = ':"' + $declared.Owner + '":private'
                            $plain = ':' + $declared.Owner + ':private'
                        }
                        [void]$entries.Add([pscustomobject]@{
                            Name=[string]$prop.Name; Suffix=$suffix; PlainSuffix=$plain; Present=$present
                            TypeName=[string]$declared.TypeName
                            Value=$(if ($present) { $object.Props[$prop.Name] } else { $null })
                        })
                    }
                }
            }
            foreach ($key in @($object.Props.Keys)) {
                if (-not $seen.Add([string]$key)) { continue }
                [void]$entries.Add([pscustomobject]@{
                    Name=[string]$key; Suffix=''; PlainSuffix=''; Present=$true; TypeName=''
                    Value=$object.Props[$key]
                })
            }
            return ,($entries.ToArray())
        }
        function Format-PhpPrintR($value, [int]$indent) {
            if (Is-PhpRefCell $value) { $value = $value.Value }
            $pad = ' ' * $indent
            if (Is-PhpArray $value) {
                $sb = [System.Text.StringBuilder]::new()
                [void]$sb.Append("Array`n" + $pad + "(`n")
                foreach ($key in @($value.Items.Keys)) {
                    [void]$sb.Append($pad + '    [' + ([string]$key).Substring(2) + '] => ' +
                        (Format-PhpPrintR $value.Items[$key] ($indent + 8)) + "`n")
                }
                [void]$sb.Append($pad + ")`n")
                return $sb.ToString()
            }
            if (Is-PhpObject $value) {
                foreach ($seenObject in $state.DumpStack) {
                    if ([object]::ReferenceEquals($seenObject, $value)) { return "*RECURSION*" }
                }
                [void]$state.DumpStack.Add($value)
                try {
                    $sb = [System.Text.StringBuilder]::new()
                    $isEnum = ($state.Classes.ContainsKey($value.Class) -and
                        $state.Classes[$value.Class].PSObject.Properties['Enum'] -and $state.Classes[$value.Class].Enum)
                    $kind = if ($isEnum) { ' Enum' } else { ' Object' }
                    [void]$sb.Append($value.Class + $kind + "`n" + $pad + "(`n")
                    foreach ($entry in (Get-PhpObjectDumpEntries $value)) {
                        if (-not $entry.Present) { continue }
                        [void]$sb.Append($pad + '    [' + $entry.Name + $entry.PlainSuffix + '] => ' +
                            (Format-PhpPrintR $entry.Value ($indent + 8)) + "`n")
                    }
                    [void]$sb.Append($pad + ")`n")
                    return $sb.ToString()
                } finally { $state.DumpStack.RemoveAt($state.DumpStack.Count - 1) }
            }
            return (To-PhpText $value)
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
            if ($name -ceq 'GLOBALS') {
                # Read-only snapshot of the global symbol table.
                $snapshot = New-PhpArray
                foreach ($globalName in @($state.Globals.Keys)) {
                    $globalValue = $state.Globals[$globalName]
                    if (Is-PhpRefCell $globalValue) { $globalValue = $globalValue.Value }
                    Set-PhpArrayItem $snapshot ([string]$globalName) $globalValue $false
                }
                return $snapshot
            }
            $slot=Get-PhpVariableSlot $name
            if (-not $slot.Store.ContainsKey($slot.Key)) {
                if ($state.GlobalBindings.Contains($name)) { return $null }
                if ($PhpDiagnostics -and $state.QuietDepth -eq 0) {
                    Write-PhpDiagnostic 2 ('Undefined variable $' + $name)
                    return $null
                }
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
                    # Writing through an undefined variable creates it; PHP does not warn here.
                    $state.QuietDepth++
                    try { $baseValue=Get-PhpVariableValue $baseName }
                    catch {
                        if ($_.Exception.Message -notlike 'ALL PHP: Undefined variable*') { throw }
                    }
                    finally { $state.QuietDepth-- }
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
                        if ($declared.Readonly -or -not [string]::IsNullOrEmpty([string]$declared.TypeName)) {
                            throw 'ALL PHP: Reference to typed/readonly property requires typed reference tracking'
                        }
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
                if (-not [string]::IsNullOrEmpty([string]$prop.TypeName)) {
                    throw 'ALL PHP: Reference to typed static property requires typed reference tracking'
                }
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
            if ($value -is [long]) {
                return $value.ToString([System.Globalization.CultureInfo]::InvariantCulture)
            }
            if ($value -is [double]) {
                if ([double]::IsNaN($value) -or [double]::IsInfinity($value)) {
                    throw 'ALL PHP: Inf and NaN cannot be JSON encoded'
                }
                return (Format-PhpFloat $value 0).Replace('E', 'e')
            }
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
                PhpType='object'; Id=(New-PhpObjectId); Class='stdClass'
                Props=[System.Collections.Specialized.OrderedDictionary]::new(
                    [System.StringComparer]::Ordinal)
            }
        }
        function Convert-JsonToPhp($value, [bool]$assoc, [int]$depth = 0) {
            if ($depth -ge 64) { throw 'ALL PHP: JSON nesting depth exceeded (64)' }
            if ($null -eq $value) { return $null }
            if ($value -is [bool] -or $value -is [string]) { return $value }
            if ($value -is [System.ValueType]) {
                # JSON integers become PHP int when they fit in 64 bits; everything else is float.
                if ($value -is [double] -or $value -is [single]) { return [double]$value }
                if ($value -is [decimal]) {
                    $scale = ([decimal]::GetBits($value)[3] -shr 16) -band 0xFF
                    if ($scale -eq 0 -and $value -ge $phpIntMinDec -and $value -le $phpIntMaxDec) {
                        return [long]$value
                    }
                    return [double]$value
                }
                if ($value -is [bigint]) {
                    if ($value -ge [bigint][long]::MinValue -and $value -le [bigint][long]::MaxValue) {
                        return [long]$value
                    }
                    return [double]$value
                }
                return [long]$value
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
        # ---- PHP number model: int = System.Int64, float = System.Double (IEEE-754) ----
        $phpIntMinDec = [decimal]::Parse('-9223372036854775808')
        $phpIntMaxDec = [decimal]::Parse('9223372036854775807')
        $phpTwo64 = [bigint]::Pow(2, 64)
        $phpTwo63 = [bigint]::Pow(2, 63)
        $phpNumericStringRx = [regex]::new(
            '^[ \t\n\r\v\f]*([+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?)[ \t\n\r\v\f]*$')
        $phpLeadingNumericRx = [regex]::new(
            '^[ \t\n\r\v\f]*([+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?)')
        function Is-PhpNum($value) { return ($value -is [long] -or $value -is [double]) }
        # Exact decimal expansion of a finite, non-zero double (sign ignored).
        function Get-PhpFloatParts([double]$d) {
            $bits = [BitConverter]::DoubleToInt64Bits([Math]::Abs($d))
            $exp = [int](($bits -shr 52) -band 0x7FF)
            $frac = $bits -band 0xFFFFFFFFFFFFF
            if ($exp -eq 0) { $m = [bigint]$frac; $e = -1074 }
            else { $m = [bigint]($frac -bor 0x10000000000000); $e = $exp - 1075 }
            if ($e -ge 0) { $unit = [bigint]::Pow(2, $e); $scale = 0 }
            else { $unit = [bigint]::Pow(5, -$e); $scale = -$e }
            $n = $m * $unit
            $digits = $n.ToString()
            return [pscustomobject]@{
                Digits=$digits; Point=($digits.Length - $scale); N=$n; Scale=$scale
                Unit=$unit; Even=$m.IsEven; Boundary=($frac -eq 0 -and $exp -gt 1)
            }
        }
        # Round a digit string to $count significant digits (round-half-even on the exact value).
        function Round-PhpDigits([string]$digits, [int]$point, [int]$count) {
            if ($digits.Length -gt $count) {
                $head = $digits.Substring(0, $count)
                $rest = $digits.Substring($count)
                $first = [int]$rest[0] - 48
                $up = $false
                if ($first -gt 5) { $up = $true }
                elseif ($first -eq 5) {
                    if ($rest.Substring(1).Trim([char]'0').Length -gt 0) { $up = $true }
                    else { $up = ((([int]$head[$count - 1] - 48) % 2) -eq 1) }
                }
                if ($up) {
                    $chars = $head.ToCharArray()
                    $i = $count - 1
                    while ($i -ge 0) {
                        if ($chars[$i] -eq [char]'9') { $chars[$i] = [char]'0'; $i-- }
                        else { $chars[$i] = [char]([int]$chars[$i] + 1); break }
                    }
                    $head = [string]::new($chars)
                    if ($i -lt 0) { $head = '1' + $head; $point++ }
                }
                $digits = $head
            }
            $digits = $digits.TrimEnd([char]'0')
            if ($digits.Length -eq 0) { $digits = '0' }
            return [pscustomobject]@{ Digits=$digits; Point=$point }
        }
        # True when the decimal 0.<digits> x 10^point converts back to exactly the same double.
        function Test-PhpFloatRoundTrip($parts, [string]$digits, [int]$point) {
            $k = $point - $digits.Length + $parts.Scale
            $c = [bigint]::Parse($digits)
            $n = $parts.N
            $unit = $parts.Unit
            if ($k -ge 0) { $c = $c * [bigint]::Pow(10, $k) }
            else { $scaleUp = [bigint]::Pow(10, -$k); $n = $n * $scaleUp; $unit = $unit * $scaleUp }
            $diff = [bigint]::Abs($c - $n)
            $factor = 2
            if ($parts.Boundary -and $c -lt $n) { $factor = 4 }
            $lhs = $diff * $factor
            if ($lhs -lt $unit) { return $true }
            return ($lhs -eq $unit -and $parts.Even)
        }
        # $precision 14 = PHP "precision" ini default (echo, string conversion).
        # $precision 0  = shortest round-trip form (serialize_precision=-1: var_dump, json_encode).
        function Format-PhpFloat([double]$d, [int]$precision) {
            if ([double]::IsNaN($d)) { return 'NAN' }
            if ([double]::IsPositiveInfinity($d)) { return 'INF' }
            if ([double]::IsNegativeInfinity($d)) { return '-INF' }
            $sign = if ([BitConverter]::DoubleToInt64Bits($d) -lt 0) { '-' } else { '' }
            if ($d -eq 0) { return ($sign + '0') }
            $parts = Get-PhpFloatParts $d
            if ($precision -gt 0) {
                $limit = $precision
                $r = Round-PhpDigits $parts.Digits $parts.Point $precision
            } else {
                $limit = 17
                $lo = 1
                $hi = 17
                $r = Round-PhpDigits $parts.Digits $parts.Point 17
                while ($lo -lt $hi) {
                    $mid = [int][Math]::Floor(($lo + $hi) / 2)
                    $t = Round-PhpDigits $parts.Digits $parts.Point $mid
                    if (Test-PhpFloatRoundTrip $parts $t.Digits $t.Point) { $hi = $mid; $r = $t }
                    else { $lo = $mid + 1 }
                }
            }
            $dg = $r.Digits
            $pt = $r.Point
            if ($pt -lt -3 -or $pt -gt $limit) {
                $e = $pt - 1
                $mant = $dg.Substring(0, 1) + '.'
                if ($dg.Length -gt 1) { $mant += $dg.Substring(1) } else { $mant += '0' }
                if ($e -lt 0) { return ($sign + $mant + 'E-' + [string](-$e)) }
                return ($sign + $mant + 'E+' + [string]$e)
            }
            if ($pt -le 0) { return ($sign + '0.' + ('0' * (-$pt)) + $dg) }
            if ($pt -ge $dg.Length) { return ($sign + $dg + ('0' * ($pt - $dg.Length))) }
            return ($sign + $dg.Substring(0, $pt) + '.' + $dg.Substring($pt))
        }
        # Numeric string -> int/float, or $null when the string is not numeric.
        function ConvertFrom-PhpNumericString([string]$text, [bool]$leadingOnly) {
            $m = if ($leadingOnly) { $phpLeadingNumericRx.Match($text) } else { $phpNumericStringRx.Match($text) }
            if (-not $m.Success) { return $null }
            $body = $m.Groups[1].Value
            $inv = [System.Globalization.CultureInfo]::InvariantCulture
            if ($body.IndexOfAny([char[]]'.eE') -lt 0) {
                $n = [long]0
                if ([long]::TryParse($body, [System.Globalization.NumberStyles]::AllowLeadingSign, $inv, [ref]$n)) {
                    return $n
                }
                return (ConvertTo-PhpDoubleFromBigInt (
                    [bigint]::Parse($body, [System.Globalization.NumberStyles]::AllowLeadingSign, $inv)))
            }
            try { return [double]::Parse($body, [System.Globalization.NumberStyles]::Float, $inv) }
            catch {
                if ($body.StartsWith('-')) { return [double]::NegativeInfinity }
                return [double]::PositiveInfinity
            }
        }
        # float -> int the way PHP does on 64-bit: truncate, wrap modulo 2^64, NAN/INF become 0.
        function To-PhpInt($value) {
            if ($value -is [long]) { return $value }
            if ($value -is [double]) {
                if ([double]::IsNaN($value) -or [double]::IsInfinity($value)) { return [long]0 }
                $t = [Math]::Truncate($value)
                if ($t -ge -9223372036854775808.0 -and $t -lt 9223372036854775808.0) { return [long]$t }
                $wrapped = [bigint]::Remainder([bigint]$t, $phpTwo64)
                if ($wrapped -ge $phpTwo63) { $wrapped = $wrapped - $phpTwo64 }
                elseif ($wrapped -lt -$phpTwo63) { $wrapped = $wrapped + $phpTwo64 }
                return [long]$wrapped
            }
            return (To-PhpInt (To-Number $value))
        }
        function Php-Add($a, $b) {
            if ($a -is [long] -and $b -is [long]) {
                $r = [System.Decimal]$a + [System.Decimal]$b
                if ($r -ge $phpIntMinDec -and $r -le $phpIntMaxDec) { return [long]$r }
            }
            return ([double]$a + [double]$b)
        }
        function Php-Sub($a, $b) {
            if ($a -is [long] -and $b -is [long]) {
                $r = [System.Decimal]$a - [System.Decimal]$b
                if ($r -ge $phpIntMinDec -and $r -le $phpIntMaxDec) { return [long]$r }
            }
            return ([double]$a - [double]$b)
        }
        function Php-Mul($a, $b) {
            if ($a -is [long] -and $b -is [long]) {
                $r = $null
                try { $r = [System.Decimal]$a * [System.Decimal]$b } catch { $r = $null }
                if ($null -ne $r -and $r -ge $phpIntMinDec -and $r -le $phpIntMaxDec) { return [long]$r }
            }
            return ([double]$a * [double]$b)
        }
        function Php-Neg($a) {
            if ($a -is [long]) {
                if ($a -eq [long]::MinValue) { return ([double]$a * -1.0) }
                return [long](-$a)
            }
            # Multiply so that negating 0.0 yields IEEE negative zero.
            return ([double]$a * -1.0)
        }
        function Php-Div($a, $b) {
            if ($b -eq 0) { Throw-PhpError 'DivisionByZeroError' 'Division by zero' 'ALL PHP: Division by zero' }
            if ($a -is [long] -and $b -is [long]) {
                if ($b -eq -1) { return (Php-Neg $a) }
                $rem = [long]0
                $quot = [Math]::DivRem([long]$a, [long]$b, [ref]$rem)
                if ($rem -eq 0) { return [long]$quot }
            }
            return ([double]$a / [double]$b)
        }
        function Php-Mod($a, $b) {
            $divisor = To-PhpInt $b
            if ($divisor -eq 0) { Throw-PhpError 'DivisionByZeroError' 'Modulo by zero' 'ALL PHP: Division by zero' }
            $dividend = To-PhpInt $a
            if ($divisor -eq -1) { return [long]0 }
            $rem = [long]0
            [void][Math]::DivRem([long]$dividend, [long]$divisor, [ref]$rem)
            return [long]$rem
        }
        function Php-Pow($a, $b) {
            if ($a -is [long] -and $b -is [long] -and $b -ge 0) {
                $result = [System.Decimal]1
                $base = [System.Decimal]$a
                $exp = $b
                $ok = $true
                try {
                    while ($exp -gt 0) {
                        if (($exp -band 1) -eq 1) { $result = $result * $base }
                        $exp = $exp -shr 1
                        if ($exp -gt 0) { $base = $base * $base }
                    }
                } catch { $ok = $false }
                if ($ok -and $result -ge $phpIntMinDec -and $result -le $phpIntMaxDec) { return [long]$result }
            }
            return [Math]::Pow([double]$a, [double]$b)
        }
        function Php-Shift($a, $b, [bool]$left) {
            $value = To-PhpInt $a
            $count = To-PhpInt $b
            if ($count -lt 0) {
                Throw-PhpError 'ArithmeticError' 'Bit shift by negative number' 'ALL PHP: Bit shift by negative number'
            }
            if ($count -ge 64) {
                if ($left -or $value -ge 0) { return [long]0 }
                return [long]-1
            }
            if ($left) { return [long]($value -shl [int]$count) }
            return [long]($value -shr [int]$count)
        }
        function Compare-PhpNumbers($a, $b) {
            if ($a -is [long] -and $b -is [long]) {
                if ($a -lt $b) { return -1 }
                if ($a -gt $b) { return 1 }
                return 0
            }
            $x = [double]$a
            $y = [double]$b
            if ($x -lt $y) { return -1 }
            if ($x -eq $y) { return 0 }
            return 1
        }
        function Test-PhpNan($value) {
            if (Is-PhpRefCell $value) { $value = $value.Value }
            return ($value -is [double] -and [double]::IsNaN($value))
        }
        # Explicit casts: (int) (float) (string) (bool).
        function Convert-PhpCast($value, [string]$type) {
            if (Is-PhpRefCell $value) { $value = $value.Value }
            switch ($type) {
                { $_ -in @('int', 'integer') } {
                    if ($null -eq $value) { return [long]0 }
                    if ($value -is [bool]) { if ($value) { return [long]1 }; return [long]0 }
                    if (Is-PhpNum $value) { return (To-PhpInt $value) }
                    if ($value -is [string]) {
                        $parsed = ConvertFrom-PhpNumericString $value $true
                        if ($null -eq $parsed) { return [long]0 }
                        if ($parsed -is [double] -and
                            $phpLeadingNumericRx.Match($value).Groups[1].Value.IndexOfAny([char[]]'.eE') -lt 0) {
                            # integer syntax too large for 64 bits saturates, like strtol()
                            if ($parsed -lt 0) { return [long]::MinValue }
                            return [long]::MaxValue
                        }
                        return (To-PhpInt $parsed)
                    }
                    if (Is-PhpArray $value) { if ($value.Items.Count -gt 0) { return [long]1 }; return [long]0 }
                    return [long]1
                }
                { $_ -in @('float', 'double') } {
                    if ($null -eq $value) { return [double]0 }
                    if ($value -is [bool]) { if ($value) { return [double]1 }; return [double]0 }
                    if (Is-PhpNum $value) { return [double]$value }
                    if ($value -is [string]) {
                        $parsed = ConvertFrom-PhpNumericString $value $true
                        if ($null -eq $parsed) { return [double]0 }
                        if ($parsed -eq 0 -and $value.TrimStart().StartsWith('-')) {
                            return ([double]0 * -1.0)
                        }
                        return [double]$parsed
                    }
                    if (Is-PhpArray $value) { if ($value.Items.Count -gt 0) { return [double]1 }; return [double]0 }
                    return [double]1
                }
                'string' { return (To-PhpText $value) }
                default { return [bool](Is-Truthy $value) }
            }
        }
        function Format-PhpVarDump($value, [string]$pad) {
            if (Is-PhpRefCell $value) { $value = $value.Value }
            if ($null -eq $value) { return ($pad + "NULL`n") }
            if ($value -is [bool]) {
                if ($value) { return ($pad + "bool(true)`n") }
                return ($pad + "bool(false)`n")
            }
            if ($value -is [long]) {
                return ($pad + 'int(' + $value.ToString([System.Globalization.CultureInfo]::InvariantCulture) + ")`n")
            }
            if ($value -is [double]) { return ($pad + 'float(' + (Format-PhpFloat $value 0) + ")`n") }
            if ($value -is [string]) {
                $length = [System.Text.Encoding]::UTF8.GetByteCount($value)
                return ($pad + 'string(' + $length + ') "' + $value + "`"`n")
            }
            if (Is-PhpArray $value) {
                $sb = [System.Text.StringBuilder]::new()
                [void]$sb.Append($pad + 'array(' + $value.Items.Count + ") {`n")
                foreach ($key in @($value.Items.Keys)) {
                    $name = [string]$key
                    if ($name.StartsWith('i:')) { [void]$sb.Append($pad + '  [' + $name.Substring(2) + "]=>`n") }
                    else { [void]$sb.Append($pad + '  ["' + $name.Substring(2) + "`"]=>`n") }
                    [void]$sb.Append((Format-PhpVarDump $value.Items[$key] ($pad + '  ')))
                }
                [void]$sb.Append($pad + "}`n")
                return $sb.ToString()
            }
            if (Is-PhpObject $value) {
                if ($state.Classes.ContainsKey($value.Class) -and
                    $state.Classes[$value.Class].PSObject.Properties['Enum'] -and
                    $state.Classes[$value.Class].Enum) {
                    return ($pad + 'enum(' + $value.Class + '::' + (To-PhpText $value.Props['name']) + ")`n")
                }
                foreach ($seenObject in $state.DumpStack) {
                    if ([object]::ReferenceEquals($seenObject, $value)) { return ($pad + "*RECURSION*`n") }
                }
                [void]$state.DumpStack.Add($value)
                try {
                    $entries = Get-PhpObjectDumpEntries $value
                    $count = 0
                    foreach ($entry in $entries) { if ($entry.Present) { $count++ } }
                    $id = 0
                    if ($value.PSObject.Properties['Id']) { $id = $value.Id }
                    $sb = [System.Text.StringBuilder]::new()
                    [void]$sb.Append($pad + 'object(' + $value.Class + ')#' + $id + ' (' + $count + ") {`n")
                    foreach ($entry in $entries) {
                        [void]$sb.Append($pad + '  ["' + $entry.Name + '"' + $entry.Suffix + "]=>`n")
                        if ($entry.Present) { [void]$sb.Append((Format-PhpVarDump $entry.Value ($pad + '  '))) }
                        else { [void]$sb.Append($pad + '  uninitialized(' + $entry.TypeName + ")`n") }
                    }
                    [void]$sb.Append($pad + "}`n")
                    return $sb.ToString()
                } finally { $state.DumpStack.RemoveAt($state.DumpStack.Count - 1) }
            }
            throw 'ALL PHP: var_dump() of this value type is not implemented'
        }
        function To-PhpText($value) {
            if (Is-PhpRefCell $value) { $value=$value.Value }
            if ($null -eq $value) { return '' }
            if ($value -is [bool]) {
                if ($value) { return '1' }
                return ''
            }
            if ($value -is [long]) {
                return $value.ToString([System.Globalization.CultureInfo]::InvariantCulture)
            }
            if ($value -is [double]) { return (Format-PhpFloat $value 14) }
            if (Is-PhpArray $value) { throw 'ALL PHP: Array to string conversion is not supported' }
            if (Is-PhpObject $value) {
                $magic=Find-OptionalPhpMethod $value.Class '__toString'
                if ($null -ne $magic) {
                    $converted=Invoke-PhpMethod $value '__toString' @()
                    if ($converted -is [string]) { return $converted }
                    if ((Is-PhpNum $converted) -or $converted -is [bool]) {
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
            if ($value -is [long] -or $value -is [double]) { return $value }
            if ($null -eq $value) { return [long]0 }
            if ($value -is [bool]) {
                if ($value) { return [long]1 }
                return [long]0
            }
            if ($value -is [string]) {
                $parsed = ConvertFrom-PhpNumericString $value $false
                if ($null -ne $parsed) { return $parsed }
            }
            throw 'ALL PHP: Unsupported numeric operand'
        }
        function Is-Truthy($value) {
            if (Is-PhpRefCell $value) { $value=$value.Value }
            if ($null -eq $value) { return $false }
            if ($value -is [bool]) { return $value }
            if ($value -is [long] -or $value -is [double]) { return ($value -ne 0) }
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
            if ($value -is [long]) { return "i:$value" }
            if ($value -is [double]) {
                $num = To-PhpInt $value
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
                if ($PhpDiagnostics -and $state.QuietDepth -eq 0) {
                    if ($keyString.StartsWith('i:')) { Write-PhpDiagnostic 2 ('Undefined array key ' + $keyString.Substring(2)) }
                    else { Write-PhpDiagnostic 2 ('Undefined array key "' + $keyString.Substring(2) + '"') }
                    return $null
                }
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
            if (Is-PhpRefCell $a) { $a=$a.Value }
            if (Is-PhpRefCell $b) { $b=$b.Value }
            if ($null -eq $a -and $null -eq $b) { return 0 }
            if ($a -is [bool] -or $b -is [bool] -or
                $null -eq $a -or $null -eq $b) {
                $av = [int][bool](Is-Truthy $a)
                $bv = [int][bool](Is-Truthy $b)
                return $av.CompareTo($bv)
            }
            $aNum = ($a -is [long] -or $a -is [double])
            $bNum = ($b -is [long] -or $b -is [double])
            if ($aNum -and $bNum) { return (Compare-PhpNumbers $a $b) }
            if ($a -is [string] -and $b -is [string]) {
                $x = ConvertFrom-PhpNumericString $a $false
                if ($null -ne $x) {
                    $y = ConvertFrom-PhpNumericString $b $false
                    if ($null -ne $y) { return (Compare-PhpNumbers $x $y) }
                }
                return [Math]::Sign([string]::CompareOrdinal($a, $b))
            }
            if (($aNum -and $b -is [string]) -or ($a -is [string] -and $bNum)) {
                if ($a -is [string]) {
                    $x = ConvertFrom-PhpNumericString $a $false
                    if ($null -ne $x) { return (Compare-PhpNumbers $x $b) }
                } else {
                    $y = ConvertFrom-PhpNumericString $b $false
                    if ($null -ne $y) { return (Compare-PhpNumbers $a $y) }
                }
                return [Math]::Sign([string]::CompareOrdinal((To-PhpText $a),(To-PhpText $b)))
            }
            throw 'ALL PHP: Comparison for these types is not supported'
        }
        function Test-PhpRelation($a, $b, [string]$op) {
            if ((Test-PhpNan $a) -or (Test-PhpNan $b)) { return $false }
            $c = Compare-Values $a $b
            switch ($op) {
                '<' { return ($c -lt 0) }
                '<=' { return ($c -le 0) }
                '>' { return ($c -gt 0) }
                default { return ($c -ge 0) }
            }
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
        function Test-PhpTypeAtom($value, [string]$type) {
            if (Is-PhpRefCell $value) { $value=$value.Value }
            switch ($type.ToLowerInvariant()) {
                'mixed' { return $true }
                'null' { return ($null -eq $value) }
                'true' { return ($value -is [bool] -and $value) }
                'false' { return ($value -is [bool] -and -not $value) }
                'bool' { return ($value -is [bool]) }
                'string' { return ($value -is [string]) }
                'int' {
                    return ($value -is [long])
                }
                'float' { return ($value -is [double]) }
                'array' { return (Is-PhpArray $value) }
                'object' { return (Is-PhpObject $value) }
                'iterable' { return (Is-PhpArray $value) }
                'callable' {
                    if ($value -is [string]) { return $state.Functions.ContainsKey($value) }
                    if ($null -eq $value) { return $false }
                    if ($value.PSObject.Properties['PhpType']) {
                        if ($value.PhpType -in @('closure','first_class_callable')) { return $true }
                    }
                    if (Is-PhpObject $value) {
                        return ($null -ne (Find-OptionalPhpMethod $value.Class '__invoke'))
                    }
                    return $false
                }
                'void' { return ($null -eq $value) }
                'never' { return $false }
                default {
                    if (-not (Is-PhpObject $value)) { return $false }
                    $className=$type
                    if ($type -in @('self','parent','static')) {
                        $className=Resolve-PhpClass $type
                    }
                    return (Test-PhpInstanceOf $value.Class $className)
                }
            }
        }
        function Convert-PhpTypedValue($value, [string]$typeName, [string]$location) {
            if ([string]::IsNullOrEmpty($typeName)) { return $value }
            if ($typeName.StartsWith('?')) {
                if ($null -eq $value) { return $null }
                $typeName=$typeName.Substring(1)
            }
            $union = $typeName.Split([char]'|')
            foreach ($variant in $union) {
                $parts=$variant.Split([char]'&')
                $all=$true
                foreach ($part in $parts) {
                    if (-not (Test-PhpTypeAtom $value $part)) { $all=$false; break }
                }
                if ($all) { return $value }
            }
            # An int is always accepted where float is allowed (and becomes a float).
            if ($value -is [long]) {
                foreach ($variant in $union) {
                    if ($variant -ieq 'float') { return [double]$value }
                }
            }
            # Weak-mode coercion into a union: PHP prefers int, then float, then string, then bool.
            if ($union.Count -gt 1 -and -not $typeName.Contains('&') -and $null -ne $value) {
                $hasInt = $false; $hasFloat = $false; $hasString = $false; $hasBool = $false
                foreach ($variant in $union) {
                    switch ($variant.ToLowerInvariant()) {
                        'int' { $hasInt = $true }
                        'float' { $hasFloat = $true }
                        'string' { $hasString = $true }
                        'bool' { $hasBool = $true }
                    }
                }
                if ($value -is [double]) {
                    if ($hasInt -and -not [double]::IsNaN($value) -and -not [double]::IsInfinity($value) -and
                        [Math]::Truncate($value) -eq $value -and
                        $value -ge -9223372036854775808.0 -and $value -lt 9223372036854775808.0) {
                        return (To-PhpInt $value)
                    }
                    if ($hasString) { return (To-PhpText $value) }
                    if ($hasBool) { return (Is-Truthy $value) }
                } elseif ($value -is [long]) {
                    if ($hasString) { return (To-PhpText $value) }
                    if ($hasBool) { return (Is-Truthy $value) }
                } elseif ($value -is [string]) {
                    $parsed = ConvertFrom-PhpNumericString $value $false
                    if ($parsed -is [long] -and $hasInt) { return $parsed }
                    if ($null -ne $parsed -and $hasFloat) { return [double]$parsed }
                    if ($parsed -is [double] -and $hasInt -and [Math]::Truncate($parsed) -eq $parsed -and
                        $parsed -ge -9223372036854775808.0 -and $parsed -lt 9223372036854775808.0) {
                        return (To-PhpInt $parsed)
                    }
                    if ($hasBool) { return (Is-Truthy $value) }
                } elseif ($value -is [bool]) {
                    if ($hasInt) { if ($value) { return [long]1 }; return [long]0 }
                    if ($hasFloat) { if ($value) { return [double]1 }; return [double]0 }
                    if ($hasString) { return (To-PhpText $value) }
                }
            }
            # Weak PHP scalar conversions for a single primitive annotation.
            if ($union.Count -eq 1 -and -not $typeName.Contains('&') -and
                $null -ne $value) {
                switch ($typeName.ToLowerInvariant()) {
                    'string' {
                        if ((Is-PhpNum $value) -or $value -is [bool]) {
                            return (To-PhpText $value)
                        }
                    }
                    'bool' {
                        if ((Is-PhpNum $value) -or $value -is [string]) {
                            return (Is-Truthy $value)
                        }
                    }
                    'int' {
                        if ($value -is [bool]) {
                            if ($value) { return [long]1 }
                            return [long]0
                        }
                        if ($value -is [double] -and -not [double]::IsNaN($value) -and
                            -not [double]::IsInfinity($value)) {
                            return (To-PhpInt $value)
                        }
                        if ($value -is [string]) {
                            $parsed = ConvertFrom-PhpNumericString $value $false
                            if ($null -ne $parsed) { return (To-PhpInt $parsed) }
                        }
                    }
                    'float' {
                        if ($value -is [bool]) {
                            if ($value) { return [double]1 }
                            return [double]0
                        }
                        if ($value -is [string]) {
                            $parsed = ConvertFrom-PhpNumericString $value $false
                            if ($null -ne $parsed) { return [double]$parsed }
                        }
                    }
                }
            }
            throw "ALL PHP: Type mismatch at $location (expected $typeName)"
        }
        function Assert-PhpPropertyDefault($value, [string]$typeName, [string]$propertyName) {
            if ([string]::IsNullOrEmpty($typeName)) { return }
            if ($typeName.StartsWith('?') -and $null -eq $value) { return }
            if ($typeName.StartsWith('?')) { $typeName=$typeName.Substring(1) }
            foreach ($variant in $typeName.Split([char]'|')) {
                $all=$true
                foreach ($part in $variant.Split([char]'&')) {
                    if (-not (Test-PhpTypeAtom $value $part)) { $all=$false; break }
                }
                if ($all) { return }
                if ($value -is [long] -and $variant -ieq 'float') { return }
            }
            throw "ALL PHP: Type mismatch at property $propertyName (expected $typeName)"
        }
        function Copy-PhpTraitMethod($method, [string]$newName, [string]$visibility) {
            if ([string]::IsNullOrEmpty($visibility)) { $visibility=$method.Visibility }
            return [pscustomobject]@{
                Kind='functiondef'; Name=$newName
                Params=$method.Params; Body=$method.Body; Expr=$method.Expr
                Visibility=$visibility; Static=$method.Static
                Owner=$method.Owner; Abstract=$method.Abstract; Final=$method.Final
                ReturnByRef=$method.ReturnByRef; ReturnType=$method.ReturnType
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
            # PHP rejects an implementation that drops & from a required
            # reference-returning method; adding & to a value method is allowed.
            if ([bool]$required.ReturnByRef -and -not [bool]$implementation.ReturnByRef) {
                throw "ALL PHP: Incompatible reference-returning method '$context'"
            }
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
            $store=$state.Classes[$prop.Owner].StaticValues
            if (-not $store.ContainsKey($node.Name)) {
                throw "ALL PHP: Typed static property '$($node.Name)' must not be accessed before initialization"
            }
            $result = $store[$node.Name]
            if (Is-PhpRefCell $result) { return $result.Value }
            return $result
        }
        function Set-PhpStaticProperty($node, $value) {
            $klass = Resolve-PhpClass ([string](Invoke-PhpExpr $node.Base))
            $prop = Find-PhpProperty $klass $node.Name $true
            if ($null -eq $prop) { throw "ALL PHP: Undefined static property '$($node.Name)'" }
            Assert-PhpVisibility $prop.Visibility $prop.Owner
            $store = $state.Classes[$prop.Owner].StaticValues
            $value=Convert-PhpTypedValue $value ([string]$prop.TypeName) ('property ' + $node.Name)
            if ($store.ContainsKey($node.Name) -and (Is-PhpRefCell $store[$node.Name])) {
                $store[$node.Name].Value = Copy-PhpValue $value
            } else { $store[$node.Name] = Copy-PhpValue $value }
        }
        function Resolve-PhpDynamicVariableName($node) {
            $value = Invoke-PhpExpr $node.NameExpr
            if ($null -eq $value) { return '' }
            if ($value -isnot [string] -and -not (Is-PhpNum $value) -and
                $value -isnot [bool]) {
                throw 'ALL PHP: Invalid dynamic variable name type'
            }
            $name=To-PhpText $value
            if ($name -eq 'this') {
                throw 'ALL PHP: Cannot access $this dynamically'
            }
            return $name
        }
        function Invoke-PhpPropertyHook($object, $declared, [string]$mode, $value=$null) {
            $hook=if ($mode -ceq 'get') { $declared.GetHook } else { $declared.SetHook }
            if ($null -eq $hook) { throw 'ALL PHP: Missing property hook' }
            $hookKey=([string]$object.GetHashCode() + ':' + [string]$declared.Name)
            if (-not $state.PropertyHookActive.Add($hookKey)) {
                throw 'ALL PHP: Recursive property hook invocation'
            }
            try {
                $parameters=@()
                if ($mode -ceq 'set') {
                    if ($null -ne $hook.Params -and $hook.Params.Count -eq 1) {
                        $parameters=@($hook.Params)
                    } else {
                        $parameters=@([pscustomobject]@{
                            Name='value'; Default=$null; TypeName=''; ByRef=$false
                            Variadic=$false; Promoted=$false
                        })
                    }
                }
                $hookDefinition=[pscustomobject]@{
                    Name=('__property_' + $mode + '_' + $declared.Name)
                    Abstract=$false; ReturnByRef=$false; ReturnType=''
                    Params=$parameters; Body=$hook.Body; Expr=$hook.Expr
                }
                $callArgs=if ($mode -ceq 'get') { @() } else { ,$value }
                $result=Invoke-PhpCallable $hookDefinition $callArgs $object $declared.Owner
                if ($mode -ceq 'get') {
                    return (Convert-PhpTypedValue $result ([string]$declared.TypeName) ('property ' + $declared.Name))
                }
                if ($hook.Arrow) {
                    # PHP expression-bodied setter writes the expression result
                    # into the backing storage. Within its own hook, access to
                    # this property bypasses the hook (same as PHP).
                    $target=[pscustomobject]@{
                        Kind='property'; Base=[pscustomobject]@{Kind='literal';Value=$object}
                        Name=$declared.Name; NullSafe=$false
                    }
                    Set-LValue $target $result '='
                }
                return $null
            } finally {
                [void]$state.PropertyHookActive.Remove($hookKey)
            }
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
                if ($null -ne $declared -and $declared.PSObject.Properties['GetHook'] -and
                    $null -ne $declared.GetHook -and
                    -not $state.PropertyHookActive.Contains(
                        ([string]$base.GetHashCode() + ':' + $node.Name))) {
                    return (Invoke-PhpPropertyHook $base $declared 'get')
                }
                if ($null -ne $declared -and $declared.PSObject.Properties['SetHook'] -and
                    $null -ne $declared.SetHook -and $null -eq $declared.GetHook -and
                    -not $declared.HookBacked -and
                    -not $state.PropertyHookActive.Contains(
                        ([string]$base.GetHashCode() + ':' + $node.Name))) {
                    throw "ALL PHP: write-only property '$($node.Name)'"
                }
                if (-not $present) {
                    if ($null -ne $declared -and
                        -not [string]::IsNullOrEmpty([string]$declared.TypeName)) {
                        throw "ALL PHP: Typed property '$($node.Name)' must not be accessed before initialization"
                    }
                    $magic=Find-OptionalPhpMethod $base.Class '__get'
                    if ($null -ne $magic) {
                        $guardKey=([string]$base.GetHashCode() + ':' + $node.Name)
                        if (-not $state.MagicGetActive.Add($guardKey)) {
                            throw 'ALL PHP: Recursive __get property access'
                        }
                        try { return (Invoke-PhpMethod $base '__get' @($node.Name)) }
                        finally { [void]$state.MagicGetActive.Remove($guardKey) }
                    }
                    if ($PhpDiagnostics -and $state.QuietDepth -eq 0) {
                        Write-PhpDiagnostic 2 ('Undefined property: ' + $base.Class + '::$' + $node.Name)
                        return $null
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
                $numeric = [long]0
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
                    '+=' { $value = Php-Add (To-Number $previous) (To-Number $value) }
                    '-=' { $value = Php-Sub (To-Number $previous) (To-Number $value) }
                    '.=' { $value = (To-PhpText $previous) + (To-PhpText $value) }
                    '*=' { $value = Php-Mul (To-Number $previous) (To-Number $value) }
                    '/=' { $value = Php-Div (To-Number $previous) (To-Number $value) }
                    '%=' { $value = Php-Mod (To-Number $previous) (To-Number $value) }
                    '&=' { $value = [long]((To-PhpInt $previous) -band (To-PhpInt $value)) }
                    '|=' { $value = [long]((To-PhpInt $previous) -bor (To-PhpInt $value)) }
                    '^=' { $value = [long]((To-PhpInt $previous) -bxor (To-PhpInt $value)) }
                    '<<=' { $value = Php-Shift $previous $value $true }
                    '>>=' { $value = Php-Shift $previous $value $false }
                    '**=' { $value = Php-Pow (To-Number $previous) (To-Number $value) }
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
                    # Writing through an undefined variable creates it; PHP does not warn here.
                    $state.QuietDepth++
                    try { $baseValue=Get-PhpVariableValue $baseName }
                    catch {
                        if ($_.Exception.Message -notlike 'ALL PHP: Undefined variable*') { throw }
                    }
                    finally { $state.QuietDepth-- }
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
                if ($null -ne $declared) {
                    if ($declared.PSObject.Properties['SetHook'] -and
                        $null -ne $declared.SetHook -and
                        -not $state.PropertyHookActive.Contains(
                            ([string]$base.GetHashCode() + ':' + $node.Name))) {
                        $value=Convert-PhpTypedValue $value ([string]$declared.TypeName) ('property ' + $node.Name)
                        [void](Invoke-PhpPropertyHook $base $declared 'set' $value)
                        return
                    }
                    if ($declared.PSObject.Properties['GetHook'] -and
                        $null -ne $declared.GetHook -and $null -eq $declared.SetHook -and
                        -not $declared.HookBacked -and
                        -not $state.PropertyHookActive.Contains(
                            ([string]$base.GetHashCode() + ':' + $node.Name))) {
                        throw "ALL PHP: get-only property '$($node.Name)'"
                    }
                    if ([bool]$declared.Readonly) {
                        if ($present) { throw "ALL PHP: Cannot modify readonly property '$($node.Name)'" }
                        if ($null -eq $state.ClassContext -or $state.ClassContext -ine $declared.Owner) {
                            throw "ALL PHP: Cannot initialize readonly property '$($node.Name)' outside its declaring class"
                        }
                    }
                    $value=Convert-PhpTypedValue $value ([string]$declared.TypeName) ('property ' + $node.Name)
                } elseif ($base.Class -ne 'stdClass' -and $state.Classes[$base.Class].Readonly) {
                    throw 'ALL PHP: Cannot create dynamic property on readonly class'
                }
                if ($present -and (Is-PhpRefCell $base.Props[$node.Name])) {
                    $base.Props[$node.Name].Value = Copy-PhpValue $value
                } else { $base.Props[$node.Name] = Copy-PhpValue $value }
                return
            }
            throw 'ALL PHP: Invalid assignment target'
        }
        function Invoke-PhpCallable($definition, $callArgs, $object, [string]$owner = '', $closure = $null, [bool]$referenceContext = $false) {
            if ($definition.Abstract) { throw 'ALL PHP: Cannot invoke an abstract method' }
            if ($state.CallDepth -ge 64) { throw 'ALL PHP: Call depth limit reached (64)' }
            $oldVars = $state.Vars
            $oldFlow = $state.Flow
            $oldGlobals = $state.GlobalBindings
            $oldStatics = $state.StaticBindings
            $oldCallable = $state.CurrentCallable
            $oldContext = $state.ClassContext
            $oldReturnByRef=$state.ReturnByRef
            $functionReturnsByRef=($definition.PSObject.Properties['ReturnByRef'] -and $definition.ReturnByRef)
            if ($referenceContext -and -not $functionReturnsByRef) {
                throw 'ALL PHP: Function does not return by reference'
            }
            $state.ReturnByRef=$functionReturnsByRef
            $state.Vars = [System.Collections.Generic.Dictionary[string,object]]::new(
                [System.StringComparer]::Ordinal)
            $state.Flow = @{ Returned=$false; ReturnedWithExpr=$false; Value=$null; RefCell=$null; LoopControl=$null; LoopDepth=0 }
            $state.GlobalBindings = [System.Collections.Generic.HashSet[string]]::new(
                [System.StringComparer]::Ordinal)
            $state.StaticBindings = [System.Collections.Generic.HashSet[string]]::new(
                [System.StringComparer]::Ordinal)
            $state.ClassContext = if ($owner.Length -gt 0) { $owner } else { $null }
            $state.CurrentCallable = if ($owner.Length -gt 0) { $owner + '::' + $definition.Name } else { $definition.Name }
            $state.CallDepth++
            $oldLine = $state.Line
            $oldQuiet = $state.QuietDepth
            $state.QuietDepth = 0
            $frameName = [string]$definition.Name
            if ($owner.Length -gt 0) {
                if ($null -ne $object) { $frameName = $owner + '->' + $definition.Name }
                else { $frameName = $owner + '::' + $definition.Name }
            }
            if ($frameName.Length -eq 0) { $frameName = '{closure}' }
            $frameArgs = @()
            if ($null -ne $callArgs) { $frameArgs = @($callArgs) }
            [void]$state.CallStack.Add([pscustomobject]@{ Name=$frameName; Line=$state.Line; Args=$frameArgs })
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
                # Enforce declared parameter types after resolving named/default/variadic
                # arguments and before entering the function body.
                foreach ($param in $definition.Params) {
                    if (-not $param.PSObject.Properties['TypeName'] -or
                        [string]::IsNullOrEmpty($param.TypeName)) { continue }
                    $name=[string]$param.Name
                    if ($param.Variadic) {
                        $argsArray=$state.Vars[$name]
                        foreach ($key in @($argsArray.Items.Keys)) {
                            $item=$argsArray.Items[$key]
                            $cell=$null
                            if (Is-PhpRefCell $item) { $cell=$item; $item=$item.Value }
                            $checked=Convert-PhpTypedValue $item $param.TypeName ('argument $' + $name)
                            if ($null -ne $cell) { $cell.Value=$checked }
                            else { $argsArray.Items[$key]=$checked }
                        }
                    } else {
                        $item=$state.Vars[$name]
                        $cell=$null
                        if (Is-PhpRefCell $item) { $cell=$item; $item=$item.Value }
                        $checked=Convert-PhpTypedValue $item $param.TypeName ('argument $' + $name)
                        if ($null -ne $cell) { $cell.Value=$checked }
                        else { $state.Vars[$name]=$checked }
                    }
                }
                if ($null -ne $object) {
                    $state.Vars['this'] = $object
                    if ($definition.Name -ieq '__construct') {
                        foreach ($parameter in $definition.Params) {
                            if (-not $parameter.Promoted) { continue }
                            $target=[pscustomobject]@{
                                Kind='property'
                                Base=[pscustomobject]@{ Kind='variable'; Name='this' }
                                Name=$parameter.Name; NullSafe=$false
                            }
                            if ($parameter.ByRef) {
                                throw 'ALL PHP: Promoted by-reference property needs typed reference tracking'
                            }
                            Set-LValue $target (Get-PhpVariableValue $parameter.Name) '='
                        }
                    }
                }
                $returnType=''
                if ($definition.PSObject.Properties['ReturnType']) {
                    $returnType=[string]$definition.ReturnType
                }
                if ($null -ne $definition.Expr) {
                    if ($state.ReturnByRef) {
                        $expr=$definition.Expr
                        if ($expr.Kind -in @('variable','dynamic_variable','index','property','static_property')) {
                            $cell=Get-PhpLValueCell $expr
                        } elseif ($expr.Kind -in @('call','method','static_method','invoke')) {
                            $cell=Invoke-PhpReferenceCall $expr
                        } else {
                            throw 'ALL PHP: Reference return requires a writable value'
                        }
                        $cell.Value=Convert-PhpTypedValue $cell.Value $returnType 'return value'
                        if ($referenceContext) { return $cell }
                        return $cell.Value
                    }
                    $result=Invoke-PhpExpr $definition.Expr
                    if ($returnType -eq 'void') {
                        throw 'ALL PHP: void function cannot return a value'
                    }
                    if ($returnType -eq 'never') {
                        throw 'ALL PHP: never function returned a value'
                    }
                    return (Convert-PhpTypedValue $result $returnType 'return value')
                }
                Invoke-PhpStatement $definition.Body
                if ($returnType -eq 'never') {
                    throw 'ALL PHP: never function returned'
                }
                if ($returnType -eq 'void' -and $state.Flow.ReturnedWithExpr) {
                    throw 'ALL PHP: void function cannot return a value'
                }
                if ($referenceContext) {
                    if (-not (Is-PhpRefCell $state.Flow.RefCell)) {
                        throw 'ALL PHP: Function did not return a reference'
                    }
                    $state.Flow.RefCell.Value=Convert-PhpTypedValue $state.Flow.RefCell.Value $returnType 'return value'
                    return $state.Flow.RefCell
                }
                return (Convert-PhpTypedValue $state.Flow.Value $returnType 'return value')
            } finally {
                $state.CallDepth--
                $state.Line = $oldLine
                $state.QuietDepth = $oldQuiet
                if ($state.CallStack.Count -gt 0) { $state.CallStack.RemoveAt($state.CallStack.Count - 1) }
                $state.Vars = $oldVars
                $state.Flow = $oldFlow
                $state.GlobalBindings = $oldGlobals
                $state.StaticBindings = $oldStatics
                $state.CurrentCallable = $oldCallable
                $state.ClassContext = $oldContext
                $state.ReturnByRef = $oldReturnByRef
            }
        }
        function KeyString-ToValue([string]$encoded) {
            if ($encoded.StartsWith('i:')) { return [long]$encoded.Substring(2) }
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
                    return [long]$state.JsonError
                }
                'json_last_error_msg' {
                    if ($callArgs.Count -ne 0) { throw 'ALL PHP: json_last_error_msg() expects no arguments' }
                    return $state.JsonErrorMessage
                }
                'count' {
                    if ($callArgs.Count -ne 1 -or -not (Is-PhpArray $callArgs[0])) {
                        throw 'ALL PHP: count() requires one array argument'
                    }
                    return [long]$callArgs[0].Items.Count
                }
                'strlen' {
                    if ($callArgs.Count -ne 1) { throw 'ALL PHP: strlen() requires one argument' }
                    return [long]([System.Text.Encoding]::UTF8.GetByteCount((To-PhpText $callArgs[0])))
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
                    $number = To-Number $callArgs[0]
                    if ($number -is [long]) {
                        if ($number -eq [long]::MinValue) { return (-[double]$number) }
                        return [long][Math]::Abs($number)
                    }
                    return [Math]::Abs([double]$number)
                }
                'array_sum' {
                    if ($callArgs.Count -ne 1 -or -not (Is-PhpArray $callArgs[0])) {
                        throw 'ALL PHP: array_sum() requires one array argument'
                    }
                    $sum = [long]0
                    foreach ($key in $callArgs[0].Items.Keys) {
                        $sum = Php-Add $sum (To-Number $callArgs[0].Items[$key])
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
                    return [long]$callArgs[0].Items.Count
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
                    return [long]$arr.Items.Count
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
                    return [long]$pos
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
                '__all_throwable_string' { return (Get-PhpThrowableString $callArgs[0]) }
                'print_r' {
                    if ($callArgs.Count -lt 1 -or $callArgs.Count -gt 2) { throw 'ALL PHP: print_r() requires one or two arguments' }
                    $printed = Format-PhpPrintR $callArgs[0] 0
                    if ($callArgs.Count -eq 2 -and (Is-Truthy $callArgs[1])) { return $printed }
                    [Console]::Write($printed)
                    return $true
                }
                'define' {
                    if ($callArgs.Count -ne 2) { throw 'ALL PHP: define() requires two arguments' }
                    $constName = To-PhpText $callArgs[0]
                    if ($state.Constants.ContainsKey($constName) -or $phpConstants.ContainsKey($constName)) {
                        Write-PhpDiagnostic 2 ('Constant ' + $constName + ' already defined, this will be an error in PHP 9')
                        return $false
                    }
                    $state.Constants[$constName] = Copy-PhpValue $callArgs[1]
                    return $true
                }
                'defined' {
                    if ($callArgs.Count -ne 1) { throw 'ALL PHP: defined() requires one argument' }
                    $constName = To-PhpText $callArgs[0]
                    return ($state.Constants.ContainsKey($constName) -or $phpConstants.ContainsKey($constName))
                }
                'constant' {
                    if ($callArgs.Count -ne 1) { throw 'ALL PHP: constant() requires one argument' }
                    $constName = To-PhpText $callArgs[0]
                    if ($state.Constants.ContainsKey($constName)) { return $state.Constants[$constName] }
                    if ($phpConstants.ContainsKey($constName)) { return $phpConstants[$constName] }
                    Throw-PhpError 'Error' ('Undefined constant "' + $constName + '"')
                }
                'error_reporting' {
                    $previous = $state.ErrorReporting
                    if ($callArgs.Count -ge 1 -and $null -ne $callArgs[0]) { $state.ErrorReporting = To-PhpInt (To-Number $callArgs[0]) }
                    return [long]$previous
                }
                'ini_set' {
                    if ($callArgs.Count -ne 2) { throw 'ALL PHP: ini_set() requires two arguments' }
                    $iniName = To-PhpText $callArgs[0]
                    $previous = $false
                    if ($state.Ini.ContainsKey($iniName)) { $previous = $state.Ini[$iniName] }
                    $state.Ini[$iniName] = To-PhpText $callArgs[1]
                    if ($iniName -ceq 'error_reporting') { $state.ErrorReporting = To-PhpInt (To-Number $callArgs[1]) }
                    return $previous
                }
                'ini_get' {
                    if ($callArgs.Count -ne 1) { throw 'ALL PHP: ini_get() requires one argument' }
                    $iniName = To-PhpText $callArgs[0]
                    if ($state.Ini.ContainsKey($iniName)) { return $state.Ini[$iniName] }
                    return $false
                }
                'set_error_handler' {
                    if ($callArgs.Count -lt 1 -or $callArgs.Count -gt 2) { throw 'ALL PHP: set_error_handler() requires one or two arguments' }
                    $previous = $state.ErrorHandler
                    [void]$state.ErrorHandlerStack.Add(@($state.ErrorHandler, $state.ErrorHandlerMask))
                    $state.ErrorHandler = $callArgs[0]
                    $state.ErrorHandlerMask = [long]-1
                    if ($callArgs.Count -eq 2) { $state.ErrorHandlerMask = To-PhpInt (To-Number $callArgs[1]) }
                    return $previous
                }
                'restore_error_handler' {
                    if ($state.ErrorHandlerStack.Count -gt 0) {
                        $entry = $state.ErrorHandlerStack[$state.ErrorHandlerStack.Count - 1]
                        $state.ErrorHandlerStack.RemoveAt($state.ErrorHandlerStack.Count - 1)
                        $state.ErrorHandler = $entry[0]
                        $state.ErrorHandlerMask = $entry[1]
                    }
                    return $true
                }
                'set_exception_handler' {
                    if ($callArgs.Count -ne 1) { throw 'ALL PHP: set_exception_handler() requires one argument' }
                    $previous = $state.ExceptionHandler
                    [void]$state.ExceptionHandlerStack.Add($state.ExceptionHandler)
                    $state.ExceptionHandler = $callArgs[0]
                    return $previous
                }
                'restore_exception_handler' {
                    if ($state.ExceptionHandlerStack.Count -gt 0) {
                        $state.ExceptionHandler = $state.ExceptionHandlerStack[$state.ExceptionHandlerStack.Count - 1]
                        $state.ExceptionHandlerStack.RemoveAt($state.ExceptionHandlerStack.Count - 1)
                    }
                    return $true
                }
                { $_ -in @('trigger_error', 'user_error') } {
                    if ($callArgs.Count -lt 1 -or $callArgs.Count -gt 2) { throw "ALL PHP: $name() requires one or two arguments" }
                    $level = [long]1024
                    if ($callArgs.Count -eq 2) { $level = To-PhpInt (To-Number $callArgs[1]) }
                    if ($level -notin @(256, 512, 1024, 16384)) {
                        Throw-PhpError 'ValueError' 'trigger_error(): Argument #2 ($error_level) must be one of E_USER_ERROR, E_USER_WARNING, E_USER_NOTICE, or E_USER_DEPRECATED'
                    }
                    Write-PhpDiagnostic $level (To-PhpText $callArgs[0])
                    return $true
                }
                'str_repeat' {
                    if ($callArgs.Count -ne 2) { throw 'ALL PHP: str_repeat() requires two arguments' }
                    $times = To-PhpInt (To-Number $callArgs[1])
                    if ($times -lt 0) {
                        Throw-PhpError 'ValueError' 'str_repeat(): Argument #2 ($times) must be greater than or equal to 0'
                    }
                    return ((To-PhpText $callArgs[0]) * [int]$times)
                }
                'function_exists' {
                    if ($callArgs.Count -ne 1) { throw 'ALL PHP: function_exists() requires one argument' }
                    return $state.Functions.ContainsKey((To-PhpText $callArgs[0]))
                }
                'call_user_func' {
                    if ($callArgs.Count -lt 1) { throw 'ALL PHP: call_user_func() requires a callable' }
                    $rest = @()
                    if ($callArgs.Count -gt 1) { $rest = @($callArgs[1..($callArgs.Count - 1)]) }
                    return (Invoke-PhpValueCallable $callArgs[0] $rest)
                }
                'call_user_func_array' {
                    if ($callArgs.Count -ne 2 -or -not (Is-PhpArray $callArgs[1])) {
                        throw 'ALL PHP: call_user_func_array() requires a callable and an array'
                    }
                    return (Invoke-PhpValueCallable $callArgs[0] @($callArgs[1].Items.Values))
                }
                'get_class' {
                    if ($callArgs.Count -ne 1 -or -not (Is-PhpObject $callArgs[0])) {
                        throw 'ALL PHP: get_class() requires one object argument'
                    }
                    return [string]$callArgs[0].Class
                }
                'var_dump' {
                    if ($callArgs.Count -lt 1) { throw 'ALL PHP: var_dump() requires at least one argument' }
                    foreach ($item in $callArgs) { [Console]::Write((Format-PhpVarDump $item '')) }
                    return $null
                }
                'gettype' {
                    if ($callArgs.Count -ne 1) { throw 'ALL PHP: gettype() requires one argument' }
                    $item = $callArgs[0]
                    if ($null -eq $item) { return 'NULL' }
                    if ($item -is [bool]) { return 'boolean' }
                    if ($item -is [long]) { return 'integer' }
                    if ($item -is [double]) { return 'double' }
                    if ($item -is [string]) { return 'string' }
                    if (Is-PhpArray $item) { return 'array' }
                    return 'object'
                }
                { $_ -in @('is_int', 'is_integer', 'is_long') } {
                    if ($callArgs.Count -ne 1) { throw "ALL PHP: $name() requires one argument" }
                    return ($callArgs[0] -is [long])
                }
                { $_ -in @('is_float', 'is_double') } {
                    if ($callArgs.Count -ne 1) { throw "ALL PHP: $name() requires one argument" }
                    return ($callArgs[0] -is [double])
                }
                'is_null' {
                    if ($callArgs.Count -ne 1) { throw 'ALL PHP: is_null() requires one argument' }
                    return ($null -eq $callArgs[0])
                }
                'is_numeric' {
                    if ($callArgs.Count -ne 1) { throw 'ALL PHP: is_numeric() requires one argument' }
                    if (Is-PhpNum $callArgs[0]) { return $true }
                    if ($callArgs[0] -is [string]) {
                        return ($null -ne (ConvertFrom-PhpNumericString $callArgs[0] $false))
                    }
                    return $false
                }
                'intval' {
                    if ($callArgs.Count -ne 1) { throw 'ALL PHP: intval() supports one argument; base is not implemented' }
                    return (Convert-PhpCast $callArgs[0] 'int')
                }
                { $_ -in @('floatval', 'doubleval') } {
                    if ($callArgs.Count -ne 1) { throw "ALL PHP: $name() requires one argument" }
                    return (Convert-PhpCast $callArgs[0] 'float')
                }
                'boolval' {
                    if ($callArgs.Count -ne 1) { throw 'ALL PHP: boolval() requires one argument' }
                    return [bool](Is-Truthy $callArgs[0])
                }
                'intdiv' {
                    if ($callArgs.Count -ne 2) { throw 'ALL PHP: intdiv() requires two arguments' }
                    $dividend = To-PhpInt (To-Number $callArgs[0])
                    $divisor = To-PhpInt (To-Number $callArgs[1])
                    if ($divisor -eq 0) {
                        Throw-PhpError 'DivisionByZeroError' 'Division by zero' 'ALL PHP: Division by zero'
                    }
                    if ($dividend -eq [long]::MinValue -and $divisor -eq -1) {
                        Throw-PhpError 'ArithmeticError' 'Division of PHP_INT_MIN by -1 is not an integer' 'ALL PHP: ArithmeticError: Division of PHP_INT_MIN by -1 is not an integer'
                    }
                    $rem = [long]0
                    return [long][Math]::DivRem([long]$dividend, [long]$divisor, [ref]$rem)
                }
                'fdiv' {
                    if ($callArgs.Count -ne 2) { throw 'ALL PHP: fdiv() requires two arguments' }
                    return ([double](To-Number $callArgs[0]) / [double](To-Number $callArgs[1]))
                }
                'pow' {
                    if ($callArgs.Count -ne 2) { throw 'ALL PHP: pow() requires two arguments' }
                    return (Php-Pow (To-Number $callArgs[0]) (To-Number $callArgs[1]))
                }
                'sqrt' {
                    if ($callArgs.Count -ne 1) { throw 'ALL PHP: sqrt() requires one argument' }
                    return [Math]::Sqrt([double](To-Number $callArgs[0]))
                }
                'floor' {
                    if ($callArgs.Count -ne 1) { throw 'ALL PHP: floor() requires one argument' }
                    return [Math]::Floor([double](To-Number $callArgs[0]))
                }
                'ceil' {
                    if ($callArgs.Count -ne 1) { throw 'ALL PHP: ceil() requires one argument' }
                    return [Math]::Ceiling([double](To-Number $callArgs[0]))
                }
                'is_nan' {
                    if ($callArgs.Count -ne 1) { throw 'ALL PHP: is_nan() requires one argument' }
                    return [double]::IsNaN([double](To-Number $callArgs[0]))
                }
                'is_infinite' {
                    if ($callArgs.Count -ne 1) { throw 'ALL PHP: is_infinite() requires one argument' }
                    return [double]::IsInfinity([double](To-Number $callArgs[0]))
                }
                'is_finite' {
                    if ($callArgs.Count -ne 1) { throw 'ALL PHP: is_finite() requires one argument' }
                    $number = [double](To-Number $callArgs[0])
                    return (-not [double]::IsNaN($number) -and -not [double]::IsInfinity($number))
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
        function Resolve-PhpFunctionNodeName($node) {
            if (-not $node.PSObject.Properties['Fallback'] -or $null -eq $node.Fallback) {
                if ($state.Functions.ContainsKey($node.Name) -or $phpBuiltinNames.Contains($node.Name)) { return $node.Name }
                Throw-PhpError 'Error' ("Call to undefined function " + $node.Name + '()')
            }
            if ($null -ne $node.ResolvedName) { return $node.ResolvedName }
            # A call site's first successful namespace/global binding is retained, like PHP's
            # runtime cache. Conditional/nested declarations are not installed during parsing.
            if ($state.Functions.ContainsKey($node.Name)) { $node.ResolvedName = $node.Name }
            elseif ($state.Functions.ContainsKey($node.Fallback) -or $phpBuiltinNames.Contains($node.Fallback)) {
                $node.ResolvedName = $node.Fallback
            } else {
                # A failed lookup must remain unresolved: a later conditional declaration can
                # install the function before this same expression is reached again.
                Throw-PhpError 'Error' ("Call to undefined function " + $node.Name + '()')
            }
            return $node.ResolvedName
        }
        function Resolve-PhpConstantNodeName($node) {
            if (-not $node.PSObject.Properties['Fallback'] -or $null -eq $node.Fallback) { return $node.Name }
            if ($null -ne $node.ResolvedName) { return $node.ResolvedName }
            if ($state.Constants.ContainsKey($node.Name) -or $phpConstants.ContainsKey($node.Name)) {
                $node.ResolvedName = $node.Name
            } elseif ($state.Constants.ContainsKey($node.Fallback) -or $phpConstants.ContainsKey($node.Fallback)) {
                $node.ResolvedName = $node.Fallback
            } else { return $node.Name }
            return $node.ResolvedName
        }
        function Invoke-PhpReferenceCall($node) {
            # A function declared with & returns the same cell as its lvalue.
            # Ordinary function calls continue to return the dereferenced value.
            if ($node.Kind -eq 'call') {
                $callName = Resolve-PhpFunctionNodeName $node
                if (-not $state.Functions.ContainsKey($callName)) {
                    throw 'ALL PHP: Reference return requires a declared function'
                }
                $def=$state.Functions[$callName]
                $args=Evaluate-PhpUserArguments $node.Args $def
                return (Invoke-PhpCallable $def $args $null '' $null $true)
            }
            if ($node.Kind -eq 'method') {
                $object=Invoke-PhpExpr $node.Base
                if (-not (Is-PhpObject $object)) { throw 'ALL PHP: Reference method requires object' }
                $def=Find-PhpMethod $object.Class $node.Name
                Assert-PhpVisibility $def.Visibility $def.Owner
                $args=Evaluate-PhpUserArguments $node.Args $def
                $receiver=if ($def.Static) { $null } else { $object }
                return (Invoke-PhpCallable $def $args $receiver $def.Owner $null $true)
            }
            if ($node.Kind -eq 'static_method') {
                $klass=Resolve-PhpClass ([string](Invoke-PhpExpr $node.Base))
                $def=Find-PhpMethod $klass $node.Name
                Assert-PhpVisibility $def.Visibility $def.Owner
                $args=Evaluate-PhpUserArguments $node.Args $def
                $receiver=$null
                if (-not $def.Static -and $state.Vars.ContainsKey('this')) {
                    $receiver=Get-PhpVariableValue 'this'
                }
                if (-not $def.Static -and -not (Is-PhpObject $receiver)) {
                    throw 'ALL PHP: Non-static method cannot be called statically'
                }
                return (Invoke-PhpCallable $def $args $receiver $def.Owner $null $true)
            }
            if ($node.Kind -eq 'invoke') {
                $callee=Invoke-PhpExpr $node.Callee
                if ($null -ne $callee -and $callee.PSObject.Properties['PhpType'] -and
                    $callee.PhpType -ceq 'closure') {
                    $args=Evaluate-PhpUserArguments $node.Args $callee.Definition
                    return (Invoke-PhpCallable $callee.Definition $args $callee.BoundThis '' $callee $true)
                }
                if ($callee -is [string] -and $state.Functions.ContainsKey($callee)) {
                    $def=$state.Functions[$callee]
                    $args=Evaluate-PhpUserArguments $node.Args $def
                    return (Invoke-PhpCallable $def $args $null '' $null $true)
                }
            }
            throw 'ALL PHP: Reference return requires a reference-returning callable'
        }
        function Invoke-PhpExpr($node) {
            switch ($node.Kind) {
                'literal' { return $node.Value }
                'silence' {
                    $state.SilenceDepth++
                    try { return (Invoke-PhpExpr $node.Arg) }
                    finally { $state.SilenceDepth-- }
                }
                'class_name' {
                    $constantName = Resolve-PhpConstantNodeName $node
                    if ($state.Constants.ContainsKey($constantName)) { return $state.Constants[$constantName] }
                    if ($phpConstants.ContainsKey($constantName)) { return $phpConstants[$constantName] }
                    return $node.Name
                }
                'cast' { return (Convert-PhpCast (Invoke-PhpExpr $node.Arg) $node.Type) }
                'throw' {
                    Ensure-PhpPrelude
                    $thrownValue = Invoke-PhpExpr $node.Arg
                    if (-not (Is-PhpObject $thrownValue)) { Throw-PhpError 'Error' 'Can only throw objects' }
                    if (-not (Test-PhpInstanceOf $thrownValue.Class 'Throwable')) {
                        Throw-PhpError 'Error' 'Cannot throw objects that do not implement Throwable'
                    }
                    Throw-PhpObject $thrownValue
                }
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
                        PhpType='closure'; Id=(New-PhpObjectId); Definition=$node; Captures=$cap
                        BoundThis=$bound; ClassContext=$state.ClassContext
                    }
                }
                'first_class_function' {
                    # Defer builtin argument evaluation until the closure is invoked.
                    return [pscustomobject]@{
                        PhpType='first_class_callable'; Id=(New-PhpObjectId); Mode='function'; Name=(Resolve-PhpFunctionNodeName $node)
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
                        PhpType='first_class_callable'; Id=(New-PhpObjectId); Mode='method'
                        Name=$node.Name; BoundThis=$object
                    }
                }
                'first_class_static' {
                    $klass=Resolve-PhpClass ([string](Invoke-PhpExpr $node.Base))
                    if ($null -eq (Find-OptionalPhpMethod $klass $node.Name)) {
                        throw "ALL PHP: Undefined static method '$($node.Name)'"
                    }
                    return [pscustomobject]@{
                        PhpType='first_class_callable'; Id=(New-PhpObjectId); Mode='static'
                        Name=$node.Name; Class=$klass
                    }
                }
                'first_class_invoke' {
                    $callable=Invoke-PhpExpr $node.Callee
                    if ($null -ne $callable -and $callable -is [string]) {
                        return [pscustomobject]@{
                            PhpType='first_class_callable'; Id=(New-PhpObjectId); Mode='function'; Name=$callable
                        }
                    }
                    if ($null -ne $callable -and $callable.PSObject.Properties['PhpType'] -and
                        $callable.PhpType -eq 'closure') { return $callable }
                    if (Is-PhpObject $callable) {
                        if ($null -eq (Find-OptionalPhpMethod $callable.Class '__invoke')) {
                            throw 'ALL PHP: Value is not callable'
                        }
                        return [pscustomobject]@{
                            PhpType='first_class_callable'; Id=(New-PhpObjectId); Mode='method'
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
                                if ($enum.BackingType -eq 'int' -and $needle -is [long] -and
                                    $item.Props['value'] -eq $needle) { return $item }
                            }
                            if ($node.Name -ceq 'tryFrom') { return $null }
                            $shown = if ($needle -is [string]) { '"' + $needle + '"' } else { To-PhpText $needle }
                            Throw-PhpError 'ValueError' ($shown + ' is not a valid backing value for enum ' + $enum.Name) 'ALL PHP: ValueError: invalid backing value for enum'
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
                        PhpType='object'; Id=(New-PhpObjectId); Class=$original.Class; Props=$props
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
                    $diff = if ($node.Op -ceq '++') { [long]1 } else { [long]-1 }
                    Set-LValue $node.Target $diff '+='
                    if ($node.Prefix) { return (Get-LValue $node.Target) }
                    return $before
                }
                'assign_ref' {
                    $cell=if ($node.Source.Kind -in @('call','method','static_method','invoke')) {
                        Invoke-PhpReferenceCall $node.Source
                    } else {
                        Get-PhpLValueCell $node.Source
                    }
                    Set-PhpReferenceTarget $node.Target $cell
                    return $cell.Value
                }
                'assign_expr' {
                    if ($node.Op -ceq '??=') {
                        $current = $null
                        $state.QuietDepth++
                        try { $current = Get-LValue $node.Target }
                        catch {
                            if ($_.Exception.Message -notlike 'ALL PHP: Undefined *') { throw }
                        }
                        finally { $state.QuietDepth-- }
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
                                        $typedProperty=$null
                                        if ($object.Class -ne 'stdClass') {
                                            $typedProperty=Find-PhpProperty $object.Class $arg.Name $false
                                        }
                                        if ($null -ne $typedProperty -and
                                            -not [string]::IsNullOrEmpty([string]$typedProperty.TypeName)) {
                                            if ($node.Name -ceq 'isset') { return $false }
                                            if ($node.Name -ceq 'empty') { return $true }
                                        }
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
                            $state.QuietDepth++
                            try {
                                $value = Invoke-PhpExpr $arg
                            } catch {
                                if ($_.Exception.Message -like 'ALL PHP: Undefined *') {
                                    $found = $false
                                } else { throw }
                            }
                            finally { $state.QuietDepth-- }
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
                                    if ($null -ne $declared -and $declared.Readonly) {
                                        throw "ALL PHP: Cannot unset readonly property '$($arg.Name)'"
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
                    $callName = Resolve-PhpFunctionNodeName $node
                    if ($state.Functions.ContainsKey($callName)) {
                        $args=Evaluate-PhpUserArguments $node.Args $state.Functions[$callName]
                        return (Invoke-PhpCallable $state.Functions[$callName] $args $null)
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
                    return (Invoke-PhpFunction $callName ($callArgs.ToArray()))
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
                        PhpType='object'; Id=(New-PhpObjectId); Class=$className
                        Props=[System.Collections.Generic.Dictionary[string,object]]::new(
                            [System.StringComparer]::Ordinal)
                    }
                    # Ancestors first, derived declarations last.
                    for ($i=$chain.Count - 1; $i -ge 0; $i--) {
                        foreach ($prop in $chain[$i].Properties) {
                            if ($prop.Static) { continue }
                            if ($null -eq $prop.Default -and
                                -not [string]::IsNullOrEmpty([string]$prop.TypeName)) {
                                continue # declared but uninitialized typed property
                            }
                            $val=$null
                            if ($null -ne $prop.Default) { $val=Invoke-PhpExpr $prop.Default }
                            $object.Props[$prop.Name]=Copy-PhpValue (Convert-PhpTypedValue $val ([string]$prop.TypeName) ('property ' + $prop.Name))
                        }
                    }
                    if ($state.PreludeLoaded -and (Test-PhpInstanceOf $className 'Throwable')) {
                        Initialize-PhpThrowable $object
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
                        '-' { return (Php-Neg (To-Number $value)) }
                        '~' { return [long](-bnot (To-PhpInt $value)) }
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
                    Throw-PhpError 'UnhandledMatchError' ('Unhandled match case ' + (Format-PhpMatchValue $subjectValue)) 'ALL PHP: UnhandledMatchError'
                }
                'binary' {
                    if ($node.Op -ceq '??') {
                        $leftValue = $null
                        $state.QuietDepth++
                        try { $leftValue = Invoke-PhpExpr $node.Left }
                        catch {
                            if ($_.Exception.Message -notlike 'ALL PHP: Undefined *') { throw }
                        }
                        finally { $state.QuietDepth-- }
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
                        '**' { return (Php-Pow (To-Number $a) (To-Number $b)) }
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
                            return (Php-Add (To-Number $a) (To-Number $b))
                        }
                        '-' { return (Php-Sub (To-Number $a) (To-Number $b)) }
                        '*' { return (Php-Mul (To-Number $a) (To-Number $b)) }
                        '/' { return (Php-Div (To-Number $a) (To-Number $b)) }
                        '%' { return (Php-Mod (To-Number $a) (To-Number $b)) }
                        '==' { return (Php-Equal $a $b $false) }
                        '!=' { return (-not (Php-Equal $a $b $false)) }
                        '===' { return (Is-StrictEqual $a $b) }
                        '!==' { return (-not (Is-StrictEqual $a $b)) }
                        '<' { return (Test-PhpRelation $a $b '<') }
                        '<=' { return (Test-PhpRelation $a $b '<=') }
                        '>' { return (Test-PhpRelation $a $b '>') }
                        '>=' { return (Test-PhpRelation $a $b '>=') }
                        '<=>' { return [long](Compare-Values $a $b) }
                        '<<' { return (Php-Shift $a $b $true) }
                        '>>' { return (Php-Shift $a $b $false) }
                        '&' { return [long]((To-PhpInt $a) -band (To-PhpInt $b)) }
                        '|' { return [long]((To-PhpInt $a) -bor (To-PhpInt $b)) }
                        '^' { return [long]((To-PhpInt $a) -bxor (To-PhpInt $b)) }
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
            if ($null -ne $node.Line) { $state.Line = $node.Line }
            switch ($node.Kind) {
                'constdecl' {
                    foreach ($decl in $node.Decls) {
                        if ($state.Constants.ContainsKey($decl.Name) -or $phpConstants.ContainsKey($decl.Name)) {
                            throw "ALL PHP: Constant already declared '$($decl.Name)'"
                        }
                        $state.Constants[$decl.Name] = Copy-PhpValue (Invoke-PhpExpr $decl.Value)
                    }
                    return
                }
                'try' {
                    # $pending holds an error that is still propagating once try/catch has finished;
                    # it is re-raised after finally unless finally itself returns, breaks or continues.
                    $pending = $null
                    try {
                        try { Invoke-PhpStatement $node.Body }
                        catch {
                            $thrown = Get-PhpThrown $_
                            if ($null -eq $thrown) { throw }
                            $handler = $null
                            foreach ($candidate in $node.Catches) {
                                foreach ($typeName in $candidate.Types) {
                                    if (Test-PhpInstanceOf $thrown.Class $typeName) { $handler = $candidate; break }
                                }
                                if ($null -ne $handler) { break }
                            }
                            if ($null -eq $handler) { throw }
                            $state.Flow.Returned = $false
                            $state.Flow.LoopControl = $null
                            if ($null -ne $handler.Var) { Set-PhpVariableValue $handler.Var $thrown }
                            Invoke-PhpStatement $handler.Body
                        }
                    } catch { $pending = $_ }
                    if ($null -ne $node.Finally) {
                        # finally runs with a clean control-flow state; a return/break/continue that
                        # was already under way resumes afterwards unless finally issues its own.
                        $flow = $state.Flow
                        $saved = @{}
                        foreach ($name in @($flow.Keys)) { $saved[$name] = $flow[$name] }
                        $flow.Returned = $false
                        $flow.LoopControl = $null
                        try { Invoke-PhpStatement $node.Finally }
                        catch {
                            # An exception raised by finally replaces the pending one and keeps it
                            # reachable at the end of its "previous" chain.
                            $replacement = Get-PhpThrown $_
                            $original = if ($null -ne $pending) { Get-PhpThrown $pending } else { $null }
                            if ($null -ne $replacement -and $null -ne $original -and
                                -not [object]::ReferenceEquals($replacement, $original)) {
                                $tail = $replacement
                                $cyclic = $false
                                while (Is-PhpObject $tail.Props['previous']) {
                                    $tail = $tail.Props['previous']
                                    if ([object]::ReferenceEquals($tail, $original)) { $cyclic = $true; break }
                                }
                                if (-not $cyclic) { $tail.Props['previous'] = $original }
                            }
                            throw
                        }
                        if ($flow.Returned -or $null -ne $flow.LoopControl) { $pending = $null }
                        else { foreach ($name in @($saved.Keys)) { $flow[$name] = $saved[$name] } }
                    }
                    if ($null -ne $pending) { throw $pending }
                    return
                }
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
                                ($backedValue -isnot [long])) {
                                throw 'ALL PHP: Backed enum int case expects an integer'
                            }
                            $uniqueValue=$node.BackingType + ':' + [string]$backedValue
                            if (-not $usedValues.Add($uniqueValue)) {
                                throw 'ALL PHP: Duplicate backed enum case value'
                            }
                            $props['value']=$backedValue
                        }
                        $caseObject=[pscustomobject]@{
                            PhpType='object'; Id=0; Class=$node.Name; Props=$props
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
                    if ($null -ne $node.Parent -and $state.Classes[$node.Parent].Readonly -and -not $node.Readonly) {
                        throw 'ALL PHP: Non-readonly class cannot extend readonly class'
                    }
                    if ($node.Readonly -and $null -ne $node.Parent -and -not $state.Classes[$node.Parent].Readonly) {
                        throw 'ALL PHP: Readonly class cannot extend non-readonly class'
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
                                # PHP does not check constructor signatures against a concrete parent.
                                if ($parentMethod.Visibility -ne 'private' -and
                                    ($method.Name -ine '__construct' -or $parentMethod.Abstract)) {
                                    Assert-PhpMethodSignature $method $parentMethod $method.Name
                                }
                            }
                        }
                        $methods[$method.Name]=$method
                    }
                    $effectiveProperties=[System.Collections.Generic.List[object]]::new()
                    $declaredNames=[System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
                    foreach ($prop in $node.Properties) {
                        if (-not $declaredNames.Add($prop.Name)) {
                            throw "ALL PHP: Duplicate property '$($prop.Name)'"
                        }
                        [void]$effectiveProperties.Add($prop)
                    }
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
                                ReturnByRef=$method.ReturnByRef; ReturnType=$method.ReturnType
                            }
                            if ($null -ne $node.Parent) {
                                $inherited=$null
                                try { $inherited=Find-PhpMethod $node.Parent $method.Name }
                                catch {
                                    if ($_.Exception.Message -notlike 'ALL PHP: Undefined method*') { throw }
                                }
                                if ($null -ne $inherited) {
                                    if ($inherited.Final) { throw 'ALL PHP: Cannot override final method via trait' }
                                    if ($inherited.Visibility -ne 'private' -and
                                        ($method.Name -ine '__construct' -or $inherited.Abstract)) {
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
                                Owner=$node.Name; TypeName=$prop.TypeName
                                Readonly=([bool]$prop.Readonly -or [bool]$node.Readonly)
                            })
                    }
                    foreach ($prop in $effectiveProperties) {
                        if ($node.Readonly -and $prop.Static) {
                            throw 'ALL PHP: readonly static property is not allowed'
                        }
                        if ($node.Readonly -and [string]::IsNullOrEmpty([string]$prop.TypeName)) {
                            throw 'ALL PHP: readonly property requires a type'
                        }
                        if (($node.Readonly -or $prop.Readonly) -and $null -ne $prop.Default) {
                            throw 'ALL PHP: readonly property cannot have a default value'
                        }
                        if ($null -ne $prop.Default) {
                            $defaultValue=Invoke-PhpExpr $prop.Default
                            Assert-PhpPropertyDefault $defaultValue ([string]$prop.TypeName) $prop.Name
                        }
                    }
                    $statics=[System.Collections.Generic.Dictionary[string,object]]::new(
                        [System.StringComparer]::Ordinal)
                    foreach ($prop in $effectiveProperties) {
                        if ($prop.Static) {
                            if ($null -eq $prop.Default -and
                                -not [string]::IsNullOrEmpty([string]$prop.TypeName)) {
                                continue # typed static property stays uninitialized
                            }
                            $default=$null
                            if ($null -ne $prop.Default) { $default=Invoke-PhpExpr $prop.Default }
                            $statics[$prop.Name]=Copy-PhpValue (Convert-PhpTypedValue $default ([string]$prop.TypeName) ('property ' + $prop.Name))
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
                        Abstract=$node.Abstract; Final=$node.Final; Readonly=$node.Readonly
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
                    $cell = $null
                    if ($null -ne $node.Expr) {
                        if ($state.ReturnByRef) {
                            if ($node.Expr.Kind -in @('variable','dynamic_variable','index','property','static_property')) {
                                $cell=Get-PhpLValueCell $node.Expr
                            } elseif ($node.Expr.Kind -in @('call','method','static_method','invoke')) {
                                $cell=Invoke-PhpReferenceCall $node.Expr
                            } else {
                                throw 'ALL PHP: Reference return requires a writable value'
                            }
                            $value=$cell.Value
                        } else {
                            $value=Invoke-PhpExpr $node.Expr
                        }
                    }
                    $state.Flow.RefCell=$cell
                    $state.Flow.Value = $value
                    $state.Flow.ReturnedWithExpr=($null -ne $node.Expr)
                    $state.Flow.Returned = $true
                    return
                }
                'assign' {
                    if ($node.Op -ceq '??=') {
                        $current = $null
                        $state.QuietDepth++
                        try { $current = Get-LValue $node.Target }
                        catch {
                            if ($_.Exception.Message -notlike 'ALL PHP: Undefined *') { throw }
                        }
                        finally { $state.QuietDepth-- }
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
                                    Set-PhpVariableValue $node.KeyName ([long]$key.Substring(2))
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
        # Load the built-in exception classes up front when the program mentions any of them, so
        # that user classes can extend them.
        foreach ($programToken in $state.Tokens) {
            if ($phpPreludeTriggers.Contains($programToken)) { Ensure-PhpPrelude; break }
        }
        try {
            foreach ($statement in $statements) {
                if ($state.Flow.Returned) { break }
                Invoke-PhpStatement $statement
            }
        } catch {
            $uncaught = Get-PhpThrown $_
            if ($null -ne $uncaught -and $null -ne $state.ExceptionHandler) {
                $handler = $state.ExceptionHandler
                $state.ExceptionHandler = $null
                [void](Invoke-PhpValueCallable $handler @($uncaught))
                return
            }
            if ($null -eq $uncaught -or -not $PhpDiagnostics) { throw }
            # Same text the PHP CLI writes with display_errors=1 and html_errors=0.
            [Console]::Write("`nFatal error: Uncaught " +
                (Get-PhpThrowableString $uncaught) + "`n  thrown in " + (To-PhpText $uncaught.Props['file']) +
                ' on line ' + (To-PhpText $uncaught.Props['line']) + "`n")
        }
    }
}
