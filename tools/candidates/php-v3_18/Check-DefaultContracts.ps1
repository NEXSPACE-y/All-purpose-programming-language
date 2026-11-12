# Reads original fixture definitions unchanged, invokes isolated candidate with
# no CliContext, and checks the original stdout/error_contains assertions.
[CmdletBinding()]
param(
    [string]$AdapterPath = '',
    [Parameter(Mandatory=$true)][string]$ReportPath
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Utility\Microsoft.PowerShell.Utility.psd1') -ErrorAction Stop
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrEmpty($AdapterPath)) { $AdapterPath = Join-Path $here 'ALL_PHP_v3_18_candidate.ps1' }
$root = (Resolve-Path (Join-Path $here '..\..\..')).ProviderPath
$adapter = & $AdapterPath
$run = $adapter.Run
$adapterBefore = (Get-FileHash -LiteralPath $AdapterPath -Algorithm SHA256).Hash
$collections = @(
    @{File='PHP_v3_15_diagnostics_oracle_cases.json'; Diagnostics=$true},
    @{File='PHP_v3_16_namespaces_oracle_cases.json'; Diagnostics=$false},
    @{File='PHP_v3_17_namespace_runtime_oracle_cases.json'; Diagnostics=$false}
)
$rows = [System.Collections.Generic.List[object]]::new()
$fixtures = [System.Collections.Generic.List[object]]::new()
foreach ($collection in $collections) {
    $path = Join-Path (Join-Path $root 'package') $collection.File
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    $cases = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($path))
    foreach ($case in $cases) {
        $writer = New-Object System.IO.StringWriter([Globalization.CultureInfo]::InvariantCulture)
        $errorWriter = New-Object System.IO.StringWriter([Globalization.CultureInfo]::InvariantCulture)
        $savedOut = [Console]::Out
        $savedError = [Console]::Error
        $failure = $null
        $pipeline = @()
        try {
            [Console]::SetOut($writer)
            [Console]::SetError($errorWriter)
            if ($collection.Diagnostics) { $pipeline = @(& $run -Code $case.code -PhpDiagnostics) }
            else { $pipeline = @(& $run -Code $case.code) }
        } catch { $failure = $_.Exception.Message }
        finally { [Console]::SetOut($savedOut); [Console]::SetError($savedError) }
        $output = $writer.ToString()
        $stderr = $errorWriter.ToString()
        $writer.Dispose(); $errorWriter.Dispose()
        if ($null -ne $case.error_contains) {
            $pass = $null -ne $failure -and $failure.Contains([string]$case.error_contains) -and $output.Length -eq 0 -and $pipeline.Count -eq 0
        } else {
            $pass = $null -eq $failure -and $output -ceq [string]$case.expected -and $pipeline.Count -eq 0
        }
        $pass = $pass -and $stderr.Length -eq 0
        $rows.Add([ordered]@{fixture=$collection.File; id=$case.name; passed=$pass; stdout=$output; stderr=$stderr; error=$failure; pipeline_count=$pipeline.Count})
    }
    $fixtures.Add([ordered]@{path=$path; sha256_before=$hash; sha256_after=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash})
}
$passed = @($rows | Where-Object {$_.passed}).Count
$report = [ordered]@{
    status=if($passed -eq $rows.Count){'PASS'}else{'FAIL'}
    scope='Selected original21 diagnostics/27 namespaces/25 runtime namespace fixtures, original expected values, no CliContext. Full965 not rerun here.'
    total=$rows.Count; passed=$passed; results=$rows.ToArray(); fixture_inputs=$fixtures.ToArray()
    adapter_sha256_before=$adapterBefore; adapter_sha256_after=(Get-FileHash -LiteralPath $AdapterPath -Algorithm SHA256).Hash
}
$utf8=New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($ReportPath,($report | ConvertTo-Json -Depth 8),$utf8)
Write-Output ([pscustomobject]@{status=$report.status;total=$report.total;passed=$report.passed} | ConvertTo-Json -Compress)
if($passed -ne $rows.Count){exit 1}
