"""Run an explicitly pinned prepared bundle's unchanged default965 validator.

This is the execution entry point, separate from preparation. It invokes only
Windows PowerShell5.1 with ALL_PHP_v3_20_validate.ps1 -CompileCSharp; no install,
fixture rewrite, stock-PHP delegation, expected-value substitution or retry.
"""
import argparse
import datetime as dt
import json
import re
import subprocess
import time
from pathlib import Path
from regression_support import HERE,ROOT,REGISTRY,POWERSHELL,sha,read_json,save,snapshot,manifest,fixture_inventory,original_git_check,byte_runtime_pin,protected_main

def counters(raw, expected):
    try:text=raw.decode('utf-8',errors='strict')
    except UnicodeDecodeError as error:return {'decodeError':str(error),'caseRows':[],'expectedCases':len(expected),'allCasesPass':False}
    reserved=('PASS [PowerShell Syntax]','PASS [SHA-256]','PASS [C# Compilation]',
              'FAIL [PowerShell Syntax]','FAIL [Package]','FAIL [C# Compilation]')
    lines=text.splitlines();rows=[]
    for line in lines:
        if line.startswith(reserved):continue
        match=re.fullmatch(r'(PASS|FAIL) (\[[^\]]+\]: .*)',line)
        if match:rows.append({'verdict':match[1],'label':match[2]})
    labels=[x['label'] for x in rows]
    old=re.findall(r'^ALL PHP v3\.16 \(direct candidate\): (\d+)/(\d+) passed; (\d+) failed\r?$',text,re.M)
    namespace=re.findall(r'^ALL PHP v3\.17 runtime namespaces: (\d+)/25 passed; (\d+) failed\r?$',text,re.M)
    syntax=re.search(r'PASS \[PowerShell Syntax\]: (\d+) scripts',text)
    hashes=re.search(r'PASS \[SHA-256\]: (\d+) packaged files',text)
    compiler=re.findall(r'^PASS \[C# Compilation\]: ([^\r\n]+)\r?$',text,re.M)
    return {'decodeError':None,'caseRows':rows,'observedCases':len(rows),'expectedCases':len(expected),
            'passLines':sum(x['verdict']=='PASS' for x in rows),'failLines':sum(x['verdict']=='FAIL' for x in rows),
            'allFailureLines':[x for x in lines if x.startswith('FAIL ')],
            'caseSequenceIsExpectedPrefix':labels==expected[:len(labels)],'caseSequenceExactlyComplete':labels==expected,
            'allCasesPass':labels==expected and all(x['verdict']=='PASS' for x in rows),
            'old940Summaries':[list(map(int,x)) for x in old],
            'namespace25Summaries':[list(map(int,x)) for x in namespace],
            'syntaxScripts':int(syntax[1]) if syntax else None,'manifestFiles':int(hashes[1]) if hashes else None,
            'compiledCSharpLines':compiler,'wrapper965BannerPresent':'ALL PHP v3.20 default API regression: 965/965 passed; 0 failed' in text,
            'counterParsingOnly':'Raw .bin bytes are retained unchanged; line parsing is for counters, not fixture/output normalization.'}

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--experiment',type=Path,required=True)
    parser.add_argument('--candidate-sha256',required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args();experiment=args.experiment.resolve(strict=True);output=args.output.resolve()
    preparation=read_json(experiment/'provenance.json');bundle=Path(preparation['bundle']).resolve(strict=True);source=ROOT/'package';registry=read_json(REGISTRY)
    if output.exists() or output.is_relative_to(bundle) or output.is_relative_to(source) or bundle.is_relative_to(output) or source.is_relative_to(output):
        parser.error('Use a fresh evidence directory outside bundle/source package')
    if preparation['status']!='PREPARED_NOT_DEFAULT_RUNTIME_EXECUTED' or not preparation['allInputsUnchanged'] or preparation['preparationPreflight']['actualExitCode']!=0:
        parser.error('Preparation was not successful')
    if args.candidate_sha256!=preparation['candidateSha256'] or sha(bundle/registry['adapterRelativePath'])!=args.candidate_sha256:
        parser.error('Explicit candidate SHA256 differs from prepared adapter')
    for name,digest in preparation['toolHashes'].items():
        if sha(HERE/name)!=digest:parser.error('Preparation tool changed: '+name)
    before=snapshot(bundle);source_before=snapshot(source)
    if before!=read_json(experiment/'bundle-after-preflight.json') or source_before!=read_json(experiment/'source-package-after.json'):
        parser.error('Prepared bundle or original package changed before execution')
    manifest_before=manifest(bundle);inventory=fixture_inventory(bundle)
    if inventory!=read_json(experiment/'fixture-inventory.json'):parser.error('Fixture definitions changed')
    runtime=byte_runtime_pin(bundle/registry['adapterRelativePath']);main_before=protected_main()
    output.mkdir(parents=True);git_before=original_git_check(output,'original940-git-before');save(output/'original940-git-before.json',git_before)
    if git_before['exit_code']!=0:raise SystemExit('Original940 tracked input diff is nonzero; no validation process started')
    save(output/'bundle-before.json',before);save(output/'source-package-before.json',source_before)
    inputs={'driver':sha(Path(__file__)),'support':sha(HERE/'regression_support.py'),'capture':sha(HERE/'Capture-DefaultRegression.ps1'),'registry':sha(REGISTRY),'powershell':sha(POWERSHELL),'adapter':args.candidate_sha256,'runtime':sha(Path(runtime['path'])),'preparation':sha(experiment/'provenance.json')}
    command=[str(POWERSHELL),'-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',str(HERE/'Capture-DefaultRegression.ps1'),'-BundlePath',str(bundle),'-EvidencePath',str(output)]
    started=time.monotonic()
    with (output/'validation.stdout.bin').open('wb') as stdout,(output/'validation.stderr.bin').open('wb') as stderr:
        process=subprocess.Popen(command,cwd=output,stdin=subprocess.DEVNULL,stdout=stdout,stderr=stderr,creationflags=subprocess.CREATE_NO_WINDOW)
        save(output/'process-start.json',{'pid':process.pid,'startedUtc':dt.datetime.now(dt.timezone.utc).isoformat(),'command':command,'timeoutSeconds':None,'timeoutPolicy':'The original default validator had no process timeout; this driver does not change that policy. No retries.','inputsBefore':inputs,'observation':'Actual spawn record; later liveness requires observation, not this JSON alone.'})
        print(json.dumps({'state':'STARTED_NOT_COMPLETED','pid':process.pid,'adapterSha256':args.candidate_sha256,'output':str(output)}),flush=True)
        while True:
            try:actual_exit=process.wait(timeout=15);break
            except subprocess.TimeoutExpired:
                progress=counters((output/'validation.stdout.bin').read_bytes(),inventory['expectedCaseLines'])
                observation={'state':'RUNNING_NOT_FINAL','elapsedSeconds':round(time.monotonic()-started,2),'observedCases':progress.get('observedCases',0),'passLines':progress.get('passLines',0),'failLines':progress.get('failLines',0)}
                with (output/'progress.jsonl').open('a',encoding='utf-8') as journal:journal.write(json.dumps(observation)+'\n')
                print(json.dumps(observation),flush=True)
    elapsed=time.monotonic()-started;raw=(output/'validation.stdout.bin').read_bytes();err=(output/'validation.stderr.bin').read_bytes()
    result=counters(raw,inventory['expectedCaseLines']);after=snapshot(bundle);source_after=snapshot(source);main_after=protected_main()
    save(output/'bundle-after.json',after);save(output/'source-package-after.json',source_after)
    git_after=original_git_check(output,'original940-git-after');save(output/'original940-git-after.json',git_after)
    meta=read_json(output/'validation-process.json') if (output/'validation-process.json').exists() else None
    ps_version=read_json(output/'powershell-version.json') if (output/'powershell-version.json').exists() else None
    worker_before=read_json(output/'bundle-worker-before.json') if (output/'bundle-worker-before.json').exists() else None
    worker_after=read_json(output/'bundle-worker-after.json') if (output/'bundle-worker-after.json').exists() else None
    inputs_after={'driver':sha(Path(__file__)),'support':sha(HERE/'regression_support.py'),'capture':sha(HERE/'Capture-DefaultRegression.ps1'),'registry':sha(REGISTRY),'powershell':sha(POWERSHELL),'adapter':sha(bundle/registry['adapterRelativePath']),'runtime':sha(Path(runtime['path'])),'preparation':sha(experiment/'provenance.json')}
    manifest_error=None
    try:manifest_after=manifest(bundle)
    except Exception as error:manifest_after=None;manifest_error=str(error)
    helper_types=[]
    if meta:
        helper_types=[name for assembly in meta.get('helperAssemblies',[]) for name in assembly.get('types',[])]
    checks={'actualProcessExitZero':actual_exit==0,'noStderr':not err,
            'all965RecordedPassInOriginalOrder':result['allCasesPass'],
            'noFailureLines':not result.get('allFailureLines',[]) and result.get('decodeError') is None,
            'original940SummaryExact':result.get('old940Summaries')==[[940,940,0]],
            'namespace25SummaryExact':result.get('namespace25Summaries')==[[25,0]],
            'unchangedWrapperBannerPresent':result.get('wrapper965BannerPresent',False),
            'syntaxCountMatchesBundle':result.get('syntaxScripts')==sum(Path(n).suffix.lower()=='.ps1' for n in before),
            'manifestCountMatchesBundle':result.get('manifestFiles')==len(manifest_before),
            'twoCSharpCompilationsReported':set(result.get('compiledCSharpLines',[]))=={'ALL_sqlite_driver.cs','ALL_ConcurrentGateway.cs'} and len(result.get('compiledCSharpLines',[]))==2,
            'bothCSharpHelperTypesActuallyLoaded':set(helper_types)=={'AllSqliteDriver','AllConcurrentGateway'},
            'workerMetadataExitZero':meta is not None and meta['exitCode']==0,
            'workerBundleSnapshotsUnchanged':worker_before is not None and worker_before==worker_after,
            'bundleUnchanged':before==after,'sourcePackageUnchanged':source_before==source_after,
            'installedMainUnchanged':main_before==main_after,
            'original940GitUnchanged':git_before['exit_code']==git_after['exit_code']==0,
            'manifestStillValid':manifest_after==manifest_before and manifest_error is None,
            'driverAndPinnedInputsUnchanged':inputs==inputs_after}
    success=all(checks.values())
    summary={'status':'DEFAULT_API_REGRESSION_ONLY_NOT_FULL_PHP','runState':'COMPLETED','default965Verdict':'PASS' if success else 'FAIL','actualPowerShellProcessExitCode':actual_exit,'elapsedSeconds':round(elapsed,3),'command':command,'inputsBefore':inputs,'inputsAfter':inputs_after,'checks':checks,'counters':result,'stderrBytes':len(err),'stdoutBytes':len(raw),'sourcePackageFileCount':len(source_before),'bundleFileCount':len(before),'manifestError':manifest_error,'byteRuntime':runtime,'installedMainBefore':main_before,'installedMainAfter':main_after,'installedALLExecuted':False,'fixturesModified':False,'preparation':str(experiment/'provenance.json'),'workerMetadata':meta,'powerShellVersion':ps_version,'scope':'Unchanged historical default API assertions, including refusal guards/parity cases. Not an official-PHP source oracle comparison, CLI/SAPI certification or full compatibility.'}
    save(output/'summary.json',summary)
    print(json.dumps({'state':'COMPLETED','default965Verdict':summary['default965Verdict'],'actualPowerShellProcessExitCode':actual_exit,'observedCases':result.get('observedCases',0),'passLines':result.get('passLines',0),'failLines':result.get('failLines',0),'allInputsUnchanged':checks['driverAndPinnedInputsUnchanged'] and checks['bundleUnchanged'] and checks['sourcePackageUnchanged']}),flush=True)
    return 0 if success else 1

if __name__=='__main__':raise SystemExit(main())
