using System;
using System.Collections.ObjectModel;
using System.Globalization;
using System.IO;
using System.Management.Automation;
using System.Management.Automation.Runspaces;

// ALL-owned command-line host. The interpreter runs in this process; no PHP
// executable is loaded or spawned. User arguments are objects, not shell code.
internal static class AllPhpCli
{
    public static int Main(string[] args)
    {
        Console.OutputEncoding = new System.Text.UTF8Encoding(false);
        Console.InputEncoding = new System.Text.UTF8Encoding(false);
        string root = AppDomain.CurrentDomain.BaseDirectory;
        try
        {
            string script = Path.Combine(root, "AllPhpCli.ps1");
            string adapter = Path.Combine(root, "ALL_PHP_adapter.ps1");
            if (!File.Exists(script) || !File.Exists(adapter))
                throw new InvalidOperationException("Incomplete ALL PHP CLI build directory");
            using (Runspace runspace = RunspaceFactory.CreateRunspace())
            {
                runspace.Open();
                using (PowerShell pipeline = PowerShell.Create())
                {
                    pipeline.Runspace = runspace;
                    pipeline.AddScript(File.ReadAllText(script, new System.Text.UTF8Encoding(false, true)))
                        .AddParameter("CliArguments", args)
                        .AddParameter("AdapterPath", adapter);
                    Collection<PSObject> result = pipeline.Invoke();
                    if (pipeline.HadErrors)
                    {
                        foreach (ErrorRecord error in pipeline.Streams.Error)
                            Console.Error.WriteLine("ALL PHP CLI host: " + error.Exception.Message);
                        return 1;
                    }
                    if (result.Count != 1 || result[0].Properties["ExitCode"] == null)
                        throw new InvalidOperationException("CLI pipeline returned an invalid host result");
                    long code = Convert.ToInt64(result[0].Properties["ExitCode"].Value, CultureInfo.InvariantCulture);
                    return unchecked((int)(uint)code);
                }
            }
        }
        catch (Exception error)
        {
            Console.Error.WriteLine("ALL PHP CLI host: " + error.Message);
            return 1;
        }
    }
}
