#!/usr/bin/env python3
"""Generate the opt-in native candidate from the frozen reviewed v3.18 source."""
from pathlib import Path
import difflib
import hashlib
import json

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
BASE=ROOT/'tools/candidates/php-v3_18/ALL_PHP_v3_18_candidate.ps1'
EXPECTED='6cfde5e729ff594741b6bb3a254a5bcbd25c2a1ef62f2ad4c9f2b9642b1efb8a'

HELPERS=r'''
        # Optional, preloaded ALL-owned native ABI context. Its host owns Start/End.
        # No stock PHP runtime is called, and no native failure is retried elsewhere.
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
        function Invoke-PhpNativeFunction([string]$name, $values) {
            # Deferred events cannot reproduce synchronous user-handler callbacks.
            # Refuse before invoking native code while any user handler is installed.
            if ($null -ne $state.ErrorHandler) {
                Throw-PhpNativeUnsupported 'native calls with an installed PHP error handler require synchronous callbacks'
            }
            $nativeName = Get-PhpNativeName $name
            foreach ($item in @($values)) {
                if ($null -ne $item -and $item.PSObject.Properties['PhpType'] -and
                    $item.PhpType -ceq 'named_argument') {
                    Throw-PhpNativeUnsupported 'named native arguments are not implemented'
                }
            }
            try {
                # The frozen evaluator has no strict_types source implementation.
                # This candidate's selected source execution is weak/positional only.
                $nativeResult = $NativeContext.InvokeScalar($nativeName, [object[]]@($values), $false)
            } catch {
                Throw-PhpNativeUnsupported ('scalar boundary: ' + $_.Exception.Message)
            }
            # The native call has happened exactly once. Even an unsupported result
            # or encoding failure must never cause a retry through another runtime.
            if ($null -ne $nativeResult.Output -and $nativeResult.Output.Length -gt 0) {
                $nativeStdout = [Console]::OpenStandardOutput()
                $nativeStdout.Write($nativeResult.Output, 0, $nativeResult.Output.Length)
                $nativeStdout.Flush()
            }
            foreach ($event in $nativeResult.DiagnosticEvents) {
                Write-PhpDiagnostic ([long]$event.Level) ([string]$event.Message)
            }
            if (-not $nativeResult.Ok) {
                if ($nativeResult.Status -lt 0 -or $nativeResult.ErrorClass -ceq 'ALLNativeUnsupported') {
                    Throw-PhpNativeUnsupported ([string]$nativeResult.ErrorMessage)
                }
                Throw-PhpError ([string]$nativeResult.ErrorClass) ([string]$nativeResult.ErrorMessage)
            }
            return $nativeResult.Value
        }
'''


