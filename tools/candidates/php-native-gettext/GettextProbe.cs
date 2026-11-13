using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Web.Script.Serialization;
using AllPhp.ByteValues;
using AllPhp85AbiCallbackGettextByte;

// Direct unchanged-module component host, not a PHP evaluator.
// One module/context per process; requested calls execute once, without retry.
public static class AllNativeGettextProbe {
    private static readonly JavaScriptSerializer Json=new JavaScriptSerializer{MaxJsonLength=Int32.MaxValue};
    [DllImport("ucrtbase.dll",CallingConvention=CallingConvention.Cdecl,EntryPoint="setlocale")]
    private static extern IntPtr SetLocale(int category,[MarshalAs(UnmanagedType.LPStr)]string locale);
    private static Dictionary<string,object> Record(params object[] pairs){var r=new Dictionary<string,object>();for(int i=0;i<pairs.Length;i+=2)r.Add((string)pairs[i],pairs[i+1]);return r;}
    private static string Hash(string path){using(var sha=SHA256.Create())using(var file=File.OpenRead(path))return BitConverter.ToString(sha.ComputeHash(file)).Replace("-","").ToLowerInvariant();}
    private static object[] Arguments(Dictionary<string,object> step){var items=(IList)step["args"];var result=new object[items.Count];for(int i=0;i<items.Count;++i){var item=(Dictionary<string,object>)items[i];string type=(string)item["type"];
        if(type=="bytes")result[i]=PhpBytes.FromBase64((string)item["base64"]);
        else if(type=="null")result[i]=null;
        else if(type=="bool")result[i]=(bool)item["value"];
        else if(type=="int")result[i]=Int64.Parse((string)item["value"],CultureInfo.InvariantCulture);
        else if(type=="double")result[i]=Double.Parse((string)item["value"],CultureInfo.InvariantCulture);
        else throw new InvalidOperationException("Unknown argument type "+type);
    }return result;}
    private static object Value(object value){
        if(value==null)return Record("type","null","value",null);
        if(value is PhpBytes)return Record("type","string","value",((PhpBytes)value).ToBase64());
        if(value is bool)return Record("type","bool","value",value);
        if(value is long||value is int)return Record("type","int","value",Convert.ToString(value,CultureInfo.InvariantCulture));
        if(value is double)return Record("type","float","value",((double)value).ToString("R",CultureInfo.InvariantCulture));
        throw new InvalidOperationException("Unexpected native value type");
    }
    public static int Main(string[] arguments){
        if(arguments.Length!=7){Console.Error.WriteLine("core extension fixture metadata coreHash extensionHash fixtureHash");return 64;}
        var metadata=Record("method","unchanged_gettext_direct_native_component","native_function_retries",0,"extension_sha256",Hash(arguments[1]),"core_sha256",Hash(arguments[0]),"fixture_sha256",Hash(arguments[2]),"host_process_cwd",Directory.GetCurrentDirectory());
        Bridge bridge=null;bool active=false;int exit=0;var observations=new List<object>();
        try{
            if((string)metadata["core_sha256"]!=arguments[4]||(string)metadata["extension_sha256"]!=arguments[5]||(string)metadata["fixture_sha256"]!=arguments[6])throw new InvalidOperationException("Input hash mismatch");
            var fixture=Json.Deserialize<Dictionary<string,object>>(File.ReadAllText(arguments[2],new UTF8Encoding(false,true)));
            bridge=new Bridge(Path.GetFullPath(arguments[0]));bridge.LoadExtension(Path.GetFullPath(arguments[1]));bridge.Start();active=true;
            metadata["loaded_php_modules"]=bridge.LoadedPhpModules;metadata["catalog"]=Json.DeserializeObject(bridge.FunctionCatalog);metadata["stats_before"]=Json.DeserializeObject(bridge.Stats);
            foreach(object raw in (IList)fixture["steps"]){var step=(Dictionary<string,object>)raw;string operation=(string)step["operation"];
                if(operation=="call"){
                    var call=bridge.InvokeScalarBytes((string)step["function"],Arguments(step),(bool)step["strict"]);
                    var events=new List<object>();foreach(var item in call.DiagnosticEvents)events.Add(Record("level",item.Level,"message_base64",item.Message.ToBase64()));
                    observations.Add(Record("operation",operation,"function",step["function"],"ok",call.Ok,"value",Value(call.Value),"output_base64",call.Output.ToBase64(),"diagnostics_base64",call.Diagnostics.ToBase64(),"events",events,"error_class",call.ErrorClass,"error_message_base64",call.ErrorMessage==null?null:call.ErrorMessage.ToBase64()));
                    if(call.Output.Length!=0){Stream output=Console.OpenStandardOutput();call.Output.WriteTo(output);output.Flush();}
                }else if(operation=="virtual_cwd"){
                    bridge.SetVirtualDirectory(PhpBytes.FromBase64((string)step["base64"]));observations.Add(Record("operation",operation,"value",Value(bridge.VirtualDirectory)));
                }else if(operation=="get_cwd")observations.Add(Record("operation",operation,"value",Value(bridge.VirtualDirectory)));
                else if(operation=="locale"){
                    string locale=(string)step["locale"];if(locale.IndexOf('\0')>=0)throw new InvalidOperationException("Locale NUL");
                    IntPtr result=SetLocale(Convert.ToInt32(step["category"],CultureInfo.InvariantCulture),locale);
                    observations.Add(Record("operation",operation,"accepted",result!=IntPtr.Zero,"locale",result==IntPtr.Zero?null:Marshal.PtrToStringAnsi(result)));
                }else if(operation=="restart"){
                    bridge.End();active=false;bridge.Start();active=true;observations.Add(Record("operation",operation,"value",Value(bridge.VirtualDirectory)));
                }else if(operation=="module_info"){
                    PhpBytes output=bridge.ModuleInfoBytes();observations.Add(Record("operation",operation,"output_base64",output.ToBase64()));Stream target=Console.OpenStandardOutput();output.WriteTo(target);target.Flush();
                }else throw new InvalidOperationException("Unknown requested operation "+operation);
            }
            metadata["stats_after_calls"]=Json.DeserializeObject(bridge.Stats);
        }catch(Exception error){metadata["host_failure"]=error.ToString();exit=70;}
        finally{
            metadata["observations"]=observations;
            if(bridge!=null){try{if(active)bridge.End();bridge.Shutdown();metadata["stats_final"]=Json.DeserializeObject(bridge.Stats);}catch(Exception error){metadata["cleanup_failure"]=error.ToString();exit=71;}}
            metadata["host_process_cwd_after"]=Directory.GetCurrentDirectory();metadata["actual_main_status"]=exit;
            File.WriteAllText(arguments[3],Json.Serialize(metadata)+Environment.NewLine,new UTF8Encoding(false));
        }return exit;
    }
}
