[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$AssemblyPath,[Parameter(Mandatory=$true)][AllowEmptyString()][string]$DataBase64)
$ErrorActionPreference='Stop'
Add-Type -Path $AssemblyPath
$value=[AllPhp.ByteValues.PhpBytes]::FromBase64($DataBase64)
$bytes=$value.ToArray();$stream=[Console]::OpenStandardOutput()
$stream.Write($bytes,0,$bytes.Length);$stream.Flush()
