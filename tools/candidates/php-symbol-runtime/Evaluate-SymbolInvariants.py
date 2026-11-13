"""Retain exact channels/exits and pinned inputs for symbol invariants."""
from pathlib import Path
import argparse,base64,importlib.util,json
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[2]
spec=importlib.util.spec_from_file_location('strict',ROOT/'tools/differential/evaluate.py');strict=importlib.util.module_from_spec(spec);spec.loader.exec_module(strict)
def main():
    ap=argparse.ArgumentParser(description=__doc__)
    for name in ['output','byte','symbol']:ap.add_argument('--'+name,type=Path,required=True)
    a=ap.parse_args();out=a.output.resolve()
    if out.exists():ap.error('Choose fresh output')
    paths={n:getattr(a,n).resolve(strict=True) for n in ['byte','symbol']}
    paths.update(driver=Path(__file__).resolve(),probe=HERE/'Test-SymbolInvariants.ps1',clr_helper=HERE/'SymbolTestHelpers.cs',helper=ROOT/'tools/differential/evaluate.py',powershell=Path('C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe'))
    before={n:strict.sha256(p) for n,p in paths.items()};out.mkdir(parents=True)
    proc=strict.run_process([str(paths['powershell']),'-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',str(paths['probe']),'-ByteRuntimePath',str(paths['byte']),'-ByteRuntimeSha256',before['byte'],'-SymbolRuntimePath',str(paths['symbol']),'-SymbolRuntimeSha256',before['symbol']],out,30)
    detail=None
    try:detail=json.loads(base64.b64decode(proc['stdout_base64']).decode('utf-8-sig'))
    except (ValueError,UnicodeError):pass
    after={n:strict.sha256(p) for n,p in paths.items()}
    healthy=proc['state']=='EXITED' and proc['exit_code']==0 and proc['stderr_base64']==''
    passed=healthy and detail is not None and detail['passed']==detail['total'] and before==after
    report=dict(status='PASS' if passed else 'DIFFERENT',scope='Symbol component only; no PHP interpreter/lexer/registry adoption or PHP full-conformance claim',inputs_before=before,inputs_after=after,inputs_unchanged=before==after,process=proc,detail=detail)
    (out/'report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'status':report['status'],'passed':detail['passed'] if detail else None,'total':detail['total'] if detail else None,'process_state':proc['state'],'exit':proc['exit_code']}))
    if detail:
        for row in detail['checks']:
            if not row['pass']:print(json.dumps(row,ensure_ascii=True))
    if proc['stderr_base64']:print(proc['stderr_utf8_preview'])
    return 0 if passed else 1
if __name__=='__main__':raise SystemExit(main())
