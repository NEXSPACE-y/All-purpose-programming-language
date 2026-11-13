<?php
var_dump(strlen("\xFF\0\u{10000}"),strtoupper("\xFFaZé"),strtolower("\xFFAZÉ"));
var_dump(trim(" \0\xFF\v\t"),trim("\x00\x01\x80x\xFF","\0..\x80\xFF"));
var_dump(str_contains("a\xFF\0z","\xFF\0"),str_starts_with("\xFFa","\xFF"),str_ends_with("a\xFF","\xFF"));
var_dump(strpos("é\xFFx","\xFF"),strpos("abc","",-3),strpos("abc","",3),substr("éX",1,1));
var_dump(str_replace("\xFF","\0","a\xFFb\xFF"),str_replace("","X","abc"),explode("\xFF","a\xFF\xFFz"));
var_dump(explode(",","a,b,c",2),explode(",","a,b,c",-1),explode(",","abc",-1));
var_dump(implode("\xFF",["a","\0","z"]),implode(["\xFF","x"]),str_repeat("\xFF\0",3),strval("\xFF"),is_string("\xFF"),gettype("\xFF"));
