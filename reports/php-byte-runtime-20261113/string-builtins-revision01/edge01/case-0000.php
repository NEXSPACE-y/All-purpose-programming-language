<?php
set_error_handler(function($n,$s){echo $n,":",$s,"\n";return true;});
var_dump(strlen(null),str_repeat("x",2.4),substr("abc","1.9",1));
var_dump(trim("...a...","..a"),trim("abcdef","z..a"),trim("abc","a.."),trim("abc","a..b..c"));
var_dump(str_replace(["a","b"],["b","X"],"abc"),str_replace(["\xFF","a"],["a"],["\x80"=>"\xFFa",7=>"a\xFF"]));
var_dump(substr("abc",PHP_INT_MIN,PHP_INT_MAX),substr("abc",1,PHP_INT_MIN));
try{strpos("abc","",-4);}catch(ValueError $e){echo $e->getMessage(),"\n";}
try{strpos("abc","",4);}catch(ValueError $e){echo $e->getMessage(),"\n";}
try{strlen([]);}catch(TypeError $e){echo $e->getMessage(),"\n";}
try{explode("","abc");}catch(ValueError $e){echo $e->getMessage(),"\n";}
try{str_replace("a",["x"],"abc");}catch(TypeError $e){echo $e->getMessage(),"\n";}
try{strpos("abc","b",[]);}catch(TypeError $e){echo $e->getMessage(),"\n";}
try{str_repeat("x",-1);}catch(ValueError $e){echo $e->getMessage(),"\n";}
try{strlen();}catch(ArgumentCountError $e){echo $e->getMessage(),"\n";}
var_dump(implode(null,["a","b"]),explode(",","a,b,c",0),trim("\f\xFF\f"));
