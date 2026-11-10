# Linux-only installer; no system-wide mutation. Requires existing pwsh runtime.
$ErrorActionPreference='Stop'
if([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)){
    throw 'This installer is for Linux; use ALL_integrated_install.ps1 on Windows'
}
$root=$PSScriptRoot;$homeRoot=Join-Path $HOME 'ALL'
New-Item -ItemType Directory -Path (Join-Path $homeRoot 'languages') -Force | Out-Null
$files=@{
  'ALL_linux_core.ps1'='ALL.ps1';
  'ALL_v1_0_adapter.ps1'='languages/all.ps1';
  'ALL_PHP_v3_2_adapter.ps1'='languages/php.ps1';
  'ALL_sqlite_driver_linux.cs'='languages/ALL_sqlite_driver_linux.cs';
  'ALL_ConcurrentGateway.cs'='ALL_ConcurrentGateway.cs';
  'ALL_serve_pool.ps1'='ALL_serve_pool.ps1';
  'ALL_debug.ps1'='ALL_debug.ps1';
  'ALL_cli.ps1'='ALL_cli.ps1';
  'ALL_cli_host.ps1'='ALL_cli_host.ps1';
  'ALL_run.ps1'='run.ps1';
  'all'='all'
}
$backups=New-Object System.Collections.ArrayList
try {
 foreach($source in $files.Keys){
  $target=Join-Path $homeRoot $files[$source]
  $had=Test-Path -LiteralPath $target
  $backup=$target+'.bak.'+[guid]::NewGuid().ToString('N')
  if($had){Copy-Item -LiteralPath $target -Destination $backup -ErrorAction Stop}
  [void]$backups.Add([pscustomobject]@{Path=$target;Backup=$backup;Had=$had})
  Copy-Item -LiteralPath (Join-Path $root $source) -Destination $target -Force -ErrorAction Stop
 }
 & (Join-Path $homeRoot 'ALL.ps1') -Language ALL -Code 'print("Linux ALL OK")'
 & (Join-Path $root 'ALL_sql_v1_4_test.ps1')
 Write-Host 'Linux smoke + SQLite tests completed. Cross-OS parity is NOT yet established.'
}catch{
 for($i=$backups.Count-1;$i -ge 0;$i--){
  $entry=$backups[$i]
  if($entry.Had){Copy-Item -LiteralPath $entry.Backup -Destination $entry.Path -Force}
  else {Remove-Item -LiteralPath $entry.Path -ErrorAction SilentlyContinue}
 }
 throw
}
