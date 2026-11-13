using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;
using AllPhp.ByteValues;
using AllPhp85AbiCallbackByte;

// Controlled managed-thunk and lease tests. Injected bytes below are synthetic,
// not evidence that dl_test emits such diagnostics or arbitrary ABI compatibility.
public static class AllByteCallbackContractProbe {
    private static readonly JavaScriptSerializer Json=new JavaScriptSerializer();
    private static void Require(bool condition,string message){if(!condition)throw new InvalidOperationException(message);}
    private static string Hash(string path){using(var sha=SHA256.Create())using(var source=File.OpenRead(path))return BitConverter.ToString(sha.ComputeHash(source)).Replace("-","").ToLowerInvariant();}
    private static object PrivateField(Bridge bridge,string name){return typeof(Bridge).GetField(name,BindingFlags.Instance|BindingFlags.NonPublic).GetValue(bridge);}
    private static object PrivateCall(Bridge bridge,string name,params object[] args){return typeof(Bridge).GetMethod(name,BindingFlags.Instance|BindingFlags.NonPublic).Invoke(bridge,args);}
    private static Dictionary<string,object> Read(string value){return Json.Deserialize<Dictionary<string,object>>(value);}
    private static long Number(Dictionary<string,object> value,string key){return Convert.ToInt64(value[key]);}
    public static int Main(string[] args){
        if(args.Length!=5)return 64;
        var record=new Dictionary<string,object>();var checks=new List<string>();record["status"]="NOT_COMPLETE";record["scope"]="Controlled managed byte thunk transport plus one real dl_test callback abort; not PHP compatibility cases";
        Bridge bridge=null;bool started=false;int status=0;PhpBytes diagnosticCopy=null,outputCopy=null;byte[] payload=new byte[263];
        payload[0]=0xff;payload[1]=0;payload[2]=0xc0;payload[3]=0xaf;payload[4]=0xed;payload[5]=0xa0;payload[6]=0x80;for(int i=0;i<256;++i)payload[i+7]=(byte)i;
        string expected=Convert.ToBase64String(payload);record["synthetic_payload_base64"]=expected;
        try{
            Require(Hash(args[0])==args[3]&&Hash(args[1])==args[4],"native input hash mismatch");
            record["core_sha256"]=Hash(args[0]);record["extension_sha256"]=Hash(args[1]);
            bridge=new Bridge(Path.GetFullPath(args[0]));bridge.LoadExtension(args[1]);bridge.Start();started=true;
            var allocated=new List<IntPtr>();
            try{
                var copy=typeof(Bridge).GetMethod("CopyArgument",BindingFlags.Static|BindingFlags.NonPublic,null,new Type[]{typeof(PhpBytes),typeof(NativeValue).MakeByRefType(),typeof(List<IntPtr>)},null);
                object[] parameters=new object[]{PhpBytes.FromBytes(payload),new NativeValue(),allocated};copy.Invoke(null,parameters);var value=(NativeValue)parameters[1];var observed=new byte[payload.Length];Marshal.Copy(value.Bytes,observed,0,observed.Length);Require(value.Length.ToUInt64()==(ulong)payload.Length&&Convert.ToBase64String(observed)==expected,"argument copy lost bytes after NUL");
            }finally{foreach(IntPtr pointer in allocated)Marshal.FreeHGlobal(pointer);}
            checks.Add("synthetic native argument allocation preserves every byte after NUL and its explicit length");
            bridge.SetByteDiagnosticHandler(delegate(long level,PhpBytes bytes){Require(level==8192,"diagnostic level");diagnosticCopy=bytes;},delegate(PhpBytes bytes){outputCopy=bytes;});
            Require(bridge.SynchronousCallbacksEnabled,"byte handler enables lease");checks.Add("byte handler enables the existing ownership guard");
            bool duplicate=false;try{bridge.SetByteDiagnosticHandler(delegate(long level,PhpBytes bytes){},delegate(PhpBytes bytes){});}catch(InvalidOperationException){duplicate=true;}Require(duplicate,"duplicate lease accepted");checks.Add("duplicate byte lease rejected");
            string wrongThread=null;var thread=new Thread(delegate(){try{bridge.InvokeScalarBytes("dl_test_test2",new object[]{PhpBytes.FromBytes(new byte[]{65})},false);wrongThread="NOT_REJECTED";}catch(NotSupportedException){wrongThread="REJECTED";}catch(Exception error){wrongThread=error.ToString();}});thread.IsBackground=true;thread.Start();Require(thread.Join(10000)&&wrongThread=="REJECTED","wrong thread was not rejected");checks.Add("new byte invocation rejects foreign managed thread before native call");
            string[] raw=bridge.ProbeRawWrongThread();foreach(string item in raw)Require(item!=null&&item.StartsWith("-1:"),"raw owner guard changed");record["raw_owner_rejections"]=raw;checks.Add("five original native owner guards remain active with byte lease");
            object local=PrivateField(bridge,"pending");object stack=local.GetType().GetProperty("Value").GetValue(local,null);Type frame=stack.GetType().GetGenericArguments()[0];stack.GetType().GetMethod("Push").Invoke(stack,new object[]{Activator.CreateInstance(frame,true)});
            GCHandle pin=GCHandle.Alloc(payload,GCHandleType.Pinned);
            try{
                IntPtr cookie=GCHandle.ToIntPtr((GCHandle)PrivateField(bridge,"callbackRoot"));
                int code=(int)PrivateCall(bridge,"ReceiveDiagnostic",8192,pin.AddrOfPinnedObject(),new UIntPtr((uint)payload.Length),cookie);Require(code==1,"byte diagnostic thunk failed");
                code=(int)PrivateCall(bridge,"ReceiveOutput",pin.AddrOfPinnedObject(),new UIntPtr((uint)payload.Length),cookie);Require(code==1,"byte output thunk failed");
                Require(diagnosticCopy.ToBase64()==expected&&outputCopy.ToBase64()==expected,"raw thunk bytes changed");
                Array.Clear(payload,0,payload.Length);Require(diagnosticCopy.ToBase64()==expected&&outputCopy.ToBase64()==expected,"copied bytes alias native memory");
            }finally{pin.Free();stack.GetType().GetMethod("Pop").Invoke(stack,null);}
            checks.Add("synthetic FF NUL invalid UTF8 surrogate UTF8 and all256 diagnostic/output bytes copied without decoding");checks.Add("synthetic copied messages do not alias the overwritten native buffer");
            Require(Number(Read(bridge.Stats),"native_invocations")==0,"guard/transport probes invoked a native function");checks.Add("guard and synthetic transport probes invoke no extension function");
            bridge.ClearDiagnosticHandler();Require(!bridge.SynchronousCallbacksEnabled,"byte clear left handler enabled");
            var expectedAbort=new InvalidOperationException("BYTE_CALLBACK_ABORT");
            bridge.SetByteDiagnosticHandler(delegate(long level,PhpBytes bytes){throw expectedAbort;},delegate(PhpBytes bytes){});
            bool sameException=false;try{bridge.InvokeScalarBytes("dl_test_test2",new object[]{null},false);}catch(InvalidOperationException error){sameException=Object.ReferenceEquals(expectedAbort,error);}
            Require(sameException,"original managed exception identity lost");
            Require(Number(Read(bridge.Stats),"native_invocations")==1,"aborted extension function retried");
            var callback=Read(bridge.CallbackStats);Require(Number(callback,"callbacks")==1&&Number(callback,"aborts")==1,"abort counters");
            record["callback_stats_after_abort"]=callback;checks.Add("one unchanged dl_test null call aborts synchronously with original managed exception identity and no retry");
            bridge.ClearDiagnosticHandler();Require(!bridge.SynchronousCallbacksEnabled,"clear after abort failed");checks.Add("byte callback lease clears after abort");
        }catch(Exception error){record["failure"]=error.ToString();status=1;}
        finally{
            if(bridge!=null){try{if(started)bridge.End();bridge.Shutdown();record["stats_final"]=Read(bridge.Stats);record["callback_stats_final"]=Read(bridge.CallbackStats);var final=(Dictionary<string,object>)record["stats_final"];Require(Number(final,"minit")==Number(final,"mshutdown")&&Number(final,"rinit")==Number(final,"rshutdown")&&Number(final,"tls_contexts_created")==Number(final,"tls_contexts_destroyed")&&Number(final,"request_allocations_live")==0,"controlled teardown unbalanced");Require(Number((Dictionary<string,object>)record["callback_stats_final"],"callback_owner_thread")==0,"lease remains owned");checks.Add("controlled module request TLS and callback teardown balanced");if(diagnosticCopy!=null){Require(diagnosticCopy.ToBase64()==expected&&outputCopy.ToBase64()==expected,"copies changed after teardown");checks.Add("synthetic managed copies remain unchanged after native teardown");}}catch(Exception error){record["cleanup_failure"]=error.ToString();status=1;}}
            record["checks"]=checks;record["passed_checks"]=checks.Count;record["status"]=status==0?"CONTROLLED_CONTRACT_PASS_NOT_PHP_COMPATIBILITY":"FAIL";record["actual_main_status"]=status;
            File.WriteAllText(args[2],Json.Serialize(record)+Environment.NewLine,new UTF8Encoding(false));
        }
        Console.WriteLine(Json.Serialize(new{status=status,passed_checks=checks.Count}));return status;
    }
}
