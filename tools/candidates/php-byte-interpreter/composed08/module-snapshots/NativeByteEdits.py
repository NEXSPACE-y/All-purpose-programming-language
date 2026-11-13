"""Compose native byte APIs into Core -> TypedKey -> StringBuiltin candidates.

Only this edit module is owned here. It does not load a native DLL, execute PHP,
write an adapter, or mutate a package. Root pins/applies/measures the resulting
candidate. Canonical dependency is AllPhp.ByteValues.Runtime runtime01.

Native names/classes remain explicit host metadata. New-context PHP values,
diagnostic messages and output remain PhpBytes. Legacy context conversion is
selected before calling native code; an error/result never triggers a retry.
The pre-existing general trace-argument formatter is a separate migration gap.
"""
import re

BASE_SHA256 = "5856687f7abd1471b4af7af9827ca2d17a011e836ad2852bf1d7993298fddc9f"
BYTE_RUNTIME_SHA256 = "18d50efb55d8a333424149e4ab37428e102b1ac938240e50358ee3c8ab89466b"

NATIVE_FUNCTION = r'''        function Throw-PhpNativeUnsupportedBytes($reason) {
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
'''

DIAGNOSTIC_FUNCTION = r'''        function Write-PhpDiagnostic([long]$level, $message) {
            $messageBytes=To-PhpBytes $message
            if ($null -ne $state.ErrorHandler -and -not $state.InErrorHandler -and
                (($state.ErrorHandlerMask -band $level) -ne 0)) {
                $handlerArgs=@($level,$messageBytes,(To-PhpBytes ([string]$state.ScriptName)),[long]$state.Line)
                $arity=Get-PhpCallableArity $state.ErrorHandler
                if ($arity -ge 0 -and $arity -lt 4) {
                    if ($arity -eq 0) { $handlerArgs=@() } else { $handlerArgs=@($handlerArgs[0..($arity-1)]) }
                }
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
'''

THROWABLE_STRING = r'''        function Get-PhpThrowableString($object) {
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
'''

CALLBACK_INSTALL = r'''        $nativeCallbackInstalled = $false
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
'''

FATAL_BYTES = r'''            $fatalBuilder=[AllPhp.ByteValues.PhpByteBuilder]::new()
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
'''


def apply(value: str) -> str:
    newline = "\r\n" if "\r\n" in value else "\n"
    value = value.replace("\r\n", "\n")
    for helper in ("To-PhpBytes", "Get-PhpHostText", "Is-PhpStringValue", "Write-PhpBytes"):
        if f"function {helper}(" not in value:
            raise ValueError("Native byte edits require Core byte helper " + helper)

    def replace(old, new):
        nonlocal value
        count = value.count(old)
        if count != 1:
            raise ValueError(f"Native byte anchor count {count}, expected 1: {old[:100]!r}")
        value = value.replace(old, new)

    def function(name, replacement):
        nonlocal value
        pattern = re.compile(r"^        function " + re.escape(name) + r"(?=[( {]).*?^        }\n", re.M | re.S)
        matches = list(pattern.finditer(value))
        if len(matches) != 1:
            raise ValueError(f"Native byte function {name} count {len(matches)}, expected 1")
        match = matches[0]
        if match.group() == replacement:
            raise ValueError("Native byte edits were already applied: " + name)
        value = value[:match.start()] + replacement + value[match.end():]

    function("Invoke-PhpNativeFunction", NATIVE_FUNCTION)
    function("Write-PhpDiagnostic", DIAGNOSTIC_FUNCTION)
    function("Get-PhpThrowableString", THROWABLE_STRING)
    replace("function Throw-PhpError([string]$className, [string]$message, [string]$legacyText = '')",
            "function Throw-PhpError([string]$className, $message, [string]$legacyText = '')")
    replace("""                $legacyText = 'ALL PHP: Uncaught ' + $object.Class + ': ' + (To-PhpText $object.Props['message'])""",
            """                $carrierMessage=To-PhpBytes $object.Props['message']
                $carrierText=$null
                if ($carrierMessage.TryDecodeUtf8([ref]$carrierText)) {
                    $legacyText='ALL PHP: Uncaught '+$object.Class+': '+$carrierText
                } else {
                    # The raw PHP message is kept on the PHP object. This is
                    # only a host control carrier and never rendered to PHP.
                    $legacyText='ALL PHP: Uncaught '+$object.Class+' (raw PHP message retained)'
                }""")
    replace("""        $nativeCallbackInstalled = $false
        if ($null -ne $NativeContext -and
            $null -ne $NativeContext.PSObject.Methods['SetDiagnosticHandler'] -and
            $null -ne $NativeContext.PSObject.Methods['ClearDiagnosticHandler']) {
            $nativeDiagnosticAction = [System.Action[long,string]] {
                param([long]$nativeLevel, [string]$nativeMessage)
                Write-PhpDiagnostic $nativeLevel $nativeMessage
            }
            $NativeContext.SetDiagnosticHandler($nativeDiagnosticAction)
            $nativeCallbackInstalled = $true
        }
""", CALLBACK_INSTALL)
    replace("""            $fatal = 'Fatal error: Uncaught ' + (Get-PhpThrowableString $uncaught) +
                "`n  thrown in " + (To-PhpText $uncaught.Props['file']) +
                ' on line ' + (To-PhpText $uncaught.Props['line']) + "`n"
            if ($isCli) {
                [Console]::Error.Write($fatal)
                $CliContext['ExitCode'] = [long]255
                $CliContext['Terminated'] = $true
                $CliContext['TerminationReason'] = 'uncaught_php_throwable'
            } else { [Console]::Write("`n" + $fatal) }
""", FATAL_BYTES)
    return value.replace("\n", newline)
