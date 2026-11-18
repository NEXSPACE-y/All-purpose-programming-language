# Interactive debugger / JSONL step trace for ALL.
[CmdletBinding()]
param(
 [Parameter(Mandatory)][string]$File,
 [string]$Breakpoints='',
 [string]$TracePath="$HOME/ALL_trace.jsonl"
)
$ErrorActionPreference='Stop'
$previousTrace=[Environment]::GetEnvironmentVariable('ALL_TRACE_PATH','Process')
$previousBreakpoints=[Environment]::GetEnvironmentVariable('ALL_BREAKPOINT_LINES','Process')
try {
    [Environment]::SetEnvironmentVariable('ALL_TRACE_PATH',[IO.Path]::GetFullPath($TracePath),'Process')
    [Environment]::SetEnvironmentVariable('ALL_BREAKPOINT_LINES',$Breakpoints,'Process')
    & (Join-Path $HOME 'ALL/run.ps1') -File ([IO.Path]::GetFullPath($File)) -Language ALL
} finally {
    [Environment]::SetEnvironmentVariable('ALL_TRACE_PATH',$previousTrace,'Process')
    [Environment]::SetEnvironmentVariable('ALL_BREAKPOINT_LINES',$previousBreakpoints,'Process')
}
