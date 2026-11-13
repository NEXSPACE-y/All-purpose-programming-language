"""Separate raw-message controls; retain the earlier literal-backslash cases."""
from pathlib import Path
import json
root=Path(__file__).resolve().parent;target=root/'callback-raw2.cases.json'
if target.exists():raise SystemExit('Preserve fixed original raw controls')
capture='echo count($args),":",$args[0],":",bin2hex($args[1]),":",gettype($args[2]),":",gettype($args[3]);return true;'
trigger=r'trigger_error("payload\xFF",E_USER_WARNING);'
rows=[
 dict(id='callback.arguments.raw-closure',code='<?php $h=function(...$args){'+capture+'};set_error_handler($h);'+trigger),
 dict(id='callback.arguments.raw-array-method',code='<?php class H{function go(...$args){'+capture+'}}$h=new H();set_error_handler([$h,"go"]);'+trigger),
]
target.write_text(json.dumps(rows,indent=2)+'\n',encoding='utf-8');print(json.dumps({'raw_message_controls':len(rows)}))