def main():
    raw=BASE.read_bytes()
    actual=hashlib.sha256(raw).hexdigest()
    if actual!=EXPECTED:raise SystemExit('Frozen v3.18 base hash mismatch; refusing to substitute another source')
    bom=raw.startswith(b'\xef\xbb\xbf')
    original=raw.decode('utf-8-sig')
    newline='\r\n' if '\r\n' in original else '\n'
    text=original.replace('\r\n','\n')
    edits=[]
    def replace(old,new,expected=1):
        nonlocal text
        count=text.count(old)
        if count!=expected:raise SystemExit(f'Native patch anchor count {count}, expected {expected}: {old[:100]!r}')
        text=text.replace(old,new)
        edits.append({'anchor':old[:140],'matches':count})
    replace('param([string]$Code, [switch]$PhpDiagnostics, [System.Collections.IDictionary]$CliContext = $null)',
            'param([string]$Code, [switch]$PhpDiagnostics, [System.Collections.IDictionary]$CliContext = $null, [object]$NativeContext = $null)')
    replace('        $state.Globals = $state.Vars\n','        $state.Globals = $state.Vars\n'+HELPERS+'\n')
    replace("throw 'ALL PHP: Named arguments for builtins are not yet supported'",
            "if (Test-PhpNativeFunction $name) { Throw-PhpNativeUnsupported 'named native arguments are not implemented' }\n                        throw 'ALL PHP: Named arguments for builtins are not yet supported'")
    replace("return ($state.Functions.ContainsKey($functionName) -or ($isCli -and $functionName -ine '__all_throwable_string' -and $phpBuiltinNames.Contains($functionName)))",
            "return ($state.Functions.ContainsKey($functionName) -or ($isCli -and $functionName -ine '__all_throwable_string' -and $phpBuiltinNames.Contains($functionName)) -or (Test-PhpNativeFunction $functionName))")
    replace("if ($value -is [string]) { return $state.Functions.ContainsKey($value) }",
            "if ($value -is [string]) { return ($state.Functions.ContainsKey($value) -or (Test-PhpNativeFunction $value)) }")
    replace("            if (-not $state.Functions.ContainsKey($name)) {\n                throw \"ALL PHP: Undefined function '$name'\"\n            }",
            "            if (-not $state.Functions.ContainsKey($name)) {\n                if (Test-PhpNativeFunction $name) { return (Invoke-PhpNativeFunction $name $callArgs) }\n                throw \"ALL PHP: Undefined function '$name'\"\n            }")
    replace('if ($state.Functions.ContainsKey($node.Name) -or $phpBuiltinNames.Contains($node.Name)) { return $node.Name }',
            'if ($state.Functions.ContainsKey($node.Name) -or $phpBuiltinNames.Contains($node.Name) -or (Test-PhpNativeFunction $node.Name)) { return $node.Name }')
    replace('if ($state.Functions.ContainsKey($node.Name)) { $node.ResolvedName = $node.Name }',
            'if ($state.Functions.ContainsKey($node.Name) -or (Test-PhpNativeFunction $node.Name)) { $node.ResolvedName = $node.Name }')
    replace('elseif ($state.Functions.ContainsKey($node.Fallback) -or $phpBuiltinNames.Contains($node.Fallback)) {',
            'elseif ($state.Functions.ContainsKey($node.Fallback) -or $phpBuiltinNames.Contains($node.Fallback) -or (Test-PhpNativeFunction $node.Fallback)) {')
    replace("                if (-not $state.Functions.ContainsKey($callName)) {\n                    throw 'ALL PHP: Reference return requires a declared function'",
            "                if (-not $state.Functions.ContainsKey($callName)) {\n                    if (Test-PhpNativeFunction $callName) { Throw-PhpNativeUnsupported 'native reference-return calls are not implemented' }\n                    throw 'ALL PHP: Reference return requires a declared function'")
    candidate=HERE/'ALL_PHP_native_candidate.ps1'
    result=(b'\xef\xbb\xbf' if bom else b'')+text.replace('\n',newline).encode('utf-8')
    candidate.write_bytes(result)
    (HERE/'native-context.patch').write_text(''.join(difflib.unified_diff(original.replace('\r\n','\n').splitlines(True),text.splitlines(True),fromfile='a/tools/candidates/php-v3_18/ALL_PHP_v3_18_candidate.ps1',tofile='b/tools/candidates/php-native/ALL_PHP_native_candidate.ps1')),encoding='utf-8')
    provenance={'status':'ISOLATED_NATIVE_INTEGRATION_CANDIDATE_NOT_COMPLETE','base_path':str(BASE.relative_to(ROOT)),'base_sha256':actual,'candidate_path':str(candidate.relative_to(ROOT)),'candidate_sha256':hashlib.sha256(result).hexdigest(),'optional_context':'NativeContext=null preserves the reviewed default path','source_profile':'preloaded native extension, weak positional scalar calls only','base_mutated':BASE.read_bytes()!=raw,'edits':edits}
    (HERE/'provenance.json').write_text(json.dumps(provenance,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(provenance,ensure_ascii=False))


if __name__=='__main__':main()
