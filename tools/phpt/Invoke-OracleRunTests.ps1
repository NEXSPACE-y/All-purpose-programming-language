# Runs the official run-tests.php with the official PHP binary over a set of test directories and
# records which tests the oracle itself passes in this environment (this fixes the denominator).
# run-tests.php sometimes aborts on Windows (transient file locks), so this resumes until every
# test has a recorded status. A test that aborts the runner twice is recorded as ORACLE_ABORT.
# ASCII only.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$PhpExe,
    [Parameter(Mandatory = $true)][string]$TestRoot,
    [Parameter(Mandatory = $true)][string[]]$Dirs,
    [Parameter(Mandatory = $true)][string]$StatusPath,   # accumulated "STATUS<TAB>absolute path" lines
    [Parameter(Mandatory = $true)][string]$WorkDir,
    [int]$Jobs = 3,
    [int]$MaxRounds = 12
)
$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
[void](New-Item -ItemType Directory -Force -Path $WorkDir)
$allTests = foreach ($d in $Dirs) {
    Get-ChildItem -LiteralPath (Join-Path $TestRoot $d) -Recurse -Filter *.phpt -File | ForEach-Object { $_.FullName }
}
$allTests = @($allTests | Sort-Object -Unique)
if (-not (Test-Path -LiteralPath $StatusPath)) { [IO.File]::WriteAllText($StatusPath, '', $utf8) }
$env:NO_INTERACTION = '1'
$env:TEST_PHP_EXECUTABLE = $PhpExe
$abortCount = @{}
Push-Location -LiteralPath $TestRoot
try {
    for ($round = 1; $round -le $MaxRounds; $round++) {
        $done = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        foreach ($line in [IO.File]::ReadAllLines($StatusPath, $utf8)) {
            $parts = $line -split "`t", 2
            if ($parts.Count -eq 2) { [void]$done.Add($parts[1]) }
        }
        $remaining = @($allTests | Where-Object { -not $done.Contains($_) })
        Write-Host "round $round : $($done.Count) recorded, $($remaining.Count) remaining"
        if ($remaining.Count -eq 0) { break }
        $list = Join-Path $WorkDir "remaining_$round.txt"
        $w = Join-Path $WorkDir "W_$round.txt"
        $log = Join-Path $WorkDir "log_$round.txt"
        [IO.File]::WriteAllLines($list, $remaining, $utf8)
        if (Test-Path -LiteralPath $w) { Remove-Item -LiteralPath $w }
        & $PhpExe -n run-tests.php -p $PhpExe -q -n "-j$Jobs" --no-progress --offline -W $w -r $list *> $log
        $new = @()
        if (Test-Path -LiteralPath $w) { $new = @([IO.File]::ReadAllLines($w, $utf8) | Where-Object { $_ -match "`t" }) }
        if ($new.Count -gt 0) { [IO.File]::AppendAllLines($StatusPath, [string[]]$new, $utf8) }
        # If the runner aborted, find the test it named and give up on it after two aborts.
        $tail = @(Get-Content -LiteralPath $log -Tail 5)
        foreach ($t in $tail) {
            if ($t -match "Cannot open file '(.+)\.php'") {
                $culprit = $Matches[1] + '.phpt'
                $abortCount[$culprit] = 1 + [int]$abortCount[$culprit]
                if ($abortCount[$culprit] -ge 2) {
                    [IO.File]::AppendAllLines($StatusPath, [string[]]@("ORACLE_ABORT`t$culprit"), $utf8)
                }
            }
        }
        if ($new.Count -eq 0 -and $Jobs -gt 1) { $Jobs = 1 }   # no progress: fall back to serial
    }
} finally { Pop-Location }
$final = [IO.File]::ReadAllLines($StatusPath, $utf8) | Where-Object { $_ -match "`t" }
Write-Host "total tests: $($allTests.Count)  recorded: $(@($final).Count)"
$final | ForEach-Object { ($_ -split "`t")[0] } | Group-Object | Sort-Object Count -Descending |
    ForEach-Object { Write-Host ("  {0,-13} {1}" -f $_.Name, $_.Count) }
