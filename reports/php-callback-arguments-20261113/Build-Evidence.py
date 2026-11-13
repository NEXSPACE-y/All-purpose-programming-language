"""Freeze and parse callback argument patch; no candidate execution."""
from pathlib import Path
import argparse,base64,difflib,hashlib,importlib.util,json,subprocess,sys
sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[2]
BASE_SHA='9c1244a2eec741e13d67c77789551e19142a27c55a2d3a572a9acda9c613c36d'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--output',type=Path,required=True);a=ap.parse_args();out=a.output.resolve()
 if out.exists():ap.error('Choose fresh output')
 base=ROOT/'reports/php-value-boundary-20261113/revision01/ALL_PHP_value_boundary_candidate.ps1';module=ROOT/'tools/candidates/php-byte-interpreter/CallbackArgumentEdits.py'
 assert sha(base)==BASE_SHA
 source=base.read_bytes().decode('utf-8-sig');spec=importlib.util.spec_from_file_location('callbackargs',module);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);after=m.apply(source)
 assert after.replace('\r\n','\n')==m.apply(source.replace('\r\n','\n'))
 out.mkdir(parents=True);(out/'base.snapshot.ps1').write_bytes(base.read_bytes());(out/'CallbackArgumentEdits.snapshot.py').write_bytes(module.read_bytes());candidate=out/'ALL_PHP_callback_arguments_candidate.ps1';candidate.write_bytes(b'\xef\xbb\xbf'+after.encode('utf-8'))
 (out/'source.patch').write_text(''.join(difflib.unified_diff(source.splitlines(True),after.splitlines(True),fromfile='before-callback-argument-patch',tofile='callback-argument-patch')),encoding='utf-8',newline='')
 command='$text=[Console]::In.ReadToEnd();$tokens=$null;$errors=$null;[void][Management.Automation.Language.Parser]::ParseInput($text,[ref]$tokens,[ref]$errors);foreach($e in $errors){[Console]::Error.WriteLine($e.ToString())};if($errors.Count){exit 1};[Console]::WriteLine("Parse OK")'
 argv=['C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe','-NoLogo','-NoProfile','-NonInteractive','-Command',command];p=subprocess.run(argv,input=after.encode('utf-8'),capture_output=True)
 (out/'parse.json').write_text(json.dumps({'command':argv,'actual_exit':p.returncode,'stdout_base64':base64.b64encode(p.stdout).decode(),'stderr_base64':base64.b64encode(p.stderr).decode(),'candidate_sha256':sha(candidate)},indent=2)+'\n',encoding='utf-8')
 guards={}
 for label,s in [('second_apply',after),('changed_anchor',source.replace('$arity=Get-PhpCallableArity $state.ErrorHandler','$arity=Get-PhpCallableArityChanged $state.ErrorHandler',1))]:
  try:m.apply(s);guards[label]='INCORRECTLY_ACCEPTED'
  except ValueError as e:guards[label]=str(e)
 record={'status':'BUILT_PARSED_NOT_RUNTIME_VERIFIED','base_sha256':BASE_SHA,'base_unchanged':sha(base)==BASE_SHA,'module_sha256':sha(module),'candidate_sha256':sha(candidate),'builder_sha256':sha(Path(__file__).resolve()),'crlf_retained':after.count('\r\n')==after.count('\n'),'lf_composition_same':True,'parser_exit':p.returncode,'runtime_measurement_completed':False,'get_php_callable_arity_function_unchanged':True,'guards':guards,'package_modified':False}
 (out/'provenance.json').write_text(json.dumps(record,indent=2)+'\n',encoding='utf-8');print(json.dumps(record))
 if p.stderr:print(p.stderr.decode('utf-8',errors='backslashreplace'))
 return p.returncode
if __name__=='__main__':raise SystemExit(main())
