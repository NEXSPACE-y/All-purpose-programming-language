using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;

public sealed class AllHttpResult
{
    public int Requested { get; set; }
    public int ConcurrentClients { get; set; }
    public int Succeeded;
    public int HttpErrors;
    public int NetworkErrors;
    public long ElapsedMs { get; set; }
    public double RequestsPerSecond { get; set; }
    public double P50Ms { get; set; }
    public double P95Ms { get; set; }
    public double P99Ms { get; set; }
    public double MaxMs { get; set; }
    public string FirstError { get; set; }
    public string Url { get; set; }
}
public static class AllHttpLoad
{
    private static int nextIndex;
    private static readonly object ErrorLock = new object();
    private static double Percentile(double[] values, double percentage)
    {
        if (values.Length == 0) return 0.0;
        var x = ((double)(values.Length - 1)) * percentage;
        var a = (int)Math.Floor(x);
        var b = (int)Math.Ceiling(x);
        return values[a] + (values[b] - values[a]) * (x - a);
    }
    private static async Task Worker(HttpClient client, string url, string expectedBody, double[] durations, AllHttpResult result)
    {
        while (true)
        {
            int index = Interlocked.Increment(ref nextIndex) - 1;
            if (index >= durations.Length) return;
            var watch = Stopwatch.StartNew();
            try
            {
                using (var request = new HttpRequestMessage(HttpMethod.Get, url))
                {
                    request.Headers.ConnectionClose = true;
                    using (var response = await client.SendAsync(request, HttpCompletionOption.ResponseContentRead).ConfigureAwait(false))
                    {
                        string body = await response.Content.ReadAsStringAsync().ConfigureAwait(false);
                        if ((int)response.StatusCode == 200 && (expectedBody == null || body == expectedBody))
                            Interlocked.Increment(ref result.Succeeded);
                        else
                        {
                            Interlocked.Increment(ref result.HttpErrors);
                            lock (ErrorLock)
                            {
                                if (result.FirstError == null)
                                    result.FirstError = "HTTP " + (int)response.StatusCode + " body=" + body;
                            }
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                Interlocked.Increment(ref result.NetworkErrors);
                lock (ErrorLock)
                {
                    if (result.FirstError == null) result.FirstError = ex.GetType().Name + ": " + ex.Message;
                }
            }
            finally
            {
                watch.Stop();
                durations[index] = watch.Elapsed.TotalMilliseconds;
            }
        }
    }
    public static AllHttpResult Run(string url, int requests, int concurrency, int timeoutMs, string expectedBody)
    {
        if (requests < 1 || requests > 500000 || concurrency < 1 || concurrency > 256 || timeoutMs < 100)
            throw new ArgumentException("Out-of-range test parameter");
        var result = new AllHttpResult { Requested=requests, ConcurrentClients=concurrency, Url=url };
        var durations = new double[requests];
        var handler = new HttpClientHandler();
        handler.UseProxy = false;
        handler.AllowAutoRedirect = false;
        using (handler)
        using (var client = new HttpClient(handler, false))
        {
            client.Timeout = TimeSpan.FromMilliseconds(timeoutMs);
            Interlocked.Exchange(ref nextIndex, 0);
            var tasks = new List<Task>();
            var total = Stopwatch.StartNew();
            for (int i=0; i < Math.Min(concurrency, requests); i++)
                tasks.Add(Task.Run(async () => await Worker(client, url, expectedBody, durations, result).ConfigureAwait(false)));
            Task.WaitAll(tasks.ToArray());
            total.Stop();
            result.ElapsedMs = total.ElapsedMilliseconds;
        }
        Array.Sort(durations);
        result.MaxMs = durations[durations.Length-1];
        result.P50Ms = Percentile(durations, .50);
        result.P95Ms = Percentile(durations, .95);
        result.P99Ms = Percentile(durations, .99);
        result.RequestsPerSecond = result.ElapsedMs > 0 ? (1000.0 * requests / result.ElapsedMs) : 0;
        return result;
    }
}
