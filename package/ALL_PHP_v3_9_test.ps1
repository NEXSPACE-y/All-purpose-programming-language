# Read-only PHP compatibility tests. Default: candidate directly (NO installation).
# -Installed: exercise the current HOME\ALL\ALL.ps1 -Language PHP pipeline instead.
[CmdletBinding()]
param([switch]$Installed)
$ErrorActionPreference = 'Stop'
$adapterPath = Join-Path $PSScriptRoot 'ALL_PHP_v3_9_adapter.ps1'
$corePath = Join-Path $HOME 'ALL\ALL.ps1'
$runPhp = $null
if ($Installed) {
    if (-not (Test-Path -LiteralPath $corePath -PathType Leaf)) {
        throw "ALL PHP v3.9: missing installed core: $corePath"
    }
} else {
    if (-not (Test-Path -LiteralPath $adapterPath -PathType Leaf)) {
        throw "ALL PHP v3.9: missing candidate: $adapterPath"
    }
    $adapter = & $adapterPath
    if ($null -eq $adapter -or $adapter.Name -cne 'PHP' -or
        $adapter.Run -isnot [scriptblock]) {
        throw 'ALL PHP v3.9: candidate did not return a PHP adapter'
    }
    $runPhp = $adapter.Run
}
function Invoke-PhpCase([string]$code) {
    $writer = [System.IO.StringWriter]::new(
        [System.Globalization.CultureInfo]::InvariantCulture)
    $saved = [Console]::Out
    $failure = $null
    $pipeline = @()
    try {
        [Console]::SetOut($writer)
        if ($Installed) { $pipeline = @(& $corePath -Language PHP -Code $code) }
        else { $pipeline = @(& $runPhp -Code $code) }
    } catch {
        $failure = $_.Exception.Message
    } finally {
        [Console]::SetOut($saved)
    }
    $value = $writer.ToString()
    $writer.Dispose()
    return [pscustomobject]@{ Output=$value; Error=$failure; Pipeline=@($pipeline) }
}
$collections = @(
    @{File='ALL_PHP_v3_1_1_cases.json'; Count=45; Category='PHP v3.1.1'},
    @{File='PHP_v3_2_cases.json'; Count=50; Category='PHP v3.2'},
    @{File='PHP_v3_3_cases.json'; Count=49; Category='PHP v3.3 reference'},
    @{File='PHP_v3_3_guard_cases.json'; Count=3; Category='PHP v3.3 fail-closed'},
    @{File='PHP_v3_4_cases.json'; Count=60; Category='PHP v3.4 native oracle'},
    @{File='PHP_v3_4_guard_cases.json'; Count=3; Category='PHP v3.4 fail-closed'},
    @{File='PHP_v3_5_variables_operators_arrays_cases.json'; Count=40; Category='PHP v3.5 variables/operators/arrays'},
    @{File='PHP_v3_5_functions_scopes_cases.json'; Count=27; Category='PHP v3.5 functions/scopes'},
    @{File='PHP_v3_5_oop_cases.json'; Count=27; Category='PHP v3.5 OOP'},
    @{File='PHP_v3_6_retained_v3_5_guards.json'; Count=6; Category='PHP v3.5 still fail-closed'},
    @{File='PHP_v3_6_implemented_prior_guards.json'; Count=2; Category='PHP v3.5 guards now supported'},
    @{File='PHP_v3_6_oop_cases.json'; Count=23; Category='PHP v3.6 OOP native oracle'},
    @{File='PHP_v3_6_reference_cases.json'; Count=22; Category='PHP v3.6 references native oracle'},
    @{File='PHP_v3_6_compound_cases.json'; Count=7; Category='PHP v3.6 compound operators native oracle'},
    @{File='PHP_v3_6_trait_cases.json'; Count=13; Category='PHP v3.6 traits native oracle'},
    @{File='PHP_v3_8_retained_v3_7_guards.json'; Count=18; Category='PHP v3.7 retained fail-closed'},
    @{File='PHP_v3_7_implemented_prior_guards.json'; Count=2; Category='PHP previously supported'},
    @{File='PHP_v3_7_native_oracle_cases.json'; Count=25; Category='PHP v3.7 dynamic variables and magic'},
    @{File='PHP_v3_7_trait_oracle_cases.json'; Count=20; Category='PHP v3.7 trait composition'},
    @{File='PHP_v3_8_implemented_prior_guards.json'; Count=1; Category='PHP previously supported'},
    @{File='PHP_v3_8_native_oracle_cases.json'; Count=47; Category='PHP v3.8 native oracle'},
    @{File='PHP_v3_9_native_oracle_cases.json'; Count=27; Category='PHP v3.9 PHP 8.4 oracle'}
)
$checked = 0
$passed = 0
$failed = 0
foreach ($entry in $collections) {
    $path = Join-Path $PSScriptRoot $entry.File
    $fixtures = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $path -Raw -Encoding UTF8)
    if (($fixtures -is [array]) -and $fixtures.Count -eq 1 -and ($fixtures[0] -is [array])) {
        $fixtures = $fixtures[0]
    }
    if ($fixtures.Count -ne $entry.Count) {
        throw "Fixture count mismatch for $($entry.File): $($fixtures.Count) expected $($entry.Count)"
    }
    foreach ($fixture in $fixtures) {
        $actual = Invoke-PhpCase ([string]$fixture.code)
        $checked++
        if ($null -ne $fixture.error_contains) {
            $ok = ($null -ne $actual.Error -and
                $actual.Error.Contains([string]$fixture.error_contains) -and
                $actual.Output.Length -eq 0 -and $actual.Pipeline.Count -eq 0)
        } else {
            $ok = ($null -eq $actual.Error -and $actual.Pipeline.Count -eq 0 -and
                $actual.Output -ceq [string]$fixture.expected)
        }
        if ($ok) {
            $passed++
            Write-Host "PASS [$($entry.Category)]: $($fixture.name)" -ForegroundColor Green
        } else {
            $failed++
            Write-Host "FAIL [$($entry.Category)]: $($fixture.name)" -ForegroundColor Red
            if ($null -ne $fixture.error_contains) {
                Write-Host "  Required error: $($fixture.error_contains)"
            } else {
                Write-Host "  Expected: $([string]$fixture.expected | ConvertTo-Json -Compress)"
            }
            Write-Host "  Actual: $($actual.Output | ConvertTo-Json -Compress)"
            if ($null -ne $actual.Error) { Write-Host "  Error: $($actual.Error)" }
            if ($actual.Pipeline.Count -gt 0) {
                Write-Host "  Unexpected PowerShell output: $($actual.Pipeline -join ', ')"
            }
        }
    }
}
# Historical PHP/ALL parity entries from mathematics regression fixtures.
$mathPath = Join-Path $PSScriptRoot 'ALL_math_cases.json'
$mathFixtures = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $mathPath -Raw -Encoding UTF8)
if (($mathFixtures -is [array]) -and $mathFixtures.Count -eq 1 -and
    ($mathFixtures[0] -is [array])) { $mathFixtures = $mathFixtures[0] }
$pairCases = @($mathFixtures | Where-Object { $_.mode -eq 'pair' })
if ($pairCases.Count -ne 17) { throw 'Expected 17 historical PHP/ALL parity cases' }
foreach ($fixture in $pairCases) {
    $actual = Invoke-PhpCase ([string]$fixture.php)
    $checked++
    $ok = ($null -eq $actual.Error -and $actual.Pipeline.Count -eq 0 -and
        $actual.Output -ceq [string]$fixture.expected)
    if ($ok) {
        $passed++
        Write-Host "PASS [historical parity]: $($fixture.name)" -ForegroundColor Green
    } else {
        $failed++
        Write-Host "FAIL [historical parity]: $($fixture.name)" -ForegroundColor Red
        Write-Host "  Expected: $($fixture.expected) / Actual: $($actual.Output)"
        if ($null -ne $actual.Error) { Write-Host "  Error: $($actual.Error)" }
    }
}
$mode = if ($Installed) { 'installed' } else { 'direct candidate' }
Write-Host "ALL PHP v3.9 ($mode): $passed/$checked passed; $failed failed"
if ($failed -gt 0) { throw "ALL PHP compatibility failures: $failed" }
