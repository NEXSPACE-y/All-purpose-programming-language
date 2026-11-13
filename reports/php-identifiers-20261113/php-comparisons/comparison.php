<?php
function probe_0_Foo(){return 1;}
echo "ascii:",function_exists('probe_0_foo')?"1":"0",":",base64_encode(strtolower('Foo')),"\n";
function probe_1_É(){return 1;}
echo "latin-e-acute:",function_exists('probe_1_é')?"1":"0",":",base64_encode(strtolower('É')),"\n";
function probe_2_S(){return 1;}
echo "long-s:",function_exists('probe_2_ſ')?"1":"0",":",base64_encode(strtolower('S')),"\n";
function probe_3_K(){return 1;}
echo "kelvin:",function_exists('probe_3_K')?"1":"0",":",base64_encode(strtolower('K')),"\n";
function probe_4_Σ(){return 1;}
echo "sigma:",function_exists('probe_4_σ')?"1":"0",":",base64_encode(strtolower('Σ')),"\n";
function probe_5_Σ(){return 1;}
echo "final-sigma:",function_exists('probe_5_ς')?"1":"0",":",base64_encode(strtolower('Σ')),"\n";
function probe_6_I(){return 1;}
echo "dotless-i:",function_exists('probe_6_ı')?"1":"0",":",base64_encode(strtolower('I')),"\n";
function probe_7_i(){return 1;}
echo "dotted-i:",function_exists('probe_7_İ')?"1":"0",":",base64_encode(strtolower('i')),"\n";
function probe_8_ẞ(){return 1;}
echo "sharp-s:",function_exists('probe_8_ß')?"1":"0",":",base64_encode(strtolower('ẞ')),"\n";
function probe_9_é(){return 1;}
echo "normalization:",function_exists('probe_9_é')?"1":"0",":",base64_encode(strtolower('é')),"\n";
function probe_10_𐐀(){return 1;}
echo "deseret:",function_exists('probe_10_𐐨')?"1":"0",":",base64_encode(strtolower('𐐀')),"\n";
function probe_11_A(){return 1;}
echo "confusable-cyrillic:",function_exists('probe_11_А')?"1":"0",":",base64_encode(strtolower('A')),"\n";
function probe_12_猫(){return 1;}
echo "japanese-same:",function_exists('probe_12_猫')?"1":"0",":",base64_encode(strtolower('猫')),"\n";
function probe_13_猫(){return 1;}
echo "japanese-distinct:",function_exists('probe_13_犬')?"1":"0",":",base64_encode(strtolower('猫')),"\n";
function probe_14_FF(){return 1;}
echo "ligature:",function_exists('probe_14_ﬀ')?"1":"0",":",base64_encode(strtolower('FF')),"\n";
