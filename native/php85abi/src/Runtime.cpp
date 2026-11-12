// ALL-owned PHP 8.5.12 ABI candidate. Implemented from API contracts, not PHP .c files.
// The compatibility DLL is never linked to, or forwarded to, stock PHP.
#define NOMINMAX
#define ENABLE_INTSAFE_SIGNED_FUNCTIONS
#include <algorithm>
#include <atomic>
#include <cmath>
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
struct Diagnostic { int level; std::string message; };
struct ThreadState {
    void **storage = nullptr; // TSRM cache's first pointer is the resource table.
    void *slots[16]{};
    bool attached=false, active=false, strict=false;
    std::string error_class, error, output, diagnostics, stats, ini_result;
    std::vector<Diagnostic> diagnostic_events;
    std::map<std::string, std::unique_ptr<IniValue>> ini;
    zend_execute_data *current=nullptr;
    zval last{};
    uint64_t requests_started=0, requests_ended=0, global_ctors=0;
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
    std::map<std::string,std::unique_ptr<zend_constant>> constants;
    std::map<std::string,zend_string*> interned;
    std::map<void*,Allocation> request_allocations;
    std::map<std::string,uint64_t> calls;
    std::recursive_mutex mutex;
    std::atomic<uint64_t> minit{0},mshutdown{0},rinit{0},rshutdown{0},invocations{0},tls_created{0},tls_destroyed{0};
} runtime;
ThreadState::~ThreadState() {if(attached&&slots[0]){if(runtime.module&&runtime.module->globals_dtor)runtime.module->globals_dtor(slots[0]);std::free(slots[0]);++runtime.tls_destroyed;}}

