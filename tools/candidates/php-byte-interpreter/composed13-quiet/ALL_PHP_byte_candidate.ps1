@{
    Name = 'PHP'
    CliContextCapabilities = @('source-body-v1','script-arguments-v1','initial-ini-v1','source-tags-v1')
    Run = {
        # -PhpDiagnostics: report an uncaught PHP exception the way the PHP CLI does (text on the
        # output stream) instead of surfacing it as a PowerShell error. Default behaviour is unchanged.
        param([string]$Code, [switch]$PhpDiagnostics, [System.Collections.IDictionary]$CliContext = $null, [object]$NativeContext = $null)
        $isCli = $null -ne $CliContext
        if ($isCli) {
            $CliContext['ExitCode'] = [long]0
            $CliContext['Terminated'] = $false
            $CliContext['TerminationReason'] = $null
            [void]$CliContext.Remove('CompileError')
        }
        $ErrorActionPreference = 'Stop'
        if (-not ('AllPhp.ValidTextSymbols.Comparers' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
namespace AllPhp.ValidTextSymbols
{
    // Equality bridge for already validated UTF-8 text metadata. No Unicode
    // normalization or invariant/current-culture comparisons are permitted.
    // Hashes are internal and are not byte-symbol hashes or Zend ABI hashes.
    public static class Comparers
    {
        public const string Contract = "allphp-valid-utf8-symbols-01";
        public static readonly StringComparer Ascii = new SymbolComparer(false);
        public static readonly StringComparer Constant = new SymbolComparer(true);
        public static string LowerAscii(string value)
        {
            if (value == null) throw new ArgumentNullException("value");
            char[] result = null;
            for (int i = 0; i < value.Length; i++)
                if (value[i] >= 'A' && value[i] <= 'Z')
                {
                    if (result == null) result = value.ToCharArray();
                    result[i] = (char)(value[i] + 32);
                }
            return result == null ? value : new String(result);
        }
        private sealed class SymbolComparer : StringComparer
        {
            private readonly bool constant;
            public SymbolComparer(bool constant) { this.constant = constant; }
            private char At(string value, int offset, int boundary)
            {
                char c = value[offset];
                return offset < boundary && c >= 'A' && c <= 'Z' ? (char)(c + 32) : c;
            }
            public override int Compare(string left, string right)
            {
                if (Object.ReferenceEquals(left, right)) return 0;
                if (left == null) return -1;
                if (right == null) return 1;
                int lb = constant ? left.LastIndexOf((char)92) : left.Length;
                int rb = constant ? right.LastIndexOf((char)92) : right.Length;
                int length = Math.Min(left.Length, right.Length);
                for (int i = 0; i < length; i++)
                {
                    char a = At(left, i, lb), b = At(right, i, rb);
                    if (a != b) return a < b ? -1 : 1;
                }
                return left.Length == right.Length ? 0 : left.Length < right.Length ? -1 : 1;
            }
            public override bool Equals(string left, string right) { return Compare(left, right) == 0; }
            public override int GetHashCode(string value)
            {
                if (value == null) throw new ArgumentNullException("value");
                int boundary = constant ? value.LastIndexOf((char)92) : value.Length;
                unchecked
                {
                    uint hash = 2166136261;
                    for (int i = 0; i < value.Length; i++) hash = (hash ^ At(value, i, boundary)) * 16777619;
                    return (int)hash;
                }
            }
        }
    }
}
'@
        }
        if ([AllPhp.ValidTextSymbols.Comparers]::Contract -cne 'allphp-valid-utf8-symbols-01') {
            throw 'ALL PHP valid-text symbol comparer contract mismatch'
        }
        function ConvertTo-PhpAsciiLower([string]$name) { return [AllPhp.ValidTextSymbols.Comparers]::LowerAscii($name) }
        function Test-PhpNameEqual([string]$left,[string]$right) { return [AllPhp.ValidTextSymbols.Comparers]::Ascii.Equals($left,$right) }
        function Test-PhpRawNameEqual([string]$left,[string]$right) { return [StringComparer]::Ordinal.Equals($left,$right) }
        function Test-PhpNameIn([string]$name,$names) {
            foreach($other in $names) { if (Test-PhpNameEqual $name $other) { return $true } }
            return $false
        }
        $phpByteRuntimePath = 'C:\Users\rinpa\ALL-php-compat-20261112\tools\candidates\php-byte-runtime\out\runtime01\AllPhp.ByteValues.Runtime.dll'
        $phpByteRuntimeHash = '18d50efb55d8a333424149e4ab37428e102b1ac938240e50358ee3c8ab89466b'
        if ((Get-FileHash -LiteralPath $phpByteRuntimePath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $phpByteRuntimeHash) {
            throw 'ALL PHP byte runtime hash mismatch'
        }
        $loadedByteType = 'AllPhp.ByteValues.PhpBytes' -as [type]
        if ($null -ne $loadedByteType) {
            if ([IO.Path]::GetFullPath($loadedByteType.Assembly.Location) -cne [IO.Path]::GetFullPath($phpByteRuntimePath)) {
                throw 'ALL PHP byte runtime was already loaded from a different location'
            }
        } else { Add-Type -Path $phpByteRuntimePath }
        # PHP-owned strings use PhpBytes. Host names/paths remain explicit text
        # boundaries until their separate symbol/source-byte migration is wired.
        function Is-PhpBytes($value) {
            if (Is-PhpRefCell $value) { $value=$value.Value }
            return ($value -is [AllPhp.ByteValues.PhpBytes])
        }
        function Is-PhpStringValue($value) {
            if (Is-PhpRefCell $value) { $value=$value.Value }
            # Legacy text from an existing builtin is normalized on value entry.
            # This bridge is temporary and is not a claim all text producers moved.
            return ($value -is [AllPhp.ByteValues.PhpBytes] -or $value -is [string])
        }
        function ConvertTo-PhpOwnedValue($value) {
            if ($value -is [string]) { return [AllPhp.ByteValues.PhpBytes]::FromUtf8($value) }
            return $value
        }
        function Get-PhpHostText($value) {
            if (Is-PhpRefCell $value) { $value=$value.Value }
            if ($value -is [string]) { return $value }
            if ($value -is [AllPhp.ByteValues.PhpBytes]) {
                $text=$null
                if ($value.TryDecodeUtf8([ref]$text)) { return $text }
                throw 'ALL PHP byte migration: this host-text boundary still requires valid UTF-8'
            }
            throw 'ALL PHP byte migration: PHP value was used as host metadata without conversion'
        }
        function To-PhpBytes($value) {
            if (Is-PhpRefCell $value) { $value=$value.Value }
            if ($value -is [AllPhp.ByteValues.PhpBytes]) { return $value }
            if ($null -eq $value) { return [AllPhp.ByteValues.PhpBytes]::Empty }
            if ($value -is [string]) { return [AllPhp.ByteValues.PhpBytes]::FromUtf8($value) }
            if ($value -is [bool]) {
                if ($value) { return [AllPhp.ByteValues.PhpBytes]::FromUtf8('1') }
                return [AllPhp.ByteValues.PhpBytes]::Empty
            }
            if ($value -is [long]) {
                return [AllPhp.ByteValues.PhpBytes]::FromUtf8($value.ToString([Globalization.CultureInfo]::InvariantCulture))
            }
            if ($value -is [double]) {
                return [AllPhp.ByteValues.PhpBytes]::FromUtf8((Format-PhpFloat $value 14))
            }
            if (Is-PhpArray $value) {
                if ($isCli -or $PhpDiagnostics) {
                    Write-PhpDiagnostic 2 'Array to string conversion'
                    return [AllPhp.ByteValues.PhpBytes]::FromUtf8('Array')
                }
                throw 'ALL PHP: Array to string conversion is not supported'
            }
            if (Is-PhpObject $value) {
                $magic=Find-OptionalPhpMethod $value.Class '__toString'
                if ($null -ne $magic) {
                    $converted=Invoke-PhpMethod $value '__toString' @()
                    if ((Is-PhpStringValue $converted) -or (Is-PhpNum $converted) -or $converted -is [bool]) {
                        return (To-PhpBytes $converted)
                    }
                    throw 'ALL PHP: __toString must return string'
                }
                throw 'ALL PHP: Object to string conversion is not supported'
            }
            throw 'ALL PHP byte migration: unsupported PHP string conversion source'
        }
        function Write-PhpBytes($value, [bool]$ErrorStream=$false) {
            $bytes=To-PhpBytes $value
            $stream=$null
            if ($isCli) {
                $key=if($ErrorStream){'ErrorByteStream'}else{'OutputByteStream'}
                if ($CliContext.Keys -contains $key) { $stream=$CliContext[$key] }
            }
            if ($null -ne $stream) {
                if ($stream -isnot [IO.Stream] -or -not $stream.CanWrite) {
                    throw 'ALL PHP byte migration: invalid request byte output stream'
                }
                $bytes.WriteTo($stream);$stream.Flush();return
            }
            if (-not $isCli) {
                # Preserve the existing library's valid-text Console capture.
                # Invalid bytes never become replacement text.
                $text=$null
                if ($bytes.TryDecodeUtf8([ref]$text)) {
                    if ($ErrorStream) { [Console]::Error.Write($text) } else { [Console]::Write($text) }
                    return
                }
            }
            $raw=if($ErrorStream){[Console]::OpenStandardError()}else{[Console]::OpenStandardOutput()}
            $bytes.WriteTo($raw);$raw.Flush()
        }
        function Get-PhpNumericView($value) {
            if ($value -is [string]) { return $value }
            if ($value -isnot [AllPhp.ByteValues.PhpBytes]) { throw 'Not a PHP string numeric view' }
            # This is a grammar-classification view, never a PHP value/output.
            # Non-ASCII bytes map to '?' which cannot match PHP ASCII numeric
            # syntax. The original bytes remain unchanged. Large streaming
            # numeric parsing is a separately tracked migration obligation.
            return [Text.Encoding]::ASCII.GetString($value.ToArray())
        }
        function New-PhpIntegerKey([long]$value) {
            return [AllPhp.ByteValues.PhpKey]::FromInteger($value)
        }
        function Get-PhpKeyValue($key) {
            if ($key -isnot [AllPhp.ByteValues.PhpKey]) { throw 'ALL PHP byte migration: untyped array key' }
            if ($key.IsInteger) { return [long]$key.IntegerValue }
            return $key.BytesValue
        }
        function Get-PhpKeyHostText($key) {
            if ($key.IsInteger) { return $key.IntegerValue.ToString([Globalization.CultureInfo]::InvariantCulture) }
            return (Get-PhpHostText $key.BytesValue)
        }
        function Format-PhpBytesDump($value, [string]$pad, $referenceContext=$null) {
            $builder=[AllPhp.ByteValues.PhpByteBuilder]::new()
            $referenceMark=''
            if (Is-PhpRefCell $value) {
                if($pad.Length-gt0 -and $null-ne$referenceContext -and (Get-PhpReferenceOwnerCount $referenceContext $value)-gt1){$referenceMark='&'}
                $value=$value.Value
            }
            if ($null -eq $value) { $builder.AppendUtf8($pad+$referenceMark+"NULL`n");return $builder.ToPhpBytes() }
            if ($value -is [bool]) {
                $text=if($value){'true'}else{'false'}
                $builder.AppendUtf8($pad+$referenceMark+'bool('+$text+")`n");return $builder.ToPhpBytes()
            }
            if ($value -is [long]) {
                $builder.AppendUtf8($pad+$referenceMark+'int('+$value.ToString([Globalization.CultureInfo]::InvariantCulture)+")`n")
                return $builder.ToPhpBytes()
            }
            if ($value -is [double]) {
                $builder.AppendUtf8($pad+$referenceMark+'float('+(Format-PhpFloat $value 0)+")`n");return $builder.ToPhpBytes()
            }
            if (Is-PhpStringValue $value) {
                $bytes=To-PhpBytes $value
                $builder.AppendUtf8($pad+$referenceMark+'string('+$bytes.Length+') "');$builder.Append($bytes)
                $builder.AppendUtf8("`"`n");return $builder.ToPhpBytes()
            }
            if (Is-PhpArray $value) {
                if($null-eq$referenceContext){$referenceContext=New-PhpReferenceContext @($value)}
                foreach($backing in $referenceContext.DumpArrays){
                    if([object]::ReferenceEquals($backing,$value.ReferenceBacking)){$builder.AppendUtf8($pad+"*RECURSION*`n");return $builder.ToPhpBytes()}
                }
                [void]$referenceContext.DumpArrays.Add($value.ReferenceBacking)
                try {
                $builder.AppendUtf8($pad+$referenceMark+'array('+$value.Items.Count+") {`n")
                foreach($key in $value.Items.Keys) {
                    if($key.IsInteger){$builder.AppendUtf8($pad+'  ['+$key.IntegerValue+"]=>`n")}
                    else{$builder.AppendUtf8($pad+'  ["');$builder.Append($key.BytesValue);$builder.AppendUtf8("`"]=>`n")}
                    $builder.Append((Format-PhpBytesDump $value.Items[$key] ($pad+'  ') $referenceContext))
                }
                $builder.AppendUtf8($pad+"}`n");return $builder.ToPhpBytes()
                } finally {$referenceContext.DumpArrays.RemoveAt($referenceContext.DumpArrays.Count-1)}
            }
            if (Is-PhpObject $value) {
                if ($state.Classes.ContainsKey($value.Class) -and
                    $state.Classes[$value.Class].PSObject.Properties['Enum'] -and
                    $state.Classes[$value.Class].Enum) {
                    $builder.AppendUtf8($pad+$referenceMark+'enum('+$value.Class+'::')
                    $builder.Append((To-PhpBytes $value.Props['name']))
                    $builder.AppendUtf8(")`n");return $builder.ToPhpBytes()
                }
                foreach($seen in $state.DumpStack) {
                    if([object]::ReferenceEquals($seen,$value)) {
                        $builder.AppendUtf8($pad+"*RECURSION*`n");return $builder.ToPhpBytes()
                    }
                }
                [void]$state.DumpStack.Add($value)
                try {
                    $entries=Get-PhpObjectDumpEntries $value
                    $count=0
                    foreach($entry in $entries){if($entry.Present){$count++}}
                    $id=0
                    if($value.PSObject.Properties['Id']){$id=$value.Id}
                    $builder.AppendUtf8($pad+$referenceMark+'object('+$value.Class+')#'+$id+' ('+$count+") {`n")
                    foreach($entry in $entries) {
                        $builder.AppendUtf8($pad+'  ["'+$entry.Name+'"'+$entry.Suffix+"]=>`n")
                        if($entry.Present){$builder.Append((Format-PhpBytesDump $entry.Value ($pad+'  ') $referenceContext))}
                        else{$builder.AppendUtf8($pad+'  uninitialized('+$entry.TypeName+")`n")}
                    }
                    $builder.AppendUtf8($pad+"}`n");return $builder.ToPhpBytes()
                } finally {$state.DumpStack.RemoveAt($state.DumpStack.Count-1)}
            }
            throw 'ALL PHP: var_dump() of this value type is not implemented'
        }
        function Format-PhpBytesPrintR($value, [int]$indent) {
            if (Is-PhpRefCell $value) { $value=$value.Value }
            $pad=' '*$indent
            $builder=[AllPhp.ByteValues.PhpByteBuilder]::new()
            if(Is-PhpArray $value) {
                $builder.AppendUtf8("Array`n"+$pad+"(`n")
                foreach($key in $value.Items.Keys) {
                    $builder.AppendUtf8($pad+'    [')
                    $builder.Append((To-PhpBytes (Get-PhpKeyValue $key)))
                    $builder.AppendUtf8('] => ')
                    $builder.Append((Format-PhpBytesPrintR $value.Items[$key] ($indent+8)))
                    $builder.AppendUtf8("`n")
                }
                $builder.AppendUtf8($pad+")`n");return $builder.ToPhpBytes()
            }
            if(Is-PhpObject $value) {
                foreach($seen in $state.DumpStack) {
                    if([object]::ReferenceEquals($seen,$value)){return [AllPhp.ByteValues.PhpBytes]::FromUtf8('*RECURSION*')}
                }
                [void]$state.DumpStack.Add($value)
                try {
                    $enum=($state.Classes.ContainsKey($value.Class)-and
                        $state.Classes[$value.Class].PSObject.Properties['Enum']-and$state.Classes[$value.Class].Enum)
                    $kind=if($enum){' Enum'}else{' Object'}
                    $builder.AppendUtf8($value.Class+$kind+"`n"+$pad+"(`n")
                    foreach($entry in (Get-PhpObjectDumpEntries $value)) {
                        if(-not$entry.Present){continue}
                        $builder.AppendUtf8($pad+'    ['+$entry.Name+$entry.PlainSuffix+'] => ')
                        $builder.Append((Format-PhpBytesPrintR $entry.Value ($indent+8)))
                        $builder.AppendUtf8("`n")
                    }
                    $builder.AppendUtf8($pad+")`n");return $builder.ToPhpBytes()
                } finally {$state.DumpStack.RemoveAt($state.DumpStack.Count-1)}
            }
            return (To-PhpBytes $value)
        }
        function Evaluate-PhpBuiltinArguments($expressions, [string]$name) {
            $referenceArgumentsRoot=$state.ReferenceTemporaryRoots.Count
            try {
            $result=[Collections.Generic.List[object]]::new()
            # These are the currently implemented mutating array builtins. Their
            # first operand retains its existing lvalue storage. All by-value
            # array arguments must snapshot at evaluation time, before later
            # argument expressions can mutate the source array.
            $firstByReference=(ConvertTo-PhpAsciiLower $name) -cin @('array_push','array_pop','array_shift','array_unshift')
            for($i=0;$i-lt$expressions.Count;$i++) {
                $expression=$expressions[$i]
                if($expression.Kind-ceq'named_argument') {
                    $value=Invoke-PhpExpr $expression.Expr
                    [void]$result.Add([pscustomobject]@{
                        PhpType='named_argument';Name=$expression.Name;Value=(Copy-PhpValue $value)
                    })
                } else {
                    $value=Invoke-PhpExpr $expression
                    if(-not($firstByReference-and$i-eq0)){$value=Copy-PhpValue $value}
                    [void]$result.Add($value)
                }
                Add-PhpReferenceArgumentRoot $value
            }
            return ,($result.ToArray())
            } finally {
                Remove-PhpReferenceTemporaryRoots $referenceArgumentsRoot
            }
        }


        # ALL's own PHP subset interpreter. No PHP executable, eval, or Invoke-Expression.
        if ($isCli -and ($CliContext.Keys -contains 'SourceMode') -and
            $CliContext['SourceMode'] -in @('body','file','stdin')) {
            # CLI -r starts in PHP code mode. Preserve the actual input body,
            # including leading lines; do not add a synthetic opening tag.
            # Empty file/stdin input is a legitimate zero-statement program.
            $source = $Code
        } else {
            $source = $Code.Trim()
            if ($source -notmatch '^<\?php(?:\s|$)') {
                throw 'ALL PHP: A <?php opening tag is required'
            }
            $source = [regex]::Replace($source, '^<\?php\b', '')
            $source = $source.TrimEnd()
            if ($source.EndsWith('?>')) {
                $source = $source.Substring(0, $source.Length - 2)
            }
        }

        $state = @{
                ReferenceOwnerFrames=[Collections.Generic.List[object]]::new()
                ReferenceTemporaryRoots=[Collections.Generic.List[object]]::new()
            Tokens = [System.Collections.Generic.List[string]]::new()
            Pos = 0
            Vars = [System.Collections.Generic.Dictionary[string,object]]::new(
                [System.StringComparer]::Ordinal)
            Functions = [System.Collections.Generic.Dictionary[string,object]]::new(
                [AllPhp.ValidTextSymbols.Comparers]::Ascii)
            Classes = [System.Collections.Generic.Dictionary[string,object]]::new(
                [AllPhp.ValidTextSymbols.Comparers]::Ascii)
            Interfaces = [System.Collections.Generic.Dictionary[string,object]]::new(
                [AllPhp.ValidTextSymbols.Comparers]::Ascii)
            Traits = [System.Collections.Generic.Dictionary[string,object]]::new(
                [AllPhp.ValidTextSymbols.Comparers]::Ascii)
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
                    [AllPhp.ValidTextSymbols.Comparers]::Constant)
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
                InlineHtml = [System.Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
                DocStrings = [System.Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
                LiteralWarnings = [System.Collections.Generic.List[object]]::new()
                ParsingInternalPrelude = $false
        }

        $state.Globals = $state.Vars

        # Optional, preloaded ALL-owned native ABI context. Its host owns Start/End.
        # No stock PHP runtime is called, and no native failure is retried elsewhere.

        function Test-PhpRegisteredPublicFunction([string]$name) {
            # Same public boundary as function_exists: the old implementation helper is not
            # a public builtin. The separate private-helper candidate removes its registry entry.
            if ($name -ine '__all_throwable_string' -and $phpBuiltinNames.Contains($name)) { return $true }
            return (Test-PhpNativeFunction $name)
        }
        function Throw-PhpRegisteredFunctionRedeclaration($declaration) {
            $message = 'Cannot redeclare function ' + $declaration.Name + '()'
            if (-not $isCli) { throw ('ALL PHP: ' + $message) }
            $line = if ($null -ne $declaration.Line) { [long]$declaration.Line } else { [long]$state.Line }
            [Console]::Error.Write('Fatal error: ' + $message + ' in ' + $state.ScriptName +
                ' on line ' + $line + "`nStack trace:`n" + (Format-PhpStackTrace) + "`n")
            $CliContext['ExitCode'] = [long]255
            $CliContext['Terminated'] = $true
            $CliContext['TerminationReason'] = 'function_redeclaration'
            # This engine fatal is not a catchable PHP Throwable and skips PHP finally.
            # The existing private control signal still runs host-side cleanup.
            $signal = [System.Exception]::new('ALL PHP: private function redeclaration fatal')
            $signal.Data['AllPhpCliExit'] = $cliExitToken
            throw $signal
        }

        function Get-PhpNativeName([string]$name) {
            if ($name.StartsWith([string][char]92)) { return $name.Substring(1) }
            return $name
        }
        function Test-PhpNativeFunction([string]$name) {
            if ($null -eq $NativeContext) { return $false }
            return [bool]$NativeContext.HasFunction((Get-PhpNativeName $name))
        }
        function Throw-PhpNativeUnsupported([string]$reason) {
            $signal = [System.InvalidOperationException]::new('ALL PHP Native Unsupported: ' + $reason)
            $signal.Data['AllPhpNativeUnsupported'] = $true
            throw $signal
        }
        function Throw-PhpNativeUnsupportedBytes($reason) {
            $rawReason=To-PhpBytes $reason
            $hostReason=$null
            if ($rawReason.TryDecodeUtf8([ref]$hostReason)) {
                Throw-PhpNativeUnsupported $hostReason
            }
            # This ASCII carrier is host metadata, not the PHP diagnostic.
            # The complete raw message remains available without replacement.
            $signal=[System.InvalidOperationException]::new('ALL PHP Native Unsupported: raw native message retained in exception data')
            $signal.Data['AllPhpNativeUnsupported']=$true
            $signal.Data['AllPhpNativeUnsupportedBytes']=$rawReason
            throw $signal
        }
        function Invoke-PhpNativeFunction([string]$name, $values) {
            if ($null -ne $state.ErrorHandler -and -not $NativeContext.SynchronousCallbacksEnabled) {
                Throw-PhpNativeUnsupported 'native calls with an installed PHP error handler require synchronous callbacks'
            }
            $nativeName=Get-PhpNativeName $name
            $nativeUsesBytes=($null -ne $NativeContext.PSObject.Methods['InvokeScalarBytes'])
            foreach ($item in @($values)) {
                if ($null -ne $item -and $item.PSObject.Properties['PhpType'] -and
                    $item.PhpType -ceq 'named_argument') {
                    Throw-PhpNativeUnsupported 'named native arguments are not implemented'
                }
            }
            $nativeValues=[System.Collections.Generic.List[object]]::new()
            try {
                foreach ($item in @($values)) {
                    # Convert only actual PHP strings. Arrays/objects/references
                    # retain their explicit pre-existing native boundary guards.
                    if (Is-PhpStringValue $item) {
                        if ($nativeUsesBytes) { [void]$nativeValues.Add((To-PhpBytes $item)) }
                        else { [void]$nativeValues.Add((Get-PhpHostText $item)) }
                    } else { [void]$nativeValues.Add($item) }
                }
                $nativeArguments=$nativeValues.ToArray()
                # API choice is made before native execution. No catch branch
                # calls an alternative native/runtime implementation.
                if ($nativeUsesBytes) {
                    $nativeResult=$NativeContext.InvokeScalarBytes($nativeName,$nativeArguments,$false)
                } else {
                    $nativeResult=$NativeContext.InvokeScalar($nativeName,$nativeArguments,$false)
                }
            } catch {
                if ($isCli -and (Test-PhpCliExit $_)) { throw }
                $callbackThrowable=Get-PhpThrown $_
                if ($null -ne $callbackThrowable) { Throw-PhpObject $callbackThrowable }
                Throw-PhpNativeUnsupported ('scalar boundary: ' + $_.Exception.Message)
            }
            if ($null -ne $nativeResult.Output -and $nativeResult.Output.Length -gt 0) {
                if (Is-PhpBytes $nativeResult.Output) { Write-PhpBytes $nativeResult.Output }
                else { Write-PhpBytes ([AllPhp.ByteValues.PhpBytes]::FromBytes([byte[]]$nativeResult.Output)) }
            }
            foreach ($event in $nativeResult.DiagnosticEvents) {
                if (-not $event.Delivered) { Write-PhpDiagnostic ([long]$event.Level) $event.Message }
            }
            if (-not $nativeResult.Ok) {
                if ($nativeResult.Status -lt 0 -or $nativeResult.ErrorClass -ceq 'ALLNativeUnsupported') {
                    Throw-PhpNativeUnsupportedBytes $nativeResult.ErrorMessage
                }
                Throw-PhpError ([string]$nativeResult.ErrorClass) $nativeResult.ErrorMessage
            }
            return (ConvertTo-PhpOwnedValue $nativeResult.Value)
        }

        if ($isCli -and ($CliContext.Keys -contains 'SourcePath') -and
            -not [string]::IsNullOrEmpty([string]$CliContext['SourcePath'])) {
            $state.ScriptName = [string]$CliContext['SourcePath']
        }
        # Unforgeable within PHP: exit is a host control signal, never Throwable.
        $cliExitToken = [object]::new()
        function Test-PhpCliExit($errorRecord) {
            $ex = $errorRecord.Exception
            while ($null -ne $ex) {
                if ($ex.Data.Contains('AllPhpCliExit') -and
                    [object]::ReferenceEquals($ex.Data['AllPhpCliExit'], $cliExitToken)) { return $true }
                $ex = $ex.InnerException
            }
            return $false
        }


        # Predefined constants. PHP_EOL is CRLF because the compatibility target is PHP on Windows.
        $phpConstants = [System.Collections.Generic.Dictionary[string,object]]::new(
            [AllPhp.ValidTextSymbols.Comparers]::Constant)
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
        $phpBuiltinNames = [System.Collections.Generic.HashSet[string]]::new([AllPhp.ValidTextSymbols.Comparers]::Ascii)
        foreach ($builtinName in @(
            'bin2hex','json_encode','json_decode','json_last_error','json_last_error_msg','count','strlen',
            'strtoupper','strtolower','trim','abs','array_sum','array_key_exists','is_array',
            'is_string','is_bool','array_push','array_pop','array_shift','array_unshift',
            'array_reverse','array_merge','array_slice','array_keys','array_values',
            'array_key_first','array_key_last','array_first','array_last','in_array',
            'str_contains','str_starts_with','str_ends_with','strpos','substr','str_replace',
            'explode','implode','print_r','define','defined','constant',
            'error_reporting','ini_set','ini_get','set_error_handler','restore_error_handler',
            'set_exception_handler','restore_exception_handler','trigger_error','user_error',
            'str_repeat','function_exists','call_user_func','call_user_func_array','get_class',
            'var_dump','gettype','is_int','is_integer','is_long','is_float','is_double',
            'is_null','is_numeric','intval','floatval','doubleval','boolval','intdiv','fdiv',
            'pow','sqrt','floor','ceil','is_nan','is_infinite','is_finite','strval'
        )) { [void]$phpBuiltinNames.Add($builtinName) }
        if ($isCli) {
            [void]$phpBuiltinNames.Add('exit')
            [void]$phpBuiltinNames.Add('die')
        }

        # Tokenize before parsing. Unknown characters produce an error, never disappear.
        $pattern = '(?:[ \t\r\n]+|//[^\r\n]*|\#[^\r\n]*|/\*[\s\S]*?\*/|"(?:\\.|[^"\\])*"|''(?:\\.|[^''\\])*''|\$\$[A-Za-z_\x80-\uffff][A-Za-z_0-9\x80-\uffff]*|\$[A-Za-z_\x80-\uffff][A-Za-z_0-9\x80-\uffff]*|\$(?=\{)|0[xX][0-9a-fA-F_]+|0[bB][01_]+|0[oO][0-7_]+|(?:[0-9][0-9_]*(?:\.[0-9_]*)?|\.[0-9][0-9_]*)(?:[eE][+-]?[0-9][0-9_]*)?|\\?[A-Za-z_\x80-\uffff][A-Za-z_0-9\x80-\uffff]*(?:\\[A-Za-z_\x80-\uffff][A-Za-z_0-9\x80-\uffff]*)*\\?|<=>|::|\.\.\.|<<=|>>=|<<|>>|===|!==|==|!=|<=|>=|&&|\|\||=>|->|\*\*=|\*\*|\?\?=|\?\?|\?->|\+\+|--|\*=|/=|%=|&=|\|=|\^=|\+=|-=|\.=|[+\-*/%.=<>!?:;{},()\[\]&|^~@])'
        $rx = [regex]::new($pattern)
        $phpLiteralUtf8 = [Text.UTF8Encoding]::new($false,$true)
        function Throw-PhpLiteralParseError([string]$message,[long]$line) {
            if ($isCli) {
                $CliContext['CompileError']=[pscustomobject]@{
                    Type='ParseError'; Reason='string_literal'; Message=$message
                    SourcePath=$state.ScriptName; Line=$line
                }
            }
            throw ('ALL PHP: '+$message)
        }
        function Add-PhpLiteralText($bytes,[string]$text) {
            foreach ($b in $phpLiteralUtf8.GetBytes($text)) { [void]$bytes.Add($b) }
        }
        function Read-PhpDocToken([string]$text,[int]$offset,[long]$line) {
            $start=$offset
            if ($offset -ge $text.Length) { return $null }
            if (($text[$offset] -ceq 'b' -or $text[$offset] -ceq 'B') -and $offset+1 -lt $text.Length) {
                if ($text[$offset+1] -ceq '"' -or $text[$offset+1] -ceq "'") {
                    $quoted=$rx.Match($text,$offset+1)
                    if ($quoted.Success -and $quoted.Index -eq $offset+1) {
                        return [pscustomobject]@{Token=$quoted.Value;Length=$quoted.Length+1;Newlines=[regex]::Matches($quoted.Value,"`r`n|`r|`n").Count}
                    }
                }
                $offset++
            }
            if ($offset+3 -gt $text.Length -or $text.Substring($offset,3) -cne '<<<') { return $null }
            $headerRx=[regex]::new('\G<<<[ \t]*(?:''(?<nowdoc>[A-Za-z_\x80-\uffff][A-Za-z_0-9\x80-\uffff]*)''|"(?<quoted>[A-Za-z_\x80-\uffff][A-Za-z_0-9\x80-\uffff]*)"|(?<bare>[A-Za-z_\x80-\uffff][A-Za-z_0-9\x80-\uffff]*))(?:\r\n|\n|\r)')
            $header=$headerRx.Match($text,$offset)
            if (-not $header.Success -or $header.Index -ne $offset) { return $null }
            $nowdoc=$header.Groups['nowdoc'].Success
            $label=if($nowdoc){$header.Groups['nowdoc'].Value}elseif($header.Groups['quoted'].Success){$header.Groups['quoted'].Value}else{$header.Groups['bare'].Value}
            $bodyStart=$offset+$header.Length
            $closingRx=[regex]::new('^(?<indent>[ \t]*)'+[regex]::Escape($label)+'(?![A-Za-z_0-9\x80-\uffff])')
            $position=$bodyStart;$closing=$null;$closingLine=$line+1
            while ($position -le $text.Length) {
                $end=$text.IndexOfAny([char[]]@([char]13,[char]10),$position)
                if ($end -lt 0) { $end=$text.Length }
                $closing=$closingRx.Match($text.Substring($position,$end-$position))
                if ($closing.Success) { break }
                if ($end -eq $text.Length) { $closing=$null;break }
                $position=$end+1
                if ($text[$end] -ceq [char]13 -and $position -lt $text.Length -and $text[$position] -ceq [char]10) { $position++ }
                $closingLine++
            }
            if ($null -eq $closing) { throw 'ALL PHP: Unterminated heredoc/nowdoc literal' }
            $indent=$closing.Groups['indent'].Value
            $body=$text.Substring($bodyStart,$position-$bodyStart)
            if ($indent.Contains(' ') -and $indent.Contains("`t")) {
                # The PHP scanner detects this before committing the current
                # text token's newline count. Interpolations commit earlier
                # segments; nowdoc and a plain heredoc stay at body-start line.
                $errorLine=$line+1;$lastInterpolation=-1
                if(-not$nowdoc) {
                    for($k=0;$k-lt$body.Length;$k++) {
                        if($body[$k]-ceq'\'){$k++;continue}
                        if($body[$k]-ceq'$'-and$k+1-lt$body.Length-and[string]$body[$k+1]-cmatch'[A-Za-z_\x80-\uffff{]') {
                            $lastInterpolation=$k
                            $errorLine=$line+1+[regex]::Matches($body.Substring(0,$k),"`r`n|`r|`n").Count
                        }
                    }
                }
                if($lastInterpolation-ge0) {
                    # Earlier literal segments are indentation-checked before
                    # the scanner reaches the malformed closing marker. A
                    # mixed closing prefix selects the tab indentation branch.
                    $prefixLines=[regex]::Split($body.Substring(0,$lastInterpolation+1),"`r`n|`r|`n")
                    for($partIndex=0;$partIndex-lt$prefixLines.Length;$partIndex++) {
                        $prefixLine=$prefixLines[$partIndex]
                        for($column=0;$column-lt$indent.Length-and$column-lt$prefixLine.Length;$column++) {
                            if($prefixLine[$column]-cne' '-and$prefixLine[$column]-cne[char]9) {
                                Throw-PhpLiteralParseError ('Invalid body indentation level (expecting an indentation level of at least '+$indent.Length+')') ($line+1+$partIndex)
                            }
                            if($prefixLine[$column]-cne[char]9) {
                                Throw-PhpLiteralParseError 'Invalid indentation - tabs and spaces cannot be mixed' ($line+1+$partIndex)
                            }
                        }
                    }
                }
                Throw-PhpLiteralParseError 'Invalid indentation - tabs and spaces cannot be mixed' $errorLine
            }
            if ($body.EndsWith("`r`n")) { $body=$body.Substring(0,$body.Length-2) }
            elseif ($body.EndsWith("`r") -or $body.EndsWith("`n")) { $body=$body.Substring(0,$body.Length-1) }
            if ($indent.Length -gt 0) {
                $clean=[Text.StringBuilder]::new();$bodyPosition=0;$bodyLine=$line+1
                while ($bodyPosition -lt $body.Length) {
                    $end=$body.IndexOfAny([char[]]@([char]13,[char]10),$bodyPosition)
                    if ($end -lt 0) { $end=$body.Length }
                    $part=$body.Substring($bodyPosition,$end-$bodyPosition);$skip=0
                    while ($skip -lt $indent.Length -and $skip -lt $part.Length) {
                        if ($part[$skip] -cne ' ' -and $part[$skip] -cne [char]9) {
                            Throw-PhpLiteralParseError ('Invalid body indentation level (expecting an indentation level of at least '+$indent.Length+')') $bodyLine
                        }
                        if ($part[$skip] -cne $indent[0]) { Throw-PhpLiteralParseError 'Invalid indentation - tabs and spaces cannot be mixed' $bodyLine }
                        $skip++
                    }
                    [void]$clean.Append($part.Substring($skip))
                    if ($end -lt $body.Length) {
                        [void]$clean.Append($body[$end]);$end++
                        if ($body[$end-1] -ceq [char]13 -and $end -lt $body.Length -and $body[$end] -ceq [char]10) { [void]$clean.Append($body[$end]);$end++ }
                    }
                    $bodyPosition=$end;$bodyLine++
                }
                $body=$clean.ToString()
            }
            $id=[string][char]29+'DOC:'+$state.DocStrings.Count
            $state.DocStrings[$id]=[pscustomobject]@{Body=$body;Nowdoc=$nowdoc;BodyLine=$line+1}
            $length=$position+$closing.Length-$start
            return [pscustomobject]@{Token=$id;Length=$length;Newlines=[regex]::Matches($text.Substring($start,$length),"`r`n|`r|`n").Count}
        }
        function ConvertTo-PhpTokens([string]$text, $tokens, $lines,
            [bool]$FileMode=$false, [bool]$StartsInPhp=$true) {
            $line = 1
            $insidePhp = $StartsInPhp
            $tokenRx = $rx
            $openRx = $null
            if ($FileMode) {
                $openPattern = '<\?(?:php(?=[ \t\r\n]|$)|=)'
                if ($isCli -and ($CliContext.Keys -contains 'InitialIni') -and
                    ($CliContext['InitialIni'].Keys -contains 'short_open_tag') -and
                    $CliContext['InitialIni']['short_open_tag'] -ceq '1') {
                    $openPattern = '<\?(?:php(?=[ \t\r\n]|$)|=)?'
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
                $doc = Read-PhpDocToken $text $offset $line
                if ($null -ne $doc) {
                    [void]$tokens.Add($doc.Token);[void]$lines.Add($line)
                    $offset += $doc.Length;$line += $doc.Newlines
                    continue
                }
                $match = $tokenRx.Match($text, $offset)
                if (-not $match.Success -or $match.Index -ne $offset) {
                    throw "ALL PHP: Unknown character at offset $offset"
                }
                $token = $match.Value
                if ($token -cnotmatch '^[ \t\r\n]+$' -and
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
        # ---- Namespaces -------------------------------------------------------------------------
        # Names are resolved once, on the token stream, before parsing: "namespace" and "use"
        # statements are consumed and every class, function and constant name is rewritten to its
        # fully qualified form without a leading backslash (the form PHP itself reports).
        $phpNameRx = [regex]::new('^\\?[A-Za-z_\x80-\uffff][A-Za-z_0-9\x80-\uffff]*(?:\\[A-Za-z_\x80-\uffff][A-Za-z_0-9\x80-\uffff]*)*\\?$')
        $phpReservedNames = [System.Collections.Generic.HashSet[string]]::new(
            [AllPhp.ValidTextSymbols.Comparers]::Ascii)
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
            $declFunctions = [System.Collections.Generic.HashSet[string]]::new([AllPhp.ValidTextSymbols.Comparers]::Ascii)
            $declConsts = [System.Collections.Generic.HashSet[string]]::new([AllPhp.ValidTextSymbols.Comparers]::Constant)
            $outTokens = [System.Collections.Generic.List[string]]::new()
            $outLines = [System.Collections.Generic.List[int]]::new()
            $outFallbacks = [System.Collections.Generic.Dictionary[int,string]]::new()
            foreach ($pass in 1, 2) {
                $seenNamespace = $false
                $ns = ''
                $depth = 0
                $classStack = [System.Collections.Generic.Stack[int]]::new()
                $nsStack = [System.Collections.Generic.Stack[int]]::new()
                $pendingClass = $false
                $classList = $false
                $useClass = [System.Collections.Generic.Dictionary[string,string]]::new([AllPhp.ValidTextSymbols.Comparers]::Ascii)
                $useFunc = [System.Collections.Generic.Dictionary[string,string]]::new([AllPhp.ValidTextSymbols.Comparers]::Ascii)
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
                        $lower = (ConvertTo-PhpAsciiLower $t)
                        # Reserved words are legal as constant, method and member names ("const USE",
                        # "function namespace()", "namespace as bar"); in those positions they are plain names.
                        $isMember = ($prev -ceq '->' -or $prev -ceq '?->' -or $prev -ceq '::')
                        $plainName = ($prev -ieq 'const' -or $prev -ieq 'function' -or $prev -ieq 'as' -or
                            $prev -ieq 'case' -or ($inClass -and ($next -ieq 'as' -or $next -ieq 'insteadof')))
                        $startsStatement = ($prev -ceq '' -or $prev -ceq ';' -or $prev -ceq '{' -or $prev -ceq '}' -or $state.InlineHtml.ContainsKey($prev))
                        if (-not $isMember -and -not $plainName -and $startsStatement -and
                            $lower -ceq 'namespace' -and $next -cne '(') {
                            # namespace A\B;   namespace A\B { ... }   namespace { ... }
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
                            # PHP attributes the entire import list to its first target token.
                            $importLine = [long]$lines[$j]
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
                                $imports = if ($itemKind -eq 'function') { $useFunc }
                                    elseif ($itemKind -eq 'const') { $useConst } else { $useClass }
                                if ($imports.ContainsKey($alias)) {
                                    $label = if ($itemKind -eq 'class') { '' } else { $itemKind + ' ' }
                                    $message = 'Cannot use ' + $label + $target + ' as ' + $alias +
                                        ' because the name is already in use'
                                    if ($isCli) {
                                        $CliContext['CompileError'] = [pscustomobject]@{
                                            Type='CompileError'; Reason='duplicate_import'; ImportKind=$itemKind
                                            Target=$target; Alias=$alias; Message=$message
                                            SourcePath=$state.ScriptName; Line=$importLine
                                        }
                                    }
                                    throw ('ALL PHP: ' + $message)
                                }
                                $imports[$alias] = $target
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
        try {
        if ($isCli -and ($CliContext.Keys -contains 'SourceMode') -and
            $CliContext['SourceMode'] -in @('body','file','stdin')) {
            ConvertTo-PhpTokens $source $state.Tokens $state.TokenLines $true ($CliContext['SourceMode'] -ceq 'body')
        } else { ConvertTo-PhpTokens $source $state.Tokens $state.TokenLines }
        }
        catch {
            if (-not $isCli -or -not ($CliContext.Keys -contains 'CompileError')) { throw }
            $literalError=$CliContext['CompileError']
            [Console]::Error.Write('Parse error: '+$literalError.Message+' in '+$literalError.SourcePath+' on line '+$literalError.Line+"`n")
            $CliContext['ExitCode']=[long]255;$CliContext['Terminated']=$true;$CliContext['TerminationReason']='compile_error'
            return
        }
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
            try { $resolvedNames = Resolve-PhpNamespaceTokens $state.Tokens $state.TokenLines }
            catch {
                if (-not $isCli -or -not ($CliContext.Keys -contains 'CompileError')) { throw }
                $compileError = $CliContext['CompileError']
                [Console]::Error.Write('Fatal error: ' + $compileError.Message + ' in ' +
                    $compileError.SourcePath + ' on line ' + $compileError.Line +
                    "`nStack trace:`n#0 {main}`n")
                $CliContext['ExitCode'] = [long]255
                $CliContext['Terminated'] = $true
                $CliContext['TerminationReason'] = 'compile_error'
                return
            }
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
            if ((-not (Test-PhpNameEqual (Peek-Token) $expected))) {
                $unexpected = Peek-Token
                if ($isCli -and $expected -ceq ';' -and $unexpected.Length -ge 2 -and
                    ($unexpected.StartsWith("'") -or $unexpected.StartsWith('"'))) {
                    $tokenKind = if ($unexpected.StartsWith("'")) { 'single-quoted string' } else { 'double-quoted string' }
                    $tokenContent = $unexpected.Substring(1, $unexpected.Length - 2)
                    $message = 'syntax error, unexpected ' + $tokenKind + ' "' + $tokenContent + '"'
                    $info = [pscustomobject]@{
                        Type='ParseError'; TokenKind=$tokenKind; TokenContent=$tokenContent
                        Message=$message; SourcePath=$state.ScriptName
                        Line=[long]$state.TokenLines[$state.Pos]
                    }
                    $CliContext['CompileError'] = $info
                    $compileSignal = [System.Exception]::new('ALL PHP: structured compilation error')
                    $compileSignal.Data['AllPhpCompileError'] = $info
                    throw $compileSignal
                }
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
            return [AllPhp.ByteValues.PhpBytes]::FromUtf8($sb.ToString())
        }
        function Expand-PhpDoubleString([string]$token,[bool]$IsBody=$false,[bool]$Heredoc=$false,[bool]$ValidateOnly=$false,[long]$LineBase=0) {
            $body=if($IsBody){$token}else{$token.Substring(1,$token.Length-2)}
            $output=[Collections.Generic.List[byte]]::new()
            if($LineBase-le0){$LineBase=[long]$state.Line}
            for($i=0;$i-lt$body.Length;$i++) {
                $ch=$body[$i]
                if($ch-ceq'\') {
                    if($i+1-ge$body.Length){[void]$output.Add([byte]92);continue}
                    $next=$body[$i+1]
                    if($next-ceq'x'-or$next-ceq'X') {
                        $hex='';$j=$i+2
                        while($j-lt$body.Length-and$hex.Length-lt2-and[string]$body[$j]-cmatch'^[0-9A-Fa-f]$'){$hex+=$body[$j];$j++}
                        if($hex.Length-gt0){[void]$output.Add([Convert]::ToByte($hex,16));$i=$j-1;continue}
                    }
                    if([string]$next-cmatch'^[0-7]$') {
                        $octal='';$j=$i+1
                        while($j-lt$body.Length-and$octal.Length-lt3-and[string]$body[$j]-cmatch'^[0-7]$'){$octal+=$body[$j];$j++}
                        $value=[Convert]::ToInt32($octal,8)
                        if($value-gt255-and$ValidateOnly){
                            [void]$state.LiteralWarnings.Add([pscustomobject]@{Level=[long]2;Message=('Octal escape sequence overflow \'+$octal+' is greater than \377');Line=($LineBase+[regex]::Matches($body.Substring(0,$i),"`r`n|`r|`n").Count)})
                        }
                        [void]$output.Add([byte]($value-band255));$i=$j-1;continue
                    }
                    if($next-ceq'u'-and$i+2-lt$body.Length-and$body[$i+2]-ceq'{') {
                        $end=$body.IndexOf('}',$i+3)
                        $errorLine=$LineBase+[regex]::Matches($body.Substring(0,$i),"`r`n|`r|`n").Count
                        if($end-lt0){Throw-PhpLiteralParseError 'Invalid UTF-8 codepoint escape sequence' $errorLine}
                        $hex=$body.Substring($i+3,$end-$i-3)
                        if($hex-cnotmatch'\A[0-9A-Fa-f]+\z'){Throw-PhpLiteralParseError 'Invalid UTF-8 codepoint escape sequence' $errorLine}
                        $point=[long]0
                        foreach($digit in $hex.ToCharArray()) {
                            if($point-le0x10ffff){$point=$point*16+[Convert]::ToInt32([string]$digit,16)}
                        }
                        if($point-gt0x10ffff){Throw-PhpLiteralParseError 'Invalid UTF-8 codepoint escape sequence: Codepoint too large' $errorLine}
                        if($point-ge0xd800-and$point-le0xdfff){
                            [void]$output.Add([byte](0xe0-bor($point-shr12)))
                            [void]$output.Add([byte](0x80-bor(($point-shr6)-band0x3f)))
                            [void]$output.Add([byte](0x80-bor($point-band0x3f)))
                            $i=$end;continue
                        }
                        Add-PhpLiteralText $output ([char]::ConvertFromUtf32([int]$point));$i=$end;continue
                    }
                    $recognized=$true
                    switch -CaseSensitive ([string]$next) {
                        'n' {[void]$output.Add([byte]10)}
                        'r' {[void]$output.Add([byte]13)}
                        't' {[void]$output.Add([byte]9)}
                        'v' {[void]$output.Add([byte]11)}
                        'e' {[void]$output.Add([byte]27)}
                        'f' {[void]$output.Add([byte]12)}
                        '\' {[void]$output.Add([byte]92)}
                        '"' {if($Heredoc){$recognized=$false}else{[void]$output.Add([byte]34)}}
                        '$' {[void]$output.Add([byte]36)}
                        default {$recognized=$false}
                    }
                    if($recognized){$i++;continue}
                    [void]$output.Add([byte]92);continue
                }
                # Compilation validates escape syntax but must not evaluate or
                # reject valid, presently unsupported interpolation in dead code.
                if($ValidateOnly){continue}
                if($ch-ceq'$'-and$i+1-lt$body.Length-and$body[$i+1]-ceq'{'){throw 'ALL PHP: Legacy ${...} interpolation is not implemented'}
                $braced=$false;$start=$i
                if($ch-ceq'{'-and$i+1-lt$body.Length-and$body[$i+1]-ceq'$'){$braced=$true;$start++}
                elseif($ch-cne'$') {
                    $length=1
                    if([char]::IsHighSurrogate($ch)-and$i+1-lt$body.Length-and[char]::IsLowSurrogate($body[$i+1])){$length=2}
                    Add-PhpLiteralText $output $body.Substring($i,$length);$i+=$length-1;continue
                }
                if($start+1-ge$body.Length-or-not([string]$body[$start+1]-cmatch'[A-Za-z_\x80-\uffff]')) {Add-PhpLiteralText $output ([string]$ch);continue}
                $end=$start+2
                while($end-lt$body.Length-and[string]$body[$end]-cmatch'[A-Za-z_0-9\x80-\uffff]'){$end++}
                if($braced){if($end-ge$body.Length-or$body[$end]-cne'}'){throw 'ALL PHP: Complex braced string interpolation is not implemented'}}
                elseif($end-lt$body.Length-and($body[$end]-ceq'['-or($end+1-lt$body.Length-and$body.Substring($end,2)-ceq'->'))){throw 'ALL PHP: Complex string interpolation is not implemented'}
                $name=$body.Substring($start+1,$end-$start-1)
                if(-not$ValidateOnly) {
                    $savedLine=$state.Line
                    try{
                        $state.Line=$LineBase+[regex]::Matches($body.Substring(0,$start),"`r`n|`r|`n").Count
                        $slot=Get-PhpVariableSlot $name
                        # The existing default API intentionally omits the PHP
                        # notice/warning while CLI and PhpDiagnostics expose it.
                        if($slot.Store.ContainsKey($slot.Key)-or$PhpDiagnostics-or$isCli){
                            $output.AddRange((To-PhpBytes (Get-PhpVariableValue $name)).ToArray())
                        }
                    }
                    finally{$state.Line=$savedLine}
                }
                if($braced){$i=$end}else{$i=$end-1}
            }
            if($ValidateOnly){return ''}
            return [AllPhp.ByteValues.PhpBytes]::FromBytes($output.ToArray())
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
                    if ($first -cmatch '^[A-Za-z_\x80-\uffff][A-Za-z_0-9\x80-\uffff\\]*$' -and
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
            if ($text -match '^[0-9]+$') {
                $n = [long]0
                if ([long]::TryParse($text, [System.Globalization.NumberStyles]::None, $inv, [ref]$n)) {
                    return $n
                }
                return (ConvertTo-PhpDoubleFromBigInt ([bigint]::Parse($text, $inv)))
            }
            try { return [double]::Parse($text, [System.Globalization.NumberStyles]::Float, $inv) }
            catch {
                if ($isCli -and (Test-PhpCliExit $_)) { throw } return [double]::PositiveInfinity }
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
                    $byReference=$false
                    if ((Peek-Token) -ceq '&') {
                        if ($spread) { throw 'ALL PHP: Array spread cannot be by reference' }
                        [void](Next-Token);$byReference=$true
                    }
                    $first = Read-Expr 1
                    $key = $null
                    $value = $first
                    if ((Peek-Token) -ceq '=>') {
                        if ($spread) { throw 'ALL PHP: Spread cannot have explicit key' }
                        if ($byReference) { throw 'ALL PHP: Array key cannot be a reference' }
                        [void](Next-Token)
                        $key = $first
                        if ((Peek-Token) -ceq '&') { [void](Next-Token);$byReference=$true }
                        $value = Read-Expr 1
                    }
                    [void]$entries.Add([pscustomobject]@{ Key=$key; Value=$value; Spread=$spread;ByReference=$byReference })
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
            if ($token -cmatch '^(?:[0-9]|\.[0-9])') {
                [void](Next-Token)
                return [pscustomobject]@{
                    Kind='literal'; Value=(ConvertFrom-PhpNumberLiteral $token)
                }
            }
            if ($state.DocStrings.ContainsKey($token)) {
                $doc=$state.DocStrings[$token]
                [void](Next-Token)
                if ($doc.Nowdoc) { return [pscustomobject]@{Kind='literal';Value=$doc.Body} }
                [void](Expand-PhpDoubleString $doc.Body $true $true $true $doc.BodyLine)
                return [pscustomobject]@{Kind='double_string';Raw=$doc.Body;IsBody=$true;Heredoc=$true;StringLine=$doc.BodyLine}
            }
            if ($token.StartsWith('"')) {
                $literalLine=[long]$state.TokenLines[$state.Pos]
                [void](Expand-PhpDoubleString $token $false $false $true $literalLine)
                [void](Next-Token)
                return [pscustomobject]@{ Kind='double_string'; Raw=$token;IsBody=$false;Heredoc=$false;StringLine=$literalLine }
            }
            if ($token.StartsWith("'")) {
                [void](Next-Token)
                return [pscustomobject]@{
                    Kind='literal'; Value=(Decode-PhpString $token)
                }
            }
            if ($token -cmatch '^\$\$[A-Za-z_\x80-\uffff][A-Za-z_0-9\x80-\uffff]*$') {
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
            if ($token -cmatch '^\$[A-Za-z_\x80-\uffff][A-Za-z_0-9\x80-\uffff]*$') {
                [void](Next-Token)
                return [pscustomobject]@{ Kind='variable'; Name=$token.Substring(1) }
            }
            if ((Test-PhpNameEqual $token 'match')) {
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
            if ((Test-PhpNameEqual $token 'function') -or (Test-PhpNameEqual $token 'fn')) {
                $arrow=((Test-PhpNameEqual $token 'fn'))
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
                            if ($name -cnotmatch '^\$[A-Za-z_\x80-\uffff][A-Za-z_0-9\x80-\uffff]*$') {
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
            if ((Test-PhpNameEqual $token 'throw')) {
                [void](Next-Token)
                return [pscustomobject]@{ Kind='throw'; Arg=(Read-Expr 1) }
            }
            if ((Test-PhpNameEqual $token 'new')) {
                [void](Next-Token)
                $className = Next-Token
                if ($className -cnotmatch '^[A-Za-z_\x80-\uffff][A-Za-z_0-9\x80-\uffff\\]*$') {
                    throw "ALL PHP: Expected class name, got '$className'"
                }
                $callArgs = @()
                if ((Peek-Token) -ceq '(') { $callArgs = Read-Arguments }
                return [pscustomobject]@{ Kind='new'; Name=$className; Args=@($callArgs) }
            }
            if ((Test-PhpNameEqual $token 'array')) {
                [void](Next-Token)
                Expect-Token '('
                return (Read-Array ')')
            }
            if ($isCli -and (Test-PhpNameIn $token @('exit','die')) -and
                $state.Tokens[$state.Pos + 1] -cne '(') {
                [void](Next-Token)
                return [pscustomobject]@{ Kind='cli_exit'; Args=@() }
            }
            switch ($token) {
                'true'  { [void](Next-Token); return [pscustomobject]@{ Kind='literal'; Value=$true } }
                'false' { [void](Next-Token); return [pscustomobject]@{ Kind='literal'; Value=$false } }
                'null'  { [void](Next-Token); return [pscustomobject]@{ Kind='literal'; Value=$null } }
            }
            if ($token -cmatch '^[A-Za-z_\x80-\uffff][A-Za-z_0-9\x80-\uffff\\]*$') {
                [void](Next-Token)
                if ((Test-PhpNameEqual $token 'stdClass')) {
                    return [pscustomobject]@{ Kind='class_name'; Name=$token }
                }
                if ((Peek-Token) -ceq '(') {
                    if (Take-PhpFirstClassCallableArgs) {
                        return [pscustomobject]@{
                            Kind='first_class_function'; Name=$token; Fallback=$fallbackName; ResolvedName=$null
                        }
                    }
                    $callArgs = Read-Arguments
                    # Only the engine-owned prelude can create this opcode. A
                    # user function with this spelling remains an ordinary call.
                    if ($state.ParsingInternalPrelude -and $token -ceq '__all_throwable_string') {
                        if ($callArgs.Count -ne 1) { throw 'ALL PHP: Invalid internal Throwable formatting call' }
                        return [pscustomobject]@{ Kind='internal_throwable_string'; Object=$callArgs[0] }
                    }
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
                    if ($member -cmatch '^\$[A-Za-z_\x80-\uffff][A-Za-z_0-9\x80-\uffff]*$') {
                        $expr = [pscustomobject]@{
                            Kind='static_property'; Base=$expr; Name=$member.Substring(1)
                        }
                    } elseif ($member -cmatch '^[A-Za-z_\x80-\uffff][A-Za-z_0-9\x80-\uffff\\]*$') {
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
                    if ($member -cnotmatch '^[A-Za-z_\x80-\uffff][A-Za-z_0-9\x80-\uffff\\]*$') {
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
            if ((Test-PhpNameEqual $token 'clone')) {
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
                $castType = (ConvertTo-PhpAsciiLower (Next-Token))
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
            if ((Test-PhpNameEqual $token 'function') -and
                $state.Pos + 1 -lt $state.Tokens.Count -and
                ($state.Tokens[$state.Pos + 1] -cmatch '^[A-Za-z_\x80-\uffff][A-Za-z_0-9\x80-\uffff\\]*$' -or
                 ($state.Tokens[$state.Pos + 1] -ceq '&' -and
                  $state.Pos + 2 -lt $state.Tokens.Count -and
                  $state.Tokens[$state.Pos + 2] -cmatch '^[A-Za-z_\x80-\uffff][A-Za-z_0-9\x80-\uffff\\]*$'))) {
                return (Read-Function)
            }
            if ((Test-PhpNameEqual $token 'global')) {
                [void](Next-Token)
                $names = [System.Collections.Generic.List[string]]::new()
                while ($true) {
                    $name = Next-Token
                    if ($name -cnotmatch '^\$[A-Za-z_\x80-\uffff][A-Za-z_0-9\x80-\uffff]*$') {
                        throw 'ALL PHP: Expected variable in global declaration'
                    }
                    [void]$names.Add($name.Substring(1))
                    if ((Peek-Token) -cne ',') { break }
                    [void](Next-Token)
                }
                Expect-Token ';'
                return [pscustomobject]@{ Kind='globaldecl'; Names=$names.ToArray() }
            }
            if ((Test-PhpNameEqual $token 'static')) {
                [void](Next-Token)
                $decls = [System.Collections.Generic.List[object]]::new()
                while ($true) {
                    $name = Next-Token
                    if ($name -cnotmatch '^\$[A-Za-z_\x80-\uffff][A-Za-z_0-9\x80-\uffff]*$') {
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
            if ((Test-PhpNameEqual $token 'interface')) {
                [void](Next-Token)
                $name = Next-Token
                if ($name -cnotmatch '^[A-Za-z_\x80-\uffff][A-Za-z_0-9\x80-\uffff\\]*$') {
                    throw 'ALL PHP: Expected interface name'
                }
                $parents = [System.Collections.Generic.List[string]]::new()
                if ((Peek-Token) -eq 'extends') {
                    [void](Next-Token)
                    while ($true) {
                        $parentName = Next-Token
                        if ($parentName -cnotmatch '^[A-Za-z_\x80-\uffff][A-Za-z_0-9\x80-\uffff\\]*$') {
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
                        if ($constName -cnotmatch '^[A-Za-z_\x80-\uffff][A-Za-z_0-9\x80-\uffff\\]*$') {
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
            if ((Test-PhpNameEqual $token 'enum')) {
                [void](Next-Token)
                $enumName=Next-Token
                if ($enumName -cnotmatch '^[A-Za-z_\x80-\uffff][A-Za-z_0-9\x80-\uffff\\]*$') {
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
                        if ($iface -cnotmatch '^[A-Za-z_\x80-\uffff][A-Za-z_0-9\x80-\uffff\\]*$') {
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
                        if ($caseName -cnotmatch '^[A-Za-z_\x80-\uffff][A-Za-z_0-9\x80-\uffff\\]*$') {
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
            if ((Test-PhpNameIn $token @('abstract','final','readonly','class','trait'))) {
                $isAbstract=$false
                $isFinal=$false
                $isTrait=((Test-PhpNameEqual $token 'trait'))
                $isReadonlyClass=$false
                if ((Test-PhpNameEqual $token 'readonly')) { $isReadonlyClass=$true; [void](Next-Token); Expect-Token 'class' }
                elseif ((Test-PhpNameEqual $token 'abstract')) { $isAbstract=$true; [void](Next-Token); Expect-Token 'class' }
                elseif ((Test-PhpNameEqual $token 'final')) { $isFinal=$true; [void](Next-Token); Expect-Token 'class' }
                else { [void](Next-Token) }
                $name = Next-Token
                if ($name -cnotmatch '^[A-Za-z_\x80-\uffff][A-Za-z_0-9\x80-\uffff\\]*$') {
                    throw 'ALL PHP: Expected class name'
                }
                $parent = $null
                if ((Peek-Token) -eq 'extends') {
                    [void](Next-Token)
                    $parent = Next-Token
                    if ($parent -cnotmatch '^[A-Za-z_\x80-\uffff][A-Za-z_0-9\x80-\uffff\\]*$') {
                        throw 'ALL PHP: Expected parent class name'
                    }
                }
                $interfaces=[System.Collections.Generic.List[string]]::new()
                if ((Peek-Token) -eq 'implements') {
                    [void](Next-Token)
                    while ($true) {
                        $iface = Next-Token
                        if ($iface -cnotmatch '^[A-Za-z_\x80-\uffff][A-Za-z_0-9\x80-\uffff\\]*$') {
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
                            if ($traitName -cnotmatch '^[A-Za-z_\x80-\uffff][A-Za-z_0-9\x80-\uffff\\]*$') {
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
                                if ($member -cnotmatch '^[A-Za-z_\x80-\uffff][A-Za-z_0-9\x80-\uffff\\]*$') {
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
                                        if ($loser -cnotmatch '^[A-Za-z_\x80-\uffff][A-Za-z_0-9\x80-\uffff\\]*$') {
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
                                        if ($alias -cnotmatch '^[A-Za-z_\x80-\uffff][A-Za-z_0-9\x80-\uffff\\]*$') {
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
                        if ($constName -cnotmatch '^[A-Za-z_\x80-\uffff][A-Za-z_0-9\x80-\uffff\\]*$') {
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
                            (Peek-Token) -cmatch '^[A-Za-z_\x80-\uffff][A-Za-z_0-9\x80-\uffff\\]*$') {
                            $propertyType=Read-PhpTypeAnnotation
                        }
                        if ((Peek-Token) -cnotmatch '^\$[A-Za-z_\x80-\uffff][A-Za-z_0-9\x80-\uffff]*$') {
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
                                        (Test-PhpRawNameEqual $state.Tokens[$hi + 2] $propName)) {
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
            if ((Test-PhpNameEqual $token 'switch')) {
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
            if ((Test-PhpNameEqual $token 'return')) {
                [void](Next-Token)
                $expr = $null
                if ((Peek-Token) -cne ';') { $expr = Read-Expr 1 }
                Expect-Token ';'
                return [pscustomobject]@{ Kind='return'; Expr=$expr }
            }
            if ((Test-PhpNameEqual $token 'if') -or (Test-PhpNameEqual $token 'elseif')) {
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
            if ((Test-PhpNameEqual $token 'break') -or (Test-PhpNameEqual $token 'continue')) {
                [void](Next-Token)
                Expect-Token ';'
                return [pscustomobject]@{ Kind='loopcontrol'; Action=$token }
            }
            if ((Test-PhpNameEqual $token 'for')) {
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
            if ((Test-PhpNameEqual $token 'do')) {
                [void](Next-Token)
                $body = Read-Statement
                Expect-Token 'while'
                Expect-Token '('
                $condition = Read-Expr 1
                Expect-Token ')'
                Expect-Token ';'
                return [pscustomobject]@{ Kind='do'; Test=$condition; Body=$body }
            }
            if ((Test-PhpNameEqual $token 'while')) {
                [void](Next-Token)
                Expect-Token '('
                $condition = Read-Expr 1
                Expect-Token ')'
                $body = Read-Statement
                return [pscustomobject]@{
                    Kind='while'; Test=$condition; Body=$body
                }
            }
            if ((Test-PhpNameEqual $token 'foreach')) {
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
                if ($first -cnotmatch '^\$[A-Za-z_\x80-\uffff][A-Za-z_0-9\x80-\uffff]*$') {
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
                    if ($second -cnotmatch '^\$[A-Za-z_\x80-\uffff][A-Za-z_0-9\x80-\uffff]*$') {
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
            if ((Test-PhpNameEqual $token 'const') -and $state.Pos + 2 -lt $state.Tokens.Count -and
                $state.Tokens[$state.Pos + 1] -cmatch '^[A-Za-z_\x80-\uffff][A-Za-z_0-9\x80-\uffff\\]*$' -and
                $state.Tokens[$state.Pos + 2] -ceq '=') {
                [void](Next-Token)
                $decls = [System.Collections.Generic.List[object]]::new()
                while ($true) {
                    $constName = Next-Token
                    if ($constName -cnotmatch '^[A-Za-z_\x80-\uffff][A-Za-z_0-9\x80-\uffff\\]*$') {
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
            if ((Test-PhpNameEqual $token 'try')) {
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
                        if ($typeName -cnotmatch '^[A-Za-z_\x80-\uffff][A-Za-z_0-9\x80-\uffff\\]*$') {
                            throw "ALL PHP: Expected class name in catch, got '$typeName'"
                        }
                        [void]$types.Add($typeName)
                        if ((Peek-Token) -cne '|') { break }
                        [void](Next-Token)
                    }
                    $varName = $null
                    if ((Peek-Token) -cmatch '^\$[A-Za-z_\x80-\uffff][A-Za-z_0-9\x80-\uffff]*$') {
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
            if ((Test-PhpNameEqual $token 'echo')) {
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
            if ((Test-PhpNameEqual $token 'print')) {
                [void](Next-Token)
                $expr = Read-Expr 1
                Expect-Token ';'
                return [pscustomobject]@{ Kind='print'; Expr=$expr }
            }
            $expr=Read-Expr 1
            if ($expr.Kind -ceq 'class_name') {
                # Diagnose invalid syntax before the legacy bare-constant guard.
                # The existing structured parser reports the actual next token.
                if ($isCli -and (Peek-Token) -cne ';') { Expect-Token ';' }
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
            if ($first -cnotmatch '^[A-Za-z_\x80-\uffff][A-Za-z_0-9\x80-\uffff\\]*$') {
                throw 'ALL PHP: Expected type name'
            }
            $typeText = $prefix + (Next-Token)
            while ((Peek-Token) -in @('|','&')) {
                $separator = Peek-Token
                if ($separator -eq '&') {
                    # An ampersand before a variable is a by-reference parameter,
                    # not an intersection type separator.
                    if ($state.Pos + 1 -ge $state.Tokens.Count -or
                        $state.Tokens[$state.Pos + 1] -cnotmatch '^[A-Za-z_\x80-\uffff][A-Za-z_0-9\x80-\uffff\\]*$') {
                        break
                    }
                }
                [void](Next-Token)
                $part = Next-Token
                if ($part -cnotmatch '^[A-Za-z_\x80-\uffff][A-Za-z_0-9\x80-\uffff\\]*$') {
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
                        (Peek-Token) -cmatch '^[A-Za-z_\x80-\uffff][A-Za-z_0-9\x80-\uffff\\]*$') {
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
                    if ($param -cnotmatch '^\$[A-Za-z_\x80-\uffff][A-Za-z_0-9\x80-\uffff]*$') {
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
                        if ((Test-PhpRawNameEqual $previous.Name $param.Substring(1))) {
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
            if ($name -cnotmatch '^[A-Za-z_\x80-\uffff][A-Za-z_0-9\x80-\uffff\\]*$') {
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
        try {
            while ((Peek-Token) -cne '(EOF)') {
                [void]$statements.Add((Read-Statement))
            }
        } catch {
                if ($isCli -and (Test-PhpCliExit $_)) { throw }
            if (-not $isCli -or -not ($CliContext.Keys -contains 'CompileError')) { throw }
            $compileError = $CliContext['CompileError']
            [Console]::Error.Write('Parse error: ' + $compileError.Message + ' in ' +
                $compileError.SourcePath + ' on line ' + $compileError.Line + "`n")
            $CliContext['ExitCode'] = [long]255
            $CliContext['Terminated'] = $true
            $CliContext['TerminationReason'] = 'compile_error'
            return
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
            [AllPhp.ValidTextSymbols.Comparers]::Ascii)
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
            if ($null -eq $script:ALLPhpPreludeAstPrivateThrowableV1) {
                $savedTokens = $state.Tokens
                $savedLines = $state.TokenLines
                $savedPos = $state.Pos
                $savedFallbacks = $state.NamespaceFallbacks
                $savedPreludeParsing = $state.ParsingInternalPrelude
                try {
                    $state.Tokens = [System.Collections.Generic.List[string]]::new()
                    $state.TokenLines = [System.Collections.Generic.List[int]]::new()
                    $state.Pos = 0
                    # The prelude is separate source. Source-token positions must never attach
                    # namespace fallback metadata to its cached AST or leak into later Runs.
                    $state.NamespaceFallbacks = [System.Collections.Generic.Dictionary[int,string]]::new()
                    $state.ParsingInternalPrelude = $true
                    ConvertTo-PhpTokens $phpPreludeSource $state.Tokens $state.TokenLines
                    $nodes = [System.Collections.Generic.List[object]]::new()
                    while ((Peek-Token) -cne '(EOF)') { [void]$nodes.Add((Read-Statement)) }
                    $script:ALLPhpPreludeAstPrivateThrowableV1 = $nodes.ToArray()
                } finally {
                    $state.Tokens = $savedTokens
                    $state.TokenLines = $savedLines
                    $state.Pos = $savedPos
                    $state.NamespaceFallbacks = $savedFallbacks
                    $state.ParsingInternalPrelude = $savedPreludeParsing
                }
            }
            $savedLine = $state.Line
            $savedSteps = $state.Steps
            foreach ($node in $script:ALLPhpPreludeAstPrivateThrowableV1) { Invoke-PhpStatement $node }
            $state.Line = $savedLine
            $state.Steps = $savedSteps
        }
        function Get-PhpDiagnosticStringLimit {
            $limit=[long]15
            if ($state.Ini.ContainsKey('zend.exception_string_param_max_len')) {
                $configured=Get-PhpHostText (To-PhpBytes $state.Ini['zend.exception_string_param_max_len'])
                $parsed=[long]0
                if ([long]::TryParse($configured,[Globalization.NumberStyles]::Integer,[Globalization.CultureInfo]::InvariantCulture,[ref]$parsed) -and $parsed -ge 0) { $limit=$parsed }
            }
            return $limit
        }
        function Format-PhpDiagnosticString($value,[long]$limit) {
            $bytes=To-PhpBytes $value
            $take=[Math]::Min($bytes.LongLength,$limit)
            $text=[Text.StringBuilder]::new()
            [void]$text.Append("'")
            for($offset=[long]0;$offset-lt$take;$offset++) {
                $byte=$bytes.GetByte($offset)
                switch([int]$byte) {
                    9 { [void]$text.Append('\t') }
                    10 { [void]$text.Append('\n') }
                    11 { [void]$text.Append('\v') }
                    12 { [void]$text.Append('\f') }
                    13 { [void]$text.Append('\r') }
                    27 { [void]$text.Append('\e') }
                    92 { [void]$text.Append('\\') }
                    default {
                        if($byte-lt32-or$byte-ge127) { [void]$text.Append('\x'+$byte.ToString('X2',[Globalization.CultureInfo]::InvariantCulture)) }
                        else { [void]$text.Append([char]$byte) }
                    }
                }
            }
            if($bytes.LongLength-gt$take) { [void]$text.Append('...') }
            [void]$text.Append("'")
            return $text.ToString()
        }
        function Format-PhpTraceArgument($value) {
            if ($null -ne $value -and $value.PSObject.Properties['PhpType'] -and
                $value.PhpType -ceq 'named_argument') { $value = $value.Value }
            if (Is-PhpRefCell $value) { $value = $value.Value }
            if ($null -eq $value) { return 'NULL' }
            if ($value -is [bool]) { if ($value) { return 'true' }; return 'false' }
            if ($value -is [long]) { return $value.ToString([System.Globalization.CultureInfo]::InvariantCulture) }
            if ($value -is [double]) { return (Format-PhpFloat $value 0) }
            if (Is-PhpStringValue $value) { return (Format-PhpDiagnosticString $value (Get-PhpDiagnosticStringLimit)) }
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
                $includeArguments=$true
                if($state.Ini.ContainsKey('zend.exception_ignore_args')) {
                    $setting=ConvertTo-PhpAsciiLower (Get-PhpHostText (To-PhpBytes $state.Ini['zend.exception_ignore_args']))
                    $includeArguments=$setting -cin @('','0','off','false','no','none')
                }
                if($includeArguments) { foreach ($item in $frame.Args) { [void]$parts.Add((Format-PhpTraceArgument $item)) } }
                [void]$sb.Append('#' + $index + ' ' + $state.ScriptName + '(' + $frame.Line + '): ' +
                    $frame.Name + '(' + [string]::Join(', ', $parts.ToArray()) + ")`n")
                $index++
            }
            [void]$sb.Append('#' + $index + ' {main}')
            return $sb.ToString()
        }
        # Called for every freshly created object: Throwables remember where they were created.
        function Initialize-PhpThrowable($object) {
            $object.Props['file'] = To-PhpBytes $state.ScriptName
            $object.Props['line'] = [long]$state.Line
            $object.Props['__trace'] = To-PhpBytes (Format-PhpStackTrace)
        }
        function Get-PhpThrowableString($object) {
            $builder=[AllPhp.ByteValues.PhpByteBuilder]::new()
            $previous=$object.Props['previous']
            if (Is-PhpObject $previous) {
                $builder.Append((Get-PhpThrowableString $previous))
                $builder.AppendUtf8("`n`nNext ")
            }
            $builder.AppendUtf8($object.Class+': ')
            $builder.Append((To-PhpBytes $object.Props['message']))
            $builder.AppendUtf8(' in ');$builder.Append((To-PhpBytes $object.Props['file']))
            $builder.AppendUtf8(':');$builder.Append((To-PhpBytes $object.Props['line']))
            $builder.AppendUtf8("`nStack trace:`n")
            $builder.Append((To-PhpBytes $object.Props['__trace']))
            return $builder.ToPhpBytes()
        }
        # A thrown PHP object travels inside a .NET exception. The message is what a caller that does
        # not understand PHP exceptions sees (and what the legacy regression fixtures match on).
        function Throw-PhpObject($object, [string]$legacyText = '') {
            if ($legacyText.Length -eq 0) {
                $carrierMessage=To-PhpBytes $object.Props['message']
                $carrierText=$null
                if ($carrierMessage.TryDecodeUtf8([ref]$carrierText)) {
                    $legacyText='ALL PHP: Uncaught '+$object.Class+': '+$carrierText
                } else {
                    # The raw PHP message is kept on the PHP object. This is
                    # only a host control carrier and never rendered to PHP.
                    $legacyText='ALL PHP: Uncaught '+$object.Class+' (raw PHP message retained)'
                }
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
        function Throw-PhpError([string]$className, $message, [string]$legacyText = '') {
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
            if (Is-PhpStringValue $value) {
                $limit=Get-PhpDiagnosticStringLimit
                if($limit-eq0) { return 'of type string' }
                return (Format-PhpDiagnosticString $value $limit)
            }
            if (Is-PhpObject $value) { return ('of type ' + $value.Class) }
            return 'of type array'
        }
        function New-PhpObjectId {
            $state.ObjectSeq++
            return $state.ObjectSeq
        }
        function Throw-PhpInvalidValueCallable([string]$message, [string]$callbackReason,
            [string]$callbackFunction, [string]$legacyText='ALL PHP: Value is not callable') {
            if ($callbackFunction.Length -gt 0) {
                Throw-PhpError 'TypeError' ($callbackFunction+'(): Argument #1 ($callback) must be a valid callback, '+$callbackReason) $legacyText
            }
            Throw-PhpError 'Error' $message $legacyText
        }
        function Assert-PhpMethodValueCallable([string]$className, [string]$methodName,
            [bool]$staticOnly, [string]$callbackFunction) {
            if ($className.StartsWith([string][char]92)) { $className=$className.Substring(1) }
            $className=Resolve-PhpClass $className
            if ($phpPreludeTriggers.Contains($className)) { Ensure-PhpPrelude }
            if ($className -ine 'stdClass' -and -not $state.Classes.ContainsKey($className)) {
                Throw-PhpInvalidValueCallable ('Class "'+$className+'" not found') ('class "'+$className+'" not found') $callbackFunction
            }
            $method=Find-OptionalPhpMethod $className $methodName
            if ($null -eq $method) {
                Throw-PhpInvalidValueCallable ('Call to undefined method '+$className+'::'+$methodName+'()') ('class '+$className+' does not have a method "'+$methodName+'"') $callbackFunction
            }
            try { Assert-PhpVisibility $method.Visibility $method.Owner }
            catch {
                if ($_.Exception.Message -notlike 'ALL PHP: Cannot access*') { throw }
                $scope=if ($null -eq $state.ClassContext) { 'global scope' } else { 'scope '+$state.ClassContext }
                Throw-PhpInvalidValueCallable ('Call to '+$method.Visibility+' method '+$method.Owner+'::'+$method.Name+'() from '+$scope) ('cannot access '+$method.Visibility+' method '+$method.Owner+'::'+$method.Name+'()') $callbackFunction
            }
            if ($staticOnly -and -not $method.Static) {
                Throw-PhpInvalidValueCallable ('Non-static method '+$method.Owner+'::'+$method.Name+'() cannot be called statically') ('non-static method '+$method.Owner+'::'+$method.Name+'() cannot be called statically') $callbackFunction
            }
            return $className
        }
        function Assert-PhpValueCallable($callee, [string]$callbackFunction='') {
            if (Is-PhpBytes $callee) { $callee=Get-PhpHostText $callee }
            if ($null -ne $callee -and $callee.PSObject.Properties['PhpType'] -and
                $callee.PhpType -in @('closure','first_class_callable')) { return $callee }
            if ($callee -is [string]) {
                $name=$callee
                if ($name.StartsWith([string][char]92)) { $name=$name.Substring(1) }
                $split=$name.IndexOf('::')
                if ($split -gt 0) {
                    $className=Assert-PhpMethodValueCallable $name.Substring(0,$split) $name.Substring($split+2) $true $callbackFunction
                    return ($className+'::'+$name.Substring($split+2))
                }
                if (-not $state.Functions.ContainsKey($name) -and -not $phpBuiltinNames.Contains($name) -and
                    -not (Test-PhpNativeFunction $name)) {
                    Throw-PhpInvalidValueCallable ('Call to undefined function '+$name+'()') ('function "'+$callee+'" not found or invalid function name') $callbackFunction ("ALL PHP: Undefined function '"+$callee+"'")
                }
                return $name
            }
            if (Is-PhpObject $callee) {
                if ($null -eq (Find-OptionalPhpMethod $callee.Class '__invoke')) {
                    Throw-PhpInvalidValueCallable ('Object of type '+$callee.Class+' is not callable') 'no array or string given' $callbackFunction 'ALL PHP: Object is not callable'
                }
                return $callee
            }
            if (Is-PhpArray $callee) {
                if ($callee.Items.Count -ne 2) {
                    Throw-PhpInvalidValueCallable 'Array callback must have exactly two elements' 'array callback must have exactly two members' $callbackFunction 'ALL PHP: Array is not a valid callable'
                }
                if (-not $callee.Items.Contains((New-PhpIntegerKey 0)) -or -not $callee.Items.Contains((New-PhpIntegerKey 1))) {
                    Throw-PhpInvalidValueCallable 'Array callback has to contain indices 0 and 1' 'array callback has to contain indices 0 and 1' $callbackFunction 'ALL PHP: Array is not a valid callable'
                }
                $target=Get-PhpArrayItem $callee ([long]0)
                $member=Get-PhpArrayItem $callee ([long]1)
                if (Is-PhpStringValue $target) { $target=Get-PhpHostText $target }
                if (Is-PhpStringValue $member) { $member=Get-PhpHostText $member }
                if ($target -isnot [string] -and -not (Is-PhpObject $target)) {
                    Throw-PhpInvalidValueCallable 'First array member is not a valid class name or object' 'first array member is not a valid class name or object' $callbackFunction 'ALL PHP: Array is not a valid callable'
                }
                if ($member -isnot [string]) {
                    Throw-PhpInvalidValueCallable 'Second array member is not a valid method' 'second array member is not a valid method' $callbackFunction 'ALL PHP: Array is not a valid callable'
                }
                if (Is-PhpObject $target) {
                    [void](Assert-PhpMethodValueCallable $target.Class $member $false $callbackFunction)
                } else { $target=Assert-PhpMethodValueCallable $target $member $true $callbackFunction }
                # Bind the selected array target before argument expressions can
                # mutate the source variable. Object identity is preserved.
                $bound=New-PhpArray
                Set-PhpArrayItem $bound $null $target $true
                Set-PhpArrayItem $bound $null $member $true
                return $bound
            }
            $type=if ($null -eq $callee) { 'null' } elseif ($callee -is [bool]) { 'bool' }
                elseif ($callee -is [long]) { 'int' } elseif ($callee -is [double]) { 'float' } else { 'unknown' }
            Throw-PhpInvalidValueCallable ('Value of type '+$type+' is not callable') 'no array or string given' $callbackFunction
        }
        function Get-PhpValueCallableDefinition($callee) {
            if (Is-PhpBytes $callee) { $callee=Get-PhpHostText $callee }
            if ($null -ne $callee -and $callee.PSObject.Properties['PhpType']) {
                if ($callee.PhpType -ceq 'closure') { return $callee.Definition }
                if ($callee.PhpType -ceq 'first_class_callable') {
                    if ($callee.Mode -ceq 'function' -and $state.Functions.ContainsKey($callee.Name)) { return $state.Functions[$callee.Name] }
                    if ($callee.Mode -ceq 'method') { return (Find-OptionalPhpMethod $callee.BoundThis.Class $callee.Name) }
                    if ($callee.Mode -ceq 'static') { return (Find-OptionalPhpMethod $callee.Class $callee.Name) }
                }
            }
            if (Is-PhpObject $callee) { return (Find-OptionalPhpMethod $callee.Class '__invoke') }
            if (Is-PhpArray $callee) {
                $target=Get-PhpArrayItem $callee ([long]0);$member=Get-PhpArrayItem $callee ([long]1)
                if (Is-PhpStringValue $target) { $target=Get-PhpHostText $target }
                if (Is-PhpStringValue $member) { $member=Get-PhpHostText $member }
                $className=if (Is-PhpObject $target) { $target.Class } else { [string]$target }
                return (Find-OptionalPhpMethod $className $member)
            }
            if ($callee -is [string]) {
                if ($state.Functions.ContainsKey($callee)) { return $state.Functions[$callee] }
                $split=$callee.IndexOf('::')
                if ($split -gt 0) { return (Find-OptionalPhpMethod $callee.Substring(0,$split) $callee.Substring($split+2)) }
            }
            return $null
        }
        function Get-PhpCallbackArrayArguments($array) {
            $values=[System.Collections.Generic.List[object]]::new()
            foreach ($key in $array.Items.Keys) {
                $value=$array.Items[$key]
                if (-not $key.IsInteger) {
                    [void]$values.Add([pscustomobject]@{ PhpType='named_argument';Name=(Get-PhpHostText $key.BytesValue);Value=$value })
                } else { [void]$values.Add($value) }
            }
            return ,($values.ToArray())
        }
        function Prepare-PhpCallbackValues($callee,$values) {
            $definition=Get-PhpValueCallableDefinition $callee
            if ($null -eq $definition) { return ,$values }
            $prepared=[System.Collections.Generic.List[object]]::new()
            $position=0;$index=0
            foreach ($item in $values) {
                $name=$null;$value=$item;$parameter=$null
                if ($null -ne $item -and $item.PSObject.Properties['PhpType'] -and $item.PhpType -ceq 'named_argument') {
                    $name=$item.Name;$value=$item.Value
                    foreach ($p in $definition.Params) { if ((Test-PhpRawNameEqual $p.Name $name)) { $parameter=$p;break } }
                } elseif ($position -lt $definition.Params.Count) {
                    $parameter=$definition.Params[$position]
                    if (-not $parameter.Variadic) { $position++ }
                }
                if ($null -ne $parameter -and $parameter.ByRef) {
                    if (Is-PhpRefCell $value) { $cell=$value }
                    elseif ($null -ne $value -and $value.PSObject.Properties['PhpType'] -and $value.PhpType -ceq 'refargument') { $cell=$value.Cell }
                    else {
                        $displayName=[string]$definition.Name
                        if ($definition.PSObject.Properties['Owner'] -and -not [string]::IsNullOrEmpty([string]$definition.Owner)) {
                            $displayName=$definition.Owner+'::'+$displayName
                        }
                        Write-PhpDiagnostic 2 ($displayName+'(): Argument #'+($index+1)+' ($'+$parameter.Name+') must be passed by reference, value given')
                        $cell=[pscustomobject]@{PhpType='refcell';Value=(Copy-PhpValue $value)}
                    }
                    $value=[pscustomobject]@{PhpType='refargument';Cell=$cell;Value=(Copy-PhpValue $cell.Value)}
                } elseif (Is-PhpRefCell $value) { $value=$value.Value }
                if ($null -ne $name) { $value=[pscustomobject]@{PhpType='named_argument';Name=$name;Value=$value} }
                [void]$prepared.Add($value);$index++
            }
            return ,($prepared.ToArray())
        }

        # Call a PHP callable value (closure, function name, [object, method], invokable object)
        # with already evaluated arguments.
        function Invoke-PhpValueCallable($callee, $values, [string]$callbackFunction='') {
            if (Is-PhpBytes $callee) { $callee=Get-PhpHostText $callee }
            $callee = Assert-PhpValueCallable $callee $callbackFunction
            $values = @($values)
            if ($callbackFunction.Length -gt 0) { $values=Prepare-PhpCallbackValues $callee $values }
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
                for($i=0;$i-lt$pair.Count;$i++) { if (Is-PhpStringValue $pair[$i]) { $pair[$i]=Get-PhpHostText $pair[$i] } }
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
        function Write-PhpDiagnostic([long]$level, $message) {
            $messageBytes=To-PhpBytes $message
            if ($null -ne $state.ErrorHandler -and -not $state.InErrorHandler -and
                (($state.ErrorHandlerMask -band $level) -ne 0)) {
                $handlerArgs=@($level,$messageBytes,(To-PhpBytes ([string]$state.ScriptName)),[long]$state.Line)
                # PHP supplies four actual arguments independently of the
                # user handler's declared fixed or variadic parameter count.
                $state.InErrorHandler=$true
                $handled=$null
                $savedLine=$state.Line
                try { $handled=Invoke-PhpValueCallable $state.ErrorHandler $handlerArgs }
                finally { $state.InErrorHandler=$false;$state.Line=$savedLine }
                if (-not ($handled -is [bool] -and -not $handled)) { return }
            }
            if (-not $PhpDiagnostics -and -not $isCli) { return }
            if ($state.SilenceDepth -gt 0) { return }
            if (($state.ErrorReporting -band $level) -eq 0) { return }
            $label='Warning'
            if ($level -eq 8 -or $level -eq 1024) { $label='Notice' }
            elseif ($level -eq 8192 -or $level -eq 16384) { $label='Deprecated' }
            elseif ($level -eq 256) { $label='Fatal error' }
            $builder=[AllPhp.ByteValues.PhpByteBuilder]::new()
            if (-not $isCli) { $builder.AppendUtf8("`n") }
            $builder.AppendUtf8($label+': ');$builder.Append($messageBytes)
            $builder.AppendUtf8(' in '+$state.ScriptName+' on line '+$state.Line+"`n")
            Write-PhpBytes ($builder.ToPhpBytes()) $isCli
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
                    [void]$sb.Append($pad + '    [' + (Get-PhpKeyHostText $key) + '] => ' +
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
        function Add-PhpReferenceIdentity($list, $value) {
            foreach($seen in $list){if([object]::ReferenceEquals($seen,$value)){return $false}}
            [void]$list.Add($value);return $true
        }
        function Add-PhpReferenceStore($context, $store, $globals=$null, $statics=$null) {
            if($null-eq$store -or -not(Add-PhpReferenceIdentity $context.Stores $store)){return}
            foreach($key in $store.Keys) {
                if($null-ne$globals -and $globals.Contains($key)){continue}
                if($null-ne$statics -and $statics.Contains($key)){continue}
                $context.Pending.Push($store[$key])
            }
        }
        function Get-PhpReferenceOwnerCount($context, $cell) {
            for($i=0;$i-lt$context.Cells.Count;$i++) {
                if([object]::ReferenceEquals($context.Cells[$i],$cell)){return [long]$context.Counts[$i]}
            }
            return [long]0
        }
        function New-PhpReferenceContext($additionalRoots) {
            $context=[pscustomobject]@{
                Cells=[Collections.Generic.List[object]]::new()
                Counts=[Collections.Generic.List[long]]::new()
                ExpandedCells=[Collections.Generic.List[object]]::new()
                Arrays=[Collections.Generic.List[object]]::new()
                Objects=[Collections.Generic.List[object]]::new()
                Stores=[Collections.Generic.List[object]]::new()
                Pending=[Collections.Generic.Stack[object]]::new()
                DumpArrays=[Collections.Generic.List[object]]::new()
            }
            Add-PhpReferenceStore $context $state.Globals
            Add-PhpReferenceStore $context $state.FunctionStatics
            Add-PhpReferenceStore $context $state.Vars $state.GlobalBindings $state.StaticBindings
            foreach($frame in $state.ReferenceOwnerFrames) {
                Add-PhpReferenceStore $context $frame.Vars $frame.Globals $frame.Statics
            }
            foreach($definition in $state.Classes.Values) {
                if($definition.PSObject.Properties['StaticValues']){Add-PhpReferenceStore $context $definition.StaticValues}
            }
            foreach($root in $state.ReferenceTemporaryRoots){$context.Pending.Push($root)}
            foreach($root in $additionalRoots){$context.Pending.Push($root)}
            while($context.Pending.Count-gt0) {
                $value=$context.Pending.Pop()
                if($null-eq$value){continue}
                if(Is-PhpRefCell $value) {
                    $found=$false
                    for($i=0;$i-lt$context.Cells.Count;$i++) {
                        if([object]::ReferenceEquals($context.Cells[$i],$value)){$context.Counts[$i]++;$found=$true;break}
                    }
                    if(-not$found){[void]$context.Cells.Add($value);[void]$context.Counts.Add([long]1)}
                    if(Add-PhpReferenceIdentity $context.ExpandedCells $value){$context.Pending.Push($value.Value)}
                    continue
                }
                if(Is-PhpArray $value) {
                    if(-not$value.PSObject.Properties['ReferenceBacking']){throw 'ALL PHP: missing logical array backing metadata'}
                    if(Add-PhpReferenceIdentity $context.Arrays $value.ReferenceBacking) {
                        foreach($key in $value.Items.Keys){$context.Pending.Push($value.Items[$key])}
                    }
                    continue
                }
                if(Is-PhpObject $value) {
                    if(Add-PhpReferenceIdentity $context.Objects $value){Add-PhpReferenceStore $context $value.Props}
                    continue
                }
                if($value.PSObject.Properties['PhpType'] -and $value.PhpType-ceq'closure') {
                    if(Add-PhpReferenceIdentity $context.Objects $value){Add-PhpReferenceStore $context $value.Captures}
                }
            }
            return $context
        }
        function Separate-PhpReferenceBacking($array) {
            if(-not(Is-PhpArray $array)){throw 'ALL PHP: logical backing separation requires array'}
            # Reference-free arrays can separate without traversing the live graph.
            # Every existing reference-slot writer invalidates this exact absence bit.
            if($array.ReferenceCellsKnownAbsent){$array.ReferenceBacking=[object]::new();return}
            $context=New-PhpReferenceContext @($array)
            $array.ReferenceCellsKnownAbsent=$true
            foreach($key in @($array.Items.Keys)) {
                $entry=$array.Items[$key]
                if(Is-PhpRefCell $entry) {
                    if((Get-PhpReferenceOwnerCount $context $entry)-le1){$array.Items[$key]=Copy-PhpValue $entry.Value}
                    else{$array.ReferenceCellsKnownAbsent=$false}
                }
            }
            $array.ReferenceBacking=[object]::new()
        }
        function Add-PhpReferenceArgumentRoot($value) {
            if($null-ne$value -and $value.PSObject.Properties['PhpType']) {
                if($value.PhpType-ceq'named_argument'){Add-PhpReferenceArgumentRoot $value.Value;return}
                if($value.PhpType-ceq'refargument'){[void]$state.ReferenceTemporaryRoots.Add($value.Cell);return}
            }
            [void]$state.ReferenceTemporaryRoots.Add($value)
        }
        function Remove-PhpReferenceTemporaryRoots([int]$start) {
            if($start-lt0 -or $start-gt$state.ReferenceTemporaryRoots.Count){throw 'ALL PHP: reference temporary lifetime mismatch'}
            if($state.ReferenceTemporaryRoots.Count-gt$start){$state.ReferenceTemporaryRoots.RemoveRange($start,$state.ReferenceTemporaryRoots.Count-$start)}
        }
        function New-PhpArray {
            return [pscustomobject]@{
                PhpType='array'
                ReferenceBacking=[object]::new()
                ReferenceCellsKnownAbsent=$true
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
            if (-not (Is-PhpArray $value)) { return (ConvertTo-PhpOwnedValue $value) }
            if ($depth -ge 64) {
                throw 'ALL PHP: Array nesting exceeds supported copy depth (64)'
            }
            $copy = New-PhpArray
            # Clone directly to preserve insertion order and NextIndex. Do not
            # call Set-PhpArrayItem, which also copies incoming array values.
            foreach ($key in $value.Items.Keys) {
                $copy.Items[$key] = Copy-PhpValue $value.Items[$key] ($depth + 1)
            }
            $copy.ReferenceBacking=$value.ReferenceBacking
            $copy.ReferenceCellsKnownAbsent=$value.ReferenceCellsKnownAbsent
            $copy.NextIndex = $value.NextIndex
            return $copy
        }
        function Get-PhpVariableSlot([string]$name) {
            # CLI-provided server data is a superglobal, including inside user
            # function frames. Existing non-host runs retain their prior setup.
            if ($name -ceq '_SERVER' -and $state.Globals.ContainsKey('_SERVER')) {
                return [pscustomobject]@{ Store=$state.Globals; Key=$name }
            }
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
                if (($PhpDiagnostics -or $isCli) -and $state.QuietDepth -eq 0) {
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
                if ($isCli -and (Test-PhpCliExit $_)) { throw }
                        if ($_.Exception.Message -notlike 'ALL PHP: Undefined variable*') { throw }
                    }
                    finally { $state.QuietDepth-- }
                    if ($null -eq $baseValue) { Set-PhpVariableValue $baseName (New-PhpArray) }
                }
                $array=Invoke-PhpExpr $node.Base
                if (Is-PhpStringValue $array) { Throw-PhpError 'Error' 'Cannot create references to/from string offsets' }
                if (-not (Is-PhpArray $array)) { throw 'ALL PHP: Reference index requires array' }
                Separate-PhpReferenceBacking $array
                if ($null -eq $node.Key) {
                    $key=New-PhpIntegerKey $array.NextIndex
                    $array.NextIndex++
                } else {
                    $key=To-PhpKey (Invoke-PhpExpr $node.Key)
                    if ($key.IsInteger) {
                        $numeric=[long]$key.IntegerValue
                        if ($numeric -ge $array.NextIndex) { $array.NextIndex=$numeric+1 }
                    }
                }
                return [pscustomobject]@{ Store=$array.Items; Key=$key; ReferenceArray=$array }
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
                $klass=Resolve-PhpClass (Get-PhpHostText (Invoke-PhpExpr $node.Base))
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
            if($slot.PSObject.Properties['ReferenceArray']){$slot.ReferenceArray.ReferenceCellsKnownAbsent=$false}
            return $cell
        }
        function Set-PhpReferenceTarget($target, $cell) {
            $referenceTargetRoot=$state.ReferenceTemporaryRoots.Count
            [void]$state.ReferenceTemporaryRoots.Add($cell)
            try {
            if (-not (Is-PhpRefCell $cell)) { throw 'ALL PHP: Internal reference cell missing' }
            $slot=Resolve-PhpLValueSlot $target
            $slot.Store[$slot.Key]=$cell
            if($slot.PSObject.Properties['ReferenceArray']){$slot.ReferenceArray.ReferenceCellsKnownAbsent=$false}
            } finally {
                Remove-PhpReferenceTemporaryRoots $referenceTargetRoot
            }
        }
        function Evaluate-PhpUserArguments($expressions, $definition) {
            $referenceArgumentsRoot=$state.ReferenceTemporaryRoots.Count
            try {
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
                        if ((Test-PhpRawNameEqual $candidate.Name $name)) { $param=$candidate; break }
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
                Add-PhpReferenceArgumentRoot $value
            }
            return ,($args.ToArray())
            } finally {
                Remove-PhpReferenceTemporaryRoots $referenceArgumentsRoot
            }
        }
        function Encode-JsonQuoted($value) {
            $raw=To-PhpBytes $value
            $decoded=$null
            if(-not$raw.TryDecodeUtf8([ref]$decoded)){Throw-PhpJsonFailure 5 'Malformed UTF-8 characters, possibly incorrectly encoded'}
            $value=$decoded
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
                if ($code -lt 32 -or $code -gt 127) {
                    [void]$sb.Append(('\u{0:x4}' -f $code))
                } else {
                    [void]$sb.Append($ch)
                }
            }
            [void]$sb.Append('"')
            return $sb.ToString()
        }
        function Throw-PhpJsonFailure([long]$code, [string]$message) {
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
            if ($value -is [bool] -or $value -is [string]) { return (ConvertTo-PhpOwnedValue $value) }
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
        function ConvertFrom-PhpNumericString($text, [bool]$leadingOnly) {
            $text = Get-PhpNumericView $text
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
                if ($isCli -and (Test-PhpCliExit $_)) { throw }
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
                try { $r = [System.Decimal]$a * [System.Decimal]$b } catch {
                if ($isCli -and (Test-PhpCliExit $_)) { throw } $r = $null }
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
                } catch {
                if ($isCli -and (Test-PhpCliExit $_)) { throw } $ok = $false }
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
                    if ((Is-PhpStringValue $value)) {
                        $parsed = ConvertFrom-PhpNumericString $value $true
                        if ($null -eq $parsed) { return [long]0 }
                        if ($parsed -is [double] -and
                            $phpLeadingNumericRx.Match((Get-PhpNumericView $value)).Groups[1].Value.IndexOfAny([char[]]'.eE') -lt 0) {
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
                    if ((Is-PhpStringValue $value)) {
                        $parsed = ConvertFrom-PhpNumericString $value $true
                        if ($null -eq $parsed) { return [double]0 }
                        if ($parsed -eq 0 -and (Get-PhpNumericView $value).TrimStart().StartsWith('-')) {
                            return ([double]0 * -1.0)
                        }
                        return [double]$parsed
                    }
                    if (Is-PhpArray $value) { if ($value.Items.Count -gt 0) { return [double]1 }; return [double]0 }
                    return [double]1
                }
                'string' { return (To-PhpBytes $value) }
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
                    $name = Get-PhpKeyHostText $key
                    if ($key.IsInteger) { [void]$sb.Append($pad + '  [' + $name + "]=>`n") }
                    else { [void]$sb.Append($pad + '  ["' + $name + "`"]=>`n") }
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
            # Explicit legacy host-text boundary. Raw PHP operations use bytes.
            # Never decode invalid data with replacement or implicit ToString().
            return (Get-PhpHostText (To-PhpBytes $value))
        }
        function To-Number($value) {
            if (Is-PhpRefCell $value) { $value=$value.Value }
            if ($value -is [long] -or $value -is [double]) { return $value }
            if ($null -eq $value) { return [long]0 }
            if ($value -is [bool]) {
                if ($value) { return [long]1 }
                return [long]0
            }
            if ((Is-PhpStringValue $value)) {
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
            if (Is-PhpStringValue $value) { return (To-PhpBytes $value).Truthy }
            if (Is-PhpArray $value) { return ($value.Items.Count -gt 0) }
            return $true
        }
        function To-PhpKey($value) {
            if (Is-PhpRefCell $value) { $value=$value.Value }
            if ($value -is [bool]) {
                if ($value) { return (New-PhpIntegerKey 1) }
                return (New-PhpIntegerKey 0)
            }
            if ($null -eq $value) { return [AllPhp.ByteValues.PhpKey]::FromString([AllPhp.ByteValues.PhpBytes]::Empty) }
            if ($value -is [long]) { return (New-PhpIntegerKey $value) }
            if ($value -is [double]) { return (New-PhpIntegerKey (To-PhpInt $value)) }
            if (Is-PhpStringValue $value) { return [AllPhp.ByteValues.PhpKey]::FromString((To-PhpBytes $value)) }
            throw 'ALL PHP: Unsupported array key type'
        }
        function Set-PhpArrayItem($array, $key, $value, [bool]$append) {
            if (-not (Is-PhpArray $array)) { throw 'ALL PHP: Index assignment requires array' }
            Separate-PhpReferenceBacking $array
            if(Is-PhpRefCell $value){$array.ReferenceCellsKnownAbsent=$false}
            if ($append) {
                $keyString = New-PhpIntegerKey $array.NextIndex
                $array.NextIndex++
            } else {
                $keyString = To-PhpKey $key
                if ($keyString.IsInteger) {
                    $intKey = [long]$keyString.IntegerValue
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
        function ConvertTo-PhpStringOffset($key) {
            if (Is-PhpRefCell $key) { $key=$key.Value }
            if ($key -is [long]) { return $key }
            if (Is-PhpStringValue $key) {
                $number=ConvertFrom-PhpNumericString $key $true
                # PHP permits integer syntax and integer-leading malformed
                # strings, but not floating syntax or integer overflow strings.
                if ($number -is [long]) {
                    $whole=ConvertFrom-PhpNumericString $key $false
                    if ($null -eq $whole -and $state.QuietDepth -eq 0) {
                        $builder=[AllPhp.ByteValues.PhpByteBuilder]::new()
                        $builder.AppendUtf8('Illegal string offset "')
                        $builder.Append((To-PhpBytes $key));$builder.AppendUtf8('"')
                        Write-PhpDiagnostic 2 ($builder.ToPhpBytes())
                    }
                    return $number
                }
                Throw-PhpError 'TypeError' 'Cannot access offset of type string on string'
            }
            if ($null -eq $key -or $key -is [bool] -or $key -is [double]) {
                if ($state.QuietDepth -eq 0) { Write-PhpDiagnostic 2 'String offset cast occurred' }
                return (To-PhpInt $key)
            }
            $type=if(Is-PhpArray $key){'array'}elseif(Is-PhpObject $key){$key.Class}else{'resource'}
            Throw-PhpError 'TypeError' ('Cannot access offset of type '+$type+' on string')
        }
        function Read-PhpStringOffset($value, $key) {
            $result=(To-PhpBytes $value).ReadOffset((ConvertTo-PhpStringOffset $key))
            if ($result.WarningLevel -gt 0 -and $state.QuietDepth -eq 0) {
                Write-PhpDiagnostic $result.WarningLevel $result.Message
            }
            return $result.Value
        }
        function Get-PhpArrayItem($array, $key) {
            if (Is-PhpStringValue $array) { return (Read-PhpStringOffset $array $key) }
            if (-not (Is-PhpArray $array)) { throw 'ALL PHP: Indexing requires array' }
            $keyString = To-PhpKey $key
            if (-not $array.Items.Contains($keyString)) {
                if($state.QuietDepth-gt0){return $null}
                if (($PhpDiagnostics -or $isCli) -and $state.QuietDepth -eq 0) {
                    $keyDiagnostic=[AllPhp.ByteValues.PhpByteBuilder]::new()
                    $keyDiagnostic.AppendUtf8('Undefined array key ')
                    if($keyString.IsInteger){$keyDiagnostic.AppendUtf8((Get-PhpKeyHostText $keyString))}
                    else{
                        $displayKey=$keyString.BytesValue
                        $nul=Find-PhpBytes $displayKey ([AllPhp.ByteValues.PhpBytes]::FromBytes([byte[]]@(0))) 0
                        if($nul-ge0){$displayKey=$displayKey.Slice(0,$nul)}
                        $keyDiagnostic.AppendUtf8('"');$keyDiagnostic.Append($displayKey);$keyDiagnostic.AppendUtf8('"')
                    }
                    Write-PhpDiagnostic 2 ($keyDiagnostic.ToPhpBytes())
                    return $null
                }
                $legacyKey = if ($keyString.IsInteger) { 'i:' + (Get-PhpKeyHostText $keyString) } else { 's:' + (Get-PhpKeyHostText $keyString) }
                throw "ALL PHP: Undefined array key '$legacyKey'"
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
                    if (-not $aKeys[$i].Equals($bKeys[$i])) { return $false }
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
                if ((-not (Test-PhpNameEqual $a.Class $b.Class)) -or $a.Props.Count -ne $b.Props.Count) {
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
                if ((Is-PhpStringValue $a) -or (Is-PhpStringValue $b)) {
                    if (-not (Is-PhpStringValue $a) -or -not (Is-PhpStringValue $b)) { return $false }
                    return (To-PhpBytes $a).Equals((To-PhpBytes $b))
                }
                if ($a.GetType() -ne $b.GetType()) { return $false }
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
            if ((Is-PhpStringValue $a) -and (Is-PhpStringValue $b)) {
                $x = ConvertFrom-PhpNumericString $a $false
                if ($null -ne $x) {
                    $y = ConvertFrom-PhpNumericString $b $false
                    if ($null -ne $y) { return (Compare-PhpNumbers $x $y) }
                }
                return (To-PhpBytes $a).CompareBinary((To-PhpBytes $b))
            }
            if (($aNum -and (Is-PhpStringValue $b)) -or ((Is-PhpStringValue $a) -and $bNum)) {
                if ((Is-PhpStringValue $a)) {
                    $x = ConvertFrom-PhpNumericString $a $false
                    if ($null -ne $x) { return (Compare-PhpNumbers $x $b) }
                } else {
                    $y = ConvertFrom-PhpNumericString $b $false
                    if ($null -ne $y) { return (Compare-PhpNumbers $a $y) }
                }
                return (To-PhpBytes $a).CompareBinary((To-PhpBytes $b))
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
            switch ((ConvertTo-PhpAsciiLower $type)) {
                'mixed' { return $true }
                'null' { return ($null -eq $value) }
                'true' { return ($value -is [bool] -and $value) }
                'false' { return ($value -is [bool] -and -not $value) }
                'bool' { return ($value -is [bool]) }
                'string' { return (Is-PhpStringValue $value) }
                'int' {
                    return ($value -is [long])
                }
                'float' { return ($value -is [double]) }
                'array' { return (Is-PhpArray $value) }
                'object' { return (Is-PhpObject $value) }
                'iterable' { return (Is-PhpArray $value) }
                'callable' {
                    if (Is-PhpStringValue $value) { $symbol=Get-PhpHostText $value;return ($state.Functions.ContainsKey($symbol) -or (Test-PhpNativeFunction $symbol)) }
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
            $value=ConvertTo-PhpOwnedValue $value
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
                    switch ((ConvertTo-PhpAsciiLower $variant)) {
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
                    if ($hasString) { return (To-PhpBytes $value) }
                    if ($hasBool) { return (Is-Truthy $value) }
                } elseif ($value -is [long]) {
                    if ($hasString) { return (To-PhpBytes $value) }
                    if ($hasBool) { return (Is-Truthy $value) }
                } elseif ((Is-PhpStringValue $value)) {
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
                    if ($hasString) { return (To-PhpBytes $value) }
                }
            }
            # Weak PHP scalar conversions for a single primitive annotation.
            if ($union.Count -eq 1 -and -not $typeName.Contains('&') -and
                $null -ne $value) {
                switch ((ConvertTo-PhpAsciiLower $typeName)) {
                    'string' {
                        if ((Is-PhpNum $value) -or $value -is [bool]) {
                            return (To-PhpBytes $value)
                        }
                    }
                    'bool' {
                        if ((Is-PhpNum $value) -or (Is-PhpStringValue $value)) {
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
                        if ((Is-PhpStringValue $value)) {
                            $parsed = ConvertFrom-PhpNumericString $value $false
                            if ($null -ne $parsed) { return (To-PhpInt $parsed) }
                        }
                    }
                    'float' {
                        if ($value -is [bool]) {
                            if ($value) { return [double]1 }
                            return [double]0
                        }
                        if ((Is-PhpStringValue $value)) {
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
                [AllPhp.ValidTextSymbols.Comparers]::Ascii)
            $resultProperties=[System.Collections.Generic.List[object]]::new()
            foreach ($use in $declaration.TraitUses) {
                $selected=[System.Collections.Generic.Dictionary[string,object]]::new(
                    [AllPhp.ValidTextSymbols.Comparers]::Ascii)
                $excluded=[System.Collections.Generic.HashSet[string]]::new(
                    [AllPhp.ValidTextSymbols.Comparers]::Ascii)
                foreach ($traitName in $use.Names) {
                    if (-not $state.Traits.ContainsKey($traitName)) {
                        throw "ALL PHP: Undefined trait '$traitName'"
                    }
                }
                foreach ($rule in $use.Adaptations) {
                    if ($rule.Kind -ne 'insteadof') { continue }
                    if ((-not (Test-PhpNameIn $rule.Trait $use.Names))) {
                        throw 'ALL PHP: Trait selection names a trait not used in this group'
                    }
                    $winner=$state.Traits[$rule.Trait]
                    $winnerMethod=@($winner.Methods | Where-Object { (Test-PhpNameEqual $_.Name $rule.Method) })
                    if ($winnerMethod.Count -eq 0) {
                        throw "ALL PHP: Trait method '$($rule.Method)' not defined"
                    }
                    foreach ($loserName in $rule.Excluded) {
                        if ((-not (Test-PhpNameIn $loserName $use.Names)) -or (Test-PhpNameEqual $loserName $rule.Trait)) {
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
                            if ((-not (Test-PhpNameEqual $rule.Method $method.Name))) { continue }
                            if ($null -ne $rule.Trait -and (-not (Test-PhpNameEqual $rule.Trait $traitName))) { continue }
                            $methodCopy.Visibility=$rule.Visibility
                        }
                        if ($resultMethods.ContainsKey($method.Name)) {
                            throw "ALL PHP: Conflicting trait method '$($method.Name)'"
                        }
                        $resultMethods[$method.Name]=$methodCopy
                    }
                    foreach ($prop in $trait.Properties) {
                        foreach ($prior in $resultProperties) {
                            if ((Test-PhpRawNameEqual $prior.Name $prop.Name)) {
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
                        if ($null -ne $rule.Trait -and (-not (Test-PhpNameEqual $rule.Trait $traitName))) { continue }
                        foreach ($method in $state.Traits[$traitName].Methods) {
                            if ((-not (Test-PhpNameEqual $method.Name $rule.Method))) { continue }
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
                    if ((Test-PhpNameEqual $prior.Name $item.Name)) { throw 'ALL PHP: Cyclic class inheritance' }
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
                [AllPhp.ValidTextSymbols.Comparers]::Ascii)
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
                        if ((Test-PhpNameEqual $iface.Name $interfaceName)) { return $true }
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
            if ((Test-PhpNameEqual $actual $target)) { return $true }
            if ($state.Classes.ContainsKey($actual) -and
                $state.Classes[$actual].PSObject.Properties['Enum'] -and
                $state.Classes[$actual].Enum) {
                if ((Test-PhpNameEqual $target 'UnitEnum')) { return $true }
                if ((Test-PhpNameEqual $target 'BackedEnum')) {
                    return ($null -ne $state.Classes[$actual].BackingType)
                }
            }
            if ($actual -eq 'stdClass') { return $false }
            foreach ($cls in (Get-PhpClassChain $actual)) {
                if ((Test-PhpNameEqual $cls.Name $target)) { return $true }
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
                if ($isCli -and (Test-PhpCliExit $_)) { throw }
                if ($_.Exception.Message -notlike 'ALL PHP: Undefined method*') { throw }
                return $null
            }
        }
        function Find-PhpProperty([string]$className, [string]$propertyName, [bool]$staticOnly) {
            foreach ($cls in (Get-PhpClassChain $className)) {
                foreach ($prop in $cls.Properties) {
                    if ((Test-PhpRawNameEqual $prop.Name $propertyName) -and [bool]$prop.Static -eq $staticOnly) {
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
            if ($visibility -eq 'private' -and (-not (Test-PhpNameEqual $state.ClassContext $owner))) {
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
            if (-not (Is-PhpStringValue $value) -and -not (Is-PhpNum $value) -and
                $value -isnot [bool]) {
                throw 'ALL PHP: Invalid dynamic variable name type'
            }
            $name=Get-PhpHostText (To-PhpBytes $value)
            if ((Test-PhpRawNameEqual $name 'this')) {
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
        # isset/empty container reads are quiet, but offset expressions are normal
        # expressions. Keep that distinction explicit rather than incrementing
        # QuietDepth around a complete dimension expression.
        function Get-PhpCliQuietPath($node) {
            $missing = [pscustomobject]@{ Found=$false; Value=$null; ShortCircuited=$false }
            if ($node.Kind -in @('variable','dynamic_variable')) {
                $name = if ($node.Kind -ceq 'variable') { $node.Name } else { Resolve-PhpDynamicVariableName $node }
                $slot = Get-PhpVariableSlot $name
                if (-not $slot.Store.ContainsKey($slot.Key)) { return $missing }
                $value = $slot.Store[$slot.Key]
                if (Is-PhpRefCell $value) { $value = $value.Value }
                return [pscustomobject]@{ Found=$true; Value=$value; ShortCircuited=$false }
            }
            if ($node.Kind -ceq 'index') {
                if ($null -eq $node.Key) { throw 'ALL PHP: Cannot read an empty [] index' }
                $container = Get-PhpCliQuietPath $node.Base
                if ($container.ShortCircuited) { return $container }
                # Evaluate even if a parent variable/offset is absent. Undefined
                # key variables, user callbacks, throws and exit retain normal
                # evaluation/diagnostic semantics, in source order.
                $key = Invoke-PhpExpr $node.Key
                if (-not $container.Found -or $null -eq $container.Value) { return $missing }
                if (-not (Is-PhpArray $container.Value)) { return $missing }
                if ((Is-PhpArray $key) -or (Is-PhpObject $key)) {
                    $type = if (Is-PhpArray $key) { 'array' } else { $key.Class }
                    Throw-PhpError 'TypeError' ('Cannot access offset of type ' + $type + ' in isset or empty')
                }
                $encoded = To-PhpKey $key
                if (-not $container.Value.Items.Contains($encoded)) { return $missing }
                $value = $container.Value.Items[$encoded]
                if (Is-PhpRefCell $value) { $value=$value.Value }
                return [pscustomobject]@{ Found=$true; Value=$value; ShortCircuited=$false }
            }
            if ($node.Kind -ceq 'property') {
                $container = Get-PhpCliQuietPath $node.Base
                if ($container.ShortCircuited) { return $container }
                if ($node.NullSafe -and $null -eq $container.Value) {
                    return [pscustomobject]@{ Found=$false; Value=$null; ShortCircuited=$true }
                }
                if (-not $container.Found -or -not (Is-PhpObject $container.Value)) { return $missing }
                # Capture the receiver once; property lookup has no remaining
                # key expression to accidentally suppress or evaluate twice.
                $property = [pscustomobject]@{
                    Kind='property'; Base=[pscustomobject]@{Kind='literal';Value=$container.Value}
                    Name=$node.Name; NullSafe=$node.NullSafe
                }
                $state.QuietDepth++
                try { $value=Get-LValue $property }
                catch {
                if ($isCli -and (Test-PhpCliExit $_)) { throw }
                    if ($_.Exception.Message -like 'ALL PHP: Undefined *' -or
                        $_.Exception.Message -like 'ALL PHP: Typed property *') { return $missing }
                    throw
                } finally { $state.QuietDepth-- }
                return [pscustomobject]@{Found=$true;Value=$value;ShortCircuited=$false}
            }
            # Function/method receivers and their argument expressions execute
            # normally. A real base exception precedes every outer offset.
            $value = Invoke-PhpExpr $node
            return [pscustomobject]@{Found=$true;Value=$value;ShortCircuited=$false}
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
                    if (($PhpDiagnostics -or $isCli) -and $state.QuietDepth -eq 0) {
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
        function Set-LValue($node, $value, [string]$op, $AssignmentResult=$null) {
            $hasResolvedIndexBase=$false;$resolvedIndexBase=$null
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
                if ($isCli -and (Test-PhpCliExit $_)) { throw }
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
                if ($node.Kind -ceq 'index') {
                    $resolvedIndexBase=Invoke-PhpExpr $node.Base;$hasResolvedIndexBase=$true
                    if (Is-PhpStringValue $resolvedIndexBase) {
                        Throw-PhpError 'Error' 'Cannot use assign-op operators with string offsets'
                    }
                }
                $previous = Get-LValue $node
                switch ($op) {
                    '+=' { $value = Php-Add (To-Number $previous) (To-Number $value) }
                    '-=' { $value = Php-Sub (To-Number $previous) (To-Number $value) }
                    '.=' { $value = (To-PhpBytes $previous).Concat((To-PhpBytes $value)) }
                    '*=' { $value = Php-Mul (To-Number $previous) (To-Number $value) }
                    '/=' { $value = Php-Div (To-Number $previous) (To-Number $value) }
                    '%=' { $value = Php-Mod (To-Number $previous) (To-Number $value) }
                    '&=' { if ((Is-PhpStringValue $previous) -and (Is-PhpStringValue $value)) { $value=(To-PhpBytes $previous).Bitwise((To-PhpBytes $value),[char]'&') } else { $value = [long]((To-PhpInt $previous) -band (To-PhpInt $value)) } }
                    '|=' { if ((Is-PhpStringValue $previous) -and (Is-PhpStringValue $value)) { $value=(To-PhpBytes $previous).Bitwise((To-PhpBytes $value),[char]'|') } else { $value = [long]((To-PhpInt $previous) -bor (To-PhpInt $value)) } }
                    '^=' { if ((Is-PhpStringValue $previous) -and (Is-PhpStringValue $value)) { $value=(To-PhpBytes $previous).Bitwise((To-PhpBytes $value),[char]'^') } else { $value = [long]((To-PhpInt $previous) -bxor (To-PhpInt $value)) } }
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
                if ($isCli -and (Test-PhpCliExit $_)) { throw }
                        if ($_.Exception.Message -notlike 'ALL PHP: Undefined variable*') { throw }
                    }
                    finally { $state.QuietDepth-- }
                    if ($null -eq $baseValue) {
                        Set-PhpVariableValue $baseName (New-PhpArray)
                    }
                }
                $base=if($hasResolvedIndexBase){$resolvedIndexBase}else{Invoke-PhpExpr $node.Base}
                $append = ($null -eq $node.Key)
                $key = $null
                if (-not $append) { $key = Invoke-PhpExpr $node.Key }
                if (Is-PhpStringValue $base) {
                    if ($append) { Throw-PhpError 'Error' '[] operator not supported for strings' }
                    $offset=ConvertTo-PhpStringOffset $key
                    $original=To-PhpBytes $base
                    $replacement=To-PhpBytes $value
                    $written=$original.WithOffset($offset,$replacement)
                    if ($written.ErrorClass.Length -gt 0) { Throw-PhpError $written.ErrorClass $written.Message }
                    if ($written.WarningLevel -gt 0) { Write-PhpDiagnostic $written.WarningLevel $written.Message }
                    Set-LValue $node.Base $written.Value '='
                    if ($null -ne $AssignmentResult) {
                        $AssignmentResult.IsStringOffset=$true
                        if($offset -lt 0 -and $offset -lt (-$original.Length)){$AssignmentResult.Value=$null}
                        else{$AssignmentResult.Value=$replacement.Slice(0,[long]1)}
                    }
                    return
                }
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
                        if ($null -eq $state.ClassContext -or (-not (Test-PhpNameEqual $state.ClassContext $declared.Owner))) {
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
            [void]$state.ReferenceOwnerFrames.Add([pscustomobject]@{Vars=$oldVars;Globals=$oldGlobals;Statics=$oldStatics})
            $referenceFrameRoot=$state.ReferenceTemporaryRoots.Count
            if($null-ne$closure){[void]$state.ReferenceTemporaryRoots.Add($closure)}
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
                            if ((Test-PhpRawNameEqual $param.Name $arg.Name)) { $known=$true; break }
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
                $referenceBindingRoot=$state.ReferenceTemporaryRoots.Count
                foreach($referenceArgument in $callArgs){Add-PhpReferenceArgumentRoot $referenceArgument}
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
                Remove-PhpReferenceTemporaryRoots $referenceBindingRoot
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
                            else { Separate-PhpReferenceBacking $argsArray;$argsArray.Items[$key]=$checked }
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
                Remove-PhpReferenceTemporaryRoots $referenceFrameRoot
                $state.ReferenceOwnerFrames.RemoveAt($state.ReferenceOwnerFrames.Count-1)
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
        function KeyString-ToValue($encoded) {
            return (Get-PhpKeyValue $encoded)
        }
        function Invoke-PhpCliExit($callArgs) {
            if ($callArgs.Count -gt 1) {
                Throw-PhpError 'ArgumentCountError' ('exit() expects at most 1 argument, ' + $callArgs.Count + ' given')
            }
            $status = [long]0
            if ($callArgs.Count -eq 1) {
                $argument = $callArgs[0]
                if ($null -ne $argument -and $argument.PSObject.Properties['PhpType'] -and
                    $argument.PhpType -ceq 'named_argument') {
                    if ($argument.Name -cne 'status') { Throw-PhpError 'Error' ('Unknown named parameter $' + $argument.Name) }
                    $argument = $argument.Value
                }
                if (Is-PhpRefCell $argument) { $argument = $argument.Value }
                if ($argument -is [long]) { $status = $argument }
                elseif (Is-PhpStringValue $argument) { Write-PhpBytes $argument }
                elseif ($argument -is [bool]) { if ($argument) { $status = [long]1 } }
                elseif ($null -eq $argument) {
                    Write-PhpDiagnostic 8192 'exit(): Passing null to parameter #1 ($status) of type string|int is deprecated'
                }
                elseif ($argument -is [double]) {
                    if ([double]::IsNaN($argument)) {
                        Write-PhpDiagnostic 2 'unexpected NAN value was coerced to string'
                        Write-PhpBytes 'NAN'
                    } elseif ([double]::IsInfinity($argument) -or
                        $argument -lt -9223372036854775808.0 -or $argument -ge 9223372036854775808.0) {
                        Write-PhpBytes $argument
                    } else {
                        $status = To-PhpInt $argument
                        if ([double]$status -ne $argument) {
                            Write-PhpDiagnostic 8192 ('Implicit conversion from float ' + (To-PhpText $argument) + ' to int loses precision')
                        }
                    }
                }
                elseif ((Is-PhpObject $argument) -and $null -ne (Find-OptionalPhpMethod $argument.Class '__toString')) {
                    Write-PhpBytes $argument
                } else {
                    $type = if (Is-PhpArray $argument) { 'array' } elseif (Is-PhpObject $argument) { $argument.Class } else { $argument.GetType().Name }
                    Throw-PhpError 'TypeError' ('exit(): Argument #1 ($status) must be of type string|int, ' + $type + ' given')
                }
            }
            # PHP's Windows process status is the low unsigned32 bits of zend_long.
            # The worker supplies the same bits to Environment.Exit; no reference
            # status is guessed or substituted in the worker.
            $CliContext['ExitCode'] = [long]($status -band [long]4294967295)
            $CliContext['Terminated'] = $true
            $CliContext['TerminationReason'] = 'exit'
            $signal = [System.Exception]::new('ALL PHP: private CLI exit control signal')
            $signal.Data['AllPhpCliExit'] = $cliExitToken
            throw $signal
        }
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
        function Invoke-PhpFunction([string]$name, $callArgs) {
            if ($isCli -and $name -in @('exit','die')) { Invoke-PhpCliExit $callArgs }

            if (-not $state.Functions.ContainsKey($name)) {
                foreach ($arg in $callArgs) {
                    if ($null -ne $arg -and $arg.PSObject.Properties['PhpType'] -and
                        $arg.PhpType -ceq 'named_argument') {
                        if (Test-PhpNativeFunction $name) { Throw-PhpNativeUnsupported 'named native arguments are not implemented' }
                        throw 'ALL PHP: Named arguments for builtins are not yet supported'
                    }
                }
            }
            switch ((ConvertTo-PhpAsciiLower $name)) {
                'bin2hex' {
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
                'json_encode' {
                    if ($callArgs.Count -ne 1) {
                        throw 'ALL PHP: json_encode() supports one argument; options are not implemented'
                    }
                    try {
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
                    }
                }
                'json_decode' {
                    if ($callArgs.Count -lt 1 -or $callArgs.Count -gt 2) {
                        throw 'ALL PHP: json_decode() supports one or two arguments'
                    }
                    $json=$null
                    if(-not(To-PhpBytes $callArgs[0]).TryDecodeUtf8([ref]$json)){
                        $state.JsonError=5
                        $state.JsonErrorMessage='Malformed UTF-8 characters, possibly incorrectly encoded'
                        return $null
                    }
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
                if ($isCli -and (Test-PhpCliExit $_)) { throw }
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
                    Assert-PhpStringBuiltinArity 'strlen' $callArgs 1 1
                    return [long](ConvertTo-PhpBuiltinBytes $callArgs[0] 'strlen' 1 'string').Length
                }
                'strtoupper' {
                    Assert-PhpStringBuiltinArity 'strtoupper' $callArgs 1 1
                    return (ConvertTo-PhpBuiltinBytes $callArgs[0] 'strtoupper' 1 'string').UpperAscii()
                }
                'strtolower' {
                    Assert-PhpStringBuiltinArity 'strtolower' $callArgs 1 1
                    return (ConvertTo-PhpBuiltinBytes $callArgs[0] 'strtolower' 1 'string').LowerAscii()
                }
                'trim' {
                    Assert-PhpStringBuiltinArity 'trim' $callArgs 1 2
                    $bytes=ConvertTo-PhpBuiltinBytes $callArgs[0] 'trim' 1 'string'
                    $characters=$null
                    if($callArgs.Count-eq2){$characters=ConvertTo-PhpBuiltinBytes $callArgs[1] 'trim' 2 'characters'}
                    $mask=New-PhpTrimMask $characters ($callArgs.Count-eq2)
                    return (Trim-PhpBytes $bytes $mask)
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
                    Assert-PhpStringBuiltinArity 'is_string' $callArgs 1 1
                    return (Is-PhpStringValue $callArgs[0])
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
                    Separate-PhpReferenceBacking $arr
                    if ($arr.Items.Count -eq 0) { return $null }
                    $keys = @($arr.Items.Keys)
                    $lastKey = $keys[$arr.Items.Count - 1]
                    $lastValue = $arr.Items[$lastKey]
                    $arr.Items.Remove($lastKey)
                    # PHP resets the next free index after array_pop().
                    $high = [long]-1
                    foreach ($k in $arr.Items.Keys) {
                        if ($k.IsInteger) {
                            $number = [long]$k.IntegerValue
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
                    Separate-PhpReferenceBacking $arr
                    if ($arr.Items.Count -eq 0) { return $null }
                    $keys = @($arr.Items.Keys)
                    $firstKey = $keys[0]
                    $firstValue = $arr.Items[$firstKey]
                    $arr.Items.Remove($firstKey)
                    $replacement = New-PhpArray
                    foreach ($k in $arr.Items.Keys) {
                        $v = $arr.Items[$k]
                        if ($k.IsInteger) {
                            Set-PhpArrayItem $replacement $null $v $true
                        } else {
                            Set-PhpArrayItem $replacement (Get-PhpKeyValue $k) $v $false
                        }
                    }
                    $arr.Items = $replacement.Items
                    $arr.ReferenceBacking=$replacement.ReferenceBacking
                    $arr.ReferenceCellsKnownAbsent=$replacement.ReferenceCellsKnownAbsent
                    $arr.NextIndex = $replacement.NextIndex
                    if (Is-PhpRefCell $firstValue) { return $firstValue.Value }
                    return $firstValue
                }
                'array_unshift' {
                    if ($callArgs.Count -lt 1 -or -not (Is-PhpArray $callArgs[0])) {
                        throw 'ALL PHP: array_unshift() expects an array'
                    }
                    $arr = $callArgs[0]
                    Separate-PhpReferenceBacking $arr
                    $replacement = New-PhpArray
                    for ($i=1; $i -lt $callArgs.Count; $i++) {
                        Set-PhpArrayItem $replacement $null $callArgs[$i] $true
                    }
                    foreach ($k in $arr.Items.Keys) {
                        $v = $arr.Items[$k]
                        if ($k.IsInteger) {
                            Set-PhpArrayItem $replacement $null $v $true
                        } else {
                            Set-PhpArrayItem $replacement (Get-PhpKeyValue $k) $v $false
                        }
                    }
                    $arr.Items = $replacement.Items
                    $arr.ReferenceBacking=$replacement.ReferenceBacking
                    $arr.ReferenceCellsKnownAbsent=$replacement.ReferenceCellsKnownAbsent
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
                        $k = $keys[$i]
                        $v = $callArgs[0].Items[$k]
                        if (-not $preserve -and $k.IsInteger) {
                            Set-PhpArrayItem $out $null $v $true
                        } else {
                            Set-PhpArrayItem $out (Get-PhpKeyValue $k) $v $false
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
                            if ($k.IsInteger) {
                                Set-PhpArrayItem $out $null $v $true
                            } else {
                                Set-PhpArrayItem $out (Get-PhpKeyValue $k) $v $false
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
                        $k = $keys[$i]
                        $v = $arr.Items[$k]
                        if ($k.IsInteger -and -not $preserve) {
                            Set-PhpArrayItem $out $null $v $true
                        } else {
                            Set-PhpArrayItem $out (Get-PhpKeyValue $k) $v $false
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
                        Set-PhpArrayItem $output $null (Get-PhpKeyValue $key) $true
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
                        return (Get-PhpKeyValue $key)
                    }
                    return $null
                }
                'array_key_last' {
                    if ($callArgs.Count -ne 1 -or -not (Is-PhpArray $callArgs[0])) {
                        throw 'ALL PHP: array_key_last() requires one array argument'
                    }
                    $last = $null
                    foreach ($key in $callArgs[0].Items.Keys) { $last = $key }
                    if ($null -ne $last) { return (Get-PhpKeyValue $last) }
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
                    Assert-PhpStringBuiltinArity 'str_contains' $callArgs 2 2
                    $haystack=ConvertTo-PhpBuiltinBytes $callArgs[0] 'str_contains' 1 'haystack'
                    $needle=ConvertTo-PhpBuiltinBytes $callArgs[1] 'str_contains' 2 'needle'
                    return ((Find-PhpBytes $haystack $needle 0)-ge0)
                }
                'str_starts_with' {
                    Assert-PhpStringBuiltinArity 'str_starts_with' $callArgs 2 2
                    $haystack=ConvertTo-PhpBuiltinBytes $callArgs[0] 'str_starts_with' 1 'haystack'
                    $needle=ConvertTo-PhpBuiltinBytes $callArgs[1] 'str_starts_with' 2 'needle'
                    return (Test-PhpBytesAt $haystack $needle 0)
                }
                'str_ends_with' {
                    Assert-PhpStringBuiltinArity 'str_ends_with' $callArgs 2 2
                    $haystack=ConvertTo-PhpBuiltinBytes $callArgs[0] 'str_ends_with' 1 'haystack'
                    $needle=ConvertTo-PhpBuiltinBytes $callArgs[1] 'str_ends_with' 2 'needle'
                    return (Test-PhpBytesAt $haystack $needle ($haystack.Length-$needle.Length))
                }
                'strpos' {
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
                }
                'substr' {
                    Assert-PhpStringBuiltinArity 'substr' $callArgs 2 3
                    $bytes=ConvertTo-PhpBuiltinBytes $callArgs[0] 'substr' 1 'string'
                    $offset=ConvertTo-PhpBuiltinInteger $callArgs[1] 'substr' 2 'offset'
                    $length=$null
                    if($callArgs.Count-eq3 -and $null-ne$callArgs[2]){$length=ConvertTo-PhpBuiltinInteger $callArgs[2] 'substr' 3 'length'}
                    return $bytes.Slice($offset,$length)
                }
                'str_replace' {
                    # Fourth by-reference count is a separate call-binding obligation.
                    if($callArgs.Count-ne3){throw 'ALL PHP: str_replace() count-reference binding is not implemented; three arguments are supported'}
                    return (Invoke-PhpByteReplace $callArgs[0] $callArgs[1] $callArgs[2])
                }
                'explode' {
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
                }
                'implode' {
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
                }
                'print_r' {
                    if ($callArgs.Count -lt 1 -or $callArgs.Count -gt 2) { throw 'ALL PHP: print_r() requires one or two arguments' }
                    $printed = Format-PhpBytesPrintR $callArgs[0] 0
                    if ($callArgs.Count -eq 2 -and (Is-Truthy $callArgs[1])) { return $printed }
                    Write-PhpBytes $printed
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
                    if ($state.Constants.ContainsKey($constName)) { return (ConvertTo-PhpOwnedValue $state.Constants[$constName]) }
                    if ($phpConstants.ContainsKey($constName)) { return (ConvertTo-PhpOwnedValue $phpConstants[$constName]) }
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
                    $errorFunction=ConvertTo-PhpAsciiLower $name
                    Assert-PhpStringBuiltinArity $errorFunction $callArgs 1 2
                    $message=ConvertTo-PhpBuiltinBytes $callArgs[0] $errorFunction 1 'message'
                    $level = [long]1024
                    if ($callArgs.Count -eq 2) { $level = ConvertTo-PhpBuiltinInteger $callArgs[1] $errorFunction 2 'error_level' }
                    if ($level -notin @(256, 512, 1024, 16384)) {
                        Throw-PhpError 'ValueError' ($errorFunction+'(): Argument #2 ($error_level) must be one of E_USER_ERROR, E_USER_WARNING, E_USER_NOTICE, or E_USER_DEPRECATED')
                    }
                    Write-PhpDiagnostic $level $message
                    return $true
                }
                'str_repeat' {
                    Assert-PhpStringBuiltinArity 'str_repeat' $callArgs 2 2
                    $bytes=ConvertTo-PhpBuiltinBytes $callArgs[0] 'str_repeat' 1 'string'
                    $times=ConvertTo-PhpBuiltinInteger $callArgs[1] 'str_repeat' 2 'times'
                    if($times-lt0){Throw-PhpError 'ValueError' 'str_repeat(): Argument #2 ($times) must be greater than or equal to 0'}
                    return $bytes.Repeat($times)
                }
                'function_exists' {
                    if ($callArgs.Count -ne 1) { throw 'ALL PHP: function_exists() requires one argument' }
                    $functionName = To-PhpText $callArgs[0]
                    return ($state.Functions.ContainsKey($functionName) -or ($isCli -and $functionName -ine '__all_throwable_string' -and $phpBuiltinNames.Contains($functionName)) -or (Test-PhpNativeFunction $functionName))
                }
                'call_user_func' {
                    if ($callArgs.Count -lt 1) { throw 'ALL PHP: call_user_func() requires a callable' }
                    $rest = @()
                    if ($callArgs.Count -gt 1) { $rest = @($callArgs[1..($callArgs.Count - 1)]) }
                    return (Invoke-PhpValueCallable $callArgs[0] $rest 'call_user_func')
                }
                'call_user_func_array' {
                    if ($callArgs.Count -ne 2 -or -not (Is-PhpArray $callArgs[1])) {
                        throw 'ALL PHP: call_user_func_array() requires a callable and an array'
                    }
                    return (Invoke-PhpValueCallable $callArgs[0] (Get-PhpCallbackArrayArguments $callArgs[1]) 'call_user_func_array')
                }
                'get_class' {
                    if ($callArgs.Count -ne 1 -or -not (Is-PhpObject $callArgs[0])) {
                        throw 'ALL PHP: get_class() requires one object argument'
                    }
                    return (To-PhpBytes ([string]$callArgs[0].Class))
                }
                'var_dump' {
                    if ($callArgs.Count -lt 1) { throw 'ALL PHP: var_dump() requires at least one argument' }
                    $referenceDumpContext=New-PhpReferenceContext $callArgs
                    foreach ($item in $callArgs) { Write-PhpBytes (Format-PhpBytesDump $item '' $referenceDumpContext) }
                    return $null
                }
                'gettype' {
                    Assert-PhpStringBuiltinArity 'gettype' $callArgs 1 1
                    $item=$callArgs[0]
                    if(Is-PhpRefCell $item){$item=$item.Value}
                    $type=if($null-eq$item){'NULL'}elseif($item-is[bool]){'boolean'}elseif($item-is[long]){'integer'}elseif($item-is[double]){'double'}elseif(Is-PhpStringValue $item){'string'}elseif(Is-PhpArray $item){'array'}else{'object'}
                    return [AllPhp.ByteValues.PhpBytes]::FromUtf8($type)
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
                    if (Is-PhpStringValue $callArgs[0]) {
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
                    Assert-PhpStringBuiltinArity 'strval' $callArgs 1 1
                    return (To-PhpBytes $callArgs[0])
                }
            }
            if (-not $state.Functions.ContainsKey($name)) {
                if (Test-PhpNativeFunction $name) { return (Invoke-PhpNativeFunction $name $callArgs) }
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
        function ConvertTo-PhpWeakEnumArgument($value,$enum,[string]$method) {
            if(Is-PhpRefCell $value) { $value=$value.Value }
            $function=$enum.Name+'::'+$method
            $stringBacked=Test-PhpNameEqual $enum.BackingType 'string'
            if(Is-PhpStringValue $value) {
                if($stringBacked) { return (To-PhpBytes $value) }
                return (ConvertTo-PhpBuiltinInteger $value $function 1 'value')
            }
            if($value-is[long]) {
                if($stringBacked) { return (To-PhpBytes $value) }
                return $value
            }
            if($null-eq$value) {
                Write-PhpDiagnostic 8192 ($function+'(): Passing null to parameter #1 ($value) of type string|int is deprecated')
                if($stringBacked) { return (To-PhpBytes ([long]0)) }
                return [long]0
            }
            if($value-is[bool]) {
                $integer=if($value){[long]1}else{[long]0}
                if($stringBacked) { return (To-PhpBytes $integer) }
                return $integer
            }
            if($value-is[double]) {
                if(-not$stringBacked) { return (ConvertTo-PhpBuiltinInteger $value $function 1 'value') }
                if(-not[double]::IsNaN($value)-and-not[double]::IsInfinity($value)-and
                    $value-ge-9223372036854775808.0-and$value-lt9223372036854775808.0) {
                    return (To-PhpBytes (ConvertTo-PhpBuiltinInteger $value $function 1 'value'))
                }
                if([double]::IsNaN($value)) { Write-PhpDiagnostic 2 'unexpected NAN value was coerced to string' }
                return (To-PhpBytes $value)
            }
            if($stringBacked-and(Is-PhpObject $value)-and
                $null-ne(Find-OptionalPhpMethod $value.Class '__toString')) { return (To-PhpBytes $value) }
            $expected=if($stringBacked){'string|int'}else{'int'}
            Throw-PhpError 'TypeError' ($function+'(): Argument #1 ($value) must be of type '+$expected+', '+(Get-PhpBuiltinTypeName $value)+' given')
        }
        function Get-PhpEnumBadStringBytes($value) {
            $bytes=To-PhpBytes $value
            $offset=[long]0;$chunk=[byte[]]::new(65536)
            while($offset-lt$bytes.LongLength) {
                $count=[int][Math]::Min([long]$chunk.Length,$bytes.LongLength-$offset)
                $bytes.CopyTo($offset,$chunk,0,$count)
                for($i=0;$i-lt$count;$i++) { if($chunk[$i]-eq0) { return $bytes.Slice(0,$offset+$i) } }
                $offset+=$count
            }
            return $bytes
        }
        function Get-PhpClassConstant([string]$className, [string]$constName) {
            $className=Resolve-PhpClass $className
            if (Test-PhpNameEqual $constName 'class') { return (To-PhpBytes $className) }
            if ($state.Classes.ContainsKey($className)) {
                foreach ($cls in (Get-PhpClassChain $className)) {
                    if ($cls.Constants.ContainsKey($constName)) {
                        $entry=$cls.Constants[$constName]
                        Assert-PhpVisibility $entry.Visibility $entry.Owner
                        return (ConvertTo-PhpOwnedValue $entry.Value)
                    }
                }
                foreach ($cls in (Get-PhpClassChain $className)) {
                    foreach ($name in $cls.Interfaces) {
                        foreach ($iface in (Get-PhpInterfaceChain $name)) {
                            if ($iface.Constants.ContainsKey($constName)) {
                                return (ConvertTo-PhpOwnedValue $iface.Constants[$constName].Value)
                            }
                        }
                    }
                }
            } elseif ($state.Interfaces.ContainsKey($className)) {
                foreach ($iface in (Get-PhpInterfaceChain $className)) {
                    if ($iface.Constants.ContainsKey($constName)) {
                        return (ConvertTo-PhpOwnedValue $iface.Constants[$constName].Value)
                    }
                }
            }
            throw "ALL PHP: Undefined class constant '$constName'"
        }
        function Resolve-PhpFunctionNodeName($node) {
            if (-not $node.PSObject.Properties['Fallback'] -or $null -eq $node.Fallback) {
                if ($state.Functions.ContainsKey($node.Name) -or $phpBuiltinNames.Contains($node.Name) -or (Test-PhpNativeFunction $node.Name)) { return $node.Name }
                Throw-PhpError 'Error' ("Call to undefined function " + $node.Name + '()')
            }
            if ($null -ne $node.ResolvedName) { return $node.ResolvedName }
            # A call site's first successful namespace/global binding is retained, like PHP's
            # runtime cache. Conditional/nested declarations are not installed during parsing.
            if ($state.Functions.ContainsKey($node.Name) -or (Test-PhpNativeFunction $node.Name)) { $node.ResolvedName = $node.Name }
            elseif ($state.Functions.ContainsKey($node.Fallback) -or $phpBuiltinNames.Contains($node.Fallback) -or (Test-PhpNativeFunction $node.Fallback)) {
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
                    if (Test-PhpNativeFunction $callName) { Throw-PhpNativeUnsupported 'native reference-return calls are not implemented' }
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
                $klass=Resolve-PhpClass (Get-PhpHostText (Invoke-PhpExpr $node.Base))
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
                $callee=Assert-PhpValueCallable (Invoke-PhpExpr $node.Callee)
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
                'literal' { return (ConvertTo-PhpOwnedValue $node.Value) }
                'internal_throwable_string' {
                    return (Get-PhpThrowableString (Invoke-PhpExpr $node.Object))
                }
                'cli_exit' { Invoke-PhpCliExit @() }
                'silence' {
                    $state.SilenceDepth++
                    try { return (Invoke-PhpExpr $node.Arg) }
                    finally { $state.SilenceDepth-- }
                }
                'class_name' {
                    $constantName = Resolve-PhpConstantNodeName $node
                    if ($state.Constants.ContainsKey($constantName)) { return (ConvertTo-PhpOwnedValue $state.Constants[$constantName]) }
                    if ($phpConstants.ContainsKey($constantName)) { return (ConvertTo-PhpOwnedValue $phpConstants[$constantName]) }
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
                            if ((Test-PhpRawNameEqual $name 'this')) { continue }
                            $cap[$name]=Copy-PhpValue (Get-PhpVariableValue $name)
                        }
                    } else {
                        foreach ($capture in $node.Captures) {
                            if ((Test-PhpRawNameEqual $capture.Name 'this')) { continue }
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
                    $klass=Resolve-PhpClass (Get-PhpHostText (Invoke-PhpExpr $node.Base))
                    if ($null -eq (Find-OptionalPhpMethod $klass $node.Name)) {
                        throw "ALL PHP: Undefined static method '$($node.Name)'"
                    }
                    return [pscustomobject]@{
                        PhpType='first_class_callable'; Id=(New-PhpObjectId); Mode='static'
                        Name=$node.Name; Class=$klass
                    }
                }
                'first_class_invoke' {
                    $callable=Assert-PhpValueCallable (Invoke-PhpExpr $node.Callee)
                    if ($null -ne $callable -and $callable -is [string]) {
                        $split=$callable.IndexOf('::')
                        if ($split -gt 0) {
                            return [pscustomobject]@{ PhpType='first_class_callable'; Id=(New-PhpObjectId)
                                Mode='static'; Class=$callable.Substring(0,$split); Name=$callable.Substring($split+2) }
                        }
                        return [pscustomobject]@{
                            PhpType='first_class_callable'; Id=(New-PhpObjectId); Mode='function'; Name=$callable
                        }
                    }
                    if (Is-PhpArray $callable) {
                        $target=Get-PhpArrayItem $callable ([long]0);$member=Get-PhpArrayItem $callable ([long]1)
                        if (Is-PhpStringValue $target) { $target=Get-PhpHostText $target }
                        if (Is-PhpStringValue $member) { $member=Get-PhpHostText $member }
                        if (Is-PhpObject $target) {
                            return [pscustomobject]@{ PhpType='first_class_callable'; Id=(New-PhpObjectId)
                                Mode='method'; BoundThis=$target; Name=$member }
                        }
                        return [pscustomobject]@{ PhpType='first_class_callable'; Id=(New-PhpObjectId)
                            Mode='static'; Class=[string]$target; Name=$member }
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
                    $callee=Assert-PhpValueCallable (Invoke-PhpExpr $node.Callee)
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
                    if (Is-PhpArray $callee) {
                        $definition=Get-PhpValueCallableDefinition $callee
                        $args=Evaluate-PhpUserArguments $node.Args $definition
                        return (Invoke-PhpValueCallable $callee $args)
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
                    $klass=Get-PhpHostText (Invoke-PhpExpr $node.Base)
                    return (Get-PhpClassConstant $klass $node.Name)
                }
                'static_method' {
                    $klass=Get-PhpHostText (Invoke-PhpExpr $node.Base)
                    $klass=Resolve-PhpClass $klass
                    if ($state.Classes.ContainsKey($klass) -and
                        $state.Classes[$klass].PSObject.Properties['Enum'] -and
                        $state.Classes[$klass].Enum) {
                        $enum=$state.Classes[$klass]
                        if ((Test-PhpNameEqual $node.Name 'cases')) {
                            if ($node.Args.Count -ne 0) { throw 'ALL PHP: cases() takes no arguments' }
                            $result=New-PhpArray
                            foreach ($item in $enum.EnumCases) {
                                Set-PhpArrayItem $result $null $item $true
                            }
                            return $result
                        }
                        if ((Test-PhpNameIn $node.Name @('from','tryFrom'))) {
                            if ($null -eq $enum.BackingType) {
                                throw 'ALL PHP: Unit enums have no from() or tryFrom()'
                            }
                            if ($node.Args.Count -ne 1) {
                                throw 'ALL PHP: Enum from() requires one argument'
                            }
                            $enumMethod=if(Test-PhpNameEqual $node.Name 'tryFrom'){'tryFrom'}else{'from'}
                            $needle=ConvertTo-PhpWeakEnumArgument (Invoke-PhpExpr $node.Args[0]) $enum $enumMethod
                            foreach ($item in $enum.EnumCases) {
                                if ($enum.BackingType -eq 'string' -and (Is-PhpStringValue $needle) -and
                                    (To-PhpBytes $item.Props['value']).Equals((To-PhpBytes $needle))) { return $item }
                                if ($enum.BackingType -eq 'int' -and $needle -is [long] -and
                                    $item.Props['value'] -eq $needle) { return $item }
                            }
                            if ((Test-PhpRawNameEqual $enumMethod 'tryFrom')) { return $null }
                            $message=[AllPhp.ByteValues.PhpByteBuilder]::new()
                            if(Is-PhpStringValue $needle) { $message.AppendUtf8('"');$message.Append((Get-PhpEnumBadStringBytes $needle));$message.AppendUtf8('"') }
                            else { $message.Append((To-PhpBytes $needle)) }
                            $message.AppendUtf8(' is not a valid backing value for enum '+$enum.Name)
                            Throw-PhpError 'ValueError' ($message.ToPhpBytes()) 'ALL PHP: ValueError: invalid backing value for enum'
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
                if ($isCli -and (Test-PhpCliExit $_)) { throw }
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
                if ($isCli -and (Test-PhpCliExit $_)) { throw }
                            if ($_.Exception.Message -notlike 'ALL PHP: Undefined *') { throw }
                        }
                        finally { $state.QuietDepth-- }
                        if ($null -ne $current) { return $current }
                    }
                    $replacement = Invoke-PhpExpr $node.Value
                    $writeOp = if ($node.Op -ceq '??=') { '=' } else { $node.Op }
                    $assignmentResult=[pscustomobject]@{IsStringOffset=$false;Value=$null}
                    Set-LValue $node.Target $replacement $writeOp $assignmentResult
                    if($assignmentResult.IsStringOffset){return $assignmentResult.Value}
                    if (($node.Target.Kind -eq 'index' -and $null -eq $node.Target.Key) -or
                        $node.Target.Kind -eq 'array' -or
                        ($node.Target.Kind -eq 'property' -and $node.Op -ceq '=')) {
                        return $replacement
                    }
                    return (Get-LValue $node.Target)
                }
                'double_string' {
                    $isBody=$false;$heredoc=$false;$stringLine=[long]$state.Line
                    if($node.PSObject.Properties['IsBody']){$isBody=[bool]$node.IsBody;$heredoc=[bool]$node.Heredoc;$stringLine=[long]$node.StringLine}
                    return (Expand-PhpDoubleString $node.Raw $isBody $heredoc $false $stringLine)
                }
                'variable' { return (Get-LValue $node) }
                'dynamic_variable' { return (Get-LValue $node) }
                'index' { return (Get-LValue $node) }
                'property' { return (Get-LValue $node) }
                'array' {
                    $array = New-PhpArray
                    foreach ($entry in $node.Entries) {
                        if ($entry.PSObject.Properties['ByReference'] -and $entry.ByReference) {
                            $key=$null
                            if ($null -ne $entry.Key) { $key=Invoke-PhpExpr $entry.Key }
                            $cell=Get-PhpLValueCell $entry.Value
                            Set-PhpArrayItem $array $key $cell ($null -eq $entry.Key)
                            continue
                        }
                        $value = Invoke-PhpExpr $entry.Value
                        if ($entry.Spread) {
                            if (-not (Is-PhpArray $value)) {
                                throw 'ALL PHP: Only arrays can be unpacked in array literals'
                            }
                            foreach ($key in $value.Items.Keys) {
                                if ($key.IsInteger) {
                                    Set-PhpArrayItem $array $null $value.Items[$key] $true
                                } else {
                                    Set-PhpArrayItem $array (Get-PhpKeyValue $key) $value.Items[$key] $false
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
                            if ($isCli -and $arg.Kind -ceq 'index') {
                                $quiet = Get-PhpCliQuietPath $arg
                                $found = $quiet.Found
                                $value = $quiet.Value
                            } else {
                                $state.QuietDepth++
                                try {
                                    $value = Invoke-PhpExpr $arg
                                } catch {
                if ($isCli -and (Test-PhpCliExit $_)) { throw }
                                    if ($_.Exception.Message -like 'ALL PHP: Undefined *') {
                                        $found = $false
                                    } else { throw }
                                }
                                finally { $state.QuietDepth-- }
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
                                if ($array.Items.Contains($key)) { Separate-PhpReferenceBacking $array;$array.Items.Remove($key) }
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
                    $callbackName=(ConvertTo-PhpAsciiLower $callName)
                    if ((Test-PhpNameEqual $node.Name $callName) -and
                        -not $state.Functions.ContainsKey($callName) -and
                        (($callbackName -ceq 'call_user_func' -and $node.Args.Count -ge 1) -or
                         ($callbackName -ceq 'call_user_func_array' -and $node.Args.Count -eq 2))) {
                        $plainArguments=$true
                        foreach ($expression in $node.Args) { if ($expression.Kind -ceq 'named_argument') { $plainArguments=$false } }
                        if ($plainArguments) {
                            $boundCallback=Assert-PhpValueCallable (Invoke-PhpExpr $node.Args[0]) $callbackName
                            $earlyArgs=[System.Collections.Generic.List[object]]::new()
                            [void]$earlyArgs.Add($boundCallback)
                            for ($argumentIndex=1;$argumentIndex -lt $node.Args.Count;$argumentIndex++) {
                                [void]$earlyArgs.Add((Invoke-PhpExpr $node.Args[$argumentIndex]))
                            }
                            return (Invoke-PhpFunction $callName ($earlyArgs.ToArray()))
                        }
                    }
                    if ($state.Functions.ContainsKey($callName)) {
                        $args=Evaluate-PhpUserArguments $node.Args $state.Functions[$callName]
                        return (Invoke-PhpCallable $state.Functions[$callName] $args $null)
                    }
                    $callArgs = Evaluate-PhpBuiltinArguments $node.Args $callName
                    return (Invoke-PhpFunction $callName $callArgs)
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
                    if ($state.Classes.ContainsKey($className)) { $className=[string]$state.Classes[$className].Name }
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
                if ($isCli -and (Test-PhpCliExit $_)) { throw }
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
                        '~' { if (Is-PhpStringValue $value) { return (To-PhpBytes $value).BitwiseNot() };return [long](-bnot (To-PhpInt $value)) }
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
                if ($isCli -and (Test-PhpCliExit $_)) { throw }
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
                        '.' { return (To-PhpBytes $a).Concat((To-PhpBytes $b)) }
                        '+' {
                            if ((Is-PhpArray $a) -and (Is-PhpArray $b)) {
                                $union = Copy-PhpValue $a
                                foreach ($key in $b.Items.Keys) {
                                    if (-not $union.Items.Contains($key)) {
                                        Set-PhpArrayItem $union (Get-PhpKeyValue $key) $b.Items[$key] $false
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
                        '&' { if ((Is-PhpStringValue $a) -and (Is-PhpStringValue $b)) { return (To-PhpBytes $a).Bitwise((To-PhpBytes $b),[char]'&') };return [long]((To-PhpInt $a) -band (To-PhpInt $b)) }
                        '|' { if ((Is-PhpStringValue $a) -and (Is-PhpStringValue $b)) { return (To-PhpBytes $a).Bitwise((To-PhpBytes $b),[char]'|') };return [long]((To-PhpInt $a) -bor (To-PhpInt $b)) }
                        '^' { if ((Is-PhpStringValue $a) -and (Is-PhpStringValue $b)) { return (To-PhpBytes $a).Bitwise((To-PhpBytes $b),[char]'^') };return [long]((To-PhpInt $a) -bxor (To-PhpInt $b)) }
                        'instanceof' {
                            if (-not (Is-PhpObject $a)) { return $false }
                            if (-not (Is-PhpStringValue $b)) { throw 'ALL PHP: instanceof class name required' }
                            return (Test-PhpInstanceOf $a.Class (Get-PhpHostText $b))
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
                'inline_html' { Write-PhpBytes $node.Text; return }
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
                if ($isCli -and (Test-PhpCliExit $_)) { throw }
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
                    } catch {
                if ($isCli -and (Test-PhpCliExit $_)) { throw } $pending = $_ }
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
                if ($isCli -and (Test-PhpCliExit $_)) { throw }
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
                    if (Test-PhpRegisteredPublicFunction $node.Name) {
                        Throw-PhpRegisteredFunctionRedeclaration $node
                    }
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
                        [AllPhp.ValidTextSymbols.Comparers]::Ascii)
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
                    $usedValues=[System.Collections.Generic.HashSet[object]]::new()
                    foreach ($case in $node.Cases) {
                        if ($constants.ContainsKey($case.Name)) {
                            throw "ALL PHP: Duplicate enum case '$($case.Name)'"
                        }
                        $props=[System.Collections.Specialized.OrderedDictionary]::new(
                            [System.StringComparer]::Ordinal)
                        $props['name']=To-PhpBytes $case.Name
                        if ($null -ne $node.BackingType) {
                            $backedValue=ConvertTo-PhpOwnedValue (Invoke-PhpExpr $case.Value)
                            if ($node.BackingType -eq 'string' -and -not (Is-PhpStringValue $backedValue)) {
                                throw 'ALL PHP: Backed enum string case expects a string'
                            }
                            if ($node.BackingType -eq 'int' -and
                                ($backedValue -isnot [long])) {
                                throw 'ALL PHP: Backed enum int case expects an integer'
                            }
                            $uniqueValue=$backedValue
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
                        [AllPhp.ValidTextSymbols.Comparers]::Ascii)
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
                            [AllPhp.ValidTextSymbols.Comparers]::Ascii)
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
                        [AllPhp.ValidTextSymbols.Comparers]::Ascii)
                    foreach ($method in $node.Methods) {
                        if ($methods.ContainsKey($method.Name)) {
                            throw "ALL PHP: Duplicate method '$($method.Name)'"
                        }
                        if ($null -ne $node.Parent) {
                            $parentMethod=$null
                            try { $parentMethod=Find-PhpMethod $node.Parent $method.Name }
                            catch {
                if ($isCli -and (Test-PhpCliExit $_)) { throw }
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
                        [AllPhp.ValidTextSymbols.Comparers]::Ascii)
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
                if ($isCli -and (Test-PhpCliExit $_)) { throw }
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
                                if ((Test-PhpRawNameEqual $existing.Name $prop.Name)) { $duplicate=$true; break }
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
                if ($isCli -and (Test-PhpCliExit $_)) { throw }
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
                if ($isCli -and (Test-PhpCliExit $_)) { throw }
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
                        Write-PhpBytes (Invoke-PhpExpr $e)
                    }
                    return
                }
                'print' {
                    Write-PhpBytes (Invoke-PhpExpr $node.Expr)
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
                    else { Separate-PhpReferenceBacking $walk;$walk.ReferenceCellsKnownAbsent=$false }
                    $referenceWalkRoot=$state.ReferenceTemporaryRoots.Count
                    [void]$state.ReferenceTemporaryRoots.Add($walk)
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
                                Set-PhpVariableValue $node.KeyName (Get-PhpKeyValue $key)
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
                    } finally { Remove-PhpReferenceTemporaryRoots $referenceWalkRoot;$state.Flow.LoopDepth-- }
                    return
                }
            }
            throw 'ALL PHP: Internal statement error'
        }
        if ($isCli -and ($CliContext.Keys -contains 'InitialIni')) {
            foreach ($setting in $CliContext['InitialIni'].Keys) {
                $state.Ini[[string]$setting] = [string]$CliContext['InitialIni'][$setting]
            }
            if ($state.Ini.ContainsKey('error_reporting')) {
                $state.ErrorReporting = [long]$state.Ini['error_reporting']
            }
        }
        if ($isCli -and ($CliContext.Keys -contains 'ScriptArguments')) {
            $scriptArguments = @($CliContext['ScriptArguments'])
            $argumentArray = New-PhpArray
            foreach ($argument in $scriptArguments) {
                Set-PhpArrayItem $argumentArray $null ([string]$argument) $true
            }
            $state.Globals['argc'] = [long]$scriptArguments.Count
            $state.Globals['argv'] = $argumentArray
            $server = New-PhpArray
            Set-PhpArrayItem $server 'argc' ([long]$scriptArguments.Count) $false
            Set-PhpArrayItem $server 'argv' $argumentArray $false
            $state.Globals['_SERVER'] = $server
        }
        foreach($literalWarning in $state.LiteralWarnings) {
            $savedLine=$state.Line
            try{$state.Line=$literalWarning.Line;Write-PhpDiagnostic $literalWarning.Level $literalWarning.Message}
            finally{$state.Line=$savedLine}
        }
        # Load the built-in exception classes up front when the program mentions any of them, so
        # that user classes can extend them.
        foreach ($programToken in $state.Tokens) {
            if ($phpPreludeTriggers.Contains($programToken)) { Ensure-PhpPrelude; break }
        }
        # Same-thread Action delegate: managed reverse-P/Invoke catches exceptions.
        # Older NativeContext hosts retain deferred diagnostics and their prior
        # installed-handler rejection. Do not call an absent optional interface.
        $nativeCallbackInstalled = $false
        if ($null -ne $NativeContext -and
            $null -ne $NativeContext.PSObject.Methods['ClearDiagnosticHandler']) {
            if ($null -ne $NativeContext.PSObject.Methods['SetByteDiagnosticHandler']) {
                $nativeByteDiagnosticAction=[System.Action[long,AllPhp.ByteValues.PhpBytes]] {
                    param([long]$nativeLevel,[AllPhp.ByteValues.PhpBytes]$nativeMessage)
                    Write-PhpDiagnostic $nativeLevel $nativeMessage
                }
                $nativeByteOutputAction=[System.Action[AllPhp.ByteValues.PhpBytes]] {
                    param([AllPhp.ByteValues.PhpBytes]$nativeOutput)
                    Write-PhpBytes $nativeOutput
                }
                $NativeContext.SetByteDiagnosticHandler($nativeByteDiagnosticAction,$nativeByteOutputAction)
                $nativeCallbackInstalled=$true
            } elseif ($null -ne $NativeContext.PSObject.Methods['SetDiagnosticHandler']) {
                $nativeDiagnosticAction=[System.Action[long,string]] {
                    param([long]$nativeLevel,[string]$nativeMessage)
                    Write-PhpDiagnostic $nativeLevel $nativeMessage
                }
                $NativeContext.SetDiagnosticHandler($nativeDiagnosticAction)
                $nativeCallbackInstalled=$true
            }
        }
        try {

            # Direct global declarations are checked before any program output. Conditional
            # and nested declarations remain runtime checks in the functiondef registration path.
            foreach ($declaration in $statements) {
                if ($declaration.Kind -ceq 'functiondef' -and
                    (Test-PhpRegisteredPublicFunction $declaration.Name)) {
                    Throw-PhpRegisteredFunctionRedeclaration $declaration
                }
            }

            foreach ($statement in $statements) {
                if ($state.Flow.Returned) { break }
                Invoke-PhpStatement $statement
            }
        } catch {
            if ($isCli -and (Test-PhpCliExit $_)) { return }
            $uncaught = Get-PhpThrown $_
            if ($null -ne $uncaught -and $null -ne $state.ExceptionHandler) {
                $handler = $state.ExceptionHandler
                $state.ExceptionHandler = $null
                if ($isCli) {
                    $handlerFailed = $false
                    try { [void](Invoke-PhpValueCallable $handler @($uncaught)) }
                    catch
                    {
                        # This callback runs inside the outer handler catch, so
                        # its private exit must be consumed at this boundary.
                        if (Test-PhpCliExit $_) { return }
                        $replacement = Get-PhpThrown $_
                        if ($null -eq $replacement) { throw }
                        $uncaught = $replacement
                        $handlerFailed = $true
                    }
                    if (-not $handlerFailed) { return }
                } else {
                    [void](Invoke-PhpValueCallable $handler @($uncaught))
                    return
                }
            }
            if ($null -eq $uncaught -or (-not $PhpDiagnostics -and -not $isCli)) { throw }
            # Same text the PHP CLI writes with display_errors=1 and html_errors=0.
            $fatalBuilder=[AllPhp.ByteValues.PhpByteBuilder]::new()
            if (-not $isCli) { $fatalBuilder.AppendUtf8("`n") }
            $fatalBuilder.AppendUtf8('Fatal error: Uncaught ')
            $fatalBuilder.Append((Get-PhpThrowableString $uncaught))
            $fatalBuilder.AppendUtf8("`n  thrown in ")
            $fatalBuilder.Append((To-PhpBytes $uncaught.Props['file']))
            $fatalBuilder.AppendUtf8(' on line ')
            $fatalBuilder.Append((To-PhpBytes $uncaught.Props['line']))
            $fatalBuilder.AppendUtf8("`n")
            Write-PhpBytes ($fatalBuilder.ToPhpBytes()) $isCli
            if ($isCli) {
                $CliContext['ExitCode'] = [long]255
                $CliContext['Terminated'] = $true
                $CliContext['TerminationReason'] = 'uncaught_php_throwable'
            }
        } finally {
            if ($nativeCallbackInstalled) { $NativeContext.ClearDiagnosticHandler() }
        }
    }
}
