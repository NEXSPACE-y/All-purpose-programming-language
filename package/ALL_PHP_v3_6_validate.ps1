# ALL PHP v3.6 read-only validation. Requires successful preflight before tests.
[CmdletBinding()]
param([switch]$CompileCSharp)
$ErrorActionPreference='Stop'
& (Join-Path $PSScriptRoot 'ALL_preflight.ps1') -CompileCSharp:$CompileCSharp
& (Join-Path $PSScriptRoot 'ALL_PHP_v3_6_test.ps1')
