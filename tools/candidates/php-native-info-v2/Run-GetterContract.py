"""One test-only getter process; never counted as PHP compatibility cases."""
from pathlib import Path
import argparse
import base64
import hashlib
import json
import subprocess
import time

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def main():
 p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);a=p.parse_args();out=a.output.resolve();assert not out.exists();out.mkdir(parents=True)
 core=HERE/'out/getter-core01/php8ts.dll';host=HERE/'out/getter-host01/getter-contract.exe'
 records=[ROOT/'reports/php-native-info-v2-20261113/build-getter-core01/build.json',HERE/'out/getter-host01/build.json']
 paths={core,host,Path(__file__).resolve(),*records}
 for record_path in records:
  record=read(record_path);assert record['inputs_before']==record['inputs_after']
  for name,value in record['input_paths'].items():
   path=Path(value);assert sha(path)==record['inputs_before'][name];paths.add(path)
  if 'files'in record:
   for item in record['files']:
    path=host.parent/item['path'];assert sha(path)==item['sha256'];paths.add(path)
 before={str(path):sha(path)for path in sorted(paths)}
 command=[str(host),str(core),str(out/'contract.json'),sha(core)];began=time.perf_counter()
 try:
  result=subprocess.run(command,cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=30);state='EXITED';status=result.returncode;stdout=result.stdout;stderr=result.stderr
 except subprocess.TimeoutExpired as error:state='TIMEOUT';status=None;stdout=error.stdout or b'';stderr=error.stderr or b''
 (out/'stdout.bin').write_bytes(stdout);(out/'stderr.bin').write_bytes(stderr)
 after={str(path):sha(path)for path in sorted(paths)};native=read(out/'contract.json')if(out/'contract.json').exists()else None
 report={'status':'SYNTHETIC_GETTER_CONTRACT_NOT_PHP_COMPATIBILITY','command':command,'state':state,'actual_status':status,'elapsed_seconds':time.perf_counter()-began,'timeout_seconds':30,'inputs_before':before,'inputs_after':after,'inputs_unchanged':before==after,'stdout_base64':base64.b64encode(stdout).decode(),'stderr_base64':base64.b64encode(stderr).decode(),'contract':native}
 report['pass']=state=='EXITED'and status==0 and before==after and bool(native)and native['status']=='CONTROLLED_GETTER_PASS_NOT_PHP_COMPATIBILITY'
 (out/'process.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
 print(json.dumps({'pass':report['pass'],'state':state,'actual_status':status,'payload_cases':native.get('payload_cases_passed')if native else None,'inputs_unchanged':before==after}));return 0 if report['pass']else 1
if __name__=='__main__':raise SystemExit(main())
