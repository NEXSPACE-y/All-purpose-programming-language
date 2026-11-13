<?php $s="";for($i=0;$i<256;$i++){$s.=chr($i);}echo base64_encode(strtolower($s)),"
",base64_encode(strtoupper($s));