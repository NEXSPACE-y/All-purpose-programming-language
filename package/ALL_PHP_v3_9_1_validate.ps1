# Read-only verification: stop on preflight failure; then run candidate PHP tests.
[CmdletBinding()]
param([switch]$CompileCSharp)
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'ALL_preflight.ps1') -CompileCSharp:$CompileCSharp
& (Join-Path $PSScriptRoot 'ALL_PHP_v3_9_1_test.ps1')
