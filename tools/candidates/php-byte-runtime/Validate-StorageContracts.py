"""Synthetic storage contracts plus independent real >2GB stream hash; not PHP interpretation."""
import argparse,base64,hashlib,json,subprocess,sys,time
from pathlib import Path
HERE=Path(__file__).resolve().parent
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--assembly',type=Path,required=True);parser.add_argument('--proof',type=Path,required=True);parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args();output=args.output.resolve()
    if output.exists():parser.error('A fresh output path is required')
    output.mkdir(parents=True)
    paths={'runtime':args.assembly.resolve(strict=True),'proof':args.proof.resolve(strict=True),'runtime_source':HERE/'PhpByteRuntime.cs','proof_source':HERE/'StorageContracts.cs','worker':HERE/'Invoke-StorageContracts.ps1','driver':Path(__file__).resolve()}
    before={k:sha(v) for k,v in paths.items()}
    pattern=bytes((i*37+11)&255 for i in range(257));repetitions=(2147483647+65577)//len(pattern)+1;length=repetitions*len(pattern);offset=2147483647+7
    positions=[0,1,256,257,65535,65536,2147483646,2147483647,2147483648,offset,length-257,length-1]
    fixture={'pattern_base64':base64.b64encode(pattern).decode(),'repetitions':repetitions,'length':length,'mutation_offset':offset,'sample_positions':positions}
    cases=output/'storage.cases.json';cases.write_text(json.dumps(fixture,indent=2)+'\n',encoding='utf-8');before['cases']=sha(cases)
    # Independent hashlib reference consumes every byte, with at most 1,052,672 input bytes per update.
    reference_start=time.monotonic();digest=hashlib.sha256();batch=pattern*4096;remaining=repetitions
    while remaining>=4096:digest.update(batch);remaining-=4096
    digest.update(pattern*remaining);expected_hash=digest.hexdigest();reference_elapsed=time.monotonic()-reference_start
    command=['C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',str(paths['worker']),'-RuntimeAssemblyPath',str(paths['runtime']),'-ProofAssemblyPath',str(paths['proof']),'-CasesPath',str(cases),'-ReportPath',str(output/'worker.json')]
    start=time.monotonic()
    try:
        p=subprocess.run(command,cwd=output,stdin=subprocess.DEVNULL,capture_output=True,timeout=180,creationflags=subprocess.CREATE_NO_WINDOW)
        stdout,stderr,code,state=p.stdout,p.stderr,p.returncode,'EXITED'
    except subprocess.TimeoutExpired as e:stdout,stderr,code,state=e.stdout or b'',e.stderr or b'',None,'TIMEOUT'
    (output/'worker.stdout.bin').write_bytes(stdout);(output/'worker.stderr.bin').write_bytes(stderr)
    result=json.loads((output/'worker.json').read_text(encoding='utf-8-sig')) if (output/'worker.json').exists() else None
    expected_window=bytes(165 if i==64 else pattern[(offset-64+i)%len(pattern)] for i in range(129))
    comparisons={
        'worker_exit_zero':state=='EXITED' and code==0,
        'all_contract_checks':result is not None and all(c['Passed'] for c in result['Checks']),
        'full_stream_exact_count':result is not None and result['FullStreamBytes']==length,
        'full_stream_independent_sha256':result is not None and result['FullStreamSha256']==expected_hash,
        'long_samples_independent':result is not None and result['Samples']=={str(p):pattern[p%len(pattern)] for p in positions},
        'mutation_window_independent':result is not None and result['MutationWindowBase64']==base64.b64encode(expected_window).decode(),
        'extension_window_independent':result is not None and result['AppendedWindowBase64']==base64.b64encode(b' '*100+b'\xff').decode(),
    }
    after={k:sha(v) for k,v in paths.items()};after['cases']=sha(cases);comparisons['inputs_unchanged']=before==after
    report={'status':'STORAGE_CONTRACT_NOT_INTERPRETER_COMPATIBILITY','timeout_seconds':180,'command':command,'state':state,'exit_code':code,'elapsed_seconds':time.monotonic()-start,'reference_elapsed_seconds':reference_elapsed,'expected_length':length,'expected_sha256':expected_hash,'inputs_before':before,'inputs_after':after,'comparisons':comparisons,'worker':result,'full_php_compatibility':False,'linux_executed':False}
    (output/'report.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'state':state,'exit_code':code,'comparisons':comparisons,'full_stream_bytes':None if result is None else result['FullStreamBytes'],'full_stream_sha256':None if result is None else result['FullStreamSha256']}))
    return 0 if all(comparisons.values()) else 1
if __name__=='__main__':raise SystemExit(main())
