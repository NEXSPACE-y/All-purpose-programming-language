// ALL-owned PHP 8.5.12 ABI candidate. Implemented from API contracts, not PHP .c files.
// The compatibility DLL is never linked to, or forwarded to, stock PHP.
#define NOMINMAX
#define ENABLE_INTSAFE_SIGNED_FUNCTIONS
#include <algorithm>
#include <atomic>
#include <cmath>
#include <cerrno>
#include <climits>
#include <cstdarg>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <limits>
#include <iomanip>
#include <locale>
#include <map>
#include <memory>
#include <mutex>
#include <sstream>
#include <regex>
#include <string>
#include <thread>
#include <unordered_map>
#include <vector>
extern "C" {
__declspec(dllexport) char *virtual_getcwd(char *,size_t);
__declspec(dllexport) char *virtual_realpath(const char *,char *);
}
#include "php.h"
#include "zend_ini.h"
#include "zend_constants.h"
#include "zend_string.h"
#include "ext/standard/info.h"
#include "all_php_bridge.h"
#undef vsnprintf

namespace {
struct Function { zend_function raw{}; std::string name; const zend_function_entry *entry{}; };
struct Property { zend_property_info raw{}; zval initial{}; };
struct Class { zend_class_entry raw{}; std::map<std::string, Function*> methods; std::map<std::string, std::unique_ptr<Property>> properties; };
struct IniDefinition { const zend_ini_entry_def *def{}; int module{}; };
struct IniValue { zend_ini_entry entry{}; };
struct Allocation { size_t bytes; DWORD thread; uint64_t request; };
struct Diagnostic { int level; std::string message; bool delivered=false; };
struct CallbackAbort {};
struct ThreadState {
    void **storage = nullptr; // TSRM cache's first pointer is the resource table.
    void *slots[16]{};
    bool attached=false, active=false, strict=false;
    std::string error_class, error, output, diagnostics, stats, ini_result;
    std::wstring cwd_wide;
    std::string cwd_bytes;
    std::map<wchar_t,std::wstring> drive_cwds;
    std::vector<Diagnostic> diagnostic_events;
    std::map<std::string, std::unique_ptr<IniValue>> ini;
    zend_execute_data *current=nullptr;
    zval last{};
    uint64_t requests_started=0, requests_ended=0, global_ctors=0;
    all_php_diagnostic_callback diagnostic_callback=nullptr;
    all_php_output_callback output_callback=nullptr;
    void *callback_user=nullptr;
    DWORD callback_thread=0;
    uint64_t callback_request=0;
    int owned_invocation_depth=0;
    ThreadState() { storage=slots; ZVAL_UNDEF(&last); }
    ~ThreadState();
};
thread_local ThreadState tls;
struct Runtime {
    HMODULE extension=nullptr;
    zend_module_entry *module=nullptr;
    std::map<std::string,std::unique_ptr<Function>> functions;
    std::vector<std::unique_ptr<Function>> method_functions;
    std::map<std::string,std::unique_ptr<Class>> classes;
    std::map<std::string,IniDefinition> ini;
    std::vector<std::string> ini_order;
    std::map<std::string,std::unique_ptr<zend_constant>> constants;
    std::map<std::string,zend_string*> interned;
    std::map<void*,Allocation> request_allocations;
    std::map<std::string,uint64_t> calls;
    std::recursive_mutex mutex;
    std::atomic<uint64_t> minit{0},mshutdown{0},rinit{0},rshutdown{0},invocations{0},tls_created{0},tls_destroyed{0};
    std::atomic<DWORD> callback_owner{0};
    std::atomic<uint64_t> callback_calls{0},callback_aborts{0},callback_rejections{0},callback_output_bytes{0},contract_started{0},contract_after_diagnostic{0};
} runtime;
ThreadState::~ThreadState() {if(attached&&slots[0]){if(runtime.module&&runtime.module->globals_dtor)runtime.module->globals_dtor(slots[0]);std::free(slots[0]);++runtime.tls_destroyed;}}

void hit(const char *name) { std::lock_guard<std::recursive_mutex> lock(runtime.mutex); ++runtime.calls[name]; }
std::string lower(std::string value) { for(char &c:value) if(c>='A'&&c<='Z') c=static_cast<char>(c+32); return value; }
void error(const char *kind,const std::string &message) { tls.error_class=kind; tls.error=message; }
void clear_error() { tls.error_class.clear(); tls.error.clear(); }
std::string json_string(const std::string &value) {std::ostringstream s;s<<'\"';for(unsigned char c:value){if(c=='\\'||c=='\"')s<<'\\';if(c<32)s<<"\\u00"<<std::hex<<std::setw(2)<<std::setfill('0')<<static_cast<unsigned>(c)<<std::dec;else s<<c;}s<<'\"';return s.str();}
void diagnostic(int level,const std::string &message);
bool callback_owner_valid(){DWORD owner=runtime.callback_owner.load();if(owner&&owner!=GetCurrentThreadId()){++runtime.callback_rejections;error("ALLNativeUnsupported","Callback prototype rejects another native thread before execution");return false;}if(tls.diagnostic_callback&&(!tls.active||tls.callback_thread!=GetCurrentThreadId()||tls.callback_request!=tls.requests_started)){++runtime.callback_rejections;error("ALLNativeUnsupported","Callback prototype request ownership mismatch");return false;}return true;}
std::string format(const char *fmt,va_list ap) {
    va_list copy; va_copy(copy,ap); int n=vsnprintf(nullptr,0,fmt,copy); va_end(copy);
    if(n<0) return "[formatting error]";
    std::vector<char> data(static_cast<size_t>(n)+1); vsnprintf(data.data(),data.size(),fmt,ap); return {data.data(),static_cast<size_t>(n)};
}
void *allocate(size_t size,bool request) {
    void *p=std::malloc(size?size:1); if(!p) { error("Error","ALL native ABI: allocation failed"); return nullptr; }
    if(request) { std::lock_guard<std::recursive_mutex> lock(runtime.mutex); runtime.request_allocations[p]={size,GetCurrentThreadId(),tls.requests_started}; }
    return p;
}
void release(void *p) {
    if(!p) return;
    {std::lock_guard<std::recursive_mutex> lock(runtime.mutex);auto it=runtime.request_allocations.find(p);if(it!=runtime.request_allocations.end()&&it->second.thread!=GetCurrentThreadId()){error("ALLNativeUnsupported","Cross-thread native value ownership transfer is unsupported");return;}runtime.request_allocations.erase(p);}
    std::free(p);
}
zend_string *string_new(const char *bytes,size_t len,bool persistent=false,bool interned=false) {
    if(len>SIZE_MAX - offsetof(zend_string,val)-1) return nullptr;
    auto *s=static_cast<zend_string*>(allocate(offsetof(zend_string,val)+len+1,!persistent));
    if(!s) return nullptr;
    GC_SET_REFCOUNT(s,1); GC_TYPE_INFO(s)=GC_STRING;
    if(persistent) GC_ADD_FLAGS(s,IS_STR_PERSISTENT);
    if(interned) GC_ADD_FLAGS(s,IS_STR_INTERNED);
    s->h=0; s->len=len; if(len) std::memcpy(s->val,bytes,len); s->val[len]=0; return s;
}
// ALL implementation of the Windows UTF-8 virtual-directory boundary.
// Each request snapshots host cwd once. Resolution never changes process cwd.
bool cwd_from_utf8(const char *data,size_t length,std::wstring &result) {
    if(length>INT_MAX||std::memchr(data,0,length)){errno=EINVAL;return false;}
    if(!length){result.clear();return true;}
    int count=MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,data,static_cast<int>(length),nullptr,0);
    if(!count){errno=EILSEQ;return false;}result.resize(count);
    return MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,data,static_cast<int>(length),&result[0],count)==count;
}
bool cwd_to_utf8(const std::wstring &value,std::string &result) {
    if(value.size()>INT_MAX){errno=ENAMETOOLONG;return false;}
    if(value.empty()){result.clear();return true;}
    int count=WideCharToMultiByte(CP_UTF8,WC_ERR_INVALID_CHARS,value.data(),static_cast<int>(value.size()),nullptr,0,nullptr,nullptr);
    if(!count){errno=EILSEQ;return false;}result.resize(count);
    return WideCharToMultiByte(CP_UTF8,WC_ERR_INVALID_CHARS,value.data(),static_cast<int>(value.size()),&result[0],count,nullptr,nullptr)==count;
}
int cwd_win32_errno(DWORD code) {
    switch(code){case ERROR_FILE_NOT_FOUND:case ERROR_PATH_NOT_FOUND:case ERROR_INVALID_DRIVE:return ENOENT;
    case ERROR_ACCESS_DENIED:case ERROR_SHARING_VIOLATION:return EACCES;
    case ERROR_FILENAME_EXCED_RANGE:case ERROR_BUFFER_OVERFLOW:return ENAMETOOLONG;
    case ERROR_DIRECTORY:return ENOTDIR;default:return EINVAL;}
}
std::wstring cwd_root(const std::wstring &path) {
    if(path.size()>1&&path[1]==L':')return path.substr(0,2)+L"\\";
    if(path.size()>1&&path[0]==L'\\'&&path[1]==L'\\'){
        size_t server=path.find(L'\\',2);if(server!=std::wstring::npos){size_t share=path.find(L'\\',server+1);return share==std::wstring::npos?path+L"\\":path.substr(0,share+1);}
    }return L"";
}
bool cwd_request_initialize() {
    tls.cwd_wide.clear();tls.cwd_bytes.clear();tls.drive_cwds.clear();
    DWORD needed=GetCurrentDirectoryW(0,nullptr);if(!needed){errno=cwd_win32_errno(GetLastError());return false;}
    std::vector<wchar_t> current(needed);DWORD size=GetCurrentDirectoryW(needed,current.data());
    if(!size||size>=needed){errno=EINVAL;return false;}tls.cwd_wide.assign(current.data(),size);
    if(!cwd_to_utf8(tls.cwd_wide,tls.cwd_bytes)||tls.cwd_bytes.size()>=MAXPATHLEN)return false;
    for(wchar_t drive=L'A';drive<=L'Z';++drive){
        std::wstring name=L"=";name+=drive;name+=L":";DWORD count=GetEnvironmentVariableW(name.c_str(),nullptr,0);
        if(count){std::vector<wchar_t> value(count);DWORD actual=GetEnvironmentVariableW(name.c_str(),value.data(),count);if(actual&&actual<count)tls.drive_cwds[drive]=std::wstring(value.data(),actual);}
    }
    if(tls.cwd_wide.size()>1&&tls.cwd_wide[1]==L':'){
        wchar_t drive=tls.cwd_wide[0];if(drive>=L'a'&&drive<=L'z')drive-=32;tls.drive_cwds[drive]=tls.cwd_wide;
    }return true;
}
void cwd_request_clear(){tls.cwd_wide.clear();tls.cwd_bytes.clear();tls.drive_cwds.clear();}
bool cwd_resolve(const char *input,size_t length,std::wstring &canonical,std::string &bytes) {
    if(!tls.active||tls.cwd_wide.empty()){errno=ENOENT;return false;}
    if(length>=MAXPATHLEN){errno=ENAMETOOLONG;return false;}
    std::wstring path;if(!cwd_from_utf8(input,length,path))return false;
    std::replace(path.begin(),path.end(),L'/',L'\\');
    if(path.empty())path=tls.cwd_wide;
    else if(path.size()>1&&path[1]==L':'){
        if(path.size()==2||path[2]!=L'\\'){
            wchar_t drive=path[0];if(drive>=L'a'&&drive<=L'z')drive-=32;
            auto found=tls.drive_cwds.find(drive);std::wstring base=found==tls.drive_cwds.end()?std::wstring(1,drive)+L":\\":found->second;
            path=base+(base.back()==L'\\'?L"":L"\\")+path.substr(2);
        }
    }else if(path.size()>1&&path[0]==L'\\'&&path[1]==L'\\'){}
    else if(path[0]==L'\\')path=cwd_root(tls.cwd_wide)+path.substr(1);
    else path=tls.cwd_wide+(tls.cwd_wide.back()==L'\\'?L"":L"\\")+path;
    // Input is now absolute; GetFullPathName cannot consult changing process cwd.
    DWORD needed=GetFullPathNameW(path.c_str(),0,nullptr,nullptr);
    if(!needed){errno=cwd_win32_errno(GetLastError());return false;}
    std::vector<wchar_t> full(needed);DWORD size=GetFullPathNameW(path.c_str(),needed,full.data(),nullptr);
    if(!size||size>=needed){errno=ENAMETOOLONG;return false;}
    HANDLE file=CreateFileW(full.data(),FILE_READ_ATTRIBUTES,FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_SHARE_DELETE,nullptr,OPEN_EXISTING,FILE_FLAG_BACKUP_SEMANTICS,nullptr);
    if(file==INVALID_HANDLE_VALUE){errno=cwd_win32_errno(GetLastError());return false;}
    DWORD final_needed=GetFinalPathNameByHandleW(file,nullptr,0,FILE_NAME_NORMALIZED|VOLUME_NAME_DOS);
    if(!final_needed){DWORD last=GetLastError();CloseHandle(file);errno=cwd_win32_errno(last);return false;}
    std::vector<wchar_t> resolved(final_needed+1);DWORD final_size=GetFinalPathNameByHandleW(file,resolved.data(),static_cast<DWORD>(resolved.size()),FILE_NAME_NORMALIZED|VOLUME_NAME_DOS);
    DWORD last=GetLastError();CloseHandle(file);
    if(!final_size||final_size>=resolved.size()){errno=cwd_win32_errno(last);return false;}
    canonical.assign(resolved.data(),final_size);
    if(canonical.compare(0,8,L"\\\\?\\UNC\\")==0)canonical=L"\\\\"+canonical.substr(8);
    else if(canonical.compare(0,4,L"\\\\?\\")==0)canonical.erase(0,4);
    if(!cwd_to_utf8(canonical,bytes))return false;
    if(bytes.size()>=MAXPATHLEN){errno=ENAMETOOLONG;return false;}return true;
}

