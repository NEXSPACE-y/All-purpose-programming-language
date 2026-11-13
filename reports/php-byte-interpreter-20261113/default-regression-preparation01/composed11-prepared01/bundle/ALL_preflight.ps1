# ALL integrated package: read-only preflight, no changes to installed ALL.
# Checks every packaged PowerShell script, SHA-256, and optional Windows C# compilation.
[CmdletBinding()]
param([switch]$CompileCSharp)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$issues = [System.Collections.Generic.List[string]]::new()

# Parse all .ps1 files, including nested validation scripts, before touching ALL.
$scripts = @(Get-ChildItem -LiteralPath $root -Filter '*.ps1' -File -Recurse)
foreach ($file in $scripts) {
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        $file.FullName, [ref]$tokens, [ref]$parseErrors
    )
    foreach ($problem in $parseErrors) {
        $relative = $file.FullName.Substring($root.Length) -replace '^[\\/]+', ''
        $lineNumber = $problem.Extent.StartLineNumber
        $columnNumber = $problem.Extent.StartColumnNumber
        [void]$issues.Add("${relative} line ${lineNumber} col ${columnNumber}: $($problem.Message)")
    }
}
if ($issues.Count -gt 0) {
    foreach ($problem in $issues) { Write-Host "FAIL [PowerShell Syntax] $problem" -ForegroundColor Red }
    throw "Preflight rejected: $($issues.Count) PowerShell syntax error(s). No installed ALL files were changed."
}
Write-Host "PASS [PowerShell Syntax]: $($scripts.Count) scripts" -ForegroundColor Green

# Verify every packaged file against the manifest (and reject unlisted files).
$manifestPath = Join-Path $root 'SHA256SUMS.txt'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw 'Preflight rejected: missing SHA256SUMS.txt'
}
$lines = @(Get-Content -LiteralPath $manifestPath -Encoding UTF8 | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($line in $lines) {
    if ($line -match '^([0-9a-fA-F]{64})  (.+)$') {
        # $Matches is populated only by a successful -match.
    } else {
        [void]$issues.Add('Malformed SHA256SUMS.txt entry')
        continue
    }
    $expected = $Matches[1].ToUpperInvariant()
    $rel = $Matches[2]
    if ([IO.Path]::IsPathRooted($rel) -or $rel -match '(^|/|\\)\.\.(/|\\|$)') {
        [void]$issues.Add("Unsafe manifest path: $rel")
        continue
    }
    if (-not $seen.Add($rel)) {
        [void]$issues.Add("Duplicate manifest path: $rel")
        continue
    }
    $path = Join-Path $root $rel
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        [void]$issues.Add("Missing manifest file: $rel")
        continue
    }
    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    if ($actual -cne $expected) { [void]$issues.Add("SHA-256 mismatch: $rel") }
}
$packaged = @(Get-ChildItem -LiteralPath $root -File -Recurse | Where-Object { $_.FullName -ne $manifestPath })
if ($packaged.Count -ne $seen.Count) {
    [void]$issues.Add("Manifest coverage: $($seen.Count) entries for $($packaged.Count) files")
}
if ($issues.Count -gt 0) {
    foreach ($problem in $issues) { Write-Host "FAIL [Package] $problem" -ForegroundColor Red }
    throw "Preflight rejected: $($issues.Count) package integrity problem(s). No installed ALL files were changed."
}
Write-Host "PASS [SHA-256]: $($seen.Count) packaged files" -ForegroundColor Green

if ($CompileCSharp) {
    if (-not [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)) {
        throw 'C# Windows preflight requested on a non-Windows host'
    }
    $assemblies = @(
        @{ File='ALL_sqlite_driver.cs'; Name='AllSqliteDriver' },
        @{ File='ALL_ConcurrentGateway.cs'; Name='AllConcurrentGateway' }
    )
    foreach ($entry in $assemblies) {
        if (-not ($entry.Name -as [type])) {
            Add-Type -Path (Join-Path $root $entry.File) -ErrorAction Stop
        }
        Write-Host "PASS [C# Compilation]: $($entry.File)" -ForegroundColor Green
    }
}
Write-Host 'ALL preflight PASS. No installed ALL files were changed.' -ForegroundColor Green
