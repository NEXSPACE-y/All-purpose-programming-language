using System;
using System.IO;
using System.Net;
using System.Threading;
using System.Collections.Generic;

// ALL HTTP gateway: concurrent request dispatch to *separate* ALL interpreters.
// Each backend has its own process and no shared interpreter variables.
// Gateway only binds to loopback. Put an HTTPS proxy in front for internet use.
public static class AllConcurrentGateway {
    static int[] ports;
    static int cursor;
    static SemaphoreSlim active;
    static long accepted,completed,failed;
    static readonly object logLock=new object();
    public static void Run(int port, int[] workers, string stopFile,int maxInFlight) {
        if(port<1024 || port>65535 || workers==null || workers.Length<2 || workers.Length>32 || maxInFlight<1 || maxInFlight>1024)
            throw new ArgumentException("Invalid gateway configuration");
        ports=workers;cursor=0;accepted=completed=failed=0;
        active=new SemaphoreSlim(maxInFlight,maxInFlight);
        var listener=new HttpListener();
        listener.Prefixes.Add("http://127.0.0.1:"+port.ToString()+"/");
        listener.Start();
        try {
            while(!File.Exists(stopFile)) {
                IAsyncResult waiting=listener.BeginGetContext(null,null);
                while(!waiting.AsyncWaitHandle.WaitOne(100)) {
                    if(File.Exists(stopFile))break;
                }
                if(File.Exists(stopFile)) { try{listener.Stop();}catch{} break; }
                HttpListenerContext context;
                try {context=listener.EndGetContext(waiting);} catch(HttpListenerException) {break;}
                finally {waiting.AsyncWaitHandle.Close();}
                Interlocked.Increment(ref accepted);
                if(!active.Wait(0)) {
                    RespondText(context,503,"Service Unavailable");
                    Interlocked.Increment(ref failed);
                    continue;
                }
                int selected=Interlocked.Increment(ref cursor);
                int workerIndex=((selected-1)%ports.Length+ports.Length)%ports.Length;
                ThreadPool.QueueUserWorkItem(state=>{
                    try { Relay((HttpListenerContext)state,ports[workerIndex],workerIndex);Interlocked.Increment(ref completed);}
                    catch(Exception ex) {
                        Interlocked.Increment(ref failed);
                        try {RespondText((HttpListenerContext)state,502,"Bad Gateway");}catch{}
                        lock(logLock)Console.Error.WriteLine("ALL_GATEWAY error="+ex.GetType().Name+" detail="+ex.Message);
                    } finally {active.Release();}
                },context);
            }
            // Finish accepted in-flight requests before exit; fail if deadline exceeded.
            var deadline=DateTime.UtcNow.AddSeconds(30);
            while(active.CurrentCount<maxInFlight && DateTime.UtcNow<deadline)Thread.Sleep(50);
        } finally {
            try{listener.Stop();}catch{}
            listener.Close();
            Console.Error.WriteLine("ALL_GATEWAY accepted="+accepted+" completed="+completed+" failed="+failed);
            active.Dispose();
        }
    }
    static void RespondText(HttpListenerContext ctx,int code,string text) {
        byte[] bytes=System.Text.Encoding.UTF8.GetBytes(text);
        ctx.Response.StatusCode=code;ctx.Response.ContentType="text/plain; charset=utf-8";
        ctx.Response.ContentLength64=bytes.Length;
        try {ctx.Response.OutputStream.Write(bytes,0,bytes.Length);} finally {ctx.Response.Close();}
    }
    static void Relay(HttpListenerContext ctx,int backend,int workerIndex) {
        // Fixed upstream (localhost) prohibits gateway request SSRF.
        string path=ctx.Request.RawUrl;
        if(String.IsNullOrEmpty(path)||!path.StartsWith("/",StringComparison.Ordinal)||path.Length>4096)
            throw new ArgumentException("Invalid request path");
        var target=new Uri("http://127.0.0.1:"+backend.ToString()+path);
        var request=(HttpWebRequest)WebRequest.Create(target);
        request.Method=ctx.Request.HttpMethod;
        request.AllowAutoRedirect=false;
        request.Timeout=15000; request.ReadWriteTimeout=15000;
        request.KeepAlive=false;request.Proxy=null;
        string contentType=ctx.Request.ContentType;
        if(!String.IsNullOrWhiteSpace(contentType))request.ContentType=contentType;
        if(!ctx.Request.HasEntityBody && (request.Method=="POST" || request.Method=="PUT" || request.Method=="PATCH"))request.ContentLength=0;
        if(ctx.Request.HasEntityBody) {
            // Do not buffer unbounded user-controlled request bodies.
            byte[] buffer=new byte[8192];long total=0;
            using(var temp=new MemoryStream()) {
                while(true) {
                    int n=ctx.Request.InputStream.Read(buffer,0,buffer.Length);
                    if(n==0)break;
                    total+=n;if(total>1048576)throw new InvalidOperationException("Request body exceeds 1 MiB");
                    temp.Write(buffer,0,n);
                }
                request.ContentLength=total;
                using(Stream upstream=request.GetRequestStream()){
                    temp.Position=0;temp.CopyTo(upstream);
                }
            }
        }
        HttpWebResponse response=null;
        try {
            try {response=(HttpWebResponse)request.GetResponse();}
            catch(WebException ex) {
                response=ex.Response as HttpWebResponse;
                if(response==null)throw;
            }
            ctx.Response.StatusCode=(int)response.StatusCode;
            string type=response.ContentType;
            if(!String.IsNullOrWhiteSpace(type))ctx.Response.ContentType=type;
            ctx.Response.Headers["X-ALL-Worker"]=(workerIndex+1).ToString();
            using(Stream upstream=response.GetResponseStream()) {
                byte[] buffer=new byte[8192];int n;long sum=0;
                while((n=upstream.Read(buffer,0,buffer.Length))>0) {
                    sum+=n;if(sum>1048576)throw new InvalidOperationException("Upstream response exceeds 1 MiB");
                    ctx.Response.OutputStream.Write(buffer,0,n);
                }
            }
        } finally { if(response!=null)response.Close();try{ctx.Response.Close();}catch{} }
    }
}
