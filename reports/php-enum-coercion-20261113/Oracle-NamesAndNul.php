<?php
enum E:string {case A='a';}
enum I:int {case A=7;}
$rows=[];
foreach(["x\0y","\0abc","xy\0","\xFF\0z"] as $value){
    try{E::FROM($value);}catch(Throwable $error){$rows[]=['value_base64'=>base64_encode($value),'class'=>get_class($error),'message_base64'=>base64_encode($error->getMessage())];}
}
try{E::TRYFROM([]);}catch(Throwable $error){$rows[]=['id'=>'upper_tryfrom','class'=>get_class($error),'message_base64'=>base64_encode($error->getMessage())];}
$rows[]=['id'=>'upper_cases','count'=>count(I::CASES())];
echo json_encode($rows,JSON_THROW_ON_ERROR|JSON_UNESCAPED_SLASHES);
