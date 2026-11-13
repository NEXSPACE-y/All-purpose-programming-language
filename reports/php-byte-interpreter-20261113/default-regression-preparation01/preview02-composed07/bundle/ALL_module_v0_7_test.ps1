$ErrorActionPreference = 'Stop'
$core = Join-Path $HOME 'ALL\ALL.ps1'
$runner = Join-Path $HOME 'ALL\run.ps1'
$casesPath = Join-Path $PSScriptRoot 'ALL_module_v0_7_cases.json'
$cases = @(ConvertFrom-Json -InputObject (Get-Content -LiteralPath $casesPath -Raw -Encoding UTF8))
if ($cases.Count -eq 1 -and $cases[0] -is [array]) { $cases = @($cases[0]) }
if ($cases.Count -ne 25) { throw "Expected 25 cases, got $($cases.Count)" }
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('allmod07_' + [guid]::NewGuid().ToString('N'))
[void][System.IO.Directory]::CreateDirectory($tempRoot)
$success = 0
$failed = 0
try {
    foreach ($case in $cases) {
        $project = Join-Path $tempRoot ([string]($success + $failed))
        [void][System.IO.Directory]::CreateDirectory($project)
        foreach ($property in $case.files.PSObject.Properties) {
            $target = Join-Path $project $property.Name
            $parent = [System.IO.Path]::GetDirectoryName($target)
            [void][System.IO.Directory]::CreateDirectory($parent)
            [System.IO.File]::WriteAllText($target,[string]$property.Value,[System.Text.UTF8Encoding]::new($false))
        }
        $mainPath = Join-Path $project 'main.all'
        [System.IO.File]::WriteAllText($mainPath,[string]$case.main,[System.Text.UTF8Encoding]::new($false))
        $capture = [System.IO.StringWriter]::new([System.Globalization.CultureInfo]::InvariantCulture)
        $previousOut = [Console]::Out
        $pipeline = @()
        $actualError = $null
        try {
            [Console]::SetOut($capture)
            if ($case.inline) {
                Push-Location -LiteralPath $project
                try { $pipeline = @(& $core -Language ALL -Code ([string]$case.main)) }
                finally { Pop-Location }
            } else {
                $pipeline = @(& $runner -File $mainPath)
            }
        } catch { $actualError = $_.Exception.Message }
        finally { [Console]::SetOut($previousOut) }
        $actual = $capture.ToString()
        $capture.Dispose()
        if ($null -ne $case.error_contains) {
            $ok = ($null -ne $actualError -and $actualError.Contains([string]$case.error_contains) -and $actual.Length -eq 0 -and $pipeline.Count -eq 0)
        } else {
            $ok = ($null -eq $actualError -and $actual -ceq ([string]$case.expected).Replace('\n',"`n") -and $pipeline.Count -eq 0)
        }
        if ($ok) {
            $success++
            Write-Host "PASS [Module]: $($case.name)" -ForegroundColor Green
        } else {
            $failed++
            Write-Host "FAIL [Module]: $($case.name)" -ForegroundColor Red
            Write-Host "  Expected: $($case.expected)"
            Write-Host "  Actual: $($actual | ConvertTo-Json -Compress)"
            Write-Host "  Error: $actualError"
            if ($pipeline.Count -gt 0) { Write-Host "  Unexpected pipeline: $($pipeline -join '|')" }
        }
    }
} finally {
    if ([System.IO.Directory]::Exists($tempRoot)) { [System.IO.Directory]::Delete($tempRoot,$true) }
}
# An actual multi-file CLI program: load UTF-8 JSON, calculate totals, persist JSON.
$cliPath = Join-Path $PSScriptRoot 'examples\cli_report'
$tempCli = Join-Path ([System.IO.Path]::GetTempPath()) ('all_cli07_' + [guid]::NewGuid().ToString('N'))
[void][System.IO.Directory]::CreateDirectory($tempCli)
try {
    Copy-Item -Path (Join-Path $cliPath '*') -Destination $tempCli -Recurse -Force
    $writer = [System.IO.StringWriter]::new([System.Globalization.CultureInfo]::InvariantCulture)
    $savedOut = [Console]::Out
    $cliError = $null
    $pipeline = @()
    try {
        [Console]::SetOut($writer)
        Push-Location -LiteralPath $tempCli
        try { $pipeline = @(& $runner -File (Join-Path $tempCli 'main.all')) }
        finally { Pop-Location }
    } catch { $cliError = $_.Exception.Message }
    finally { [Console]::SetOut($savedOut) }
    $cliText = $writer.ToString()
    $writer.Dispose()
    $resultPath = Join-Path $tempCli 'result.json'
    $total = $null
    if (Test-Path -LiteralPath $resultPath) {
        $report = ConvertFrom-Json -InputObject ([System.IO.File]::ReadAllText($resultPath,[System.Text.Encoding]::UTF8))
        $total = $report.'合計'
    }
    $ok = ($null -eq $cliError -and $pipeline.Count -eq 0 -and
           $cliText -ceq "集計:商品売上`n480`n" -and $total -eq 480)
    if ($ok) { $success++; Write-Host 'PASS [Module]: Multi-file sales report CLI' -ForegroundColor Green }
    else {
        $failed++
        Write-Host 'FAIL [Module]: Multi-file sales report CLI' -ForegroundColor Red
        Write-Host "  Output: $($cliText | ConvertTo-Json -Compress)"
        Write-Host "  Total: $total; Error: $cliError"
    }
} finally {
    if ([System.IO.Directory]::Exists($tempCli)) { [System.IO.Directory]::Delete($tempCli,$true) }
}

Write-Host "ALL modules v0.7: $success / 26 passed; $failed failed"
if ($failed -ne 0) { throw "ALL modules v0.7 regressions: $failed failure(s)" }
