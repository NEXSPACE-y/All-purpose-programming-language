# Read-only v3.7 validation: ALL installation unchanged.
[CmdletBinding()]
param([switch]$CompileCSharp)
$ErrorActionPreference='Stop'
& (Join-Path $PSScriptRoot 'ALL_preflight.ps1') -CompileCSharp:$CompileCSharp
& (Join-Path $PSScriptRoot 'ALL_PHP_v3_7_test.ps1')
