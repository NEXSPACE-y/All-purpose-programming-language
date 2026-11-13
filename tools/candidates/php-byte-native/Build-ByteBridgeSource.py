"""Add byte-valued APIs to immutable legacy/callback bridge copies."""
import difflib
import argparse
import hashlib
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
PINS = {
    "legacy": ("AllNativeLegacyBridge.cs", "32692504898a77063bcbad631c48d40d8fa1f7c17fcf3f5d837c6f77479ec077", "AllPhp85Abi", "AllPhp85AbiByte"),
    "callback": ("AllNativeCallbackBridge.cs", "8c37470ecafa4c00a41dbf8917295f88f76b7d2fbbd57645a91313bc833efda8", "AllPhp85AbiCallback", "AllPhp85AbiCallbackByte"),
}

TYPES = r'''
    public sealed class ByteScalarInvocation {
        public bool Ok;
        public int Status;
        public object Value;
        public PhpBytes Output, Diagnostics, ErrorMessage;
        public string ErrorClass;
        public ByteNativeDiagnosticEvent[] DiagnosticEvents;
    }
    public sealed class ByteNativeDiagnosticEvent {
        public int Level;
        public PhpBytes Message;
        public bool Delivered;
    }
'''

METHODS = r'''
        // The borrowed pointer never escapes this synchronous copying stream.
        // FromStream must consume/copy the complete stream before returning.
        private sealed class BorrowedNativeStream : Stream {
            private readonly IntPtr pointer;
            private readonly long length;
            private long position;
            public BorrowedNativeStream(IntPtr pointer,long length) {
                if(length<0)throw new ArgumentOutOfRangeException("length");
                if(length>0&&pointer==IntPtr.Zero)throw new InvalidOperationException("Null native pointer with nonempty byte length");
                this.pointer=pointer;this.length=length;
            }
            public override bool CanRead {get{return true;}}
            public override bool CanSeek {get{return false;}}
            public override bool CanWrite {get{return false;}}
            public override long Length {get{return length;}}
            public override long Position {get{return position;}set{throw new NotSupportedException();}}
            public override int Read(byte[] buffer,int offset,int count) {
                if(buffer==null)throw new ArgumentNullException("buffer");
                if(offset<0||count<0||offset>buffer.Length-count)throw new ArgumentOutOfRangeException();
                int take=(int)Math.Min((long)count,length-position);
                if(take>0){Marshal.Copy(new IntPtr(checked(pointer.ToInt64()+position)),buffer,offset,take);position+=take;}
                return take;
            }
            public override void Flush(){}
            public override long Seek(long offset,SeekOrigin origin){throw new NotSupportedException();}
            public override void SetLength(long value){throw new NotSupportedException();}
            public override void Write(byte[] buffer,int offset,int count){throw new NotSupportedException();}
        }
        private static PhpBytes CopyNativeBytes(IntPtr pointer,UIntPtr count) {
            ulong size=count.ToUInt64();if(size>Int64.MaxValue)throw new NotSupportedException("Native string length exceeds the managed byte model");
            using(var source=new BorrowedNativeStream(pointer,(long)size)){PhpBytes result=PhpBytes.FromStream(source);if(result.Length!=(long)size)throw new InvalidOperationException("Native byte copy ended before its declared length");return result;}
        }
        private static PhpBytes CopyNativeCString(IntPtr pointer) {
            if(pointer==IntPtr.Zero)return null;
            int length=0;while(Marshal.ReadByte(pointer,length)!=0){if(++length>16777216)throw new InvalidOperationException("Native C string lacks a bounded terminator");}
            return CopyNativeBytes(pointer,new UIntPtr((uint)length));
        }
        private PhpBytes CaptureBytes(SizedStringDelegate function) {UIntPtr count;IntPtr pointer=function(out count);return CopyNativeBytes(pointer,count);}
        private static object DecodeBytes(NativeValue value) {
            switch(value.Type){case 1:return null;case 2:return false;case 3:return true;case 4:return value.Integer;case 5:return value.Real;case 6:return CopyNativeBytes(value.Bytes,value.Length);default:throw new NotSupportedException("Unsupported return type "+value.Type);}
        }
        public object ConstantBytes(string name){OWNER_GUARD RequireCString(name,"Constant name",false);NativeValue value;Check(getConstant(name,out value));return DecodeBytes(value);}
        public PhpBytes ModuleInfoBytes(){OWNER_GUARD clear();Check(info());return CaptureBytes(output);}
        public PhpBytes IniBytes(string name){OWNER_GUARD RequireCString(name,"INI key",false);return CopyNativeCString(getIni(name));}
        public void SetIniBytes(string name,PhpBytes value){
            OWNER_GUARD RequireCString(name,"INI key",false);if(value==null)throw new ArgumentNullException("value");
            var allocated=new List<IntPtr>();try{NativeValue native=new NativeValue();CopyArgument(value,ref native,allocated,true);Check(setIniBytes(name,native.Bytes));}finally{foreach(IntPtr pointer in allocated)Marshal.FreeHGlobal(pointer);}
        }
        private static void CopyArgument(PhpBytes value,ref NativeValue target,List<IntPtr> allocated) {
            CopyArgument(value,ref target,allocated,false);
        }
        private static void CopyArgument(PhpBytes value,ref NativeValue target,List<IntPtr> allocated,bool cstring) {
            long length=value.Length;
            if(length<0)throw new InvalidOperationException("Negative managed byte length");
            IntPtr pointer=Marshal.AllocHGlobal(new IntPtr(Math.Max(1L,checked(length+(cstring?1L:0L)))));allocated.Add(pointer);
            byte[] buffer=new byte[65536];
            for(long offset=0;offset<length;){int count=(int)Math.Min((long)buffer.Length,length-offset);value.CopyTo(offset,buffer,0,count);if(cstring)for(int i=0;i<count;++i)if(buffer[i]==0)throw new NotSupportedException("Existing NUL-terminated native INI value boundary cannot represent embedded NUL; no INI call was made");Marshal.Copy(buffer,0,new IntPtr(checked(pointer.ToInt64()+offset)),count);offset+=count;}
            if(cstring)Marshal.WriteByte(new IntPtr(checked(pointer.ToInt64()+length)),0);
            target.Type=6;target.Bytes=pointer;target.Length=new UIntPtr(checked((ulong)length));
        }
        public ByteNativeDiagnosticEvent[] ByteDiagnosticEvents {get{
            UInt32 count=diagnosticCount();var result=new ByteNativeDiagnosticEvent[count];
            for(UInt32 i=0;i<count;++i){int level;UIntPtr length;IntPtr pointer=diagnosticGet(i,out level,out length);result[i]=new ByteNativeDiagnosticEvent{Level=level,Message=CopyNativeBytes(pointer,length),Delivered=DELIVERED};}
            return result;
        }}
        // Identifiers retain the existing explicitly UTF-8 C-string contract.
        // PHP string values use PhpBytes; managed text is not silently accepted.
        public ByteScalarInvocation InvokeScalarBytes(string name,object[] arguments,bool strict) {
            OWNER_GUARD
            RequireCString(name,"Native function name",false);
            if(arguments==null)throw new ArgumentNullException("arguments");
            if(!HasFunction(name))throw new MissingMethodException("Native function is not registered: "+name);
            var values=new NativeValue[arguments.Length];var allocated=new List<IntPtr>();
            PENDING_PUSH
            try {
                for(int i=0;i<arguments.Length;++i){object value=arguments[i];
                    if(value==null)values[i].Type=1;
                    else if(value is bool)values[i].Type=(bool)value?3u:2u;
                    else if(value is long){values[i].Type=4;values[i].Integer=(long)value;}
                    else if(value is int){values[i].Type=4;values[i].Integer=(int)value;}
                    else if(value is double){values[i].Type=5;values[i].Real=(double)value;}
                    else if(value is PhpBytes)CopyArgument((PhpBytes)value,ref values[i],allocated);
                    else throw new NotSupportedException("ALL byte native scalar bridge requires PhpBytes for PHP strings; unsupported type "+value.GetType().FullName+" was not passed or converted");
                }
                clear();NativeValue nativeResult;
                int code=invoke("",name,values,(UInt32)values.Length,strict?1:0,out nativeResult);
                PENDING_THROW
                // Copy the borrowed result before another native invocation or End
                // can destroy tls.last, and before argument buffers are released.
                object valueResult=code==0?DecodeBytes(nativeResult):null;
                string className=code==0?null:Ansi(errorClass());
                PhpBytes message=code==0?null:CopyNativeCString(errorMessage());
                return new ByteScalarInvocation{Ok=code==0,Status=code,Value=valueResult,Output=CaptureBytes(output),Diagnostics=CaptureBytes(diagnostics),DiagnosticEvents=ByteDiagnosticEvents,ErrorClass=className,ErrorMessage=message};
            } finally {foreach(IntPtr pointer in allocated)Marshal.FreeHGlobal(pointer);PENDING_POP}
        }
'''