void hit(const char *name) { std::lock_guard<std::recursive_mutex> lock(runtime.mutex); ++runtime.calls[name]; }
std::string lower(std::string value) { for(char &c:value) if(c>='A'&&c<='Z') c=static_cast<char>(c+32); return value; }
void error(const char *kind,const std::string &message) { tls.error_class=kind; tls.error=message; }
void clear_error() { tls.error_class.clear(); tls.error.clear(); }
std::string json_string(const std::string &value) {std::ostringstream s;s<<'\"';for(unsigned char c:value){if(c=='\\'||c=='\"')s<<'\\';if(c<32)s<<"\\u00"<<std::hex<<std::setw(2)<<std::setfill('0')<<static_cast<unsigned>(c)<<std::dec;else s<<c;}s<<'\"';return s.str();}
void diagnostic(int level,const std::string &message){tls.diagnostic_events.push_back({level,message});tls.diagnostics+=(level==E_DEPRECATED?"Deprecated: ":level==E_WARNING?"Warning: ":"Diagnostic: ")+message+"\n";}
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
        entry.name=intern(def->name,def->name_length,true); entry.def=def;entry.on_modify=def->on_modify;
        entry.mh_arg1=def->mh_arg1;entry.mh_arg2=def->mh_arg2;entry.mh_arg3=def->mh_arg3;
        entry.module_number=pair.second.module;entry.modifiable=def->modifiable;entry.orig_modifiable=def->modifiable;
        entry.value=string_new(def->value,def->value_length);
        if(entry.on_modify&&entry.on_modify(&entry,entry.value,entry.mh_arg1,entry.mh_arg2,entry.mh_arg3,ZEND_INI_STAGE_ACTIVATE)!=SUCCESS) return -1;
        tls.ini[pair.first]=std::move(value);
    } return 0;
}
void clear_ini() {for(auto &p:tls.ini) string_release(p.second->entry.value);tls.ini.clear();}
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
ZEND_API void ZEND_FASTCALL zend_wrong_parameter_type_error(uint32_t num,zend_expected_type expected,zval *arg) {hit("zend_wrong_parameter_type_error@@24");if(!tls.error.empty())return;std::string target=expected==Z_EXPECTED_LONG?"int":expected==Z_EXPECTED_STRING?"string":"unsupported type";error("TypeError",callable()+"(): Argument #"+std::to_string(num)+" ($"+argument_name(num)+") must be of type "+target+", "+type_name(arg)+" given");}
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
ZEND_API zend_result zend_register_ini_entries_ex(const zend_ini_entry_def *defs,int number,int type) {hit("zend_register_ini_entries_ex");for(auto *d=defs;d&&d->name;++d){if(runtime.ini.count(d->name)){error("Error","Duplicate INI directive");return FAILURE;}runtime.ini[d->name]={d,number};}return SUCCESS;}
ZEND_API zend_result zend_register_ini_entries(const zend_ini_entry_def *defs,int number) {hit("zend_register_ini_entries");return zend_register_ini_entries_ex(defs,number,MODULE_PERSISTENT);}
ZEND_API void zend_unregister_ini_entries_ex(int number,int type) {hit("zend_unregister_ini_entries_ex");for(auto it=runtime.ini.begin();it!=runtime.ini.end();)if(it->second.module==number)it=runtime.ini.erase(it);else ++it;}
ZEND_API void zend_unregister_ini_entries(int number) {hit("zend_unregister_ini_entries");zend_unregister_ini_entries_ex(number,MODULE_PERSISTENT);}
PHPAPI void php_info_print_table_start(void) {hit("php_info_print_table_start");tls.output+='\n';}
PHPAPI void php_info_print_table_end(void) {hit("php_info_print_table_end");tls.output+='\n';}
PHPAPI void php_info_print_table_row(int columns,...) {hit("php_info_print_table_row");va_list ap;va_start(ap,columns);for(int i=0;i<columns;++i){if(i)tls.output+=" => ";auto *s=va_arg(ap,const char*);if(s)tls.output+=s;}va_end(ap);tls.output+='\n';}
ZEND_API void display_ini_entries(zend_module_entry *module) {hit("display_ini_entries");for(auto &p:tls.ini)if(p.second->entry.module_number==module->module_number){tls.output+=p.first+" => "+ZSTR_VAL(p.second->entry.value)+" => "+p.second->entry.def->value+"\n";}}

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
int all_php_request_start(void) {clear_error();if(!runtime.module||tls.active){error("Error","Native request cannot start");return -1;}if(attach_thread()!=0)return -1;tls.active=true;++tls.requests_started;if(apply_ini_defaults()!=0){clear_ini();tls.active=false;return -1;}if(runtime.module->request_startup_func&&runtime.module->request_startup_func(MODULE_PERSISTENT,1)!=SUCCESS)return -1;++runtime.rinit;return 0;}
int all_php_request_end(void) {if(!tls.active){error("Error","No active native request");return -1;}if(runtime.module->request_shutdown_func&&runtime.module->request_shutdown_func(MODULE_PERSISTENT,1)!=SUCCESS)return -1;++runtime.rshutdown;destroy(&tls.last);clear_ini();tls.active=false;++tls.requests_ended;return 0;}
int all_php_invoke(const char *scope,const char *name,const all_php_value *args,uint32_t count,int strict,all_php_value *result) {
    clear_error();if(!tls.active){error("Error","Native call outside request");return -1;}destroy(&tls.last);Function *fn=nullptr;Class *cls=nullptr;
    if(scope&&*scope){auto c=runtime.classes.find(lower(scope));if(c==runtime.classes.end()){error("Error","Unknown native class");return -1;}cls=c->second.get();auto f=cls->methods.find(lower(name));if(f!=cls->methods.end())fn=f->second;}
    else {auto f=runtime.functions.find(lower(name));if(f!=runtime.functions.end())fn=f->second.get();}
    if(!fn){error("Error","Unknown native callable");return -1;}
    std::vector<unsigned char> storage(sizeof(zend_execute_data)+static_cast<size_t>(count)*sizeof(zval),0);auto *frame=reinterpret_cast<zend_execute_data*>(storage.data());
    frame->func=&fn->raw;frame->return_value=&tls.last;frame->prev_execute_data=tls.current;ZEND_CALL_NUM_ARGS(frame)=count;
    zend_object *object=nullptr;if(cls){object=object_new(cls);ZVAL_OBJ(&frame->This,object);ZEND_CALL_NUM_ARGS(frame)=count;}
    for(uint32_t i=0;i<count;++i)if(!value_in(args[i],ZEND_CALL_ARG(frame,i+1))){for(uint32_t j=0;j<i;++j)destroy(ZEND_CALL_ARG(frame,j+1));object_destroy(object);return -1;}
    auto *previous=tls.current;tls.current=frame;tls.strict=strict!=0;ZVAL_NULL(&tls.last);++runtime.invocations;
    fn->raw.internal_function.handler(frame,&tls.last);
    tls.current=previous;tls.strict=false;for(uint32_t i=0;i<count;++i)destroy(ZEND_CALL_ARG(frame,i+1));object_destroy(object);
    if(!tls.error.empty())return 1;return value_out(&tls.last,result)?0:-1;
}
int all_php_invoke_frameless(const char *name,const all_php_value *arg,int strict,all_php_value *result) {
    clear_error();if(!tls.active){error("Error","Frameless call outside request");return -1;}auto it=runtime.functions.find(lower(name));if(it==runtime.functions.end()||!it->second->entry->frameless_function_infos){error("ALLNativeUnsupported","No registered frameless native callable");return -1;}
    auto *info=it->second->entry->frameless_function_infos;if(info->num_args!=1){error("ALLNativeUnsupported","Frameless arity unsupported");return -1;}
    zend_execute_data frame{};frame.func=&it->second->raw;ZEND_CALL_NUM_ARGS(&frame)=1;zval value{};if(!value_in(*arg,&value))return -1;destroy(&tls.last);ZVAL_NULL(&tls.last);
    tls.current=&frame;tls.strict=strict!=0;using Fast=void(ZEND_FASTCALL*)(zval*,zval*);reinterpret_cast<Fast>(info->handler)(&tls.last,&value);tls.current=nullptr;tls.strict=false;destroy(&value);++runtime.invocations;
    if(!tls.error.empty())return 1;return value_out(&tls.last,result)?0:-1;
}
const char *all_php_error_class(void){return tls.error_class.c_str();}
const char *all_php_error_message(void){return tls.error.c_str();}
const char *all_php_output(size_t *length){*length=tls.output.size();return tls.output.data();}
const char *all_php_diagnostics(size_t *length){*length=tls.diagnostics.size();return tls.diagnostics.data();}
void all_php_clear_output(void){tls.output.clear();tls.diagnostics.clear();tls.diagnostic_events.clear();}
const char *all_php_ini_get(const char *name){auto i=tls.ini.find(name);return i==tls.ini.end()?nullptr:ZSTR_VAL(i->second->entry.value);}
int all_php_ini_set(const char *name,const char *text){clear_error();auto i=tls.ini.find(name);if(i==tls.ini.end()){error("Error","Unknown INI directive");return -1;}auto &e=i->second->entry;auto *s=string_new(text,std::strlen(text));if(e.on_modify&&e.on_modify(&e,s,e.mh_arg1,e.mh_arg2,e.mh_arg3,ZEND_INI_STAGE_RUNTIME)!=SUCCESS){string_release(s);error("ValueError","INI callback rejected value");return -1;}string_release(e.value);e.value=s;e.modified=1;return 0;}
int all_php_constant_get(const char *name,all_php_value *result){auto p=runtime.constants.find(name);if(p==runtime.constants.end())return -1;return value_out(&p->second->value,result)?0:-1;}
const char *all_php_class_parent(const char *name){auto p=runtime.classes.find(lower(name));if(p==runtime.classes.end())return nullptr;return p->second->raw.parent?ZSTR_VAL(p->second->raw.parent->name):"";}
int all_php_class_property(const char *name,const char *property,uint32_t *flags,uint32_t *mask,int *initialized){auto p=runtime.classes.find(lower(name));if(p==runtime.classes.end())return -1;Class *c=p->second.get();while(c){auto prop=c->properties.find(property);if(prop!=c->properties.end()){*flags=prop->second->raw.flags;*mask=ZEND_TYPE_FULL_MASK(prop->second->raw.type);*initialized=Z_TYPE(prop->second->initial)!=IS_UNDEF;return 0;}if(!c->raw.parent)break;c=runtime.classes[lower(ZSTR_VAL(c->raw.parent->name))].get();}return -1;}
const wchar_t *all_php_core_path(void){static wchar_t path[32768];HMODULE m=nullptr;GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS|GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,reinterpret_cast<LPCWSTR>(&all_php_core_path),&m);GetModuleFileNameW(m,path,32768);return path;}
const char *all_php_stats_json(void){std::lock_guard<std::recursive_mutex> lock(runtime.mutex);std::ostringstream s;s<<"{\"minit\":"<<runtime.minit<<",\"mshutdown\":"<<runtime.mshutdown<<",\"rinit\":"<<runtime.rinit<<",\"rshutdown\":"<<runtime.rshutdown<<",\"thread_requests_started\":"<<tls.requests_started<<",\"thread_requests_ended\":"<<tls.requests_ended<<",\"thread_global_ctors\":"<<tls.global_ctors<<",\"tls_contexts_created\":"<<runtime.tls_created<<",\"tls_contexts_destroyed\":"<<runtime.tls_destroyed<<",\"native_invocations\":"<<runtime.invocations<<",\"registered_functions\":"<<runtime.functions.size()<<",\"registered_classes\":"<<runtime.classes.size()<<",\"request_allocations_live\":"<<runtime.request_allocations.size()<<",\"api_calls\":{";bool first=true;for(auto &p:runtime.calls){if(!first)s<<',';first=false;s<<'\"'<<p.first<<"\":"<<p.second;}s<<"}}";tls.stats=s.str();return tls.stats.c_str();}
int all_php_module_info(void){if(!tls.active||!runtime.module||!runtime.module->info_func)return -1;runtime.module->info_func(runtime.module);return 0;}
int all_php_has_function(const char *name){if(!name)return 0;std::lock_guard<std::recursive_mutex> lock(runtime.mutex);return runtime.functions.count(lower(name))?1:0;}
const char *all_php_function_catalog_json(void){std::lock_guard<std::recursive_mutex> lock(runtime.mutex);std::ostringstream s;s<<'[';bool first=true;for(auto &p:runtime.functions){if(!first)s<<',';first=false;auto &f=p.second->raw.common;s<<"{\"name\":"<<json_string(p.second->name)<<",\"required_args\":"<<f.required_num_args<<",\"declared_args\":"<<f.num_args<<",\"flags\":"<<f.fn_flags<<",\"module\":"<<json_string(runtime.module?runtime.module->name:"")<<",\"supports_named_arguments\":false,\"parameters\":[";for(uint32_t i=0;i<f.num_args;++i){if(i)s<<',';auto *a=p.second->raw.internal_function.arg_info;s<<"{\"position\":"<<i+1<<",\"name\":"<<json_string(a&&a[i].name?a[i].name:"")<<'}';}s<<"]}";}s<<']';tls.stats=s.str();return tls.stats.c_str();}
const char *all_php_diagnostics_json(void){std::ostringstream s;s<<'[';bool first=true;for(auto &e:tls.diagnostic_events){if(!first)s<<',';first=false;s<<"{\"level\":"<<e.level<<",\"message\":"<<json_string(e.message)<<'}';}s<<']';tls.stats=s.str();return tls.stats.c_str();}
uint32_t all_php_diagnostic_count(void){return static_cast<uint32_t>(tls.diagnostic_events.size());}
const char *all_php_diagnostic_get(uint32_t index,int *level,size_t *length){if(index>=tls.diagnostic_events.size()){*level=0;*length=0;return nullptr;}auto &e=tls.diagnostic_events[index];*level=e.level;*length=e.message.size();return e.message.data();}
const char *all_php_memory_probe(void){clear_error();if(!tls.active){error("Error","Memory probe outside native request");return nullptr;}size_t before;{std::lock_guard<std::recursive_mutex> lock(runtime.mutex);before=runtime.request_allocations.size();}auto *block=static_cast<unsigned char*>(_emalloc(32));std::memset(block,0x5a,32);std::atomic<bool> rejected{false};std::thread foreign([&](){_efree(block);rejected=tls.error_class=="ALLNativeUnsupported";});foreign.join();bool intact=block[0]==0x5a;_efree(block);zval one{},two{};ZVAL_STR(&one,string_new("shared",6));auto *s=Z_STR(one);copy_value(&two,&one);uint32_t retained=GC_REFCOUNT(s);destroy(&one);uint32_t surviving=GC_REFCOUNT(s);destroy(&two);size_t after;{std::lock_guard<std::recursive_mutex> lock(runtime.mutex);after=runtime.request_allocations.size();}std::ostringstream out;out<<"{\"before\":"<<before<<",\"after\":"<<after<<",\"retained_refcount\":"<<retained<<",\"remaining_refcount\":"<<surviving<<",\"cross_thread_free_rejected\":"<<(rejected?"true":"false")<<",\"owner_buffer_intact\":"<<(intact?"true":"false")<<"}";tls.stats=out.str();return tls.stats.c_str();}
int all_php_shutdown(void){clear_error();if(tls.active){error("Error","End native request before shutdown");return -1;}auto *m=runtime.module;if(!m)return 0;if(m->module_shutdown_func&&m->module_shutdown_func(MODULE_PERSISTENT,1)!=SUCCESS)return -1;++runtime.mshutdown;if(tls.attached){if(m->globals_dtor)m->globals_dtor(tls.slots[0]);std::free(tls.slots[0]);tls.slots[0]=nullptr;tls.attached=false;++runtime.tls_destroyed;}
    for(auto &p:runtime.classes){auto *ce=&p.second->raw;for(int i=0;i<ce->default_properties_count;++i)destroy(ce->default_properties_table+i);std::free(ce->default_properties_table);hash_destroy_storage(&ce->function_table);hash_destroy_storage(&ce->properties_info);}runtime.classes.clear();runtime.method_functions.clear();runtime.functions.clear();runtime.constants.clear();runtime.ini.clear();for(auto &p:runtime.interned)std::free(p.second);runtime.interned.clear();runtime.module=nullptr;FreeLibrary(runtime.extension);runtime.extension=nullptr;return 0;}
}
