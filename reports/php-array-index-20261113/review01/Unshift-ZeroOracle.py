"""Four short reference-only probes for the zero-argument coverage gap."""
from pathlib import Path
import base64,hashlib,json,subprocess
HERE=Path(__file__).resolve().parent;php=Path.home()/'ALL_php_oracle/php-8.5.12-ts-x64/php.exe';target=HERE/'unshift-zero-reference.json'
if target.exists():raise SystemExit('Preserve observations')
cases=[
 ('negative-numeric',"$a=[-5=>'x'];array_unshift($a);$a[]='y';var_dump($a);"),
 ('sparse-positive',"$a=[8=>'x'];array_unshift($a);$a[]='y';var_dump($a);"),
 ('string-with-history',"$a=[8=>'gone','s'=>'x'];unset($a[8]);array_unshift($a);$a[-5]='y';$a[]='z';var_dump($a);"),
 ('empty-with-history',"$a=[8=>'gone'];unset($a[8]);array_unshift($a);$a[-5]='y';$a[]='z';var_dump($a);"),
]
rows=[]
for id,code in cases:
 argv=[str(php),'-n','-d','display_errors=stderr','-d','error_reporting=-1','-r',code];p=subprocess.run(argv,capture_output=True);rows.append({'id':id,'source':code,'source_sha256':hashlib.sha256(code.encode()).hexdigest(),'command':argv,'actual_exit':p.returncode,'stdout_base64':base64.b64encode(p.stdout).decode(),'stderr_base64':base64.b64encode(p.stderr).decode()});print(id+': '+repr(p.stdout))
target.write_text(json.dumps({'status':'OFFICIAL_REFERENCE_ONLY_NO_CANDIDATE_EXECUTION','php_sha256':hashlib.sha256(php.read_bytes()).hexdigest(),'probe_sha256':hashlib.sha256(Path(__file__).resolve().read_bytes()).hexdigest(),'rows':rows},indent=2)+'\n',encoding='utf-8')
