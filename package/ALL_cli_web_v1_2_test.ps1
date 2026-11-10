$ErrorActionPreference='Stop'
$core=Join-Path $HOME 'ALL\ALL.ps1'
$hostScript=Join-Path $HOME 'ALL\ALL_cli_host.ps1'
$pass=0; $fail=0
function Record([string]$name,[bool]$ok,[string]$detail='') {
    if($ok) { $script:pass++; Write-Host "PASS [CLI+WEB]: $name" -ForegroundColor Green }
    else { $script:fail++; Write-Host "FAIL [CLI+WEB]: $name" -ForegroundColor Red; if($detail) { Write-Host "  $detail" } }
}
function Capture([scriptblock]$action) {
    $writer=[System.IO.StringWriter]::new([System.Globalization.CultureInfo]::InvariantCulture)
    $old=[Console]::Out; $errorText=''
    try { [Console]::SetOut($writer); & $action | Out-Null }
    catch { $errorText=$_.Exception.Message }
    finally { [Console]::SetOut($old) }
    $data=[pscustomobject]@{Output=$writer.ToString();Error=$errorText}
    $writer.Dispose()
    return $data
}
function FreePort {
    $listener=[System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback,0)
    $listener.Start()
    try { return [int]$listener.LocalEndpoint.Port } finally { $listener.Stop() }
}
function Request([int]$port,[string]$path) {
    $req=[System.Net.HttpWebRequest][System.Net.WebRequest]::Create("http://127.0.0.1:$port$path")
    $req.Timeout=2000; $req.ReadWriteTimeout=2000; $req.KeepAlive=$false
    $response=$null
    try {
        try { $response=[System.Net.HttpWebResponse]$req.GetResponse() }
        catch {
            $ex=$_.Exception
            while($null -ne $ex -and $ex -isnot [System.Net.WebException]) { $ex=$ex.InnerException }
            if($null -eq $ex -or $ex.Response -isnot [System.Net.HttpWebResponse]) { throw }
            $response=[System.Net.HttpWebResponse]$ex.Response
        }
        $reader=[System.IO.StreamReader]::new($response.GetResponseStream(),[System.Text.Encoding]::UTF8)
        try { $body=$reader.ReadToEnd() } finally { $reader.Dispose() }
        return [pscustomobject]@{Code=[int]$response.StatusCode;Body=$body}
    } finally {
        if($null -ne $response) { $response.Dispose() }
        $req.Abort()
    }
}
# No network access is used by negative tests.
$invalid=@(
    @{Name='Live missing handler'; Code='http_serve_live(18888,"missing")'; Want='Undefined handler'},
    @{Name='Live zero port'; Code='fn route(req){return {"status":200,"body":"ok"}};http_serve_live(0,"route")'; Want='http_serve port'},
    @{Name='Live invalid argument count'; Code='http_serve_live(18888)'; Want='http_serve_live() accepts'},
    @{Name='Live Japanese alias missing handler'; Code='HTTP常時配信(18888,"missing")'; Want='Undefined handler'}
)
foreach($test in $invalid) {
    $result=Capture { & $core -Language ALL -Code $test.Code }
    Record $test.Name ($result.Error.Contains($test.Want)) $result.Error
}
# Use an external child process so exit does not terminate the parent test runner.
$psExe=(Get-Command powershell.exe -ErrorAction Stop).Source
$psi=[System.Diagnostics.ProcessStartInfo]::new()
$psi.FileName=$psExe
$psi.Arguments='-NoLogo -NoProfile -ExecutionPolicy Bypass -File "'+$hostScript+'" help'
$psi.UseShellExecute=$false
$psi.RedirectStandardOutput=$true
$psi.RedirectStandardError=$true
$proc=[System.Diagnostics.Process]::Start($psi)
try {
    $out=$proc.StandardOutput.ReadToEnd(); $err=$proc.StandardError.ReadToEnd(); $proc.WaitForExit(10000) | Out-Null
    Record 'Native entrypoint help exit=0' ($proc.HasExited -and $proc.ExitCode -eq 0 -and $out.Contains('ALL command v1.2')) ($out+' '+$err)
} finally { if(-not $proc.HasExited) { $proc.Kill() }; $proc.Dispose() }
$psi.Arguments='-NoLogo -NoProfile -ExecutionPolicy Bypass -File "'+$hostScript+'" run'
$proc=[System.Diagnostics.Process]::Start($psi)
try {
    $out=$proc.StandardOutput.ReadToEnd(); $err=$proc.StandardError.ReadToEnd(); $proc.WaitForExit(10000) | Out-Null
    Record 'Native entrypoint invalid usage exit=1' ($proc.HasExited -and $proc.ExitCode -eq 1 -and $err.Contains('Usage')) ($out+' '+$err)
} finally { if(-not $proc.HasExited) { $proc.Kill() }; $proc.Dispose() }
# A stop-signal file permits a long-running server to be controlled without a remote admin endpoint.
$port=FreePort
$folder=Join-Path ([System.IO.Path]::GetTempPath()) ('all_live_v12_'+[guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $folder)
$stopFile=Join-Path $folder 'shutdown.signal'
$program=@'
fn route(req) {
    if (req["path"] == "/boom") { throw "server-side handler error" }
    return {"status":200,"body":req["path"]}
}
http_serve_live(__PORT__,"route")
'@
$program=$program.Replace('__PORT__',[string]$port)
$job=Start-Job -ArgumentList $core,$program,$stopFile -ScriptBlock {
    param($engine,$src,$stop)
    $ErrorActionPreference='Stop'
    [Environment]::SetEnvironmentVariable('ALL_HTTP_STOP_FILE',$stop,'Process')
    try { & $engine -Language ALL -Code $src } finally {
        [Environment]::SetEnvironmentVariable('ALL_HTTP_STOP_FILE',$null,'Process')
    }
}
try {
    $ready=$false
    for($attempt=0; $attempt -lt 60; $attempt++) {
        try { $first=Request $port '/ready'; $ready=$true; break }
        catch { if($job.State -ne 'Running') { break }; Start-Sleep -Milliseconds 100 }
    }
    if(-not $ready) { throw 'Live HTTP server failed to start' }
    Record 'Live starts and answers GET' ($first.Code -eq 200 -and $first.Body -ceq '/ready')
    $bad=0
    foreach($n in 1..260) {
        $res=Request $port ("/item"+$n)
        if($res.Code -ne 200 -or $res.Body -cne ("/item"+$n)) { $bad++ }
    }
    Record 'Live accepts >256 requests' ($bad -eq 0) "mismatches=$bad"
    $failure=Request $port '/boom'
    Record 'Live handler failure gives 500' ($failure.Code -eq 500)
    $after=Request $port '/after'
    Record 'Live survives handler exception' ($after.Code -eq 200 -and $after.Body -ceq '/after')
    [System.IO.File]::WriteAllText($stopFile,'stop',[System.Text.UTF8Encoding]::new($false))
    $null=Wait-Job -Job $job -Timeout 8
    Record 'Live responds to operator stop file' ($job.State -eq 'Completed') "state=$($job.State)"
} catch {
    Record 'Live integration setup' $false $_.Exception.Message
} finally {
    if($job.State -eq 'Running') { Stop-Job -Job $job -ErrorAction SilentlyContinue }
    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $folder -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host "ALL CLI/WEB v1.2: $pass passed; $fail failed"
if($fail -ne 0) { throw "ALL CLI/WEB v1.2 failed: $fail" }
