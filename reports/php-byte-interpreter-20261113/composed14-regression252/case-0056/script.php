<?php function f($x){return $x;} $fn="f"; echo $fn(<<<TXT
argument
TXT);
?>done