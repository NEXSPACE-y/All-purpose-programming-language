"""Copy the frozen MO and prepare separate Windows locale oracle controls."""
from pathlib import Path
import hashlib
import json
import os
import shutil

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
REPORT=ROOT/'reports/php-gettext-locale-20261113'
OUT=REPORT/'prepared01'
OLD=ROOT/'reports/php-native-gettext-20261113/prepared01'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
save=lambda p,x:p.write_text(json.dumps(x,indent=2)+'\n',encoding='utf-8')
assert not OUT.exists()
manifest=json.loads((OLD/'prepared-manifest.json').read_text())
assert sha(OLD/'prepared-manifest.json')=='7233554d73698495f56f5ec27b588ed32afefc89b09ed7d89a9c5ae0916ee646'
relative='owned/catalog/zz_ALL/LC_MESSAGES/all_php_gettext_20261113.mo'
original=OLD/relative;assert sha(original)==manifest['files'][relative]['sha256']
OUT.mkdir(parents=True);catalog=OUT/'owned/catalog';copied=catalog/'zz_ALL/LC_MESSAGES'/original.name;copied.parent.mkdir(parents=True);shutil.copyfile(original,copied);assert sha(copied)==sha(original)
keys=['LC_ALL','LC_MESSAGES','LANG','LANGUAGE','LC_CTYPE']
env=lambda **kw:{key:kw.get(key)for key in keys}
cases=[
    ('locale.C-encoding',env(LC_ALL='C.UTF-8',LANG='C.UTF-8',LANGUAGE='zz_ALL')),
    ('locale.C-exact',env(LC_ALL='C',LC_MESSAGES='zz_ALL',LANG='en_US.UTF-8',LANGUAGE='zz_ALL')),
    ('locale.language-nonC',env(LANG='en_US.UTF-8',LANGUAGE='zz_ALL')),
    ('locale.all-over-messages',env(LC_ALL='en_US.UTF-8',LC_MESSAGES='C',LANG='C',LANGUAGE='zz_ALL')),
    ('locale.messages-over-lang',env(LC_MESSAGES='zz_ALL',LANG='C.UTF-8')),
    ('locale.lang-only',env(LANG='zz_ALL')),
    ('locale.messages-over-catalog-lang',env(LC_MESSAGES='en_US.UTF-8',LANG='zz_ALL')),
    ('locale.language-fallback',env(LANG='en_US.UTF-8',LANGUAGE='not_existing:zz_ALL')),
]
program=r'''<?php
$keys=['LC_ALL','LC_MESSAGES','LANG','LANGUAGE','LC_CTYPE'];$environment=[];
foreach($keys as $key){$value=getenv($key);$environment[$key]=$value===false?null:$value;}
$record=['environment_inside_php'=>$environment,'constants'=>['LC_ALL'=>LC_ALL,'LC_CTYPE'=>LC_CTYPE,'LC_MESSAGES_defined'=>defined('LC_MESSAGES'),'LC_MESSAGES'=>defined('LC_MESSAGES')?constant('LC_MESSAGES'):null],'initial_CRT_locale_all'=>setlocale(LC_ALL,0),'initial_CRT_locale_ctype'=>setlocale(LC_CTYPE,0)];
$requested='English_United States.utf8';$accepted=setlocale(LC_ALL,$requested);
$record['requested_CRT_locale']=$requested;$record['returned_CRT_locale']=$accepted;
$record['actual_CRT_locale_all']=setlocale(LC_ALL,0);$record['actual_CRT_locale_ctype']=setlocale(LC_CTYPE,0);
$record['LC_MESSAGES_native_query']='Not queried: Microsoft CRT category set does not include LC_MESSAGES; message selection is measured through gettext outputs.';
$domain='all_php_gettext_20261113';$directory=base64_decode('CATALOG_BASE64');
$record['bound_directory']=bindtextdomain($domain,$directory);
$record['singular_base64']=base64_encode(dgettext($domain,'probe'));
$record['plural_base64']=base64_encode(dngettext($domain,'apple','apples',2));
$record['translation_observed']=($record['singular_base64']===base64_encode('catalog-translated')&&$record['plural_base64']===base64_encode('catalog-many'));
echo json_encode($record,JSON_THROW_ON_ERROR),"\n";
'''
import base64
program=program.replace('CATALOG_BASE64',base64.b64encode(str(catalog).encode()).decode())
rows=[]
for identity,environment in cases:
    folder=OUT/identity;folder.mkdir();source=folder/'oracle.php';source.write_text(program,encoding='utf-8',newline='\n')
    rows.append({'id':identity,'environment_overrides':environment,'null_means_remove_in_child_only':True,'source':str(source),'source_sha256':sha(source),'copied_mo_sha256':sha(copied),'expected_catalog_payloads_base64':{'singular':base64.b64encode(b'catalog-translated').decode(),'plural':base64.b64encode(b'catalog-many').decode()},'interpretation':'Observe selection; untranslated identity is not a translation pass.'})
save(OUT/'controls.json',rows)
save(OUT/'preparation-process-environment.json',{'status':'CURRENT_PREPARATION_PROCESS_NOT_HISTORICAL51_ENVIRONMENT','locale_environment':{key:os.environ.get(key)for key in keys}})
save(OUT/'provenance.json',{'status':'PREPARED_NOT_EXECUTED','original_mo':str(original),'original_mo_sha256':sha(original),'copied_mo':str(copied),'copied_mo_sha256':sha(copied),'original_prepared_manifest_sha256':sha(OLD/'prepared-manifest.json'),'controls':len(rows),'timeout_seconds':30,'old51_inputs_changed':False,'source':str(Path(__file__).resolve()),'source_sha256':sha(Path(__file__).resolve()),'oracle_or_candidate_execution_count':0,'OS_locale_or_machine_environment_changed':False})
files=[p for p in OUT.rglob('*')if p.is_file()]
save(OUT/'manifest.json',{'status':'FROZEN_NEW_CONTROLS_NOT_EXECUTED','files':{p.relative_to(OUT).as_posix():{'sha256':sha(p),'bytes':p.stat().st_size}for p in sorted(files)}})
print(json.dumps({'status':'PREPARED_NOT_EXECUTED','controls':len(rows),'copied_mo_sha256':sha(copied),'manifest_sha256':sha(OUT/'manifest.json')}))
