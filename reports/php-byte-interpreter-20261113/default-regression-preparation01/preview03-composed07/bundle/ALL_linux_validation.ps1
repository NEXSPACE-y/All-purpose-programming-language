# Run on an actual Linux host with PowerShell 7 (pwsh) and libsqlite3.
$ErrorActionPreference='Stop'
if([System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)){
    throw 'Linux verification must be executed on Linux'
}
$root=$PSScriptRoot
$checks=@(
 'ALL_sql_v1_4_test.ps1',
 'ALL_sql_migrations_test.ps1',
 'ALL_debug_test.ps1',
 'ALL_parallel_web_test.ps1',
 'ALL_language_v0_3_test.ps1',
 'ALL_math_test.ps1'
)
$results=[System.Collections.Generic.List[object]]::new()
foreach($test in $checks){
  try {
    & (Join-Path $root $test)
    [void]$results.Add([pscustomobject]@{test=$test;result='PASS'})
  }catch{
    [void]$results.Add([pscustomobject]@{test=$test;result='FAIL';detail=$_.Exception.Message})
  }
}
$report=Join-Path $HOME 'ALL_linux_validation.json'
$results | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $report -Encoding utf8
Write-Host "Linux report: $report"
if(@($results|Where-Object {$_.result -ne 'PASS'}).Count -gt 0){throw 'Linux parity validation failed'}
