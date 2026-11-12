"""Small47c-based candidate: reject collisions with actually registered public functions."""
from pathlib import Path
import difflib
import hashlib
import json

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
BASE = ROOT / 'tools/candidates/php-native/ALL_PHP_native_candidate.ps1'
EXPECTED = '47c8edb9e39bffe3ed5475f2aeed7e36673a798d2f72baf0cb60abc39695322d'
OUTPUT = HERE / 'ALL_PHP_registered_function_candidate.ps1'

HELPERS = r'''
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
'''

PREFLIGHT = r'''
            # Direct global declarations are checked before any program output. Conditional
            # and nested declarations remain runtime checks in the functiondef registration path.
            foreach ($declaration in $statements) {
                if ($declaration.Kind -ceq 'functiondef' -and
                    (Test-PhpRegisteredPublicFunction $declaration.Name)) {
                    Throw-PhpRegisteredFunctionRedeclaration $declaration
                }
            }
'''


def main() -> None:
    before = BASE.read_bytes()
    if hashlib.sha256(before).hexdigest() != EXPECTED:
        raise SystemExit('Frozen native candidate differs from47c; refusing a new implicit baseline')
    if OUTPUT.exists():
        raise SystemExit('Output already exists; preserve the candidate and evidence')
    bom = before.startswith(b'\xef\xbb\xbf')
    text = before.decode('utf-8-sig').replace('\r\n', '\n')
    original = text
    edits = []

    def replace_once(anchor: str, replacement: str, label: str) -> None:
        nonlocal text
        matches = text.count(anchor)
        if matches != 1:
            raise SystemExit(f'{label}: expected1 anchor, got{matches}')
        text = text.replace(anchor, replacement, 1)
        edits.append(dict(label=label, anchor_matches=matches))

    anchor = '        function Get-PhpNativeName([string]$name) {'
    replace_once(anchor, HELPERS + '\n' + anchor, 'public-registration predicate and fatal control')
    anchor = "                'functiondef' {\n                    if ($state.Functions.ContainsKey($node.Name)) {"
    replacement = "                'functiondef' {\n                    if (Test-PhpRegisteredPublicFunction $node.Name) {\n                        Throw-PhpRegisteredFunctionRedeclaration $node\n                    }\n                    if ($state.Functions.ContainsKey($node.Name)) {"
    replace_once(anchor, replacement, 'conditional/nested declaration registration check')
    anchor = '        try {\n            foreach ($statement in $statements) {'
    replace_once(anchor, '        try {\n' + PREFLIGHT + '\n            foreach ($statement in $statements) {', 'direct-declaration compile-time check')
    result = (b'\xef\xbb\xbf' if bom else b'') + text.replace('\n', '\r\n').encode('utf-8')
    OUTPUT.write_bytes(result)
    patch = ''.join(difflib.unified_diff(original.splitlines(True), text.splitlines(True),
        fromfile='a/tools/candidates/php-native/ALL_PHP_native_candidate.ps1',
        tofile='b/tools/candidates/php-native-redeclare/ALL_PHP_registered_function_candidate.ps1'))
    (HERE / 'registered-function.patch').write_bytes(patch.encode('utf-8'))
    provenance = dict(status='ISOLATED_CANDIDATE_NOT_COMPLETE', base_path=str(BASE.relative_to(ROOT)),
        base_sha256=EXPECTED, candidate_path=str(OUTPUT.relative_to(ROOT)),
        candidate_sha256=hashlib.sha256(result).hexdigest(), base_unchanged=BASE.read_bytes() == before,
        edits=edits, retained_utf8_bom=bom, retained_line_endings='CRLF',
        scope='actual public phpBuiltinNames entries excluding old private helper plus NativeContext registrations; no925-name fabricated registry',
        untouched=['package', 'frozen native47c candidate', 'private-helper and import-alias candidates', 'user-vs-user redeclaration diagnostic'])
    (HERE / 'provenance.json').write_bytes((json.dumps(provenance, indent=2) + '\n').encode('utf-8'))
    print(json.dumps(provenance, indent=2))


if __name__ == '__main__':
    main()