void string_release(zend_string *s) {
    if(s && !(GC_FLAGS(s)&IS_STR_INTERNED) && --s->gc.refcount==0) release(s);
}
zend_string *ZEND_FASTCALL intern(const char *bytes,size_t len,bool permanent) {
    hit("zend_string_init_interned"); std::lock_guard<std::recursive_mutex> lock(runtime.mutex);
    std::string key(bytes,len); auto it=runtime.interned.find(key); if(it!=runtime.interned.end()) return it->second;
    auto *value=string_new(bytes,len,true,true); runtime.interned[key]=value; return value;
}
void destroy(zval *v) {
    if(Z_TYPE_P(v)==IS_STRING) string_release(Z_STR_P(v));
    else if(Z_TYPE_P(v)==IS_ARRAY) release(Z_ARR_P(v));
    else if(Z_TYPE_P(v)==IS_OBJECT) release(Z_OBJ_P(v));
    ZVAL_UNDEF(v);
}
void copy_value(zval *dest,const zval *src) {
    *dest=*src; if(Z_TYPE_P(dest)==IS_STRING && !(GC_FLAGS(Z_STR_P(dest))&IS_STR_INTERNED)) ++Z_STR_P(dest)->gc.refcount;
}
// Native-only transient frame. No managed exception is permitted to cross this scope.
struct CallbackTransientState {
    zval last;zend_execute_data *current;bool strict;
    std::string error_class,error,output,diagnostics;std::vector<Diagnostic> events;
    CallbackTransientState():last(tls.last),current(tls.current),strict(tls.strict),error_class(std::move(tls.error_class)),error(std::move(tls.error)),output(std::move(tls.output)),diagnostics(std::move(tls.diagnostics)),events(std::move(tls.diagnostic_events)){ZVAL_UNDEF(&tls.last);tls.output.clear();tls.diagnostics.clear();tls.diagnostic_events.clear();}
    ~CallbackTransientState(){destroy(&tls.last);tls.last=last;tls.current=current;tls.strict=strict;tls.error_class=std::move(error_class);tls.error=std::move(error);tls.output=std::move(output);tls.diagnostics=std::move(diagnostics);tls.diagnostic_events=std::move(events);}
};
void flush_callback_output(){
    if(!tls.output_callback||tls.output.empty())return;
    std::string bytes=std::move(tls.output);tls.output.clear();int status;
    {CallbackTransientState preserve;status=tls.output_callback(reinterpret_cast<const unsigned char*>(bytes.data()),bytes.size(),tls.callback_user);}
    if(status!=1)throw CallbackAbort{};runtime.callback_output_bytes+=bytes.size();
}
void diagnostic(int level,const std::string &message){
    bool delivered=false;
    if(tls.diagnostic_callback){
        if(tls.owned_invocation_depth<=0){++runtime.callback_rejections;error("ALLNativeUnsupported","Synchronous diagnostic outside an owned native invocation is rejected");return;}
        if(!callback_owner_valid())throw CallbackAbort{};
        flush_callback_output();int status;++runtime.callback_calls;
        {CallbackTransientState preserve;status=tls.diagnostic_callback(level,reinterpret_cast<const unsigned char*>(message.data()),message.size(),tls.callback_user);}
        if(status!=1)throw CallbackAbort{};delivered=true;
    }
    tls.diagnostic_events.push_back({level,message,delivered});
    if(!delivered)tls.diagnostics+=(level==E_DEPRECATED?"Deprecated: ":level==E_WARNING?"Warning: ":"Diagnostic: ")+message+"\n";
}
zend_ulong hash_bytes(const char *s,size_t n) { zend_ulong h=5381; for(size_t i=0;i<n;++i) h=h*33+static_cast<unsigned char>(s[i]); return h | (static_cast<zend_ulong>(1)<<63); }
void hash_initialize(HashTable *table,uint32_t capacity=8) {
    std::memset(table,0,sizeof(*table)); GC_SET_REFCOUNT(table,1); GC_TYPE_INFO(table)=GC_ARRAY;
    table->nTableSize=capacity; table->nTableMask=HT_SIZE_TO_MASK(capacity);
    size_t hashes=HT_HASH_SIZE(table->nTableMask);
    auto *raw=static_cast<char*>(std::calloc(1,hashes+capacity*sizeof(Bucket)));
    std::memset(raw,0xff,hashes); table->arData=reinterpret_cast<Bucket*>(raw+hashes);
}
void hash_pointer(HashTable *table,const std::string &name,void *ptr) {
    if(table->nNumUsed>=table->nTableSize) { error("ALLNativeUnsupported","Native class table capacity exceeded"); return; }
    auto h=hash_bytes(name.data(),name.size()); auto index=table->nNumUsed++;
    auto *b=table->arData+index; b->h=h; b->key=intern(name.data(),name.size(),true); ZVAL_PTR(&b->val,ptr);
    uint32_t slot=static_cast<uint32_t>(h)|table->nTableMask;
    Z_NEXT(b->val)=HT_HASH(table,slot); HT_HASH(table,slot)=HT_IDX_TO_HASH(index); ++table->nNumOfElements;
}
void hash_destroy_storage(HashTable *table) {
    if(table->arData) std::free(reinterpret_cast<char*>(table->arData)-HT_HASH_SIZE(table->nTableMask));
    std::memset(table,0,sizeof(*table));
}
std::unique_ptr<Function> function_new(const zend_function_entry *entry,zend_class_entry *scope) {
    auto fn=std::make_unique<Function>(); fn->entry=entry; fn->name=entry->fname;
    fn->raw.internal_function.type=ZEND_INTERNAL_FUNCTION;
    fn->raw.internal_function.fn_flags=entry->flags;
    fn->raw.internal_function.function_name=intern(entry->fname,std::strlen(entry->fname),true);
    fn->raw.internal_function.scope=scope;
    fn->raw.internal_function.num_args=entry->num_args;
    fn->raw.internal_function.required_num_args=entry->arg_info?static_cast<uint32_t>(reinterpret_cast<uintptr_t>(entry->arg_info[0].name)):0;
    fn->raw.internal_function.arg_info=const_cast<zend_internal_arg_info*>(entry->arg_info?entry->arg_info+1:nullptr);
    fn->raw.internal_function.handler=entry->handler;
    fn->raw.internal_function.module=runtime.module;
    fn->raw.internal_function.frameless_function_infos=entry->frameless_function_infos;
    return fn;
}
std::string callable() {
    if(!tls.current||!tls.current->func) return "[native]";
    auto *f=tls.current->func; std::string out;
    if(f->common.scope) out=std::string(ZSTR_VAL(f->common.scope->name))+"::";
    return out+ZSTR_VAL(f->common.function_name);
}
std::string type_name(const zval *arg) {
    switch(Z_TYPE_P(arg)) { case IS_NULL:return "null";case IS_FALSE:case IS_TRUE:return "bool";case IS_LONG:return "int";case IS_DOUBLE:return "float";case IS_STRING:return "string";case IS_ARRAY:return "array";case IS_OBJECT:return "object";default:return "unknown"; }
}
std::string argument_name(uint32_t number) {
    if(tls.current&&tls.current->func&&number>0&&number<=tls.current->func->common.num_args) {
        auto *info=tls.current->func->internal_function.arg_info;
        if(info&&info[number-1].name) return info[number-1].name;
    }
    return "value";
}
std::string float_text(double value) {std::ostringstream s;s.imbue(std::locale::classic());s<<std::setprecision(14)<<value;return s.str();}
void null_deprecation(uint32_t number,const char *type) {diagnostic(E_DEPRECATED,callable()+"(): Passing null to parameter #"+std::to_string(number)+" ($"+argument_name(number)+") of type "+type+" is deprecated");}
bool numeric_double(const std::string &text,double *number) {
    static const std::regex syntax("^[ \\t\\r\\n\\f\\v]*[+-]?(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)(?:[eE][+-]?[0-9]+)?[ \\t\\r\\n\\f\\v]*$");
    if(!std::regex_match(text,syntax))return false;char *end=nullptr;*number=std::strtod(text.c_str(),&end);return std::isfinite(*number);
}
void *ini_target(void *offset,void *id) {
    if(!id) {error("ALLNativeUnsupported","INI callback has no resource id");return nullptr;}
    int index=*static_cast<ts_rsrc_id*>(id)-1;
    if(index<0||index>=16||!tls.slots[index]) {error("Error","INI callback resource is not attached");return nullptr;}
    return static_cast<char*>(tls.slots[index])+reinterpret_cast<uintptr_t>(offset);
}
int attach_thread() {
    if(tls.attached) return 0; auto *m=runtime.module; if(!m) return -1;
    tls.slots[0]=std::calloc(1,m->globals_size?m->globals_size:1); if(!tls.slots[0]) return -1;
    tls.attached=true;++runtime.tls_created; if(m->globals_ctor) {m->globals_ctor(tls.slots[0]);++tls.global_ctors;} return 0;
}
int apply_ini_defaults() {
    for(auto &pair:runtime.ini) {
        auto value=std::make_unique<IniValue>(); auto &entry=value->entry; auto *def=pair.second.def;
        entry.name=intern(def->name,def->name_length,true); entry.def=def;entry.on_modify=def->on_modify;entry.displayer=def->displayer;
        entry.mh_arg1=def->mh_arg1;entry.mh_arg2=def->mh_arg2;entry.mh_arg3=def->mh_arg3;
        entry.module_number=pair.second.module;entry.modifiable=def->modifiable;entry.orig_modifiable=def->modifiable;
        entry.value=string_new(def->value,def->value_length);
        if(entry.on_modify&&entry.on_modify(&entry,entry.value,entry.mh_arg1,entry.mh_arg2,entry.mh_arg3,ZEND_INI_STAGE_ACTIVATE)!=SUCCESS) return -1;
        tls.ini[pair.first]=std::move(value);
    } return 0;
}
void clear_ini() {for(auto &p:tls.ini){string_release(p.second->entry.value);string_release(p.second->entry.orig_value);}tls.ini.clear();}
bool value_in(const all_php_value &arg,zval *dest) {
    switch(arg.type) {
        case IS_NULL:ZVAL_NULL(dest);return true;
        case IS_FALSE:ZVAL_FALSE(dest);return true;
        case IS_TRUE:ZVAL_TRUE(dest);return true;
        case IS_LONG:ZVAL_LONG(dest,arg.integer);return true;
        case IS_DOUBLE:ZVAL_DOUBLE(dest,arg.real);return true;
        case IS_STRING:ZVAL_STR(dest,string_new(reinterpret_cast<const char*>(arg.bytes),arg.length));return Z_STR_P(dest)!=nullptr;
        case IS_ARRAY: {if(arg.length||arg.bytes||arg.flags){error("ALLNativeUnsupported","Only a documented empty-array argument is supported");return false;}auto *a=static_cast<zend_array*>(allocate(sizeof(zend_array),true)); std::memset(a,0,sizeof(*a));GC_SET_REFCOUNT(a,1);GC_TYPE_INFO(a)=GC_ARRAY;ZVAL_ARR(dest,a);return true;}
        default:error("ALLNativeUnsupported","Unsupported native argument kind");return false;
    }
}
bool value_out(const zval *value,all_php_value *dest) {
    std::memset(dest,0,sizeof(*dest));dest->type=Z_TYPE_P(value);
    switch(Z_TYPE_P(value)) {
        case IS_UNDEF:dest->type=IS_NULL;return true;case IS_NULL:case IS_FALSE:case IS_TRUE:return true;
        case IS_LONG:dest->integer=Z_LVAL_P(value);return true;
        case IS_DOUBLE:dest->real=Z_DVAL_P(value);return true;
        case IS_STRING:dest->bytes=reinterpret_cast<const unsigned char*>(ZSTR_VAL(Z_STR_P(value)));dest->length=ZSTR_LEN(Z_STR_P(value));return true;
        default:error("ALLNativeUnsupported","Unsupported native return kind");return false;
    }
}
void object_free_storage(zend_object *object) {
    hit("ALL.standard.free_obj");for(int i=0;i<object->ce->default_properties_count;++i)destroy(object->properties_table+i);
    if(object->properties){hash_destroy_storage(object->properties);std::free(object->properties);object->properties=nullptr;}
}
void object_destructor(zend_object *object) {hit("ALL.standard.dtor_obj");if(object->ce->destructor)error("ALLNativeUnsupported","Native user destructor callbacks are not implemented");}
zend_string *object_class_name(const zend_object *object) {return object->ce->name;}
zend_function *object_get_method(zend_object **object,zend_string *name,const zval *key) {
    auto cls=runtime.classes.find(lower(ZSTR_VAL((*object)->ce->name)));if(cls==runtime.classes.end()){error("Error","Unregistered native object class");return nullptr;}
    auto fn=cls->second->methods.find(lower(std::string(ZSTR_VAL(name),ZSTR_LEN(name))));if(fn==cls->second->methods.end()){error("Error","Unknown native object method");return nullptr;}return &fn->second->raw;
}
zend_function *object_constructor(zend_object *object) {return object->ce->constructor;}
HashTable *object_gc(zend_object *object,zval **table,int *count) {*table=object->properties_table;*count=object->ce->default_properties_count;return object->properties;}
zval *unsupported_read_property(zend_object*,zend_string*,int,void**,zval *rv){error("ALLNativeUnsupported","Native object property reads are not implemented");ZVAL_UNDEF(rv);return rv;}
zval *unsupported_write_property(zend_object*,zend_string*,zval*,void**){error("ALLNativeUnsupported","Native object property writes are not implemented");return nullptr;}
zval *unsupported_read_dimension(zend_object*,zval*,int,zval *rv){error("ALLNativeUnsupported","Native object dimensions are not implemented");ZVAL_UNDEF(rv);return rv;}
void unsupported_write_dimension(zend_object*,zval*,zval*){error("ALLNativeUnsupported","Native object dimensions are not implemented");}
zval *unsupported_property_pointer(zend_object*,zend_string*,int,void**){error("ALLNativeUnsupported","Native property pointer access is not implemented");return nullptr;}
int unsupported_has_property(zend_object*,zend_string*,int,void**){error("ALLNativeUnsupported","Native property existence execution is not implemented");return 0;}
void unsupported_unset_property(zend_object*,zend_string*,void**){error("ALLNativeUnsupported","Native property unsetting is not implemented");}
int unsupported_has_dimension(zend_object*,zval*,int){error("ALLNativeUnsupported","Native object dimensions are not implemented");return 0;}
void unsupported_unset_dimension(zend_object*,zval*){error("ALLNativeUnsupported","Native object dimensions are not implemented");}
HashTable *unsupported_properties(zend_object*){error("ALLNativeUnsupported","Native object property enumeration is not implemented");return nullptr;}
zend_result unsupported_cast(zend_object*,zval*,int){error("ALLNativeUnsupported","Native object casts are not implemented");return FAILURE;}
int unsupported_compare(zval *a,zval *b){if(Z_OBJ_P(a)==Z_OBJ_P(b))return 0;error("ALLNativeUnsupported","Native object structural comparison is not implemented");return ZEND_UNCOMPARABLE;}
zend_object_handlers make_handlers(){zend_object_handlers h{};h.free_obj=&object_free_storage;h.dtor_obj=&object_destructor;h.read_property=&unsupported_read_property;h.write_property=&unsupported_write_property;h.read_dimension=&unsupported_read_dimension;h.write_dimension=&unsupported_write_dimension;h.get_property_ptr_ptr=&unsupported_property_pointer;h.has_property=&unsupported_has_property;h.unset_property=&unsupported_unset_property;h.has_dimension=&unsupported_has_dimension;h.unset_dimension=&unsupported_unset_dimension;h.get_properties=&unsupported_properties;h.get_method=&object_get_method;h.get_constructor=&object_constructor;h.get_class_name=&object_class_name;h.cast_object=&unsupported_cast;h.get_gc=&object_gc;h.compare=&unsupported_compare;return h;}
zend_object *object_new(Class *cls){size_t bytes=offsetof(zend_object,properties_table)+sizeof(zval)*std::max(1,cls->raw.default_properties_count);auto *o=static_cast<zend_object*>(std::calloc(1,bytes));GC_SET_REFCOUNT(o,1);GC_TYPE_INFO(o)=GC_OBJECT;o->ce=&cls->raw;o->handlers=&std_object_handlers;for(int i=0;i<cls->raw.default_properties_count;++i)copy_value(o->properties_table+i,cls->raw.default_properties_table+i);return o;}
void object_destroy(zend_object *object){if(object){object->handlers->dtor_obj(object);object->handlers->free_obj(object);std::free(object);}}
}

