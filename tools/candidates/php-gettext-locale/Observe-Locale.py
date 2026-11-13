"""Observe separate pinned-PHP locale controls after root's runtime signal."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import subprocess
import sys
import time

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
REPORT=ROOT/'reports/php-gettext-locale-20261113'
PREP=REPORT/'prepared01'
PHP=Path('C:/Users/rinpa/ALL_php_oracle/php-8.5.12-ts-x64/php.exe')
EXTENSION=PHP.parent/'ext/php_gettext.dll'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
read=lambda p:json.loads(p.read_text(encoding='utf-8-sig'))
save=lambda p,x:p.write_text(json.dumps(x,indent=2)+'\n',encoding='utf-8')
KEYS=['LC_ALL','LC_MESSAGES','LANG','LANGUAGE','LC_CTYPE']

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--execute',action='store_true');parser.add_argument('--output',type=Path,required=True);parser.add_argument('--case',action='append');args=parser.parse_args()
    if not args.execute:raise SystemExit('Prepared only; await root runtime signal before --execute')
    out=args.output.resolve();assert out.is_relative_to(REPORT)and not out.exists()
    assert sha(PHP)=='0ac893499799256db6d3a54b0da73692e02311493922e6e4f86a062674a77d66'
    assert sha(EXTENSION)=='ed395f80018920ba1b4551cdc33dd89871eb8b8ef362b1515ae93c0e7f1de3ad'
    assert sha(PREP/'manifest.json')=='8c96bdfd924e005cdec3b689482810be908c78d0b883ecb6f640816750856a4e'
    manifest=read(PREP/'manifest.json');inputs={p:sha(p)for p in [PHP,EXTENSION,Path(__file__).resolve(),PREP/'manifest.json']}
    for relative,row in manifest['files'].items():path=PREP/relative;assert sha(path)==row['sha256'];inputs[path]=row['sha256']
    provenance=read(PREP/'provenance.json')
    for label in ['original_mo','copied_mo']:
        path=Path(provenance[label]);assert sha(path)==provenance[label+'_sha256'];inputs[path]=sha(path)
    cases=read(PREP/'controls.json')
    if args.case:
        assert len(set(args.case))==len(args.case)and set(args.case)<={c['id']for c in cases}
        cases=[c for identity in args.case for c in cases if c['id']==identity]
    before={str(p):sha(p)for p in inputs};out.mkdir()
    save(out/'run-context.json',{'status':'ORACLE_CONTROLS_STARTED_NOT_COMPLETED','candidate_execution_count':0,'inputs_before':before,'timeout_seconds':30,'driver_argv':[sys.executable,*sys.argv],'cases':[c['id']for c in cases]})
    rows=[]
    for index,case in enumerate(cases):
        work=out/(str(index).zfill(2)+'-'+case['id']);work.mkdir();environment=os.environ.copy()
        for key,value in case['environment_overrides'].items():
            if value is None:environment.pop(key,None)
            else:environment[key]=value
        snapshot={key:environment.get(key)for key in KEYS}
        command=[str(PHP),'-n','-d','extension='+str(EXTENSION),'-d','display_errors=stderr','-d','error_reporting=-1','-d','date.timezone=UTC',case['source']]
        began=time.monotonic();state='EXITED'
        with(work/'stdout.bin').open('wb')as stdout,(work/'stderr.bin').open('wb')as stderr:
            process=subprocess.Popen(command,cwd=work,env=environment,stdout=stdout,stderr=stderr,creationflags=subprocess.CREATE_NO_WINDOW)
            try:actual=process.wait(timeout=30)
            except subprocess.TimeoutExpired:state='TIMEOUT';actual=None;process.kill();process.wait()
        raw=(work/'stdout.bin').read_bytes();observation=None;parse_error=None
        try:observation=json.loads(raw.decode('utf-8'))
        except(ValueError,UnicodeError)as error:parse_error=str(error)
        row={'id':case['id'],'command':command,'pid':process.pid,'state':state,'actual_exit_code':actual,'post_cleanup_exit_code':process.returncode,'elapsed_seconds':time.monotonic()-began,'timeout_seconds':30,'child_locale_environment':snapshot,'source_sha256':sha(Path(case['source'])),'copied_mo_sha256':case['copied_mo_sha256'],'stdout_sha256':sha(work/'stdout.bin'),'stdout_bytes':len(raw),'stderr_sha256':sha(work/'stderr.bin'),'stderr_bytes':(work/'stderr.bin').stat().st_size,'observation':observation,'parse_error':parse_error,'translation_observed':bool(observation and observation.get('translation_observed')),'kind':'OFFICIAL_ORACLE_OBSERVATION_NOT_CANDIDATE_PASS'}
        row['locale_environment_snapshot_matches_php']=bool(observation and observation.get('environment_inside_php')==snapshot)
        rows.append(row)
        with(out/'records.jsonl').open('a',encoding='utf-8')as journal:journal.write(json.dumps(row)+'\n')
        print(case['id']+' '+state+' translation='+str(row['translation_observed'])+' locale-env-agrees='+str(row['locale_environment_snapshot_matches_php']),flush=True)
    after={str(p):sha(p)for p in inputs}
    save(out/'report.json',{'status':'SEPARATE_LOCALE_ORACLE_OBSERVATIONS_NOT_CONFORMANCE','candidate_execution_count':0,'old51_expectations_or_MO_changed':False,'inputs_before':before,'inputs_after':after,'inputs_unchanged':before==after,'timeout_seconds':30,'total':len(rows),'translations_observed':sum(r['translation_observed']for r in rows),'not_observed':sum(not r['translation_observed']for r in rows),'records':rows})
    assert before==after
    return 0 if all(r['state']=='EXITED'and r['actual_exit_code']==0 and r['parse_error']is None for r in rows)else 1

if __name__=='__main__':raise SystemExit(main())
