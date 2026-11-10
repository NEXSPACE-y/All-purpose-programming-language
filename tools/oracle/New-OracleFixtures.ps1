# Builds a fixture JSON file from a plain-text list of PHP snippets by running each snippet through
# the official PHP binary. The expectation stored in the fixture is whatever official PHP printed.
# A snippet that makes official PHP fail or emit a diagnostic is refused, so the fixture file only
# contains cases whose complete observable behaviour is the recorded stdout.
#
# Source format:   "### <case name>" on one line, followed by the PHP code (one or more lines).
# ASCII only. Works on Windows PowerShell 5.1 and PowerShell 7.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$PhpExe,
    [Parameter(Mandatory = $true)][string]$SourcePath,
    [Parameter(Mandatory = $true)][string]$OutPath,
    [int]$TimeoutSeconds = 20
)
$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$work = Join-Path ([IO.Path]::GetTempPath()) ('ALL_fixture_' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $work)

$cases = New-Object System.Collections.Generic.List[object]
$name = $null
$buffer = New-Object System.Collections.Generic.List[string]
foreach ($line in [IO.File]::ReadAllLines($SourcePath, $utf8)) {
    if ($line.StartsWith('### ')) {
        if ($null -ne $name) { $cases.Add([pscustomobject]@{ name = $name; code = ($buffer -join "`n").Trim() }) }
        $name = $line.Substring(4).Trim()
        $buffer.Clear()
    } elseif ($null -ne $name) { $buffer.Add($line) }
}
if ($null -ne $name) { $cases.Add([pscustomobject]@{ name = $name; code = ($buffer -join "`n").Trim() }) }
$duplicates = @($cases | Group-Object name | Where-Object { $_.Count -gt 1 })
if ($duplicates.Count -gt 0) { throw "Duplicate case names: $(($duplicates | ForEach-Object Name) -join ', ')" }

$fixtures = New-Object System.Collections.Generic.List[object]
$refused = 0
try {
    foreach ($case in $cases) {
        $file = Join-Path $work 'case.php'
        [IO.File]::WriteAllBytes($file, $utf8.GetBytes($case.code))
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $PhpExe
        $psi.Arguments = '-n -d display_errors=stderr -d error_reporting=-1 -d date.timezone=UTC "' + $file + '"'
        $psi.WorkingDirectory = $work
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.RedirectStandardInput = $true
        $psi.CreateNoWindow = $true
        $psi.StandardOutputEncoding = $utf8
        $psi.StandardErrorEncoding = $utf8
        $p = [System.Diagnostics.Process]::Start($psi)
        $p.StandardInput.Close()
        $outTask = $p.StandardOutput.ReadToEndAsync()
        $errTask = $p.StandardError.ReadToEndAsync()
        if (-not $p.WaitForExit($TimeoutSeconds * 1000)) { try { $p.Kill() } catch { }; throw "oracle timeout: $($case.name)" }
        $p.WaitForExit()
        $stdout = $outTask.Result
        $stderr = $errTask.Result.Trim()
        $exit = $p.ExitCode
        $p.Dispose()
        if ($exit -ne 0 -or $stderr.Length -gt 0) {
            $refused++
            Write-Host "REFUSED [$($case.name)] exit=$exit" -ForegroundColor Yellow
            Write-Host ('   ' + ($stderr -replace [regex]::Escape($file), 'case.php'))
            continue
        }
        $fixtures.Add([ordered]@{ name = $case.name; code = $case.code; oracle_php_exit = 0; expected = $stdout })
    }
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
if ($refused -gt 0) { throw "$refused case(s) refused; fix or remove them. Nothing was written." }
$json = ConvertTo-Json -InputObject @($fixtures.ToArray()) -Depth 4
[IO.File]::WriteAllText($OutPath, $json, $utf8)
Write-Host "Wrote $($fixtures.Count) oracle fixtures to $OutPath (PHP $(& $PhpExe -n -r 'echo PHP_VERSION;'))"
