# Read-only candidate validation. Does not install or change ALL.
[CmdletBinding()]
param([switch]$CompileCSharp)
$ErrorActionPreference='Stop'
& (Join-Path $PSScriptRoot 'ALL_preflight.ps1') -CompileCSharp:$CompileCSharp
& (Join-Path $PSScriptRoot 'ALL_PHP_v3_8_test.ps1')
