<?php
// Oracle-only arity observation. debug_backtrace is not assumed implemented by
// the independent candidate; its later same-source profile uses variadic capture.
$rows=[];
function boundary_record($args) {
    global $rows;
    $rows[]=['count'=>count($args),'types'=>array_map('gettype',$args),'level'=>$args[0]??null,'message_base64'=>isset($args[1])?base64_encode($args[1]):null,'file_base64'=>isset($args[2])?base64_encode($args[2]):null,'line'=>$args[3]??null];
    return true;
}
function boundary_zero() { return boundary_record(debug_backtrace(0,1)[0]['args']); }
function boundary_one($level) { return boundary_record(debug_backtrace(0,1)[0]['args']); }
function boundary_many(...$args) { return boundary_record($args); }
function boundary_four($level,$message,$file,$line) { return boundary_record([$level,$message,$file,$line]); }
class BoundaryHandlers {
    static function zero() { return boundary_record(debug_backtrace(0,1)[0]['args']); }
    function one($level) { return boundary_record(debug_backtrace(0,1)[0]['args']); }
    function __invoke(...$args) { return boundary_record($args); }
}
$object=new BoundaryHandlers;
$handlers=[
    'zero_named'=>'boundary_zero','one_named'=>'boundary_one','variadic_named'=>'boundary_many','four_named'=>'boundary_four',
    'zero_closure'=>function(){return boundary_record(debug_backtrace(0,1)[0]['args']);},
    'one_closure'=>function($level){return boundary_record(debug_backtrace(0,1)[0]['args']);},
    'variadic_closure'=>function(...$args){return boundary_record($args);},
    'first_class'=>boundary_many(...),'static_array'=>[BoundaryHandlers::class,'zero'],'instance_array'=>[$object,'one'],'invokable'=>$object,
    'builtin'=>'strlen'
];
$observations=[];
foreach($handlers as $id=>$handler) {
    $before=count($rows);$error=null;
    set_error_handler($handler);
    try { trigger_error("payload\xFF",E_USER_WARNING); }
    catch(Throwable $failure) {$error=['class'=>get_class($failure),'message_base64'=>base64_encode($failure->getMessage())];}
    finally {restore_error_handler();}
    $observations[]=['id'=>$id,'observed'=>count($rows)>$before?$rows[$before]:null,'error'=>$error];
}
echo json_encode($observations,JSON_THROW_ON_ERROR|JSON_UNESCAPED_SLASHES);
