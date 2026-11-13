"""Create a new gettext-only callback core/bridge; never load its DLLs."""
from pathlib import Path
import argparse
import difflib
import hashlib
import json

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
BASE=ROOT/'tools/candidates/php-native-info-v2/generated02'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
PINS={BASE/'callback/src/Runtime.cpp':'c0c35e44e8d8213142b27bb963756bae2970747b05cec5e0ecd3483e62469c05',BASE/'bridge/AllNativeCallbackBridge.cs':'234536085e15eab5e78dc8998562fbb9a4cac76cfa6492374bddcce3c286d5ed'}

def once(value,old,new):
    assert value.count(old)==1,(old[:90],value.count(old))
    return value.replace(old,new)

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--output-directory',type=Path,required=True);args=parser.parse_args()
    out=args.output_directory.resolve();assert out.is_relative_to(HERE)and not out.exists();out.mkdir()
    records=[]
    def emit(source,relative,text):
        destination=out/relative;destination.parent.mkdir(parents=True,exist_ok=True)
        original=source.read_text(encoding='utf-8-sig');destination.write_text(text,encoding='utf-8',newline='\n')
        patch=destination.with_suffix(destination.suffix+'.patch')
        patch.write_text(''.join(difflib.unified_diff(original.splitlines(True),text.splitlines(True),fromfile=source.as_posix(),tofile=destination.as_posix())),encoding='utf-8',newline='\n')
        records.append(dict(original=str(source),original_sha256=sha(source),candidate=str(destination),candidate_sha256=sha(destination),patch_sha256=sha(patch)))
    for path,pin in PINS.items():assert sha(path)==pin,(path,sha(path))
    source=BASE/'callback/src/Runtime.cpp';text=source.read_text(encoding='utf-8-sig')
    text=once(text,'#include <cmath>','#include <cmath>\n#include <cerrno>\n#include <climits>')
    # The SDK virtual-cwd header has no own C++ linkage guard. Establish its
    # actual C ABI before php.h transitively introduces those declarations.
    text=once(text,'#include "php.h"','extern "C" {\n__declspec(dllexport) char *virtual_getcwd(char *,size_t);\n__declspec(dllexport) char *virtual_realpath(const char *,char *);\n}\n#include "php.h"')
    text=once(text,'    std::vector<Diagnostic> diagnostic_events;','    std::wstring cwd_wide;\n    std::string cwd_bytes;\n    std::map<wchar_t,std::wstring> drive_cwds;\n    std::vector<Diagnostic> diagnostic_events;')
    text=once(text,'void string_release(zend_string *s) {',(HERE/'CwdHelpers.cpp').read_text()+'\nvoid string_release(zend_string *s) {')
    text=once(text,'ZEND_API const zend_object_handlers std_object_handlers=make_handlers();',(HERE/'GettextExports.cpp').read_text()+'\nZEND_API const zend_object_handlers std_object_handlers=make_handlers();')
    text=once(text,'if(attach_thread()!=0)return -1;tls.active=true;++tls.requests_started;','if(attach_thread()!=0)return -1;if(!cwd_request_initialize()){cwd_request_clear();error("Error","Cannot initialize virtual directory");return -1;}tls.active=true;++tls.requests_started;')
    text=once(text,'if(apply_ini_defaults()!=0){clear_ini();tls.active=false;return -1;}','if(apply_ini_defaults()!=0){clear_ini();cwd_request_clear();tls.active=false;return -1;}')
    text=once(text,'destroy(&tls.last);clear_ini();tls.active=false;++tls.requests_ended;','destroy(&tls.last);clear_ini();cwd_request_clear();tls.active=false;++tls.requests_ended;')
    # The SDK inlines path validation but reports the failure through this existing
    # export. A string rejected by Z_PARAM_PATH_STR is the embedded-NUL case.
    text=once(text,'if(!tls.error.empty())return;std::string target=expected==Z_EXPECTED_LONG?"int":expected==Z_EXPECTED_STRING?"string":"unsupported type";',
        'if(!tls.error.empty())return;if((expected==Z_EXPECTED_PATH||expected==Z_EXPECTED_PATH_OR_NULL)&&Z_TYPE_P(arg)==IS_STRING){zend_argument_value_error(num,"must not contain any null bytes");return;}std::string target=expected==Z_EXPECTED_LONG?"int":(expected==Z_EXPECTED_STRING||expected==Z_EXPECTED_PATH)?"string":(expected==Z_EXPECTED_STRING_OR_NULL||expected==Z_EXPECTED_PATH_OR_NULL)?"?string":"unsupported type";')
    emit(source,Path('callback/src/Runtime.cpp'),text)
    source=BASE/'callback/include/all_php_bridge.h';text=source.read_text(encoding='utf-8-sig')
    text=once(text,'ALL_ABI_EXPORT int all_php_request_start(void);','/* UTF-8 path bytes; embedded NUL rejected; explicit per-request state. */\nALL_ABI_EXPORT int all_php_virtual_cwd_set(const unsigned char *path,size_t length);\nALL_ABI_EXPORT const char *all_php_virtual_cwd_get(size_t *length);\nALL_ABI_EXPORT int all_php_request_start(void);')
    emit(source,Path('callback/include/all_php_bridge.h'),text)
    source=BASE/'bridge/AllNativeCallbackBridge.cs';text=source.read_text(encoding='utf-8-sig')
    text=once(text,'namespace AllPhp85AbiCallbackInfoV2Byte','namespace AllPhp85AbiCallbackGettextByte')
    text=once(text,'        private LoadDelegate load;','        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int CwdSetDelegate(IntPtr path,UIntPtr length);\n        private CwdSetDelegate cwdSet;\n        private SizedStringDelegate cwdGet;\n        private LoadDelegate load;')
    text=once(text,'            load=Bind<LoadDelegate>("all_php_load_extension");','            cwdSet=Bind<CwdSetDelegate>("all_php_virtual_cwd_set");cwdGet=Bind<SizedStringDelegate>("all_php_virtual_cwd_get");\n            load=Bind<LoadDelegate>("all_php_load_extension");')
    text=once(text,'if(hash!="532b9f0944d482a704eb81ac1cb9af3b59aa0f54c753c53a5709c17f57d4e938")throw new NotSupportedException("Callback prototype accepts only the pinned tested C dl_test binary");','if(hash!="ed395f80018920ba1b4551cdc33dd89871eb8b8ef362b1515ae93c0e7f1de3ad")throw new NotSupportedException("Gettext candidate accepts only the exact reviewed PHP 8.5.12 gettext binary");')
    text=once(text,'        public void Start(){EnsureCallbackOwner();Check(start());}', '''        public void SetVirtualDirectory(PhpBytes path){
            EnsureCallbackOwner();if(path==null)throw new ArgumentNullException("path");
            if(path.Length>Int32.MaxValue)throw new NotSupportedException("Path exceeds bounded native path API");
            byte[] data=path.ToArray();for(int i=0;i<data.Length;++i)if(data[i]==0)throw new ArgumentException("Path contains NUL","path");
            IntPtr pointer=Marshal.AllocHGlobal(checked(data.Length+1));
            try{if(data.Length>0)Marshal.Copy(data,0,pointer,data.Length);Marshal.WriteByte(pointer,data.Length,0);Check(cwdSet(pointer,new UIntPtr((uint)data.Length)));}finally{Marshal.FreeHGlobal(pointer);}
        }
        public PhpBytes VirtualDirectory {get{EnsureCallbackOwner();return CaptureBytes(cwdGet);}}
        public void Start(){EnsureCallbackOwner();Check(start());}''')
    emit(source,Path('bridge/AllNativeCallbackBridge.cs'),text)
    record={'status':'GENERATED_NOT_BUILT_OR_LOADED','inputs':records,'fragment_hashes':{str(p):sha(p)for p in [HERE/'CwdHelpers.cpp',HERE/'GettextExports.cpp',Path(__file__).resolve()]},'stock_php_source_adopted':False,'extension_executed':False,'profile':'UTF-8 Windows paths with request/TLS cwd and exact gettext binary only; general PHP code-page/SAPI support not established'}
    (out/'provenance.json').write_text(json.dumps(record,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'status':record['status'],'files':len(records),'directory':str(out)}))

if __name__=='__main__':main()
