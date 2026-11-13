#!/usr/bin/env python3
"""Minimal synchronous diagnostic callback integration onto frozen package v3.19."""
from pathlib import Path
import argparse,difflib,hashlib,json
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
BASE=ROOT/'package/ALL_PHP_v3_12_adapter.ps1'
EXPECTED='113d0c2b967a8726cd9a9dec3f032a725ed9c98ee093c4aedd0a4830737f155b'

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output-directory',type=Path,default=HERE)
    args=parser.parse_args();destination=args.output_directory.resolve()
    target=destination/'ALL_PHP_v3_20_callback_candidate.ps1'
    if target.exists():raise SystemExit('Candidate exists; preserve measured revisions and select a fresh directory')
    raw=BASE.read_bytes();assert hashlib.sha256(raw).hexdigest()==EXPECTED,'Frozen native candidate hash mismatch'
    original=raw.decode('utf-8-sig');newline='\r\n'if'\r\n'in original else'\n';text=original.replace('\r\n','\n');edits=[]
    def replace(a,b):
        nonlocal text
        assert text.count(a)==1,(a[:80],text.count(a));text=text.replace(a,b);edits.append(a[:100])
    replace('if ($null -ne $state.ErrorHandler) {\n                Throw-PhpNativeUnsupported',
            'if ($null -ne $state.ErrorHandler -and -not $NativeContext.SynchronousCallbacksEnabled) {\n                Throw-PhpNativeUnsupported')
    replace("            } catch {\n                Throw-PhpNativeUnsupported ('scalar boundary: ' + $_.Exception.Message)\n            }",
            "            } catch {\n                if ($isCli -and (Test-PhpCliExit $_)) { throw }\n                $callbackThrowable = Get-PhpThrown $_\n                if ($null -ne $callbackThrowable) { Throw-PhpObject $callbackThrowable }\n                Throw-PhpNativeUnsupported ('scalar boundary: ' + $_.Exception.Message)\n            }")
    replace('            foreach ($event in $nativeResult.DiagnosticEvents) {\n                Write-PhpDiagnostic ([long]$event.Level) ([string]$event.Message)\n            }',
            '            foreach ($event in $nativeResult.DiagnosticEvents) {\n                if (-not $event.Delivered) { Write-PhpDiagnostic ([long]$event.Level) ([string]$event.Message) }\n            }')
    replace('        try {\n\n            # Direct global declarations','        # Same-thread Action delegate: managed reverse-P/Invoke catches exceptions.\n        # Older NativeContext hosts retain deferred diagnostics and their prior\n        # installed-handler rejection. Do not call an absent optional interface.\n        $nativeCallbackInstalled = $false\n        if ($null -ne $NativeContext -and\n            $null -ne $NativeContext.PSObject.Methods[\'SetDiagnosticHandler\'] -and\n            $null -ne $NativeContext.PSObject.Methods[\'ClearDiagnosticHandler\']) {\n            $nativeDiagnosticAction = [System.Action[long,string]] {\n                param([long]$nativeLevel, [string]$nativeMessage)\n                Write-PhpDiagnostic $nativeLevel $nativeMessage\n            }\n            $NativeContext.SetDiagnosticHandler($nativeDiagnosticAction)\n            $nativeCallbackInstalled = $true\n        }\n        try {\n\n            # Direct global declarations')
    assert text.endswith('        }\n    }\n}\n')
    text=text[:-len('        }\n    }\n}\n')]+'''        } finally {
            if ($nativeCallbackInstalled) { $NativeContext.ClearDiagnosticHandler() }
        }
    }
}
'''
    result=(b'\xef\xbb\xbf'if raw.startswith(b'\xef\xbb\xbf')else b'')+text.replace('\n',newline).encode('utf-8')
    destination.mkdir(parents=True,exist_ok=True);target.write_bytes(result)
    (destination/'callback-context.patch').write_text(''.join(difflib.unified_diff(original.replace('\r\n','\n').splitlines(True),text.splitlines(True),fromfile='package-v3_19-113d',tofile='v3_20-callback-integration')),encoding='utf-8')
    provenance={'status':'EXPERIMENTAL_NOT_ADOPTED','base_sha256':EXPECTED,'candidate_sha256':hashlib.sha256(result).hexdigest(),'edits':edits,'frozen_base_unchanged':BASE.read_bytes()==raw}
    provenance['optional_callback_interface_guard']=True
    provenance['legacy_scalar_unsupported_diagnostic_prefix_preserved']=True
    (destination/'candidate-provenance.json').write_text(json.dumps(provenance,indent=2)+'\n',encoding='utf-8');print(json.dumps(provenance))

if __name__=='__main__':main()
