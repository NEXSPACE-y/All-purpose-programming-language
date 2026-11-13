"""Byte-copy package219; overlay only the supplied adapter and its manifest hash."""
import argparse
import datetime as dt
import json
import re
import shutil
import subprocess
from pathlib import Path
from regression_support import HERE,ROOT,REGISTRY,POWERSHELL,sha,read_json,save,snapshot,manifest,fixture_inventory,original_git_check,byte_runtime_pin,protected_main

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--candidate',type=Path,required=True)
    parser.add_argument('--candidate-sha256',required=True)
    parser.add_argument('--destination',type=Path,required=True,help='Fresh experiment directory; bundle and external provenance become children')
    args=parser.parse_args();candidate=args.candidate.resolve(strict=True);destination=args.destination.resolve();source=ROOT/'package';registry=read_json(REGISTRY)
    if not re.fullmatch('[0-9a-f]{64}',args.candidate_sha256) or sha(candidate)!=args.candidate_sha256:
        parser.error('Candidate bytes do not match the explicit lower-case SHA256 pin')
    if destination.exists() or destination.is_relative_to(source) or source.is_relative_to(destination) or candidate.is_relative_to(destination):
        parser.error('Use a fresh destination isolated from source package and candidate input')
    original=snapshot(source)
    if len(original)!=registry['sourcePackageFileCount'] or original[registry['adapterRelativePath']]['sha256']!=registry['baseAdapterSha256']:
        parser.error('Source package count/base adapter changed; investigate rather than loosen the baseline')
    source_manifest=manifest(source);inventory=fixture_inventory(source);runtime=byte_runtime_pin(candidate);main_before=protected_main()
    tools_before={p.name:sha(p) for p in HERE.iterdir() if p.is_file()}
    destination.mkdir(parents=True);save(destination/'source-package-before.json',original)
    git=original_git_check(destination,'original940-git-before');save(destination/'original940-git-before.json',git)
    if git['exit_code']!=0:raise SystemExit('Original940 tracked inputs differ; no bundle execution performed')
    bundle=destination/'bundle';bundle.mkdir()
    for relative in original:
        target=bundle/relative;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(source/relative,target)
    adapter=bundle/registry['adapterRelativePath'];adapter.write_bytes(candidate.read_bytes())
    manifest_path=bundle/registry['manifestRelativePath'];data=manifest_path.read_bytes()
    pattern=re.compile(rb'^([0-9A-Fa-f]{64})(  ALL_PHP_v3_12_adapter\.ps1)(\r?\n|$)',re.M)
    matches=list(pattern.finditer(data))
    if len(matches)!=1:raise ValueError('Expected exactly one adapter manifest entry')
    entry=matches[0];replacement=args.candidate_sha256.upper() if entry[1].isupper() else args.candidate_sha256
    manifest_path.write_bytes(data[:entry.start(1)]+replacement.encode('ascii')+data[entry.end(1):])
    copied=snapshot(bundle);changes=[name for name in original if copied.get(name)!=original[name]]
    if set(copied)!=set(original) or set(changes)!={registry['adapterRelativePath'],registry['manifestRelativePath']}:
        raise ValueError('Bundle differs outside exactly the adapter and SHA256SUMS')
    bundle_manifest=manifest(bundle)
    if fixture_inventory(bundle)!=inventory:raise ValueError('Bundle fixture definitions changed')
    tracked=[]
    for path in registry['trackedPaths']+registry['extraPaths']:
        relative=path.removeprefix('package/')
        if original[relative]!=copied[relative]:raise ValueError('Original test/expectation bytes changed: '+relative)
        tracked.append({'path':path,'source':original[relative],'bundle':copied[relative],'byteIdentical':True})
    save(destination/'bundle-before-preflight.json',copied);save(destination/'fixture-inventory.json',inventory);save(destination/'protected-input-verification.json',tracked)
    command=[str(POWERSHELL),'-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',str(HERE/'Check-PreparedBundle.ps1'),'-BundlePath',str(bundle),'-VersionPath',str(destination/'preparation-powershell-version.json')]
    try:
        process=subprocess.run(command,cwd=destination,stdin=subprocess.DEVNULL,capture_output=True,timeout=120,creationflags=subprocess.CREATE_NO_WINDOW)
        stdout,stderr,actual_exit,state=process.stdout,process.stderr,process.returncode,'EXITED'
    except subprocess.TimeoutExpired as error:
        stdout,stderr,actual_exit,state=error.stdout or b'',error.stderr or b'',None,'TIMEOUT'
    (destination/'preflight.stdout.bin').write_bytes(stdout);(destination/'preflight.stderr.bin').write_bytes(stderr)
    after=snapshot(source);bundle_after=snapshot(bundle);git_after=original_git_check(destination,'original940-git-after');main_after=protected_main()
    save(destination/'source-package-after.json',after);save(destination/'bundle-after-preflight.json',bundle_after);save(destination/'original940-git-after.json',git_after)
    tools_after={p.name:sha(p) for p in HERE.iterdir() if p.is_file()}
    unchanged=after==original and copied==bundle_after and sha(candidate)==args.candidate_sha256 and main_after==main_before and git_after['exit_code']==0 and tools_before==tools_after
    record={'status':'PREPARED_NOT_DEFAULT_RUNTIME_EXECUTED','createdUtc':dt.datetime.now(dt.timezone.utc).isoformat(),'candidate':str(candidate),'candidateSha256':args.candidate_sha256,'sourcePackage':str(source),'bundle':str(bundle),'packageFiles':len(copied),'manifestFiles':len(bundle_manifest),'changedBundlePaths':changes,'allOtherFilesByteIdentical':True,'old940TrackedPaths':34,'additionalNamespaceCases':25,'expectedDefaultCases':965,'original940GitBase':registry['original940Base'],'byteRuntime':runtime,'canonicalRuntimeBootstrapRewritten':False,'readmesCopiedUnchanged':True,'readmeScope':'Copied base-package documentation; its assertions are not verification of this candidate. Candidate status and limits live outside bundle.','installedMainBefore':main_before,'installedMainAfter':main_after,'installedALLExecuted':False,'sourcePackageModified':False,'preparationPreflight':{'command':command,'actualExitCode':actual_exit,'timeoutSeconds':120,'compileCSharp':False,'defaultFixturesExecuted':False,'stderrBytes':len(stderr)},'allInputsUnchanged':unchanged,'toolHashes':{p.name:sha(p) for p in HERE.iterdir() if p.is_file()},'sourceManifestSha256':original[registry['manifestRelativePath']]['sha256'],'bundleManifestSha256':copied[registry['manifestRelativePath']]['sha256']}
    record['preparationPreflight'].update(state=state,actualExitCode=actual_exit,stderrBytes=len(stderr))
    record['toolHashesBefore']=tools_before
    record['toolHashes']=tools_after
    success=state=='EXITED' and actual_exit==0 and not stderr and unchanged
    record['preparationVerdict']='PASS' if success else 'FAIL'
    record['status']='PREPARED_NOT_DEFAULT_RUNTIME_EXECUTED' if success else 'PREPARATION_FAILED_NOT_DEFAULT_RUNTIME_EXECUTED'
    record['sourcePackageModified']=after!=original
    save(destination/'provenance.json',record)
    print(json.dumps({'prepared':success,'default965Executed':False,'bundle':str(bundle),'files':len(copied),'changedPaths':changes,'inputsUnchanged':unchanged}))
    return 0 if success else 1

if __name__=='__main__':raise SystemExit(main())
