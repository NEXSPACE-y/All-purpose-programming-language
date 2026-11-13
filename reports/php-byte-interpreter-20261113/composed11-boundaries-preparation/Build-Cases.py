"""Unchanged original40/weak12/typecase2/key4 plus eight new trigger controls."""
from pathlib import Path
import hashlib,json
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[2];target=HERE/'composed11-boundaries66.cases.json';sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
if target.exists():raise SystemExit('Preserve fixed definitions')
sources=[ROOT/'reports/php-byte-interpreter-20261113/composed07-boundaries-preparation/composed07-boundaries40.cases.json',ROOT/'reports/php-enum-coercion-20261113/enum-weak12.cases.json',ROOT/'reports/php-enum-coercion-20261113/enum-typecase2.cases.json',ROOT/'tools/candidates/php-byte-interpreter/array-diagnostics.cases.json']
cases=[];provenance=[]
for path in sources:
 original=json.loads(path.read_text(encoding='utf-8-sig'));cases.extend(original)
 for c in original:provenance.append({'id':c['id'],'basis':'unchanged_prior_entry','definition_path':str(path),'definition_sha256':sha(path),'source_sha256':hashlib.sha256(c['code'].encode('utf-8')).hexdigest(),'original_entry':c})
new=[]
def add(id,code):new.append(dict(id='trigger.coercion.'+id,mode='body',code=code))
handler=r'set_error_handler(function($level,$message){echo $level,":",bin2hex($message),"\n";return true;});'
add('null',handler+'trigger_error(null,E_USER_WARNING);')
add('reject-array-object',handler+r'try{trigger_error([],E_USER_WARNING);}catch(TypeError $e){echo $e->getMessage(),"\n";}try{trigger_error(new stdClass(),E_USER_WARNING);}catch(TypeError $e){echo $e->getMessage();}')
add('stringable-raw',handler+r'class S{function __toString(){return "\xFF";}}trigger_error(new S(),E_USER_WARNING);')
add('alias-null',handler+'USER_ERROR(null,E_USER_WARNING);')
add('arity-alias',r'try{USER_ERROR();}catch(ArgumentCountError $e){echo $e->getMessage(),"\n";}try{TRIGGER_ERROR("x",E_USER_WARNING,99);}catch(ArgumentCountError $e){echo $e->getMessage();}')
add('null-level',handler+r'try{trigger_error("x",null);}catch(ValueError $e){echo $e->getMessage();}')
add('array-level',handler+r'try{trigger_error("x",[]);}catch(TypeError $e){echo $e->getMessage();}')
add('fraction-level',handler+r'trigger_error("\xFF",512.5);')
assert len(new)==8
(HERE/'trigger-coercion8.cases.json').write_text(json.dumps(new,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');cases.extend(new)
for c in new:provenance.append({'id':c['id'],'basis':'new_weak_trigger_source','source_sha256':hashlib.sha256(c['code'].encode('utf-8')).hexdigest()})
assert len(cases)==66 and len({c['id'] for c in cases})==66
target.write_text(json.dumps(cases,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
(HERE/'case-provenance.json').write_text(json.dumps({'original40_preserved_as_complete_entries':True,'weak12_preserved':True,'typecase2_preserved':True,'array4_preserved':True,'new_trigger8':8,'same_transports':True,'strict_types_coverage_claimed':False,'cases':provenance},ensure_ascii=False,indent=2)+'\n',encoding='utf-8');print(json.dumps({'total':len(cases),'unchanged_entries':58,'new_sources':8,'cases_sha256':sha(target)}))
