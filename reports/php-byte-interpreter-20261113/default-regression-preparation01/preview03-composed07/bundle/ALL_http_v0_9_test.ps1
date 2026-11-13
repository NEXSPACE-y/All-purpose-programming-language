$ErrorActionPreference='Stop'
$core = Join-Path $HOME 'ALL\ALL.ps1'
$passed=0; $failed=0
function Record([string]$name,[bool]$ok,[string]$detail='') {
    if ($ok) { $script:passed++; Write-Host "PASS [Server]: $name" -ForegroundColor Green }
    else { $script:failed++; Write-Host "FAIL [Server]: $name" -ForegroundColor Red; if($detail){ Write-Host "  $detail" } }
}
function Test-All([string]$code) {
    $writer=[System.IO.StringWriter]::new([System.Globalization.CultureInfo]::InvariantCulture)
    $previous=[Console]::Out
    $err=$null; $lines=@()
    try {
        [Console]::SetOut($writer)
        $lines=@(& $core -Language ALL -Code $code)
    } catch { $err=$_.Exception.Message }
    finally { [Console]::SetOut($previous) }
    $result=[pscustomobject]@{ Output=$writer.ToString(); Error=$err; Pipeline=$lines }
    $writer.Dispose()
    return $result
}
function Get-FreeLoopbackPort {
    $probe=[System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback,0)
    $probe.Start()
    try { return [int]$probe.LocalEndpoint.Port }
    finally { $probe.Stop() }
}
function Start-ALLServer([int]$port,[string]$code) {
    return (Start-Job -ArgumentList $core,($code.Replace('__PORT__',[string]$port)) -ScriptBlock {
        param([string]$core,[string]$source)
        $ErrorActionPreference='Stop'
        & $core -Language ALL -Code $source
    })
}
function Test-HttpWithRetries([int]$port,[string]$source,$job) {
    $deadline=[DateTime]::UtcNow.AddSeconds(12)
    while ($true) {
        $result=Test-All ($source.Replace('__PORT__',[string]$port))
        if ($null -eq $result.Error) { return $result }
        if ($job.State -ne 'Running' -and $job.State -ne 'NotStarted') { return $result }
        if ([DateTime]::UtcNow -ge $deadline) { return $result }
        Start-Sleep -Milliseconds 80
    }
}
$serverCode=@'
fn route(request) {
    if (request["path"] == "/hello") {
        return {"status":200,"body":"Hello from ALL","content_type":"text/plain; charset=utf-8"}
    }
    if (request["path"] == "/unicode") {
        return {"status":200,"body":"こんにちは世界","content_type":"text/plain; charset=utf-8"}
    }
    if (request["path"] == "/json") {
        return {"status":201,"body":request["body"],"content_type":"application/json; charset=utf-8"}
    }
    return {"status":404,"body":"missing"}
}
http_serve(__PORT__, "route", 4)
'@
$job=$null
try {
    $port=Get-FreeLoopbackPort
    $job=Start-ALLServer $port $serverCode
    $a=Test-HttpWithRetries $port 'let r=http_get("http://127.0.0.1:__PORT__/hello");print(r["status"]);print("|");print(r["body"])' $job
    Record 'ALL server GET 200' ($null -eq $a.Error -and $a.Output -ceq '200|Hello from ALL' -and $a.Pipeline.Count -eq 0) "output=$($a.Output); error=$($a.Error)"
    $b=Test-HttpWithRetries $port 'let r=http_get("http://127.0.0.1:__PORT__/unicode");print(r["body"])' $job
    Record 'ALL server UTF-8 response' ($null -eq $b.Error -and $b.Output -ceq 'こんにちは世界') "output=$($b.Output); error=$($b.Error)"
    $c=Test-HttpWithRetries $port 'let r=http_post_json("http://127.0.0.1:__PORT__/json",{"message":"hello"});print(r["status"]);print("|");print(r["body"]);print("|");print(r["content_type"])' $job
    Record 'ALL server POST JSON 201' ($null -eq $c.Error -and $c.Output -ceq '201|{"message":"hello"}|application/json; charset=utf-8') "output=$($c.Output); error=$($c.Error)"
    $d=Test-HttpWithRetries $port 'let r=http_get("http://127.0.0.1:__PORT__/not-found");print(r["status"]);print("|");print(r["body"])' $job
    Record 'ALL server 404 returned' ($null -eq $d.Error -and $d.Output -ceq '404|missing') "output=$($d.Output); error=$($d.Error)"
    [void](Wait-Job -Job $job -Timeout 12)
    Record 'ALL server stops after 4 requests' ($job.State -eq 'Completed') "state=$($job.State); output=$((Receive-Job $job -Keep -ErrorAction SilentlyContinue) -join '|')"
} finally {
    if($null -ne $job) {
        if($job.State -eq 'Running') { Stop-Job $job -ErrorAction SilentlyContinue }
        Remove-Job $job -Force -ErrorAction SilentlyContinue
    }
}
# Verify Japanese alias + Japanese-defined route function.
$jpCode=@'
関数 応答(要求) {
    返す {"status":200,"body":"日本語HTTP", "content_type":"text/plain; charset=utf-8"}
}
HTTP配信(__PORT__, "応答", 1)
'@
$job=$null
try {
    $port=Get-FreeLoopbackPort
    $job=Start-ALLServer $port $jpCode
    $jp=Test-HttpWithRetries $port 'let r=HTTP取得("http://127.0.0.1:__PORT__/jp");print(r["body"])' $job
    [void](Wait-Job $job -Timeout 10)
    Record 'Japanese HTTP配信 and handler' ($null -eq $jp.Error -and $jp.Output -ceq '日本語HTTP' -and $job.State -eq 'Completed') "output=$($jp.Output); error=$($jp.Error); state=$($job.State)"
} finally {
    if($null -ne $job) {
        if($job.State -eq 'Running') { Stop-Job $job -ErrorAction SilentlyContinue }
        Remove-Job $job -Force -ErrorAction SilentlyContinue
    }
}
# Validation should fail BEFORE attempting a socket bind.
$errors=@(
    @{name='Reject zero port'; code='fn route(req){return {"status":200,"body":"ok"}};http_serve(0,"route",1)'; want='http_serve port requires an integer'},
    @{name='Reject missing handler'; code='http_serve(18080,"no_function",1)'; want='Undefined handler'},
    @{name='Reject invalid arity'; code='fn route(req){return {"status":200,"body":"ok"}};http_serve(18080,"route")'; want='http_serve() accepts'},
    @{name='Reject excessive count'; code='fn route(req){return {"status":200,"body":"ok"}};http_serve(18080,"route",21)'; want='http_serve count requires an integer'},
    @{name='Reject handler with two arguments'; code='fn route(a,b){return {"status":200,"body":"ok"}};http_serve(18080,"route",1)'; want='Handler must accept exactly one'}
)
foreach ($e in $errors) {
    $r=Test-All $e.code
    Record $e.name ($null -ne $r.Error -and $r.Error.Contains($e.want) -and $r.Output.Length -eq 0) "error=$($r.Error); output=$($r.Output)"
}
Write-Host "ALL server v0.9: $passed / 11 passed; $failed failed"
if($failed -ne 0) { throw "ALL HTTP server v0.9 regressions: $failed failure(s)" }
