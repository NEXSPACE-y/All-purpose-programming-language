"""Run one actual CLI comparison loop with additional dependency pins."""
from pathlib import Path
import argparse,hashlib,json,subprocess,sys
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[2]
EXPECTED_ADAPTER='2236abb15caf624a0ed5c30c0d703d782e455d420d519912595603ff09f52aa9'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--output',type=Path,required=True);a=ap.parse_args();out=a.output.resolve()
 if out.exists():ap.error('Choose fresh output; failed measurements are not retried')
 build=ROOT/'tools/candidates/php-byte-interpreter/out/composed07-cli';exe=build/'all-php.exe';adapter=build/'ALL_PHP_adapter.ps1';record=json.loads((build/'build.json').read_text(encoding='utf-8-sig'));php=Path.home()/'ALL_php_oracle/php-8.5.12-ts-x64/php.exe';cases=HERE/'composed07-boundaries40.cases.json';driver=ROOT/'tools/cli/Compare-AllPhpCli.py'
 assert sha(adapter)==record['adapter_sha256']==EXPECTED_ADAPTER
 for entry in record['files']:assert sha(build/entry['path'])==entry['sha256']
 runtime=ROOT/'tools/candidates/php-byte-runtime/out/runtime01/AllPhp.ByteValues.Runtime.dll'
 assert sha(runtime)=='18d50efb55d8a333424149e4ab37428e102b1ac938240e50358ee3c8ab89466b'
 paths={'executable':exe,'adapter':adapter,'host':build/'AllPhpCli.ps1','cli_build':build/'build.json','original_candidate':ROOT/'tools/candidates/php-byte-interpreter/composed07/ALL_PHP_byte_candidate.ps1','byte_runtime':runtime,'php':php,'driver':driver,'wrapper':Path(__file__).resolve(),'cases':cases,'case_provenance':HERE/'case-provenance.json','new_cases':HERE/'new-boundary16.cases.json','case_builder':HERE/'Build-Cases.py','original_callback14':ROOT/'reports/php-callback-arguments-20261113/callback-arguments.cases.json','original_raw2':ROOT/'reports/php-callback-arguments-20261113/callback-raw2.cases.json','original_hex8':ROOT/'tools/candidates/php-byte-interpreter/hex-bytes.cases.json','automation_assembly':Path(record['automation_assembly']),'python_executable':Path(sys.executable)}
 # Distribution DLL pins are a conservative superset, not a claim each is loaded.
 for i,p in enumerate(sorted(php.parent.rglob('*.dll'))):paths['oracle_distribution_dll_'+str(i)]=p
 before={key:{'path':str(path.resolve()),'sha256':sha(path)} for key,path in paths.items()}
 assert before['original_candidate']['sha256']==EXPECTED_ADAPTER
 (HERE/'additional-pins-before.json').write_text(json.dumps({'status':'STARTED_NOT_COMPLETED','expected_adapter':EXPECTED_ADAPTER,'inputs':before,'scope':'Application/runtime and reference distribution files; standard OS/.NET transitive dependencies are not enumerated as loaded modules'},indent=2)+'\n',encoding='utf-8')
 argv=[sys.executable,str(driver),'--executable',str(exe),'--cases',str(cases),'--output',str(out),'--timeout','30']
 result=subprocess.run(argv,cwd=ROOT)
 after={key:{'path':str(path.resolve()),'sha256':sha(path)} for key,path in paths.items()}
 report={'status':'COMPLETED_NO_AUTOMATIC_RETRY','command':argv,'actual_comparator_exit':result.returncode,'inputs_before':before,'inputs_after':after,'inputs_unchanged':before==after,'expected_adapter':EXPECTED_ADAPTER,'candidate_modified':False,'definitions_modified':False,'scope':'Exact CLI stdout/stderr/process-status comparison; selected 40 sources only, not full PHP compatibility'}
 if out.exists():(out/'additional-input-pins.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
 print(json.dumps({'comparator_exit':result.returncode,'additional_inputs_unchanged':before==after,'pinned_files':len(paths)}),flush=True)
 return result.returncode if before==after else 2
if __name__=='__main__':raise SystemExit(main())
