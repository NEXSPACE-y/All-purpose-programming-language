<?php
// Reference-only byte escaping and truncation, not candidate execution.
function boundary_trace_argument($value) { return (new Exception('x'))->getTraceAsString(); }
$rows=[];
for($byte=0;$byte<256;$byte++) {
    try { match(chr($byte)) {}; } catch(UnhandledMatchError $error) {
        $rows[]=['byte'=>$byte,'message_base64'=>base64_encode($error->getMessage())];
    }
}
$limits=[];
foreach([0,1,3,15] as $limit) {
    ini_set('zend.exception_string_param_max_len',(string)$limit);
    $value="\xFFa\nb猫";
    try { match($value) {}; } catch(UnhandledMatchError $error) {
        $limits[]=['limit'=>$limit,'message_base64'=>base64_encode($error->getMessage()),'trace_base64'=>base64_encode(boundary_trace_argument($value))];
    }
}
ini_set('zend.exception_ignore_args','1');
$ignored=boundary_trace_argument('abc');
echo json_encode(['rows'=>$rows,'limits'=>$limits,'ignored_trace_base64'=>base64_encode($ignored)],JSON_THROW_ON_ERROR|JSON_UNESCAPED_SLASHES);
