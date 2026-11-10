# ALL native core for PowerShell 7 installations; all plugins selected by language key.
param([string]$Language,[string]$Code)
$ErrorActionPreference='Stop'
$registry=@{}
$root=Join-Path $PSScriptRoot 'languages'
foreach($file in @(Get-ChildItem -LiteralPath $root -Filter '*.ps1' -File)){
    $plugin=& $file.FullName
    if(-not $plugin -or [string]::IsNullOrWhiteSpace([string]$plugin.Name) -or $plugin.Run -isnot [scriptblock]){
        throw "Invalid ALL language plugin: $($file.Name)"
    }
    if($registry.ContainsKey($plugin.Name)){throw "Duplicate plugin: $($plugin.Name)"}
    $registry[$plugin.Name]=$plugin.Run
}
if([string]::IsNullOrWhiteSpace($Language)){
    Write-Output 'ALL Core: READY'
    Write-Output ('Registered languages: '+$registry.Count)
    return
}
if(-not $registry.ContainsKey($Language)){throw "Unsupported language: $Language"}
& ($registry[$Language]) $Code
