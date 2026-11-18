param(
    [string]$Language,
    [string]$Code
)

$ErrorActionPreference = "Stop"
$registry = @{}
$dir = Join-Path $PSScriptRoot "languages"

foreach ($file in @(Get-ChildItem -LiteralPath $dir -Filter "*.ps1" -File)) {
    $adapter = & $file.FullName

    if ($null -eq $adapter -or
        [string]::IsNullOrWhiteSpace([string]$adapter.Name) -or
        $adapter.Run -isnot [scriptblock]) {
        throw "Invalid adapter: $($file.Name)"
    }

    if ($registry.ContainsKey($adapter.Name)) {
        throw "Duplicate language: $($adapter.Name)"
    }

    $registry[$adapter.Name] = $adapter.Run
}

if ([string]::IsNullOrWhiteSpace($Language)) {
    Write-Output "ALL Core: READY"
    Write-Output "Registered languages: $($registry.Count)"
    return
}

if (-not $registry.ContainsKey($Language)) {
    throw "Unsupported language: $Language"
}

& ($registry[$Language]) $Code
