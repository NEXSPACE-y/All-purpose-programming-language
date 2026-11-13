using System;
using System.Collections.ObjectModel;
using System.Globalization;
using System.IO;
using System.Management.Automation;
using System.Management.Automation.Runspaces;

// Diagnostic execution host: same interpreter/native workers, but they return
// their requested status and this outer managed Main owns normal process exit.
internal static class AllNativePhpHost
{
    public static int Main(string[] args)
    {
        Console.OutputEncoding = new System.Text.UTF8Encoding(false);
        Console.InputEncoding = new System.Text.UTF8Encoding(false);
        try
        {
            if (args.Length != 7 || (args[0] != "callback" && args[0] != "legacy"))
                throw new ArgumentException("Expected mode, adapter, source, core, extension, metadata, core hash");
            string worker = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, args[0] + "-return-worker.ps1");
            InitialSessionState initial = InitialSessionState.CreateDefault();
            initial.ExecutionPolicy = Microsoft.PowerShell.ExecutionPolicy.Bypass;
            using (Runspace runspace = RunspaceFactory.CreateRunspace(initial))
            {
                runspace.Open();
                using (PowerShell pipeline = PowerShell.Create())
                {
                    pipeline.Runspace = runspace;
                    // Invoke the trusted worker file so its PSScriptRoot keeps
                    // the same bridge location semantics as powershell -File.
                    pipeline.AddCommand(worker)
                        .AddParameter("AdapterPath", args[1]).AddParameter("SourcePath", args[2])
                        .AddParameter("CorePath", args[3]).AddParameter("ExtensionPath", args[4])
                        .AddParameter("MetadataPath", args[5]).AddParameter("ExpectedCoreHash", args[6]);
                    Collection<PSObject> result = pipeline.Invoke();
                    if (pipeline.HadErrors)
                    {
                        foreach (ErrorRecord error in pipeline.Streams.Error)
                            Console.Error.WriteLine("ALL native host: " + error.Exception.Message);
                        return 1;
                    }
                    if (result.Count != 1 || result[0].Properties["ExitCode"] == null)
                        throw new InvalidOperationException("Worker returned an invalid host result");
                    long status = Convert.ToInt64(result[0].Properties["ExitCode"].Value, CultureInfo.InvariantCulture);
                    return unchecked((int)(uint)status);
                }
            }
        }
        catch (Exception error)
        {
            Console.Error.WriteLine("ALL native host: " + error.Message);
            return 1;
        }
    }
}
