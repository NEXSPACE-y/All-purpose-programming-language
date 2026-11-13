# Candidate-only preflight and 808 test cases. Does not install ALL.
[CmdletBinding()]
param([switch]$CompileCSharp)
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'ALL_preflight.ps1') -CompileCSharp:$CompileCSharp
& (Join-Path $PSScriptRoot 'ALL_PHP_v3_13_test.ps1')
