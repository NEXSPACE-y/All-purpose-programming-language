<?php
declare(strict_types=0);
$events=[];
set_error_handler(function($level,$message)use(&$events){$events[]=['level'=>$level,'message_base64'=>base64_encode($message)];return true;});
$record=['ok'=>true,'error_class'=>null,'error_message_base64'=>null];
try{$value=dl_test_test2(base64_decode('7aCA',true));$record['value']=is_string($value)?['type'=>'string','value'=>base64_encode($value)]:(is_int($value)?['type'=>'int','value'=>(string)$value]:(is_null($value)?['type'=>'null','value'=>null]:['type'=>get_debug_type($value),'value'=>$value]));}
catch(Throwable $error){$record['ok']=false;$record['error_class']=get_class($error);$record['error_message_base64']=base64_encode($error->getMessage());$record['value']=['type'=>'null','value'=>null];}
$record['events']=$events;
file_put_contents($argv[1],json_encode($record,JSON_THROW_ON_ERROR));
