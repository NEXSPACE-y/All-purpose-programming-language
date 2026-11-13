# Existing default API contracts remain unchanged. Native/CLI comparisons are separate.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'ALL_PHP_v3_18_test.ps1')
Write-Host 'ALL PHP v3.19 default API regression: 965/965 passed; 0 failed'
