"""Decode the actual module/function table and contract references, no DLL load."""
from pathlib import Path
import hashlib
import importlib.util
import json
import zipfile

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
binary=Path('C:/Users/rinpa/ALL_php_oracle/php-8.5.12-ts-x64/ext/php_gettext.dll')
assert sha(binary)=='ed395f80018920ba1b4551cdc33dd89871eb8b8ef362b1515ae93c0e7f1de3ad'
spec=importlib.util.spec_from_file_location('pe',ROOT/'tools/abi/Inspect-NativeAbi.py');pe=importlib.util.module_from_spec(spec);spec.loader.exec_module(pe)
image=pe.PE(binary);meta=image.module_metadata(image.exports());assert meta['status']=='statically_decoded'
entry=image.offset(meta['module_entry_rva']);table=image.u64(entry+40);functions=[]
for index in range(256):
 offset=image.offset(table-image.image_base+48*index);name=image.u64(offset)
 if not name:break
 handler=image.u64(offset+8);arginfo=image.u64(offset+16);declared=image.u32(offset+24);flags=image.u32(offset+28)
 required=image.u64(image.offset(arginfo-image.image_base))if arginfo else 0
 assert 0<=required<=declared<=64
 functions.append({'name':image.pointer_string(name),'handler_rva':handler-image.image_base,'declared_args':declared,'required_args':required,'flags':flags,'method':'Static SDK48-byte function-entry and module+40 pointer; not execution'})
else:raise ValueError('Unterminated static function table')
archive=Path('C:/Users/rinpa/Downloads/php-8.5.12-1-src.zip');assert sha(archive)=='9dac05f72f328afd0a2b0e795a519ae4cb3d056bc3f3b55147bd048bd64e45e8'
contracts={}
with zipfile.ZipFile(archive)as z:
 for member,terms in {'Zend/zend_virtual_cwd.h':['virtual_getcwd(','virtual_realpath('], 'Zend/zend_virtual_cwd.c':['virtual_getcwd(','virtual_realpath('], 'Zend/zend_API.h':['zend_argument_value_error(','zend_argument_must_not_be_empty_error('], 'Zend/zend_API.c':['zend_argument_value_error(','zend_argument_must_not_be_empty_error(','zend_argument_error_variadic('], 'ext/gettext/gettext.c':['PHP_GETTEXT_MAX_DOMAIN_LENGTH','PHP_GETTEXT_MAX_MSGID_LENGTH','VCWD_REALPATH','VCWD_GETCWD','zend_argument_value_error','zend_argument_must_not_be_empty_error'], 'ext/gettext/gettext_arginfo.h':['ext_functions','ZEND_RAW_FENTRY']}.items():
  data=z.read(member);lines=data.decode('utf-8-sig').splitlines();contracts[member]={'sha256':hashlib.sha256(data).hexdigest(),'anchor_lines':{term:[i for i,line in enumerate(lines,1)if term in line]for term in terms}}
cores={}
for mode in ('legacy','callback'):
 path=ROOT/('tools/candidates/php-native-info-v2/out/'+mode+'01/php8ts.dll');exports={name for e in pe.PE(path).exports()for name in e['names']};names={s['name']for item in image.imports()if item['dll'].lower()=='php8ts.dll'for s in item['symbols']if'name'in s}
 cores[mode]={'path':str(path),'sha256':sha(path),'missing_names':sorted(names-exports),'present_names':sorted(names&exports)}
out=ROOT/'reports/php-native-gettext-20261113';assert not(out/'inventory.json').exists();out.mkdir(parents=True,exist_ok=True)
record={'status':'READ_ONLY_STATIC_GETTEXT_DEPENDENCY_NOT_LOAD_OR_COMPATIBILITY_PROOF','binary':str(binary),'sha256':sha(binary),'machine':image.machine,'module_metadata':meta,'functions':functions,'imports':image.imports(),'current_info_v2_cores':cores,'reference_archive':{'path':str(archive),'sha256':sha(archive),'contracts':contracts},'extension_or_stock_php_loaded_or_executed':False,'os_or_dependency_installed':False,'implementation_changed':False}
(out/'inventory.json').write_text(json.dumps(record,indent=2)+'\n',encoding='utf-8');print(json.dumps({'functions':functions,'missing_names':cores['callback']['missing_names'],'loaded':False}))
