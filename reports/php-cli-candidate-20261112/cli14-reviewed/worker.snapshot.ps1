# Opt-in CLI entry for a candidate that returns real exit status in CliContext.
# No output rewriting, inferred reference errors, or official runtime delegation.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$AdapterPath,
    [Parameter(Mandatory=$true)][string]$SourcePath
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Utility\Microsoft.PowerShell.Utility.psd1') -ErrorAction Stop
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
[Console]::InputEncoding = New-Object System.Text.UTF8Encoding($false)
try {
    $source = (Resolve-Path -LiteralPath $SourcePath).ProviderPath
    $code = [IO.File]::ReadAllText($source, (New-Object System.Text.UTF8Encoding($false,$true)))
    $adapter = & $AdapterPath
    if ($null -eq $adapter -or $adapter.Run -isnot [scriptblock]) { throw 'Candidate did not return Run' }
    $context = @{ SourcePath=$source; ExitCode=[long]0; Terminated=$false }
    & ($adapter.Run) -Code $code -CliContext $context
    $bits = [uint32]$context.ExitCode
    $signed = [BitConverter]::ToInt32([BitConverter]::GetBytes($bits),0)
    [Environment]::Exit($signed)
} catch {
    # Unimplemented parser/host failures stay real failures, not forged PHP text.
    [Console]::Error.WriteLine($_.Exception.Message)
    [Environment]::Exit(1)
}
