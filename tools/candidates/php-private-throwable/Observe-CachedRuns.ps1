# Same-process observation only. No script cache is reset, inspected or injected.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$BaseAdapterPath,
    [Parameter(Mandatory=$true)][string]$AdapterPath,
    [Parameter(Mandatory=$true)][string]$SequencePath,
    [Parameter(Mandatory=$true)][string]$ReportPath
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Utility\Microsoft.PowerShell.Utility.psd1') -ErrorAction Stop
$baseAdapter=& $BaseAdapterPath
$privateAdapter=& $AdapterPath
$sequence=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($SequencePath))
$rows=[System.Collections.Generic.List[object]]::new()
$before=(Get-FileHash -LiteralPath $AdapterPath -Algorithm SHA256).Hash
foreach($step in $sequence){
    $run=if($step.adapter -ceq 'base'){$baseAdapter.Run}else{$privateAdapter.Run}
    $code=[IO.File]::ReadAllText($step.source_path,(New-Object System.Text.UTF8Encoding($false,$true)))
    $context=@{SourcePath=$step.source_path}
    $writer=[IO.StringWriter]::new();$errors=[IO.StringWriter]::new()
    $saved=[Console]::Out;$savedError=[Console]::Error;$failure=$null;$pipeline=@()
    try{
        [Console]::SetOut($writer);[Console]::SetError($errors)
        $pipeline=@(& $run -Code $code -CliContext $context)
    }catch{$failure=$_.Exception.Message}
    finally{[Console]::SetOut($saved);[Console]::SetError($savedError)}
    $rows.Add([ordered]@{id=$step.id;adapter=$step.adapter;source_path=$step.source_path;stdout=$writer.ToString();stderr=$errors.ToString();error=$failure;pipeline_count=$pipeline.Count;context_exit_code=$context['ExitCode'];context_terminated=$context['Terminated']})
    $writer.Dispose();$errors.Dispose()
}
$report=[ordered]@{process_id=$PID;powershell_version=$PSVersionTable.PSVersion.ToString();cache_reset_performed=$false;adapter_sha256_before=$before;adapter_sha256_after=(Get-FileHash -LiteralPath $AdapterPath -Algorithm SHA256).Hash;results=$rows.ToArray()}
[IO.File]::WriteAllText($ReportPath,($report|ConvertTo-Json -Depth 7),(New-Object System.Text.UTF8Encoding($false)))
