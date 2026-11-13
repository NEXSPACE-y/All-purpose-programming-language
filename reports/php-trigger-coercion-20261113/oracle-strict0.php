<?php declare(strict_types=0);
// Reference-only builtin parameter conversion and canonical function names.
class RawStringValue {function __toString():string{return "\xFF";}}
$values=['null'=>null,'array'=>[],'object'=>new stdClass,'stringable'=>new RawStringValue,'raw'=>"\xFF",'int'=>7,'float'=>7.5,'true'=>true,'false'=>false];
$diagnostics=[];
set_error_handler(function($level,$message)use(&$diagnostics){$diagnostics[]=['level'=>$level,'message_base64'=>base64_encode($message)];return true;});
$rows=[];
foreach(['trigger_error','TRIGGER_ERROR','user_error','USER_ERROR','\\trigger_error','\\USER_ERROR'] as $function) {
    foreach($values as $id=>$value) {
        $diagnostics=[];
        try{$result=$function($value,E_USER_WARNING);$out=['status'=>'return','value'=>$result];}
        catch(Throwable $error){$out=['status'=>'error','class'=>get_class($error),'message_base64'=>base64_encode($error->getMessage())];}
        $rows[]=['strict'=>0,'function'=>$function,'argument'=>'message','id'=>$id,'result'=>$out,'diagnostics'=>$diagnostics];
    }
    foreach([0,3] as $count) {
        $diagnostics=[];
        try{$result=$count===0?$function():$function('x',E_USER_WARNING,99);$out=['status'=>'return','value'=>$result];}
        catch(Throwable $error){$out=['status'=>'error','class'=>get_class($error),'message_base64'=>base64_encode($error->getMessage())];}
        $rows[]=['strict'=>0,'function'=>$function,'argument'=>'count','id'=>(string)$count,'result'=>$out,'diagnostics'=>$diagnostics];
    }
}
foreach(['null'=>null,'array'=>[],'numeric_string'=>'512','nonnumeric'=>'x','fraction'=>512.5] as $id=>$level) {
    $diagnostics=[];
    try{$result=trigger_error('x',$level);$out=['status'=>'return','value'=>$result];}
    catch(Throwable $error){$out=['status'=>'error','class'=>get_class($error),'message_base64'=>base64_encode($error->getMessage())];}
    $rows[]=['strict'=>0,'function'=>'trigger_error','argument'=>'error_level','id'=>$id,'result'=>$out,'diagnostics'=>$diagnostics];
}
restore_error_handler();
echo json_encode($rows,JSON_THROW_ON_ERROR|JSON_UNESCAPED_SLASHES);
