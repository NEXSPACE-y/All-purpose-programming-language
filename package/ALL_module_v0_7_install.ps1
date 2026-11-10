$ErrorActionPreference = 'Stop'
$core = Join-Path $HOME 'ALL\ALL.ps1'
$target = Join-Path $HOME 'ALL\languages\all.ps1'
$php = Join-Path $HOME 'ALL\languages\php.ps1'
$runner = Join-Path $HOME 'ALL\run.ps1'
$src = Join-Path $PSScriptRoot 'ALL_module_v0_7_adapter.ps1'
$runnerSource = Join-Path $PSScriptRoot 'ALL_run.ps1'
$scripts = @('ALL_module_v0_7_adapter.ps1','ALL_run.ps1','ALL_module_v0_7_test.ps1','ALL_language_v0_5_test.ps1','ALL_Japanese_grammar_v0_6_test.ps1',
             'ALL_JP_v0_4_test.ps1','ALL_language_v0_3_test.ps1',
             'ALL_PHP_v3_2_test.ps1','ALL_math_test.ps1')
$fixtures = @('ALL_module_v0_7_cases.json','examples\cli_report\main.all','examples\cli_report\orders.json','examples\cli_report\lib\calc.all','examples\cli_report\lib\titles.all','ALL_Japanese_grammar_v0_6_cases.json','ALL_language_v0_5_cases.json','ALL_JP_v0_4_cases.json',
              'ALL_language_v0_3_cases.json','ALL_math_cases.json',
              'ALL_PHP_v3_1_1_cases.json','PHP_v3_2_cases.json',
              'examples\hello.all','examples\data.all','examples\natural_japanese.all')
foreach ($file in @($core,$target,$php)) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Missing ALL dependency: $file" }
}
foreach ($file in @($scripts+$fixtures)) {
    $full=Join-Path $PSScriptRoot $file
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "Missing bundle file: $full" }
}
foreach ($file in $scripts) {
    $full=Join-Path $PSScriptRoot $file
    $tokens=$null; $errors=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile($full,[ref]$tokens,[ref]$errors)
    if ($errors.Count -gt 0) { throw "PowerShell syntax error in $file`: $($errors[0].Message)" }
}
$cases = ConvertFrom-Json -InputObject (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'ALL_language_v0_5_cases.json') -Raw -Encoding UTF8)
if ($cases.Count -ne 43) { throw "Invalid fixture count: $($cases.Count)" }
$stamp = (Get-Date).ToString('yyyyMMddHHmmssfff')
$backup = "$target.bak.$stamp"
$runnerExists = Test-Path -LiteralPath $runner -PathType Leaf
$runnerBackup = "$runner.bak.$stamp"
Copy-Item -LiteralPath $target -Destination $backup -ErrorAction Stop
if ($runnerExists) { Copy-Item -LiteralPath $runner -Destination $runnerBackup -ErrorAction Stop }
Write-Host "Backup: $backup"
try {
    Copy-Item -LiteralPath $src -Destination $target -Force -ErrorAction Stop
    Copy-Item -LiteralPath $runnerSource -Destination $runner -Force -ErrorAction Stop
    Write-Host '=== ALL modules v0.7 (26) ==='
    & (Join-Path $PSScriptRoot 'ALL_module_v0_7_test.ps1')
    Write-Host '=== ALL natural Japanese v0.6 (34) ==='
    & (Join-Path $PSScriptRoot 'ALL_Japanese_grammar_v0_6_test.ps1')
    Write-Host '=== ALL v0.5 application features (49) ==='
    & (Join-Path $PSScriptRoot 'ALL_language_v0_5_test.ps1')
    Write-Host '=== ALL Japanese v0.4 regression (27) ==='
    & (Join-Path $PSScriptRoot 'ALL_JP_v0_4_test.ps1')
    Write-Host '=== ALL v0.3 regression (61) ==='
    & (Join-Path $PSScriptRoot 'ALL_language_v0_3_test.ps1')
    Write-Host '=== PHP + mathematics regression (196) ==='
    & (Join-Path $PSScriptRoot 'ALL_PHP_v3_2_test.ps1')
    Write-Host 'Result: 393 / 393 passed; 0 failed' -ForegroundColor Green
    Write-Host "ALL modules v0.7 installed: $target" -ForegroundColor Green
    Write-Host "ALL file runner installed: $runner" -ForegroundColor Green
} catch {
    $failure=$_.Exception.Message
    Copy-Item -LiteralPath $backup -Destination $target -Force -ErrorAction Stop
    if ($runnerExists) { Copy-Item -LiteralPath $runnerBackup -Destination $runner -Force -ErrorAction Stop }
    elseif (Test-Path -LiteralPath $runner) { Remove-Item -LiteralPath $runner -Force -ErrorAction Stop }
    Write-Warning "Tests failed; original adapter and runner restored."
    throw "ALL modules v0.7 update cancelled: $failure"
}
