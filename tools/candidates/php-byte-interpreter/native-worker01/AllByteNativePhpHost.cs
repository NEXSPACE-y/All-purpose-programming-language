using System;
using System.Collections.ObjectModel;
using System.Globalization;
using System.IO;
using System.Management.Automation;
using System.Management.Automation.Runspaces;

// The worker returns its requested status; Main disposes the runspace before
// normal process exit. No Environment.Exit or stock PHP execution is used.
internal static class AllByteNativePhpHost {
    public static int Main(string[] args) {
        Console.OutputEncoding=new System.Text.UTF8Encoding(false);
        Console.InputEncoding=new System.Text.UTF8Encoding(false);
        try {
            if(args.Length!=12||(args[0]!="callback"&&args[0]!="legacy"))throw new ArgumentException("mode adapter source core extension metadata coreHash runtime bridge runtimeHash bridgeHash adapterHash");
            string worker=Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"byte-return-worker.ps1");
            InitialSessionState initial=InitialSessionState.CreateDefault();initial.ExecutionPolicy=Microsoft.PowerShell.ExecutionPolicy.Bypass;
            using(Runspace runspace=RunspaceFactory.CreateRunspace(initial)) {
                runspace.Open();
                using(PowerShell pipeline=PowerShell.Create()) {
                    pipeline.Runspace=runspace;
                    pipeline.AddCommand(worker).AddParameter("Mode",args[0]).AddParameter("AdapterPath",args[1]).AddParameter("SourcePath",args[2])
                        .AddParameter("CorePath",args[3]).AddParameter("ExtensionPath",args[4]).AddParameter("MetadataPath",args[5])
                        .AddParameter("ExpectedCoreHash",args[6]).AddParameter("RuntimePath",args[7]).AddParameter("BridgePath",args[8])
                        .AddParameter("ExpectedRuntimeHash",args[9]).AddParameter("ExpectedBridgeHash",args[10]).AddParameter("ExpectedAdapterHash",args[11]);
                    Collection<PSObject> result=pipeline.Invoke();
                    if(pipeline.HadErrors){foreach(ErrorRecord error in pipeline.Streams.Error)Console.Error.WriteLine("ALL byte native host: "+error.Exception.Message);return 1;}
                    if(result.Count!=1||result[0].Properties["ExitCode"]==null)throw new InvalidOperationException("Worker returned an invalid host result");
                    long status=Convert.ToInt64(result[0].Properties["ExitCode"].Value,CultureInfo.InvariantCulture);
                    return unchecked((int)(uint)status);
                }
            }
        }catch(Exception error){Console.Error.WriteLine("ALL byte native host: "+error.Message);return 1;}
    }
}
