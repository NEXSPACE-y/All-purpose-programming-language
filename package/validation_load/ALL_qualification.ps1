param(
    [ValidateRange(1024,65535)][int]$Port = 18888,
    [ValidateRange(1,500000)][int]$LoadRequests = 500,
    [ValidateRange(1,128)][int]$MaxClients = 16,
    [ValidateRange(0,10080)][int]$SoakMinutes = 5,
    [ValidateRange(1,120)][int]$SoakIntervalSeconds = 2,
    [ValidateRange(100,120000)][int]$TimeoutMs = 15000,
    [string]$ReportPath = "$HOME\ALL_qualification_report.json"
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not (Test-Path -LiteralPath (Join-Path $HOME 'ALL\ALL.ps1'))) {
    throw 'ALL not installed: ALL.ps1 not found'
}
Add-Type -Path (Join-Path $root 'ALL_HttpLoad.cs') -ReferencedAssemblies 'System.Net.Http.dll' -ErrorAction Stop
$folder = Join-Path ([System.IO.Path]::GetTempPath()) ('ALL_QA_' + [guid]::NewGuid().ToString('N'))
$null = New-Item -Path $folder -ItemType Directory -Force
$stopPath = Join-Path $folder 'stop.signal'
$runner = Join-Path $root 'ALL_local_runner.ps1'
$exe = Join-Path $PSHOME 'powershell.exe'
$portUrl = "http://127.0.0.1:$Port/health"
# Refuse to attach to a server already listening on the test port.
$portCheck = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback,$Port)
try { $portCheck.Start() } catch { throw "Local test port $Port is in use; choose an unused port with -Port." } finally { $portCheck.Stop() }
$startedAt = [DateTime]::UtcNow.ToString('o')
$measurements = [System.Collections.Generic.List[object]]::new()
$stress = [System.Collections.Generic.List[object]]::new()
$soakTotal = 0; $soakFailed = 0; $soakMaxLatencyMs = 0.0
$failure = $null
$process = $null
$stoppedGracefully = $false
try {
    $argsText = '-NoLogo -NoProfile -ExecutionPolicy Bypass -File "' + $runner + '" -Port ' + $Port + ' -StopPath "' + $stopPath + '"'
    $process = Start-Process -FilePath $exe -ArgumentList $argsText -PassThru -WindowStyle Hidden
    $ready = $false
    for ($attempt=0; $attempt -lt 100; $attempt++) {
        $process.Refresh()
        if ($process.HasExited) { throw "ALL server exited during startup: $($process.ExitCode)" }
        $probe = [AllHttpLoad]::Run($portUrl,1,1,2000,'OK')
        if ($probe.Succeeded -eq 1) { $ready=$true; break }
        Start-Sleep -Milliseconds 100
    }
    if (-not $ready) { throw "ALL server did not become ready at $portUrl" }
    Write-Host "ALL QA local server ready PID=$($process.Id) URL=$portUrl" -ForegroundColor Green
    # 1) simultaneous client contention & 3) load/latency/error rate
    $levels = @(1,4,$MaxClients) | Select-Object -Unique
    foreach ($clients in $levels) {
        $r = [AllHttpLoad]::Run($portUrl,$LoadRequests,[int]$clients,$TimeoutMs,'OK')
        $stress.Add([pscustomobject]@{
            clients=$clients; requested=$r.Requested; succeeded=$r.Succeeded;
            failed=$r.HttpErrors+$r.NetworkErrors; http_errors=$r.HttpErrors;
            network_errors=$r.NetworkErrors; elapsed_ms=$r.ElapsedMs;
            throughput_rps=$r.RequestsPerSecond;
            p50_ms=$r.P50Ms; p95_ms=$r.P95Ms; p99_ms=$r.P99Ms; max_ms=$r.MaxMs;
            first_error=$r.FirstError
        })
        Write-Host ("Concurrent={0} ok={1}/{2} RPS={3:N2} p95={4:N1}ms failures={5}" -f $clients,$r.Succeeded,$r.Requested,$r.RequestsPerSecond,$r.P95Ms,($r.HttpErrors+$r.NetworkErrors))
    }
    # 2) time-bounded soak and process memory profile
    $soakWatch=[System.Diagnostics.Stopwatch]::StartNew()
    $soakDeadline=[DateTime]::UtcNow.AddMinutes($SoakMinutes)
    $lastPrinted=[DateTime]::UtcNow
    while ([DateTime]::UtcNow -lt $soakDeadline) {
        $process.Refresh()
        if ($process.HasExited) { $soakFailed++; $failure='Server exited during soak'; break }
        $one=[AllHttpLoad]::Run($portUrl,1,1,$TimeoutMs,'OK')
        $soakTotal++
        if ($one.Succeeded -ne 1) { $soakFailed++ }
        if ($one.MaxMs -gt $soakMaxLatencyMs) { $soakMaxLatencyMs=$one.MaxMs }
        $measurements.Add([pscustomobject]@{
            elapsed_sec=[Math]::Round($soakWatch.Elapsed.TotalSeconds,1)
            working_set_bytes=[long]$process.WorkingSet64
            private_bytes=[long]$process.PrivateMemorySize64
            response_ms=[Math]::Round($one.MaxMs,2)
            success=($one.Succeeded -eq 1)
        })
        if (([DateTime]::UtcNow - $lastPrinted).TotalSeconds -ge 60) {
            Write-Host ("Soak {0:N1} minutes, ok={1}/{2}, working_set={3:N1} MB" -f ($soakWatch.Elapsed.TotalMinutes),($soakTotal-$soakFailed),$soakTotal,($process.WorkingSet64 / 1MB))
            $lastPrinted = [DateTime]::UtcNow
        }
        if ([DateTime]::UtcNow -lt $soakDeadline) { Start-Sleep -Seconds $SoakIntervalSeconds }
    }
    $soakWatch.Stop()
} catch {
    $failure = $_.Exception.Message
    Write-Host ('QA ERROR: ' + $failure) -ForegroundColor Red
} finally {
    if ($null -ne $process) {
        try {
            if (-not $process.HasExited) {
                [System.IO.File]::WriteAllText($stopPath,'stop',[System.Text.UTF8Encoding]::new($false))
                $stoppedGracefully = $process.WaitForExit(15000)
                if (-not $stoppedGracefully) { $process.Kill(); $process.WaitForExit(5000) | Out-Null }
            } else { $stoppedGracefully = $true }
        } catch { $failure = if ($failure) { $failure } else { $_.Exception.Message } }
    }
    $minMem=0L; $maxMem=0L; $growth=0L
    if ($measurements.Count -gt 0) {
        $minMem=[long](($measurements | Measure-Object -Property working_set_bytes -Minimum).Minimum)
        $maxMem=[long](($measurements | Measure-Object -Property working_set_bytes -Maximum).Maximum)
        $growth=[long]$measurements[$measurements.Count-1].working_set_bytes-[long]$measurements[0].working_set_bytes
    }
    $report = [ordered]@{
        tool='ALL professional validation / local'; started_utc=$startedAt;
        all_version='v1.2 installed (user environment)';
        test_scope='Loopback only; synchronous server; no public TLS test here';
        port=$Port; process_id=if($process){$process.Id}else{$null};
        concurrent_load=@($stress.ToArray());
        soak=[ordered]@{
            minutes_requested=$SoakMinutes; attempted=$soakTotal; failed=$soakFailed;
            max_latency_ms=$soakMaxLatencyMs; working_set_min_bytes=$minMem;
            working_set_max_bytes=$maxMem; working_set_end_minus_start_bytes=$growth;
            memory_samples=@($measurements.ToArray())
        };
        service_graceful_exit=$stoppedGracefully;
        test_error=$failure;
        notes=@('A zero-error run proves only the tested workload and duration.',
            'ALL v1.2 server accepts and handles requests sequentially. Client concurrency is not server parallelism.',
            'Memory reports refer to the host PowerShell process; they are not language-only allocation.')
    }
    $destination=[System.IO.Path]::GetFullPath($ReportPath)
    $parent=[System.IO.Path]::GetDirectoryName($destination)
    if (-not [System.IO.Directory]::Exists($parent)) { [void][System.IO.Directory]::CreateDirectory($parent) }
    $json=ConvertTo-Json -InputObject $report -Depth 12
    [System.IO.File]::WriteAllText($destination,$json,[System.Text.UTF8Encoding]::new($false))
    Write-Host "Report: $destination"
    Remove-Item -LiteralPath $folder -Recurse -Force -ErrorAction SilentlyContinue
}
if ($failure) { throw $failure }
Write-Host 'Local qualification run finished. Evaluate latency, errors, and memory before claiming professional readiness.' -ForegroundColor Yellow
