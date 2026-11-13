<?php
$keys=['LC_ALL','LC_MESSAGES','LANG','LANGUAGE','LC_CTYPE'];$environment=[];
foreach($keys as $key){$value=getenv($key);$environment[$key]=$value===false?null:$value;}
$record=['environment_inside_php'=>$environment,'constants'=>['LC_ALL'=>LC_ALL,'LC_CTYPE'=>LC_CTYPE,'LC_MESSAGES_defined'=>defined('LC_MESSAGES'),'LC_MESSAGES'=>defined('LC_MESSAGES')?constant('LC_MESSAGES'):null],'initial_CRT_locale_all'=>setlocale(LC_ALL,0),'initial_CRT_locale_ctype'=>setlocale(LC_CTYPE,0)];
$requested='English_United States.utf8';$accepted=setlocale(LC_ALL,$requested);
$record['requested_CRT_locale']=$requested;$record['returned_CRT_locale']=$accepted;
$record['actual_CRT_locale_all']=setlocale(LC_ALL,0);$record['actual_CRT_locale_ctype']=setlocale(LC_CTYPE,0);
$record['LC_MESSAGES_native_query']='Not queried: Microsoft CRT category set does not include LC_MESSAGES; message selection is measured through gettext outputs.';
$domain='all_php_gettext_20261113';$directory=base64_decode('QzpcVXNlcnNccmlucGFcQUxMLXBocC1jb21wYXQtMjAyNjExMTJccmVwb3J0c1xwaHAtZ2V0dGV4dC1sb2NhbGUtMjAyNjExMTNccHJlcGFyZWQwMVxvd25lZFxjYXRhbG9n');
$record['bound_directory']=bindtextdomain($domain,$directory);
$record['singular_base64']=base64_encode(dgettext($domain,'probe'));
$record['plural_base64']=base64_encode(dngettext($domain,'apple','apples',2));
$record['translation_observed']=($record['singular_base64']===base64_encode('catalog-translated')&&$record['plural_base64']===base64_encode('catalog-many'));
echo json_encode($record,JSON_THROW_ON_ERROR),"\n";
