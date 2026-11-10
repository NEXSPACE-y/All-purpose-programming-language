# Additive original-file diagnostics regression; original 523 tests are retained.
$ErrorActionPreference='Stop'
$core=Join-Path $HOME 'ALL/ALL.ps1'
$runner=Join-Path $HOME 'ALL/run.ps1'
$tmp=Join-Path ([IO.Path]::GetTempPath()) ('ALL_DEBUG_SOURCE_'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($tmp) | Out-Null
$pass=0;$fail=0
function Check([string]$label,[bool]$condition) {
    if($condition){$script:pass++;Write-Host "PASS [Debug source]: $label" -ForegroundColor Green}
    else{$script:fail++;Write-Host "FAIL [Debug source]: $label" -ForegroundColor Red}
}
function Run-WithTrace([scriptblock]$action,[string]$trace) {
    $oldTrace=[Environment]::GetEnvironmentVariable('ALL_TRACE_PATH','Process')
    $previousOut=[Console]::Out
    $writer=[IO.StringWriter]::new([Globalization.CultureInfo]::InvariantCulture)
    try {
        [Environment]::SetEnvironmentVariable('ALL_TRACE_PATH',$trace,'Process')
        [Console]::SetOut($writer)
        & $action | Out-Null
        $rows=@([IO.File]::ReadAllLines($trace) | ForEach-Object { ConvertFrom-Json -InputObject $_ })
        return [pscustomobject]@{Output=$writer.ToString();Rows=@($rows)}
    } finally {
        [Console]::SetOut($previousOut)
        [Environment]::SetEnvironmentVariable('ALL_TRACE_PATH',$oldTrace,'Process')
        $writer.Dispose()
    }
}
try {
    $moduleDir=Join-Path $tmp 'lib'
    [IO.Directory]::CreateDirectory($moduleDir) | Out-Null
    $modulePath=Join-Path $moduleDir 'calc.all'
    $mainPath=Join-Path $tmp 'main.all'
    [IO.File]::WriteAllText($modulePath,"fn add(a,b) {`n let answer = a + b`n return answer`n}",[Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($mainPath,"import `"lib/calc.all`"`nlet total = add(2,3)`nprint(total)",[Text.UTF8Encoding]::new($false))
    $importResult=Run-WithTrace { & $runner -File $mainPath -Language ALL } (Join-Path $tmp 'import.jsonl')
    Check 'imported source maps to its real file and line 2' (
        @($importResult.Rows|Where-Object{$_.event -eq 'statement' -and $_.source_file -ceq $modulePath -and $_.source_line -eq 2}).Count -gt 0)
    Check 'caller after import retains original line 2 and preprocessed line' (
        $importResult.Output -ceq '5' -and @($importResult.Rows|Where-Object{
            $_.event -eq 'statement' -and $_.source_file -ceq $mainPath -and $_.source_line -eq 2 -and $_.line -gt 2
        }).Count -gt 0)

    $jpPath=Join-Path $tmp 'japanese.all'
    [IO.File]::WriteAllText($jpPath,"値という変数を 3 とする`n値に 2 を足す`n値を表示する",[Text.UTF8Encoding]::new($false))
    $jpResult=Run-WithTrace { & $runner -File $jpPath -Language ALL } (Join-Path $tmp 'jp.jsonl')
    Check 'Japanese normalization preserves original file/line' (
        $jpResult.Output -ceq '5' -and @($jpResult.Rows|Where-Object{
            $_.event -eq 'statement' -and $_.source_file -ceq $jpPath -and $_.source_line -eq 2
        }).Count -gt 0)

    $inlineResult=Run-WithTrace { & $core -Language ALL -Code "let a = 1`nprint(a)" } (Join-Path $tmp 'inline.jsonl')
    Check 'inline code has an explicit origin marker and retains trace lines' (
        $inlineResult.Output -ceq '1' -and @($inlineResult.Rows|Where-Object{
            $_.event -eq 'statement' -and $_.source_file -ceq '<inline>' -and $_.source_line -eq 2 -and $_.line -eq 2
        }).Count -gt 0)
} finally {
    [IO.Directory]::Delete($tmp,$true)
}
Write-Host "ALL debug source mapping: $pass / 4 passed; $fail failed"
if($fail){throw "ALL debug source mapping regressions: $fail failure(s)"}
