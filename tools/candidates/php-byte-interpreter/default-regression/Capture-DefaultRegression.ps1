[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$BundlePath,[Parameter(Mandatory=$true)][string]$EvidencePath)
$ErrorActionPreference='Stop'
Import-Module -Name (Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Utility\Microsoft.PowerShell.Utility.psd1') -ErrorAction Stop
$utf8=New-Object Text.UTF8Encoding($false)
[Console]::OutputEncoding=$utf8
[Console]::InputEncoding=$utf8
if($PSVersionTable.PSVersion.Major-ne5 -or $PSVersionTable.PSVersion.Minor-ne1 -or [IntPtr]::Size-ne8){throw 'Default regression requires Windows PowerShell5.1 x64'}
$bundleRoot=[IO.Path]::GetFullPath($BundlePath)
$evidenceRoot=[IO.Path]::GetFullPath($EvidencePath)
if($evidenceRoot.StartsWith($bundleRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)-or$evidenceRoot-eq$bundleRoot){throw 'Evidence must stay outside the manifest-covered bundle'}
function Save-Json([string]$name,$value){[IO.File]::WriteAllText((Join-Path $evidenceRoot $name),($value|ConvertTo-Json -Depth 8),$utf8)}
function Get-BundleSnapshot {
    @(Get-ChildItem -LiteralPath $bundleRoot -File -Recurse|Sort-Object FullName|ForEach-Object{
        [pscustomobject]@{path=$_.FullName.Substring($bundleRoot.Length+1).Replace('\','/');bytes=$_.Length;sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}
    })
}
$before=Get-BundleSnapshot
Save-Json 'bundle-worker-before.json' $before
Save-Json 'powershell-version.json' $PSVersionTable
$started=[DateTime]::UtcNow
$clock=[Diagnostics.Stopwatch]::StartNew()
$exitCode=0;$failure=$null
try {
    & (Join-Path $bundleRoot 'ALL_PHP_v3_20_validate.ps1') -CompileCSharp
} catch {
    $exitCode=1;$failure=$_|Out-String
    [Console]::Error.WriteLine($failure)
} finally {
    $clock.Stop();$after=Get-BundleSnapshot
    Save-Json 'bundle-worker-after.json' $after
    $assemblies=@([AppDomain]::CurrentDomain.GetAssemblies()|ForEach-Object{
        $location=$null;try{$location=$_.Location}catch{}
        $types=@();foreach($name in @('AllSqliteDriver','AllConcurrentGateway')){if($_.GetType($name,$false)){$types+=,$name}}
        if($types.Count){[pscustomobject]@{fullName=$_.FullName;location=$location;types=$types}}
    })
    Save-Json 'validation-process.json' ([ordered]@{pid=$PID;startedUtc=$started.ToString('o');finishedUtc=[DateTime]::UtcNow.ToString('o');durationSeconds=[Math]::Round($clock.Elapsed.TotalSeconds,3);validator=Join-Path $bundleRoot 'ALL_PHP_v3_20_validate.ps1';arguments=@('-CompileCSharp');installedMode=$false;exitCode=$exitCode;failure=$failure;bundleUnchanged=(($before|ConvertTo-Json -Depth 5 -Compress)-ceq($after|ConvertTo-Json -Depth 5 -Compress));helperAssemblies=$assemblies})
}
exit $exitCode
