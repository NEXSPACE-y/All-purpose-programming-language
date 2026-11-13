#Requires -Version 5.1
param(
    [ValidateRange(1024,65535)][int]$BackendPort = 18888,
    [ValidateRange(1024,65535)][int]$HttpsPort = 18443,
    [ValidateRange(1,100)][int]$Requests = 20,
    [string]$CaddyExe = '',
    [string]$ReportPath = "$HOME\ALL_local_https_report.json"
)
$ErrorActionPreference = 'Stop'

function Assert-FreeLoopbackPort([int]$port) {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $port)
    try { $listener.Start() }
    catch { throw "Port $port is already in use. Stop the other service or select an unused port." }
    finally { $listener.Stop() }
}

if ($BackendPort -eq $HttpsPort) { throw 'BackendPort and HttpsPort must differ.' }
if (-not (Test-Path -LiteralPath (Join-Path $HOME 'ALL\ALL.ps1'))) { throw 'ALL is not installed at $HOME\ALL\ALL.ps1' }
if ([string]::IsNullOrWhiteSpace($CaddyExe)) {
    $exe = Get-Command 'caddy.exe' -ErrorAction SilentlyContinue
    if ($null -ne $exe) { $CaddyExe = $exe.Source }
    else {
        foreach ($candidate in @((Join-Path $PSScriptRoot 'caddy.exe'), (Join-Path $HOME 'Downloads\caddy.exe'))) {
            if (Test-Path -LiteralPath $candidate) { $CaddyExe = $candidate; break }
        }
    }
}
if ([string]::IsNullOrWhiteSpace($CaddyExe) -or -not (Test-Path -LiteralPath $CaddyExe)) {
    throw 'caddy.exe not found. Download the official Windows build from https://caddyserver.com/download, place caddy.exe beside this script, then rerun. No public domain is required.'
}
$CaddyExe = (Resolve-Path -LiteralPath $CaddyExe).Path
if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) { throw 'curl.exe is required (Windows 10/11 normally includes it).' }
Assert-FreeLoopbackPort $BackendPort
Assert-FreeLoopbackPort $HttpsPort

