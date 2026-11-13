"""Short official-reference-only trigger/user_error conversion observations."""
from pathlib import Path
import base64,hashlib,json,subprocess
HERE=Path(__file__).resolve().parent;template=HERE/'Oracle-TriggerTemplate.php';php=Path.home()/'ALL_php_oracle/php-8.5.12-ts-x64/php.exe';sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
for strict in [0,1]:
 source=HERE/('oracle-strict'+str(strict)+'.php')
 if source.exists():raise SystemExit('Preserve prior observations')
 source.write_text(template.read_text(encoding='utf-8-sig').replace('__STRICT__',str(strict)),encoding='utf-8')
 argv=[str(php),'-n','-d','display_errors=stderr','-d','error_reporting=-1',str(source)];p=subprocess.run(argv,capture_output=True)
 report={'command':argv,'actual_exit':p.returncode,'source_sha256':sha(source),'template_sha256':sha(template),'php_sha256':sha(php),'stdout_base64':base64.b64encode(p.stdout).decode(),'stderr_base64':base64.b64encode(p.stderr).decode(),'observed':json.loads(p.stdout) if p.returncode==0 else None}
 (HERE/('oracle-strict'+str(strict)+'.json')).write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8');print(json.dumps({'strict':strict,'exit':p.returncode,'stderr_bytes':len(p.stderr),'observations':len(report['observed']) if report['observed'] else 0}))
 if p.returncode:raise SystemExit(p.returncode)
 for row in report['observed']:
  if row['function'] in ['trigger_error','USER_ERROR'] and (row['id'] in ['null','array','stringable'] or row['argument']=='count'):
   print(json.dumps(row,ensure_ascii=True))
