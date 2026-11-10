# Regenerates package/SHA256SUMS.txt (the manifest that package/ALL_preflight.ps1 verifies).
# Run after every intentional change inside package/. ASCII only.
[CmdletBinding()]
param([string]$PackageDir = '')
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrEmpty($PackageDir)) {
    $PackageDir = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) '..\package'
}
$root = (Resolve-Path -LiteralPath $PackageDir).Path
$manifest = Join-Path $root 'SHA256SUMS.txt'
$entries = New-Object System.Collections.Generic.List[string]
$files = Get-ChildItem -LiteralPath $root -File -Recurse | Where-Object { $_.FullName -ne $manifest }
$relative = foreach ($file in $files) { $file.FullName.Substring($root.Length + 1).Replace('\', '/') }
$sorted = [string[]]@($relative)
[Array]::Sort($sorted, [StringComparer]::Ordinal)
foreach ($rel in $sorted) {
    $hash = (Get-FileHash -LiteralPath (Join-Path $root $rel) -Algorithm SHA256).Hash
    $entries.Add("$hash  $rel")
}
$text = ($entries -join "`n") + "`n"
$utf8Bom = New-Object System.Text.UTF8Encoding($true)
[IO.File]::WriteAllText($manifest, $text, $utf8Bom)
Write-Host "SHA256SUMS.txt: $($entries.Count) files"
