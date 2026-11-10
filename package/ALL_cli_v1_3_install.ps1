$ErrorActionPreference='Stop'
$dest=Join-Path $HOME 'ALL'
if(-not (Test-Path -LiteralPath (Join-Path $dest 'ALL.ps1') -PathType Leaf)) { throw 'ALL Core is missing' }
$languageDir=Join-Path $dest 'languages'
$target=Join-Path $languageDir 'all.ps1'
if(-not (Test-Path -LiteralPath $target -PathType Leaf)) { throw 'Existing ALL adapter is missing' }
$files=[ordered]@{
    'ALL_v1_0_adapter.ps1'='languages\all.ps1'
    'ALL_cli.ps1'='ALL_cli.ps1'
    'ALL_cli_host.ps1'='ALL_cli_host.ps1'
    'all.cmd'='all.cmd'
}
# Syntax validation prior to touching the installation.
foreach($ps in @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1' -File)) {
    $t=$null; $e=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile($ps.FullName,[ref]$t,[ref]$e)
    if($e.Count -gt 0) { throw "PowerShell syntax error in $($ps.Name): $($e[0].Message)" }
}
$backups=[System.Collections.Generic.List[object]]::new()
try {
    foreach($name in $files.Keys) {
        $source=Join-Path $PSScriptRoot $name
        $destination=Join-Path $dest $files[$name]
        if(-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Missing package file $name" }
        $previous=(Test-Path -LiteralPath $destination -PathType Leaf)
        $backup=$destination+'.bak.'+[guid]::NewGuid().ToString('N')
        if($previous) { Copy-Item -LiteralPath $destination -Destination $backup -ErrorAction Stop }
        [void]$backups.Add([pscustomobject]@{File=$destination;Backup=$backup;Previous=$previous})
        Copy-Item -LiteralPath $source -Destination $destination -Force -ErrorAction Stop
    }
    & (Join-Path $PSScriptRoot 'ALL_cli_v1_3_test.ps1')
    & (Join-Path $PSScriptRoot 'ALL_cli_web_v1_2_test.ps1')
    Write-Host '=== Previous 467 regression cases ==='
    & (Join-Path $PSScriptRoot 'ALL_cli_http_v1_1_test.ps1')
    & (Join-Path $PSScriptRoot 'ALL_v1_0_test.ps1')
    & (Join-Path $PSScriptRoot 'ALL_http_v0_9_test.ps1')
    & (Join-Path $PSScriptRoot 'ALL_http_v0_8_test.ps1')
    & (Join-Path $PSScriptRoot 'ALL_module_v0_7_test.ps1')
    & (Join-Path $PSScriptRoot 'ALL_Japanese_grammar_v0_6_test.ps1')
    & (Join-Path $PSScriptRoot 'ALL_language_v0_5_test.ps1')
    & (Join-Path $PSScriptRoot 'ALL_JP_v0_4_test.ps1')
    & (Join-Path $PSScriptRoot 'ALL_language_v0_3_test.ps1')
    & (Join-Path $PSScriptRoot 'ALL_PHP_v3_2_test.ps1')
    Write-Host 'ALL v1.3 CLI installed; 8 new CLI tests and 478 original regressions passed.' -ForegroundColor Green
} catch {
    $reason=$_.Exception.Message
    # Rollback in reverse order, including files newly added by this installer.
    for($i=$backups.Count-1; $i -ge 0; $i--) {
        $item=$backups[$i]
        if($item.Previous) { Copy-Item -LiteralPath $item.Backup -Destination $item.File -Force }
        elseif(Test-Path -LiteralPath $item.File) { Remove-Item -LiteralPath $item.File -Force }
    }
    Write-Warning 'New installation failed; original ALL files restored.'
    throw "ALL v1.3 CLI installation cancelled: $reason"
}
