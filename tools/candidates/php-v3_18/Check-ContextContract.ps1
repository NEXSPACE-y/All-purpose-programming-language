[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$AdapterPath,[Parameter(Mandatory=$true)][string]$ReportPath)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Utility\Microsoft.PowerShell.Utility.psd1') -ErrorAction Stop
$adapter=& $AdapterPath
$run=$adapter.Run
$context=[System.Collections.Generic.Dictionary[string,object]]::new()
$context['SourcePath']='dictionary-context.php'
$cases=@(
    @{Id='dictionary.exit';Code='<?php exit(7);';Out='';Exit=[long]7;Terminated=$true},
    @{Id='dictionary.compile';Code='<?php exit ''another'';';Out='';Exit=[long]255;Terminated=$true},
    @{Id='dictionary.reuse';Code='<?php echo ''reused'';';Out='reused';Exit=[long]0;Terminated=$false}
)
$rows=[System.Collections.Generic.List[object]]::new()
$before=(Get-FileHash -LiteralPath $AdapterPath -Algorithm SHA256).Hash
foreach($case in $cases){
    $writer=[IO.StringWriter]::new();$errorWriter=[IO.StringWriter]::new()
    $saved=[Console]::Out;$savedError=[Console]::Error;$failure=$null;$pipeline=@()
    try{[Console]::SetOut($writer);[Console]::SetError($errorWriter);$pipeline=@(& $run -Code $case.Code -CliContext $context)}
    catch{$failure=$_.Exception.Message}
    finally{[Console]::SetOut($saved);[Console]::SetError($savedError)}
    $stdout=$writer.ToString();$stderr=$errorWriter.ToString();$writer.Dispose();$errorWriter.Dispose()
    $compilePresent=$context.Keys -contains 'CompileError'
    $pass=$null -eq $failure -and $stdout -ceq $case.Out -and $pipeline.Count -eq 0 -and $context['ExitCode'] -eq $case.Exit -and $context['Terminated'] -eq $case.Terminated
    if($case.Id -ceq 'dictionary.compile'){$pass=$pass -and $compilePresent -and $stderr.Contains('dictionary-context.php')}
    else{$pass=$pass -and -not $compilePresent -and $stderr.Length -eq 0}
    $rows.Add([ordered]@{id=$case.Id;code=$case.Code;passed=$pass;stdout=$stdout;stderr=$stderr;error=$failure;pipeline_count=$pipeline.Count;exit_code=$context['ExitCode'];terminated=$context['Terminated'];compile_error_present=$compilePresent})
}
$passed=@($rows|Where-Object{$_.passed}).Count
$report=[ordered]@{scope='Host IDictionary context/reset contract only; not PHP conformance';total=$rows.Count;passed=$passed;results=$rows.ToArray();adapter_sha256_before=$before;adapter_sha256_after=(Get-FileHash -LiteralPath $AdapterPath -Algorithm SHA256).Hash}
[IO.File]::WriteAllText($ReportPath,($report|ConvertTo-Json -Depth 7),(New-Object System.Text.UTF8Encoding($false)))
Write-Output ([pscustomobject]@{total=$rows.Count;passed=$passed}|ConvertTo-Json -Compress)
if($passed -ne $rows.Count){exit 1}
