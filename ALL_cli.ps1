# ALL CLI v1.1: optional command interface. Does not modify ALL Core.
param(
    [ValidateSet('run','help','version')]
    [string]$Command = 'help',
    [string]$File,
    [ValidateSet('ALL','PHP')]
    [string]$Language = 'ALL',
    [string[]]$ScriptArgs = @()
)
$ErrorActionPreference = 'Stop'
$runner = Join-Path $PSScriptRoot 'run.ps1'
if ($Command -eq 'help') {
    [Console]::WriteLine('ALL CLI v1.1')
    [Console]::WriteLine('Usage: ALL_cli.ps1 -Command run -File program.all [-Language ALL] [-ScriptArgs @("a","b")]')
    [Console]::WriteLine('       ALL_cli.ps1 -Command version | help')
    return
}
if ($Command -eq 'version') {
    [Console]::WriteLine('ALL CLI v1.1 (ALL interpreter compatibility extension)')
    return
}
if (-not (Test-Path -LiteralPath $runner -PathType Leaf)) {
    throw "ALL CLI: Runner not found: $runner"
}
if ([string]::IsNullOrWhiteSpace($File)) { throw 'ALL CLI: -File is required for run' }
if ($Language -eq 'PHP' -and $ScriptArgs.Count -ne 0) {
    throw 'ALL CLI: -ScriptArgs is supported only for ALL, not PHP'
}
if ($ScriptArgs.Count -gt 64) { throw 'ALL CLI: Maximum 64 arguments' }
foreach ($item in $ScriptArgs) {
    if ($null -eq $item -or $item.Length -gt 4096) { throw 'ALL CLI: Argument too long' }
}
$previousArgs = [Environment]::GetEnvironmentVariable('ALL_SCRIPT_ARGS_JSON','Process')
try {
    # Caller-controlled values are serialized, never interpolated into ALL code.
    $payload = @{ arguments = @($ScriptArgs) } | ConvertTo-Json -Compress -Depth 4
    [Environment]::SetEnvironmentVariable('ALL_SCRIPT_ARGS_JSON',[string]$payload,'Process')
    & $runner -File $File -Language $Language
} finally {
    [Environment]::SetEnvironmentVariable('ALL_SCRIPT_ARGS_JSON',$previousArgs,'Process')
}
