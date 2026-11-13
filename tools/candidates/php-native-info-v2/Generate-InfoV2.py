"""Fresh independent core/byte-bridge copies; frozen inputs never overwritten."""
from pathlib import Path
import argparse
import difflib
import hashlib
import json

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]

TABLES=r'''// Text-mode rules only. HTML/SAPI mode is not supplied by this profile.
PHPAPI void php_info_print_table_start(void) {hit("php_info_print_table_start");tls.output+='\n';}
PHPAPI void php_info_print_table_end(void) {hit("php_info_print_table_end");}
static void all_info_text_cells(int columns,va_list cells,bool heading) {
    for(int column=0;column<columns;++column){
        const char *cell=va_arg(cells,const char*);bool blank=!cell||!*cell;
        tls.output+=blank?" ":cell;
        if(column+1==columns)tls.output+='\n';
        else if(heading||!blank)tls.output+=" => ";
    }
}
PHPAPI void php_info_print_table_header(int columns,...) {
    hit("php_info_print_table_header");va_list cells;va_start(cells,columns);all_info_text_cells(columns,cells,true);va_end(cells);
}
PHPAPI void php_info_print_table_row(int columns,...) {
    hit("php_info_print_table_row");va_list cells;va_start(cells,columns);all_info_text_cells(columns,cells,false);va_end(cells);
}
static void all_info_ini_value(zend_ini_entry &entry,int which) {
    if(entry.displayer){entry.displayer(&entry,which);return;}
    zend_string *value=(which==ZEND_INI_DISPLAY_ORIG&&entry.modified)?entry.orig_value:entry.value;
    if(value&&ZSTR_LEN(value)&&ZSTR_VAL(value)[0])tls.output.append(ZSTR_VAL(value),ZSTR_LEN(value));
    else tls.output+="no value";
}
ZEND_API void display_ini_entries(zend_module_entry *module) {
    hit("display_ini_entries");int number=module?module->module_number:0;bool first=true;
    for(const auto &name:runtime.ini_order){
        auto found=tls.ini.find(name);if(found==tls.ini.end()||found->second->entry.module_number!=number)continue;
        if(first){php_info_print_table_start();php_info_print_table_header(3,"Directive","Local Value","Master Value");first=false;}
        auto &entry=found->second->entry;
        tls.output.append(ZSTR_VAL(entry.name),ZSTR_LEN(entry.name));tls.output+=" => ";
        all_info_ini_value(entry,ZEND_INI_DISPLAY_ACTIVE);tls.output+=" => ";all_info_ini_value(entry,ZEND_INI_DISPLAY_ORIG);tls.output+='\n';
    }
    if(!first)php_info_print_table_end();
}
'''

MODULE_INFO=r'''int all_php_module_info(void){
    if(!tls.active||!runtime.module)return -1;
    auto *module=runtime.module;
    if(module->info_func||module->version){
        php_info_print_table_start();php_info_print_table_header(1,module->name);php_info_print_table_end();
        if(module->info_func)module->info_func(module);
        else{php_info_print_table_start();php_info_print_table_row(2,"Version",module->version);php_info_print_table_end();display_ini_entries(module);}
    }else{tls.output+=module->name;tls.output+='\n';}
    return 0;
}'''


def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def once(text,old,new):
 count=text.count(old)
 if count!=1:raise ValueError(("Expected one frozen anchor",count,old[:90]))
 return text.replace(old,new)


