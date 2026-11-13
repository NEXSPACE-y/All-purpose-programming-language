[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$BundlePath,[Parameter(Mandatory=$true)][string]$VersionPath)
$ErrorActionPreference='Stop'
Import-Module -Name (Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Utility\Microsoft.PowerShell.Utility.psd1') -ErrorAction Stop
$utf8=New-Object Text.UTF8Encoding($false)
[Console]::OutputEncoding=$utf8
[Console]::InputEncoding=$utf8
if($PSVersionTable.PSVersion.Major-ne5 -or $PSVersionTable.PSVersion.Minor-ne1 -or [IntPtr]::Size-ne8){throw 'Preparation requires Windows PowerShell5.1 x64'}
foreach($script in @('Check-PreparedBundle.ps1','Capture-DefaultRegression.ps1')) {
    $tokens=$null;$parseErrors=$null
    [void][Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $script),[ref]$tokens,[ref]$parseErrors)
    if($parseErrors.Count){foreach($problem in $parseErrors){[Console]::Error.WriteLine($script+': '+$problem.Message)};throw 'Capture/preparation worker syntax rejected by PS5.1'}
}
[IO.File]::WriteAllText($VersionPath,([ordered]@{powerShell=$PSVersionTable.PSVersion.ToString();clr=[Environment]::Version.ToString();pointerBytes=[IntPtr]::Size;workerSyntaxErrors=0;compileCSharp=$false;defaultFixturesExecuted=$false}|ConvertTo-Json -Depth 4),$utf8)
# The unchanged preflight parses scripts and verifies the updated bundle manifest.
# No CompileCSharp switch and no default test script are invoked in preparation.
& (Join-Path $BundlePath 'ALL_preflight.ps1')