BYTE_SETTER = r'''
        public void SetByteDiagnosticHandler(Action<long,PhpBytes> handler,Action<PhpBytes> outputHandler) {
            if(handler==null)throw new ArgumentNullException("handler");
            if(outputHandler==null)throw new ArgumentNullException("outputHandler");
            if(SynchronousCallbacksEnabled)throw new InvalidOperationException("Callback lease already installed");
            UInt64 id=requestId();if(id==0)throw new InvalidOperationException("Callback lease requires an active native request");
            callbackManagedThread=Thread.CurrentThread.ManagedThreadId;callbackNativeThread=GetCurrentThreadId();callbackRequest=id;
            managedByteDiagnostic=handler;managedByteOutput=outputHandler;diagnosticThunk=ReceiveDiagnostic;outputThunk=ReceiveOutput;callbackRoot=GCHandle.Alloc(this);
            try{Check(setCallbacks(diagnosticThunk,outputThunk,GCHandle.ToIntPtr(callbackRoot)));}
            catch{managedByteDiagnostic=null;managedByteOutput=null;callbackRoot.Free();throw;}
        }
'''


def once(source, old, new):
    if source.count(old) != 1:
        raise AssertionError(("expected exactly one bridge hook", old[:100], source.count(old)))
    return source.replace(old, new)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-directory", required=True)
    options = parser.parse_args()
    destination = Path(options.output_directory).resolve()
    if not destination.is_relative_to(HERE):
        raise SystemExit("Generated source must remain in the owned candidate directory")
    if destination.exists():
        raise SystemExit("Preserve generated/measured source; choose a new revision in this generator")
    destination.mkdir(parents=True)
    records = []
    for mode, (filename, expected, old_namespace, new_namespace) in PINS.items():
        origin = ROOT / "tools/candidates/php-callback-v3_20" / filename
        raw = origin.read_bytes()
        assert hashlib.sha256(raw).hexdigest() == expected
        source = raw.decode("utf-8-sig")
        source = once(source, "namespace " + old_namespace + " {", "namespace " + new_namespace + " {")
        source = once(source, "using System;", "using System;\nusing AllPhp.ByteValues;")
        if "using System.IO;" not in source:
            source = once(source, "using System;", "using System;\nusing System.IO;")
        source = once(source, "    public sealed class Bridge {", TYPES + "    public sealed class Bridge {")
        source = once(source, "        private SetDelegate setIni;", "        private SetDelegate setIni;\n        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int SetBytesDelegate([MarshalAs(UnmanagedType.LPUTF8Str)] string name,IntPtr value);\n        private SetBytesDelegate setIniBytes;")
        source = once(source, 'setIni=Bind<SetDelegate>("all_php_ini_set");', 'setIni=Bind<SetDelegate>("all_php_ini_set");setIniBytes=Bind<SetBytesDelegate>("all_php_ini_set");')
        methods = METHODS.replace("DELIVERED", "diagnosticDelivered(i)!=0" if mode == "callback" else "false")
        methods = methods.replace("OWNER_GUARD", "EnsureCallbackOwner();" if mode == "callback" else "")
        methods = methods.replace("PENDING_PUSH", "pending.Value.Push(new PendingCall());" if mode == "callback" else "")
        methods = methods.replace("PENDING_THROW", "ThrowPending();if(code==2)throw new NotSupportedException(\"Native callback aborted without a saved managed exception\");" if mode == "callback" else "")
        methods = methods.replace("PENDING_POP", "pending.Value.Pop();GC.KeepAlive(diagnosticThunk);GC.KeepAlive(outputThunk);" if mode == "callback" else "")
        source = once(source, "        public ThreadResult[] RunThreadIsolation(){", methods + "\n        public ThreadResult[] RunThreadIsolation(){")
        if mode == "callback":
            source = once(source, "        private Action<long,string> managedDiagnostic;", "        private Action<long,string> managedDiagnostic;\n        private Action<long,PhpBytes> managedByteDiagnostic;\n        private Action<PhpBytes> managedByteOutput;")
            source = once(source, "get{return managedDiagnostic!=null;}", "get{return managedDiagnostic!=null||managedByteDiagnostic!=null;}")
            source = once(source, "string text=new UTF8Encoding(false,true).GetString(Convert.FromBase64String(Base64(bytes,length)));managedDiagnostic(level,text);", "if(managedByteDiagnostic!=null)managedByteDiagnostic(level,CopyNativeBytes(bytes,length));else{string text=new UTF8Encoding(false,true).GetString(Convert.FromBase64String(Base64(bytes,length)));managedDiagnostic(level,text);}")
            source = once(source, "byte[] data=Convert.FromBase64String(Base64(bytes,length));Stream stream=Console.OpenStandardOutput();stream.Write(data,0,data.Length);stream.Flush();", "if(managedByteOutput!=null)managedByteOutput(CopyNativeBytes(bytes,length));else{byte[] data=Convert.FromBase64String(Base64(bytes,length));Stream stream=Console.OpenStandardOutput();stream.Write(data,0,data.Length);stream.Flush();}")
            source = once(source, "Check(clearCallbacks());managedDiagnostic=null;", "Check(clearCallbacks());managedDiagnostic=null;managedByteDiagnostic=null;managedByteOutput=null;")
            source = once(source, "        public void ClearDiagnosticHandler(){", BYTE_SETTER + "\n        public void ClearDiagnosticHandler(){")
        output = destination / filename
        output.write_text(source, encoding="utf-8", newline="\n")
        patch = "".join(difflib.unified_diff(raw.decode("utf-8-sig").splitlines(True), source.splitlines(True), fromfile=origin.as_posix(), tofile=output.as_posix()))
        (destination / (filename + ".patch")).write_text(patch, encoding="utf-8", newline="\n")
        records.append({"mode": mode, "original": origin.as_posix(), "original_sha256": expected, "candidate": output.as_posix(), "candidate_sha256": hashlib.sha256(output.read_bytes()).hexdigest(), "namespace": new_namespace})
    record = {"status": "GENERATED_NOT_BUILT_OR_RUNTIME_VERIFIED", "generator_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(), "canonical_type": "AllPhp.ByteValues.PhpBytes", "core_changes": False, "original_inputs": records}
    (destination / "provenance.json").write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(record))


if __name__ == "__main__":
    main()
