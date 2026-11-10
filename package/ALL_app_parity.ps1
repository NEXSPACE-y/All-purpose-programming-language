# End-to-end same-spec HTTP/SQLite test: ALL vs Python reference.
[CmdletBinding()]
param([string]$PythonExe='python')
$ErrorActionPreference='Stop'
$py=(Get-Command $PythonExe -ErrorAction SilentlyContinue)
if(-not $py){throw 'Python required to run independent reference application'}
$src=Join-Path $PSScriptRoot 'examples/pro_app'
$tmp=Join-Path ([IO.Path]::GetTempPath()) ('ALL_APP_PARITY_'+[guid]::NewGuid().ToString('N'))
$aDir=Join-Path $tmp 'all';$pDir=Join-Path $tmp 'python'
New-Item -ItemType Directory -Path $aDir,$pDir -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $src 'service.all') -Destination $aDir
Copy-Item -LiteralPath (Join-Path $src 'setup.all') -Destination $aDir
Copy-Item -LiteralPath (Join-Path $src 'migrations') -Destination $aDir -Recurse
Copy-Item -LiteralPath (Join-Path $src 'reference.py') -Destination $pDir
$psExe=(Get-Process -Id $PID).Path
$port=Get-Random -Minimum 25000 -Maximum 29000
$pyPort=$port+1;$workers=$port+2
$stop=Join-Path $tmp 'stop.flag'
$pA=$null;$pP=$null
$dir=(Get-Location).Path
try {
    Set-Location $aDir
    $setupSource=[IO.File]::ReadAllText((Join-Path $aDir 'setup.all'),[Text.UTF8Encoding]::new($false,$true))
    & (Join-Path $HOME 'ALL/ALL.ps1') -Language ALL -Code $setupSource | Out-Null
    Set-Location $dir
    $sa=[Diagnostics.ProcessStartInfo]::new()
    $sa.FileName=$psExe
    $sa.Arguments='-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+(Join-Path $HOME 'ALL/ALL_serve_pool.ps1')+'" -File "'+(Join-Path $aDir 'service.all')+'" -StopFile "'+$stop+'" -Workers 4 -Port '+$port+' -WorkerStartPort '+$workers
    $sa.UseShellExecute=$false;$sa.CreateNoWindow=$true
    $pA=[Diagnostics.Process]::Start($sa)
    $sp=[Diagnostics.ProcessStartInfo]::new()
    $sp.FileName=$py.Source;$sp.Arguments='"'+(Join-Path $pDir 'reference.py')+'" --port '+$pyPort
    $sp.UseShellExecute=$false;$sp.CreateNoWindow=$true
    $pP=[Diagnostics.Process]::Start($sp)
    $client=[Net.WebClient]::new()
    try {
        foreach($value in @($port,$pyPort)){
            $online=$false
            for($i=0;$i -lt 100;$i++){
                try {if(($client.DownloadString('http://127.0.0.1:'+$value+'/health')).Trim() -eq 'OK'){$online=$true;break}}catch{}
                Start-Sleep -Milliseconds 250
            }
            if(-not $online){throw "Parity server did not start: port $value"}
        }
        # A consistent input and deterministic IDs in separate fresh databases.
        $data='{"name":"日本語テスト","qty":3}'
        $body=[Text.Encoding]::UTF8.GetBytes($data)
        foreach($value in @($port,$pyPort)){
            $client.Headers['Content-Type']='application/json; charset=utf-8'
            [void]$client.UploadData(('http://127.0.0.1:'+$value+'/items'),'POST',$body)
        }
        $a=[string]$client.DownloadString('http://127.0.0.1:'+$port+'/items')
        $p=[string]$client.DownloadString('http://127.0.0.1:'+$pyPort+'/items')
        $aObj=@(ConvertFrom-Json -InputObject $a)
        $pObj=@(ConvertFrom-Json -InputObject $p)
        if($aObj.Count -ne 1 -or $pObj.Count -ne 1){throw 'API parity: expected one record'}
        foreach($field in @('id','name','qty')){
            if([string]$aObj[0].$field -cne [string]$pObj[0].$field){throw "API parity mismatch ${field}: ALL=$($aObj[0].$field) Python=$($pObj[0].$field)"}
        }
        Write-Host 'PASS [Real app]: ALL/Python POST->SQLite->GET JSON parity' -ForegroundColor Green
    } finally {$client.Dispose()}
} finally {
    [IO.File]::WriteAllText($stop,'stop')
    if($pA){try{if(-not $pA.WaitForExit(15000)){$pA.Kill()}}catch{};$pA.Dispose()}
    if($pP){try{if(-not $pP.HasExited){$pP.Kill()}}catch{};$pP.Dispose()}
    Set-Location $dir
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
