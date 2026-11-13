"""New default weak-mode cases; original composed07 forty inputs stay fixed."""
from pathlib import Path
import json
HERE=Path(__file__).resolve().parent;target=HERE/'enum-weak12.cases.json'
if target.exists():raise SystemExit('Preserve original new definitions')
rows=[]
def add(id,code):rows.append(dict(id='enum.weak.'+id,mode='body',code=code))
warn='set_error_handler(function($level,$message){echo $level,":",$message,"\\n";return true;});'
add('string-int','enum E:string{case A="7";}echo E::from(7)->name;')
add('string-bool-null',warn+'enum E:string{case Z="0";case O="1";}echo E::from(false)->name,E::from(true)->name,E::from(null)->name;')
add('string-float',warn+'enum E:string{case A="7";case B="-7";}echo E::from(7.0)->name,E::from(7.5)->name,E::from(-7.5)->name;')
add('integer-numeric-string','enum E:int{case A=7;}echo E::from("07")->name,E::from("7.0")->name,E::from("7e0")->name,E::from(" 7 ")->name;')
add('integer-float-string',warn+'enum E:int{case A=7;}echo E::from("7.5")->name;')
add('integer-null-bool',warn+'enum E:int{case Z=0;case O=1;}echo E::from(null)->name,E::from(false)->name,E::from(true)->name;')
add('stringable','class S{function __toString(){return "7";}}enum E:string{case A="7";}echo E::from(new S())->name;')
add('integer-stringable-reject','class S{function __toString(){return "7";}}enum E:int{case A=7;}try{E::from(new S());}catch(TypeError $e){echo $e->getMessage();}')
add('string-reject-types','enum E:string{case A="7";}try{E::from([]);}catch(TypeError $e){echo $e->getMessage(),"\\n";}try{E::from(new stdClass());}catch(TypeError $e){echo $e->getMessage();}')
add('tryfrom-canonical','enum E:int{case A=7;}var_dump(E::TRYFROM("8"),count(E::CASES()));try{E::TRYFROM([]);}catch(TypeError $e){echo $e->getMessage();}')
add('bad-string-nul',r'enum E:string{case A="a";}try{E::from("x\0y");}catch(ValueError $e){echo bin2hex($e->getMessage());}')
add('nonfinite-string',warn+'enum E:string{case A="INF";case B="NAN";}echo E::from(INF)->name,E::from(NAN)->name;')
assert len(rows)==12;target.write_text(json.dumps(rows,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');print(json.dumps({'new_weak_cases':len(rows),'strict_cases_claimed':False}))
