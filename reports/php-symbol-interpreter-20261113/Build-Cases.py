"""Keep existing definitions unchanged and add independent PHP source examples."""
from pathlib import Path
import json
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[1]
target=HERE/'symbols40.cases.json'
if target.exists():raise SystemExit('Preserve prior fixed cases')
old=json.loads((ROOT/'tools/candidates/php-identifiers/identifier-audit.cases.json').read_text(encoding='utf-8-sig'))
cases=[c for c in old if c['id'] not in ['identifier.raw-byte-0x80','identifier.raw-byte-0xff','identifier.strtolower-nonascii']]
more=[
 ('parameter-nfc-distinct','function f($é=1,$é=2){return $é+$é;}echo f();'),
 ('parameter-nfc-named','function f($é=1,$é=2){return $é+$é;}echo f(é:5);'),
 ('property-nfc-distinct','class C{public $é=1;public $é=2;} $x=new C();echo $x->é,":",$x->é;'),
 ('class-unicode-distinct','class É{public function x(){return 1;}}class é{public function x(){return 2;}}echo (new É())->x(),":",(new é())->x();'),
 ('method-nfc-distinct','class C{function é(){return 1;}function é(){return 2;}}$x=new C();echo $x->é(),":",$x->é();'),
 ('constant-prefix-ascii','namespace MiXeD;const VaL=7;echo \\mixed\\VaL;'),
 ('constant-leaf-sensitive','define("MiXeD\\\\VaL",7);var_dump(defined("mixed\\\\VaL"),defined("mixed\\\\val"));'),
 ('array-callable-japanese','class 猫{static function 鳴く($x){return $x+1;}}$f=["猫","鳴く"];echo $f(4),":",call_user_func_array($f,["x"=>6]);'),
 ('arabic-digit-label','function ١(){return 5;}echo ١();'),
 ('keyword-kelvin-control','function breaK(){return 9;}echo breaK();'),
 ('ascii-keyword-case','FuNcTiOn f(){ReTuRn 8;}EcHo f();'),
]
cases.extend(dict(id='symbols.'+id,code='<?php '+body) for id,body in more)
assert len(cases)==40
target.write_text(json.dumps(cases,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
before_ids={'identifier.variable-japanese','identifier.function-japanese','identifier.class-japanese','identifier.namespace-japanese','identifier.function-unicode-case','identifier.function-emoji','identifier.function-nbsp','identifier.ascii-class-canonical','symbols.constant-prefix-ascii','symbols.keyword-kelvin-control'}
(HERE/'before10.cases.json').write_text(json.dumps([c for c in cases if c['id'] in before_ids],ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
(HERE/'case-provenance.json').write_text(json.dumps({'unchanged_original_cases':len(cases)-len(more),'new_original_sources':len(more),'exclusions':{'raw_byte_0x80_0xff':'Outside valid-UTF8 decoder scope; old failing audit retained','strtolower_nonascii':'String builtin byte migration owned separately'},'total':len(cases)},indent=2)+'\n',encoding='utf-8')
print(json.dumps({'total':len(cases),'before':len(before_ids)}))
