#!/usr/bin/env python3
"""Exact same-source process comparison of ALL evaluator/native integration."""
from __future__ import annotations
import argparse
import importlib.util
import json
from pathlib import Path
import sys

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
sys.dont_write_bytecode=True
spec=importlib.util.spec_from_file_location('all_strict_comparison',ROOT/'tools/differential/evaluate.py')
strict=importlib.util.module_from_spec(spec);spec.loader.exec_module(strict)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cases',type=Path,default=HERE/'native-source.cases.json')
    parser.add_argument('--adapter',type=Path,default=HERE/'ALL_PHP_native_candidate.ps1')
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--php',type=Path,default=Path.home()/'ALL_php_oracle/php-8.5.12-ts-x64/php.exe')
    parser.add_argument('--extension',type=Path,default=Path.home()/'ALL_php_oracle/php-8.5.12-ts-x64/ext/php_dl_test.dll')
    parser.add_argument('--core',type=Path,default=ROOT/'native/php85abi/out/windows-x64-ts/php8ts.dll')
    parser.add_argument('--powershell',type=Path,default=Path('C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe'))
    parser.add_argument('--timeout',type=float,default=30)
    args=parser.parse_args();out=args.output.resolve()
    if out.exists():parser.error('Output directory exists; preserve evidence and choose a new run directory')
    paths={name:getattr(args,name).resolve(strict=True) for name in ['cases','adapter','php','extension','core','powershell']}
    paths['worker']=ROOT/'tools/abi/Invoke-NativePhpWorker.ps1'
    paths['bridge']=ROOT/'tools/abi/AllNativeBridge.cs'
    paths['frozen_base']=ROOT/'tools/candidates/php-v3_18/ALL_PHP_v3_18_candidate.ps1'
    paths['driver']=Path(__file__).resolve()
    before={key:strict.sha256(path) for key,path in paths.items()}
    cases=json.loads(paths['cases'].read_text(encoding='utf-8-sig'))
    if not cases or len({c['id'] for c in cases})!=len(cases):parser.error('Need unique, nonempty case IDs')
    out.mkdir(parents=True);rows=[]
    for index,case in enumerate(cases):
        source=out/f'case-{index:04d}.php';source.write_bytes(case['code'].encode('utf-8'))
        metadata=out/f'case-{index:04d}.native.json'
        oracle=strict.run_process([str(paths['php']),'-n','-d','extension='+str(paths['extension']),'-d','display_errors=stderr','-d','error_reporting=-1','-d','date.timezone=UTC',str(source)],out,args.timeout)
        actual=strict.run_process([str(paths['powershell']),'-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',str(paths['worker']),'-AdapterPath',str(paths['adapter']),'-SourcePath',str(source),'-CorePath',str(paths['core']),'-ExtensionPath',str(paths['extension']),'-MetadataPath',str(metadata),'-ExpectedCoreHash',before['core']],out,args.timeout)
        meta=json.loads(metadata.read_text(encoding='utf-8-sig')) if metadata.exists() else None
        differences=strict.differences(oracle,actual)
        input_stable=bool(meta) and meta.get('inputs_before')==meta.get('inputs_after')
        own_core=bool(meta) and str(meta.get('core_path','')).lower()==str(paths['core']).lower()
        modules=meta.get('loaded_php_modules',[]) if meta else []
        if isinstance(modules,str):modules=[modules]
        core_modules=[p for p in modules if Path(p).name.lower()=='php8ts.dll']
        own_core=own_core and len(core_modules)==1 and core_modules[0].lower()==str(paths['core']).lower()
        guard=case.get('expect_native_guard',False)
        if guard:
            good=actual['state']=='EXITED' and actual['exit_code']==1 and bool(meta) and meta.get('native_unsupported',False) and meta.get('native_stats',{}).get('native_invocations')==0
            verdict='EXPECTED_ENGINE_REJECTION' if good and input_stable and own_core else 'GUARD_FAILURE'
        else:
            good=not differences and input_stable and own_core and meta.get('native_context_parameter_verified',False)
            verdict='PASS' if good else 'DIFFERENT'
        rows.append({'id':case['id'],'source_path':str(source),'source_sha256':strict.sha256(source),'verdict':verdict,'differences':differences,
                     'native_guard_case':guard,'inputs_stable_in_worker':input_stable,'own_native_core_verified':own_core,
                     'oracle':oracle,'candidate':actual,'metadata_path':str(metadata),'native_metadata':meta})
        print(verdict+': '+case['id'],flush=True)
    after={key:strict.sha256(path) for key,path in paths.items()}
    normal=[r for r in rows if not r['native_guard_case']];guards=[r for r in rows if r['native_guard_case']]
    report={'schema_version':1,'status':'NOT_COMPLETE','measurement':'same PHP source; exact stdout bytes/stderr bytes/actual process exit; no normalization',
            'driver_argv':[sys.executable,*sys.argv],'working_directory':str(Path.cwd()),'timeout_seconds':args.timeout,
            'profile':'preloaded unchanged native extension in the actual ALL evaluator; not ALL CLI extension flags',
            'scope':'selected valid-UTF8/NUL-literal/scalar/weak positional paths; callbacks/refs/objects/populated arrays/named native args remain unsupported',
            'inputs_before':before,'inputs_after':after,'inputs_unchanged':before==after,'base_frozen_sha256':before['frozen_base'],
            'total_comparisons':len(normal),'passed':sum(r['verdict']=='PASS' for r in normal),'guard_cases':len(guards),'guards_rejected_before_native':sum(r['verdict']=='EXPECTED_ENGINE_REJECTION' for r in guards),'results':rows}
    (out/'report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({key:report[key] for key in ['passed','total_comparisons','guard_cases','guards_rejected_before_native','inputs_unchanged']}))
    return 0 if report['passed']==len(normal) and report['guards_rejected_before_native']==len(guards) and before==after else 1


if __name__=='__main__':raise SystemExit(main())
