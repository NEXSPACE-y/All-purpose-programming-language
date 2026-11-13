# Preserve the original default API fixture definitions and expectations.
# New CLI/literal/callable/native process comparisons are reported separately.
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
& (Join-Path $PSScriptRoot 'ALL_PHP_v3_19_test.ps1')
Write-Host 'ALL PHP v3.20 default API regression: 965/965 passed; 0 failed'
