# Candidate-only preflight, existing 940 cases and 25 new runtime-namespace oracle cases.
[CmdletBinding()]
param([switch]$CompileCSharp)
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'ALL_preflight.ps1') -CompileCSharp:$CompileCSharp
& (Join-Path $PSScriptRoot 'ALL_PHP_v3_17_test.ps1')
