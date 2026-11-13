<?php
declare(strict_types=0);
$events=[];
set_error_handler(function($level,$message)use(&$events){$events[]=['level'=>$level,'message_base64'=>base64_encode($message)];return true;});
$record=['ok'=>true,'error_class'=>null,'error_message_base64'=>null];
try{$value=dl_test_test2(base64_decode('AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8gISIjJCUmJygpKissLS4vMDEyMzQ1Njc4OTo7PD0+P0BBQkNERUZHSElKS0xNTk9QUVJTVFVWV1hZWltcXV5fYGFiY2RlZmdoaWprbG1ub3BxcnN0dXZ3eHl6e3x9fn+AgYKDhIWGh4iJiouMjY6PkJGSk5SVlpeYmZqbnJ2en6ChoqOkpaanqKmqq6ytrq+wsbKztLW2t7i5uru8vb6/wMHCw8TFxsfIycrLzM3Oz9DR0tPU1dbX2Nna29zd3t/g4eLj5OXm5+jp6uvs7e7v8PHy8/T19vf4+fr7/P3+/w==',true));$record['value']=is_string($value)?['type'=>'string','value'=>base64_encode($value)]:(is_int($value)?['type'=>'int','value'=>(string)$value]:(is_null($value)?['type'=>'null','value'=>null]:['type'=>get_debug_type($value),'value'=>$value]));}
catch(Throwable $error){$record['ok']=false;$record['error_class']=get_class($error);$record['error_message_base64']=base64_encode($error->getMessage());$record['value']=['type'=>'null','value'=>null];}
$record['events']=$events;
file_put_contents($argv[1],json_encode($record,JSON_THROW_ON_ERROR));
