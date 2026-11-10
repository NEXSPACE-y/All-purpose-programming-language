param(
    [Parameter(Mandatory=$true)][string]$BaseUrl,
    [ValidateRange(1,50000)][int]$Requests = 100,
    [ValidateRange(1,128)][int]$ConcurrentClients = 8,
    [string]$ReportPath = "$HOME\ALL_https_report.json"
)
$ErrorActionPreference='Stop'
$uri=[Uri]$BaseUrl
if($uri.Scheme -cne 'https') { throw 'HTTPS URL is required. Do not bypass TLS verification.' }
if($uri.Host -in @('localhost','127.0.0.1','::1')) { throw 'A public DNS host is required for the public HTTPS test.' }
Add-Type -Path (Join-Path $PSScriptRoot 'ALL_HttpLoad.cs') -ReferencedAssemblies 'System.Net.Http.dll' -ErrorAction Stop
$target=$BaseUrl.TrimEnd('/') + '/health'
# HttpClient uses system certificate validation. No insecure callback is configured.
$check=[AllHttpLoad]::Run($target,1,1,15000,'OK')
if($check.Succeeded -ne 1) {
    throw "Public HTTPS check failed: $($check.FirstError)"
}
$stress=[AllHttpLoad]::Run($target,$Requests,$ConcurrentClients,15000,'OK')
$report=[ordered]@{
    tool='ALL professional validation / public HTTPS';
    started_utc=[DateTime]::UtcNow.ToString('o'); url=$target;
    tls_validation='OS trust chain and hostname checked by HttpClient; no bypass';
    checks=[ordered]@{
        https_get_200=($check.Succeeded -eq 1);
        response_body_ok=($check.Succeeded -eq 1);
        load_requested=$stress.Requested;
        load_succeeded=$stress.Succeeded;
        http_errors=$stress.HttpErrors;
        network_errors=$stress.NetworkErrors;
        p95_ms=$stress.P95Ms;
        p99_ms=$stress.P99Ms;
        requests_per_second=$stress.RequestsPerSecond;
        first_error=$stress.FirstError
    };
    notes=@('Run from a different network to verify actual internet reachability.',
      'This tests an already deployed HTTPS endpoint; it does not install Caddy, configure DNS, or open ports.',
      'Backend TLS terminates at the reverse proxy as configured; it is not native ALL TLS.')
}
$destination=[IO.Path]::GetFullPath($ReportPath)
$parent=[IO.Path]::GetDirectoryName($destination)
if(-not [IO.Directory]::Exists($parent)) { [void][IO.Directory]::CreateDirectory($parent) }
[IO.File]::WriteAllText($destination,(ConvertTo-Json -InputObject $report -Depth 8),[Text.UTF8Encoding]::new($false))
Write-Host ("HTTPS validated: {0}; load ok={1}/{2}; p95={3:N1}ms; RPS={4:N2}" -f $target,$stress.Succeeded,$stress.Requested,$stress.P95Ms,$stress.RequestsPerSecond) -ForegroundColor Green
Write-Host "Report: $destination"
if($stress.Succeeded -ne $stress.Requested) { throw 'HTTPS load had failed requests' }
