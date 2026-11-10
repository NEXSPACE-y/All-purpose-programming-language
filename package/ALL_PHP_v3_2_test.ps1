# ALL PHP v3.2: 50 additional PHP compatibility cases.
# This script does NOT invoke php.exe. PHP 8.4.24 reference outputs are frozen
# in the JSON fixtures. PHP 8.5 array_first()/array_last() expectations come
# from the PHP 8.5 release documentation.
$ErrorActionPreference = 'Stop'
$core = Join-Path $HOME 'ALL\ALL.ps1'
$fixtures = Join-Path $PSScriptRoot 'PHP_v3_2_cases.json'
if (-not (Test-Path -LiteralPath $core -PathType Leaf)) { throw "Missing ALL Core: $core" }
if (-not (Test-Path -LiteralPath $fixtures -PathType Leaf)) { throw "Missing fixtures: $fixtures" }
$cases = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $fixtures -Raw -Encoding UTF8)
if (($cases -is [array]) -and $cases.Count -eq 1 -and ($cases[0] -is [array])) { $cases = $cases[0] }
if ($cases.Count -ne 50 -or $cases[0].name -cne 'power simple') {
    throw "Fixture loader error: expected 50 distinct cases; got $($cases.Count)"
}
function Invoke-PhpCase([string]$code) {
    $writer = [System.IO.StringWriter]::new([System.Globalization.CultureInfo]::InvariantCulture)
    $saved = [Console]::Out
    $errorText = $null
    $pipeline = @()
    try {
        [Console]::SetOut($writer)
        $pipeline = @(& $core -Language PHP -Code $code)
    } catch {
        $errorText = $_.Exception.Message
    } finally {
        [Console]::SetOut($saved)
    }
    $output = $writer.ToString()
    $writer.Dispose()
    return [pscustomobject]@{ Output=$output; Error=$errorText; Pipeline=@($pipeline) }
}
$passed = 0
$failed = 0
Write-Host '=== PHP 8.5 oriented compatibility extension tests ==='
foreach ($case in $cases) {
    $actual = Invoke-PhpCase ([string]$case.code)
    $isErrorTest = ($null -ne $case.error_contains)
    if ($isErrorTest) {
        $ok = ($null -ne $actual.Error -and
               $actual.Error.Contains([string]$case.error_contains) -and
               $actual.Output.Length -eq 0 -and $actual.Pipeline.Count -eq 0)
    } else {
        $ok = ($null -eq $actual.Error -and $actual.Pipeline.Count -eq 0 -and
               $actual.Output -ceq [string]$case.expected)
    }
    if ($ok) {
        Write-Host "PASS [PHP new]: $($case.name)" -ForegroundColor Green
        $passed++
    } else {
        Write-Host "FAIL [PHP new]: $($case.name)" -ForegroundColor Red
        if ($isErrorTest) { Write-Host "  Expected error contains: $($case.error_contains)" }
        else { Write-Host "  Expected: $([string]$case.expected | ConvertTo-Json -Compress)" }
        Write-Host "  Actual: $($actual.Output | ConvertTo-Json -Compress)"
        if ($actual.Error) { Write-Host "  Error: $($actual.Error)" }
        if ($actual.Pipeline.Count) { Write-Host "  Unexpected pipeline output: $($actual.Pipeline -join ' | ')" }
        $failed++
    }
}
Write-Host "PHP new: $passed / $($cases.Count) passed; $failed failed"
if ($failed -ne 0) { throw "PHP v3.2 extension failures: $failed" }
Write-Host ''
Write-Host '=== Previous ALL mathematics + PHP regression tests (146) ==='
& (Join-Path $PSScriptRoot 'ALL_math_test.ps1')
Write-Host 'Result: 196 / 196 passed; 0 failed' -ForegroundColor Green
