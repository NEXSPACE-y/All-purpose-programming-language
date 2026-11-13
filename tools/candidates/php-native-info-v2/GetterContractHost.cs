using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;
using AllPhp.ByteValues;
using AllPhp85AbiCallbackInfoV2Byte;

// Own test-only DLL, no extension is loaded/called. The production byte bridge
// invokes the real sized getter/copy routine, not an emulated managed function.
public static class GetterContractHost {
    [DllImport("kernel32.dll",CharSet=CharSet.Ansi)] private static extern IntPtr GetProcAddress(IntPtr module,string name);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int SetError(IntPtr bytes,UIntPtr length);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate IntPtr NullLengthGetter(IntPtr length);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int Simple();
    private static void Check(bool condition,string message){if(!condition)throw new InvalidOperationException(message);}
    private static string Hash(byte[] data){using(var hash=SHA256.Create())return BitConverter.ToString(hash.ComputeHash(data)).Replace("-","").ToLowerInvariant();}
    private static string FileHash(string path){return Hash(File.ReadAllBytes(path));}
    private static PhpBytes CopyError(Bridge bridge){object getter=typeof(Bridge).GetField("errorMessageBytes",BindingFlags.NonPublic|BindingFlags.Instance).GetValue(bridge);return (PhpBytes)typeof(Bridge).GetMethod("CaptureBytes",BindingFlags.NonPublic|BindingFlags.Instance).Invoke(bridge,new object[]{getter});}
    private static T Bind<T>(IntPtr module,string name)where T:class{IntPtr address=GetProcAddress(module,name);if(address==IntPtr.Zero)throw new InvalidOperationException("Missing test export "+name);return Marshal.GetDelegateForFunctionPointer(address,typeof(T))as T;}
    public static int Main(string[] args){
        if(args.Length!=3)return 64;
        var rows=new List<object>();var record=new Dictionary<string,object>();var json=new JavaScriptSerializer();int status=0;
        record["scope"]="SYNTHETIC_GETTER_CONTRACT_NOT_PHP_COMPATIBILITY";record["extension_loaded_or_called"]=false;record["core_sha256"]=FileHash(args[0]);
        try{
            Check((string)record["core_sha256"]==args[2],"test core hash mismatch");
            var bridge=new Bridge(Path.GetFullPath(args[0]));IntPtr module=(IntPtr)typeof(Bridge).GetField("module",BindingFlags.NonPublic|BindingFlags.Instance).GetValue(bridge);
            var set=Bind<SetError>(module,"all_info_v2_contract_set_error");var nullLength=Bind<NullLengthGetter>(module,"all_php_error_message_bytes");var end=Bind<Simple>(module,"all_php_request_end");
            Check(CopyError(bridge).Length==0,"initial inactive getter not empty");Check(nullLength(IntPtr.Zero)!=IntPtr.Zero,"optional null size pointer failed");
            record["initial_empty_outside_request"]=true;record["null_length_pointer_safe"]=true;
            Check(end()==-1,"inactive End was accepted");Check(CopyError(bridge).Length>0,"inactive-state error bytes missing");record["inactive_end_rejected_and_error_readable"]=true;
            Check(set(IntPtr.Zero,new UIntPtr(1))==-1,"invalid synthetic setter pointer accepted");record["invalid_synthetic_input_rejected"]=true;
            var payloads=new List<byte[]>();payloads.Add(new byte[0]);payloads.Add(new byte[]{255});payloads.Add(new byte[]{65,0,66});payloads.Add(new byte[]{0xed,0xa0,0x80});var all=new byte[256];for(int i=0;i<256;++i)all[i]=(byte)i;payloads.Add(all);
            var large=new byte[16777217];for(int i=0;i<large.Length;++i)large[i]=120;large[large.Length-1]=255;payloads.Add(large);
            PhpBytes retained=null;string retainedHash=null;
            for(int index=0;index<payloads.Count;++index){byte[] input=payloads[index];IntPtr pointer=Marshal.AllocHGlobal(Math.Max(1,input.Length));
                try{if(input.Length>0)Marshal.Copy(input,0,pointer,input.Length);Check(set(pointer,new UIntPtr((uint)input.Length))==0,"synthetic set failed");PhpBytes copy=CopyError(bridge);string actual=Hash(copy.ToArray()),expected=Hash(input);Check(copy.Length==input.LongLength&&actual==expected,"sized getter lost bytes");
                    Check(set(IntPtr.Zero,UIntPtr.Zero)==0,"overwrite failed");Check(CopyError(bridge).Length==0,"overwrite not observed");Check(Hash(copy.ToArray())==expected,"managed copy aliases expired native buffer");
                    rows.Add(new{index=index,length=copy.Length,sha256=actual,after_native_overwrite_same=true});retained=copy;retainedHash=expected;
                }finally{Marshal.FreeHGlobal(pointer);}}
            string foreign=null;var thread=new Thread(delegate(){try{foreign=CopyError(bridge).ToBase64();}catch(Exception error){foreign="FAIL:"+error.Message;}});thread.IsBackground=true;thread.Start();Check(thread.Join(10000)&&foreign=="","foreign TLS getter not independently empty");record["thread_local_error_state_separate"]=true;
            bridge.Shutdown();Check(Hash(retained.ToArray())==retainedHash,"copy changed after shutdown");record["copy_survives_shutdown"]=true;
            record["stats"]=json.DeserializeObject(bridge.Stats);record["loaded_php_modules"]=bridge.LoadedPhpModules;
        }catch(Exception error){record["failure"]=error.ToString();status=1;}
        record["payload_cases"]=rows;record["payload_cases_passed"]=rows.Count;record["actual_main_status"]=status;record["status"]=status==0?"CONTROLLED_GETTER_PASS_NOT_PHP_COMPATIBILITY":"FAIL";
        File.WriteAllText(args[1],json.Serialize(record)+Environment.NewLine,new UTF8Encoding(false));Console.WriteLine(json.Serialize(new{actual_status=status,payload_cases_passed=rows.Count}));return status;
    }
}
