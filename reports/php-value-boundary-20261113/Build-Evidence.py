"""Freeze json05 + selected symbols + value-boundary patch; parse, no runtime."""
from pathlib import Path
import argparse,base64,difflib,hashlib,importlib.util,json,re,subprocess,sys
sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[2];TOOLS=ROOT/'tools/candidates/php-byte-interpreter'
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def module(name):
 path=TOOLS/(name+'.py');spec=importlib.util.spec_from_file_location(name,path);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
def main():
 ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--output',type=Path,required=True);a=ap.parse_args();out=a.output.resolve()
 if out.exists():ap.error('Choose a fresh revision')
 vm=module('ValueBoundaryEdits');sm=module('SymbolEdits');base=TOOLS/'json05/ALL_PHP_byte_candidate.ps1';raw=base.read_bytes()
 assert sha(base)==vm.BASE_JSON05_SHA256 and sha(TOOLS/'SymbolEdits.py')==vm.SYMBOL_MODULE_SHA256
 before=sm.apply(raw.decode('utf-8-sig'));after=vm.apply(before)
 assert after.replace('\r\n','\n')==vm.apply(before.replace('\r\n','\n'))
 out.mkdir(parents=True);(out/'json05.snapshot.ps1').write_bytes(raw);(out/'SymbolEdits.snapshot.py').write_bytes((TOOLS/'SymbolEdits.py').read_bytes());(out/'ValueBoundaryEdits.snapshot.py').write_bytes((TOOLS/'ValueBoundaryEdits.py').read_bytes())
 (out/'post-symbol-before-boundary.snapshot.ps1').write_bytes(b'\xef\xbb\xbf'+before.encode('utf-8'))
 candidate=out/'ALL_PHP_value_boundary_candidate.ps1';candidate.write_bytes(b'\xef\xbb\xbf'+after.encode('utf-8'))
 (out/'source.patch').write_text(''.join(difflib.unified_diff(before.splitlines(True),after.splitlines(True),fromfile='json05-plus-symbols',tofile='value-boundary-candidate')),encoding='utf-8',newline='')
 # A textual inventory is a review aid, not proof every match needs changing.
 hits=[];scope='Run host/source setup'
 for n,line in enumerate(before.splitlines(),1):
  match=re.match(r'        function ([\w-]+)',line)
  if match:scope=match[1]
  if re.search(r'-is(?:not)?\s*\[string\]|\[string\]\$|-(?:ceq|cne)\b',line):hits.append({'line':n,'function_context':scope,'source':line.strip()})
 (out/'boundary-text-inventory.json').write_text(json.dumps({'scope':'Read-only textual candidate locations; metadata/source tokens/internal tags must not be converted indiscriminately','source_sha256':sha(out/'post-symbol-before-boundary.snapshot.ps1'),'hits':hits},indent=2)+'\n',encoding='utf-8')
 command='$text=[Console]::In.ReadToEnd();$tokens=$null;$errors=$null;[void][Management.Automation.Language.Parser]::ParseInput($text,[ref]$tokens,[ref]$errors);foreach($e in $errors){[Console]::Error.WriteLine($e.ToString())};if($errors.Count){exit 1};[Console]::WriteLine("Parse OK")'
 args=['C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe','-NoLogo','-NoProfile','-NonInteractive','-Command',command]
 proc=subprocess.run(args,input=after.encode('utf-8'),capture_output=True)
 (out/'parse.json').write_text(json.dumps({'command':args,'actual_exit':proc.returncode,'stdout_base64':base64.b64encode(proc.stdout).decode(),'stderr_base64':base64.b64encode(proc.stderr).decode(),'input_candidate_sha256':sha(candidate),'scope':'Actual candidate source parse only, not runtime execution'},indent=2)+'\n',encoding='utf-8')
 record={'status':'BUILT_PARSED_NOT_RUNTIME_VERIFIED','base_sha256':sha(base),'symbol_module_sha256':sha(TOOLS/'SymbolEdits.py'),'value_module_sha256':sha(TOOLS/'ValueBoundaryEdits.py'),'candidate_sha256':sha(candidate),'post_symbol_starting_sha256':sha(out/'post-symbol-before-boundary.snapshot.ps1'),'builder_sha256':sha(Path(__file__).resolve()),'base_unchanged':raw==base.read_bytes(),'crlf_retained':after.count('\r\n')==after.count('\n'),'lf_composition_same':True,'parser_exit':proc.returncode,'stock_php_runtime_delegation':False,'package_modified':False,'textual_inventory_hits':len(hits)}
 (out/'provenance.json').write_text(json.dumps(record,indent=2)+'\n',encoding='utf-8');print(json.dumps(record))
 if proc.stderr:print(proc.stderr.decode('utf-8',errors='backslashreplace'))
 return proc.returncode
if __name__=='__main__':raise SystemExit(main())
