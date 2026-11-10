# Runs every existing PHP regression fixture through the official PHP binary (the oracle)
# and reports whether the expectation stored in the fixture agrees with official PHP.
# Read-only for package/: fixtures and expectations are never modified.
# Compatible with Windows PowerShell 5.1. ASCII only.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$PhpExe,
    [string]$PackageDir = '',
    [Parameter(Mandatory = $true)][string]$ReportPath,
    [int]$TimeoutSeconds = 20
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $PhpExe -PathType Leaf)) { throw "PHP binary not found: $PhpExe" }
if ([string]::IsNullOrEmpty($PackageDir)) {
    $PackageDir = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) '..\..\package'
}
$PackageDir = (Resolve-Path -LiteralPath $PackageDir).Path
$utf8 = New-Object System.Text.UTF8Encoding($false)
$work = Join-Path ([IO.Path]::GetTempPath()) ('ALL_oracle_' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $work)

function Invoke-Oracle([string]$code) {
    $file = Join-Path $work 'case.php'
    [IO.File]::WriteAllBytes($file, $utf8.GetBytes($code))
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $PhpExe
    # -n: no php.ini. Diagnostics go to stderr so stdout is the program output only.
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
    $timedOut = -not $p.WaitForExit($TimeoutSeconds * 1000)
    if ($timedOut) { try { $p.Kill() } catch { } ; $p.WaitForExit() }
    $result = [pscustomobject]@{
        Stdout   = $outTask.Result
        Stderr   = ($errTask.Result -replace [regex]::Escape($file), 'case.php')
        ExitCode = $(if ($timedOut) { $null } else { $p.ExitCode })
        TimedOut = $timedOut
    }
    $p.Dispose()
    return $result
}

function Read-Fixtures([string]$name) {
    $path = Join-Path $PackageDir $name
    $data = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $path -Raw -Encoding UTF8)
    if (($data -is [array]) -and $data.Count -eq 1 -and ($data[0] -is [array])) { $data = $data[0] }
    return @($data)
}

# Same collections, in the same order, as package/ALL_PHP_v3_12_test.ps1.
$collections = @(
    'ALL_PHP_v3_1_1_cases.json', 'PHP_v3_2_cases.json', 'PHP_v3_3_cases.json', 'PHP_v3_3_guard_cases.json',
    'PHP_v3_4_cases.json', 'PHP_v3_4_guard_cases.json', 'PHP_v3_5_variables_operators_arrays_cases.json',
    'PHP_v3_5_functions_scopes_cases.json', 'PHP_v3_5_oop_cases.json', 'PHP_v3_6_retained_v3_5_guards.json',
    'PHP_v3_6_implemented_prior_guards.json', 'PHP_v3_6_oop_cases.json', 'PHP_v3_6_reference_cases.json',
    'PHP_v3_6_compound_cases.json', 'PHP_v3_6_trait_cases.json', 'PHP_v3_9_2_active_guards.json',
    'PHP_v3_9_2_native_oracle_cases.json', 'PHP_v3_7_implemented_prior_guards.json',
    'PHP_v3_7_native_oracle_cases.json', 'PHP_v3_7_trait_oracle_cases.json',
    'PHP_v3_8_implemented_prior_guards.json', 'PHP_v3_8_native_oracle_cases.json',
    'PHP_v3_9_native_oracle_cases.json', 'PHP_v3_9_1_ref_return_oracle_cases.json',
    'PHP_v3_10_typed_oracle_cases.json', 'PHP_v3_11_properties_oracle_cases.json',
    'PHP_v3_12_hooks_oracle_cases.json'
)

$rows = New-Object System.Collections.Generic.List[object]
function Add-Case([string]$file, [string]$name, [string]$code, $expected, $errorContains) {
    $r = Invoke-Oracle $code
    $isErrorCase = ($null -ne $errorContains)
    if ($r.TimedOut) { $verdict = 'ORACLE_TIMEOUT' }
    elseif ($isErrorCase) {
        # The fixture requires ALL to fail. Does official PHP also fail?
        if ($r.ExitCode -ne 0) { $verdict = 'ERROR_AGREES' } else { $verdict = 'ALL_REJECTS_VALID_PHP' }
    } else {
        $same = ($r.Stdout -ceq [string]$expected)
        if ($same -and $r.ExitCode -eq 0 -and $r.Stderr.Length -eq 0) { $verdict = 'MATCH' }
        elseif ($same) { $verdict = 'MATCH_BUT_PHP_DIAGNOSTIC' }
        else { $verdict = 'MISMATCH' }
    }
    $rows.Add([pscustomobject]@{
        file = $file; name = $name; verdict = $verdict; kind = $(if ($isErrorCase) { 'error' } else { 'output' })
        fixture_expected = $expected; fixture_error_contains = $errorContains
        php_stdout = $r.Stdout; php_stderr = $r.Stderr; php_exit = $r.ExitCode; code = $code
    })
}

try {
    foreach ($file in $collections) {
        foreach ($fx in (Read-Fixtures $file)) {
            Add-Case $file ([string]$fx.name) ([string]$fx.code) $fx.expected $fx.error_contains
        }
    }
    foreach ($fx in (Read-Fixtures 'ALL_math_cases.json' | Where-Object { $_.mode -eq 'pair' })) {
        Add-Case 'ALL_math_cases.json' ([string]$fx.name) ([string]$fx.php) $fx.expected $null
    }
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

$summary = [ordered]@{}
foreach ($g in ($rows | Group-Object verdict | Sort-Object Name)) { $summary[$g.Name] = $g.Count }
$report = [ordered]@{
    php_version = (& $PhpExe -n -r 'echo PHP_VERSION;')
    php_exe_sha256 = (Get-FileHash -LiteralPath $PhpExe -Algorithm SHA256).Hash.ToLower()
    php_args = '-n -d display_errors=stderr -d error_reporting=-1 -d date.timezone=UTC'
    total = $rows.Count
    summary = $summary
    cases = $rows
}
$json = $report | ConvertTo-Json -Depth 6
[IO.File]::WriteAllText($ReportPath, $json, $utf8)
Write-Host "Oracle PHP $($report.php_version): $($rows.Count) cases"
foreach ($k in $summary.Keys) { Write-Host ("  {0,-26} {1}" -f $k, $summary[$k]) }
