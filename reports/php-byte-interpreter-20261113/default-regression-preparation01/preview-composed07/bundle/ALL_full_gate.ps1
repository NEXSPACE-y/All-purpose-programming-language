# ALL professional graduation gate. Every condition must be proved separately;
# public deploy and Linux proof are never substituted with local examples.
[CmdletBinding()]
param(
  [switch]$RunInstalledTests,
  [switch]$RunRealAppParity,
  [switch]$RunPerformanceComparison,
  [string]$PythonExe='python',
  [string]$LinuxReportPath,
  [string]$PublicBaseUrl,
  [string]$ExternalProofReportPath,
  [string]$ReportPath="$HOME/ALL_professional_status.json"
)
$ErrorActionPreference='Stop'
$root=$PSScriptRoot
$gates=[System.Collections.Generic.List[object]]::new()
function Record([string]$name,[string]$status,[string]$notes){
    [void]$gates.Add([pscustomobject]@{item=$name;status=$status;details=$notes})
    Write-Host "$status | $name | $notes"
}
if($RunInstalledTests){
    $groups=[ordered]@{
      'CLI / standardized process exit'= @('ALL_cli_v1_3_test.ps1')
      'SQL atomic transactions and migrations'=@('ALL_sql_v1_4_test.ps1','ALL_sql_migrations_test.ps1')
      'Debugger structured trace and call stack'=@('ALL_debug_test.ps1','ALL_debug_source_test.ps1')
      'HTTP concurrent independent execution'=@('ALL_parallel_web_test.ps1')
    }
    foreach($entry in $groups.GetEnumerator()){
      try{foreach($test in $entry.Value){& (Join-Path $root $test)};Record $entry.Key 'PASS' ('Tests: '+($entry.Value -join ', '))}
      catch{Record $entry.Key 'FAIL' $_.Exception.Message}
    }
} else {
    foreach($name in @('CLI / standardized process exit','SQL atomic transactions and migrations','Debugger structured trace and call stack','HTTP concurrent independent execution')){
      Record $name 'NOT_RUN' 'Invoke with -RunInstalledTests'
    }
}
if($RunRealAppParity){
    try{& (Join-Path $root 'ALL_app_parity.ps1') -PythonExe $PythonExe;Record 'Same-spec DB API parity with Python' 'PASS' 'Create, SELECT and JSON output match'}
    catch{Record 'Same-spec DB API parity with Python' 'FAIL' $_.Exception.Message}
} else {Record 'Same-spec DB API parity with Python' 'NOT_RUN' 'Invoke with -RunRealAppParity'}
if($RunPerformanceComparison){
    try{& (Join-Path $root 'ALL_compare.ps1') -PythonExe $PythonExe -OutputPath (Join-Path (Split-Path -Parent $ReportPath) 'ALL_compare.json');Record 'Comparable CPU benchmark' 'MEASURED' 'Inspect speed, CPU and memory; correctness is separately verified'}
    catch{Record 'Comparable CPU benchmark' 'FAIL' $_.Exception.Message}
} else {Record 'Comparable CPU benchmark' 'NOT_RUN' 'Invoke with -RunPerformanceComparison'}
if(-not $LinuxReportPath){Record 'Linux native execution parity' 'BLOCKED' 'Run ALL_linux_validation.ps1 on a Linux host and supply its report'}
else {
    try{
        $cases=@(Get-Content -LiteralPath $LinuxReportPath -Raw -Encoding UTF8 | ConvertFrom-Json)
        if($cases.Count -eq 0 -or @($cases|Where-Object{$_.result -ne 'PASS'}).Count){throw 'Linux test report has failures or is empty'}
        Record 'Linux native execution parity' 'PASS' ('Independent Linux test cases: '+$cases.Count)
    }catch{Record 'Linux native execution parity' 'FAIL' $_.Exception.Message}
}
if([string]::IsNullOrWhiteSpace($PublicBaseUrl)){
    Record 'Public HTTPS external network' 'BLOCKED' 'Real domain and deployed endpoint required'
} else {
    try {
        if($PublicBaseUrl -notmatch '^https://'){throw 'An HTTPS endpoint is required'}
        & (Join-Path $root 'validation_load/ALL_https_verify.ps1') -BaseUrl $PublicBaseUrl -Requests 100 -ConcurrentClients 8
        if(-not $ExternalProofReportPath){throw 'Run from a different external network and supply evidence; local checks are insufficient'}
        if(-not (Test-Path -LiteralPath $ExternalProofReportPath)){throw 'External evidence file missing'}
        Record 'Public HTTPS external network' 'MEASURED' 'Endpoint passed locally; review external evidence separately'
    }catch{Record 'Public HTTPS external network' 'FAIL' $_.Exception.Message}
}
# Acceptance of uptime/throughput is deliberately numeric and separate from code creation.
Record 'Sustained reliability and professional traffic SLO' 'NOT_VERIFIED' 'Requires separately agreed target RPS, p95/p99, error budget and realistic-duration failure recovery'
Record 'Security review (deferred separate phase)' 'OUT_OF_SCOPE' 'Not part of current ALL-language graduation'
$strict=@($gates | Where-Object {$_.item -ne 'Security review (deferred separate phase)'})
$graduated=($strict.Count -gt 0 -and @($strict|Where-Object {$_.status -ne 'PASS'}).Count -eq 0)
$payload=[pscustomobject]@{generated_utc=[DateTime]::UtcNow.ToString('o');graduation_passed=$graduated;gates=@($gates)}
$parent=Split-Path -Parent $ReportPath
if($parent -and -not (Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Path $parent -Force|Out-Null}
$payload|ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ReportPath -Encoding UTF8
Write-Host "Report: $ReportPath"
Write-Host ('Graduation: '+$(if($graduated){'PASS'}else{'INCOMPLETE'}))
