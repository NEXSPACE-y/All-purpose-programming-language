"""Same-source callback argument observations; no func_num_args/introspection."""
from pathlib import Path
import json
HERE=Path(__file__).resolve().parent;target=HERE/'callback-arguments.cases.json'
if target.exists():raise SystemExit('Preserve fixed original cases')
cases=[]
def add(id,body):cases.append(dict(id='callback.arguments.'+id,code='<?php '+body))
capture='echo count($args),":",gettype($args[0]),":",$args[0],":",bin2hex($args[1]),":",gettype($args[2]),":",gettype($args[3]);return true;'
add('named-variadic','function h(...$args){'+capture+'}set_error_handler("h");trigger_error("payload\\xFF",E_USER_WARNING);')
add('closure-variadic','$h=function(...$args){'+capture+'};set_error_handler($h);trigger_error("payload\\xFF",E_USER_WARNING);')
capture_tail='echo $level,":",count($rest),":",bin2hex($rest[0]),":",gettype($rest[1]),":",gettype($rest[2]);return true;'
add('named-one-plus-variadic','function h($level,...$rest){'+capture_tail+'}set_error_handler("h");trigger_error("payload\\xFF",E_USER_WARNING);')
add('closure-one-plus-variadic','$h=function($level,...$rest){'+capture_tail+'};set_error_handler($h);trigger_error("payload\\xFF",E_USER_WARNING);')
add('first-class','function h(...$args){'+capture+'}$h=h(...);set_error_handler($h);trigger_error("payload\\xFF",E_USER_WARNING);')
add('array-static','class H{static function go(...$args){'+capture+'}}set_error_handler(["H","go"]);trigger_error("payload\\xFF",E_USER_WARNING);')
add('array-instance','class H{function go(...$args){'+capture+'}}$h=new H();set_error_handler([$h,"go"]);trigger_error("payload\\xFF",E_USER_WARNING);')
add('invokable','class H{function __invoke(...$args){'+capture+'}}$h=new H();set_error_handler($h);trigger_error("payload\\xFF",E_USER_WARNING);')
add('named-zero','function h(){echo "zero";return true;}set_error_handler("h");trigger_error("payload\\xFF",E_USER_WARNING);')
add('closure-zero','$h=function(){echo "zero";return true;};set_error_handler($h);trigger_error("payload\\xFF",E_USER_WARNING);')
add('named-one','function h($level){echo $level;return true;}set_error_handler("h");trigger_error("payload\\xFF",E_USER_WARNING);')
add('closure-one','$h=function($level){echo $level;return true;};set_error_handler($h);trigger_error("payload\\xFF",E_USER_WARNING);')
add('builtin-four','set_error_handler("strlen");try{trigger_error("payload\\xFF",E_USER_WARNING);}catch(ArgumentCountError $e){echo $e->getMessage();}')
add('closure-all-four','$h=function($level,$message,$file,$line){echo $level,":",bin2hex($message),":",gettype($file),":",gettype($line);return true;};set_error_handler($h);trigger_error("payload\\xFF",E_USER_WARNING);')
target.write_text(json.dumps(cases,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'cases':len(cases),'capture_count_proofs':8,'zero_one_controls':4,'builtin_control':1,'fixed_four_control':1}))
