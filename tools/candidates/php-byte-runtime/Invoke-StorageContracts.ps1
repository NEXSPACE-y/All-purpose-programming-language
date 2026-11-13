[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$RuntimeAssemblyPath,[Parameter(Mandatory=$true)][string]$ProofAssemblyPath,[Parameter(Mandatory=$true)][string]$CasesPath,[Parameter(Mandatory=$true)][string]$ReportPath)
$ErrorActionPreference='Stop'
Add-Type -Path $RuntimeAssemblyPath
Add-Type -Path $ProofAssemblyPath
$cases=[IO.File]::ReadAllText($CasesPath)|ConvertFrom-Json
$result=[AllPhp.ByteValues.Proof.StorageProbe]::Run([string]$cases.pattern_base64,[long]$cases.repetitions,[long]$cases.mutation_offset,[long[]]$cases.sample_positions)
[IO.File]::WriteAllText($ReportPath,($result|ConvertTo-Json -Depth 10)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
$failed=@($result.Checks|Where-Object {-not $_.Passed})
Write-Output ('checks='+$result.Checks.Count+' failed='+$failed.Count+' bytes='+$result.FullStreamBytes+' sha256='+$result.FullStreamSha256)
if($failed.Count){$failed|ForEach-Object{[Console]::Error.WriteLine($_.Id+': '+$_.Error)};exit 1}
exit 0
