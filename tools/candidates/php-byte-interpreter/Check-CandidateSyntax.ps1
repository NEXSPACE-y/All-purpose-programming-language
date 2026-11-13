[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$CandidatePath,
    [Parameter(Mandatory=$true)][string]$OutputPath
)
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -ne 'Desktop'){throw 'Use the real Windows PowerShell 5.1 target'}
$source=(Resolve-Path -LiteralPath $CandidatePath).ProviderPath
$destination=[IO.Path]::GetFullPath($OutputPath)
if(Test-Path -LiteralPath $destination){throw 'Preserve the previous syntax record; choose a fresh output file'}
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($source,[ref]$tokens,[ref]$errors)
$record=[ordered]@{
    status=if($errors.Count -eq 0){'PARSE_ONLY_PASS_NOT_EXECUTION'}else{'PARSE_FAILED'}
    candidate=$source
    sourceSha256=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
    powerShell=$PSVersionTable.PSVersion.ToString()
    errorCount=$errors.Count
    errors=@($errors|ForEach-Object{[ordered]@{message=$_.Message;line=$_.Extent.StartLineNumber;column=$_.Extent.StartColumnNumber}})
    phpProgramsExecuted=0
}
[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination))
[IO.File]::WriteAllText($destination,($record|ConvertTo-Json -Depth 6)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
if($errors.Count -gt 0){throw ('Candidate syntax errors: '+$errors.Count)}
Write-Output 'Parse OK; execution unverified'
