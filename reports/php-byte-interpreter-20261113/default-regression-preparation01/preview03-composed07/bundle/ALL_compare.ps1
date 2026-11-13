# Compare equivalent non-I/O arithmetic in ALL and Python on the same host.
# No claims about a broader language ranking are made from this microbenchmark.
[CmdletBinding()]
param([ValidateRange(3,100)][int]$Iterations=7,
      [string]$PythonExe='python',
      [string]$OutputPath="$HOME/ALL_compare.json")
$ErrorActionPreference='Stop'
$python=(Get-Command $PythonExe -ErrorAction SilentlyContinue)
if(-not $python){throw 'Python executable not found; pass the path with -PythonExe'}
$psExe=(Get-Process -Id $PID).Path
$tmp=Join-Path ([IO.Path]::GetTempPath()) ('ALL_COMPARE_'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
$all=Join-Path $tmp 'test.all';$py=Join-Path $tmp 'test.py'
[IO.File]::WriteAllText($all,@'
let i = 0
let total = 0
while (i < 1000) {
 total = total + i
 i = i + 1
}
print(total)
'@,[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText($py,@'
total=0
for i in range(1000):
    total+=i
print(total,end='')
'@,[Text.UTF8Encoding]::new($false))
function RunNative([string]$exe,[string]$arguments){
    $psi=[Diagnostics.ProcessStartInfo]::new()
    $psi.FileName=$exe;$psi.Arguments=$arguments
    $psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
    $psi.UseShellExecute=$false;$psi.CreateNoWindow=$true
    $clock=[Diagnostics.Stopwatch]::StartNew()
    $p=[Diagnostics.Process]::Start($psi)
    try {
      $stdout=$p.StandardOutput.ReadToEnd();$stderr=$p.StandardError.ReadToEnd()
      if(-not $p.WaitForExit(60000)){$p.Kill();throw 'Benchmark process timed out'}
      $clock.Stop()
      return [pscustomobject]@{Exit=$p.ExitCode;Stdout=$stdout.Trim();Stderr=$stderr;ElapsedMs=$clock.Elapsed.TotalMilliseconds;PeakBytes=$p.PeakWorkingSet64;CpuMs=$p.TotalProcessorTime.TotalMilliseconds}
    } finally {$p.Dispose()}
}
try {
    $allArgs='-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+(Join-Path $HOME 'ALL/ALL_cli_host.ps1')+'" run "'+$all+'"'
    $pyArgs='"'+$py+'"'
    $rows=[System.Collections.Generic.List[object]]::new()
    for($i=0;$i -lt $Iterations;$i++){
        $one=RunNative $psExe $allArgs
        $two=RunNative $python.Source $pyArgs
        if($one.Exit -ne 0 -or $two.Exit -ne 0 -or $one.Stdout -cne '499500' -or $two.Stdout -cne '499500'){
            throw "Incorrect benchmark result at run $i ALL=[$($one.Stdout)] Python=[$($two.Stdout)]"
        }
        [void]$rows.Add([pscustomobject]@{run=$i+1;all_ms=$one.ElapsedMs;python_ms=$two.ElapsedMs;all_peak_bytes=$one.PeakBytes;python_peak_bytes=$two.PeakBytes;all_cpu_ms=$one.CpuMs;python_cpu_ms=$two.CpuMs})
    }
    $am=@($rows|ForEach-Object{$_.all_ms}|Sort-Object)
    $pm=@($rows|ForEach-Object{$_.python_ms}|Sort-Object)
    $mid=[int][Math]::Floor($Iterations/2)
    $report=[ordered]@{comparison='ALL_vs_Python_same_1000_iterations';includes_process_startup=$true;all_median_ms=$am[$mid];python_median_ms=$pm[$mid];runs=@($rows);parity='499500 verified';note='Single workload; not a full substitute for real application benchmarks'}
    $report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
    Write-Host "ALL median=$($am[$mid]) ms | Python median=$($pm[$mid]) ms | parity PASS"
} finally {Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue}
