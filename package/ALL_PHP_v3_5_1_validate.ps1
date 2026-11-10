# ALL PHP v3.5.1 read-only validation. Stop on failed preflight.
[CmdletBinding()]
param([switch]$CompileCSharp)
$ErrorActionPreference = 'Stop'
$preflight = Join-Path $PSScriptRoot 'ALL_preflight.ps1'
$test = Join-Path $PSScriptRoot 'ALL_PHP_v3_5_test.ps1'
& $preflight -CompileCSharp:$CompileCSharp
& $test
