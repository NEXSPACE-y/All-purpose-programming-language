param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('init','add','list','verify')]
    [string]$Action,
    [string]$Project='.',
    [string]$Name,
    [string]$Source,
    [string]$Version='0.1.0'
)
$ErrorActionPreference='Stop'
$projectRoot=[System.IO.Path]::GetFullPath($Project)
if (-not [System.IO.Directory]::Exists($projectRoot)) { throw 'ALL Packages: Project directory does not exist' }
$manifest=Join-Path $projectRoot 'all.packages.json'
$packageRoot=Join-Path $projectRoot 'packages'
function Get-AllManifest {
    if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) { throw 'ALL Packages: Run init first' }
    $obj=Get-Content -LiteralPath $manifest -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($obj.format -cne 'ALL_PKGS_1' -or $null -eq $obj.packages) { throw 'ALL Packages: Invalid manifest' }
    return $obj
}
function Save-AllManifest($value) {
    $json=ConvertTo-Json -InputObject $value -Depth 15
    $temp=$manifest+'.tmp.'+[guid]::NewGuid().ToString('N')
    try {
        [System.IO.File]::WriteAllText($temp,$json,[System.Text.UTF8Encoding]::new($false))
        if ([System.IO.File]::Exists($manifest)) {
            $replaceBackup=$manifest+'.bak.'+[guid]::NewGuid().ToString('N')
            [System.IO.File]::Replace($temp,$manifest,$replaceBackup)
            if ([System.IO.File]::Exists($replaceBackup)) {
                try { [System.IO.File]::Delete($replaceBackup) } catch { }
            }
        }
        else { [System.IO.File]::Move($temp,$manifest) }
    } finally { if ([System.IO.File]::Exists($temp)) { [System.IO.File]::Delete($temp) } }
}
function Get-PackageFiles([string]$folder) {
    $root=([System.IO.Path]::GetFullPath($folder)).TrimEnd([char[]]@('\','/'))+[System.IO.Path]::DirectorySeparatorChar
    $entriesOnDisk=@(Get-ChildItem -LiteralPath $folder -Recurse -Force)
    foreach ($entry in $entriesOnDisk) {
        if (($entry.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'ALL Packages: Symlinks and reparse points are forbidden'
        }
    }
    $files=@($entriesOnDisk | Where-Object { -not $_.PSIsContainer })
    if ($files.Count -lt 1 -or $files.Count -gt 128) { throw 'ALL Packages: 1 to 128 files required' }
    $entries=[ordered]@{}
    foreach ($file in $files) {
        if (($file.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0 -or $file.Extension -cne '.all') {
            throw 'ALL Packages: Only regular .all files are permitted'
        }
        if ($file.Length -gt 1048576) { throw 'ALL Packages: File exceeds 1 MiB' }
        if (-not $file.FullName.StartsWith($root,[System.StringComparison]::OrdinalIgnoreCase)) {
            throw 'ALL Packages: Invalid package entry'
        }
        $relative=$file.FullName.Substring($root.Length).Replace('\','/')
        $entries[$relative]=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    return $entries
}
switch ($Action) {
    'init' {
        if (Test-Path -LiteralPath $manifest) { throw 'ALL Packages: Manifest already exists' }
        [void](New-Item -ItemType Directory -Path $packageRoot -Force)
        Save-AllManifest ([ordered]@{format='ALL_PKGS_1';packages=@()})
        Write-Output "Initialized: $manifest"
    }
    'add' {
        $state=Get-AllManifest
        if ($Name -cnotmatch '^[A-Za-z][A-Za-z0-9_-]{0,39}$') { throw 'ALL Packages: Invalid package name' }
        if ($Version -cnotmatch '^\d+\.\d+\.\d+$') { throw 'ALL Packages: Version must be X.Y.Z' }
        if ([string]::IsNullOrWhiteSpace($Source) -or -not (Test-Path -LiteralPath $Source -PathType Container)) {
            throw 'ALL Packages: Source directory is required'
        }
        if (@($state.packages | Where-Object { $_.name -ceq $Name }).Count -gt 0) {
            throw 'ALL Packages: Package already installed'
        }
        $target=Join-Path $packageRoot $Name
        if (Test-Path -LiteralPath $target) { throw 'ALL Packages: Target already exists' }
        [void](Get-PackageFiles ([System.IO.Path]::GetFullPath($Source)))
        [void](New-Item -ItemType Directory -Path $packageRoot -Force)
        try {
            Copy-Item -LiteralPath $Source -Destination $target -Recurse -Force
            $checks=Get-PackageFiles $target
            $state.packages=@($state.packages)+@([pscustomobject]@{name=$Name;version=$Version;files=$checks})
            Save-AllManifest $state
        } catch {
            if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
            throw
        }
        Write-Output "Installed: $Name $Version"
        Write-Output "Import example: import `"packages/$Name/main.all`""
    }
    'list' {
        $state=Get-AllManifest
        foreach ($item in @($state.packages)) { Write-Output "$($item.name) $($item.version)" }
    }
    'verify' {
        $state=Get-AllManifest
        foreach ($item in @($state.packages)) {
            if ($item.name -cnotmatch '^[A-Za-z][A-Za-z0-9_-]{0,39}$') {
                throw 'ALL Packages: Invalid package name in manifest'
            }
            $folder=Join-Path $packageRoot $item.name
            if (-not (Test-Path -LiteralPath $folder -PathType Container)) { throw "ALL Packages: Missing package $($item.name)" }
            $actual=Get-PackageFiles $folder
            $expected=$item.files
            if ($actual.Count -ne @($expected.PSObject.Properties).Count) { throw "ALL Packages: File count mismatch for $($item.name)" }
            foreach ($file in $actual.Keys) {
                $hash=$expected.PSObject.Properties[$file]
                if ($null -eq $hash -or $actual[$file] -cne $hash.Value) { throw "ALL Packages: Hash mismatch for $($item.name)/$file" }
            }
            Write-Output "VERIFIED: $($item.name) $($item.version)"
        }
    }
}
