"""Build an isolated import-name collision fix from the frozen native candidate."""
from pathlib import Path
import hashlib
import difflib
import json

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
BASE = ROOT / 'tools/candidates/php-native/ALL_PHP_native_candidate.ps1'
EXPECTED = '47c8edb9e39bffe3ed5475f2aeed7e36673a798d2f72baf0cb60abc39695322d'
raw = BASE.read_bytes()
if hashlib.sha256(raw).hexdigest() != EXPECTED:
    raise SystemExit('Frozen input hash differs; do not silently rebase.')
before = raw.decode('utf-8-sig')
value = before

def replace(old, new):
    global value
    if value.count(old) != 1:
        raise SystemExit('Expected exactly one replacement site')
    value = value.replace(old, new)

replace("""                                if ($itemKind -eq 'function') { $useFunc[$alias] = $target }
                                elseif ($itemKind -eq 'const') { $useConst[$alias] = $target }
                                else { $useClass[$alias] = $target }""".replace('\n', '\r\n'), """                                $imports = if ($itemKind -eq 'function') { $useFunc }
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
                                $imports[$alias] = $target""".replace('\n', '\r\n'))

replace("""                            $group = ''
                            while ($j -lt $total -and $tokens[$j] -cne ';') {""".replace('\n', '\r\n'), """                            # PHP attributes the entire import list to its first target token.
                            $importLine = [long]$lines[$j]
                            $group = ''
                            while ($j -lt $total -and $tokens[$j] -cne ';') {""".replace('\n', '\r\n'))

replace("""            $resolvedNames = Resolve-PhpNamespaceTokens $state.Tokens $state.TokenLines
            $state.Tokens = $resolvedNames.Tokens""".replace('\n', '\r\n'), """            try { $resolvedNames = Resolve-PhpNamespaceTokens $state.Tokens $state.TokenLines }
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
            $state.Tokens = $resolvedNames.Tokens""".replace('\n', '\r\n'))

result = b'\xef\xbb\xbf' + value.encode('utf-8')
candidate = HERE / 'ALL_PHP_import_alias_candidate.ps1'
candidate.write_bytes(result)
(HERE / 'import-alias.patch').write_text(''.join(difflib.unified_diff(before.splitlines(True), value.splitlines(True), fromfile='base47c', tofile='import-alias')), encoding='utf-8', newline='')
(HERE / 'provenance.json').write_text(json.dumps({'base':str(BASE), 'base_sha256':EXPECTED, 'candidate':str(candidate), 'candidate_sha256':hashlib.sha256(result).hexdigest(), 'scope':'Same symbol-space duplicate imports only; not all namespace compile errors', 'package_modified':False}, indent=2)+'\n', encoding='utf-8')
print(hashlib.sha256(result).hexdigest())
