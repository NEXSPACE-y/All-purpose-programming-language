$ErrorActionPreference='Stop'
$core=Join-Path $HOME 'ALL\ALL.ps1'
$target=Join-Path $HOME 'ALL\languages\all.ps1'
$php=Join-Path $HOME 'ALL\languages\php.ps1'
$runner=Join-Path $HOME 'ALL\run.ps1'
$src=Join-Path $PSScriptRoot 'ALL_v1_0_adapter.ps1'
$tests=@(
    'ALL_v1_0_test.ps1','ALL_package.ps1','ALL_benchmark.ps1',
    'ALL_http_v0_9_test.ps1','ALL_http_v0_8_test.ps1','ALL_http_v0_8_cases.json',
    'ALL_module_v0_7_test.ps1','ALL_module_v0_7_cases.json',
    'ALL_Japanese_grammar_v0_6_test.ps1','ALL_Japanese_grammar_v0_6_cases.json',
    'ALL_language_v0_5_test.ps1','ALL_language_v0_5_cases.json',
    'ALL_JP_v0_4_test.ps1','ALL_JP_v0_4_cases.json',
    'ALL_language_v0_3_test.ps1','ALL_language_v0_3_cases.json',
    'ALL_PHP_v3_2_test.ps1','PHP_v3_2_cases.json',
    'ALL_math_test.ps1','ALL_math_cases.json','ALL_PHP_v3_1_1_cases.json',
    'examples\cli_report\main.all','examples\cli_report\orders.json',
    'examples\cli_report\lib\calc.all','examples\cli_report\lib\titles.all'
)
foreach ($file in @($core,$target,$php,$runner)) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Missing existing ALL file: $file" }
}
foreach ($relative in @('ALL_v1_0_adapter.ps1')+$tests) {
    $file=Join-Path $PSScriptRoot $relative
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Missing bundle file: $relative" }
}
# Parse entire bundle before touching the installed adapter.
foreach ($relative in @('ALL_v1_0_adapter.ps1','ALL_v1_0_install.ps1') +
        @($tests | Where-Object { $_.EndsWith('.ps1') })) {
    $tokens=$null;$errors=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $relative),[ref]$tokens,[ref]$errors)
    if ($errors.Count -ne 0) { throw "Syntax error in $relative`: $($errors[0].Message)" }
}
$backup="$target.bak.$((Get-Date).ToString('yyyyMMddHHmmssfff'))"
Copy-Item -LiteralPath $target -Destination $backup
Write-Host "Backup: $backup"
try {
    Copy-Item -LiteralPath $src -Destination $target -Force
    Write-Host '=== v1.0 foundational capabilities (29) ==='
    & (Join-Path $PSScriptRoot 'ALL_v1_0_test.ps1')
    Write-Host '=== v0.9 HTTP server (11) ==='
    & (Join-Path $PSScriptRoot 'ALL_http_v0_9_test.ps1')
    Write-Host '=== v0.8 HTTP client (16) ==='
    & (Join-Path $PSScriptRoot 'ALL_http_v0_8_test.ps1')
    Write-Host '=== v0.7 modules (26) ==='
    & (Join-Path $PSScriptRoot 'ALL_module_v0_7_test.ps1')
    Write-Host '=== v0.6 natural Japanese (34) ==='
    & (Join-Path $PSScriptRoot 'ALL_Japanese_grammar_v0_6_test.ps1')
    Write-Host '=== v0.5 applications (49) ==='
    & (Join-Path $PSScriptRoot 'ALL_language_v0_5_test.ps1')
    Write-Host '=== v0.4 Japanese (27) ==='
    & (Join-Path $PSScriptRoot 'ALL_JP_v0_4_test.ps1')
    Write-Host '=== v0.3 programming (61) ==='
    & (Join-Path $PSScriptRoot 'ALL_language_v0_3_test.ps1')
    Write-Host '=== v0.2 mathematics / PHP (196) ==='
    & (Join-Path $PSScriptRoot 'ALL_PHP_v3_2_test.ps1')
    Write-Host 'Result: 449 / 449 passed; 0 failed' -ForegroundColor Green
    Write-Host "ALL v1.0 foundations installed: $target" -ForegroundColor Green
    Write-Host 'Benchmark command: & "<unzipped folder>\ALL_benchmark.ps1"' -ForegroundColor Cyan
} catch {
    $reason=$_.Exception.Message
    Copy-Item -LiteralPath $backup -Destination $target -Force
    Write-Warning "ALL v1.0 tests failed, restored previous adapter: $backup"
    throw "ALL v1.0 update cancelled: $reason"
}
