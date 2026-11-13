"""Compare frozen unchanged-gettext cases in separate fresh native/PHP processes.

No native execution on import. --execute is required and must only be used in
the root agent's authorized serialized runtime window. Deadline stays 30 sec.
"""
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
ROOT=HERE.parents[2]
PHP=Path('C:/Users/rinpa/ALL_php_oracle/php-8.5.12-ts-x64/php.exe')
EXTENSION=PHP.parent/'ext/php_gettext.dll'
CORE=HERE/'out/callback04/php8ts.dll'
BUILD=HERE/'out/managed02'
PREP=ROOT/'reports/php-native-gettext-20261113/prepared01'
PINS={PHP:'0ac893499799256db6d3a54b0da73692e02311493922e6e4f86a062674a77d66',EXTENSION:'ed395f80018920ba1b4551cdc33dd89871eb8b8ef362b1515ae93c0e7f1de3ad',CORE:'d005aa1205e214ad346783546c946e7e0e22a1c3eaa9ea696950dd49e17f328f',BUILD/'all-native-gettext-probe.exe':'a94faefa8bed3d9006cfb362b3812d1c86fd6b68d3ec80540f5c33300e5e2ba6',BUILD/'AllPhp.NativeGettext.Bridges.dll':'944c17e0fab140b7688278a315b2bc4c59692ceb91f206b02b48d58f7fc40689',BUILD/'AllPhp.ByteValues.Runtime.dll':'18d50efb55d8a333424149e4ab37428e102b1ac938240e50358ee3c8ab89466b',PREP/'prepared-manifest.json':'7233554d73698495f56f5ec27b588ed32afefc89b09ed7d89a9c5ae0916ee646'}
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
load=lambda p:json.loads(p.read_text(encoding='utf-8-sig'))
save=lambda p,x:p.write_text(json.dumps(x,indent=2)+'\n',encoding='utf-8')

