# Isolated backend tests + actual requests concurrent in the gateway.
$ErrorActionPreference='Stop'
$root=$PSScriptRoot
$testRoot=Join-Path ([IO.Path]::GetTempPath()) ('ALL_POOL_TEST_'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
$serverFile=Join-Path $testRoot 'server.all'
$stop=Join-Path $testRoot 'stop.flag'
[IO.File]::WriteAllText($serverFile,@'
fn handler(request) {
    if (request["path"] == "/health") { return {"status":200,"body":"OK"} }
    return {"status":404,"body":"missing"}
}
http_serve_live(18888,"handler")
'@,[Text.UTF8Encoding]::new($false))
$psExe=(Get-Process -Id $PID).Path
$port=Get-Random -Minimum 30000 -Maximum 39000
$workerStart=$port+1
$server=$null
$passed=0;$failed=0
function Case([string]$label,[bool]$success,[string]$detail=''){
    if($success){$script:passed++;Write-Host "PASS [Pool]: $label" -ForegroundColor Green}
    else{$script:failed++;Write-Host "FAIL [Pool]: $label $detail" -ForegroundColor Red}
}
try {
    $psi=[Diagnostics.ProcessStartInfo]::new()
    $psi.FileName=$psExe
    $psi.Arguments='-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+(Join-Path $HOME 'ALL/ALL_serve_pool.ps1')+'" -File "'+$serverFile+'" -StopFile "'+$stop+'" -Workers 4 -Port '+$port+' -WorkerStartPort '+$workerStart
    $psi.UseShellExecute=$false
    $psi.CreateNoWindow=$true
    $server=[Diagnostics.Process]::Start($psi)
    $base='http://127.0.0.1:'+$port
    $ready=$false
    $client=[Net.WebClient]::new()
    try {
        for($i=0;$i -lt 100;$i++){
            if($server.HasExited){break}
            try {if($client.DownloadString($base+'/health') -eq 'OK'){$ready=$true;break}}catch{}
            Start-Sleep -Milliseconds 250
        }
        Case 'gateway becomes ready' $ready
        if(-not $ready){throw 'ALL worker pool failed to start'}
    } finally {$client.Dispose()}
    Add-Type -AssemblyName System.Net.Http
    $http=[Net.Http.HttpClient]::new()
    try {
        $tasks=[System.Collections.Generic.List[System.Threading.Tasks.Task]]::new()
        for($i=0;$i -lt 32;$i++){
            [void]$tasks.Add($http.GetAsync($base+'/health'))
        }
        [Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]$tasks.ToArray(),30000) | Out-Null
        $codes=@($tasks | ForEach-Object { [int]$_.Result.StatusCode })
        Case '32 concurrently requested responses succeeded' (@($codes|Where-Object {$_ -eq 200}).Count -eq 32)
        $workers=@($tasks | ForEach-Object {$_.Result.Headers.GetValues('X-ALL-Worker') | Select-Object -First 1} | Sort-Object -Unique)
        Case 'more than one independent ALL worker served requests' ($workers.Count -gt 1) ('workers='+($workers -join ','))
        foreach($task in $tasks){$task.Result.Dispose()}
        $notFound=$http.GetAsync($base+'/unknown').GetAwaiter().GetResult()
        Case '404 is forwarded' ([int]$notFound.StatusCode -eq 404)
        $notFound.Dispose()
    } finally {$http.Dispose()}
    [IO.File]::WriteAllText($stop,'stop')
    Case 'operator stop terminates gateway' ($server.WaitForExit(15000))
} finally {
    if($server -and -not $server.HasExited){$server.Kill();$server.WaitForExit()|Out-Null}
    if($server){$server.Dispose()}
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host "ALL concurrent pool: $passed / 5 passed; $failed failed"
if($failed){throw "Concurrent HTTP pool failed: $failed"}
