using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Reflection;
using System.Runtime.ExceptionServices;
using System.Security.Cryptography;
using System.Text;
using System.Web.Script.Serialization;
using AllPhp.ByteValues;

// A component probe, not a PHP evaluator. Each fixture invokes its selected
// unchanged native function once; failed calls are never retried via old APIs.
public static class AllNativeByteProbe {
    private static readonly JavaScriptSerializer Json=new JavaScriptSerializer{MaxJsonLength=Int32.MaxValue};
    private static object Call(object bridge,string method,params object[] arguments) {
        try{return bridge.GetType().GetMethod(method).Invoke(bridge,arguments);}
        catch(TargetInvocationException error){ExceptionDispatchInfo.Capture(error.InnerException).Throw();throw;}
    }
    private static object Property(object value,string name){return value.GetType().GetProperty(name).GetValue(value,null);}
    private static object Field(object value,string name){return value.GetType().GetField(name).GetValue(value);}
    private static string Hash(string path){using(var sha=SHA256.Create())using(var file=File.OpenRead(path))return BitConverter.ToString(sha.ComputeHash(file)).Replace("-","").ToLowerInvariant();}
    private static string Bytes(object value){return value==null?null:((PhpBytes)value).ToBase64();}
    private static Dictionary<string,object> Record(params object[] pairs){var result=new Dictionary<string,object>();for(int i=0;i<pairs.Length;i+=2)result.Add((string)pairs[i],pairs[i+1]);return result;}
    private static object[] Arguments(Dictionary<string,object> fixture) {
        var input=(object[])fixture["args"];var result=new object[input.Length];
        for(int i=0;i<input.Length;++i){var item=(Dictionary<string,object>)input[i];string type=(string)item["type"];
            if(type=="bytes")result[i]=PhpBytes.FromBase64((string)item["base64"]);
            else if(type=="null")result[i]=null;
            else if(type=="int")result[i]=Int64.Parse((string)item["value"],CultureInfo.InvariantCulture);
            else if(type=="double")result[i]=Double.Parse((string)item["value"],CultureInfo.InvariantCulture);
            else if(type=="bool")result[i]=(bool)item["value"];
            else if(type=="managed_text")result[i]=(string)item["value"];
            else throw new InvalidOperationException("Unknown fixture argument type");
        }return result;
    }
    private static Dictionary<string,object> Value(object value) {
        if(value==null)return Record("type","null","value",null);
        if(value is PhpBytes)return Record("type","string","value",Bytes(value));
        if(value is bool)return Record("type","bool","value",value);
        if(value is long||value is int)return Record("type","int","value",Convert.ToString(value,CultureInfo.InvariantCulture));
        if(value is double)return Record("type","float","value",((double)value).ToString("R",CultureInfo.InvariantCulture));
        if(value is string)return Record("type","string","value",Convert.ToBase64String(new UTF8Encoding(false,true).GetBytes((string)value)));
        throw new InvalidOperationException("Unexpected native result type: "+value.GetType().FullName);
    }
    public static int Main(string[] arguments) {
        if(arguments.Length!=7){Console.Error.WriteLine("mode core extension fixture metadata expectedCoreHash expectedExtensionHash");return 64;}
        string mode=arguments[0],core=Path.GetFullPath(arguments[1]),extension=Path.GetFullPath(arguments[2]);
        var metadata=Record("method","byte_native_component_direct_no_php_evaluator","mode",mode,"core",core,"core_sha256",Hash(core),"extension_sha256",Hash(extension),"fixture_sha256",Hash(arguments[3]),"native_function_retries",0);
        object bridge=null;bool started=false;int exit=0;
        var callbacks=new List<object>();var ordered=new List<object>();
        try {
            if((string)metadata["core_sha256"]!=arguments[5]||(string)metadata["extension_sha256"]!=arguments[6])throw new InvalidOperationException("Selected native input hash mismatch");
            var fixture=Json.Deserialize<Dictionary<string,object>>(File.ReadAllText(arguments[3],new UTF8Encoding(false,true)));
            string name=mode=="callback"?"AllPhp85AbiCallbackByte.Bridge":"AllPhp85AbiByte.Bridge";
            bridge=Activator.CreateInstance(Type.GetType(name+", AllPhp.NativeBytes.Bridges",true),new object[]{core});
            metadata["loaded_php_modules"]=Property(bridge,"LoadedPhpModules");
            Call(bridge,"LoadExtension",extension);Call(bridge,"Start");started=true;
            string behavior=fixture.ContainsKey("callback_behavior")?(string)fixture["callback_behavior"]:"none";
            if(mode=="callback"&&behavior=="legacy_capture") {
                Action<long,string> handler=delegate(long level,string message){callbacks.Add(Record("level",level,"message_base64",Convert.ToBase64String(new UTF8Encoding(false,true).GetBytes(message))));};
                Call(bridge,"SetDiagnosticHandler",handler);
            } else if(mode=="callback"&&behavior!="none") {
                Action<long,PhpBytes> handler=delegate(long level,PhpBytes message){
                    var diagnostic=Record("level",level,"message_base64",message.ToBase64());callbacks.Add(diagnostic);ordered.Add(Record("diagnostic",diagnostic));
                    if(behavior=="throw")throw new InvalidOperationException("BYTE_CALLBACK_STOP");
                };
                Action<PhpBytes> output=delegate(PhpBytes bytes){ordered.Add(Record("output_base64",bytes.ToBase64()));Stream target=Console.OpenStandardOutput();bytes.WriteTo(target);target.Flush();};
                Call(bridge,"SetByteDiagnosticHandler",handler,output);
            }
            metadata["stats_before"]=Json.DeserializeObject((string)Property(bridge,"Stats"));
            object call;
            try {
                if(fixture.ContainsKey("operation")&&(string)fixture["operation"]=="module_info") {
                    var values=Arguments(fixture);Call(bridge,"SetIniBytes","dl_test.string",values[0]);metadata["ini_value_base64"]=Bytes(Call(bridge,"IniBytes","dl_test.string"));
                    var output=(PhpBytes)Call(bridge,"ModuleInfoBytes");metadata["ok"]=true;metadata["status"]=0;metadata["value"]=Value(null);metadata["value_model"]=null;metadata["output_base64"]=output.ToBase64();metadata["diagnostics_base64"]="";metadata["error_class"]=null;metadata["error_message_base64"]=null;metadata["events"]=new object[0];Stream target=Console.OpenStandardOutput();output.WriteTo(target);target.Flush();
                }else{
                string api=fixture.ContainsKey("api")?(string)fixture["api"]:"InvokeScalarBytes";
                call=Call(bridge,api,(string)fixture["function"],Arguments(fixture),(bool)fixture["strict"]);
                metadata["ok"]=Field(call,"Ok");metadata["status"]=Field(call,"Status");metadata["value"]=Value(Field(call,"Value"));metadata["value_model"]=Field(call,"Value")==null?null:Field(call,"Value").GetType().FullName;
                object output=Field(call,"Output"),diagnostics=Field(call,"Diagnostics");
                if(output is PhpBytes){metadata["output_base64"]=Bytes(output);Stream target=Console.OpenStandardOutput();((PhpBytes)output).WriteTo(target);target.Flush();}
                else{byte[] data=(byte[])output;metadata["output_base64"]=Convert.ToBase64String(data);Console.OpenStandardOutput().Write(data,0,data.Length);}
                metadata["diagnostics_base64"]=diagnostics is PhpBytes?Bytes(diagnostics):Convert.ToBase64String((byte[])diagnostics);
                metadata["error_class"]=Field(call,"ErrorClass");object error=Field(call,"ErrorMessage");metadata["error_message_base64"]=error is PhpBytes?Bytes(error):error==null?null:Convert.ToBase64String(new UTF8Encoding(false,true).GetBytes((string)error));
                var events=new List<object>();foreach(object item in (IEnumerable)Field(call,"DiagnosticEvents")){object message=Field(item,"Message");var row=Record("level",Field(item,"Level"),"message_base64",message is PhpBytes?Bytes(message):Convert.ToBase64String(new UTF8Encoding(false,true).GetBytes((string)message)));events.Add(row);}metadata["events"]=events;
                // Preserve a returned byte value across End/Shutdown for the
                // recorded ownership check, after tls.last has been destroyed.
                metadata["returned_value_before_end"]=Value(Field(call,"Value"));
                metadata["retained_return_value"]=Field(call,"Value");
                }
            } catch(Exception error) {
                metadata["managed_exception"]=error.GetType().FullName;metadata["managed_exception_message"]=error.Message;
            }
            metadata["stats_after_call"]=Json.DeserializeObject((string)Property(bridge,"Stats"));
            metadata["callbacks"]=callbacks;metadata["ordered_callback_chunks"]=ordered;
        } catch(Exception error){metadata["host_failure"]=error.ToString();exit=70;}
        finally {
            if(bridge!=null){
                try{if(started)Call(bridge,"End");Call(bridge,"Shutdown");metadata["stats_final"]=Json.DeserializeObject((string)Property(bridge,"Stats"));if(mode=="callback")metadata["callback_stats_final"]=Json.DeserializeObject((string)Property(bridge,"CallbackStats"));}
                catch(Exception error){metadata["cleanup_failure"]=error.ToString();exit=71;}
            }
            if(metadata.ContainsKey("retained_return_value")){metadata["returned_value_after_end"]=Value(metadata["retained_return_value"]);metadata.Remove("retained_return_value");}
            metadata["actual_main_status"]=exit;
            File.WriteAllText(arguments[4],Json.Serialize(metadata)+Environment.NewLine,new UTF8Encoding(false));
        }
        return exit;
    }
}
