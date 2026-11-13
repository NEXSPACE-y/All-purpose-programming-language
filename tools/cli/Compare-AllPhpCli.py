"""Compare the actual independent CLI executable with PHP, preserving raw channels."""
from pathlib import Path
import argparse
import base64
import hashlib
import json
import os
import subprocess
import sys
import time

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]
PROFILE=['-n','-d','display_errors=stderr','-d','error_reporting=-1','-d','date.timezone=UTC']

def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()

def process(argv,cwd,timeout,stdin):
    started=time.monotonic()
    try:
        r=subprocess.run(argv,cwd=cwd,input=stdin,capture_output=True,timeout=timeout,
                         creationflags=subprocess.CREATE_NO_WINDOW if os.name=='nt' else 0)
        out,err,code,state=r.stdout,r.stderr,r.returncode,'EXITED'
    except subprocess.TimeoutExpired as e:
        out,err,code,state=e.stdout or b'',e.stderr or b'',None,'TIMEOUT'
    return {'command':argv,'working_directory':str(cwd),'state':state,'exit_code':code,
            'elapsed_seconds':time.monotonic()-started,
            'stdout_base64':base64.b64encode(out).decode('ascii'),
            'stderr_base64':base64.b64encode(err).decode('ascii')}

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--executable',type=Path,required=True)
    ap.add_argument('--cases',type=Path,required=True)
    ap.add_argument('--output',type=Path,required=True)
    ap.add_argument('--php',type=Path,default=Path.home()/'ALL_php_oracle/php-8.5.12-ts-x64/php.exe')
    ap.add_argument('--timeout',type=float,default=30)
    a=ap.parse_args();out=a.output.resolve()
    if out.exists() or a.timeout<=0:ap.error('Use a fresh directory and positive timeout')
    paths={n:getattr(a,n).resolve(strict=True) for n in ['executable','cases','php']}
    paths.update(driver=Path(__file__).resolve(),adapter=paths['executable'].parent/'ALL_PHP_adapter.ps1',
                 host=paths['executable'].parent/'AllPhpCli.ps1')
    before={k:sha(p) for k,p in paths.items()}
    cases=json.loads(paths['cases'].read_text(encoding='utf-8-sig'))
    if not cases or len({c['id'] for c in cases})!=len(cases):ap.error('Need distinct nonempty case IDs')
    out.mkdir(parents=True);rows=[]
    (out/'run-context.json').write_text(json.dumps({'state':'STARTED_NOT_COMPLETED','driver_argv':[sys.executable,*sys.argv],'timeout_seconds':a.timeout,'inputs_before':before,'cases_planned':len(cases)},indent=2)+'\n',encoding='utf-8')
    for i,c in enumerate(cases):
        work=out/f'case-{i:04d}';work.mkdir()
        raw=c.get('code','').encode('utf-8');(work/'source-input.bin').write_bytes(raw)
        argv=[];stdin=b''
        if c['mode']=='body':argv=['-r',c['code']]
        elif c['mode']=='stdin':stdin=raw
        elif c['mode']=='file':
            file=work/c.get('filename','script.php');file.write_bytes(raw)
            arg=file.name if c.get('relative',False) else str(file)
            argv=(['-f',arg] if c.get('explicit_f',False) else [arg])
            if c.get('dashdash_before_file',False):argv=['--',arg]
        elif c['mode']=='missing':argv=[c['filename']]
        elif c['mode']=='raw':
            argv=c['arguments'];stdin=c.get('stdin','').encode('utf-8')
        else:raise ValueError('Unsupported case mode')
        argv+=c.get('tail',[])
        prefix=c.get('profile',PROFILE)
        oracle=process([str(paths['php']),*prefix,*argv],work,a.timeout,stdin)
        candidate=process([str(paths['executable']),*prefix,*argv],work,a.timeout,stdin)
        differences=[]
        if oracle['state']!='EXITED' or candidate['state']!='EXITED':differences.append('process_state')
        differences += [k for k in ['exit_code','stdout_base64','stderr_base64'] if oracle[k]!=candidate[k]]
        source_stable=sha(work/'source-input.bin')==hashlib.sha256(raw).hexdigest()
        if c['mode']=='file':source_stable=source_stable and file.read_bytes()==raw
        if not source_stable:differences.append('source_changed')
        row={'id':c['id'],'mode':c['mode'],'source_sha256':hashlib.sha256(raw).hexdigest(),
             'stdin_base64':base64.b64encode(stdin).decode('ascii'),'source_unchanged':source_stable,
             'verdict':'PASS' if not differences else 'DIFFERENT','differences':differences,
             'oracle':oracle,'candidate':candidate}
        rows.append(row)
        with (out/'results.jsonl').open('a',encoding='utf-8',newline='') as progress:
            progress.write(json.dumps(row,ensure_ascii=False)+'\n');progress.flush()
        print(row['verdict']+': '+c['id'],flush=True)
    after={k:sha(p) for k,p in paths.items()}
    report={'status':'NOT_COMPLETE','run_state':'COMPLETED','scope':'Actual C#/.NET Framework CLI host with own interpreter, selected modes/profile only; not full CLI/SAPI',
            'measurement':'Same argument strings and stdin bytes; exact stdout/stderr and actual process status; no normalization',
            'driver_argv':[sys.executable,*sys.argv],'timeout_seconds':a.timeout,'inputs_before':before,'inputs_after':after,
            'inputs_unchanged':before==after,'total':len(rows),'passed':sum(r['verdict']=='PASS' for r in rows),'results':rows}
    (out/'report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({k:report[k] for k in ['passed','total','inputs_unchanged']}))
    return 0 if report['passed']==report['total'] and before==after else 1

if __name__=='__main__':raise SystemExit(main())
