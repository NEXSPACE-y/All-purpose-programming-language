# Executes only ALL's candidate interpreter. Never invokes the PHP oracle.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$AdapterPath,
    [Parameter(Mandatory = $true)][string]$SourcePath
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Utility\Microsoft.PowerShell.Utility.psd1') -ErrorAction Stop
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
[Console]::InputEncoding = New-Object System.Text.UTF8Encoding($false)
try {
    $adapter = & $AdapterPath
    if ($null -eq $adapter -or $adapter.Run -isnot [scriptblock]) {
        throw 'The candidate did not return a PHP adapter'
    }
    $code = [IO.File]::ReadAllText($SourcePath, (New-Object System.Text.UTF8Encoding($false, $true)))
    & ($adapter.Run) -Code $code -PhpDiagnostics
    exit 0
} catch {
    # Preserve candidate failure as observed. Do not synthesize PHP exit/status/diagnostics.
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
