"""Additional controls preserve the original twelve weak cases unchanged."""
from pathlib import Path
import json,hashlib,subprocess,base64
HERE=Path(__file__).resolve().parent;target=HERE/'enum-typecase2.cases.json'
if target.exists():raise SystemExit('Preserve prior definitions')
rows=[dict(id='enum.weak.uppercase-string-type',mode='body',code='enum E:STRING{case A="7";}echo E::from(7)->name;'),dict(id='enum.weak.uppercase-int-type',mode='body',code='enum E:INT{case A=7;}echo E::from("7")->name;')]
target.write_text(json.dumps(rows,indent=2)+'\n',encoding='utf-8')
php=Path.home()/'ALL_php_oracle/php-8.5.12-ts-x64/php.exe';observed=[]
for case in rows:
 argv=[str(php),'-n','-d','display_errors=stderr','-d','error_reporting=-1','-r',case['code']];p=subprocess.run(argv,capture_output=True);observed.append(dict(id=case['id'],command=argv,actual_exit=p.returncode,source_sha256=hashlib.sha256(case['code'].encode()).hexdigest(),stdout_base64=base64.b64encode(p.stdout).decode(),stderr_base64=base64.b64encode(p.stderr).decode()))
(HERE/'oracle-typecase2.json').write_text(json.dumps({'scope':'Official reference-only uppercase backing metadata controls','cases_sha256':hashlib.sha256(target.read_bytes()).hexdigest(),'php_sha256':hashlib.sha256(php.read_bytes()).hexdigest(),'observed':observed},indent=2)+'\n',encoding='utf-8')
print(json.dumps([{'id':r['id'],'exit':r['actual_exit'],'stdout_base64':r['stdout_base64'],'stderr_base64':r['stderr_base64']} for r in observed]))
