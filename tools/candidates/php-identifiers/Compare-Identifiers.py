"""Read-only identifier/byte comparison audit of a frozen actual adapter."""
from pathlib import Path
import argparse,base64,hashlib,importlib.util,json,sys

HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[2]
spec=importlib.util.spec_from_file_location('strict',ROOT/'tools/differential/evaluate.py')
strict=importlib.util.module_from_spec(spec);spec.loader.exec_module(strict)

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--output',type=Path,required=True)
    ap.add_argument('--adapter',type=Path,default=HERE/'baseline113d.snapshot.ps1')
    ap.add_argument('--cases',type=Path,default=HERE/'identifier-audit.cases.json')
    ap.add_argument('--php',type=Path,default=Path.home()/'ALL_php_oracle/php-8.5.12-ts-x64/php.exe')
    ap.add_argument('--timeout',type=float,default=30)
    a=ap.parse_args();out=a.output.resolve()
    if out.exists() or a.timeout<=0:ap.error('Use a new output path and positive timeout')
    paths={n:getattr(a,n).resolve(strict=True) for n in ['adapter','cases','php']}
    paths.update(driver=Path(__file__).resolve(),strict_helper=ROOT/'tools/differential/evaluate.py',worker=ROOT/'tools/differential/PhpCliCandidateWorker.ps1',powershell=Path('C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe'))
    before={n:strict.sha256(p) for n,p in paths.items()}
    cases=json.loads(paths['cases'].read_text(encoding='utf-8-sig'))
    assert cases and len({c['id'] for c in cases})==len(cases)
    out.mkdir(parents=True);rows=[]
    for i,c in enumerate(cases):
        raw=base64.b64decode(c['code_base64']) if 'code_base64' in c else c['code'].encode('utf-8')
        file=out/f'case-{i:04d}.php';file.write_bytes(raw)
        try:raw.decode('utf-8');valid_utf8=True
        except UnicodeDecodeError:valid_utf8=False
        oracle=strict.run_process([str(paths['php']),'-n','-d','display_errors=stderr','-d','error_reporting=-1','-d','date.timezone=UTC',str(file)],out,a.timeout)
        candidate=strict.run_process([str(paths['powershell']),'-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',str(paths['worker']),'-AdapterPath',str(paths['adapter']),'-SourcePath',str(file)],out,a.timeout)
        diff=strict.differences(oracle,candidate);source_stable=file.read_bytes()==raw
        if not source_stable:diff.append('source_changed')
        row={'id':c['id'],'source_path':str(file),'source_sha256':hashlib.sha256(raw).hexdigest(),'source_base64':base64.b64encode(raw).decode(),'valid_utf8_source':valid_utf8,'source_unchanged':source_stable,'verdict':'PASS' if not diff else 'DIFFERENT','differences':diff,'oracle':oracle,'candidate':candidate}
        rows.append(row);print(row['verdict']+': '+c['id'],flush=True)
    after={n:strict.sha256(p) for n,p in paths.items()}
    report={'status':'READ_ONLY_AUDIT_NOT_COMPLETE','baseline':'Frozen exact starting package snapshot; production lexer/comparers were not changed','driver_argv':[sys.executable,*sys.argv],'timeout_seconds':a.timeout,'measurement':'Same original PHP source bytes, exact stdout/stderr/actual process exit; no normalization','inputs_before':before,'inputs_after':after,'inputs_unchanged':before==after,'total':len(rows),'passed':sum(r['verdict']=='PASS' for r in rows),'results':rows}
    (out/'report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({k:report[k] for k in ['passed','total','inputs_unchanged']}))
    return 0 if report['passed']==report['total'] and before==after else 1

if __name__=='__main__':raise SystemExit(main())