def process(command,cwd,overrides,directory,label):
    began=time.perf_counter();environment=os.environ.copy();environment.update(overrides)
    child=subprocess.Popen(command,cwd=cwd,env=environment,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    try:
        stdout,stderr=child.communicate(timeout=30);state='EXITED';status=child.returncode
    except subprocess.TimeoutExpired:
        # Only this own child is terminated, after the unchanged deadline.
        child.kill();stdout,stderr=child.communicate();state='TIMEOUT';status=None
    (directory/(label+'.stdout.bin')).write_bytes(stdout);(directory/(label+'.stderr.bin')).write_bytes(stderr)
    record={'command':command,'cwd':str(cwd),'environment_overrides':overrides,'pid':child.pid,'state':state,'actual_status':status,'post_cleanup_status':child.returncode,'elapsed_seconds':time.perf_counter()-began,'timeout_seconds':30,'stdout_base64':base64.b64encode(stdout).decode(),'stderr_base64':base64.b64encode(stderr).decode()}
    save(directory/(label+'.process.json'),record);return record

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--output',type=Path,required=True);parser.add_argument('--case',action='append');parser.add_argument('--execute',action='store_true');args=parser.parse_args()
    if not args.execute:raise SystemExit('No execution requested. Await root authorization before --execute.')
    out=args.output.resolve();assert out.is_relative_to(ROOT/'reports/php-native-gettext-20261113')and not out.exists()
    inputs=dict(PINS);inputs[Path(__file__).resolve()]=sha(Path(__file__).resolve())
    for record_path in [ROOT/'reports/php-native-gettext-20261113/build-callback04/build.json',BUILD/'build.json',HERE/'generated04/provenance.json']:
        inputs[record_path]=sha(record_path);record=load(record_path)
        if'inputs_before'in record:
            assert record['inputs_before']==record['inputs_after']
            for key,path in record['input_paths'].items():inputs[Path(path)]=record['inputs_before'][key]
    prepared=load(PREP/'prepared-manifest.json');assert prepared['timeout_seconds']==30
    for relative,record in prepared['files'].items():inputs[PREP/relative]=record['sha256']
    for path,pin in inputs.items():assert sha(path)==pin,(path,sha(path),pin)
    before={str(p):sha(p)for p in inputs};out.mkdir()
    fixtures=sorted((PREP/'cases').glob('*/fixture.json'))
    if args.case:
        assert len(set(args.case))==len(args.case),'Case retries are not accepted'
        names={p.parent.name for p in fixtures};assert set(args.case)<=names
        fixtures=[p for name in args.case for p in fixtures if p.parent.name==name]
    save(out/'selected-cases.json',{'cases':[p.parent.name for p in fixtures],'source_manifest_sha256':PINS[PREP/'prepared-manifest.json'],'expected_native_function_retries':0,'timeout_seconds':30})
    rows=[]
    for fixture_path in fixtures:
        fixture=load(fixture_path);directory=out/fixture['id'];directory.mkdir();reference=fixture_path.parent/'reference.php';own_meta=directory/'native.metadata.json';php_meta=directory/'reference.metadata.json'
        cwd=Path(fixture.get('cwd',str(ROOT)));env=fixture.get('env',{})
        native=process([str(BUILD/'all-native-gettext-probe.exe'),str(CORE),str(EXTENSION),str(fixture_path),str(own_meta),PINS[CORE],PINS[EXTENSION],sha(fixture_path)],cwd,env,directory,'native')
        oracle=process([str(PHP),'-n','-d','extension='+str(EXTENSION),'-d','display_errors=stderr','-d','error_reporting=-1','-d','date.timezone=UTC',str(reference),str(php_meta)],cwd,env,directory,'reference')
        own=load(own_meta)if own_meta.exists()else None;official=load(php_meta)if php_meta.exists()else None
        row={'id':fixture['id'],'group':fixture['group'],'fixture_sha256':sha(fixture_path),'reference_source_sha256':sha(reference),'native':native,'reference':oracle,'native_metadata':own,'reference_metadata':official,'differences':[]};diff=row['differences']
        for label,run in [('native',native),('reference',oracle)]:
            if run['state']!='EXITED'or run['actual_status']!=0:diff.append(label+' process did not exit normally')
        if not own or'host_failure'in own or'cleanup_failure'in own:diff.append('native load/call/cleanup metadata incomplete')
        if not official:diff.append('reference metadata incomplete')
        for channel in ['stdout_base64','stderr_base64']:
            if native[channel]!=oracle[channel]:diff.append('raw '+channel)
        if own:
            actual=own.get('stats_after_calls',{}).get('native_invocations',0)-own.get('stats_before',{}).get('native_invocations',0)
            expected=sum(s['operation']=='call'for s in fixture['steps'])
            if actual!=expected:diff.append('native invocation count (no retry)')
            final=own.get('stats_final',{})
            for pair in [('minit','mshutdown'),('rinit','rshutdown'),('tls_contexts_created','tls_contexts_destroyed')]:
                if any(final.get(k)!=1 for k in pair):diff.append('controlled lifecycle '+repr(pair))
            if final.get('request_allocations_live')!=0:diff.append('tracked request allocations live')
            if own.get('host_process_cwd')!=own.get('host_process_cwd_after'):diff.append('native virtual cwd changed process cwd')
            modules={str(Path(p).resolve()).casefold()for p in own.get('loaded_php_modules',[])}
            if modules!={str(CORE.resolve()).casefold(),str(EXTENSION.resolve()).casefold()}:diff.append('unexpected PHP module identity')
        if own and official:
            observed=own.get('observations',[]);expected=official.get('observations',[])
            if len(observed)!=len(expected):diff.append('observation count')
            for index,(actual,reference_row)in enumerate(zip(observed,expected)):
                for key,expected_value in reference_row.items():
                    if actual.get(key)!=expected_value:diff.append('observation '+str(index)+' '+key)
        translation=fixture.get('required_last_translation_base64')
        exercised=True
        if translation:
            observations=official.get('observations',[])if official else[]
            exercised=bool(observations and observations[-1].get('value')=={'type':'string','value':translation}and any(r.get('operation')=='locale'and r.get('accepted')for r in observations))
            row['reference_catalog_translation_observed']=exercised
        row['verdict']='FAIL'if diff else'CATALOG_TRANSLATION_NOT_OBSERVED'if not exercised else'PASS'
        rows.append(row);save(out/'report.partial.json',{'status':'IN_PROGRESS','results':rows});print(row['verdict']+': '+row['id']+(' '+repr(diff)if diff else''),flush=True)
    after={str(p):sha(p)for p in inputs}
    record={'status':'SELECTED_UNCHANGED_GETTEXT_COMPONENT_NOT_FULL_PHP','timeout_seconds':30,'native_function_retries':0,'driver_argv':sys.argv,'inputs_before':before,'inputs_after':after,'inputs_unchanged':before==after,'passed':sum(r['verdict']=='PASS'for r in rows),'failed':sum(r['verdict']=='FAIL'for r in rows),'catalog_translation_not_observed':sum(r['verdict']=='CATALOG_TRANSLATION_NOT_OBSERVED'for r in rows),'results':rows}
    save(out/'report.json',record);print(json.dumps({k:record[k]for k in ['passed','failed','catalog_translation_not_observed','inputs_unchanged']}));return 0 if not record['failed']and before==after else 1

if __name__=='__main__':raise SystemExit(main())
