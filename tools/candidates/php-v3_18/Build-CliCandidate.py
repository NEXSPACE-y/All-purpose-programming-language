"""Build an explicitly isolated CLI candidate from the post-prelude-fix adapter.

No package file is written. The source snapshot/hash and generated diff are kept
beside the candidate so the root agent can review and merge selected changes.
"""
from pathlib import Path
import difflib
import hashlib
import json
import re

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
BASE = ROOT / "package/ALL_PHP_v3_12_adapter.ps1"
EXPECTED = "244b5c1385a5c5c298d9e6ea43d7b28ba65b4b4b7b131577cf45729a62de7f39"
raw = BASE.read_bytes()
if hashlib.sha256(raw).hexdigest() != EXPECTED:
    raise SystemExit("Package changed from reviewed post-prelude baseline; do not silently rebuild.")
before = raw.decode("utf-8-sig")
value = before


def replace(old, new):
    global value
    if value.count(old) != 1:
        raise ValueError(("anchor count", value.count(old), old[:100]))
    value = value.replace(old, new)


replace("param([string]$Code, [switch]$PhpDiagnostics)",
        "param([string]$Code, [switch]$PhpDiagnostics, [System.Collections.IDictionary]$CliContext = $null)\n"
        "        $isCli = $null -ne $CliContext\n"
        "        if ($isCli) {\n"
        "            $CliContext['ExitCode'] = [long]0\n"
        "            $CliContext['Terminated'] = $false\n"
        "            $CliContext['TerminationReason'] = $null\n"
        "            [void]$CliContext.Remove('CompileError')\n"
        "        }")
replace("        $state.Globals = $state.Vars", """        $state.Globals = $state.Vars
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
""")
replace("        )) { [void]$phpBuiltinNames.Add($builtinName) }", """        )) { [void]$phpBuiltinNames.Add($builtinName) }
        if ($isCli) {
            [void]$phpBuiltinNames.Add('exit')
            [void]$phpBuiltinNames.Add('die')
        }""")
replace("            switch ($token) {\n                'true'", """            if ($isCli -and $token -in @('exit','die') -and
                $state.Tokens[$state.Pos + 1] -cne '(') {
                [void](Next-Token)
                return [pscustomobject]@{ Kind='cli_exit'; Args=@() }
            }
            switch ($token) {
                'true'""")
replace("""            if ((Peek-Token) -cne $expected) {
                throw "ALL PHP: Expected '$expected', got '$(Peek-Token)'"
            }""", """            if ((Peek-Token) -cne $expected) {
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
            }""")
replace("""        while ((Peek-Token) -cne '(EOF)') {
            [void]$statements.Add((Read-Statement))
        }""", """        try {
            while ((Peek-Token) -cne '(EOF)') {
                [void]$statements.Add((Read-Statement))
            }
        } catch {
            if (-not $isCli -or -not ($CliContext.Keys -contains 'CompileError')) { throw }
            $compileError = $CliContext['CompileError']
            [Console]::Error.Write('Parse error: ' + $compileError.Message + ' in ' +
                $compileError.SourcePath + ' on line ' + $compileError.Line + "`n")
            $CliContext['ExitCode'] = [long]255
            $CliContext['Terminated'] = $true
            $CliContext['TerminationReason'] = 'compile_error'
            return
        }""")
replace("            if (-not $PhpDiagnostics) { return }", "            if (-not $PhpDiagnostics -and -not $isCli) { return }")
replace("            [Console]::Write(\"`n\" + $label + ': ' + $message + ' in ' + $state.ScriptName + ' on line ' + $state.Line + \"`n\")", """            $diagnostic = $label + ': ' + $message + ' in ' + $state.ScriptName + ' on line ' + $state.Line + "`n"
            if ($isCli) { [Console]::Error.Write($diagnostic) }
            else { [Console]::Write("`n" + $diagnostic) }""")
value = value.replace("if ($PhpDiagnostics -and $state.QuietDepth -eq 0)",
                      "if (($PhpDiagnostics -or $isCli) -and $state.QuietDepth -eq 0)")
replace("        function Invoke-PhpFunction([string]$name, $callArgs) {", """        function Invoke-PhpCliExit($callArgs) {
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
                elseif ($argument -is [string]) { [Console]::Write($argument) }
                elseif ($argument -is [bool]) { if ($argument) { $status = [long]1 } }
                elseif ($null -eq $argument) {
                    Write-PhpDiagnostic 8192 'exit(): Passing null to parameter #1 ($status) of type string|int is deprecated'
                }
                elseif ($argument -is [double]) {
                    if ([double]::IsNaN($argument)) {
                        Write-PhpDiagnostic 2 'unexpected NAN value was coerced to string'
                        [Console]::Write('NAN')
                    } elseif ([double]::IsInfinity($argument) -or
                        $argument -lt -9223372036854775808.0 -or $argument -ge 9223372036854775808.0) {
                        [Console]::Write((To-PhpText $argument))
                    } else {
                        $status = To-PhpInt $argument
                        if ([double]$status -ne $argument) {
                            Write-PhpDiagnostic 8192 ('Implicit conversion from float ' + (To-PhpText $argument) + ' to int loses precision')
                        }
                    }
                }
                elseif ((Is-PhpObject $argument) -and $null -ne (Find-OptionalPhpMethod $argument.Class '__toString')) {
                    [Console]::Write((To-PhpText $argument))
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
        function Invoke-PhpFunction([string]$name, $callArgs) {
            if ($isCli -and $name -in @('exit','die')) { Invoke-PhpCliExit $callArgs }
""")
replace("return $state.Functions.ContainsKey((To-PhpText $callArgs[0]))",
        "$functionName = To-PhpText $callArgs[0]\n"
        "                    return ($state.Functions.ContainsKey($functionName) -or ($isCli -and $functionName -ine '__all_throwable_string' -and $phpBuiltinNames.Contains($functionName)))")
