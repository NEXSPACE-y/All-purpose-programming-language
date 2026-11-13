"""Record official PHP offset observations before connecting the byte runtime.

Oracle only: no candidate is run, and these observations are not compatibility
passes. Each generated program is preserved for a later exact CLI comparison.
"""
from pathlib import Path
import argparse
import base64
import hashlib
import json
import subprocess
import time

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output',type=Path,required=True)
parser.add_argument('--php',type=Path,default=Path.home()/'ALL_php_oracle/php-8.5.12-ts-x64/php.exe')
args=parser.parse_args()
out=args.output.resolve()
if out.exists():
    raise SystemExit('Use a fresh output directory')
php=args.php.resolve(strict=True)
pin='0ac893499799256db6d3a54b0da73692e02311493922e6e4f86a062674a77d66'
if hashlib.sha256(php.read_bytes()).hexdigest()!=pin:
    raise SystemExit('Oracle differs from pinned PHP8.5.12')
handler='set_error_handler(function($n,$m){echo "W",$n,":",$m,"\\n";return true;});'
initial='$s="A\\xFF\\0B";'
programs=[
    ('read.integer','var_dump($s[1],$s[-1],$s[-4]);'),
    ('read.outside','var_dump($s[4],$s[-5]);'),
    ('read.numeric-string','var_dump($s["1"],$s[" 1 "],$s["+1"],$s["01"]);'),
    ('read.float-string','var_dump($s["1.0"]);'),
    ('read.prefix-string','var_dump($s["1x"]);'),
    ('read.nonnumeric-string','var_dump($s["x"]);'),
    ('read.scalar-cast','var_dump($s[true],$s[false],$s[null],$s[2.9]);'),
    ('read.array','var_dump($s[[]]);'),
    ('write.integer','$a=$s;$r=$s[1]="\\x80";var_dump($s,$a,$r);'),
    ('write.extend','$r=$s[7]="\\x80";var_dump($s,$r);'),
    ('write.negative','$r=$s[-2]="\\x80";var_dump($s,$r);'),
    ('write.negative-outside','$r=$s[-5]="\\x80";var_dump($s,$r);'),
    ('write.multibyte','$r=$s[0]="\\xFF\\0";var_dump($s,$r);'),
    ('write.empty','$s[1]="";var_dump($s);'),
    ('write.append','$s[]="x";var_dump($s);'),
    ('write.nested','$a=["s"=>$s];$b=$a;$a["s"][1]="\\x80";var_dump($a,$b);'),
    ('write.property','$o=new stdClass();$o->s=$s;$o->s[1]="\\x80";var_dump($o->s);'),
    ('write.compound','$s[1].="x";var_dump($s);'),
    ('write.reference','$r=&$s[1];var_dump($r);'),
]
cases=[{'id':'byte.offset.'+name,'mode':'body','code':handler+initial+'try{'+body+'}catch(Throwable $e){echo get_class($e),":",$e->getMessage();}'} for name,body in programs]
out.mkdir(parents=True)
(out/'cases.json').write_text(json.dumps(cases,indent=2)+'\n',encoding='utf-8')
rows=[]
for i,case in enumerate(cases):
    path=out/f'case-{i:02d}.php'
    path.write_bytes(('<?php '+case['code']).encode('utf-8'))
    command=[str(php),'-n','-d','display_errors=stderr','-d','error_reporting=-1','-r',case['code']]
    start=time.monotonic()
    result=subprocess.run(command,capture_output=True,timeout=30,creationflags=subprocess.CREATE_NO_WINDOW)
    rows.append({'id':case['id'],'command':command,'actual_exit_code':result.returncode,'elapsed_seconds':time.monotonic()-start,
                 'stdout_base64':base64.b64encode(result.stdout).decode('ascii'),'stderr_base64':base64.b64encode(result.stderr).decode('ascii'),
                 'source_sha256':hashlib.sha256(case['code'].encode('utf-8')).hexdigest()})
report={'status':'ORACLE_ONLY_NOT_CANDIDATE_VERIFICATION','candidate_invocations':0,'oracle_sha256':pin,'count':len(rows),'records':rows}
(out/'oracle.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
for row in rows:
    print(row['id']+' '+repr(base64.b64decode(row['stdout_base64'])))
