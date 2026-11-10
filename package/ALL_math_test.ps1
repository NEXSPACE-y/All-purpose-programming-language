# ALL v0.2.1 mathematics tests: ALL, direct PHP-subset adapter parity, and offline
# PHP 8.4.24 reference fixtures. The PHP regression suite is tested unchanged.
$ErrorActionPreference = 'Stop'
$core = Join-Path $HOME 'ALL\ALL.ps1'
$caseFile = Join-Path $PSScriptRoot 'ALL_math_cases.json'
$phpCaseFile = Join-Path $PSScriptRoot 'ALL_PHP_v3_1_1_cases.json'
if (-not (Test-Path -LiteralPath $core -PathType Leaf)) { throw "Missing ALL core: $core" }
if (-not (Test-Path -LiteralPath $caseFile -PathType Leaf)) { throw "Missing math fixtures: $caseFile" }
if (-not (Test-Path -LiteralPath $phpCaseFile -PathType Leaf)) { throw "Missing PHP regression fixtures: $phpCaseFile" }

function Invoke-TestLanguage([string]$language, [string]$code) {
    $writer = [System.IO.StringWriter]::new([System.Globalization.CultureInfo]::InvariantCulture)
    $originalOutput = [Console]::Out
    $errorMessage = $null
    $pipeline = @()
    try {
        [Console]::SetOut($writer)
        $pipeline = @(& $core -Language $language -Code $code)
    } catch {
        $errorMessage = $_.Exception.Message
    } finally {
        [Console]::SetOut($originalOutput)
    }
    $output = $writer.ToString()
    $writer.Dispose()
    return [pscustomobject]@{
        Output = $output
        Error = $errorMessage
        Pipeline = @($pipeline)
    }
}

function Equal-TestOutput($actual, [string]$expected, $fixture) {
    if ($null -ne $actual.Error -or $actual.Pipeline.Count -gt 0) { return $false }
    if ($fixture.compare -eq 'numeric') {
        $style = [System.Globalization.NumberStyles]::Float
        $ci = [System.Globalization.CultureInfo]::InvariantCulture
        $a = [double]0
        $b = [double]0
        if (-not [double]::TryParse([string]$actual.Output, $style, $ci, [ref]$a)) { return $false }
        if (-not [double]::TryParse($expected, $style, $ci, [ref]$b)) { return $false }
        $tolerance = [double]$fixture.tolerance
        return ([Math]::Abs($a - $b) -le ($tolerance * [Math]::Max(1.0, [Math]::Abs($b))))
    }
    return ($actual.Output -ceq $expected)
}

# Windows PowerShell 5.1 may return a root JSON array as ONE pipeline object.
# Wrapping `... | ConvertFrom-Json` in @() then creates a nested array: one
# fixture containing all 101 tests. Use -InputObject and validate both lists.
$cases = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $caseFile -Raw -Encoding UTF8)
$phpCases = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $phpCaseFile -Raw -Encoding UTF8)

if (($cases -is [array]) -and $cases.Count -eq 1 -and ($cases[0] -is [array])) { $cases = $cases[0] }
if (($phpCases -is [array]) -and $phpCases.Count -eq 1 -and ($phpCases[0] -is [array])) { $phpCases = $phpCases[0] }

if ($cases.Count -ne 101 -or $phpCases.Count -ne 45) {
    throw "Fixture load error: expected ALL=101 PHP=45; got ALL=$($cases.Count) PHP=$($phpCases.Count)"
}
if ($cases[0].name -cne 'Hello World regression' -or $cases[0].mode -cne 'all' -or
    $phpCases[0].name -cne 'Smoke') {
    throw 'Fixture load error: cases not parsed as individual objects'
}
Write-Host "Loaded fixtures: ALL=$($cases.Count); PHP=$($phpCases.Count); total=$($cases.Count + $phpCases.Count)"
$pass = 0
$fail = 0
$groups = @{}

foreach ($fixture in $cases) {
    $category = [string]$fixture.mode
    if (-not $groups.ContainsKey($category)) { $groups[$category] = @{ Pass=0; Fail=0 } }
    $actual = Invoke-TestLanguage 'ALL' ([string]$fixture.all)
    $ok = $false
    $phpActual = $null
    if ($category -eq 'error') {
        $ok = ($null -ne $actual.Error -and
               $actual.Error.Contains([string]$fixture.message_contains) -and
               $actual.Output.Length -eq 0 -and $actual.Pipeline.Count -eq 0)
    } else {
        $ok = Equal-TestOutput $actual ([string]$fixture.expected) $fixture
        if ($category -eq 'pair') {
            $phpActual = Invoke-TestLanguage 'PHP' ([string]$fixture.php)
            $ok = $ok -and (Equal-TestOutput $phpActual ([string]$fixture.expected) $fixture)
            $ok = $ok -and ($actual.Output -ceq $phpActual.Output)
        }
    }
    if ($ok) {
        Write-Host "PASS [$category]: $($fixture.name)" -ForegroundColor Green
        $pass++
        $groups[$category].Pass++
    } else {
        Write-Host "FAIL [$category]: $($fixture.name)" -ForegroundColor Red
        if ($category -ne 'error') { Write-Host "  Expected: $($fixture.expected | ConvertTo-Json -Compress)" }
        else { Write-Host "  Expected error containing: $($fixture.message_contains)" }
        Write-Host "  ALL output: $($actual.Output | ConvertTo-Json -Compress)"
        if ($null -ne $actual.Error) { Write-Host "  ALL error: $($actual.Error)" }
        if ($actual.Pipeline.Count -gt 0) { Write-Host "  ALL pipeline output: $($actual.Pipeline -join ' | ')" }
        if ($null -ne $phpActual) {
            Write-Host "  PHP adapter output: $($phpActual.Output | ConvertTo-Json -Compress)"
            if ($null -ne $phpActual.Error) { Write-Host "  PHP adapter error: $($phpActual.Error)" }
        }
        $fail++
        $groups[$category].Fail++
    }
}

$groups['php-regression'] = @{ Pass=0; Fail=0 }
foreach ($fixture in $phpCases) {
    $actual = Invoke-TestLanguage 'PHP' ([string]$fixture.code)
    $ok = (Equal-TestOutput $actual ([string]$fixture.expected) $fixture)
    if ($ok) {
        Write-Host "PASS [php-regression]: $($fixture.name)" -ForegroundColor Green
        $pass++
        $groups['php-regression'].Pass++
    } else {
        Write-Host "FAIL [php-regression]: $($fixture.name)" -ForegroundColor Red
        Write-Host "  Expected: $($fixture.expected | ConvertTo-Json -Compress)"
        Write-Host "  Actual: $($actual.Output | ConvertTo-Json -Compress)"
        if ($null -ne $actual.Error) { Write-Host "  Error: $($actual.Error)" }
        $fail++
        $groups['php-regression'].Fail++
    }
}

Write-Host ''
Write-Host '=== ALL mathematics test summary ==='
foreach ($key in @('all','pair','native','error','php-regression')) {
    if ($groups.ContainsKey($key)) {
        Write-Host "  $key`: $($groups[$key].Pass) passed; $($groups[$key].Fail) failed"
    }
}
Write-Host "Result: $pass / $($pass+$fail) passed; $fail failed"
if ($fail -ne 0) { throw "ALL math v0.2.1 test failed: $fail failure(s)" }
