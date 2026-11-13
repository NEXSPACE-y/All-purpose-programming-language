<?php namespace N;use function call_user_func as call;function f($x){return $x;} ?>X<?php echo call('N\\f',<<<TXT
Y
TXT);
?>Z