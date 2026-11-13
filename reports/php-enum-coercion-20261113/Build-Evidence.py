"""Freeze/parse the weak enum patch on composed09 without executing candidate."""
from pathlib import Path
import argparse,base64,difflib,hashlib,importlib.util,json,subprocess,sys
sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[2];EXPECTED='6ee5992ebe6226d470bc4bf643b4f0a08ccb6a32861114fa0b4fe3eb1405b3f0'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--output',type=Path,required=True);a=ap.parse_args();out=a.output.resolve()
 if out.exists():ap.error('Choose fresh revision')
 base=ROOT/'tools/candidates/php-byte-interpreter/composed09/ALL_PHP_byte_candidate.ps1';module=ROOT/'tools/candidates/php-byte-interpreter/EnumCoercionEdits.py';assert sha(base)==EXPECTED
 raw=base.read_bytes();source=raw.decode('utf-8-sig');spec=importlib.util.spec_from_file_location('enumedit',module);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);after=m.apply(source);assert after.replace('\r\n','\n')==m.apply(source.replace('\r\n','\n'))
 out.mkdir(parents=True);(out/'base.snapshot.ps1').write_bytes(raw);(out/'EnumCoercionEdits.snapshot.py').write_bytes(module.read_bytes());candidate=out/'ALL_PHP_enum_weak_candidate.ps1';candidate.write_bytes(b'\xef\xbb\xbf'+after.encode('utf-8'))
 (out/'source.patch').write_text(''.join(difflib.unified_diff(source.splitlines(True),after.splitlines(True),fromfile='composed09',tofile='weak-enum-patch')),encoding='utf-8',newline='')
 command='$text=[Console]::In.ReadToEnd();$tokens=$null;$errors=$null;[void][Management.Automation.Language.Parser]::ParseInput($text,[ref]$tokens,[ref]$errors);foreach($e in $errors){[Console]::Error.WriteLine($e.ToString())};if($errors.Count){exit 1};[Console]::WriteLine("Parse OK")'
 argv=['C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe','-NoLogo','-NoProfile','-NonInteractive','-Command',command];p=subprocess.run(argv,input=after.encode('utf-8'),capture_output=True)
 (out/'parse.json').write_text(json.dumps({'command':argv,'actual_exit':p.returncode,'stdout_base64':base64.b64encode(p.stdout).decode(),'stderr_base64':base64.b64encode(p.stderr).decode(),'candidate_sha256':sha(candidate)},indent=2)+'\n',encoding='utf-8')
 guard=''
 try:m.apply(after);guard='INCORRECTLY_ACCEPTED'
 except ValueError as e:guard=str(e)
 record={'status':'BUILT_PARSED_WEAK_ENUM_PATCH_NOT_RUNTIME_VERIFIED','base_sha256':sha(base),'base_unchanged':raw==base.read_bytes(),'module_sha256':sha(module),'candidate_sha256':sha(candidate),'builder_sha256':sha(Path(__file__).resolve()),'crlf_retained':after.count('\r\n')==after.count('\n'),'lf_composition_same':True,'parser_exit':p.returncode,'second_apply_guard':guard,'strict_types_implemented':False,'new_nominal_strict_flag_added':False,'package_modified':False,'runtime_measurement_completed':False}
 (out/'provenance.json').write_text(json.dumps(record,indent=2)+'\n',encoding='utf-8');print(json.dumps(record))
 if p.stderr:print(p.stderr.decode('utf-8',errors='backslashreplace'))
 return p.returncode
if __name__=='__main__':raise SystemExit(main())
