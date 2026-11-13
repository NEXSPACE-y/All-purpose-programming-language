<?php
declare(strict_types=0);

function all_value($value){return is_string($value)?['type'=>'string','value'=>base64_encode($value)]:(is_int($value)?['type'=>'int','value'=>(string)$value]:(is_null($value)?['type'=>'null','value'=>null]:['type'=>get_debug_type($value),'value'=>$value]));}
$observations=[];$events=[];
set_error_handler(function($level,$message)use(&$events){$events[]=['level'=>$level,'message_base64'=>base64_encode($message)];return true;});

$events=[];$row=['operation'=>'call','function'=>'dcngettext','ok'=>true,'value'=>all_value(null),'error_class'=>null,'error_message_base64'=>null];ob_start();try{$row['value']=all_value(dcngettext(base64_decode('YWxsX3BocF9nZXR0ZXh0XzIwMjYxMTEz'),base64_decode('b25l'),base64_decode('bWFueQ=='),(int)'2',(int)'0'));}catch(Throwable $e){$row['ok']=false;$row['error_class']=get_class($e);$row['error_message_base64']=base64_encode($e->getMessage());}$output=ob_get_clean();echo $output;$row['output_base64']=base64_encode($output);$row['events']=$events;$observations[]=$row;
file_put_contents($argv[1],json_encode(['observations'=>$observations],JSON_THROW_ON_ERROR));
