"""Source-grounded labels for the static inventory; no binary execution."""
from pathlib import Path
import argparse
import csv
import hashlib
import json
import re
import zipfile

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]

NOTES={
 "OnUpdateLong":"Parses complete decimal strings and stores through one attached TLS resource; not the complete INI lifecycle/modifiability contract.",
 "OnUpdateString":"Stores an interior zend_string pointer through one TLS resource; lifetime depends on retained IniValue.",
 "__zend_malloc":"Real malloc allocation, persistent/non-request path; not a complete Zend MM or ownership registry.",
 "_efree@@8":"Real free with tracked cross-thread refusal; untracked pointers are freed too, no complete double-free/request-generation policy.",
 "_emalloc@@8":"Real request-tagged malloc; size/thread/request recorded, no complete Zend MM or GC.",
 "display_ini_entries":"Real CLI-like output, but missing INI table heading and ignores display callbacks; observed output difference.",
 "php_info_print_table_end":"Writes a newline unconditionally; pinned PHP text-mode table_end writes nothing. Not a no-op stub, but a semantic mismatch.",
 "php_info_print_table_row":"Joins C strings using => and newline; only a narrow text-mode subset, no HTML/empty-cell parity claim.",
 "php_info_print_table_start":"Writes newline; selected text-mode behavior, no SAPI HTML mode.",
 "php_printf":"Formats bytes with CRT vsnprintf and appends native output; not full PHP formatter/locale/SAPI parity.",
 "std_object_handlers":"Actual table with selected methods/free/get_gc; property/dimension/cast/enumeration routes explicitly reject, several handler slots remain zero.",
 "tsrm_get_ls_cache":"Actual TLS cache pointer backed by fixed slots[16], one module uses slot0/id1; not full TSRM globals allocation.",
 "zend_declare_typed_property":"Registers metadata/default cells and offsets; actual property reads/writes/type/visibility/hooks are not implemented.",
 "zend_flf_parse_arg_long_slow@@24":"Delegates to selected long coercion and emits type error; narrow frameless parameter profile.",
 "zend_parse_arg_long_slow@@24":"Selected null/bool/finite double/numeric-string coercion and deprecations; not all numeric/locale/overflow cases certified.",
 "zend_parse_arg_str_slow@@24":"Selected scalar coercion to owned zend_string; objects/arrays are not converted here.",
 "zend_register_functions":"Real global function entries; dynamic scoped registration explicitly fails, supplied target table/type not fully modeled.",
 "zend_register_ini_entries":"Wrapper for actual INI definition registry; same narrow semantics as _ex.",
 "zend_register_ini_entries_ex":"Real single-module INI registry; modifiability/stages/full global state remain incomplete.",
 "zend_register_internal_class_with_flags":"Registers class/method/default-property metadata and fixed-capacity tables; no full inheritance/magic/allocator/object execution contract.",
 "zend_register_long_constant":"Real long constant registry; ignores flags/module ownership semantics and only one scalar kind.",
 "zend_string_init_interned":"Actual exported function pointer to owned intern table with byte keys; does not model every persistence/request flag.",
 "zend_strpprintf":"Real CRT formatted owned string; max_len truncation and PHP-specific formatter details not fully certified.",
 "zend_unregister_ini_entries":"Wrapper for removal from registry; no complete deactivation restoration protocol.",
 "zend_unregister_ini_entries_ex":"Removes matching module definitions; callback-stage/type semantics remain limited.",
 "zend_wrong_parameter_error@@40":"Handles ZPP_ERROR_WRONG_ARG; other codes explicitly unsupported.",
 "zend_wrong_parameter_type_error@@24":"Builds actual TypeError for expected int/string; other expected types use unsupported-type text.",
 "zend_wrong_parameters_count_error@@16":"Actual selected ArgumentCountError formatting using current native frame.",
 "zend_wrong_parameters_none_error@@0":"Actual selected zero-arity ArgumentCountError formatting.",
}
FEATURES=[
 ("scalar_and_bytes", "IMPLEMENTED_LIMITED", ["value_in","value_out","string_new"], "Null/bool/int64/double/length-bearing byte strings cross the bridge; no retry/fallback. Existing selected evidence remains separate."),
 ("populated_arrays", "EXPLICIT_UNSUPPORTED", ["value_in","value_out"], "Input permits only a zeroed empty array; populated/flagged arrays and all array returns reject."),
 ("array_storage", "METADATA_ONLY_PARTIAL", ["hash_initialize","hash_pointer","hash_destroy_storage"], "Only fixed-capacity class metadata buckets are built. No exported general HashTable operations, nested zval destruction or COW."),
 ("references", "MISSING_IMPLEMENTATION", ["copy_value","destroy"], "No zend_reference construction, alias graph/writeback or ref-source/type semantics; copy_value only retains strings."),
 ("object_values", "EXPLICIT_UNSUPPORTED_AND_PARTIAL_INTERNAL_OBJECT", ["value_out","object_new","object_destroy"], "Objects cannot cross the value boundary; scoped native call constructs an ephemeral own object, ignoring create_object and general object-store identity."),
 ("object_properties", "EXPLICIT_UNSUPPORTED", ["unsupported_read_property","unsupported_write_property","unsupported_properties","unsupported_property_pointer"], "Read/write/existence/unset/enumeration/property pointers and dimensions refuse execution."),
 ("object_destructors", "EXPLICIT_UNSUPPORTED", ["object_destructor"], "User destructor callbacks are rejected; not a complete destructor/free/custom-offset protocol."),
 ("resources", "MISSING_IMPLEMENTATION", ["value_in","value_out","destroy"], "No resource registry/type/destructor/persistent resource handling or managed proxy; unsupported tags reject."),
 ("ownership", "PARTIAL_WITH_UNSAFE_TO_ENABLE_GENERAL_VALUES", ["copy_value","destroy","release"], "Strings retain/release; arrays/objects shallow copy and are freed without general recursive/refcount semantics. Do not open new tags before this changes."),
 ("gc", "UNASSIGNED_OR_PARTIAL_HANDLERS_NOT_COLLECTOR", ["object_gc","make_handlers"], "get_gc only exposes roots; no cycle collector/object store or general persistent/request heap.") ,
 ("lifecycle", "IMPLEMENTED_SINGLE_MODULE_WITH_ROLLBACK_GAPS", ["all_php_load_extension","all_php_request_start","all_php_request_end","all_php_shutdown"], "One module, selected MINIT/GINIT/RINIT/RSHUTDOWN/MSHUTDOWN/GSHUTDOWN; failed startup rollback and foreign attached-thread unload need implementation."),
 ("callbacks", "IMPLEMENTED_RESTRICTED_CALLBACK_PROFILE", ["callback_owner_valid","all_php_set_callbacks"], "Callback core only: synchronous owned invocation, same request/thread, abort captured locally; arbitrary native callables/async/lifecycle callbacks absent."),
 ("error_message_length", "EXISTING_CSTRING_LIMIT", ["all_php_error_message"], "std::string is returned via c_str with no length; embedded-NUL suffix is inaccessible at existing API."),
 ("module_info", "OBSERVED_FORMAT_DIFFERENCE", ["all_php_module_info","display_ini_entries","php_info_print_table_end"], "Existing output lacks module/INI headings; table_end itself also differs from pinned text-mode contract."),
]


