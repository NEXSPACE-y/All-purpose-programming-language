# Stage-specific graduation checks; never prints "graduated" without all gates.
param(
    [switch]$RunRegression,
    [switch]$RunLoad,
    [switch]$RunLocalTLS,
    [string]$CaddyExe,
    [string]$PublicBaseUrl,
    [string]$ReportPath = "$HOME\ALL_graduation_status.json"
)
$ErrorActionPreference='Stop'
$root=$PSScriptRoot
$entries=[System.Collections.Generic.List[object]]::new()
function AddGate([string]$name,[string]$status,[string]$notes) {
    [void]$entries.Add([pscustomobject]@{name=$name;status=$status;notes=$notes})
    Write-Host ("$status | $name | $notes")
}
try {
    if($RunRegression) {
        try {
            & (Join-Path $root 'ALL_cli_v1_3_test.ps1')
            & (Join-Path $root 'ALL_cli_web_v1_2_test.ps1')
            & (Join-Path $root 'ALL_cli_http_v1_1_test.ps1')
            & (Join-Path $root 'ALL_v1_0_test.ps1')
            & (Join-Path $root 'ALL_http_v0_9_test.ps1')
            & (Join-Path $root 'ALL_http_v0_8_test.ps1')
            & (Join-Path $root 'ALL_module_v0_7_test.ps1')
            & (Join-Path $root 'ALL_Japanese_grammar_v0_6_test.ps1')
            & (Join-Path $root 'ALL_language_v0_5_test.ps1')
            & (Join-Path $root 'ALL_JP_v0_4_test.ps1')
            & (Join-Path $root 'ALL_language_v0_3_test.ps1')
            & (Join-Path $root 'ALL_PHP_v3_2_test.ps1')
            AddGate 'CLI+legacy regression (486)' 'PASS' '8 new CLI plus 478 existing cases'
        } catch { AddGate 'CLI+legacy regression (486)' 'FAIL' $_.Exception.Message }
    } else { AddGate 'CLI+legacy regression (486)' 'NOT_RUN' 'Add -RunRegression' }
    if($RunLoad) {
        try {
            $report=Join-Path (Split-Path -Parent $ReportPath) 'ALL_local_load_report.json'
            & (Join-Path $root 'validation_load\ALL_qualification.ps1') -LoadRequests 500 -MaxClients 16 -SoakMinutes 5 -ReportPath $report
            $raw=Get-Content -LiteralPath $report -Raw -Encoding UTF8 | ConvertFrom-Json
            # The source script throws on transport/test failures.
            AddGate 'Local HTTP concurrent-clients/load' 'MEASURED' "Report=$report; not proof of server parallelism"
        } catch { AddGate 'Local HTTP concurrent-clients/load' 'FAIL' $_.Exception.Message }
    } else { AddGate 'Local HTTP concurrent-clients/load' 'NOT_RUN' 'Add -RunLoad' }
    if($RunLocalTLS) {
        try {
            $target=Join-Path $root 'validation_tls\caddy.exe'
            if ([string]::IsNullOrWhiteSpace($CaddyExe) -or -not (Test-Path -LiteralPath $CaddyExe -PathType Leaf)) {
                throw 'Pass -CaddyExe with exact existing caddy Windows amd64/arm64 binary path'
            }
            Copy-Item -LiteralPath $CaddyExe -Destination $target -Force
            & (Join-Path $root 'validation_tls\ALL_local_https_test.ps1') -Requests 20
            AddGate 'Local HTTPS and hostname validation' 'PASS' '20 requests via Caddy TLS; public DNS not tested'
        } catch { AddGate 'Local HTTPS and hostname validation' 'FAIL' $_.Exception.Message }
    } else { AddGate 'Local HTTPS and hostname validation' 'NOT_RUN' 'Add -RunLocalTLS -CaddyExe full-path' }
    if([string]::IsNullOrWhiteSpace($PublicBaseUrl)) {
        AddGate 'Public HTTPS external network' 'BLOCKED' 'A real public deployment and verified domain are required'
    } else {
        try {
            if ($PublicBaseUrl -notmatch '^https://') { throw 'PublicBaseUrl must be HTTPS' }
            $public = Join-Path $root 'validation_load\ALL_https_verify.ps1'
            & $public -BaseUrl $PublicBaseUrl -Requests 100 -ConcurrentClients 8
            AddGate 'Public HTTPS external network' 'MEASURED' 'Run from a separate external network for true external proof'
        } catch { AddGate 'Public HTTPS external network' 'FAIL' $_.Exception.Message }
    }
    # None of the following exist in current ALL v1.3. Do not manufacture passing statuses.
    AddGate 'True concurrent request execution' 'NOT_IMPLEMENTED' 'Existing HTTP handler executes sequentially'
    AddGate 'SQL driver + atomic transactions + migrations' 'NOT_IMPLEMENTED' 'Current KV/JSON is not equivalent to SQL'
    AddGate 'Source debugger and structured stack traces' 'NOT_IMPLEMENTED' 'Needs independent implementation and tests'
    AddGate 'Windows/Linux parity' 'NOT_VERIFIED' 'Windows PowerShell 5.1 only'
    AddGate 'Equal-spec real app vs PHP/Python benchmarks' 'NOT_VERIFIED' 'No equal-workload acceptance data'
    AddGate 'Extended uptime/failure-recovery' 'NOT_VERIFIED' 'Short soak test alone cannot prove extended uptime'
} finally {
    $all=@($entries)
    $graduated = ($all.Count -gt 0 -and @($all | Where-Object { $_.status -ne 'PASS' }).Count -eq 0)
    $payload=[pscustomobject]@{
        generated_utc=[DateTime]::UtcNow.ToString('o')
        graduation_passed=$graduated
        gates=$all
    }
    $parent=Split-Path -Parent $ReportPath
    if($parent -and -not (Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Path $parent -Force | Out-Null}
    $payload | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ReportPath -Encoding UTF8
    Write-Host "Report: $ReportPath"
    Write-Host "Graduation: $(if($graduated){'PASS'}else{'INCOMPLETE'})"
}
