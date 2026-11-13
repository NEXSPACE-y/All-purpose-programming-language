"""One fresh composed11 CLI loop with unchanged prior inputs and fixed hashes."""
from pathlib import Path
import argparse,hashlib,json,subprocess,sys
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[2]
EXPECTED='f7b61d06772ed661ac101347f454375ecfe8f18f952ea767f961cb77584e7706'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--output',type=Path,required=True);a=ap.parse_args();out=a.output.resolve()
 if out.exists():ap.error('Choose fresh output; no automatic retry or timeout extension')
 build=ROOT/'tools/candidates/php-byte-interpreter/out/composed11-cli';exe=build/'all-php.exe';adapter=build/'ALL_PHP_adapter.ps1';record=json.loads((build/'build.json').read_text(encoding='utf-8-sig'));php=Path.home()/'ALL_php_oracle/php-8.5.12-ts-x64/php.exe';cases=HERE/'composed11-boundaries66.cases.json';driver=ROOT/'tools/cli/Compare-AllPhpCli.py'
 assert sha(adapter)==record['adapter_sha256']==EXPECTED
 for entry in record['files']:assert sha(build/entry['path'])==entry['sha256']
 runtime=ROOT/'tools/candidates/php-byte-runtime/out/runtime01/AllPhp.ByteValues.Runtime.dll';assert sha(runtime)=='18d50efb55d8a333424149e4ab37428e102b1ac938240e50358ee3c8ab89466b'
 paths={'executable':exe,'adapter':adapter,'host':build/'AllPhpCli.ps1','cli_build':build/'build.json','original_candidate':ROOT/'tools/candidates/php-byte-interpreter/composed11/ALL_PHP_byte_candidate.ps1','byte_runtime':runtime,'php':php,'driver':driver,'wrapper':Path(__file__).resolve(),'cases':cases,'case_provenance':HERE/'case-provenance.json','new_trigger_cases':HERE/'trigger-coercion8.cases.json','case_builder':HERE/'Build-Cases.py','original_40':ROOT/'reports/php-byte-interpreter-20261113/composed07-boundaries-preparation/composed07-boundaries40.cases.json','original_callback14':ROOT/'reports/php-callback-arguments-20261113/callback-arguments.cases.json','original_raw2':ROOT/'reports/php-callback-arguments-20261113/callback-raw2.cases.json','original_hex8':ROOT/'tools/candidates/php-byte-interpreter/hex-bytes.cases.json','weak12':ROOT/'reports/php-enum-coercion-20261113/enum-weak12.cases.json','typecase2':ROOT/'reports/php-enum-coercion-20261113/enum-typecase2.cases.json','array4':ROOT/'tools/candidates/php-byte-interpreter/array-diagnostics.cases.json','automation_assembly':Path(record['automation_assembly']),'python_executable':Path(sys.executable)}
 for i,p in enumerate(sorted(php.parent.rglob('*.dll'))):paths['oracle_distribution_dll_'+str(i)]=p
 before={k:{'path':str(p.resolve()),'sha256':sha(p)} for k,p in paths.items()};assert before['original_candidate']['sha256']==EXPECTED
 (HERE/'additional-pins-before.json').write_text(json.dumps({'status':'STARTED_NOT_COMPLETED','expected_adapter':EXPECTED,'inputs':before,'scope':'Application/runtime and conservative reference distribution pins; standard OS/.NET transitive dependencies are not enumerated as loaded modules'},indent=2)+'\n',encoding='utf-8')
 argv=[sys.executable,str(driver),'--executable',str(exe),'--cases',str(cases),'--output',str(out),'--timeout','30'];p=subprocess.run(argv,cwd=ROOT)
 after={k:{'path':str(p.resolve()),'sha256':sha(p)} for k,p in paths.items()}
 result={'status':'COMPLETED_NO_AUTOMATIC_RETRY','command':argv,'actual_comparator_exit':p.returncode,'inputs_before':before,'inputs_after':after,'inputs_unchanged':before==after,'expected_adapter':EXPECTED,'candidate_modified':False,'definitions_modified':False,'original_40_preserved':True,'scope':'Exact raw CLI stdout/stderr/actual process-status, same PHP source per side, fixed 30s; no normalization'}
 if out.exists():(out/'additional-input-pins.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
 print(json.dumps({'comparator_exit':p.returncode,'additional_inputs_unchanged':before==after,'pinned_files':len(paths)}),flush=True)
 return p.returncode if before==after else 2
if __name__=='__main__':raise SystemExit(main())