def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def save(path,value):path.write_text(json.dumps(value,indent=2)+"\n",encoding="utf-8")


def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--inventory',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
 out=a.output.resolve();assert not out.exists();out.mkdir(parents=True)
 inventory=json.loads(a.inventory.read_text(encoding='utf-8-sig'))
 sources={mode:ROOT/('native/'+folder+'/src/Runtime.cpp')for mode,folder in [('original','php85abi'),('callback','php85abi-callback')]}
 lines={mode:path.read_text(encoding='utf-8-sig').splitlines()for mode,path in sources.items()}
 def evidence(mode,name,public=False):
  base=name.split('@@',1)[0];found=[]
  for n,line in enumerate(lines[mode],1):
   if re.search(r'\b'+re.escape(base)+r'\s*(?:\(|=)',line) and ('{'in line or (public and re.search(r'\b'+re.escape(base)+r'\s*=',line))) and not line.lstrip().startswith('//'):
    if public and not (line.startswith(('ZEND_API ','PHPAPI ','TSRM_API '))or re.match(r'^(?:int|void|const |uint\d+_t)',line)) :continue
    if public or re.match(r'^(?:void|bool|int|zend_\w+\s*\*?|HashTable\s*\*?|std::\w+(?:::\w+)*(?:<[^>]+>)?)\s*\*?'+re.escape(base)+r'\s*\(',line):found.append(n)
  return {'path':sources[mode].relative_to(ROOT).as_posix(),'source_sha256':sha(sources[mode]),'definition_lines':found[:1]}
 present={mode:{name for item in core['exports']for name in item['names']}for mode,core in inventory['cores'].items()}
 rows=[]
 for name,req in sorted(inventory['requirements'].items()):
  row={'name':name,**req,'source_audit':{}}
  for mode,names in present.items():
   if name not in names:row['source_audit'][mode]={'classification':'MISSING_EXPORT','compatibility':'NOT_ESTABLISHED'};continue
   assert name in NOTES,name
   category='IMPLEMENTED_LIMITED'
   if name=='std_object_handlers':category='DATA_TABLE_PARTIAL_WITH_EXPLICIT_UNSUPPORTED_HANDLERS'
   elif name=='zend_string_init_interned':category='DATA_FUNCTION_POINTER_TO_REAL_LIMITED_IMPLEMENTATION'
   elif name in ('zend_register_functions','zend_wrong_parameter_error@@40'):category='IMPLEMENTED_WITH_EXPLICIT_UNSUPPORTED_BRANCHES'
   ev=evidence(mode,name,True);assert ev['definition_lines'],(mode,name)
   row['source_audit'][mode]={'classification':category,'note':NOTES[name],'evidence':ev,'compatibility':'NOT_INFERRED_FROM_SOURCE_OR_NAME'}
  rows.append(row)
 features=[{'feature':name,'classification':category,'note':note,'source_evidence':{mode:[evidence(mode,anchor)for anchor in anchors]for mode in sources}}for name,category,anchors,note in FEATURES]
 own=[]
 for mode,core in inventory['cores'].items():
  for item in core['exports']:
   for name in item['names']:
    if name.startswith('all_php_'):own.append({'mode':mode,'name':name,'classification':'CONTROLLED_TEST_PROBE_NOT_PHP_API'if name.endswith(('_memory_probe','_contract_probe'))else'OWN_CONTROL_API_LIMITED_NOT_PHP_ABI_SYMBOL','evidence':evidence(mode,name,True)})
 sourcezip=Path('C:/Users/rinpa/Downloads/php-8.5.12-1-src.zip');assert sha(sourcezip)=='9dac05f72f328afd0a2b0e795a519ae4cb3d056bc3f3b55147bd048bd64e45e8'
 contracts={}
 with zipfile.ZipFile(sourcezip)as z:
  for member,terms in {'ext/standard/info.c':['php_info_print_module(','php_info_print_table_start(','php_info_print_table_end(','php_info_print_table_header('],
                       'main/php_ini.c':['display_ini_entries('], 'ext/gettext/gettext.c':['VCWD_GETCWD','VCWD_REALPATH','zend_argument_value_error','zend_argument_must_not_be_empty_error'],
                       'Zend/zend_virtual_cwd.h':['virtual_getcwd(','virtual_realpath('], 'Zend/zend_API.h':['zend_argument_value_error(','zend_argument_must_not_be_empty_error('],
                       'Zend/zend_list.h':['zend_register_resource(','zend_list_close(','zend_fetch_resource'], 'Zend/zend_types.h':['struct _zend_reference {','struct _zend_resource {'],
                       'Zend/zend_object_handlers.h':['struct _zend_object_handlers {']}.items():
   raw=z.read(member);text=raw.decode('utf-8-sig').splitlines();contracts[member]={'sha256':hashlib.sha256(raw).hexdigest(),'anchor_lines':{term:[i for i,line in enumerate(text,1)if term in line]for term in terms}}
 report={'status':'STATIC_SOURCE_AUDIT_NOT_RUNTIME_COMPATIBILITY','inventory_sha256':sha(a.inventory),'source_hashes':{mode:sha(path)for mode,path in sources.items()},
         'summary':{'required_names':len(rows),'present_php_names_per_core':{mode:sum(row['name']in names for row in rows)for mode,names in present.items()},'missing_php_names_per_core':{mode:sum(row['name']not in names for row in rows)for mode,names in present.items()},'standalone_exported_noop_stub_observed_in_29_audited_php_names':0},
         'stub_definition':'A symbol exported solely as a dummy/no-op return without its required behavior; none observed among the 29 present PHP names. Narrow/incorrect implementations and unassigned handler slots remain separately labeled, never PASS.',
         'requirements':rows,'features':features,'own_control_exports':own,'pinned_reference_source_zip':{'path':str(sourcezip),'sha256':sha(sourcezip),'members':contracts},
         'approval_scope':'Independent native state/value/bridge work under approved option A; no source adoption, new dependencies or option B implementation performed'}
 save(out/'source-audit.json',report)
 with (out/'modules.csv').open('w',encoding='utf-8',newline='')as f:
  writer=csv.writer(f);writer.writerow(['extension','sha256','php8ts_import_names','original_missing_names','callback_missing_names','name_presence_is_not_compatibility'])
  for row in inventory['extensions']:writer.writerow([row['file'],row['sha256'],len(row['php8ts_named_imports']),len(row['own_name_presence']['original']['missing_names']),len(row['own_name_presence']['callback']['missing_names']),'NOT_TESTED'])
 print(json.dumps(report['summary']))


if __name__=='__main__':main()
