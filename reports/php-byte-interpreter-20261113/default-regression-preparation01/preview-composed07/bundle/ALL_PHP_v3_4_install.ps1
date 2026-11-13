# Optional PHP-only installation with rollback; ALL language adapter untouched.
# Run ALL_PHP_v3_4_test.ps1 first. Existing ALL regression totals are NOT implied.
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$root=$PSScriptRoot
$languageDir=Join-Path $HOME 'ALL\languages'
$core=Join-Path $HOME 'ALL\ALL.ps1'
$target=Join-Path $languageDir 'php.ps1'
$source=Join-Path $root 'ALL_PHP_v3_4_adapter.ps1'
if(-not (Test-Path -LiteralPath $core -PathType Leaf)) {
    throw "ALL PHP: Core not installed: $core"
}
if(-not (Test-Path -LiteralPath $target -PathType Leaf)) {
    throw "ALL PHP: Existing PHP adapter not found: $target"
}
# All checks below finish BEFORE the installed file changes.
& (Join-Path $root 'ALL_preflight.ps1')
& (Join-Path $root 'ALL_PHP_v3_4_test.ps1')
$backup = $target + '.bak.' + [guid]::NewGuid().ToString('N')
Copy-Item -LiteralPath $target -Destination $backup -ErrorAction Stop
try {
    Copy-Item -LiteralPath $source -Destination $target -Force -ErrorAction Stop
    & (Join-Path $root 'ALL_PHP_v3_4_test.ps1') -Installed
    # Reuse the historic 196-test ALL + PHP suite against the installed core.
    & (Join-Path $root 'ALL_PHP_v3_2_test.ps1')
    Write-Host "ALL PHP-only candidate installed; backup retained: $backup" -ForegroundColor Green
    Write-Host 'The existing 523/527 integrated regression suite was NOT run by this installer.'
} catch {
    $failure = $_.Exception.Message
    Copy-Item -LiteralPath $backup -Destination $target -Force -ErrorAction Stop
    throw "ALL PHP v3.4 installation rolled back: $failure"
}