$runDir = Join-Path ([IO.Path]::GetTempPath()) ('ALL_TLS_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $runDir -Force | Out-Null
$storage = (Join-Path $runDir 'storage').Replace('\','/')
$caddyFile = Join-Path $runDir 'Caddyfile'
$stopFile = Join-Path $runDir 'stop.flag'
$runnerFile = Join-Path $runDir 'ALL_backend.ps1'
$rootCert = Join-Path (Join-Path $runDir 'storage') 'pki\authorities\local\root.crt'
$responseFile = Join-Path $runDir 'response.txt'
$startedAt = [DateTime]::UtcNow.ToString('o')
$backend = $null
$caddy = $null
$success = 0
$errorDetail = $null

# These are separate loopback services: ALL is HTTP backend, Caddy terminates TLS.
$caddyText = @"
{
    admin off
    persist_config off
    skip_install_trust
    auto_https disable_redirects
    storage file_system "$storage"
}
https://127.0.0.1:$HttpsPort {
    bind 127.0.0.1
    tls internal
    reverse_proxy 127.0.0.1:$BackendPort
}
"@
[IO.File]::WriteAllText($caddyFile, $caddyText, [Text.UTF8Encoding]::new($false))
# Generate a UTF-8 BOM runner for Windows PowerShell 5.1.
$runnerSource = @(
    'param([int]$Port, [string]$StopPath)',
    '$ErrorActionPreference="Stop"',
    '$env:ALL_HTTP_STOP_FILE=$StopPath',
    '$env:ALL_HTTP_ACCESS_LOG="0"',
    '$source = @"',
    '関数 API(要求) {',
    '    もし (要求["path"] == "/health") {',
    '        返す {"status":200,"body":"OK"}',
    '    }',
    '    返す {"status":404,"body":"Not found"}',
    '}',
    'HTTP常時配信(__PORT__,"API")',
    '"@',
    '$source=$source.Replace("__PORT__",[string]$Port)',
    'try { & (Join-Path $HOME "ALL\ALL.ps1") -Language ALL -Code $source }',
    'catch { [Console]::Error.WriteLine($_.Exception.Message); exit 1 }'
) -join "`r`n"
[IO.File]::WriteAllText($runnerFile, $runnerSource, [Text.UTF8Encoding]::new($true))

try {
    $exe = Join-Path $PSHOME 'powershell.exe'
    $argText = '-NoLogo -NoProfile -ExecutionPolicy Bypass -File "' + $runnerFile + '" -Port ' + $BackendPort + ' -StopPath "' + $stopFile + '"'
    $backend = Start-Process -FilePath $exe -ArgumentList $argText -PassThru -WindowStyle Hidden -RedirectStandardError (Join-Path $runDir 'backend.err.log')
    $ready = $false
    for ($i=0; $i -lt 80; $i++) {
        $backend.Refresh()
        if ($backend.HasExited) { throw "ALL backend exited unexpectedly. See $runDir\backend.err.log" }
        try {
            $r = Invoke-WebRequest -Uri "http://127.0.0.1:$BackendPort/health" -UseBasicParsing -TimeoutSec 2
            if ($r.StatusCode -eq 200 -and $r.Content.Trim() -ceq 'OK') { $ready=$true; break }
        } catch {}
        Start-Sleep -Milliseconds 100
    }
    if (-not $ready) { throw 'ALL local HTTP backend did not become ready.' }
    Write-Host 'PASS: ALL HTTP backend is responding (200 OK)' -ForegroundColor Green

    $caddyArgs = 'run --config "' + $caddyFile + '" --adapter caddyfile'
    $caddy = Start-Process -FilePath $CaddyExe -ArgumentList $caddyArgs -WorkingDirectory $runDir -PassThru -WindowStyle Hidden -RedirectStandardError (Join-Path $runDir 'caddy.err.log')
    $certReady = $false
    for ($i=0; $i -lt 100; $i++) {
        $caddy.Refresh()
        if ($caddy.HasExited) { throw "Caddy exited unexpectedly. See $runDir\caddy.err.log" }
        if (Test-Path -LiteralPath $rootCert) { $certReady=$true; break }
        Start-Sleep -Milliseconds 100
    }
    if (-not $certReady) { throw "Caddy local CA root was not generated: $rootCert" }
    Write-Host 'PASS: Caddy issued a local TLS certificate (no OS trust changes)' -ForegroundColor Green

    $uri = "https://127.0.0.1:$HttpsPort/health"
    for ($i=1; $i -le $Requests; $i++) {
        $httpCode = & curl.exe --ssl-revoke-best-effort --noproxy '*' --silent --show-error --max-time 10 --cacert $rootCert --output $responseFile --write-out '%{http_code}' $uri
        if ($LASTEXITCODE -ne 0) { throw "TLS certificate/handshake verification failed on request $i (curl exit $LASTEXITCODE)." }
        $body = [IO.File]::ReadAllText($responseFile,[Text.Encoding]::UTF8).Trim()
        if ($httpCode -ne '200' -or $body -cne 'OK') { throw "HTTP mismatch on request $i (code=$httpCode, body=$body)" }
        $success++
    }
    Write-Host "PASS: Local HTTPS TLS certificate + hostname checked, $success/$Requests requests returned 200/OK" -ForegroundColor Green
} catch {
    $errorDetail = $_.Exception.Message
    Write-Host "FAIL: $errorDetail" -ForegroundColor Red
} finally {
    if ($null -ne $backend) {
        try {
            $backend.Refresh()
            if (-not $backend.HasExited) {
                [IO.File]::WriteAllText($stopFile, 'stop', [Text.UTF8Encoding]::new($false))
                if (-not $backend.WaitForExit(10000)) { $backend.Kill(); [void]$backend.WaitForExit(5000) }
            }
        } catch {}
    }
    if ($null -ne $caddy) {
        try {
            $caddy.Refresh()
            if (-not $caddy.HasExited) { $caddy.Kill(); [void]$caddy.WaitForExit(5000) }
        } catch {}
    }
    $report = [ordered]@{
        test='ALL local HTTPS through Caddy'; started_utc=$startedAt
        https_uri="https://127.0.0.1:$HttpsPort/health"
        all_backend="http://127.0.0.1:$BackendPort/health"
        certificate_validation='curl --cacert with dedicated local CA; no insecure flag; hostname checked'
        success_count=$success; requested_count=$Requests; error=$errorDetail
        local_tls_passed=([string]::IsNullOrEmpty($errorDetail) -and $success -eq $Requests)
        public_internet_https_verified=$false
        note='Proves TLS reverse-proxy integration on loopback only. Public DNS, publicly trusted certificates, and off-network connectivity remain untested.'
    }
    $outFile = [IO.Path]::GetFullPath($ReportPath)
    $parent=[IO.Path]::GetDirectoryName($outFile)
    if (-not [IO.Directory]::Exists($parent)) { [void][IO.Directory]::CreateDirectory($parent) }
    [IO.File]::WriteAllText($outFile,(ConvertTo-Json -InputObject $report -Depth 6),[Text.UTF8Encoding]::new($false))
    Write-Host "Report: $outFile"
    if ([string]::IsNullOrEmpty($errorDetail)) {
        Remove-Item -LiteralPath $runDir -Force -Recurse -ErrorAction SilentlyContinue
    } else {
        Write-Warning "Diagnostic logs remain at $runDir"
    }
}
if ($errorDetail) { throw $errorDetail }
Write-Host 'Local TLS: PASS. Public HTTPS: NOT TESTED.' -ForegroundColor Yellow
