param([int]$Iterations=7,[string]$OutputPath='')
$ErrorActionPreference='Stop'
if ($Iterations -lt 3 -or $Iterations -gt 50) { throw 'Iterations must be 3..50' }
$core=Join-Path $HOME 'ALL\ALL.ps1'
if (-not (Test-Path -LiteralPath $core)) { throw 'ALL core not installed' }
$samples=[System.Collections.Generic.List[double]]::new()
$code='let total=0;for(let i=0;i<100;i=i+1){total=total+i};print(total)'
# Warmup and timings use a live interpreter call. Excludes process startup.
for($i=-1;$i -lt $Iterations;$i++) {
    $sink=[System.IO.StringWriter]::new([System.Globalization.CultureInfo]::InvariantCulture)
    $original=[Console]::Out
    $stopwatch=[System.Diagnostics.Stopwatch]::StartNew()
    try {
        [Console]::SetOut($sink)
        & $core -Language ALL -Code $code | Out-Null
        $stopwatch.Stop()
    } finally { [Console]::SetOut($original) }
    if ($sink.ToString() -cne '4950') { throw 'ALL benchmark calculation mismatch' }
    if ($i -ge 0) { [void]$samples.Add([double]$stopwatch.Elapsed.TotalMilliseconds) }
    $sink.Dispose()
}
$sorted=@($samples.ToArray() | Sort-Object)
$process=[System.Diagnostics.Process]::GetCurrentProcess()
$report=[ordered]@{
    benchmark='ALL_v1_0_interpreter_in_process'; iterations=$Iterations;
    median_ms=[Math]::Round([double]$sorted[[int][Math]::Floor(($sorted.Length-1)/2)],3);
    min_ms=[Math]::Round([double]$sorted[0],3);
    max_ms=[Math]::Round([double]$sorted[-1],3);
    current_process_working_set_bytes=[long]$process.WorkingSet64;
    detail='Interpreter invocation and computation; excludes shell startup. Current memory is not peak memory.'
}
$json=ConvertTo-Json -InputObject $report -Depth 5
Write-Output $json
if ($OutputPath) { [System.IO.File]::WriteAllText([System.IO.Path]::GetFullPath($OutputPath),$json,[System.Text.UTF8Encoding]::new($false)) }
