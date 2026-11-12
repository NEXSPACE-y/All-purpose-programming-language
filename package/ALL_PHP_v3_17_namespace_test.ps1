# Independent runtime-namespace regression. Expectations were obtained from PHP 8.5.12.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$adapter = & (Join-Path $PSScriptRoot 'ALL_PHP_v3_12_adapter.ps1')
if ($null -eq $adapter -or $adapter.Run -isnot [scriptblock]) { throw 'PHP adapter did not load' }
$fixtures = ConvertFrom-Json -InputObject (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'PHP_v3_17_namespace_runtime_oracle_cases.json') -Raw -Encoding UTF8)
if (($fixtures -is [array]) -and $fixtures.Count -eq 1 -and ($fixtures[0] -is [array])) {
    $fixtures = $fixtures[0]
}
if ($fixtures.Count -ne 25) { throw 'Expected 25 runtime namespace oracle cases' }
$passed = 0
foreach ($fixture in $fixtures) {
    $writer = New-Object IO.StringWriter([Globalization.CultureInfo]::InvariantCulture)
    $saved = [Console]::Out
    $failure = $null
    $pipeline = @()
    try {
        [Console]::SetOut($writer)
        $pipeline = @(& ($adapter.Run) -Code ([string]$fixture.code))
    } catch { $failure = $_.Exception.Message }
    finally { [Console]::SetOut($saved) }
    $output = $writer.ToString()
    $writer.Dispose()
    if ($null -eq $failure -and $pipeline.Count -eq 0 -and $output -ceq [string]$fixture.expected) {
        $passed++
        Write-Host "PASS [runtime namespaces]: $($fixture.name)"
    } else {
        Write-Host "FAIL [runtime namespaces]: $($fixture.name)"
        Write-Host "  Expected: $($fixture.expected | ConvertTo-Json -Compress)"
        Write-Host "  Actual: $($output | ConvertTo-Json -Compress)"
        if ($null -ne $failure) { Write-Host "  Error: $failure" }
        if ($pipeline.Count -gt 0) { Write-Host "  Unexpected pipeline output: $($pipeline -join ', ')" }
    }
}
Write-Host "ALL PHP v3.17 runtime namespaces: $passed/25 passed; $(25-$passed) failed"
if ($passed -ne 25) { throw 'Runtime namespace regression failures' }
