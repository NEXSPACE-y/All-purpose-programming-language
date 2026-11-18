# ALL source-file runner. This does not modify ALL.ps1.
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$File,
    [ValidateSet('ALL','PHP')]
    [string]$Language = 'ALL'
)
$ErrorActionPreference = 'Stop'
$core = Join-Path $PSScriptRoot 'ALL.ps1'
if (-not (Test-Path -LiteralPath $core -PathType Leaf)) {
    throw "ALL Core not found: $core"
}
$full = (Resolve-Path -LiteralPath $File -ErrorAction Stop).ProviderPath
if ([System.IO.Path]::GetExtension($full) -cnotin @('.all','.php')) {
    throw "ALL Runner: expected .all or .php source file"
}
$source = [System.IO.File]::ReadAllText($full,[System.Text.UTF8Encoding]::new($false,$true))
if ($source.Length -gt 100000) { throw 'ALL Runner: Source too large' }
# Imports resolve from the source directory, not from the current shell folder.
# Restore the previous process environment even if source execution throws.
$previousModuleRoot = [Environment]::GetEnvironmentVariable('ALL_MODULE_ROOT','Process')
$previousSourceFile = [Environment]::GetEnvironmentVariable('ALL_SOURCE_FILE','Process')
try {
    [Environment]::SetEnvironmentVariable('ALL_MODULE_ROOT',[System.IO.Path]::GetDirectoryName($full),'Process')
    # Metadata for diagnostic source mapping only; never changes ALL semantics.
    [Environment]::SetEnvironmentVariable('ALL_SOURCE_FILE',$full,'Process')
    & $core -Language $Language -Code $source
} finally {
    [Environment]::SetEnvironmentVariable('ALL_MODULE_ROOT',$previousModuleRoot,'Process')
    [Environment]::SetEnvironmentVariable('ALL_SOURCE_FILE',$previousSourceFile,'Process')
}
