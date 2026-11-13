#!/usr/bin/env python3
"""Synthetic own-native safety/output contracts, separate from PHP comparisons."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]

def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--core',type=Path,default=ROOT/'native/php85abi-callback/out/windows-x64-ts/php8ts.dll')
    parser.add_argument('--extension',type=Path,default=Path.home()/'ALL_php_oracle/php-8.5.12-ts-x64/ext/php_dl_test.dll')
    parser.add_argument('--powershell',type=Path,default=Path('C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe'))
    args=parser.parse_args();out=args.output.resolve()
    if out.exists():parser.error('Output directory exists; preserve evidence and choose a new directory')
    paths={'core':args.core.resolve(strict=True),'extension':args.extension.resolve(strict=True),'powershell':args.powershell.resolve(strict=True),
           'worker':HERE/'Invoke-CallbackContractWorker.ps1','bridge':HERE/'AllNativeCallbackBridge.cs','runner':Path(__file__).resolve()}
    before={name:sha256(path) for name,path in paths.items()}
    out.mkdir(parents=True);rows=[]
    expected={'continue':b'N-beforeHN-afterE','throw':b'N-beforeHCaught','reenter':b'N-beforeHHello innerN-afterE'}
    for mode,want in expected.items():
        meta=out/(mode+'.json')
        cmd=[str(paths['powershell']),'-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',str(paths['worker']),'-Core',str(paths['core']),'-Extension',str(paths['extension']),'-Output',str(meta),'-Mode',mode]
        try:
            process=subprocess.run(cmd,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=30)
            state='EXITED';code=process.returncode;stdout=process.stdout;stderr=process.stderr
        except subprocess.TimeoutExpired as exc:
            state='TIMEOUT';code=None;stdout=exc.stdout or b'';stderr=exc.stderr or b''
        (out/(mode+'.stdout')).write_bytes(stdout);(out/(mode+'.stderr')).write_bytes(stderr)
        record=json.loads(meta.read_text(encoding='utf-8-sig')) if meta.exists() else None
        modules=record.get('loaded_php_modules',[]) if record else []
        if isinstance(modules,str):modules=[modules]
        core_modules=[x for x in modules if Path(x).name.lower()=='php8ts.dll']
        own_core=len(core_modules)==1 and core_modules[0].lower()==str(paths['core']).lower()
        row={'mode':mode,'state':state,'exit':code,'stdout_hex':stdout.hex(),'expected_stdout_hex':want.hex(),'stderr_hex':stderr.hex(),
             'metadata_pass':bool(record and record['status']=='PASS'),'own_core_verified':own_core,'exact_output':stdout==want and not stderr,'command':cmd}
        row['passed']=state=='EXITED' and code==0 and row['metadata_pass'] and row['exact_output'] and own_core
        rows.append(row);print(('PASS' if row['passed'] else 'FAIL')+': '+mode,flush=True)
    after={name:sha256(path) for name,path in paths.items()}
    report={'scope':'synthetic own-native safety/output contracts, not PHP compatibility','results':rows,'passed':sum(x['passed'] for x in rows),'total':len(rows),
            'driver_argv':[sys.executable,*sys.argv],'timeout_seconds':30,
            'inputs_before':before,'inputs_after':after,'inputs_unchanged':before==after,'all_pass':all(x['passed'] for x in rows) and before==after}
    (out/'report.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    return 0 if report['all_pass'] else 1

if __name__=='__main__':raise SystemExit(main())
