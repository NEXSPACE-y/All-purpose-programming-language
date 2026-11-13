$ErrorActionPreference='Stop'
$core = Join-Path $HOME 'ALL\ALL.ps1'
$cli = Join-Path $HOME 'ALL\ALL_cli.ps1'
$pass=0; $fail=0
function Record([string]$label,[bool]$ok,[string]$why='') {
    if ($ok) { $script:pass++; Write-Host "PASS [CLI+HTTP]: $label" -ForegroundColor Green }
    else { $script:fail++; Write-Host "FAIL [CLI+HTTP]: $label" -ForegroundColor Red; if ($why) { Write-Host "  $why" } }
}
function Capture([scriptblock]$action) {
    $capture=[System.IO.StringWriter]::new([System.Globalization.CultureInfo]::InvariantCulture)
    $before=[Console]::Out
    $problem=''; $pipeline=@()
    try { [Console]::SetOut($capture); $pipeline = @(& $action) }
    catch { $problem=$_.Exception.Message }
    finally { [Console]::SetOut($before) }
    $result=[pscustomobject]@{Output=$capture.ToString();Error=$problem;Pipeline=$pipeline}
    $capture.Dispose()
    return $result
}
# CLI smoke / argument transfer / env restore / error codes by terminating errors.
$h=Capture { & $cli -Command help }
Record 'CLI help' ($h.Error -eq '' -and $h.Output.Contains('Usage:')) $h.Error
$v=Capture { & $cli -Command version }
Record 'CLI version' ($v.Error -eq '' -and $v.Output.Contains('CLI v1.1')) $v.Error
$empty=Capture { & $core -Language ALL -Code 'print(len(cli_args()))' }
Record 'Empty CLI argument list' ($empty.Error -eq '' -and $empty.Output -ceq '0') ($empty.Output+' '+$empty.Error)
$folder=Join-Path ([System.IO.Path]::GetTempPath()) ('all_cli_http_v11_'+[guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $folder)
try {
    $file=Join-Path $folder '引数.all'
    [System.IO.File]::WriteAllText($file, 'let args=引数一覧();println(len(args));println(args[0]);println(args[1])', [System.Text.UTF8Encoding]::new($false))
    $r=Capture { & $cli -Command run -File $file -ScriptArgs @('日本語','two') }
    Record 'CLI file + Japanese arguments' ($r.Error -eq '' -and $r.Output -ceq "2`n日本語`ntwo`n") ($r.Output+' '+$r.Error)
    $envTest=Capture { & $core -Language ALL -Code 'print(len(cli_args()))' }
    Record 'CLI environment restored' ($envTest.Error -eq '' -and $envTest.Output -ceq '0') ($envTest.Output+' '+$envTest.Error)
    $bad=Capture { & $cli -Command run -File (Join-Path $folder 'missing.all') }
    Record 'CLI missing file rejected' ($bad.Error -ne '') $bad.Error
    $badLang=Capture { & $cli -Command run -File $file -Language PHP -ScriptArgs @('x') }
    Record 'CLI PHP arguments rejected' ($badLang.Error.Contains('supported only')) $badLang.Error
    $jp=Capture { & $core -Language ALL -Code 'print(len(引数一覧()))' }
    Record 'Japanese CLI builtin alias' ($jp.Error -eq '' -and $jp.Output -ceq '0') ($jp.Output+' '+$jp.Error)
} finally { Remove-Item -LiteralPath $folder -Recurse -Force -ErrorAction SilentlyContinue }
# Validate new server entrypoint without opening sockets.
$invalid=@(
    @{Name='Batch rejects zero count';Code='fn route(req){return {"status":200,"body":"ok"}};http_serve_batch(18888,"route",0)';Want='http_serve count'},
    @{Name='Batch rejects count >256';Code='fn route(req){return {"status":200,"body":"ok"}};http_serve_batch(18888,"route",257)';Want='http_serve count'},
    @{Name='Batch requires handler';Code='http_serve_batch(18888,"missing",10)';Want='Undefined handler'},
    @{Name='Batch rejects invalid argument count';Code='http_serve_batch(18888,"route")';Want='http_serve_batch() accepts'}
)
foreach ($test in $invalid) {
    $r=Capture { & $core -Language ALL -Code $test.Code }
    Record $test.Name ($r.Error.Contains($test.Want)) $r.Error
}
function FreePort {
    $server=[System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback,0)
    $server.Start()
    try { return [int]$server.LocalEndpoint.Port } finally { $server.Stop() }
}
function GetHttp([int]$port,[string]$path) {
    $req=[System.Net.HttpWebRequest][System.Net.WebRequest]::Create("http://127.0.0.1:$port$path")
    $req.Timeout=3000; $req.ReadWriteTimeout=3000; $req.KeepAlive=$false
    $response=$null
    try {
        try { $response=[System.Net.HttpWebResponse]$req.GetResponse() }
        catch {
            $webError = $_.Exception
            while ($null -ne $webError -and $webError -isnot [System.Net.WebException]) {
                $webError = $webError.InnerException
            }
            if ($null -eq $webError -or $webError.Response -isnot [System.Net.HttpWebResponse]) { throw }
            $response = [System.Net.HttpWebResponse]$webError.Response
        }
        $reader=[System.IO.StreamReader]::new($response.GetResponseStream(),[System.Text.Encoding]::UTF8)
        try { $body=$reader.ReadToEnd() } finally { $reader.Dispose() }
        return [pscustomobject]@{Status=[int]$response.StatusCode;Body=$body}
    } finally {
        if ($null -ne $response) { $response.Dispose() }
        $req.Abort()
    }
}
$port=FreePort
$program=@'
fn route(req) {
    if (req["path"] == "/boom") { throw "handler failed" }
    return {"status":200,"body":req["path"]}
}
http_serve_batch(__PORT__,"route",34)
'@
$program=$program.Replace('__PORT__',[string]$port)
$job=Start-Job -ArgumentList $core,$program -ScriptBlock {
    param([string]$engine,[string]$src)
    $ErrorActionPreference='Stop'
    & $engine -Language ALL -Code $src
}
try {
    $ready=$false; $first=$null
    for($try=0;$try -lt 60;$try++) {
        try { $first=GetHttp $port '/start'; $ready=$true; break }
        catch {
            if($job.State -eq 'Failed' -or $job.State -eq 'Completed') { break }
            Start-Sleep -Milliseconds 100
        }
    }
    if(-not $ready) { throw 'Batch service did not become ready' }
    Record 'Batch initial GET' ($first.Status -eq 200 -and $first.Body -ceq '/start')
    $errors=0
    foreach($n in 1..30) {
        $r=GetHttp $port ("/r"+$n)
        if ($r.Status -ne 200 -or $r.Body -cne ("/r"+$n)) { $errors++ }
    }
    Record 'Batch handles 30 sequential requests' ($errors -eq 0) "mismatches=$errors"
    $failure=GetHttp $port '/boom'
    Record 'Handler exception returns 500' ($failure.Status -eq 500 -and $failure.Body -ceq 'Internal Server Error') "status=$($failure.Status) body=$($failure.Body)"
    # Malformed request is isolated to its connection; parser does not crash server.
    $tcp=[System.Net.Sockets.TcpClient]::new()
    try {
        $tcp.Connect('127.0.0.1',$port)
        $tcp.ReceiveTimeout=3000; $tcp.SendTimeout=3000
        $st=$tcp.GetStream()
        $raw=[System.Text.Encoding]::ASCII.GetBytes("TRACE / HTTP/1.1`r`nHost: localhost`r`n`r`n")
        $st.Write($raw,0,$raw.Length)
        $bytes=[byte[]]::new(2048)
        $replyBuilder=[System.Text.StringBuilder]::new()
        while ($replyBuilder.Length -lt 2048) {
            $received=$st.Read($bytes,0,$bytes.Length)
            if ($received -le 0) { break }
            [void]$replyBuilder.Append([System.Text.Encoding]::ASCII.GetString($bytes,0,$received))
            if ($replyBuilder.ToString().Contains("`r`n`r`n")) { break }
        }
        $reply=$replyBuilder.ToString()
        Record 'Malformed request returns 400' ($reply.StartsWith('HTTP/1.1 400')) $reply
    } finally { $tcp.Dispose() }
    $last=GetHttp $port '/after-error'
    Record 'Server survives bad requests' ($last.Status -eq 200 -and $last.Body -ceq '/after-error') "status=$($last.Status) body=$($last.Body)"
    [void](Wait-Job -Job $job -Timeout 10)
    Record 'Batch exits after exact request limit' ($job.State -eq 'Completed') "job=$($job.State)"
} catch {
    Record 'Batch live test setup' $false $_.Exception.Message
} finally {
    if($job.State -eq 'Running') { Stop-Job -Job $job -ErrorAction SilentlyContinue }
    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
}
Write-Host "CLI+HTTP v1.1: $pass passed; $fail failed"
if($fail -ne 0) { throw "ALL CLI/HTTP v1.1 failed: $fail" }