extern "C" {
ZEND_API void zend_argument_value_error(uint32_t number,const char *message_format,...) {
    hit("zend_argument_value_error");if(!tls.error.empty())return;
    va_list arguments;va_start(arguments,message_format);std::string message=format(message_format,arguments);va_end(arguments);
    std::string name;
    if(tls.current&&tls.current->func&&number>0&&number<=tls.current->func->common.num_args){
        auto *info=tls.current->func->internal_function.arg_info;if(info&&info[number-1].name)name=info[number-1].name;
    }
    error("ValueError",callable()+"(): Argument #"+std::to_string(number)+(name.empty()?"":" ($"+name+")")+" "+message);
}
ZEND_API void zend_argument_must_not_be_empty_error(uint32_t number) {
    hit("zend_argument_must_not_be_empty_error");zend_argument_value_error(number,"must not be empty");
}
CWD_API char *virtual_getcwd(char *buffer,size_t size) {
    hit("virtual_getcwd");if(!tls.active||tls.cwd_bytes.empty()){errno=ENOENT;return nullptr;}
    size_t length=tls.cwd_bytes.size();
    if(!buffer){buffer=static_cast<char*>(allocate(length+1,true));if(!buffer){errno=ENOMEM;return nullptr;}}
    else if(size<=length){errno=ERANGE;return nullptr;}
    std::memcpy(buffer,tls.cwd_bytes.data(),length);buffer[length]=0;return buffer;
}
CWD_API char *virtual_realpath(const char *path,char *resolved) {
    hit("virtual_realpath");if(!path||!resolved){errno=EINVAL;return nullptr;}
    std::wstring canonical;std::string bytes;if(!cwd_resolve(path,std::strlen(path),canonical,bytes))return nullptr;
    std::memcpy(resolved,bytes.data(),bytes.size());resolved[bytes.size()]=0;return resolved;
}
int all_php_virtual_cwd_set(const unsigned char *path,size_t length) {
    clear_error();if(!callback_owner_valid())return -1;
    if(!tls.active||!path){error("Error","Virtual directory requires an active request and a path");return -1;}
    std::wstring canonical;std::string bytes;
    if(!cwd_resolve(reinterpret_cast<const char*>(path),length,canonical,bytes)){error("Error","Virtual directory resolution failed, errno "+std::to_string(errno));return -1;}
    DWORD attributes=GetFileAttributesW(canonical.c_str());
    if(attributes==INVALID_FILE_ATTRIBUTES||!(attributes&FILE_ATTRIBUTE_DIRECTORY)){errno=ENOTDIR;error("Error","Virtual directory is not a directory");return -1;}
    tls.cwd_wide=std::move(canonical);tls.cwd_bytes=std::move(bytes);
    if(tls.cwd_wide.size()>1&&tls.cwd_wide[1]==L':'){wchar_t drive=tls.cwd_wide[0];if(drive>=L'a'&&drive<=L'z')drive-=32;tls.drive_cwds[drive]=tls.cwd_wide;}
    return 0;
}
const char *all_php_virtual_cwd_get(size_t *length) {
    if(length)*length=0;if(!callback_owner_valid()||!tls.active)return nullptr;
    if(length)*length=tls.cwd_bytes.size();return tls.cwd_bytes.data();
}

ZEND_API const zend_object_handlers std_object_handlers=make_handlers();
ZEND_API zend_string_init_interned_func_t zend_string_init_interned=&intern;
TSRM_API void *tsrm_get_ls_cache(void) {hit("tsrm_get_ls_cache");return &tls.storage;}
ZEND_API void *ZEND_FASTCALL _emalloc(size_t size) {hit("_emalloc@@8");return allocate(size,true);}
ZEND_API void ZEND_FASTCALL _efree(void *ptr) {hit("_efree@@8");release(ptr);}
ZEND_API void *__zend_malloc(size_t size) {hit("__zend_malloc");return allocate(size,false);}
PHPAPI size_t php_printf(const char *fmt,...) {hit("php_printf");va_list ap;va_start(ap,fmt);auto s=format(fmt,ap);va_end(ap);tls.output+=s;return s.size();}
ZEND_API zend_string *zend_strpprintf(size_t max_len,const char *fmt,...) {hit("zend_strpprintf");va_list ap;va_start(ap,fmt);auto s=format(fmt,ap);va_end(ap);if(max_len&&s.size()>max_len)s.resize(max_len);return string_new(s.data(),s.size());}
ZEND_API void ZEND_FASTCALL zend_wrong_parameters_none_error(void) {hit("zend_wrong_parameters_none_error@@0");auto n=tls.current?ZEND_CALL_NUM_ARGS(tls.current):0;error("ArgumentCountError",callable()+"() expects exactly 0 arguments, "+std::to_string(n)+" given");}
ZEND_API void ZEND_FASTCALL zend_wrong_parameters_count_error(uint32_t min_args,uint32_t max_args) {hit("zend_wrong_parameters_count_error@@16");auto n=tls.current?ZEND_CALL_NUM_ARGS(tls.current):0;std::string expectation=min_args==max_args?"exactly ":(n<min_args?"at least ":"at most ");auto limit=n<min_args?min_args:max_args;error("ArgumentCountError",callable()+"() expects "+expectation+std::to_string(limit)+" argument"+(limit==1?"":"s")+", "+std::to_string(n)+" given");}
ZEND_API void ZEND_FASTCALL zend_wrong_parameter_type_error(uint32_t num,zend_expected_type expected,zval *arg) {hit("zend_wrong_parameter_type_error@@24");if(!tls.error.empty())return;if((expected==Z_EXPECTED_PATH||expected==Z_EXPECTED_PATH_OR_NULL)&&Z_TYPE_P(arg)==IS_STRING){zend_argument_value_error(num,"must not contain any null bytes");return;}std::string target=expected==Z_EXPECTED_LONG?"int":(expected==Z_EXPECTED_STRING||expected==Z_EXPECTED_PATH)?"string":(expected==Z_EXPECTED_STRING_OR_NULL||expected==Z_EXPECTED_PATH_OR_NULL)?"?string":"unsupported type";error("TypeError",callable()+"(): Argument #"+std::to_string(num)+" ($"+argument_name(num)+") must be of type "+target+", "+type_name(arg)+" given");}
ZEND_API void ZEND_FASTCALL zend_wrong_parameter_error(int code,uint32_t num,char *name,zend_expected_type expected,zval *arg) {hit("zend_wrong_parameter_error@@40");if(!tls.error.empty())return;if(code==ZPP_ERROR_WRONG_ARG) zend_wrong_parameter_type_error(num,expected,arg);else error("ALLNativeUnsupported","Unsupported ZPP error code "+std::to_string(code));}
ZEND_API bool ZEND_FASTCALL zend_parse_arg_long_slow(const zval *arg,zend_long *dest,uint32_t num) {
    hit("zend_parse_arg_long_slow@@24");if(tls.strict)return false;
    if(Z_TYPE_P(arg)==IS_NULL){null_deprecation(num,"int");*dest=0;return true;}
    if(Z_TYPE_P(arg)==IS_TRUE||Z_TYPE_P(arg)==IS_FALSE){*dest=Z_TYPE_P(arg)==IS_TRUE;return true;}
    if(Z_TYPE_P(arg)==IS_DOUBLE&&std::isfinite(Z_DVAL_P(arg))&&Z_DVAL_P(arg)>=-9223372036854775808.0&&Z_DVAL_P(arg)<9223372036854775808.0) {
        *dest=static_cast<zend_long>(Z_DVAL_P(arg));if(static_cast<double>(*dest)!=Z_DVAL_P(arg))diagnostic(E_DEPRECATED,"Implicit conversion from float "+float_text(Z_DVAL_P(arg))+" to int loses precision");return true;
    }
    if(Z_TYPE_P(arg)==IS_STRING) {std::string s(ZSTR_VAL(Z_STR_P(arg)),ZSTR_LEN(Z_STR_P(arg)));char *end=nullptr;errno=0;auto v=std::strtoll(s.c_str(),&end,10);if(end!=s.c_str()&&end==s.c_str()+s.size()&&errno==0){*dest=v;return true;}double d;if(numeric_double(s,&d)&&d>=-9223372036854775808.0&&d<9223372036854775808.0){*dest=static_cast<zend_long>(d);if(static_cast<double>(*dest)!=d)diagnostic(E_DEPRECATED,"Implicit conversion from float-string \""+s+"\" to int loses precision");return true;}}
    return false;
}
ZEND_API bool ZEND_FASTCALL zend_flf_parse_arg_long_slow(const zval *arg,zend_long *dest,uint32_t num) {hit("zend_flf_parse_arg_long_slow@@24");if(zend_parse_arg_long_slow(arg,dest,num))return true;if(tls.error.empty())zend_wrong_parameter_type_error(num,Z_EXPECTED_LONG,const_cast<zval*>(arg));return false;}
ZEND_API bool ZEND_FASTCALL zend_parse_arg_str_slow(zval *arg,zend_string **dest,uint32_t num) {
    hit("zend_parse_arg_str_slow@@24");if(tls.strict)return false;std::string s;
    if(Z_TYPE_P(arg)==IS_LONG)s=std::to_string(Z_LVAL_P(arg));
    else if(Z_TYPE_P(arg)==IS_TRUE)s="1";else if(Z_TYPE_P(arg)==IS_FALSE)s="";
    else if(Z_TYPE_P(arg)==IS_NULL){null_deprecation(num,"string");s="";}
    else if(Z_TYPE_P(arg)==IS_DOUBLE)s=float_text(Z_DVAL_P(arg));
    else return false;
    destroy(arg);ZVAL_STR(arg,string_new(s.data(),s.size()));*dest=Z_STR_P(arg);return true;
}
ZEND_API zend_result zend_register_functions(zend_class_entry *scope,const zend_function_entry *functions,HashTable *table,int type) {
    hit("zend_register_functions");if(!functions)return SUCCESS;
    if(scope){error("ALLNativeUnsupported","Dynamic scoped function registration unsupported");return FAILURE;}
    for(auto *e=functions;e->fname;++e){auto key=lower(e->fname);if(runtime.functions.count(key)){error("Error","Duplicate native function "+key);return FAILURE;}runtime.functions[key]=function_new(e,nullptr);}return SUCCESS;
}
ZEND_API zend_class_entry *zend_register_internal_class_with_flags(zend_class_entry *entry,zend_class_entry *parent,uint32_t flags) {
    hit("zend_register_internal_class_with_flags");std::string key=lower(ZSTR_VAL(entry->name));if(runtime.classes.count(key)){error("Error","Duplicate native class "+key);return nullptr;}
    auto cls=std::make_unique<Class>();std::memcpy(&cls->raw,entry,sizeof(*entry));cls->raw.type=ZEND_INTERNAL_CLASS;cls->raw.parent=parent;cls->raw.ce_flags|=flags;
    hash_initialize(&cls->raw.function_table,32);hash_initialize(&cls->raw.properties_info,32);
    cls->raw.default_properties_count=0;cls->raw.default_properties_table=nullptr;
    if(parent){auto it=runtime.classes.find(lower(ZSTR_VAL(parent->name)));if(it!=runtime.classes.end())cls->methods=it->second->methods;cls->raw.default_properties_count=parent->default_properties_count;if(parent->default_properties_count){cls->raw.default_properties_table=static_cast<zval*>(std::calloc(parent->default_properties_count,sizeof(zval)));for(int i=0;i<parent->default_properties_count;++i)copy_value(cls->raw.default_properties_table+i,parent->default_properties_table+i);}}
    auto *raw=&cls->raw;
    for(auto *e=entry->info.internal.builtin_functions;e&&e->fname;++e){auto fn=function_new(e,raw);cls->methods[lower(e->fname)]=fn.get();runtime.method_functions.push_back(std::move(fn));}
    for(auto &pair:cls->methods)hash_pointer(&raw->function_table,pair.first,&pair.second->raw);
    runtime.classes[key]=std::move(cls);return raw;
}
ZEND_API zend_property_info *zend_declare_typed_property(zend_class_entry *ce,zend_string *name,zval *property,int flags,zend_string *doc,zend_type type) {
    hit("zend_declare_typed_property");auto it=runtime.classes.find(lower(ZSTR_VAL(ce->name)));if(it==runtime.classes.end()){error("Error","Property class unregistered");return nullptr;}
    auto p=std::make_unique<Property>();p->raw.name=intern(ZSTR_VAL(name),ZSTR_LEN(name),true);p->raw.ce=ce;p->raw.flags=flags;p->raw.type=type;p->raw.doc_comment=doc;
    p->raw.offset=static_cast<uint32_t>(offsetof(zend_object,properties_table)+sizeof(zval)*ce->default_properties_count);
    copy_value(&p->initial,property);int index=ce->default_properties_count++;
    auto *values=static_cast<zval*>(std::realloc(ce->default_properties_table,sizeof(zval)*ce->default_properties_count));ce->default_properties_table=values;copy_value(values+index,property);
    auto *result=&p->raw;it->second->properties[std::string(ZSTR_VAL(name),ZSTR_LEN(name))]=std::move(p);hash_pointer(&ce->properties_info,std::string(ZSTR_VAL(name),ZSTR_LEN(name)),result);return result;
}
ZEND_API zend_constant *zend_register_long_constant(const char *name,size_t length,zend_long value,int flags,int module_number) {hit("zend_register_long_constant");auto p=std::make_unique<zend_constant>();ZVAL_LONG(&p->value,value);p->name=intern(name,length,true);auto *out=p.get();runtime.constants[std::string(name,length)]=std::move(p);return out;}
ZEND_API int OnUpdateLong(zend_ini_entry *entry,zend_string *value,void *offset,void *id,void *arg3,int stage) {hit("OnUpdateLong");void *p=ini_target(offset,id);if(!p)return FAILURE;char *end=nullptr;errno=0;auto number=std::strtoll(ZSTR_VAL(value),&end,10);if(errno||end!=ZSTR_VAL(value)+ZSTR_LEN(value))return FAILURE;*static_cast<zend_long*>(p)=number;return SUCCESS;}
ZEND_API int OnUpdateString(zend_ini_entry *entry,zend_string *value,void *offset,void *id,void *arg3,int stage) {hit("OnUpdateString");void *p=ini_target(offset,id);if(!p)return FAILURE;*static_cast<char**>(p)=ZSTR_VAL(value);return SUCCESS;}
ZEND_API zend_result zend_register_ini_entries_ex(const zend_ini_entry_def *defs,int number,int type) {hit("zend_register_ini_entries_ex");for(auto *d=defs;d&&d->name;++d){if(runtime.ini.count(d->name)){error("Error","Duplicate INI directive");return FAILURE;}runtime.ini[d->name]={d,number};runtime.ini_order.emplace_back(d->name);}return SUCCESS;}
ZEND_API zend_result zend_register_ini_entries(const zend_ini_entry_def *defs,int number) {hit("zend_register_ini_entries");return zend_register_ini_entries_ex(defs,number,MODULE_PERSISTENT);}
ZEND_API void zend_unregister_ini_entries_ex(int number,int type) {hit("zend_unregister_ini_entries_ex");for(auto it=runtime.ini.begin();it!=runtime.ini.end();)if(it->second.module==number)it=runtime.ini.erase(it);else ++it;runtime.ini_order.erase(std::remove_if(runtime.ini_order.begin(),runtime.ini_order.end(),[](const std::string &name){return runtime.ini.find(name)==runtime.ini.end();}),runtime.ini_order.end());}
ZEND_API void zend_unregister_ini_entries(int number) {hit("zend_unregister_ini_entries");zend_unregister_ini_entries_ex(number,MODULE_PERSISTENT);}
// Text-mode rules only. HTML/SAPI mode is not supplied by this profile.
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

int all_php_load_extension(const wchar_t *path) {
    clear_error();if(runtime.extension){error("ALLNativeUnsupported","Only one native module is supported by this candidate");return -1;}
    if(!path||!((path[0]&&path[1]==L':')||(path[0]==L'\\'&&path[1]==L'\\'))){error("Error","Extension path must be absolute");return -1;}
    runtime.extension=LoadLibraryExW(path,nullptr,LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR|LOAD_LIBRARY_SEARCH_SYSTEM32);
    if(!runtime.extension){error("Error","Extension load failed, Win32 error "+std::to_string(GetLastError()));return -1;}
    auto get=reinterpret_cast<zend_module_entry*(*)()>(GetProcAddress(runtime.extension,"get_module"));
    if(!get){error("Error","Native extension has no get_module");FreeLibrary(runtime.extension);runtime.extension=nullptr;return -1;}
    auto *m=get();if(m->size!=sizeof(zend_module_entry)||m->zend_api!=ZEND_MODULE_API_NO||!m->zts||m->zend_debug||std::strcmp(m->build_id,ZEND_MODULE_BUILD_ID)){
        error("Error","Native module API/build ID/layout mismatch");FreeLibrary(runtime.extension);runtime.extension=nullptr;return -1;}
    runtime.module=m;m->module_number=1;if(m->globals_id_ptr)*m->globals_id_ptr=1;
    if(attach_thread()!=0)return -1;
    if(zend_register_functions(nullptr,m->functions,nullptr,MODULE_PERSISTENT)!=SUCCESS)return -1;
    if(m->module_startup_func&&m->module_startup_func(MODULE_PERSISTENT,1)!=SUCCESS)return -1;
    ++runtime.minit;m->module_started=1;return tls.error.empty()?0:-1;
}
int all_php_request_start(void) {clear_error();if(!callback_owner_valid())return -1;if(!runtime.module||tls.active){error("Error","Native request cannot start");return -1;}if(attach_thread()!=0)return -1;if(!cwd_request_initialize()){cwd_request_clear();error("Error","Cannot initialize virtual directory");return -1;}tls.active=true;++tls.requests_started;if(apply_ini_defaults()!=0){clear_ini();cwd_request_clear();tls.active=false;return -1;}if(runtime.module->request_startup_func&&runtime.module->request_startup_func(MODULE_PERSISTENT,1)!=SUCCESS)return -1;++runtime.rinit;return 0;}
int all_php_request_end(void) {if(!callback_owner_valid())return -1;if(tls.diagnostic_callback){error("ALLNativeUnsupported","Clear callback lease before request teardown");return -1;}if(!tls.active){error("Error","No active native request");return -1;}if(runtime.module->request_shutdown_func&&runtime.module->request_shutdown_func(MODULE_PERSISTENT,1)!=SUCCESS)return -1;++runtime.rshutdown;destroy(&tls.last);clear_ini();cwd_request_clear();tls.active=false;++tls.requests_ended;return 0;}
int all_php_invoke(const char *scope,const char *name,const all_php_value *args,uint32_t count,int strict,all_php_value *result) {
    clear_error();if(!callback_owner_valid())return -1;if(!tls.active){error("Error","Native call outside request");return -1;}destroy(&tls.last);Function *fn=nullptr;Class *cls=nullptr;
    if(scope&&*scope){auto c=runtime.classes.find(lower(scope));if(c==runtime.classes.end()){error("Error","Unknown native class");return -1;}cls=c->second.get();auto f=cls->methods.find(lower(name));if(f!=cls->methods.end())fn=f->second;}
    else {auto f=runtime.functions.find(lower(name));if(f!=runtime.functions.end())fn=f->second.get();}
    if(!fn){error("Error","Unknown native callable");return -1;}
    std::vector<unsigned char> storage(sizeof(zend_execute_data)+static_cast<size_t>(count)*sizeof(zval),0);auto *frame=reinterpret_cast<zend_execute_data*>(storage.data());
    frame->func=&fn->raw;frame->return_value=&tls.last;frame->prev_execute_data=tls.current;ZEND_CALL_NUM_ARGS(frame)=count;
    zend_object *object=nullptr;if(cls){object=object_new(cls);ZVAL_OBJ(&frame->This,object);ZEND_CALL_NUM_ARGS(frame)=count;}
    for(uint32_t i=0;i<count;++i)if(!value_in(args[i],ZEND_CALL_ARG(frame,i+1))){for(uint32_t j=0;j<i;++j)destroy(ZEND_CALL_ARG(frame,j+1));object_destroy(object);return -1;}
    auto *previous=tls.current;tls.current=frame;tls.strict=strict!=0;ZVAL_NULL(&tls.last);++runtime.invocations;
    bool aborted=false;++tls.owned_invocation_depth;try{fn->raw.internal_function.handler(frame,&tls.last);}catch(const CallbackAbort&){aborted=true;++runtime.callback_aborts;}catch(...){error("ALLNativeUnsupported","Unexpected native C++ exception in callback prototype");}--tls.owned_invocation_depth;
    tls.current=previous;tls.strict=false;for(uint32_t i=0;i<count;++i)destroy(ZEND_CALL_ARG(frame,i+1));object_destroy(object);
    if(aborted)return 2;if(!tls.error.empty())return 1;return value_out(&tls.last,result)?0:-1;
}
int all_php_invoke_frameless(const char *name,const all_php_value *arg,int strict,all_php_value *result) {
    clear_error();if(!callback_owner_valid())return -1;if(!tls.active){error("Error","Frameless call outside request");return -1;}auto it=runtime.functions.find(lower(name));if(it==runtime.functions.end()||!it->second->entry->frameless_function_infos){error("ALLNativeUnsupported","No registered frameless native callable");return -1;}
    auto *info=it->second->entry->frameless_function_infos;if(info->num_args!=1){error("ALLNativeUnsupported","Frameless arity unsupported");return -1;}
    zend_execute_data frame{};frame.func=&it->second->raw;ZEND_CALL_NUM_ARGS(&frame)=1;zval value{};if(!value_in(*arg,&value))return -1;destroy(&tls.last);ZVAL_NULL(&tls.last);
    tls.current=&frame;tls.strict=strict!=0;using Fast=void(ZEND_FASTCALL*)(zval*,zval*);bool aborted=false;++tls.owned_invocation_depth;try{reinterpret_cast<Fast>(info->handler)(&tls.last,&value);}catch(const CallbackAbort&){aborted=true;++runtime.callback_aborts;}catch(...){error("ALLNativeUnsupported","Unexpected native C++ exception in callback prototype");}--tls.owned_invocation_depth;tls.current=nullptr;tls.strict=false;destroy(&value);++runtime.invocations;
    if(aborted)return 2;if(!tls.error.empty())return 1;return value_out(&tls.last,result)?0:-1;
}
const char *all_php_error_class(void){return tls.error_class.c_str();}
const char *all_php_error_message(void){return tls.error.c_str();}
const char *all_php_error_message_bytes(size_t *length){if(length)*length=tls.error.size();return tls.error.data();}
const char *all_php_output(size_t *length){*length=tls.output.size();return tls.output.data();}
const char *all_php_diagnostics(size_t *length){*length=tls.diagnostics.size();return tls.diagnostics.data();}
void all_php_clear_output(void){tls.output.clear();tls.diagnostics.clear();tls.diagnostic_events.clear();}
const char *all_php_ini_get(const char *name){auto i=tls.ini.find(name);return i==tls.ini.end()?nullptr:ZSTR_VAL(i->second->entry.value);}
int all_php_ini_set(const char *name,const char *text){clear_error();auto i=tls.ini.find(name);if(i==tls.ini.end()){error("Error","Unknown INI directive");return -1;}auto &e=i->second->entry;auto *s=string_new(text,std::strlen(text));if(e.on_modify&&e.on_modify(&e,s,e.mh_arg1,e.mh_arg2,e.mh_arg3,ZEND_INI_STAGE_RUNTIME)!=SUCCESS){string_release(s);error("ValueError","INI callback rejected value");return -1;}if(!e.modified){e.orig_value=e.value;if(e.orig_value&&!(GC_FLAGS(e.orig_value)&IS_STR_INTERNED))++e.orig_value->gc.refcount;e.orig_modifiable=e.modifiable;}string_release(e.value);e.value=s;e.modified=1;return 0;}
int all_php_constant_get(const char *name,all_php_value *result){auto p=runtime.constants.find(name);if(p==runtime.constants.end())return -1;return value_out(&p->second->value,result)?0:-1;}
const char *all_php_class_parent(const char *name){auto p=runtime.classes.find(lower(name));if(p==runtime.classes.end())return nullptr;return p->second->raw.parent?ZSTR_VAL(p->second->raw.parent->name):"";}
int all_php_class_property(const char *name,const char *property,uint32_t *flags,uint32_t *mask,int *initialized){auto p=runtime.classes.find(lower(name));if(p==runtime.classes.end())return -1;Class *c=p->second.get();while(c){auto prop=c->properties.find(property);if(prop!=c->properties.end()){*flags=prop->second->raw.flags;*mask=ZEND_TYPE_FULL_MASK(prop->second->raw.type);*initialized=Z_TYPE(prop->second->initial)!=IS_UNDEF;return 0;}if(!c->raw.parent)break;c=runtime.classes[lower(ZSTR_VAL(c->raw.parent->name))].get();}return -1;}
const wchar_t *all_php_core_path(void){static wchar_t path[32768];HMODULE m=nullptr;GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS|GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,reinterpret_cast<LPCWSTR>(&all_php_core_path),&m);GetModuleFileNameW(m,path,32768);return path;}
const char *all_php_stats_json(void){std::lock_guard<std::recursive_mutex> lock(runtime.mutex);std::ostringstream s;s<<"{\"minit\":"<<runtime.minit<<",\"mshutdown\":"<<runtime.mshutdown<<",\"rinit\":"<<runtime.rinit<<",\"rshutdown\":"<<runtime.rshutdown<<",\"thread_requests_started\":"<<tls.requests_started<<",\"thread_requests_ended\":"<<tls.requests_ended<<",\"thread_global_ctors\":"<<tls.global_ctors<<",\"tls_contexts_created\":"<<runtime.tls_created<<",\"tls_contexts_destroyed\":"<<runtime.tls_destroyed<<",\"native_invocations\":"<<runtime.invocations<<",\"registered_functions\":"<<runtime.functions.size()<<",\"registered_classes\":"<<runtime.classes.size()<<",\"request_allocations_live\":"<<runtime.request_allocations.size()<<",\"api_calls\":{";bool first=true;for(auto &p:runtime.calls){if(!first)s<<',';first=false;s<<'\"'<<p.first<<"\":"<<p.second;}s<<"}}";tls.stats=s.str();return tls.stats.c_str();}
int all_php_module_info(void){
    if(!tls.active||!runtime.module)return -1;
    auto *module=runtime.module;
    if(module->info_func||module->version){
        php_info_print_table_start();php_info_print_table_header(1,module->name);php_info_print_table_end();
        if(module->info_func)module->info_func(module);
        else{php_info_print_table_start();php_info_print_table_row(2,"Version",module->version);php_info_print_table_end();display_ini_entries(module);}
    }else{tls.output+=module->name;tls.output+='\n';}
    return 0;
}
int all_php_has_function(const char *name){if(!name)return 0;std::lock_guard<std::recursive_mutex> lock(runtime.mutex);return runtime.functions.count(lower(name))?1:0;}
const char *all_php_function_catalog_json(void){std::lock_guard<std::recursive_mutex> lock(runtime.mutex);std::ostringstream s;s<<'[';bool first=true;for(auto &p:runtime.functions){if(!first)s<<',';first=false;auto &f=p.second->raw.common;s<<"{\"name\":"<<json_string(p.second->name)<<",\"required_args\":"<<f.required_num_args<<",\"declared_args\":"<<f.num_args<<",\"flags\":"<<f.fn_flags<<",\"module\":"<<json_string(runtime.module?runtime.module->name:"")<<",\"supports_named_arguments\":false,\"parameters\":[";for(uint32_t i=0;i<f.num_args;++i){if(i)s<<',';auto *a=p.second->raw.internal_function.arg_info;s<<"{\"position\":"<<i+1<<",\"name\":"<<json_string(a&&a[i].name?a[i].name:"")<<'}';}s<<"]}";}s<<']';tls.stats=s.str();return tls.stats.c_str();}
const char *all_php_diagnostics_json(void){std::ostringstream s;s<<'[';bool first=true;for(auto &e:tls.diagnostic_events){if(!first)s<<',';first=false;s<<"{\"level\":"<<e.level<<",\"message\":"<<json_string(e.message)<<'}';}s<<']';tls.stats=s.str();return tls.stats.c_str();}
uint32_t all_php_diagnostic_count(void){return static_cast<uint32_t>(tls.diagnostic_events.size());}
const char *all_php_diagnostic_get(uint32_t index,int *level,size_t *length){if(index>=tls.diagnostic_events.size()){*level=0;*length=0;return nullptr;}auto &e=tls.diagnostic_events[index];*level=e.level;*length=e.message.size();return e.message.data();}
int all_php_diagnostic_delivered(uint32_t index){return index<tls.diagnostic_events.size()&&tls.diagnostic_events[index].delivered?1:0;}
uint64_t all_php_request_id(void){return tls.active?tls.requests_started:0;}
int all_php_set_callbacks(all_php_diagnostic_callback callback,all_php_output_callback output,void *user){clear_error();DWORD expected=0;if(!tls.active||!callback||!output||!runtime.callback_owner.compare_exchange_strong(expected,GetCurrentThreadId())){error("ALLNativeUnsupported","Callback lease requires an active exclusively owned request");return -1;}tls.diagnostic_callback=callback;tls.output_callback=output;tls.callback_user=user;tls.callback_thread=GetCurrentThreadId();tls.callback_request=tls.requests_started;return 0;}
int all_php_clear_callbacks(void){if(!runtime.callback_owner.load())return 0;if(!callback_owner_valid())return -1;tls.diagnostic_callback=nullptr;tls.output_callback=nullptr;tls.callback_user=nullptr;tls.callback_thread=0;tls.callback_request=0;runtime.callback_owner=0;return 0;}
const char *all_php_callback_stats_json(void){std::ostringstream s;s<<"{\"callbacks\":"<<runtime.callback_calls<<",\"aborts\":"<<runtime.callback_aborts<<",\"owner_rejections\":"<<runtime.callback_rejections<<",\"flushed_output_bytes\":"<<runtime.callback_output_bytes<<",\"contract_started\":"<<runtime.contract_started<<",\"contract_after_diagnostic\":"<<runtime.contract_after_diagnostic<<",\"callback_owner_thread\":"<<runtime.callback_owner<<'}';tls.stats=s.str();return tls.stats.c_str();}
int all_php_callback_contract_probe(void){clear_error();if(!callback_owner_valid()||!tls.active)return -1;all_php_clear_output();++runtime.contract_started;++tls.owned_invocation_depth;try{php_printf("N-before");diagnostic(E_WARNING,"ALL callback contract probe");++runtime.contract_after_diagnostic;php_printf("N-after");}catch(const CallbackAbort&){--tls.owned_invocation_depth;++runtime.callback_aborts;return 2;}--tls.owned_invocation_depth;return 0;}
const char *all_php_memory_probe(void){clear_error();if(!tls.active){error("Error","Memory probe outside native request");return nullptr;}size_t before;{std::lock_guard<std::recursive_mutex> lock(runtime.mutex);before=runtime.request_allocations.size();}auto *block=static_cast<unsigned char*>(_emalloc(32));std::memset(block,0x5a,32);std::atomic<bool> rejected{false};std::thread foreign([&](){_efree(block);rejected=tls.error_class=="ALLNativeUnsupported";});foreign.join();bool intact=block[0]==0x5a;_efree(block);zval one{},two{};ZVAL_STR(&one,string_new("shared",6));auto *s=Z_STR(one);copy_value(&two,&one);uint32_t retained=GC_REFCOUNT(s);destroy(&one);uint32_t surviving=GC_REFCOUNT(s);destroy(&two);size_t after;{std::lock_guard<std::recursive_mutex> lock(runtime.mutex);after=runtime.request_allocations.size();}std::ostringstream out;out<<"{\"before\":"<<before<<",\"after\":"<<after<<",\"retained_refcount\":"<<retained<<",\"remaining_refcount\":"<<surviving<<",\"cross_thread_free_rejected\":"<<(rejected?"true":"false")<<",\"owner_buffer_intact\":"<<(intact?"true":"false")<<"}";tls.stats=out.str();return tls.stats.c_str();}
int all_php_shutdown(void){clear_error();if(!callback_owner_valid())return -1;if(tls.active){error("Error","End native request before shutdown");return -1;}auto *m=runtime.module;if(!m)return 0;if(m->module_shutdown_func&&m->module_shutdown_func(MODULE_PERSISTENT,1)!=SUCCESS)return -1;++runtime.mshutdown;if(tls.attached){if(m->globals_dtor)m->globals_dtor(tls.slots[0]);std::free(tls.slots[0]);tls.slots[0]=nullptr;tls.attached=false;++runtime.tls_destroyed;}
    for(auto &p:runtime.classes){auto *ce=&p.second->raw;for(int i=0;i<ce->default_properties_count;++i)destroy(ce->default_properties_table+i);std::free(ce->default_properties_table);hash_destroy_storage(&ce->function_table);hash_destroy_storage(&ce->properties_info);}runtime.classes.clear();runtime.method_functions.clear();runtime.functions.clear();runtime.constants.clear();runtime.ini.clear();runtime.ini_order.clear();for(auto &p:runtime.interned)std::free(p.second);runtime.interned.clear();runtime.module=nullptr;FreeLibrary(runtime.extension);runtime.extension=nullptr;return 0;}
}
