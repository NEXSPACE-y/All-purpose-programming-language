<?php
declare(strict_types=0);
$events=[];
set_error_handler(function($level,$message)use(&$events){$events[]=['level'=>$level,'message_base64'=>base64_encode($message)];return true;});
$record=['ok'=>true,'error_class'=>null,'error_message_base64'=>null];
try{ini_set('dl_test.string',base64_decode('AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyAhIiMkJSYnKCkqKywtLi8wMTIzNDU2Nzg5Ojs8PT4/QEFCQ0RFRkdISUpLTE1OT1BRUlNUVVZXWFlaW1xdXl9gYWJjZGVmZ2hpamtsbW5vcHFyc3R1dnd4eXp7fH1+f4CBgoOEhYaHiImKi4yNjo+QkZKTlJWWl5iZmpucnZ6foKGio6SlpqeoqaqrrK2ur7CxsrO0tba3uLm6u7y9vr/AwcLDxMXGx8jJysvMzc7P0NHS09TV1tfY2drb3N3e3+Dh4uPk5ebn6Onq6+zt7u/w8fLz9PX29/j5+vv8/f7/',true));$record['ini_value_base64']=base64_encode(ini_get('dl_test.string'));(new ReflectionExtension('dl_test'))->info();$value=null;$record['value']=is_string($value)?['type'=>'string','value'=>base64_encode($value)]:(is_int($value)?['type'=>'int','value'=>(string)$value]:(is_null($value)?['type'=>'null','value'=>null]:['type'=>get_debug_type($value),'value'=>$value]));}
catch(Throwable $error){$record['ok']=false;$record['error_class']=get_class($error);$record['error_message_base64']=base64_encode($error->getMessage());$record['value']=['type'=>'null','value'=>null];}
$record['events']=$events;
file_put_contents($argv[1],json_encode($record,JSON_THROW_ON_ERROR));
