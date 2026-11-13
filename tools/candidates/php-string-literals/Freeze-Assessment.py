"""Read actual reports/source bytes and freeze a non-completion assessment."""
from pathlib import Path
import hashlib
import json
import base64

ROOT=Path(__file__).resolve().parents[3]
TASK=ROOT/'tools/candidates/php-string-literals'
REPORTS=ROOT/'reports/php-string-literals-20261113'
EXPECTED='e150594bb520e984fcb61a9288b695a044271b11559dcc5d8ceda4fae9ab3bb2'
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
if (REPORTS/'assessment.json').exists() or (REPORTS/'artifact-manifest.json').exists():
    raise SystemExit('Frozen assessment already exists; preserve it')
assert sha(TASK/'revision05/ALL_PHP_string_literal_candidate.ps1')==EXPECTED
r=read(REPORTS/'revision05-48/report.json')
assert r['total']==48 and r['passed']==45 and r['inputs_unchanged'] and r['inputs_before']['adapter']==EXPECTED
byid={c['id']:c for c in read(TASK/'final48.cases.json')}
for row in r['results']:
    original=byid[row['id']]['code'].encode('utf-8')
    assert Path(row['source_path']).read_bytes()==original
    assert row['source_sha256']==hashlib.sha256(original).hexdigest()
    assert row['candidate']['state']=='EXITED'
failed=[x for x in r['results'] if x['verdict']!='PASS']
assert {x['id'] for x in failed}=={'literal.octal-ascii','literal.binary-invalid-byte','literal.binary-surrogate'}
for x in failed:
    assert x['candidate']['exit_code']==1 and x['oracle']['exit_code']==0
    assert b'not supported' in base64.b64decode(x['candidate']['stderr_base64'])
d=read(REPORTS/'revision05-default52.json')
assert d['status']=='PASS' and d['passed']==d['total']==52
assert d['adapter_sha256_before'].lower()==d['adapter_sha256_after'].lower()==EXPECTED
assert all(x['sha256_before']==x['sha256_after'] for x in d['fixture_inputs'])
base=read(REPORTS/'baseline33/report.json');early=read(REPORTS/'revision01-33/report.json');prior=read(REPORTS/'revision04-42/report.json')
assert (base['passed'],early['passed'],prior['passed'])==(1,28,38)
assessment={
    'status':'LITERAL_SUBSET_MEASURED_NOT_COMPLETE','full_php_compatibility':False,
    'package_modified':False,'package_current_sha256':sha(ROOT/'package/ALL_PHP_v3_12_adapter.ps1'),
    'candidate_sha256':EXPECTED,
    'final':{'total':48,'matched':45,'different':3,'timeout':0,'inputs_unchanged':True,
             'all_source_bytes_preserved':True,'report':'revision05-48/report.json',
             'report_sha256':sha(REPORTS/'revision05-48/report.json')},
    'original_default_api':{'total':52,'passed':52,'unchanged_expectations':True,
                            'report':'revision05-default52.json','report_sha256':sha(REPORTS/'revision05-default52.json')},
    'remaining_byte_cases':[{'id':x['id'],'oracle_exit':x['oracle']['exit_code'],
                             'candidate_exit':x['candidate']['exit_code'],
                             'oracle_stdout_base64':x['oracle']['stdout_base64'],
                             'candidate_stderr_base64':x['candidate']['stderr_base64'],
                             'compatibility_pass':False} for x in failed],
    'historical':{'base33_matched':1,'revision01_33_matched':28,'revision04_42_matched':38,
                  'revision01_timeout_ids':[x['id'] for x in early['results'] if x['candidate']['state']=='TIMEOUT'],
                  'timeout_cause':'UNDETERMINED'},
    'not_verified':['Full965 on final candidate','Composition with other candidates and CLI file lexer',
                    'Arbitrary PHP byte-string value model','Complex interpolation and every malformed parser diagnostic',
                    'Native ABI all profiles and Linux/Web']}
assert assessment['package_current_sha256']=='113d0c2b967a8726cd9a9dec3f032a725ed9c98ee093c4aedd0a4830737f155b'
(REPORTS/'assessment.json').write_text(json.dumps(assessment,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
manifest=REPORTS/'artifact-manifest.json';files=[]
for tree in [TASK,REPORTS]:
    for p in sorted(tree.rglob('*')):
        if p.is_file() and p!=manifest and '__pycache__' not in p.parts:
            files.append({'path':p.relative_to(ROOT).as_posix(),'bytes':p.stat().st_size,'sha256':sha(p)})
manifest.write_text(json.dumps({'status':'FROZEN_SUBSET_NOT_ADOPTED','files':files},indent=2)+'\n',encoding='utf-8')
assert all((ROOT/f['path']).stat().st_size==f['bytes'] and sha(ROOT/f['path'])==f['sha256'] for f in files)
print(json.dumps({'candidate':EXPECTED,'matched':45,'total':48,'default_passed':52,'indexed_files':len(files),'package_unchanged':True}))
