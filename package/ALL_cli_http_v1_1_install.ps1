$ErrorActionPreference='Stop'
$target = Join-Path $HOME 'ALL\languages\all.ps1'
$cliTarget = Join-Path $HOME 'ALL\ALL_cli.ps1'
$core = Join-Path $HOME 'ALL\ALL.ps1'
$runner = Join-Path $HOME 'ALL\run.ps1'
$src = Join-Path $PSScriptRoot 'ALL_v1_0_adapter.ps1'
$cliSrc = Join-Path $PSScriptRoot 'ALL_cli.ps1'
$firstTest = Join-Path $PSScriptRoot 'ALL_cli_http_v1_1_test.ps1'
foreach ($file in @($target,$core,$runner,$src,$cliSrc,$firstTest)) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Missing file: $file" }
}
# Check all scripts for syntax before installing anything.
$scripts = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1' -File)
foreach ($script in $scripts) {
    $tokens=$null; $errors=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile($script.FullName,[ref]$tokens,[ref]$errors)
    if ($errors.Count -ne 0) { throw "Syntax error in $($script.Name): $($errors[0].Message)" }
}
$backup = "$target.bak.$((Get-Date).ToString('yyyyMMddHHmmssfff'))"
$hadCli = Test-Path -LiteralPath $cliTarget -PathType Leaf
$cliBackup = "$cliTarget.bak.$((Get-Date).ToString('yyyyMMddHHmmssfff'))"
Copy-Item -LiteralPath $target -Destination $backup
if ($hadCli) { Copy-Item -LiteralPath $cliTarget -Destination $cliBackup }
Write-Host "Backup: $backup"
try {
    Copy-Item -LiteralPath $src -Destination $target -Force
    Copy-Item -LiteralPath $cliSrc -Destination $cliTarget -Force
    Write-Host '=== ALL CLI + HTTP v1.1 tests ==='
    & $firstTest
    # The legacy 449 test suite is untouched.
    Write-Host '=== Previous 449 regression cases ==='
    & (Join-Path $PSScriptRoot 'ALL_v1_0_test.ps1')
    & (Join-Path $PSScriptRoot 'ALL_http_v0_9_test.ps1')
    & (Join-Path $PSScriptRoot 'ALL_http_v0_8_test.ps1')
    & (Join-Path $PSScriptRoot 'ALL_module_v0_7_test.ps1')
    & (Join-Path $PSScriptRoot 'ALL_Japanese_grammar_v0_6_test.ps1')
    & (Join-Path $PSScriptRoot 'ALL_language_v0_5_test.ps1')
    & (Join-Path $PSScriptRoot 'ALL_JP_v0_4_test.ps1')
    & (Join-Path $PSScriptRoot 'ALL_language_v0_3_test.ps1')
    & (Join-Path $PSScriptRoot 'ALL_PHP_v3_2_test.ps1')
    Write-Host 'ALL CLI/HTTP v1.1 installed; all regression scripts passed.' -ForegroundColor Green
} catch {
    $reason=$_.Exception.Message
    Copy-Item -LiteralPath $backup -Destination $target -Force
    if ($hadCli) { Copy-Item -LiteralPath $cliBackup -Destination $cliTarget -Force }
    elseif (Test-Path -LiteralPath $cliTarget) { Remove-Item -LiteralPath $cliTarget -Force }
    Write-Warning 'Tests failed; prior ALL adapter and CLI restored.'
    throw "ALL v1.1 update cancelled: $reason"
}