def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output-directory',type=Path,required=True);a=p.parse_args();out=a.output_directory.resolve()
 assert out.is_relative_to(HERE)and not out.exists();out.mkdir(parents=True)
 inventory=json.loads((ROOT/'reports/php-native-coverage-20261113/static01/inventory.json').read_text())
 pins=inventory['input_hashes_before'];records=[]
 pins.update({
  (ROOT/'tools/candidates/php-byte-native/generated04/AllNativeLegacyBridge.cs').as_posix():'4f1ebbe77a692b6e2846cb4d180b06679542ed4dc37c57a91c7310029644c94d',
  (ROOT/'tools/candidates/php-byte-native/generated04/AllNativeCallbackBridge.cs').as_posix():'c4a20f91216e33fd2af06e0a39c57f336b859e4515f2fcc217756cc62f6e4b79',
 })
 def emit(origin,destination,changed):
  original=origin.read_bytes();assert sha(origin)==pins[origin.as_posix()]
  destination.parent.mkdir(parents=True,exist_ok=True);destination.write_text(changed,encoding='utf-8',newline='\n')
  patch=destination.with_suffix(destination.suffix+'.patch');patch.write_text(''.join(difflib.unified_diff(original.decode('utf-8-sig').splitlines(True),changed.splitlines(True),fromfile=origin.as_posix(),tofile=destination.as_posix())),encoding='utf-8',newline='\n')
  records.append({'original':origin.as_posix(),'original_sha256':hashlib.sha256(original).hexdigest(),'candidate':destination.as_posix(),'candidate_sha256':sha(destination),'patch_sha256':sha(patch)})
 for mode,folder in [('legacy','php85abi'),('callback','php85abi-callback')]:
  source=ROOT/('native/'+folder+'/src/Runtime.cpp');value=source.read_text(encoding='utf-8-sig')
  value=once(value,'    std::map<std::string,IniDefinition> ini;','    std::map<std::string,IniDefinition> ini;\n    std::vector<std::string> ini_order;')
  value=once(value,'entry.name=intern(def->name,def->name_length,true); entry.def=def;entry.on_modify=def->on_modify;','entry.name=intern(def->name,def->name_length,true); entry.def=def;entry.on_modify=def->on_modify;entry.displayer=def->displayer;')
  value=once(value,'void clear_ini() {for(auto &p:tls.ini) string_release(p.second->entry.value);tls.ini.clear();}','void clear_ini() {for(auto &p:tls.ini){string_release(p.second->entry.value);string_release(p.second->entry.orig_value);}tls.ini.clear();}')
  value=once(value,'runtime.ini[d->name]={d,number};','runtime.ini[d->name]={d,number};runtime.ini_order.emplace_back(d->name);')
  old='for(auto it=runtime.ini.begin();it!=runtime.ini.end();)if(it->second.module==number)it=runtime.ini.erase(it);else ++it;'
  new='for(auto it=runtime.ini.begin();it!=runtime.ini.end();)if(it->second.module==number)it=runtime.ini.erase(it);else ++it;runtime.ini_order.erase(std::remove_if(runtime.ini_order.begin(),runtime.ini_order.end(),[](const std::string &name){return runtime.ini.find(name)==runtime.ini.end();}),runtime.ini_order.end());'
  value=once(value,old,new)
  start=value.index('PHPAPI void php_info_print_table_start(void)');end=value.index('\n\nint all_php_load_extension',start)
  value=value[:start]+TABLES.rstrip()+value[end:]
  value=once(value,'const char *all_php_error_message(void){return tls.error.c_str();}','const char *all_php_error_message(void){return tls.error.c_str();}\nconst char *all_php_error_message_bytes(size_t *length){if(length)*length=tls.error.size();return tls.error.data();}')
  value=once(value,'string_release(e.value);e.value=s;e.modified=1;','if(!e.modified){e.orig_value=e.value;if(e.orig_value&&!(GC_FLAGS(e.orig_value)&IS_STR_INTERNED))++e.orig_value->gc.refcount;e.orig_modifiable=e.modifiable;}string_release(e.value);e.value=s;e.modified=1;')
  value=once(value,'int all_php_module_info(void){if(!tls.active||!runtime.module||!runtime.module->info_func)return -1;runtime.module->info_func(runtime.module);return 0;}',MODULE_INFO)
  value=once(value,'runtime.constants.clear();runtime.ini.clear();','runtime.constants.clear();runtime.ini.clear();runtime.ini_order.clear();')
  emit(source,out/mode/'src/Runtime.cpp',value)
  header=ROOT/('native/'+folder+'/include/all_php_bridge.h');text=header.read_text(encoding='utf-8-sig')
  text=once(text,'ALL_ABI_EXPORT const char *all_php_error_message(void);','ALL_ABI_EXPORT const char *all_php_error_message(void);\n/* v2 additive sized getter; borrowed bytes copied before another operation. */\nALL_ABI_EXPORT const char *all_php_error_message_bytes(size_t *length);')
  emit(header,out/mode/'include/all_php_bridge.h',text)
 for filename,old_namespace,new_namespace in [('AllNativeLegacyBridge.cs','AllPhp85AbiByte','AllPhp85AbiInfoV2Byte'),('AllNativeCallbackBridge.cs','AllPhp85AbiCallbackByte','AllPhp85AbiCallbackInfoV2Byte')]:
  origin=ROOT/'tools/candidates/php-byte-native/generated04'/filename;text=origin.read_text(encoding='utf-8-sig')
  text=once(text,'namespace '+old_namespace+' {','namespace '+new_namespace+' {')
  text=once(text,'private SizedStringDelegate output,diagnostics;','private SizedStringDelegate output,diagnostics,errorMessageBytes;')
  text=once(text,'errorMessage=Bind<StringDelegate>("all_php_error_message");','errorMessage=Bind<StringDelegate>("all_php_error_message");errorMessageBytes=Bind<SizedStringDelegate>("all_php_error_message_bytes");')
  text=once(text,'PhpBytes message=code==0?null:CopyNativeCString(errorMessage());','PhpBytes message=code==0?null:CaptureBytes(errorMessageBytes);')
  emit(origin,out/'bridge'/filename,text)
 record={'status':'GENERATED_NOT_BUILT_OR_RUNTIME_VERIFIED','approval':'Existing owner-approved native option A and byte model1; no stock runtime links/forwarding','generator_sha256':sha(Path(__file__)),'files':records,'original_inputs_unchanged':all(sha(Path(row['original']))==row['original_sha256']for row in records),
         'contract_changes':['New sized error_message_bytes export; old getter/layout unchanged','Text-mode module wrapper/table header/table end/row cells/INI table rules','INI display order/displayer/original-value retention for actual display contract','New bridge namespaces and sized PHP error-message copy; original bridges unchanged'],
         'limits':['No HTML/SAPI implementation','MINFO lifecycle callback contract not added','General INI stages/rollback and non-scalar value ownership remain incomplete']}
 (out/'provenance.json').write_text(json.dumps(record,indent=2)+'\n',encoding='utf-8');print(json.dumps({'files':len(records),'original_inputs_unchanged':record['original_inputs_unchanged']}))


if __name__=='__main__':main()
