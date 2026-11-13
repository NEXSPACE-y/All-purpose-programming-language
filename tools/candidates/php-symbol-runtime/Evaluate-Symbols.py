"""Compare isolated symbol keys with real PHP registry observations."""
from pathlib import Path
import argparse,base64,hashlib,importlib.util,json,sys
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[2]
spec=importlib.util.spec_from_file_location('strict',ROOT/'tools/differential/evaluate.py');strict=importlib.util.module_from_spec(spec);spec.loader.exec_module(strict)
def main():
    ap=argparse.ArgumentParser(description=__doc__)
    for name in ['output','cases','byte','symbol']:ap.add_argument('--'+name,type=Path,required=True)
    ap.add_argument('--php',type=Path,default=Path.home()/'ALL_php_oracle/php-8.5.12-ts-x64/php.exe');ap.add_argument('--timeout',type=float,default=30)
    a=ap.parse_args();out=a.output.resolve()
    if out.exists() or a.timeout<=0:ap.error('Use fresh output and positive timeout')
    paths={n:getattr(a,n).resolve(strict=True) for n in ['cases','byte','symbol','php']}
    paths.update(driver=Path(__file__).resolve(),ps_probe=HERE/'Probe-SymbolKeys.ps1',php_probe=HERE/'Probe-PhpSymbols.php',helper=ROOT/'tools/differential/evaluate.py',powershell=Path('C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe'))
    before={n:strict.sha256(p) for n,p in paths.items()};out.mkdir(parents=True)
    cases=json.loads(paths['cases'].read_text(encoding='utf-8-sig'));assert len({c['id'] for c in cases})==len(cases)
    oracle=strict.run_process([str(paths['php']),'-n','-d','display_errors=stderr','-d','error_reporting=-1',str(paths['php_probe']),str(paths['cases'])],out,a.timeout)
    candidate=strict.run_process([str(paths['powershell']),'-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',str(paths['ps_probe']),'-ByteRuntimePath',str(paths['byte']),'-ByteRuntimeSha256',before['byte'],'-SymbolRuntimePath',str(paths['symbol']),'-SymbolRuntimeSha256',before['symbol'],'-CasesPath',str(paths['cases'])],out,a.timeout)
    healthy=lambda p:p['state']=='EXITED' and p['exit_code']==0 and p['stderr_base64']==''
    process_ok=healthy(oracle) and healthy(candidate)
    observed=json.loads(base64.b64decode(oracle['stdout_base64'])) if healthy(oracle) else []
    actual=json.loads(base64.b64decode(candidate['stdout_base64']).decode('utf-8-sig')) if healthy(candidate) else []
    ob={r['id']:r for r in observed};ac={r['id']:r for r in actual};rows=[]
    for case in cases:
        got=ac.get(case['id']);ref=ob.get(case['id']) if case['oracle'] else None
        expected=ref['equal'] if ref else case.get('contract_equal');diff=[]
        if not process_ok:diff.append('process_state_or_channels')
        if got is None:diff.append('missing_candidate')
        if case['oracle'] and ref is None:diff.append('missing_oracle')
        if ref and ref['error']:
            error=ref['error'];message=base64.b64decode(error['message_base64']).decode('utf-8',errors='backslashreplace')
            allowed=error['class']=='Error' and ((case['kind']=='Parameter' and message.startswith('Unknown named parameter $')) or (case['kind']=='FunctionImportAlias' and message.startswith('Call to undefined function ')) or (case['kind']=='ClassImportAlias' and message.startswith('Class ') and message.endswith(' not found')) or (case['kind']=='ConstantImportAlias' and message.startswith('Undefined constant ')))
            if not allowed:diff.append('unexpected_oracle_error')
        if got:
            if got['equal']!=expected:diff.append('lookup_equality')
            if got['dictionary_found']!=expected:diff.append('dictionary_lookup')
            if got['equal'] and not got['hash_equal']:diff.append('equal_hash_contract')
        rows.append(dict(id=case['id'],basis='actual_php_lookup' if case['oracle'] else 'component_contract_only',expected=expected,actual=got,oracle=ref,verdict='PASS' if not diff else 'DIFFERENT',differences=diff))
    after={n:strict.sha256(p) for n,p in paths.items()}
    report=dict(status='ISOLATED_COMPONENT_NOT_CORE_ADOPTED',measurement='Actual PHP lookup result versus separate key component; protocol JSON is decoded, raw process channels/exits are retained; not byte-identical stdout claims',inputs_before=before,inputs_after=after,inputs_unchanged=before==after,oracle_process=oracle,candidate_process=candidate,total=len(rows),passed=sum(r['verdict']=='PASS' for r in rows),oracle_total=sum(c['oracle'] for c in cases),results=rows)
    (out/'report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({k:report[k] for k in ['passed','total','oracle_total','inputs_unchanged']}))
    for row in rows:
        if row['differences']:print(row['id']+': '+','.join(row['differences']))
    return 0 if report['passed']==report['total'] and before==after else 1
if __name__=='__main__':raise SystemExit(main())
