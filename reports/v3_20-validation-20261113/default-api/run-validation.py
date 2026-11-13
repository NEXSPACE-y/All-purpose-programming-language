"""Capture the actual v3.20 package preflight/default regression, without editing it."""
from pathlib import Path
import datetime as dt
import hashlib
import json
import os
import re
import subprocess
import time

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
PS=Path('C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe')
EXPECTED='5856687f7abd1471b4af7af9827ca2d17a011e836ad2852bf1d7993298fddc9f'
BASE='9d8171712828a0b57555b8eb1e1ca5c475391244'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def save(name,data):(HERE/name).write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8')

def main():
    if (HERE/'process-start.json').exists():raise SystemExit('An execution already exists; inspect its live process or choose a fresh run, do not overwrite it.')
    adapter=ROOT/'package/ALL_PHP_v3_12_adapter.ps1';capture=HERE/'capture-validation.ps1'
    assert sha(adapter)==EXPECTED
    original=read(ROOT/'reports/v3_19-validation-20261112/old940-git-verification.json')
    paths=original['trackedPaths'];assert len(paths)==34
    before=subprocess.run(['git','diff','--exit-code',BASE,'--',*paths],cwd=ROOT,capture_output=True)
    invariant={'against':BASE,'trackedPaths':paths,'fixtureCollections':32,'beforeDiffExitCode':before.returncode,'beforeDiffStdout':before.stdout.decode('utf-8',errors='backslashreplace'),'beforeDiffStderr':before.stderr.decode('utf-8',errors='backslashreplace')}
    save('old940-git-verification.json',invariant)
    if before.returncode!=0:raise SystemExit('Original940 tracked inputs differ; stop before runtime')
    save('source-provenance.json',{'adapterPath':str(adapter),'adapterSha256':sha(adapter),'captureSha256':sha(capture),'driverSha256':sha(Path(__file__)),'powershellPath':str(PS),'powershellSha256':sha(PS),'original940Base':BASE,'scope':'Actual default API/preflight only; no installed ALL execution'})
    command=[str(PS),'-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',str(capture)]
    start=time.monotonic()
    with (HERE/'validation.stdout.bin').open('wb') as stdout,(HERE/'validation.stderr.bin').open('wb') as stderr:
        process=subprocess.Popen(command,cwd=ROOT,stdin=subprocess.DEVNULL,stdout=stdout,stderr=stderr,creationflags=subprocess.CREATE_NO_WINDOW if os.name=='nt' else 0)
        save('process-start.json',{'pid':process.pid,'startedUtc':dt.datetime.now(dt.timezone.utc).isoformat(),'command':command,'observation':'PID recorded at actual spawn; later liveness must be checked, this record alone is not proof of a live process'})
        print(json.dumps({'pid':process.pid,'command':command}),flush=True)
        code=process.wait()
    elapsed=time.monotonic()-start
    after=subprocess.run(['git','diff','--exit-code',BASE,'--',*paths],cwd=ROOT,capture_output=True)
    invariant.update(afterDiffExitCode=after.returncode,afterDiffStdout=after.stdout.decode('utf-8',errors='backslashreplace'),afterDiffStderr=after.stderr.decode('utf-8',errors='backslashreplace'))
    save('old940-git-verification.json',invariant)
    raw=(HERE/'validation.stdout.bin').read_bytes();err=(HERE/'validation.stderr.bin').read_bytes();text=raw.decode('utf-8',errors='strict')
    (HERE/'validation.stdout.log').write_bytes(raw);(HERE/'validation.stderr.log').write_bytes(err)
    case_lines=[line for line in text.splitlines() if line.startswith('PASS [') and not line.startswith(('PASS [PowerShell Syntax]','PASS [SHA-256]','PASS [C# Compilation]'))]
    fails=[line for line in text.splitlines() if line.startswith('FAIL ')]
    syntax=re.search(r'PASS \[PowerShell Syntax\]: (\d+) scripts',text)
    manifest=re.search(r'PASS \[SHA-256\]: (\d+) packaged files',text)
    compiler=re.findall(r'^PASS \[C# Compilation\]: (.+)$',text,re.M)
    before_snapshot=read(HERE/'package-hashes-before.json') if (HERE/'package-hashes-before.json').exists() else None
    after_snapshot=read(HERE/'package-hashes-after.json') if (HERE/'package-hashes-after.json').exists() else None
    meta=read(HERE/'validation-process.json') if (HERE/'validation-process.json').exists() else None
    success=code==0 and len(case_lines)==965 and not fails and not err and 'ALL PHP v3.20 default API regression: 965/965 passed; 0 failed' in text and before_snapshot==after_snapshot and len(before_snapshot or [])==219 and after.returncode==0 and sha(adapter)==EXPECTED
    summary={'status':'NOT_COMPLETE','defaultApiRegressionStatus':'PASS' if success else 'FAIL','scope':'Actual PS5.1 package preflight/default965 only; strict/native/CLI/literal/dynamic groups are separate','adapterSha256':sha(adapter),'actualProcessExitCode':code,'processDurationSeconds':round(elapsed,3),'passLines':len(case_lines),'failLines':len(fails),'failureLines':fails,'stderrBytes':len(err),'syntaxScripts':int(syntax.group(1)) if syntax else None,'manifestFiles':int(manifest.group(1)) if manifest else None,'compiledCSharpHelpers':len(compiler),'packageBeforeCount':len(before_snapshot or []),'packageAfterCount':len(after_snapshot or []),'packageUnchanged':before_snapshot==after_snapshot,'old940TrackedPaths':34,'old940BeforeDiffExit':before.returncode,'old940AfterDiffExit':after.returncode,'validationProcess':meta,'otherGroupsVerifiedByThisTask':False,'installedALLExecuted':False}
    save('validation-summary.json',summary)
    print(json.dumps({k:summary[k] for k in ['defaultApiRegressionStatus','actualProcessExitCode','passLines','failLines','stderrBytes','syntaxScripts','manifestFiles','compiledCSharpHelpers','packageUnchanged']}),flush=True)
    return 0 if success else 1

if __name__=='__main__':raise SystemExit(main())
