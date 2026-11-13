"""Preserve callback14/raw2/hex8 sources and add sixteen boundary observations."""
from pathlib import Path
import hashlib,json
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[2]
target=HERE/'composed07-boundaries40.cases.json'
if target.exists():raise SystemExit('Preserve prior fixed definitions')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
paths=[ROOT/'reports/php-callback-arguments-20261113/callback-arguments.cases.json',ROOT/'reports/php-callback-arguments-20261113/callback-raw2.cases.json',ROOT/'tools/candidates/php-byte-interpreter/hex-bytes.cases.json']
cases=[];provenance=[]
for p in paths:
 original=json.loads(p.read_text(encoding='utf-8-sig'))
 for case in original:
  copied=dict(case)
  if 'mode' not in copied:copied['mode']='file' # Keep the original opening tag and every source byte.
  assert copied['code']==case['code']
  cases.append(copied);provenance.append({'id':case['id'],'basis':'unchanged_existing_source','definition_path':str(p),'definition_sha256':sha(p),'source_sha256':hashlib.sha256(case['code'].encode('utf-8')).hexdigest(),'original_entry':case,'selected_transport':copied['mode']})
new=[]
def add(id,code):new.append(dict(id='boundary.'+id,mode='body',code=code))
add('enum-string-raw',r'enum E:string{case A="\xFF";case B="\0";}echo E::from("\xFF")->name,":",bin2hex(E::from("\0")->value);')
add('enum-string-nfc','enum E:string{case A="é";case B="é";}echo E::from("é")->name,":",E::from("é")->name;')
add('enum-string-valueerror',r'enum E:string{case A="a";}try{E::from("\xFE");}catch(ValueError $e){echo bin2hex($e->getMessage());}')
add('enum-int-control','enum E:int{case A=7;}echo E::from(7)->name;var_dump(E::tryFrom(8));')
add('enum-weak-scalar-known-gap','enum E:string{case A="7";}echo E::from(7)->name;')
add('firstclass-array-object','class C{function m($x){return $x+1;}}$c=new C();$f=[$c,"m"];$g=$f(...);echo $g(3);')
add('firstclass-array-static','class C{static function m($x){return $x+1;}}$f=["C","m"];$g=$f(...);echo $g(4);')
add('isnumeric-bytes',r'var_dump(is_numeric("12"),is_numeric("12.5"),is_numeric("\xFF"),is_numeric("猫"));')
add('instanceof-string','class C{}$x=new C();$name="c";var_dump($x instanceof $name);')
add('getter-constants',r'define("X","\xFF");class C{const Y="\0";}$c=new C();var_dump(is_string(get_class($c)),bin2hex(constant("X")),bin2hex(C::Y),is_string(C::class));')
add('match-escaped-bytes',r'try{match("\xFF\0\x27\\\n"){};}catch(UnhandledMatchError $e){echo $e->getMessage();}')
add('match-byte-limit',r'ini_set("zend.exception_string_param_max_len","3");try{match("A\xFF\nB"){};}catch(UnhandledMatchError $e){echo $e->getMessage();}')
add('trace-escaped-bytes',r'function f($x){throw new Exception("boom");}try{f("\xFF\0\x27\\\n");}catch(Throwable $e){echo $e->getTraceAsString();}')
add('trace-ignore-args',r'ini_set("zend.exception_ignore_args","1");function f($x){throw new Exception("boom");}try{f("\xFF");}catch(Throwable $e){echo $e->getTraceAsString();}')
add('trace-byte-limit',r'ini_set("zend.exception_string_param_max_len","1");function f($x){throw new Exception("boom");}try{f("猫");}catch(Throwable $e){echo $e->getTraceAsString();}')
add('static-reference-string',r'class C{public static $v="A";static function &get(){return self::$v;}}$n="C";$x=&$n::get();$x.="\xFF";echo bin2hex(C::$v);')
assert len(new)==16
(HERE/'new-boundary16.cases.json').write_text(json.dumps(new,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
for case in new:provenance.append({'id':case['id'],'basis':'new_original_boundary_source','source_sha256':hashlib.sha256(case['code'].encode('utf-8')).hexdigest(),'selected_transport':case['mode']})
cases.extend(new);assert len(cases)==40 and len({c['id'] for c in cases})==40
target.write_text(json.dumps(cases,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
(HERE/'case-provenance.json').write_text(json.dumps({'existing_callback14':14,'existing_raw2':2,'existing_hex8':8,'new_boundary16':16,'code_bytes_unchanged_for_existing':True,'transport':'Callback scripts retain original PHP opening tag and are passed as actual files; existing hex bodies keep their original -r mode','known_limitation_control':'boundary.enum-weak-scalar-known-gap is retained as an explicit observation, not assumed passing','cases':provenance},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'total':len(cases),'existing_sources':24,'new_sources':16,'cases_sha256':sha(target)}))
