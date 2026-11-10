# Parent: runs a list of PHPT tests against the ALL PHP adapter using isolated worker processes
# (Windows PowerShell 5.1), with a per-test timeout, a memory cap and crash recovery.
# ASCII only.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$AdapterPath,
    [Parameter(Mandatory = $true)][string]$TestRoot,
    [Parameter(Mandatory = $true)][string]$ListFile,     # relative test paths, one per line
    [Parameter(Mandatory = $true)][string]$WorkDir,      # scratch directory for shard files
    [Parameter(Mandatory = $true)][string]$ResultPath,   # merged JSONL result
    [int]$Workers = 3,
    [int]$TimeoutSeconds = 15,
    [int]$MemoryLimitMB = 1500
)
$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$worker = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'PhptWorker.ps1'
$ps51 = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$all = @([IO.File]::ReadAllLines($ListFile, $utf8) | Where-Object { $_ })
[void](New-Item -ItemType Directory -Force -Path $WorkDir)

$shards = @()
for ($w = 0; $w -lt $Workers; $w++) {
    $items = New-Object System.Collections.Generic.List[string]
    for ($k = $w; $k -lt $all.Count; $k += $Workers) { $items.Add($all[$k]) }
    $list = Join-Path $WorkDir "shard$w.list"
    $out = Join-Path $WorkDir "shard$w.jsonl"
    [IO.File]::WriteAllLines($list, $items, $utf8)
    if (Test-Path -LiteralPath $out) { Remove-Item -LiteralPath $out }
    $shards += [pscustomobject]@{ Id = $w; List = $list; Out = $out; Count = $items.Count; Items = $items
        Proc = $null; Done = ($items.Count -eq 0); LastLength = -1; LastChange = [DateTime]::UtcNow }
}

function Start-Shard($s, [int]$from) {
    $argLine = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -AdapterPath "{1}" -TestRoot "{2}" -ListFile "{3}" -OutFile "{4}" -StartIndex {5}' -f `
        $worker, $AdapterPath, $TestRoot, $s.List, $s.Out, $from
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $ps51
    $psi.Arguments = $argLine
    $psi.WorkingDirectory = $WorkDir
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $s.Proc = [System.Diagnostics.Process]::Start($psi)
    $s.LastChange = [DateTime]::UtcNow
}

# Returns the state of a shard's output: index of a test that started but has no result (or -1),
# the next index to run, and whether the worker wrote its final "done" line.
function Get-ShardState($s) {
    $pending = -1; $next = 0; $done = $false
    if (Test-Path -LiteralPath $s.Out) {
        foreach ($line in [IO.File]::ReadAllLines($s.Out, $utf8)) {
            if (-not $line) { continue }
            $o = $line | ConvertFrom-Json
            if ($o.done) { $done = $true }
            elseif ($o.start) { $pending = [int]$o.i }
            elseif ($null -ne $o.verdict) { $pending = -1; $next = [int]$o.i + 1 }
        }
    }
    return [pscustomobject]@{ Pending = $pending; Next = $next; Done = $done }
}

function Add-Synthetic($s, [int]$i, [string]$verdict, [string]$detail) {
    $row = [ordered]@{ i = $i; test = $s.Items[$i]; verdict = $verdict; detail = $detail; expects_fatal = $false; ms = 0 }
    [IO.File]::AppendAllText($s.Out, (($row | ConvertTo-Json -Compress) + "`n"), $utf8)
}

foreach ($s in $shards) { if (-not $s.Done) { Start-Shard $s 0 } }
$started = [DateTime]::UtcNow
$lastReport = [DateTime]::UtcNow
while (@($shards | Where-Object { -not $_.Done }).Count -gt 0) {
    Start-Sleep -Milliseconds 400
    foreach ($s in ($shards | Where-Object { -not $_.Done })) {
        $len = if (Test-Path -LiteralPath $s.Out) { ([IO.FileInfo]$s.Out).Length } else { 0 }
        if ($len -ne $s.LastLength) { $s.LastLength = $len; $s.LastChange = [DateTime]::UtcNow }
        $exited = $s.Proc.HasExited
        $reason = $null
        if (-not $exited) {
            $s.Proc.Refresh()
            if ($s.Proc.WorkingSet64 -gt ($MemoryLimitMB * 1MB)) { $reason = 'MEMORY' }
            elseif (([DateTime]::UtcNow - $s.LastChange).TotalSeconds -gt $TimeoutSeconds) { $reason = 'TIMEOUT' }
            if ($null -eq $reason) { continue }
            try { $s.Proc.Kill() } catch { }
            $s.Proc.WaitForExit()
        }
        $st = Get-ShardState $s
        if ($st.Done) { $s.Done = $true; continue }
        if ($st.Pending -ge 0) {
            if ($null -eq $reason) { $reason = 'CRASH' }
            $detail = switch ($reason) {
                'TIMEOUT' { "no result within $TimeoutSeconds s" }
                'MEMORY' { "worker exceeded $MemoryLimitMB MB" }
                default { "worker process exited (code $($s.Proc.ExitCode))" }
            }
            Add-Synthetic $s $st.Pending $reason $detail
            $resume = $st.Pending + 1
        } else {
            $resume = $st.Next   # died between tests or during startup
        }
        $s.LastLength = -1
        if ($resume -ge $s.Count) { $s.Done = $true } else { Start-Shard $s $resume }
    }
    if (([DateTime]::UtcNow - $lastReport).TotalSeconds -ge 60) {
        $lastReport = [DateTime]::UtcNow
        $doneCount = 0
        foreach ($s in $shards) { $doneCount += (Get-ShardState $s).Next }
        Write-Host ("progress {0}/{1}  elapsed {2:n0}s" -f $doneCount, $all.Count, ([DateTime]::UtcNow - $started).TotalSeconds)
    }
}

# Merge: one row per test, in the original list order.
$byTest = @{}
foreach ($s in $shards) {
    if (-not (Test-Path -LiteralPath $s.Out)) { continue }
    foreach ($line in [IO.File]::ReadAllLines($s.Out, $utf8)) {
        if (-not $line) { continue }
        $o = $line | ConvertFrom-Json
        if ($null -ne $o.verdict) { $byTest[$o.test] = $line }
    }
}
$merged = New-Object System.Collections.Generic.List[string]
foreach ($t in $all) {
    if ($byTest.ContainsKey($t)) { $merged.Add($byTest[$t]) }
    else { $merged.Add((([ordered]@{ i = -1; test = $t; verdict = 'HARNESS_ERROR'; detail = 'no result recorded'; expects_fatal = $false; ms = 0 }) | ConvertTo-Json -Compress)) }
}
[IO.File]::WriteAllLines($ResultPath, $merged, $utf8)
Write-Host ("finished {0} tests in {1:n0}s" -f $all.Count, ([DateTime]::UtcNow - $started).TotalSeconds)
$merged | ForEach-Object { ($_ | ConvertFrom-Json).verdict } | Group-Object | Sort-Object Count -Descending |
    ForEach-Object { Write-Host ("  {0,-14} {1}" -f $_.Name, $_.Count) }
