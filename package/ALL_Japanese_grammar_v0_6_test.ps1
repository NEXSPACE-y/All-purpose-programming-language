$ErrorActionPreference='Stop'
$core=Join-Path $HOME 'ALL\ALL.ps1'
$casesPath=Join-Path $PSScriptRoot 'ALL_Japanese_grammar_v0_6_cases.json'
$tests=ConvertFrom-Json -InputObject (Get-Content -LiteralPath $casesPath -Raw -Encoding UTF8)
if (($tests -is [array]) -and $tests.Count -eq 1 -and ($tests[0] -is [array])) { $tests=$tests[0] }
if ($tests.Count -ne 33) { throw "Expected 33 natural-Japanese cases, got $($tests.Count)" }
function Invoke-NaturalTest([string]$source) {
    $writer=[System.IO.StringWriter]::new([System.Globalization.CultureInfo]::InvariantCulture)
    $original=[Console]::Out
    $err=$null; $pipeline=@()
    try {
        [Console]::SetOut($writer)
        $pipeline=@(& $core -Language ALL -Code $source)
    } catch { $err=$_.Exception.Message }
    finally { [Console]::SetOut($original) }
    $result=[pscustomobject]@{ Output=$writer.ToString(); Error=$err; Pipeline=@($pipeline) }
    $writer.Dispose()
    return $result
}
$pass=0; $fail=0
foreach($t in $tests) {
    $res=Invoke-NaturalTest ([string]$t.all)
    if($t.mode -eq 'error') {
        $ok=($null -ne $res.Error -and $res.Error.Contains([string]$t.message_contains) -and $res.Output.Length -eq 0 -and $res.Pipeline.Count -eq 0)
    } else {
        $ok=($null -eq $res.Error -and $res.Pipeline.Count -eq 0 -and $res.Output -ceq [string]$t.expected)
    }
    if ($ok) { Write-Host "PASS [JP natural]: $($t.name)" -ForegroundColor Green; $pass++ }
    else {
        Write-Host "FAIL [JP natural]: $($t.name)" -ForegroundColor Red
        Write-Host "  Expected: $([string]$(if($t.mode -eq 'error'){$t.message_contains}else{$t.expected}))"
        Write-Host "  Output: $($res.Output | ConvertTo-Json -Compress)"
        Write-Host "  Error: $($res.Error)"
        if($res.Pipeline.Count -gt 0){ Write-Host "  Unexpected pipeline: $($res.Pipeline -join '|')" }
        $fail++
    }
}
$runner=Join-Path $HOME 'ALL\run.ps1'
$example=Join-Path $PSScriptRoot 'examples\natural_japanese.all'
$writer=[System.IO.StringWriter]::new([System.Globalization.CultureInfo]::InvariantCulture)
$original=[Console]::Out
$runnerError=$null
$runnerPipeline=@()
try {
    [Console]::SetOut($writer)
    $runnerPipeline=@(& $runner -File $example)
} catch { $runnerError=$_.Exception.Message }
finally { [Console]::SetOut($original) }
$runnerOutput=$writer.ToString()
$writer.Dispose()
if($null -eq $runnerError -and $runnerPipeline.Count -eq 0 -and $runnerOutput -ceq "成人です") {
    Write-Host 'PASS [JP natural]: File runner Japanese program' -ForegroundColor Green
    $pass++
} else {
    Write-Host 'FAIL [JP natural]: File runner Japanese program' -ForegroundColor Red
    Write-Host "  Output: $($runnerOutput | ConvertTo-Json -Compress)"
    Write-Host "  Error: $runnerError"
    $fail++
}
Write-Host "ALL natural Japanese v0.6: $pass / 34 passed; $fail failed"
if($fail -ne 0) { throw "Natural Japanese v0.6 regressions: $fail failure(s)" }
