<?php declare(strict_types=1);
// Reference-only enum argument conversion matrix.
enum SE:string {case Zero='0';case One='1';case Seven='7';case Fraction='7.5';case Negative='-7';case Raw="\xFF";}
enum IE:int {case Zero=0;case One=1;case Seven=7;case Negative=-7;case Eight=8;}
class StringValue {function __toString():string{return '7';}}
$values=['null'=>null,'false'=>false,'true'=>true,'int0'=>0,'int7'=>7,'int8'=>8,'float7'=>7.0,'float7_5'=>7.5,'negative7_5'=>-7.5,'infinity'=>INF,'nan'=>NAN,'empty'=>'','zero'=>'0','seven'=>'7','decimal'=>'7.0','leading_zero'=>'07','exponent'=>'7e0','whitespace'=>' 7 ','nonnumeric'=>'7x','negative_zero'=>'-0','negative'=>'-7','nul'=>"\0",'raw'=>"\xFF",'array'=>[],'object'=>new stdClass,'stringable'=>new StringValue];
$warnings=[];
set_error_handler(function($level,$message)use(&$warnings){$warnings[]=['level'=>$level,'message_base64'=>base64_encode($message)];return true;});
$rows=[];
foreach(['SE','IE'] as $class)foreach(['from','tryFrom'] as $method)foreach($values as $id=>$value){
    $warnings=[];
    try{$result=$class::$method($value);$out=$result===null?['status'=>'null']:['status'=>'case','name'=>$result->name,'backing_type'=>gettype($result->value),'value_base64'=>is_string($result->value)?base64_encode($result->value):null,'integer_value'=>is_int($result->value)?$result->value:null];}
    catch(Throwable $error){$out=['status'=>'error','class'=>get_class($error),'message_base64'=>base64_encode($error->getMessage())];}
    $rows[]=['strict'=>1,'enum'=>$class,'method'=>$method,'id'=>$id,'input_type'=>get_debug_type($value),'result'=>$out,'warnings'=>$warnings];
}
restore_error_handler();
echo json_encode($rows,JSON_THROW_ON_ERROR|JSON_UNESCAPED_SLASHES);
