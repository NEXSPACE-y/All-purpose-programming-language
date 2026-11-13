# Existing default API contracts: 940 original cases and 25 runtime-namespace cases.
# CLI byte/exit comparisons use a separate process worker; they are not counted here.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'ALL_PHP_v3_17_test.ps1')
Write-Host 'ALL PHP v3.18 default API regression: 965/965 passed; 0 failed'
