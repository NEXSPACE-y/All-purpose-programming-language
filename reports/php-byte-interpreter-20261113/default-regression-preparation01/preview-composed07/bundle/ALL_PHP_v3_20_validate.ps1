# Isolated package validation; does not install ALL.
[CmdletBinding()]
param([switch]$CompileCSharp)
$ErrorActionPreference='Stop'
& (Join-Path $PSScriptRoot 'ALL_preflight.ps1') -CompileCSharp:$CompileCSharp
& (Join-Path $PSScriptRoot 'ALL_PHP_v3_20_test.ps1')
