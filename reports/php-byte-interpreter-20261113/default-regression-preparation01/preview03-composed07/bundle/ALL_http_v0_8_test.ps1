$ErrorActionPreference = 'Stop'
$core = Join-Path $HOME 'ALL\ALL.ps1'
$cases = @(ConvertFrom-Json -InputObject (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'ALL_http_v0_8_cases.json') -Raw -Encoding UTF8))
if ($cases.Count -eq 1 -and $cases[0] -is [array]) { $cases = @($cases[0]) }
if ($cases.Count -ne 16) { throw "ALL HTTP: Expected 16 tests; got $($cases.Count)" }
$workspace = Join-Path ([System.IO.Path]::GetTempPath()) ('allhttp08_' + [guid]::NewGuid().ToString('N'))
[void][System.IO.Directory]::CreateDirectory($workspace)
$ready = Join-Path $workspace 'ready.txt'
$job = $null
$pass=0; $fail=0
try {
    # Reserve a temporary loopback port. The child job hosts a fixed-response
    # fixture; no public listener and no dependency on an external website.
    $probe = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback,0)
    $probe.Start()
    $port = [int]$probe.LocalEndpoint.Port
    $probe.Stop()
    $job = Start-Job -ArgumentList $port,$ready,10 -ScriptBlock {
        param([int]$port,[string]$ready,[int]$requests)
        $ErrorActionPreference='Stop'
        $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback,$port)
        $listener.Start()
        try {
            [System.IO.File]::WriteAllText($ready,'ready',[System.Text.Encoding]::ASCII)
            $utf8 = [System.Text.UTF8Encoding]::new($false,$true)
            for($i=0;$i -lt $requests;$i++) {
                $task=$listener.AcceptTcpClientAsync()
                if (-not $task.Wait(12000)) { throw 'Fixture: Client timeout' }
                $client=$task.Result
                try {
                    $client.ReceiveTimeout=6000
                    $client.SendTimeout=6000
                    $stream=$client.GetStream()
                    $headerBytes=[System.Collections.Generic.List[byte]]::new()
                    while($true) {
                        $b=$stream.ReadByte()
                        if($b -lt 0) { throw 'Fixture: EOF in HTTP headers' }
                        [void]$headerBytes.Add([byte]$b)
                        $n=$headerBytes.Count
                        if($n -gt 8192) { throw 'Fixture: Header too long' }
                        if($n -ge 4 -and $headerBytes[$n-4] -eq 13 -and $headerBytes[$n-3] -eq 10 -and
                            $headerBytes[$n-2] -eq 13 -and $headerBytes[$n-1] -eq 10) { break }
                    }
                    $headerText=[System.Text.Encoding]::ASCII.GetString($headerBytes.ToArray())
                    $lines=$headerText.Split([string[]]@("`r`n"),[System.StringSplitOptions]::None)
                    $requestParts=$lines[0].Split(' ')
                    $verb=$requestParts[0]
                    $path=$requestParts[1]
                    $contentLength=0
                    $requestType=''
                    foreach($h in $lines) {
                        if($h.StartsWith('Content-Length:',[System.StringComparison]::OrdinalIgnoreCase)) {
                            $contentLength=[int]$h.Substring(15).Trim()
                        }
                        if($h.StartsWith('Content-Type:',[System.StringComparison]::OrdinalIgnoreCase)) {
                            $requestType=$h.Substring(13).Trim()
                        }
                    }
                    if($contentLength -lt 0 -or $contentLength -gt 65536) { throw 'Fixture: Invalid body length' }
                    $bytes=[byte[]]::new($contentLength)
                    $count=0
                    while($count -lt $contentLength) {
                        $read=$stream.Read($bytes,$count,$contentLength-$count)
                        if($read -le 0) { throw 'Fixture: EOF in HTTP body' }
                        $count+=$read
                    }
                    $requestBody=$utf8.GetString($bytes)
                    $status='200 OK'; $type='text/plain; charset=utf-8'; $responseBody=''; $more=''
                    switch ($path) {
                        '/hello' { $responseBody='Hello ALL' }
                        '/unicode' { $responseBody='こんにちは世界' }
                        '/json' { $type='application/json; charset=utf-8'; $responseBody='{"message":"ALL-JSON"}' }
                        '/missing' { $status='404 Not Found'; $responseBody='not found' }
                        '/redirect' { $status='302 Found'; $responseBody='redirect'; $more="Location: /hello`r`n" }
                        '/echo' { $responseBody=$verb+'|'+$requestBody }
                        '/echo-json' {
                            if(-not $requestType.StartsWith('application/json',[System.StringComparison]::OrdinalIgnoreCase)) {
                                $status='415 Unsupported Media Type'; $responseBody='not json'
                            } else { $type='application/json; charset=utf-8'; $responseBody=$requestBody }
                        }
                        default { $status='404 Not Found'; $responseBody='unknown' }
                    }
                    $responseBytes=$utf8.GetBytes($responseBody)
                    $header="HTTP/1.1 $status`r`nContent-Type: $type`r`nContent-Length: $($responseBytes.Length)`r`n${more}Connection: close`r`n`r`n"
                    $outHeader=[System.Text.Encoding]::ASCII.GetBytes($header)
                    $stream.Write($outHeader,0,$outHeader.Length)
                    $stream.Write($responseBytes,0,$responseBytes.Length)
                    $stream.Flush()
                } finally { $client.Dispose() }
            }
        } finally { $listener.Stop() }
    }
    $deadline=[DateTime]::UtcNow.AddSeconds(12)
    while(-not [System.IO.File]::Exists($ready)) {
        if($job.State -eq 'Failed') { throw 'ALL HTTP: Local fixture failed to start' }
        if([DateTime]::UtcNow -gt $deadline) { throw 'ALL HTTP: Local fixture startup timeout' }
        Start-Sleep -Milliseconds 50
    }
    foreach($test in $cases) {
        $code=([string]$test.code).Replace('__PORT__',[string]$port)
        $sw=[System.IO.StringWriter]::new([System.Globalization.CultureInfo]::InvariantCulture)
        $saved=[Console]::Out
        $pipeline=@(); $actualError=$null
        try {
            [Console]::SetOut($sw)
            $pipeline=@(& $core -Language ALL -Code $code)
        } catch { $actualError=$_.Exception.Message }
        finally { [Console]::SetOut($saved) }
        $actual=$sw.ToString()
        $sw.Dispose()
        if ($null -ne $test.error_contains) {
            $ok=($null -ne $actualError -and $actualError.Contains([string]$test.error_contains) -and $actual.Length -eq 0 -and $pipeline.Count -eq 0)
        } else {
            $ok=($null -eq $actualError -and $actual -ceq [string]$test.expected -and $pipeline.Count -eq 0)
        }
        if($ok) { $pass++; Write-Host "PASS [HTTP]: $($test.name)" -ForegroundColor Green }
        else {
            $fail++; Write-Host "FAIL [HTTP]: $($test.name)" -ForegroundColor Red
            Write-Host "  Expected: $($test.expected)"
            Write-Host "  Actual: $($actual | ConvertTo-Json -Compress)"
            Write-Host "  Error: $actualError"
            if($pipeline.Count -gt 0) { Write-Host "  Pipeline: $($pipeline -join '|')" }
        }
    }
    if($job.State -eq 'Failed') { Write-Host '  Fixture failed:'; Receive-Job $job }
    Write-Host "ALL HTTP v0.8: $pass / 16 passed; $fail failed"
    if($fail -ne 0) { throw "ALL HTTP v0.8 regressions: $fail failure(s)" }
} finally {
    if ($null -ne $job) {
        if ($job.State -eq 'Running') { Stop-Job -Job $job -ErrorAction SilentlyContinue }
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
    }
    if ([System.IO.Directory]::Exists($workspace)) { [System.IO.Directory]::Delete($workspace,$true) }
}
