"""Repeat the unchanged old native fixtures and bridge contracts on callback core.

These are native result/metadata contracts, not raw CLI source comparisons.
Stock PHP is only the separately executed reference worker.
"""
from pathlib import Path
import argparse
import base64
import hashlib
import importlib.util
import json
import os
import subprocess
import sys
import time

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
FLAGS=['PHP_DL_TEST_USE_OLD_REGISTER_INI_ENTRIES','PHP_DL_TEST_USE_REGISTER_FUNCTIONS_DIRECTLY']

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def run(cmd,cwd,env,timeout):
    start=time.monotonic()
    try:
        p=subprocess.run(cmd,cwd=cwd,env=env,stdin=subprocess.DEVNULL,capture_output=True,timeout=timeout,creationflags=subprocess.CREATE_NO_WINDOW if os.name=='nt' else 0)
        out,err,state,code=p.stdout,p.stderr,'EXITED',p.returncode
    except subprocess.TimeoutExpired as e:
        out,err,state,code=e.stdout or b'',e.stderr or b'','TIMEOUT',None
    return {'command':cmd,'working_directory':str(cwd),'inherited_legacy_flags':{k:env.get(k) for k in FLAGS},'state':state,'exit_code':code,'elapsed_seconds':time.monotonic()-start,
            'stdout_base64':base64.b64encode(out).decode(),'stderr_base64':base64.b64encode(err).decode()}

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--output',type=Path,required=True)
    ap.add_argument('--core',type=Path,default=ROOT/'native/php85abi-callback/out/windows-x64-ts/php8ts.dll')
    ap.add_argument('--extension',type=Path,default=Path.home()/'ALL_php_oracle/php-8.5.12-ts-x64/ext/php_dl_test.dll')
    ap.add_argument('--php',type=Path,default=Path.home()/'ALL_php_oracle/php-8.5.12-ts-x64/php.exe')
    ap.add_argument('--powershell',type=Path,default=Path('C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe'))
    ap.add_argument('--timeout',type=float,default=30)
    a=ap.parse_args();out=a.output.resolve()
    if out.exists() or a.timeout<=0:ap.error('Need fresh output directory and positive timeout')
    paths={k:getattr(a,k).resolve(strict=True) for k in ['core','extension','php','powershell']}
    paths.update(worker=HERE/'Invoke-DlTestWorker.ps1',scalar=HERE/'Invoke-NativeScalarBridgeProbe.ps1',load=HERE/'Invoke-NativeLoadProbe.ps1',bridge=HERE/'AllNativeCallbackBridge.cs',driver=Path(__file__).resolve(),
                 cases=ROOT/'tools/abi/DlTest-Cases.json',oracle=ROOT/'tools/abi/DlTest-Oracle.php',oracle_strict=ROOT/'tools/abi/DlTest-Oracle-Strict.php',
                 source=ROOT/'native/php85abi-callback/src/Runtime.cpp',header=ROOT/'native/php85abi-callback/include/all_php_bridge.h',build=ROOT/'reports/native-callback-20261112/build-final/build.json',
                 frozen_core=ROOT/'native/php85abi/out/windows-x64-ts/php8ts.dll',frozen_bridge=ROOT/'tools/abi/AllNativeBridge.cs',package=ROOT/'package/ALL_PHP_v3_12_adapter.ps1')
    before={k:sha(p) for k,p in paths.items()}
    assert before['core']=='88117b8f38dc77d20e638ce573bb83fc6f959c1ad6821f8803c5499969fe234b'
    assert before['bridge']=='8c37470ecafa4c00a41dbf8917295f88f76b7d2fbbd57645a91313bc833efda8'
    assert before['package']=='113d0c2b967a8726cd9a9dec3f032a725ed9c98ee093c4aedd0a4830737f155b'
    out.mkdir(parents=True);runs=[]
    base_env=os.environ.copy()
    for k in FLAGS:base_env.pop(k,None)
    for mode in ['normal','legacy']:
        env=base_env.copy()
        if mode=='legacy':env.update({k:'1' for k in FLAGS})
        oracle_out=out/(mode+'-oracle.json');actual_out=out/(mode+'-candidate.json')
        oracle_cmd=[str(paths['php']),'-n','-d','extension='+str(paths['extension']),'-d','display_errors=stderr','-d','error_reporting=-1','-d','date.timezone=UTC',str(paths['oracle']),str(paths['cases']),str(oracle_out)]
        candidate_cmd=[str(paths['powershell']),'-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',str(paths['worker']),'-Core',str(paths['core']),'-Extension',str(paths['extension']),'-Cases',str(paths['cases']),'-Output',str(actual_out)]
        if mode=='legacy':candidate_cmd+=['-Legacy']
        for kind,cmd in [('oracle',oracle_cmd),('candidate',candidate_cmd)]:
            r=run(cmd,out,env,a.timeout);runs.append({'mode':mode,'kind':kind,**r})
            (out/(mode+'-'+kind+'-process.json')).write_text(json.dumps(r,indent=2)+'\n',encoding='utf-8')
            print(mode+' '+kind+' '+r['state']+' '+str(r['exit_code']),flush=True)
    for name,worker,extension in [('scalar',paths['scalar'],paths['extension']),('unsupported-load',paths['load'],paths['extension'].parent/'php_shmop.dll')]:
        cmd=[str(paths['powershell']),'-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',str(worker),'-Core',str(paths['core']),'-Extension',str(extension),'-Output',str(out/(name+'.json'))]
        r=run(cmd,out,base_env,a.timeout);runs.append({'kind':name,**r});(out/(name+'-process.json')).write_text(json.dumps(r,indent=2)+'\n',encoding='utf-8')
        print(name+' '+r['state']+' '+str(r['exit_code']),flush=True)
    after={k:sha(p) for k,p in paths.items()}
    rows=[];threads=[];metadata=[];checks={}
    spec=importlib.util.spec_from_file_location('native_pe',ROOT/'tools/abi/Inspect-NativeAbi.py');pe=importlib.util.module_from_spec(spec);spec.loader.exec_module(pe)
    imports=pe.PE(paths['core']).imports();build=read(paths['build'])
    checks['candidate_hash_matches_build']=before['core']==build['candidate_sha256']
    checks['candidate_source_hash_matches_build']=before['source']==build['source_sha256']
    checks['candidate_does_not_import_stock_PHP']=not any(g['dll'].lower().startswith('php') for g in imports)
    for mode in ['normal','legacy']:
        actual=read(out/(mode+'-candidate.json'));expected=read(out/(mode+'-oracle.json'))
        refs={r['id']:r['result'] for r in expected['cases']}
        checks[mode+'_same_case_ids']=set(refs)=={r['id'] for r in actual['cases']}
        for c in actual['cases']:
            want=refs[c['id']];got=c['result'];dif={k:{'actual':got.get(k),'expected':want.get(k)} for k in set(want)|set(got) if want.get(k)!=got.get(k)}
            rows.append({'mode':mode,'id':c['id'],'matched':not dif,'differences':dif})
        am=actual['metadata'];em=expected['metadata'];fields=['constant','parent','property','inherited_property','ini_long','ini_string','ini_changed']
        if mode=='legacy':fields.append('direct_registration')
        metadata.append({'mode':mode,'scope':'registration metadata, not property execution','matches':{k:am.get(k)==em.get(k) for k in fields}})
        cores=[p for p in am['loaded_php_modules'] if Path(p).name.lower()=='php8ts.dll']
        checks[mode+'_only_loaded_PHP_core_is_own_candidate']=len(cores)==1 and cores[0].lower()==str(paths['core']).lower()
        checks[mode+'_reported_core_path_matches']=am['core_path'].lower()==str(paths['core']).lower()
        checks[mode+'_INI_resets_at_next_request']=am['ini_reset']==['0','hello']
        m=am['memory_probe'];checks[mode+'_memory_refcount_and_owner_probe']=m['before']==m['after'] and m['retained_refcount']==2 and m['remaining_refcount']==1 and m['cross_thread_free_rejected'] and m['owner_buffer_intact']
        for i,t in enumerate(actual['thread_isolation']):
            good=t['Error'] is None and t['Before']=='0' and t['After']=='0' and t['Value']==str(100+i) and t['Call']['Ok'] and t['Call']['Value']==base64.b64encode(('Hello thread'+str(i)).encode()).decode()
            threads.append({'mode':mode,'thread':i,'matched':good})
        s=actual['stats_after_shutdown'];checks[mode+'_controlled_lifecycle_balanced']=s['minit']==s['mshutdown']==1 and s['rinit']==s['rshutdown']==6 and s['tls_contexts_created']==s['tls_contexts_destroyed']==3
        checks[mode+'_tracked_request_allocations_zero']=s['request_allocations_live']==0
    checks['original_dl_test_binary_hash_preserved']=before['extension']=='532b9f0944d482a704eb81ac1cb9af3b59aa0f54c753c53a5709c17f57d4e938'
    rejected=read(out/'unsupported-load.json');checks['unsupported_module_load_rejected']=rejected['status']=='LOAD_REJECTED'
    scalar=read(out/'scalar.json');checks['scalar_bridge_contract_checks_pass']=scalar['all_passed'] and all(scalar['checks'].values())
    process_ok=all(r['state']=='EXITED' and r['exit_code']==0 for r in runs)
    success=process_ok and before==after and all(checks.values()) and all(r['matched'] for r in rows+threads) and all(all(x['matches'].values()) for x in metadata)
    report={'status':'SELECTED_NATIVE_REGRESSION_PASS' if success else 'HAS_FAILURES','PHP_FULL_COMPATIBLE':False,'driver_argv':[sys.executable,*sys.argv],'timeout_seconds':a.timeout,
            'scope':'Unchanged37fixtures in two registration modes; result/diagnostic/byte contracts, registration metadata, controlled lifecycle, not all ABI/PHP source conformance',
            'inputs_before':before,'inputs_after':after,'inputs_unchanged':before==after,'processes_all_exited_zero':process_ok,
            'unique_call_cases':len({r['id'] for r in rows}),'call_comparisons':len(rows),'matched_call_comparisons':sum(r['matched'] for r in rows),
            'checks':checks,'scalar_checks':scalar['checks'],'threads':threads,'metadata':metadata,'results':rows,'processes':runs,
            'unsupported_module_rejection':{'status':rejected['status'],'error':rejected['error'],'limit':'The callback bridge explicitly restricts the extension to pinned dl_test; this rejection is not a proof of the native OS loader missing-symbol path.'}}
    (out/'report.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'status':report['status'],'calls':report['matched_call_comparisons'],'total':len(rows),'consistency_checks':sum(checks.values()),'consistency_total':len(checks),'scalar_checks':sum(scalar['checks'].values()),'scalar_total':len(scalar['checks'])}))
    return 0 if success else 1

if __name__=='__main__':raise SystemExit(main())
