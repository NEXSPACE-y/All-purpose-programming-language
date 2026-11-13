"""Same-source native evaluator checks through an outer-Main managed host.

The original PowerShell-process observations remain independent records. This
host returns the worker's requested status after disposing its runspace.
"""
from pathlib import Path
import argparse
import importlib.util
import json
import sys

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
spec=importlib.util.spec_from_file_location('strict',ROOT/'tools/differential/evaluate.py')
strict=importlib.util.module_from_spec(spec);spec.loader.exec_module(strict)

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--mode',choices=['callback','legacy'],required=True)
    ap.add_argument('--output',type=Path,required=True)
    ap.add_argument('--host',type=Path,default=HERE/'out/managed-host-02/all-native-php-host.exe')
    ap.add_argument('--adapter',type=Path,default=HERE/'revision02/ALL_PHP_v3_20_callback_candidate.ps1')
    ap.add_argument('--cases',type=Path)
    ap.add_argument('--core',type=Path)
    ap.add_argument('--php',type=Path,default=Path.home()/'ALL_php_oracle/php-8.5.12-ts-x64/php.exe')
    ap.add_argument('--extension',type=Path,default=Path.home()/'ALL_php_oracle/php-8.5.12-ts-x64/ext/php_dl_test.dll')
    ap.add_argument('--timeout',type=float,default=30)
    a=ap.parse_args();out=a.output.resolve()
    if out.exists() or a.timeout<=0:ap.error('Need a fresh output directory and positive timeout')
    if a.cases is None:a.cases=ROOT/('tools/candidates/php-native-callback/callback-source.cases.json' if a.mode=='callback' else 'tools/candidates/php-native/native-source.cases.json')
    if a.core is None:a.core=ROOT/('native/php85abi-callback/out/windows-x64-ts/php8ts.dll' if a.mode=='callback' else 'native/php85abi/out/windows-x64-ts/php8ts.dll')
    paths={k:getattr(a,k).resolve(strict=True) for k in ['host','adapter','cases','core','php','extension']}
    paths.update(driver=Path(__file__).resolve(),helper=ROOT/'tools/differential/evaluate.py',worker=paths['host'].parent/(a.mode+'-return-worker.ps1'),
                 bridge=paths['host'].parent/('AllNativeCallbackBridge.cs' if a.mode=='callback' else 'AllNativeBridge.cs'),host_build=paths['host'].parent/'build.json')
    before={k:strict.sha256(p) for k,p in paths.items()}
    cases=json.loads(paths['cases'].read_text(encoding='utf-8-sig'))
    if not cases or len({c['id'] for c in cases})!=len(cases):ap.error('Need nonempty unique case IDs')
    out.mkdir(parents=True);rows=[]
    for index,c in enumerate(cases):
        source=out/f'case-{index:04d}.php';source.write_bytes(c['code'].encode('utf-8'));metadata=out/f'case-{index:04d}.native.json'
        ref=strict.run_process([str(paths['php']),'-n','-d','extension='+str(paths['extension']),'-d','display_errors=stderr','-d','error_reporting=-1','-d','date.timezone=UTC',str(source)],out,a.timeout)
        actual=strict.run_process([str(paths['host']),a.mode,str(paths['adapter']),str(source),str(paths['core']),str(paths['extension']),str(metadata),before['core']],out,a.timeout)
        meta=json.loads(metadata.read_text(encoding='utf-8-sig')) if metadata.exists() else None
        diff=strict.differences(ref,actual);stable=bool(meta) and meta['inputs_before']==meta['inputs_after']
        modules=meta.get('loaded_php_modules',[]) if meta else []
        if isinstance(modules,str):modules=[modules]
        core_modules=[m for m in modules if Path(m).name.lower()=='php8ts.dll']
        own_core=len(core_modules)==1 and core_modules[0].lower()==str(paths['core']).lower()
        guard=c.get('expect_native_guard',False)
        if guard:
            good=actual['state']=='EXITED' and actual['exit_code']==1 and bool(meta) and meta['native_unsupported'] and meta['native_stats']['native_invocations']==0
            verdict='EXPECTED_ENGINE_REJECTION' if good and stable and own_core else 'GUARD_FAILURE'
        else:verdict='PASS' if not diff and stable and own_core and meta.get('native_context_parameter_verified') else 'DIFFERENT'
        rows.append({'id':c['id'],'source_path':str(source),'source_sha256':strict.sha256(source),'verdict':verdict,'native_guard_case':guard,'differences':diff,
                     'inputs_stable_in_worker':stable,'own_native_core_verified':own_core,'oracle':ref,'candidate':actual,'native_metadata':meta})
        print(verdict+': '+c['id'],flush=True)
    after={k:strict.sha256(p) for k,p in paths.items()};normal=[r for r in rows if not r['native_guard_case']];guards=[r for r in rows if r['native_guard_case']]
    report={'status':'NOT_COMPLETE','measurement':'Same PHP source, exact stdout/stderr bytes and actual process status; no normalization','mode':a.mode,
            'host_profile':'Own managed outer Main; trusted worker file returns status, runspace disposed before process exit; original PS worker records not replaced',
            'timeout_seconds':a.timeout,'driver_argv':[sys.executable,*sys.argv],'inputs_before':before,'inputs_after':after,'inputs_unchanged':before==after,
            'total_comparisons':len(normal),'passed':sum(r['verdict']=='PASS' for r in normal),'guard_cases':len(guards),'guards_rejected_before_native':sum(r['verdict']=='EXPECTED_ENGINE_REJECTION' for r in guards),'results':rows}
    (out/'report.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({k:report[k] for k in ['passed','total_comparisons','guard_cases','guards_rejected_before_native','inputs_unchanged']}))
    return 0 if report['passed']==len(normal) and report['guards_rejected_before_native']==len(guards) and before==after else 1

if __name__=='__main__':raise SystemExit(main())
