# ALL multiprocess HTTP server. Independent interpreters; concurrent gateway.
[CmdletBinding()]
param(
 [Parameter(Mandatory)][string]$File,
 [Parameter(Mandatory)][string]$StopFile,
 [ValidateRange(2,32)][int]$Workers=4,
 [ValidateRange(1024,65535)][int]$Port=18888,
 [ValidateRange(1024,65535)][int]$WorkerStartPort=19090,
 [ValidateRange(1,1024)][int]$MaxInFlight=128
)
$ErrorActionPreference='Stop'
$File=[IO.Path]::GetFullPath($File)
$StopFile=[IO.Path]::GetFullPath($StopFile)
if(-not (Test-Path -LiteralPath $File -PathType Leaf)){throw "ALL server source not found: $File"}
if([IO.Path]::GetExtension($File) -cne '.all'){throw 'ALL server source must be .all'}
if($WorkerStartPort+$Workers-1 -gt 65535){throw 'Worker port range exceeds 65535'}
if($Port -ge $WorkerStartPort -and $Port -lt $WorkerStartPort+$Workers){throw 'Gateway and worker port ranges overlap'}
$hostScript=Join-Path $HOME 'ALL/ALL_cli_host.ps1'
$gatewaySource=Join-Path $HOME 'ALL/ALL_ConcurrentGateway.cs'
if(-not (Test-Path -LiteralPath $hostScript) -or -not (Test-Path -LiteralPath $gatewaySource)) {throw 'ALL worker installation incomplete'}
if(Test-Path -LiteralPath $StopFile){Remove-Item -LiteralPath $StopFile -Force}
$psExe=(Get-Process -Id $PID).Path
$workersList=[System.Collections.Generic.List[Diagnostics.Process]]::new()
$stopFiles=[System.Collections.Generic.List[string]]::new()
$previousLocation=(Get-Location).Path
Set-Location ([IO.Path]::GetDirectoryName($File))
$programRoot=Join-Path ([IO.Path]::GetTempPath()) ('ALL_HTTP_POOL_'+[guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $programRoot -Force)
try {
 for($i=0;$i -lt $Workers;$i++){
   $workerPort=$WorkerStartPort+$i
   $workerStop=Join-Path $programRoot ("worker_$i.stop")
   [void]$stopFiles.Add($workerStop)
   $psi=[Diagnostics.ProcessStartInfo]::new()
   $psi.FileName=$psExe
   $psi.Arguments='-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$hostScript+'" serve "'+$File+'" "'+$workerStop+'"'
   $psi.UseShellExecute=$false
   $psi.CreateNoWindow=$true
   $psi.EnvironmentVariables['ALL_HTTP_PORT_OVERRIDE']=[string]$workerPort
   $proc=[Diagnostics.Process]::Start($psi)
   if($null -eq $proc){throw "Failed to start ALL worker $i"}
   [void]$workersList.Add($proc)
 }
 # Wait for every worker to accept TCP connections before binding front end.
 for($i=0;$i -lt $Workers;$i++){
   $portToTest=$WorkerStartPort+$i
   $deadline=[DateTime]::UtcNow.AddSeconds(20)
   $online=$false
   while([DateTime]::UtcNow -lt $deadline){
     if($workersList[$i].HasExited){throw "ALL worker $i exited unexpectedly: $($workersList[$i].ExitCode)"}
     $client=[Net.Sockets.TcpClient]::new()
     try {
       $result=$client.BeginConnect('127.0.0.1',$portToTest,$null,$null)
       if($result.AsyncWaitHandle.WaitOne(150)){$client.EndConnect($result);$online=$true;break}
     } catch {} finally {$client.Dispose()}
     Start-Sleep -Milliseconds 100
   }
   if(-not $online){throw "ALL worker did not become ready on port $portToTest"}
 }
 if(-not ('AllConcurrentGateway' -as [type])){
   Add-Type -Path $gatewaySource -ErrorAction Stop
 }
 Write-Host "ALL concurrent gateway ready workers=$Workers port=$Port pid=$PID"
 [AllConcurrentGateway]::Run($Port,[int[]]@(($WorkerStartPort)..($WorkerStartPort+$Workers-1)),$StopFile,$MaxInFlight)
} finally {
 foreach($filePath in $stopFiles){try{[IO.File]::WriteAllText($filePath,'stop')}catch{}}
 foreach($proc in $workersList){
   try{
     if(-not $proc.WaitForExit(4000)){ $proc.Kill();[void]$proc.WaitForExit(4000) }
     $proc.Dispose()
   }catch{}
 }
 try{Remove-Item -LiteralPath $programRoot -Recurse -Force -ErrorAction Stop}catch{}
 Set-Location $previousLocation
}
