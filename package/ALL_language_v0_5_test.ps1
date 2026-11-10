$ErrorActionPreference = 'Stop'
$core = Join-Path $HOME 'ALL\ALL.ps1'
$runner = Join-Path $HOME 'ALL\run.ps1'
$path = Join-Path $PSScriptRoot 'ALL_language_v0_5_cases.json'
$tests = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $path -Raw -Encoding UTF8)
if (($tests -is [array]) -and $tests.Count -eq 1 -and ($tests[0] -is [array])) { $tests=$tests[0] }
if ($tests.Count -ne 43) { throw "Expected 43 cases, got $($tests.Count)" }
function Invoke-ALLTest([string]$source) {
    $writer = [System.IO.StringWriter]::new([System.Globalization.CultureInfo]::InvariantCulture)
    $original = [Console]::Out
    $err = $null
    $pipeline = @()
    try {
        [Console]::SetOut($writer)
        $pipeline = @(& $core -Language ALL -Code $source)
    } catch { $err = $_.Exception.Message }
    finally { [Console]::SetOut($original) }
    $res = [pscustomobject]@{ Output=$writer.ToString(); Error=$err; Pipeline=@($pipeline) }
    $writer.Dispose()
    return $res
}
function Invoke-RunnerTest([string]$file) {
    $writer = [System.IO.StringWriter]::new([System.Globalization.CultureInfo]::InvariantCulture)
    $original = [Console]::Out
    $err = $null
    $pipeline = @()
    try {
        [Console]::SetOut($writer)
        $pipeline = @(& $runner -File $file)
    } catch { $err = $_.Exception.Message }
    finally { [Console]::SetOut($original) }
    $res = [pscustomobject]@{ Output=$writer.ToString(); Error=$err; Pipeline=@($pipeline) }
    $writer.Dispose()
    return $res
}
$pass = 0
$fail = 0
function Report([string]$name,[bool]$ok,[string]$expected,$res) {
    if($ok){Write-Host "PASS [ALL v0.5]: $name" -ForegroundColor Green;return $true}
    Write-Host "FAIL [ALL v0.5]: $name" -ForegroundColor Red
    Write-Host "  Expected: $expected"
    Write-Host "  Output: $($res.Output | ConvertTo-Json -Compress)"
    Write-Host "  Error: $($res.Error)"
    if ($res.Pipeline.Count -gt 0) { Write-Host "  Unexpected pipeline: $($res.Pipeline -join '|')" }
    return $false
}
foreach($test in $tests) {
    $res=Invoke-ALLTest ([string]$test.all)
    if($test.mode -eq 'error') {
        $ok = ($null -ne $res.Error -and $res.Error.Contains([string]$test.message_contains) -and
               $res.Output.Length -eq 0 -and $res.Pipeline.Count -eq 0)
    } else {
        $ok = ($null -eq $res.Error -and $res.Pipeline.Count -eq 0 -and
               $res.Output -ceq [string]$test.expected)
    }
    if (Report $test.name $ok $(if($test.mode -eq 'error'){$test.message_contains}else{$test.expected}) $res) { $pass++ } else {$fail++}
}
foreach ($sample in @(
    @{Name='Runner hello';File=(Join-Path $PSScriptRoot 'examples\hello.all');Expected="Hello World!!`nHello from ALL v0.5`n"},
    @{Name='Runner data';File=(Join-Path $PSScriptRoot 'examples\data.all');Expected="太郎`n24`n10`n"}
)) {
    $res=Invoke-RunnerTest $sample.File
    $ok=($null -eq $res.Error -and $res.Pipeline.Count -eq 0 -and $res.Output -ceq $sample.Expected)
    if (Report $sample.Name $ok $sample.Expected $res) {$pass++}else{$fail++}
}
# Temporary UTF-8 files; deleted in finally even on failure.
$temp = Join-Path ([System.IO.Path]::GetTempPath()) ("allv05_" + [guid]::NewGuid().ToString('N'))
[void][System.IO.Directory]::CreateDirectory($temp)
try {
    $textPath = (Join-Path $temp 'example.txt').Replace('\','/')
    $jsonPath = (Join-Path $temp 'example.json').Replace('\','/')
    $pathA = ConvertTo-Json -InputObject $textPath -Compress
    $pathB = ConvertTo-Json -InputObject $jsonPath -Compress
    $pathMissing = ConvertTo-Json -InputObject ($jsonPath + ".missing") -Compress
    $ioTests = @(
        @{Name='UTF-8 text write read append'; Code="write_text($pathA,`"こんにちは`" );append_text($pathA,`" 世界`" );print(read_text($pathA))";Expected='こんにちは 世界'},
        @{Name='File exists'; Code="print(file_exists($pathA))";Expected='true'},
        @{Name='JSON file roundtrip'; Code="write_json($pathB, {`"名前`":`"花子`",`"値`":[1,2]});let d=read_json($pathB);print(d[`"名前`"]);print(d[`"値`"][1])";Expected='花子2'},
        @{Name='Missing file exists false'; Code="print(file_exists($pathMissing))";Expected='false'}
    )
    foreach($test in $ioTests) {
        $res=Invoke-ALLTest $test.Code
        $ok=($null -eq $res.Error -and $res.Pipeline.Count -eq 0 -and $res.Output -ceq $test.Expected)
        if(Report $test.Name $ok $test.Expected $res) {$pass++}else{$fail++}
    }
} finally {
    if ([System.IO.Directory]::Exists($temp)) { [System.IO.Directory]::Delete($temp,$true) }
}
Write-Host "ALL v0.5: $pass / 49 passed; $fail failed"
if ($fail -ne 0) { throw "ALL v0.5 regressions: $fail failure(s)" }
