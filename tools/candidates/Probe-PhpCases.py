"""Record pinned PHP observations only; never candidate conformance passes."""
from pathlib import Path
import argparse
import base64
import hashlib
import json
import subprocess
import sys
import time

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--cases',type=Path,required=True)
parser.add_argument('--output',type=Path,required=True)
parser.add_argument('--php',type=Path,default=Path.home()/'ALL_php_oracle/php-8.5.12-ts-x64/php.exe')
args=parser.parse_args()
out=args.output.resolve()
if out.exists():raise SystemExit('Preserve prior measurements: use a fresh output directory')
paths={'cases':args.cases.resolve(strict=True),'php':args.php.resolve(strict=True),'driver':Path(__file__).resolve()}
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
before={name:sha(p) for name,p in paths.items()}
if before['php']!='0ac893499799256db6d3a54b0da73692e02311493922e6e4f86a062674a77d66':
    raise SystemExit('Oracle differs from approved pinned PHP8.5.12')
cases=json.loads(paths['cases'].read_text(encoding='utf-8-sig'))
if not cases or len({c['id'] for c in cases})!=len(cases) or any(c.get('mode')!='body' for c in cases):
    raise SystemExit('This oracle probe accepts distinct nonempty body-mode cases only')
out.mkdir(parents=True)
(out/'run-context.json').write_text(json.dumps({'state':'ORACLE_STARTED_NOT_COMPLETED','candidate_invocations':0,'inputs_before':before,'command':[sys.executable,*sys.argv]},indent=2)+'\n',encoding='utf-8')
rows=[]
for i,case in enumerate(cases):
    work=out/f'case-{i:04d}'
    work.mkdir()
    raw=case['code'].encode('utf-8')
    (work/'source-input.bin').write_bytes(raw)
    command=[str(paths['php']),'-n','-d','display_errors=stderr','-d','error_reporting=-1','-d','date.timezone=UTC','-r',case['code']]
    start=time.monotonic()
    state='EXITED'
    # Keep even nonterminating reference programs' bytes on disk rather than
    # losing the TimeoutExpired output or accumulating an unbounded RAM buffer.
    with (work/'stdout.bin').open('wb') as stdout, (work/'stderr.bin').open('wb') as stderr:
        process=subprocess.Popen(command,cwd=work,stdout=stdout,stderr=stderr,creationflags=subprocess.CREATE_NO_WINDOW)
        try:actual_code=process.wait(timeout=30)
        except subprocess.TimeoutExpired:
            state='TIMEOUT';actual_code=None
            process.kill();process.wait()
    row={'id':case['id'],'command':command,'source_sha256':hashlib.sha256(raw).hexdigest(),'actual_exit_code':actual_code,'state':state,'elapsed_seconds':time.monotonic()-start}
    for channel in ['stdout','stderr']:
        file=work/(channel+'.bin')
        hasher=hashlib.sha256()
        with file.open('rb') as captured:
            for block in iter(lambda:captured.read(1024*1024),b''):hasher.update(block)
        row[channel+'_bytes']=file.stat().st_size
        row[channel+'_sha256']=hasher.hexdigest()
        row[channel+'_base64']=base64.b64encode(file.read_bytes()).decode('ascii') if file.stat().st_size<=1024*1024 else None
    rows.append(row)
    with (out/'records.jsonl').open('a',encoding='utf-8') as journal:journal.write(json.dumps(row)+'\n')
    print(case['id']+' '+state+' stdout='+str(row['stdout_bytes'])+' stderr='+str(row['stderr_bytes']),flush=True)
after={name:sha(p) for name,p in paths.items()}
(out/'report.json').write_text(json.dumps({'status':'ORACLE_ONLY_NOT_CANDIDATE_VERIFICATION','candidate_invocations':0,'total':len(rows),'inputs_before':before,'inputs_after':after,'inputs_unchanged':before==after,'records':rows},indent=2)+'\n',encoding='utf-8')
if before!=after:raise SystemExit('Probe inputs changed')
