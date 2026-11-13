<?php
function wire($v){if(is_string($v))return ['bytes'=>base64_encode($v)];if(is_array($v)){ $r=[];foreach($v as $k=>$x)$r[]=[wire($k),wire($x)];return ['array'=>$r];}return $v;}
$cases=[
 ['strlen',[null]],['strlen',[[]]],['strtoupper',["\xffAz\xc3\xa9"]],['strtolower',["\xffAZ\xc3\x89"]],
 ['strpos',['abc','',-4]],['strpos',['abc','',4]],['strpos',['abc','',-3]],['strpos',['abc','',3]],
 ['substr',["\xc3\xa9X",1,1]],['substr',['abc',PHP_INT_MIN,PHP_INT_MAX]],['substr',['abc',1,PHP_INT_MIN]],
 ['str_replace',['','x','abc']],['str_replace',[['a','b'],['b','X'],'abc']],['str_replace',['a',['x'],'abc']],
 ['explode',['','abc']],['explode',[',','a,b,c',0]],['explode',[',','a,b,c',-1]],['explode',[',','abc',-1]],
 ['implode',[["\xff",'x']]],['implode',[null,['a','b']]],
 ['trim',['...a...', '..a']],['trim',['abcdef','z..a']],['trim',['abc','a..']],['trim',['abc','..b']],['trim',['abc','a..b..c']],
 ['str_repeat',['x',2.4]],['substr',['abc','1.9',1]],['strpos',['abc','b',[]]],['str_repeat',['a',-1]]
];
foreach($cases as $i=>[$f,$a]){ $events=[];set_error_handler(function($n,$s)use(&$events){$events[]=[$n,base64_encode($s)];return true;});$row=['id'=>$i,'function'=>$f,'args'=>wire($a)];try{$row['value']=wire($f(...$a));}catch(Throwable $e){$row['exception']=[get_class($e),base64_encode($e->getMessage())];}restore_error_handler();$row['events']=$events;echo json_encode($row),"\n";}
