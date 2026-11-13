# Candidate-only preflight and default API regression. Does not install ALL.
[CmdletBinding()]
param([switch]$CompileCSharp)
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'ALL_preflight.ps1') -CompileCSharp:$CompileCSharp
& (Join-Path $PSScriptRoot 'ALL_PHP_v3_18_test.ps1')
