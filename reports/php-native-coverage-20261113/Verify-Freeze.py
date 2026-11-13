"""Verify static evidence only; never load an inspected binary."""
from pathlib import Path
import hashlib
import json

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def read(path):return json.loads(path.read_text(encoding='utf-8-sig'))
inventory=read(HERE/'static01/inventory.json');audit=read(HERE/'source02/source-audit.json')
assert inventory['inputs_unchanged']and inventory['input_hashes_before']==inventory['input_hashes_after']
assert not inventory['extensions_loaded_or_executed']and not inventory['stock_php_executed']and not inventory['existing_core_modified']
assert len(inventory['extensions'])==36 and len(inventory['requirements'])==985
assert sum(row['oracle_export_kind']=='data'for row in inventory['requirements'].values())==59
assert len(inventory['dumpbin_processes'])==41
for path,pin in inventory['input_hashes_before'].items():assert sha(Path(path))==pin
for row in inventory['dumpbin_processes']:
 assert row['actual_status']==0
 for channel in ('stdout','stderr'):assert sha(HERE/'static01'/row[channel+'_path'])==row[channel+'_sha256']
for row in inventory['extensions']:
 assert row['machine']==0x8664 and row['pe_magic']==0x20b and not row['php8ts_ordinal_imports']
 assert sha(Path(row['path']))==row['sha256']
assert audit['inventory_sha256']==sha(HERE/'static01/inventory.json')
assert len(audit['requirements'])==985
for mode in ('original','callback'):
 present=[row for row in audit['requirements']if row['source_audit'][mode]['classification']!='MISSING_EXPORT']
 assert len(present)==29
 assert all(row['source_audit'][mode]['evidence']['definition_lines']for row in present)
 assert not any(e['kind']=='forwarder'for e in inventory['cores'][mode]['exports'])
 assert not any(i['dll'].lower().startswith('php')for i in inventory['cores'][mode]['imports'])
sourcezip=audit['pinned_reference_source_zip'];assert sha(Path(sourcezip['path']))==sourcezip['sha256']
record={'status':'VERIFIED_STATIC_EVIDENCE_NO_RUNTIME_COMPATIBILITY_CLAIM','extension_dlls':36,'php_import_names':985,'data_import_names':59,'own_php_names_each':29,'missing_names_each':956,'dumpbin_actual_status_zero':41,'all_current_input_hashes_match':True,'no_own_core_forwarders_or_php_imports':True,'extensions_loaded_or_executed':False}
(HERE/'verification.json').write_text(json.dumps(record,indent=2)+'\n',encoding='utf-8')
files=[{'path':p.relative_to(ROOT).as_posix(),'bytes':p.stat().st_size,'sha256':sha(p)}for folder in (ROOT/'tools/candidates/php-native-coverage',HERE)for p in sorted(folder.rglob('*'))if p.is_file()and p!=HERE/'artifact-manifest.json']
(HERE/'artifact-manifest.json').write_text(json.dumps({'status':'FROZEN_STATIC_NATIVE_COVERAGE_NOT_FULL_PHP','files':files},indent=2)+'\n',encoding='utf-8')
for row in files:assert sha(ROOT/row['path'])==row['sha256']
print(json.dumps({'files':len(files),'manifest_sha256':sha(HERE/'artifact-manifest.json'),'runtime_executed':False}))
