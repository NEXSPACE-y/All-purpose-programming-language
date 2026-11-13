<?php function f(){if(false){?>NO<?php }return <<<TXT
YES
TXT;
}echo f();?>TAIL