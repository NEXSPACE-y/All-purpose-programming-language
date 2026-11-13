# Preserve every existing v3.16 test and expectation, then check the new oracle cases.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'ALL_PHP_v3_16_test.ps1')
& (Join-Path $PSScriptRoot 'ALL_PHP_v3_17_namespace_test.ps1')
Write-Host 'ALL PHP v3.17 direct candidate: 965/965 passed; 0 failed'
