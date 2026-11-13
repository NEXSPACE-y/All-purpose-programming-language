[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Core,[Parameter(Mandatory=$true)][string]$Extension,[Parameter(Mandatory=$true)][string]$Output)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Utility\Microsoft.PowerShell.Utility.psd1') -ErrorAction Stop
Add-Type -Path (Join-Path $PSScriptRoot 'AllNativeCallbackBridge.cs')
$bridge=New-Object AllPhp85AbiCallback.Bridge([IO.Path]::GetFullPath($Core))
$record=[ordered]@{extension=[IO.Path]::GetFullPath($Extension);status='NOT_ATTEMPTED';error=$null;core_path=$bridge.CorePath}
try {$bridge.LoadExtension($record.extension);$record.status='LOADED'}catch{$record.status='LOAD_REJECTED';$record.error=$_.Exception.Message}
$record.loaded_php_modules=$bridge.LoadedPhpModules
$bridge.Shutdown()
$utf8=New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText([IO.Path]::GetFullPath($Output),($record|ConvertTo-Json -Depth 5)+[Environment]::NewLine,$utf8)
Write-Output $record.status
