# Independent v0.3 feature tests; existing 196 tests are run separately.
$ErrorActionPreference = 'Stop'
$core = Join-Path $HOME 'ALL\ALL.ps1'
$casesPath = Join-Path $PSScriptRoot 'ALL_language_v0_3_cases.json'
if (-not (Test-Path -LiteralPath $core -PathType Leaf)) { throw "Missing ALL core: $core" }
if (-not (Test-Path -LiteralPath $casesPath -PathType Leaf)) { throw "Missing ALL v0.3 fixtures: $casesPath" }

$tests = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $casesPath -Raw -Encoding UTF8)
if (($tests -is [array]) -and $tests.Count -eq 1 -and ($tests[0] -is [array])) { $tests = $tests[0] }
if ($tests.Count -ne 61 -or $tests[0].name -cne 'ALL Hello World') {
    throw "Fixture load error: expected 61 distinct cases, got $($tests.Count)"
}

function Invoke-Program([string]$lang,[string]$source) {
    $writer = [System.IO.StringWriter]::new([System.Globalization.CultureInfo]::InvariantCulture)
    $saved = [Console]::Out
    $failure = $null
    $pipeline = @()
    try {
        [Console]::SetOut($writer)
        $pipeline = @(& $core -Language $lang -Code $source)
    } catch {
        $failure = $_.Exception.Message
    } finally {
        [Console]::SetOut($saved)
    }
    $output = $writer.ToString()
    $writer.Dispose()
    return [pscustomobject]@{ Output=$output; Error=$failure; Pipeline=@($pipeline) }
}

$passed = 0
$failed = 0
$pairCount = 0
foreach ($test in $tests) {
    $all = Invoke-Program 'ALL' ([string]$test.all)
    $valid = $false
    $php = $null
    if ($test.mode -eq 'error') {
        $valid = ($null -ne $all.Error -and
                  $all.Error.Contains([string]$test.message_contains) -and
                  $all.Output.Length -eq 0 -and $all.Pipeline.Count -eq 0)
    } else {
        $valid = ($null -eq $all.Error -and $all.Pipeline.Count -eq 0 -and
                  $all.Output -ceq [string]$test.expected)
        if ($test.mode -eq 'pair') {
            $pairCount++
            $php = Invoke-Program 'PHP' ([string]$test.php)
            $valid = ($valid -and $null -eq $php.Error -and $php.Pipeline.Count -eq 0 -and
                      $php.Output -ceq [string]$test.expected -and $php.Output -ceq $all.Output)
        }
    }
    if ($valid) {
        $passed++
        Write-Host "PASS [$($test.mode)]: $($test.name)" -ForegroundColor Green
    } else {
        $failed++
        Write-Host "FAIL [$($test.mode)]: $($test.name)" -ForegroundColor Red
        if ($test.mode -eq 'error') {
            Write-Host "  Expected error contains: $($test.message_contains)"
        } else {
            Write-Host "  Expected: $([string]$test.expected | ConvertTo-Json -Compress)"
        }
        Write-Host "  ALL output: $($all.Output | ConvertTo-Json -Compress)"
        if ($null -ne $all.Error) { Write-Host "  ALL error: $($all.Error)" }
        if ($all.Pipeline.Count -ne 0) { Write-Host "  Unexpected ALL pipeline: $($all.Pipeline -join ' | ')" }
        if ($null -ne $php) {
            Write-Host "  PHP output: $($php.Output | ConvertTo-Json -Compress)"
            if ($null -ne $php.Error) { Write-Host "  PHP error: $($php.Error)" }
        }
    }
}
Write-Host "ALL v0.3: $passed / $($tests.Count) passed; $failed failed; PHP parity cases=$pairCount"
if ($failed -ne 0) { throw "ALL v0.3 regressions: $failed failure(s)" }
