#!/usr/bin/env python3
"""Independent synchronous-callback evaluator prototype from frozen native47c."""
from pathlib import Path
import difflib,hashlib,json
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
BASE=ROOT/'tools/candidates/php-native/ALL_PHP_native_candidate.ps1'
EXPECTED='47c8edb9e39bffe3ed5475f2aeed7e36673a798d2f72baf0cb60abc39695322d'

def main():
    raw=BASE.read_bytes();assert hashlib.sha256(raw).hexdigest()==EXPECTED,'Frozen native candidate hash mismatch'
    original=raw.decode('utf-8-sig');newline='\r\n'if'\r\n'in original else'\n';text=original.replace('\r\n','\n');edits=[]
    def replace(a,b):
        nonlocal text
        assert text.count(a)==1,(a[:80],text.count(a));text=text.replace(a,b);edits.append(a[:100])
    replace('if ($null -ne $state.ErrorHandler) {\n                Throw-PhpNativeUnsupported',
            'if ($null -ne $state.ErrorHandler -and -not $NativeContext.SynchronousCallbacksEnabled) {\n                Throw-PhpNativeUnsupported')
    replace("            } catch {\n                Throw-PhpNativeUnsupported ('scalar boundary: ' + $_.Exception.Message)\n            }",
            "            } catch {\n                if ($isCli -and (Test-PhpCliExit $_)) { throw }\n                $callbackThrowable = Get-PhpThrown $_\n                if ($null -ne $callbackThrowable) { Throw-PhpObject $callbackThrowable }\n                Throw-PhpNativeUnsupported ('callback/scalar boundary: ' + $_.Exception.Message)\n            }")
    replace('            foreach ($event in $nativeResult.DiagnosticEvents) {\n                Write-PhpDiagnostic ([long]$event.Level) ([string]$event.Message)\n            }',
            '            foreach ($event in $nativeResult.DiagnosticEvents) {\n                if (-not $event.Delivered) { Write-PhpDiagnostic ([long]$event.Level) ([string]$event.Message) }\n            }')
    replace('        try {\n            foreach ($statement in $statements) {',r'''        # Same-thread Action delegate: managed reverse-P/Invoke catches exceptions.
        $nativeCallbackInstalled = $false
        if ($null -ne $NativeContext) {
            $nativeDiagnosticAction = [System.Action[long,string]] {
                param([long]$nativeLevel, [string]$nativeMessage)
                Write-PhpDiagnostic $nativeLevel $nativeMessage
            }
            $NativeContext.SetDiagnosticHandler($nativeDiagnosticAction)
            $nativeCallbackInstalled = $true
        }
        try {
            foreach ($statement in $statements) {''')
    assert text.endswith('        }\n    }\n}\n')
    text=text[:-len('        }\n    }\n}\n')]+'''        } finally {
            if ($nativeCallbackInstalled) { $NativeContext.ClearDiagnosticHandler() }
        }
    }
}
'''
    result=(b'\xef\xbb\xbf'if raw.startswith(b'\xef\xbb\xbf')else b'')+text.replace('\n',newline).encode('utf-8')
    target=HERE/'ALL_PHP_callback_candidate.ps1';target.write_bytes(result)
    (HERE/'callback-context.patch').write_text(''.join(difflib.unified_diff(original.replace('\r\n','\n').splitlines(True),text.splitlines(True),fromfile='frozen-native47c',tofile='callback-prototype')),encoding='utf-8')
    provenance={'status':'EXPERIMENTAL_NOT_ADOPTED','base_sha256':EXPECTED,'candidate_sha256':hashlib.sha256(result).hexdigest(),'edits':edits,'frozen_base_unchanged':BASE.read_bytes()==raw}
    (HERE/'candidate-provenance.json').write_text(json.dumps(provenance,indent=2)+'\n',encoding='utf-8');print(json.dumps(provenance))

if __name__=='__main__':main()
