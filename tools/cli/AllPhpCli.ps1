# Standalone CLI prototype. The C# host supplies user arguments as a string[].
[CmdletBinding()]
param([string[]]$CliArguments, [Parameter(Mandatory=$true)][string]$AdapterPath)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Utility\Microsoft.PowerShell.Utility.psd1') -ErrorAction Stop
function Invoke-AllPhpCli {
    $mode=$null; $code=$null; $file=$null
    $remaining=[Collections.Generic.List[string]]::new()
    $ini=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
    for($i=0;$i-lt$CliArguments.Length;$i++) {
        $argument=$CliArguments[$i]
        if($argument-ceq'--') {
            for($j=$i+1;$j-lt$CliArguments.Length;$j++){[void]$remaining.Add($CliArguments[$j])}
            break
        }
        if($argument-ceq'-n'){continue}
        if($argument-ceq'-r'-or$argument-ceq'-f') {
            if($null-ne$mode){throw 'ALL PHP CLI unsupported: multiple source modes'}
            if($i+1-ge$CliArguments.Length){throw ('ALL PHP CLI: missing argument for '+$argument)}
            $i++
            if($argument-ceq'-r'){$mode='body';$code=$CliArguments[$i]}
            else{$mode='file';$file=$CliArguments[$i]}
            continue
        }
        if($argument-ceq'-d'-or($argument.StartsWith('-d')-and$argument.Length-gt2)) {
            if($argument.Length-gt2){$setting=$argument.Substring(2)}
            else{if($i+1-ge$CliArguments.Length){throw 'ALL PHP CLI: missing argument for -d'};$i++;$setting=$CliArguments[$i]}
            $cut=$setting.IndexOf('=')
            if($cut-lt0){$name=$setting;$value='1'}else{$name=$setting.Substring(0,$cut);$value=$setting.Substring($cut+1)}
            # This host currently supports the exact diagnostic profile used by
            # strict comparisons. Other settings are rejected rather than ignored.
            if($name-ceq'display_errors'-and$value-ceq'stderr'){$ini[$name]=$value;continue}
            if($name-ceq'error_reporting'-and$value-ceq'-1'){$ini[$name]=$value;continue}
            if($name-ceq'date.timezone'-and$value-ceq'UTC'){$ini[$name]=$value;continue}
            throw ('ALL PHP CLI unsupported INI setting: '+$setting)
        }
        if($argument.StartsWith('-')){throw ('ALL PHP CLI unsupported option: '+$argument)}
        if($null-eq$mode){$mode='file';$file=$argument}
        else{[void]$remaining.Add($argument)}
        # After the first positional script or argument, PHP treats the rest as
        # script arguments, including strings that start with a hyphen.
        for($j=$i+1;$j-lt$CliArguments.Length;$j++){[void]$remaining.Add($CliArguments[$j])}
        break
    }
    if($null-eq$mode){
        if($remaining.Count-gt0){$mode='file';$file=$remaining[0];$remaining.RemoveAt(0)}
        else{$mode='stdin'}
    }
    $sourceName='Command line code';$argv0='Standard input code'
    if($mode-ceq'file') {
        if(-not[IO.File]::Exists($file)){[Console]::WriteLine('Could not open input file: '+$file);return [long]1}
        $sourceName=[IO.Path]::GetFullPath($file);$argv0=$file
        $code=[IO.File]::ReadAllText($sourceName,[Text.UTF8Encoding]::new($false,$true))
    } elseif($mode-ceq'stdin') {
        $sourceName='Standard input code'
        $code=[Console]::In.ReadToEnd()
    }
    $scriptArguments=[Collections.Generic.List[string]]::new();[void]$scriptArguments.Add($argv0)
    foreach($item in $remaining){[void]$scriptArguments.Add($item)}
    $adapter=& $AdapterPath
    if($null-eq$adapter-or$adapter.Run-isnot[scriptblock]){throw 'ALL PHP CLI: adapter has no Run scriptblock'}
    $parameters=@($adapter.Run.Ast.ParamBlock.Parameters|ForEach-Object{$_.Name.VariablePath.UserPath})
    if($parameters-notcontains'CliContext'){throw 'ALL PHP CLI: adapter has no declared CliContext'}
    $context=@{SourcePath=$sourceName;ExitCode=[long]0;Terminated=$false;SourceMode=$mode;ScriptArguments=$scriptArguments.ToArray();InitialIni=$ini}
    # File/stdin modes use ordinary PHP source. -r begins in PHP code mode and
    # passes the exact body, without manufacturing a tagged source string.
    $pipeline=@(& ($adapter.Run) -Code $code -CliContext $context)
    if($pipeline.Count-ne0){throw 'ALL PHP CLI: interpreter leaked pipeline objects'}
    return [long]$context.ExitCode
}
try{$status=Invoke-AllPhpCli;[pscustomobject]@{ExitCode=[long]$status}}
catch{[Console]::Error.WriteLine($_.Exception.Message);[pscustomobject]@{ExitCode=[long]1}}
