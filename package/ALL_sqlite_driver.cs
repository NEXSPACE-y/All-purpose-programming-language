using System;
using System.IO;
using System.Text;
using System.Collections;
using System.Collections.Generic;
using System.Security.Cryptography;
using System.Runtime.InteropServices;

// SQLite integration for ALL on Windows PowerShell 5.1 / Windows 11.
// Windows provides winsqlite3.dll. This class does not translate or emulate SQL;
// queries and transactions are executed by SQLite itself.
public sealed class AllSqliteDriver {
    private static class N {
        const string Lib="winsqlite3.dll";
        [DllImport(Lib, CallingConvention=CallingConvention.Cdecl)] internal static extern int sqlite3_open_v2(IntPtr filename, out IntPtr db, int flags, IntPtr vfs);
        [DllImport(Lib, CallingConvention=CallingConvention.Cdecl)] internal static extern int sqlite3_close(IntPtr db);
        [DllImport(Lib, CallingConvention=CallingConvention.Cdecl)] internal static extern int sqlite3_busy_timeout(IntPtr db,int ms);
        [DllImport(Lib, CallingConvention=CallingConvention.Cdecl)] internal static extern IntPtr sqlite3_errmsg(IntPtr db);
        [DllImport(Lib, CallingConvention=CallingConvention.Cdecl)] internal static extern int sqlite3_prepare_v2(IntPtr db,IntPtr sql,int n,out IntPtr stmt,out IntPtr tail);
        [DllImport(Lib, CallingConvention=CallingConvention.Cdecl)] internal static extern int sqlite3_step(IntPtr stmt);
        [DllImport(Lib, CallingConvention=CallingConvention.Cdecl)] internal static extern int sqlite3_finalize(IntPtr stmt);
        [DllImport(Lib, CallingConvention=CallingConvention.Cdecl)] internal static extern int sqlite3_bind_parameter_count(IntPtr stmt);
        [DllImport(Lib, CallingConvention=CallingConvention.Cdecl)] internal static extern int sqlite3_bind_null(IntPtr stmt,int i);
        [DllImport(Lib, CallingConvention=CallingConvention.Cdecl)] internal static extern int sqlite3_bind_int64(IntPtr stmt,int i,long v);
        [DllImport(Lib, CallingConvention=CallingConvention.Cdecl)] internal static extern int sqlite3_bind_double(IntPtr stmt,int i,double v);
        [DllImport(Lib, CallingConvention=CallingConvention.Cdecl)] internal static extern int sqlite3_bind_text(IntPtr stmt,int i,IntPtr v,int len,IntPtr destructor);
        [DllImport(Lib, CallingConvention=CallingConvention.Cdecl)] internal static extern int sqlite3_column_count(IntPtr stmt);
        [DllImport(Lib, CallingConvention=CallingConvention.Cdecl)] internal static extern int sqlite3_column_type(IntPtr stmt,int i);
        [DllImport(Lib, CallingConvention=CallingConvention.Cdecl)] internal static extern long sqlite3_column_int64(IntPtr stmt,int i);
        [DllImport(Lib, CallingConvention=CallingConvention.Cdecl)] internal static extern double sqlite3_column_double(IntPtr stmt,int i);
        [DllImport(Lib, CallingConvention=CallingConvention.Cdecl)] internal static extern IntPtr sqlite3_column_name(IntPtr stmt,int i);
        [DllImport(Lib, CallingConvention=CallingConvention.Cdecl)] internal static extern IntPtr sqlite3_column_text(IntPtr stmt,int i);
        [DllImport(Lib, CallingConvention=CallingConvention.Cdecl)] internal static extern int sqlite3_column_bytes(IntPtr stmt,int i);
        [DllImport(Lib, CallingConvention=CallingConvention.Cdecl)] internal static extern int sqlite3_exec(IntPtr db,IntPtr sql,IntPtr callback,IntPtr arg,out IntPtr error);
        [DllImport(Lib, CallingConvention=CallingConvention.Cdecl)] internal static extern void sqlite3_free(IntPtr ptr);
        [DllImport(Lib, CallingConvention=CallingConvention.Cdecl)] internal static extern int sqlite3_changes(IntPtr db);
        [DllImport(Lib, CallingConvention=CallingConvention.Cdecl)] internal static extern long sqlite3_last_insert_rowid(IntPtr db);
    }
    public sealed class Result {
        public bool IsQuery;
        public int Changed;
        public long LastInsertId;
        public Dictionary<string,object>[] Rows;
    }
    private readonly IntPtr db;
    private AllSqliteDriver(IntPtr h) {db=h;}
    private static readonly UTF8Encoding Utf8 = new UTF8Encoding(false,true);
    private static IntPtr PtrUtf8(string value) {
        byte[] bytes=Utf8.GetBytes(value+"\0");
        IntPtr p=Marshal.AllocHGlobal(bytes.Length);
        Marshal.Copy(bytes,0,p,bytes.Length);
        return p;
    }
    private static string FromPtr(IntPtr pointer,int length) {
        if(pointer==IntPtr.Zero || length==0) return "";
        if(length<0 || length>8*1024*1024) throw new InvalidOperationException("SQLite text size limit");
        byte[] bytes=new byte[length];Marshal.Copy(pointer,bytes,0,length);
        return Utf8.GetString(bytes);
    }
    private static string ZeroString(IntPtr pointer) {
        if(pointer==IntPtr.Zero) return "";
        int len=0;
        while(len<8192 && Marshal.ReadByte(pointer,len)!=0) len++;
        if(len==8192) throw new InvalidOperationException("SQLite error text too long");
        return FromPtr(pointer,len);
    }
    private static InvalidOperationException Failure(IntPtr h,int code) {
        return new InvalidOperationException("ALL SQL Error "+code+": "+ZeroString(N.sqlite3_errmsg(h)));
    }
    private static void Check(IntPtr h,int rc) {if(rc!=0)throw Failure(h,rc);}
    private static string ValidatePath(string path) {
        if(String.IsNullOrWhiteSpace(path) || path.Length>1024)throw new ArgumentException("Invalid SQL database path");
        string full=Path.GetFullPath(path);
        string ext=Path.GetExtension(full);
        if(!String.Equals(ext,".sqlite",StringComparison.OrdinalIgnoreCase) && !String.Equals(ext,".db",StringComparison.OrdinalIgnoreCase))
            throw new ArgumentException("SQL database must have .sqlite or .db extension");
        return full;
    }
    private static AllSqliteDriver Open(string path) {
        IntPtr ptr=PtrUtf8(ValidatePath(path));
        IntPtr h=IntPtr.Zero;
        try {int rc=N.sqlite3_open_v2(ptr,out h,0x00000002|0x00000004|0x00010000,IntPtr.Zero);
            if(rc!=0){string reason=h!=IntPtr.Zero?ZeroString(N.sqlite3_errmsg(h)):"Cannot open SQLite database";
                if(h!=IntPtr.Zero)N.sqlite3_close(h);
                throw new InvalidOperationException("ALL SQL Open Error: "+reason);
            }
            Check(h,N.sqlite3_busy_timeout(h,5000));return new AllSqliteDriver(h);
        } finally {Marshal.FreeHGlobal(ptr);}
    }
    private void Close(){N.sqlite3_close(db);}
    private void Bind(IntPtr stmt,object[] args) {
        int n=N.sqlite3_bind_parameter_count(stmt);
        if(n!=args.Length)throw new ArgumentException("ALL SQL Error: expected "+n+" SQL parameters, received "+args.Length);
        for(int i=0;i<n;i++) {
            object v=args[i];int rc=0;
            if(v==null)rc=N.sqlite3_bind_null(stmt,i+1);
            else if(v is bool)rc=N.sqlite3_bind_int64(stmt,i+1,((bool)v)?1:0);
            else if(v is string) {
                byte[] b=Utf8.GetBytes((string)v);
                IntPtr p=Marshal.AllocHGlobal(Math.Max(1,b.Length));
                try {if(b.Length>0)Marshal.Copy(b,0,p,b.Length);
                    rc=N.sqlite3_bind_text(stmt,i+1,p,b.Length,new IntPtr(-1));
                } finally {Marshal.FreeHGlobal(p);}
            }
            else if(v is decimal) {
                decimal d=(decimal)v;
                if(d>=long.MinValue && d<=long.MaxValue && Decimal.Truncate(d)==d)
                    rc=N.sqlite3_bind_int64(stmt,i+1,(long)d);
                else rc=N.sqlite3_bind_double(stmt,i+1,(double)d);
            }
            else if(v is long || v is int || v is short || v is byte)
                rc=N.sqlite3_bind_int64(stmt,i+1,Convert.ToInt64(v));
            else if(v is double || v is float)
                rc=N.sqlite3_bind_double(stmt,i+1,Convert.ToDouble(v));
            else throw new ArgumentException("ALL SQL Error: unsupported SQL parameter type");
            Check(db,rc);
        }
    }
    private Result Execute(string sql,object[] args,int maxRows=10000) {
        if(String.IsNullOrWhiteSpace(sql) || sql.Length>65536)throw new ArgumentException("Invalid SQL statement length");
        IntPtr zSql=PtrUtf8(sql);IntPtr stmt=IntPtr.Zero;IntPtr tail=IntPtr.Zero;
        try {
            Check(db,N.sqlite3_prepare_v2(db,zSql,-1,out stmt,out tail));
            if(stmt==IntPtr.Zero)throw new ArgumentException("SQL statement was empty");
            // Reject a second statement, not semicolons within quoted string literals.
            int consumed=tail.ToInt64()>=zSql.ToInt64()?(int)(tail.ToInt64()-zSql.ToInt64()):0;
            byte[] text=Utf8.GetBytes(sql);
            for(int k=consumed;k<text.Length;k++)if(!Char.IsWhiteSpace((char)text[k]))
                throw new ArgumentException("ALL SQL Error: one statement per call");
            Bind(stmt,args);
            int columns=N.sqlite3_column_count(stmt);
            var result=new Result();result.IsQuery=columns>0;
            var rows=new List<Dictionary<string,object>>();
            while(true) {
                int rc=N.sqlite3_step(stmt);
                if(rc==101)break; // SQLITE_DONE
                if(rc!=100)throw Failure(db,rc); // SQLITE_ROW
                if(!result.IsQuery)throw new InvalidOperationException("Unexpected SQLite row");
                if(rows.Count>=maxRows)throw new InvalidOperationException("ALL SQL Error: query exceeded row limit");
                var row=new Dictionary<string,object>(StringComparer.Ordinal);
                for(int i=0;i<columns;i++) {
                    string name=ZeroString(N.sqlite3_column_name(stmt,i));
                    if(row.ContainsKey(name))throw new InvalidOperationException("ALL SQL Error: duplicate column alias "+name);
                    int type=N.sqlite3_column_type(stmt,i);object value=null;
                    switch(type) {
                        case 1:value=N.sqlite3_column_int64(stmt,i);break;
                        case 2:value=N.sqlite3_column_double(stmt,i);break;
                        case 3:value=FromPtr(N.sqlite3_column_text(stmt,i),N.sqlite3_column_bytes(stmt,i));break;
                        case 5:break;
                        case 4:throw new InvalidOperationException("ALL SQL Error: BLOB output not yet supported");
                        default:throw new InvalidOperationException("Unknown SQLite column type");
                    }
                    row[name]=value;
                }
                rows.Add(row);
            }
            result.Rows=rows.ToArray();result.Changed=N.sqlite3_changes(db);result.LastInsertId=N.sqlite3_last_insert_rowid(db);
            return result;
        } finally {if(stmt!=IntPtr.Zero)N.sqlite3_finalize(stmt);Marshal.FreeHGlobal(zSql);}
    }
    public static Result Run(string path,string sql,object[] args) {
        AllSqliteDriver con=Open(path);
        try {return con.Execute(sql,args==null?new object[0]:args);} finally {con.Close();}
    }
    private void ExecScript(string sql) {
        if (String.IsNullOrWhiteSpace(sql) || sql.Length>1024*1024)
            throw new ArgumentException("ALL SQL Error: invalid migration length");
        IntPtr code=PtrUtf8(sql),error=IntPtr.Zero;
        try {
            int rc=N.sqlite3_exec(db,code,IntPtr.Zero,IntPtr.Zero,out error);
            if(rc!=0)throw new InvalidOperationException("ALL SQL migration error " + rc + ": " + (error!=IntPtr.Zero?ZeroString(error):ZeroString(N.sqlite3_errmsg(db))));
        } finally { if(error!=IntPtr.Zero)N.sqlite3_free(error); Marshal.FreeHGlobal(code); }
    }
    public static int Migrate(string path,string directory) {
        if(String.IsNullOrWhiteSpace(directory))throw new ArgumentException("ALL SQL Error: migration directory required");
        string full=Path.GetFullPath(directory);
        if(!Directory.Exists(full))throw new DirectoryNotFoundException(full);
        string[] scripts=Directory.GetFiles(full,"*.sql",SearchOption.TopDirectoryOnly);
        Array.Sort(scripts,StringComparer.Ordinal);
        if(scripts.Length>512)throw new InvalidOperationException("ALL SQL Error: maximum 512 migration files");
        AllSqliteDriver con=Open(path);
        bool transaction=false;
        try {
            con.Execute("BEGIN IMMEDIATE",new object[0]);transaction=true;
            con.Execute("CREATE TABLE IF NOT EXISTS __all_migrations (version TEXT PRIMARY KEY, sha256 TEXT NOT NULL, applied_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP)",new object[0]);
            int applied=0;
            foreach(string file in scripts) {
                string version=Path.GetFileName(file);
                byte[] bytes=File.ReadAllBytes(file);
                if(bytes.Length>1024*1024)throw new InvalidOperationException("ALL SQL Error: migration too large: "+version);
                string sha;
                using(var h=SHA256.Create())sha=BitConverter.ToString(h.ComputeHash(bytes)).Replace("-","").ToLowerInvariant();
                var previous=con.Execute("SELECT sha256 FROM __all_migrations WHERE version=?",new object[]{version});
                if(previous.Rows.Length>0) {
                    string oldHash=(string)previous.Rows[0]["sha256"];
                    if(!String.Equals(oldHash,sha,StringComparison.OrdinalIgnoreCase))
                        throw new InvalidOperationException("ALL SQL Error: migration checksum changed: "+version);
                    continue;
                }
                string script=Utf8.GetString(bytes);
                if(script.Length>0 && script[0]=='\uFEFF')script=script.Substring(1);
                con.ExecScript(script);
                con.Execute("INSERT INTO __all_migrations(version,sha256) VALUES(?,?)",new object[]{version,sha});
                applied++;
            }
            con.Execute("COMMIT",new object[0]);transaction=false;
            return applied;
        }catch{
            if(transaction)try{con.Execute("ROLLBACK",new object[0]);}catch{}
            throw;
        } finally {con.Close();}
    }
    public static int Transaction(string path,object[] operations) {
        if(operations==null || operations.Length==0 || operations.Length>128)throw new ArgumentException("ALL SQL Error: require 1..128 transaction statements");
        AllSqliteDriver con=Open(path);bool started=false;
        try {
            con.Execute("BEGIN IMMEDIATE",new object[0]);started=true;
            int count=0;
            foreach(object op in operations){
                IDictionary entry=op as IDictionary;
                if(entry==null || !entry.Contains("sql"))throw new ArgumentException("ALL SQL Error: invalid transaction operation");
                string sql=entry["sql"] as string;
                object[] parameters=entry.Contains("params")?(entry["params"] as object[]):null;
                if(parameters==null)parameters=new object[0];
                Result r=con.Execute(sql,parameters);
                if(r.IsQuery)throw new ArgumentException("ALL SQL Error: transaction operation must not return rows");
                count+=r.Changed;
            }
            con.Execute("COMMIT",new object[0]);started=false;return count;
        }catch{
            if(started)try{con.Execute("ROLLBACK",new object[0]);}catch{}
            throw;
        }finally{con.Close();}
    }
}
