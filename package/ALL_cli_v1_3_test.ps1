# Independent native-process checks: source pipeline, stderr and exit status.
$ErrorActionPreference='Stop'
$nativeHost = Join-Path $HOME 'ALL\ALL_cli_host.ps1'
if (-not (Test-Path -LiteralPath $nativeHost -PathType Leaf)) { throw 'ALL CLI host missing' }
$psExe=(Get-Command powershell.exe -ErrorAction Stop).Source
$pass=0; $fail=0
$runRoot=Join-Path ([System.IO.Path]::GetTempPath()) ('all_cli_v13_'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $runRoot | Out-Null
function Record([string]$name,[bool]$ok,[string]$detail='') {
    if ($ok) { $script:pass++; Write-Host "PASS [CLI v1.3]: $name" -ForegroundColor Green }
    else { $script:fail++; Write-Host "FAIL [CLI v1.3]: $name" -ForegroundColor Red; Write-Host "  $detail" }
}
function RunCase([string]$body,[string]$stdin='') {
    $file=Join-Path $runRoot 'case.all'
    [IO.File]::WriteAllText($file,$body,[Text.UTF8Encoding]::new($false))
    $psi=[Diagnostics.ProcessStartInfo]::new()
    $psi.FileName=$psExe
    $psi.Arguments='-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$nativeHost+'" run "'+$file+'"'
    $psi.UseShellExecute=$false
    $psi.RedirectStandardInput=$true
    $psi.RedirectStandardOutput=$true
    $psi.RedirectStandardError=$true
    $psi.CreateNoWindow=$true
    $p=[Diagnostics.Process]::Start($psi)
    try {
        $p.StandardInput.Write($stdin)
        $p.StandardInput.Close()
        $out=$p.StandardOutput.ReadToEnd()
        $err=$p.StandardError.ReadToEnd()
        if (-not $p.WaitForExit(20000)) { throw 'CLI timed out (20s)' }
        return [pscustomobject]@{Code=$p.ExitCode;Output=$out;Error=$err}
    } finally {
        if (-not $p.HasExited) { $p.Kill() }
        $p.Dispose()
    }
}
try {
    $r=RunCase 'print(stdin_text())' 'abc123'
    Record 'stdin to ALL stdout' ($r.Code -eq 0 -and $r.Output -ceq 'abc123' -and $r.Error -eq '') ("exit=$($r.Code), out=$($r.Output), err=$($r.Error)")
    $r=RunCase '表示(標準入力())' 'ABC!'
    Record 'Japanese stdin alias' ($r.Code -eq 0 -and $r.Output -ceq 'ABC!') ("exit=$($r.Code), out=$($r.Output), err=$($r.Error)")
    $r=RunCase 'stderr_text("ERR_MARK");print("OK")'
    Record 'stderr separated from stdout' ($r.Code -eq 0 -and $r.Output -ceq 'OK' -and $r.Error.Contains('ERR_MARK')) ("exit=$($r.Code), out=$($r.Output), err=$($r.Error)")
    $r=RunCase '標準エラー出力("JP_ERR");表示("OK")'
    Record 'Japanese stderr alias' ($r.Code -eq 0 -and $r.Output -ceq 'OK' -and $r.Error.Contains('JP_ERR')) ("exit=$($r.Code), out=$($r.Output), err=$($r.Error)")
    $r=RunCase 'set_exit_code(23); print("SUCCESS")'
    Record 'explicit CLI exit code 23' ($r.Code -eq 23 -and $r.Output -ceq 'SUCCESS') ("exit=$($r.Code), out=$($r.Output), err=$($r.Error)")
    $r=RunCase '終了コード設定(7); print("JP")'
    Record 'Japanese exit-code alias' ($r.Code -eq 7 -and $r.Output -ceq 'JP') ("exit=$($r.Code), out=$($r.Output), err=$($r.Error)")
    $r=RunCase 'set_exit_code(256)'
    Record 'reject exit code outside 0..255' ($r.Code -eq 1 -and $r.Error -ne '') ("exit=$($r.Code), err=$($r.Error)")
    $r=RunCase 'print(does_not_exist)'
    Record 'runtime failure produces nonzero exit' ($r.Code -eq 1 -and $r.Error -ne '') ("exit=$($r.Code), err=$($r.Error)")
} finally {
    Remove-Item -LiteralPath $runRoot -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host "ALL CLI v1.3: $pass / 8 passed; $fail failed"
if ($fail -ne 0) { throw "ALL CLI v1.3 failed: $fail" }
