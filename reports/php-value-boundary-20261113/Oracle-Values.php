<?php
// Reference-only observations; the independent candidate never starts PHP.
function symbol_boundary_trace($value) { return (new Exception('x'))->getTraceAsString(); }
$values = ['ascii'=>'abc','raw'=>"\xFF",'nul'=>"a\0b",'quote'=>"a'b",'slash'=>"a\\b",'line'=>"a\nb",'control'=>"\x01\t\r",'long_ascii'=>str_repeat('A',20),'long_utf8'=>str_repeat('猫',8),'nfc'=>'é','nfd'=>'é'];
$rows=[];
foreach($values as $id=>$value) {
    try { match($value) {}; } catch(UnhandledMatchError $error) {
        $rows[]=['id'=>$id,'value_base64'=>base64_encode($value),'match_message_base64'=>base64_encode($error->getMessage()),'trace_base64'=>base64_encode(symbol_boundary_trace($value))];
    }
}
enum BoundaryEnum:string { case Num='7';case Raw="\xFF";case Nul="\0";case NFC='é';case NFD='é'; }
$enum=[];
foreach(['seven'=>'7','seven_int'=>7,'raw'=>"\xFF",'nul'=>"\0",'nfc'=>'é','nfd'=>'é','missing'=>"\xFE"] as $id=>$value) {
    try { $case=BoundaryEnum::from($value);$enum[]=['id'=>$id,'name'=>$case->name,'value_base64'=>base64_encode($case->value)]; }
    catch(Throwable $error) { $enum[]=['id'=>$id,'class'=>get_class($error),'message_base64'=>base64_encode($error->getMessage())]; }
}
echo json_encode(['scope'=>'official oracle only','exception_ignore_args'=>ini_get('zend.exception_ignore_args'),'exception_string_param_max_len'=>ini_get('zend.exception_string_param_max_len'),'strings'=>$rows,'enum'=>$enum],JSON_THROW_ON_ERROR|JSON_UNESCAPED_SLASHES);