replace("                'literal' { return $node.Value }", """                'literal' { return $node.Value }
                'cli_exit' { Invoke-PhpCliExit @() }""")
replace("        function Get-LValue($node) {", """        # isset/empty container reads are quiet, but offset expressions are normal
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
        function Get-LValue($node) {""")
replace("""                            $state.QuietDepth++
                            try {
                                $value = Invoke-PhpExpr $arg
                            } catch {
                                if ($_.Exception.Message -like 'ALL PHP: Undefined *') {
                                    $found = $false
                                } else { throw }
                            }
                            finally { $state.QuietDepth-- }""", """                            if ($isCli -and $arg.Kind -ceq 'index') {
                                $quiet = Get-PhpCliQuietPath $arg
                                $found = $quiet.Found
                                $value = $quiet.Value
                            } else {
                                $state.QuietDepth++
                                try {
                                    $value = Invoke-PhpExpr $arg
                                } catch {
                                    if ($_.Exception.Message -like 'ALL PHP: Undefined *') {
                                        $found = $false
                                    } else { throw }
                                }
                                finally { $state.QuietDepth-- }
                            }""")
replace("""                [void](Invoke-PhpValueCallable $handler @($uncaught))
                return""", """                if ($isCli) {
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
                }""")
# Every host catch must let this non-PHP control signal continue unwinding. In
# particular this bypasses the interpreter's manually executed PHP finally while
# automatic PowerShell finally blocks still restore call/loop/host state.
value = re.sub(r"\bcatch \{", "catch {\n                if ($isCli -and (Test-PhpCliExit $_)) { throw }", value)
replace("""        } catch {
                if ($isCli -and (Test-PhpCliExit $_)) { throw }
            $uncaught = Get-PhpThrown $_""", """        } catch {
            if ($isCli -and (Test-PhpCliExit $_)) { return }
            $uncaught = Get-PhpThrown $_""")
replace("            if ($null -eq $uncaught -or -not $PhpDiagnostics) { throw }", "            if ($null -eq $uncaught -or (-not $PhpDiagnostics -and -not $isCli)) { throw }")
replace("""            [Console]::Write("`nFatal error: Uncaught " +
                (Get-PhpThrowableString $uncaught) + "`n  thrown in " + (To-PhpText $uncaught.Props['file']) +
                ' on line ' + (To-PhpText $uncaught.Props['line']) + "`n")""", """            $fatal = 'Fatal error: Uncaught ' + (Get-PhpThrowableString $uncaught) +
                "`n  thrown in " + (To-PhpText $uncaught.Props['file']) +
                ' on line ' + (To-PhpText $uncaught.Props['line']) + "`n"
            if ($isCli) {
                [Console]::Error.Write($fatal)
                $CliContext['ExitCode'] = [long]255
                $CliContext['Terminated'] = $true
                $CliContext['TerminationReason'] = 'uncaught_php_throwable'
            } else { [Console]::Write("`n" + $fatal) }""")

candidate = HERE / "ALL_PHP_v3_18_candidate.ps1"
candidate.write_text(value, encoding="utf-8-sig")
(HERE / "base-adapter.snapshot.ps1").write_bytes(raw)
(HERE / "cli-context.patch").write_text("".join(difflib.unified_diff(
    before.splitlines(True), value.splitlines(True), fromfile="a/package/ALL_PHP_v3_12_adapter.ps1",
    tofile="b/package/ALL_PHP_v3_12_adapter.ps1")), encoding="utf-8")
provenance = {"status": "NOT_COMPLETE", "isolated_candidate": True,
              "base_path": str(BASE), "base_sha256": EXPECTED,
              "candidate_path": str(candidate), "candidate_sha256": hashlib.sha256(candidate.read_bytes()).hexdigest(),
              "package_modified_by_generator": False,
              "scope": "Optional CLI context, existing diagnostic routing and finite exit/die semantics; not full CLI/SAPI.",
              "pending": ["Other compiler/parser diagnostics beyond unexpected quoted string at required semicolon", "Full argv/stdin/ini/CLI flags", "strict_types and binary strings", "Shutdown/destructor/output-buffer lifecycle", "Exception-handler closure/internal stack-frame text", "Internal Throwable formatting helper remains publicly callable/hijackable; visibility filtering alone is not private binding", "Full string-offset/ArrayAccess/magic object quiet-read semantics", "All PHP semantics and Web/native ABI"]}
(HERE / "provenance.json").write_text(json.dumps(provenance, indent=2) + "\n", encoding="utf-8")
print(json.dumps(provenance))
