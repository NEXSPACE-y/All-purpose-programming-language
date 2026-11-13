<?php
declare(strict_types=0);

function all_value($value){return is_string($value)?['type'=>'string','value'=>base64_encode($value)]:(is_int($value)?['type'=>'int','value'=>(string)$value]:(is_null($value)?['type'=>'null','value'=>null]:['type'=>get_debug_type($value),'value'=>$value]));}
$observations=[];$events=[];
set_error_handler(function($level,$message)use(&$events){$events[]=['level'=>$level,'message_base64'=>base64_encode($message)];return true;});

ob_start();(new ReflectionExtension('gettext'))->info();$output=ob_get_clean();echo $output;$observations[]=['operation'=>'module_info','output_base64'=>base64_encode($output)];
file_put_contents($argv[1],json_encode(['observations'=>$observations],JSON_THROW_ON_ERROR));
