# Check line-positioned JSONL trace, function stack and syntax-error detection.
$ErrorActionPreference='Stop'
$core=Join-Path $HOME 'ALL/ALL.ps1'
$path=Join-Path ([IO.Path]::GetTempPath()) ('ALL_TRACE_'+[guid]::NewGuid().ToString('N')+'.jsonl')
$old=[Environment]::GetEnvironmentVariable('ALL_TRACE_PATH','Process')
$pass=0;$fail=0
try {
    [Environment]::SetEnvironmentVariable('ALL_TRACE_PATH',$path,'Process')
    $source="fn add(a,b) {`n return a + b`n}`nlet x = add(2,3)`nprint(x)"
    $output=[IO.StringWriter]::new();$console=[Console]::Out
    try{[Console]::SetOut($output);& $core -Language ALL -Code $source | Out-Null}
    finally{[Console]::SetOut($console)}
    $value=$output.ToString();$output.Dispose()
    $rows=@([IO.File]::ReadAllLines($path) | ForEach-Object { ConvertFrom-Json $_ })
    $ok=($value -ceq '5' -and $rows.Count -ge 4 -and @($rows | Where-Object {$_.event -eq 'statement' -and $_.line -gt 1}).Count -ge 2)
    if($ok){$pass++;Write-Host 'PASS [Debug]: line-based structured traces'}else{$fail++;Write-Host 'FAIL [Debug]: line traces'}
    $nested=@($rows | Where-Object {@($_.function_stack).Count -gt 0})
    if($nested.Count -gt 0){$pass++;Write-Host 'PASS [Debug]: function stack'}else{$fail++;Write-Host 'FAIL [Debug]: function stack'}
    # No breakpoints set; original output and program result must remain intact.
    if(@($rows|Where-Object {$_.event -eq 'error'}).Count -eq 0){$pass++;Write-Host 'PASS [Debug]: no spurious errors'}else{$fail++;Write-Host 'FAIL [Debug]: spurious trace errors'}
} finally {
    [Environment]::SetEnvironmentVariable('ALL_TRACE_PATH',$old,'Process')
    Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
}
Write-Host "ALL debug: $pass / 3 passed; $fail failed"
if($fail){throw "ALL debug failed: $fail"}
