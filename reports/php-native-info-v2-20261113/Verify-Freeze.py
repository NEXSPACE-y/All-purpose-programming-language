"""Independently verify terminal records; keep synthetic scope explicit."""
from pathlib import Path
import hashlib
import importlib.util
import json

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]
CANDIDATE=ROOT/'tools/candidates/php-native-info-v2'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
old=read(ROOT/'reports/php-byte-native-20261113/run02/report.json');new=read(HERE/'run01/report.json')
assert new['passed']==36 and new['guard_rejections']==4 and new['failed']==0 and new['inputs_unchanged']
assert new['timeout_seconds']==old['timeout_seconds']==30
assert new['inputs_before']==new['inputs_after']
for path,pin in new['inputs_before'].items():assert sha(Path(path))==pin
assert read(ROOT/'reports/php-byte-native-20261113/run02/fixtures.json')==read(HERE/'run01/fixtures.json')
assert len(old['results'])==len(new['results'])==40
info=[]
for before,after in zip(old['results'],new['results']):
 assert before['id']==after['id']and before['fixture_sha256']==after['fixture_sha256']and before['reference_source_sha256']==after['reference_source_sha256']
 assert after['candidate']['state']=='EXITED'and after['candidate']['actual_status']==0
 if after['verdict']=='PASS':
  for key in ('stdout_base64','stderr_base64','actual_status'):assert after['candidate'][key]==after['oracle'][key]
 if after['id'].endswith('raw_ini_module_output'):
  assert before['verdict']=='FAIL'and after['verdict']=='PASS'
  info.append({'id':after['id'],'previous_verdict':'FAIL','new_verdict':'PASS','whole_output_normalized':False,'candidate_stdout_sha256':hashlib.sha256(__import__('base64').b64decode(after['candidate']['stdout_base64'])).hexdigest()})
contract=read(HERE/'getter-contract01/process.json');assert contract['pass']and contract['state']=='EXITED'and contract['actual_status']==0 and contract['inputs_unchanged']
for path,pin in contract['inputs_before'].items():assert sha(Path(path))==pin
payloads=[b'',b'\xff',b'A\0B',b'\xed\xa0\x80',bytes(range(256)),b'x'*16777216+b'\xff']
actual=contract['contract'];assert actual['payload_cases_passed']==6
for expected,row in zip(payloads,actual['payload_cases']):assert row['length']==len(expected)and row['sha256']==hashlib.sha256(expected).hexdigest()and row['after_native_overwrite_same']
assert actual['initial_empty_outside_request']and actual['null_length_pointer_safe']and actual['inactive_end_rejected_and_error_readable']and actual['invalid_synthetic_input_rejected']and actual['copy_survives_shutdown']
assert actual['stats']['native_invocations']==0 and not actual['extension_loaded_or_called']
spec=importlib.util.spec_from_file_location('pe',ROOT/'tools/abi/Inspect-NativeAbi.py');pe=importlib.util.module_from_spec(spec);spec.loader.exec_module(pe)
cores=[]
for mode in ('legacy','callback'):
 record=read(HERE/('build-'+mode+'01/build.json'));path=Path(record['candidate']);image=pe.PE(path);exports=image.exports();names={name for row in exports for name in row['names']}
 assert sha(path)==record['candidate_sha256']and record['inputs_before']==record['inputs_after']
 assert 'all_php_error_message_bytes'in names and 'php_info_print_table_header'in names and 'all_info_v2_contract_set_error'not in names
 assert not any(row['kind']=='forwarder'for row in exports)and not any(row['dll'].lower().startswith('php')for row in image.imports())
 cores.append({'mode':mode,'core_sha256':sha(path),'export_names':len(names),'forwarders':0,'php_imports':0})
for row in read(CANDIDATE/'generated02/provenance.json')['files']:assert sha(Path(row['original']))==row['original_sha256']and sha(Path(row['candidate']))==row['candidate_sha256']
for row in read(HERE/'sdk-preparation01/headers.json')['files']:assert sha(ROOT/row['path'])==row['sha256']
verification={'status':'VERIFIED_SELECTED_INFO_V2_AND_SEPARATE_SYNTHETIC_GETTER_NOT_FULL_PHP','comparisons_passed':36,'guards_separate':4,'original_fixture_and_source_bytes_unchanged':True,'module_info_previous_failures_preserved':info,'synthetic_payloads_separate':6,'synthetic_scope':'Real getter in a test-only own DLL with one setter; same production CPP/getter and production byte bridge copy; no third-party extension or stock-PHP call','getter_tls_limit':'Foreign getter was empty while main was already empty. This is an empty-read observation only; metadata field thread_local_error_state_separate does not establish TLS isolation. No isolation PASS is counted.','production_cores':cores,'package_adopted':False}
(HERE/'verification.json').write_text(json.dumps(verification,indent=2)+'\n',encoding='utf-8')
files=[{'path':p.relative_to(ROOT).as_posix(),'bytes':p.stat().st_size,'sha256':sha(p)}for folder in (CANDIDATE,HERE)for p in sorted(folder.rglob('*'))if p.is_file()and p!=HERE/'artifact-manifest.json']
(HERE/'artifact-manifest.json').write_text(json.dumps({'status':'FROZEN_INFO_V2_EVIDENCE_NOT_FULL_PHP','files':files},indent=2)+'\n',encoding='utf-8')
for item in files:assert sha(ROOT/item['path'])==item['sha256']
print(json.dumps({'comparisons':36,'guards':4,'synthetic_payloads':6,'files':len(files),'manifest_sha256':sha(HERE/'artifact-manifest.json')}))
