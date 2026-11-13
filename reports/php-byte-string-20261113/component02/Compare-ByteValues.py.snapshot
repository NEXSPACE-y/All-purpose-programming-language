"""Component-level bytes/protocol proof; not PHP source interpretation."""
from pathlib import Path
import argparse,base64,hashlib,json,subprocess,sys,time

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def run(command,cwd,timeout):
    start=time.monotonic()
    try:
        p=subprocess.run(command,cwd=cwd,stdin=subprocess.DEVNULL,capture_output=True,timeout=timeout,creationflags=subprocess.CREATE_NO_WINDOW)
        out,err,code,state=p.stdout,p.stderr,p.returncode,'EXITED'
    except subprocess.TimeoutExpired as e:out,err,code,state=e.stdout or b'',e.stderr or b'',None,'TIMEOUT'
    return {'command':command,'state':state,'exit_code':code,'elapsed_seconds':time.monotonic()-start,'stdout_base64':base64.b64encode(out).decode(),'stderr_base64':base64.b64encode(err).decode()}
def diffs(a,b):
    result=[]
    if a['state']!='EXITED' or b['state']!='EXITED':result.append('process_state')
    result += [k for k in ['exit_code','stdout_base64','stderr_base64'] if a[k]!=b[k]]
    return result
def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--assembly',type=Path,required=True);p.add_argument('--cases',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--timeout',type=float,default=30)
    a=p.parse_args();out=a.output.resolve()
    if out.exists() or a.timeout<=0:p.error('Fresh output and positive timeout required')
    paths={'assembly':a.assembly.resolve(strict=True),'cases':a.cases.resolve(strict=True),'php':Path.home()/'ALL_php_oracle/php-8.5.12-ts-x64/php.exe','powershell':Path('C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe'),'driver':Path(__file__).resolve(),'oracle_worker':HERE/'Reference-ByteValues.php','component_worker':HERE/'Invoke-ByteValues.ps1','raw_oracle':HERE/'Reference-RawBytes.php','raw_component':HERE/'Invoke-RawBytes.ps1','source':HERE/'PhpByteValues.cs'}
    before={k:sha(f) for k,f in paths.items()};cases=json.loads(paths['cases'].read_text(encoding='utf-8-sig'))
    if len({c['id'] for c in cases})!=len(cases):p.error('Need unique IDs')
    out.mkdir(parents=True)
    profile=['-n','-d','display_errors=stderr','-d','error_reporting=-1','-d','date.timezone=UTC']
    oracle=run([str(paths['php']),*profile,str(paths['oracle_worker']),str(paths['cases'])],out,a.timeout)
    component=run([str(paths['powershell']),'-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',str(paths['component_worker']),'-CasesPath',str(paths['cases']),'-AssemblyPath',str(paths['assembly'])],out,a.timeout)
    for name,r in [('oracle',oracle),('component',component)]:
        for channel in ['stdout','stderr']:(out/(name+'.'+channel+'.bin')).write_bytes(base64.b64decode(r[channel+'_base64']))
    ar=base64.b64decode(oracle['stdout_base64']).splitlines();br=base64.b64decode(component['stdout_base64']).splitlines()
    rows=[]
    for i,c in enumerate(cases):
        x=ar[i] if i<len(ar) else None;y=br[i] if i<len(br) else None
        rows.append({'id':c['id'],'matched':x is not None and x==y,'oracle_record_base64':None if x is None else base64.b64encode(x).decode(),'component_record_base64':None if y is None else base64.b64encode(y).decode()})
    raw_rows=[]
    for i,raw in enumerate([b'\xff',b'\x00A\xff\x00',bytes.fromhex('eda080'),bytes(range(256))]):
        data=base64.b64encode(raw).decode()
        x=run([str(paths['php']),*profile,str(paths['raw_oracle']),data],out,a.timeout)
        y=run([str(paths['powershell']),'-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',str(paths['raw_component']),'-AssemblyPath',str(paths['assembly']),'-DataBase64',data],out,a.timeout)
        differences=diffs(x,y);raw_rows.append({'id':'raw-'+str(i),'input_base64':data,'matched':not differences and base64.b64decode(y['stdout_base64'])==raw,'differences':differences,'oracle':x,'component':y})
    after={k:sha(f) for k,f in paths.items()}
    report={'status':'COMPONENT_PROOF_NOT_INTERPRETER_COMPATIBILITY','scope':'Isolated immutable managed bytes and typed-key primitives, not PHP parser/runtime/ABI/ALL integration','driver_argv':[sys.executable,*sys.argv],'timeout_seconds':a.timeout,'inputs_before':before,'inputs_after':after,'inputs_unchanged':before==after,'protocol_total':len(rows),'protocol_matched':sum(r['matched'] for r in rows),'protocol_line_counts':{'oracle':len(ar),'component':len(br)},'protocol_process_differences':diffs(oracle,component),'oracle':oracle,'component':component,'results':rows,'raw_output_results':raw_rows,'full_php_compatibility':False}
    (out/'report.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({k:report[k] for k in ['protocol_total','protocol_matched','protocol_process_differences','inputs_unchanged']}));print('raw matched',sum(x['matched'] for x in raw_rows),'/',len(raw_rows))
    return 0 if all(r['matched'] for r in rows) and len(ar)==len(br)==len(rows) and not report['protocol_process_differences'] and all(r['matched'] for r in raw_rows) and before==after else 1
if __name__=='__main__':raise SystemExit(main())
