[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Import-Module -Name (Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Utility\Microsoft.PowerShell.Utility.psd1') -ErrorAction Stop
$evidenceRoot = $PSScriptRoot
$repoRoot = [IO.Path]::GetFullPath((Join-Path $evidenceRoot '..\..'))
$packageRoot = Join-Path $repoRoot 'package'
$utf8 = New-Object System.Text.UTF8Encoding($false)
function Save-Json([string]$name, $value) {
    [IO.File]::WriteAllText((Join-Path $evidenceRoot $name), ($value | ConvertTo-Json -Depth 8), $utf8)
}
function Get-PackageSnapshot {
    @(Get-ChildItem -LiteralPath $packageRoot -File -Recurse | Sort-Object FullName | ForEach-Object {
        [pscustomobject]@{
            path = $_.FullName.Substring($repoRoot.Length + 1).Replace('\','/')
            length = $_.Length
            sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    })
}
$before = Get-PackageSnapshot
Save-Json 'package-hashes-before.json' $before
Save-Json 'powershell-version.json' $PSVersionTable
$started = [DateTime]::UtcNow
$clock = [Diagnostics.Stopwatch]::StartNew()
$exitCode = 0
$failure = $null
try {
    & (Join-Path $packageRoot 'ALL_PHP_v3_19_validate.ps1') -CompileCSharp
} catch {
    $exitCode = 1
    $failure = $_ | Out-String
    [Console]::Error.WriteLine($failure)
} finally {
    $clock.Stop()
    $after = Get-PackageSnapshot
    Save-Json 'package-hashes-after.json' $after
    $assemblies = @([AppDomain]::CurrentDomain.GetAssemblies() | ForEach-Object {
        $location = $null
        try { $location = $_.Location } catch {}
        if ($_.GetType('AllSqliteDriver', $false) -or $_.GetType('AllConcurrentGateway', $false)) {
            [pscustomobject]@{ fullName=$_.FullName; location=$location; fileExists=([bool]($location -and (Test-Path -LiteralPath $location -PathType Leaf))) }
        }
    })
    Save-Json 'validation-process.json' ([ordered]@{
        pid = $PID
        startedUtc = $started.ToString('o')
        finishedUtc = [DateTime]::UtcNow.ToString('o')
        durationSeconds = [Math]::Round($clock.Elapsed.TotalSeconds, 3)
        validator = 'package/ALL_PHP_v3_19_validate.ps1'
        arguments = @('-CompileCSharp')
        installedMode = $false
        exitCode = $exitCode
        failure = $failure
        packageUnchanged = (($before | ConvertTo-Json -Depth 5 -Compress) -ceq ($after | ConvertTo-Json -Depth 5 -Compress))
        helperAssemblies = $assemblies
    })
}
exit $exitCode
