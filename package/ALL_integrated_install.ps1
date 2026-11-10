# Integrated Windows install. Stages files; runs core + new functional tests;
# restores every previous ALL file on failure. No background execution.
$ErrorActionPreference='Stop'
$source=$PSScriptRoot
$homeAll=Join-Path $HOME 'ALL'
$languageDir=Join-Path $homeAll 'languages'
$core=Join-Path $homeAll 'ALL.ps1'
if(-not (Test-Path -LiteralPath $core -PathType Leaf)){throw 'Existing ALL Core not found'}
$files=[ordered]@{
 'ALL_v1_0_adapter.ps1'='languages/all.ps1'
 'ALL_sqlite_driver.cs'='languages/ALL_sqlite_driver.cs'
 'ALL_sqlite_driver_linux.cs'='languages/ALL_sqlite_driver_linux.cs'
 'ALL_ConcurrentGateway.cs'='ALL_ConcurrentGateway.cs'
 'ALL_serve_pool.ps1'='ALL_serve_pool.ps1'
 'ALL_debug.ps1'='ALL_debug.ps1'
 'ALL_cli.ps1'='ALL_cli.ps1'
 'ALL_cli_host.ps1'='ALL_cli_host.ps1'
 'ALL_run.ps1'='run.ps1'
 'all.cmd'='all.cmd'
}
# One read-only preflight scans *every* PowerShell script and compiles C#.
# It must succeed before any installed ALL file is overwritten.
& (Join-Path $source 'ALL_preflight.ps1') -CompileCSharp
New-Item -ItemType Directory -Path $languageDir -Force | Out-Null
$oldFiles=New-Object System.Collections.ArrayList
try {
 foreach($name in $files.Keys){
    $dest=Join-Path $homeAll $files[$name]
    $before=Test-Path -LiteralPath $dest
    $backup=$dest+'.bak.'+[guid]::NewGuid().ToString('N')
    if($before){Copy-Item -LiteralPath $dest -Destination $backup -ErrorAction Stop}
    [void]$oldFiles.Add([pscustomobject]@{dest=$dest;backup=$backup;had=$before})
    Copy-Item -LiteralPath (Join-Path $source $name) -Destination $dest -Force -ErrorAction Stop
 }
 # Legacy test scripts are unchanged; their baseline is 486 tests.
 & (Join-Path $source 'ALL_cli_v1_3_test.ps1')
 & (Join-Path $source 'ALL_cli_web_v1_2_test.ps1')
 & (Join-Path $source 'ALL_cli_http_v1_1_test.ps1')
 & (Join-Path $source 'ALL_v1_0_test.ps1')
 & (Join-Path $source 'ALL_http_v0_9_test.ps1')
 & (Join-Path $source 'ALL_http_v0_8_test.ps1')
 & (Join-Path $source 'ALL_module_v0_7_test.ps1')
 & (Join-Path $source 'ALL_Japanese_grammar_v0_6_test.ps1')
 & (Join-Path $source 'ALL_language_v0_5_test.ps1')
 & (Join-Path $source 'ALL_JP_v0_4_test.ps1')
 & (Join-Path $source 'ALL_language_v0_3_test.ps1')
 & (Join-Path $source 'ALL_PHP_v3_2_test.ps1')
 & (Join-Path $source 'ALL_sql_v1_4_test.ps1')
 & (Join-Path $source 'ALL_sql_migrations_test.ps1')
 & (Join-Path $source 'ALL_debug_test.ps1')
 & (Join-Path $source 'ALL_debug_source_test.ps1')
 & (Join-Path $source 'ALL_parallel_web_test.ps1')
 Write-Host 'ALL integrated candidate installed; 523 baseline and 4 new debug-source tests passed.' -ForegroundColor Green
} catch {
 $why=$_.Exception.Message
 for($i=$oldFiles.Count-1;$i -ge 0;$i--){
   $entry=$oldFiles[$i]
   if($entry.had){Copy-Item -LiteralPath $entry.backup -Destination $entry.dest -Force}
   else {Remove-Item -LiteralPath $entry.dest -Force -ErrorAction SilentlyContinue}
 }
 throw "ALL integrated installation rolled back: $why"
}
