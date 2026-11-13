"""Summarize completed raw measurements without changing any verdict."""
from pathlib import Path
import json,hashlib,collections
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[2];run=ROOT/'reports/php-byte-interpreter-20261113/composed11-boundaries-66'
report=json.loads((run/'report.json').read_text(encoding='utf-8-sig'));pins=json.loads((run/'additional-input-pins.json').read_text(encoding='utf-8-sig'))
old=json.loads((ROOT/'reports/php-byte-interpreter-20261113/composed07-boundaries-40/report.json').read_text(encoding='utf-8-sig'))
load=lambda p:json.loads(p.read_text(encoding='utf-8-sig'))
normal=load(ROOT/'reports/php-callback-arguments-20261113/callback-arguments.cases.json');raw=load(ROOT/'reports/php-callback-arguments-20261113/callback-raw2.cases.json');hexes=load(ROOT/'tools/candidates/php-byte-interpreter/hex-bytes.cases.json');value=load(ROOT/'reports/php-byte-interpreter-20261113/composed07-boundaries-preparation/new-boundary16.cases.json');weak=load(ROOT/'reports/php-enum-coercion-20261113/enum-weak12.cases.json');typecase=load(ROOT/'reports/php-enum-coercion-20261113/enum-typecase2.cases.json');array=load(ROOT/'tools/candidates/php-byte-interpreter/array-diagnostics.cases.json');trigger=load(HERE/'trigger-coercion8.cases.json')
groups={}
for name,definitions in [('callback14',normal),('raw2',raw),('hex8',hexes),('value16',value),('weak12',weak),('typecase2',typecase),('array4',array),('trigger8',trigger)]:
 ids={c['id'] for c in definitions};rows=[r for r in report['results'] if r['id'] in ids];assert len(rows)==len(definitions)
 groups[name]={'total':len(rows),'passed':sum(r['verdict']=='PASS' for r in rows),'oracle_states':dict(collections.Counter(r['oracle']['state'] for r in rows)),'candidate_states':dict(collections.Counter(r['candidate']['state'] for r in rows)),'different':[{'id':r['id'],'differences':r['differences']} for r in rows if r['verdict']!='PASS']}
now={r['id']:r for r in report['results']};comparison=[]
for row in old['results']:
 new=now[row['id']];assert new['source_sha256']==row['source_sha256'] and new['mode']==row['mode']
 comparison.append({'id':row['id'],'source_sha256':row['source_sha256'],'prior_composed07_verdict':row['verdict'],'current_composed11_verdict':new['verdict'],'current_candidate_state':new['candidate']['state'],'scope':'Compare per-run verdicts, not raw output across different working directories'})
timeouts=[]
for row in report['results']:
 for side in ['oracle','candidate']:
  if row[side]['state']!='EXITED':timeouts.append({'id':row['id'],'side':side,'state':row[side]['state'],'elapsed_seconds':row[side]['elapsed_seconds'],'stdout_equal':row['oracle']['stdout_base64']==row['candidate']['stdout_base64'],'verdict':row['verdict']})
summary={'status':'COMPLETED_SELECTED_PROFILE_NOT_PHP_COMPLETE','adapter_sha256':pins['expected_adapter'],'comparator_exit':pins['actual_comparator_exit'],'passed':report['passed'],'total':report['total'],'groups':groups,'non_exited_process_observations':timeouts,'driver_inputs_unchanged':report['inputs_unchanged'],'additional_inputs_unchanged':pins['inputs_unchanged'],'additional_pinned_files':len(pins['inputs_before']),'all_sources_unchanged':all(r['source_unchanged'] for r in report['results']),'original40_same_source_mode':True,'common40_verdict_comparison':comparison,'timeout_extended':False,'automatic_retry_performed':False,'candidate_or_expected_modified':False,'all_measurement_process_handles_terminal':True,'timeout_cause':'Not determined; execution and shutdown phases require separate future tracing'}
(run/'group-summary.json').write_text(json.dumps(summary,indent=2)+'\n',encoding='utf-8');print(json.dumps({'passed':report['passed'],'total':report['total'],'groups':{k:str(v['passed'])+'/'+str(v['total']) for k,v in groups.items()},'non_exited':timeouts}))
