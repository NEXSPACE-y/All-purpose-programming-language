# Runs two programs through the same candidate adapter in one fresh PS5.1 process.
# Deliberately does not clear or alter the adapter's internal prelude cache/state.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$AdapterPath,
    [ValidateSet(0,1)][int]$Parity = 0,
    [ValidateSet('bare','binary')][string]$SeedShape = 'bare',
    [Parameter(Mandatory=$true)][string]$OutputDirectory
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Utility\Microsoft.PowerShell.Utility.psd1') -ErrorAction Stop
$utf8 = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = $utf8
$adapterFull = (Resolve-Path -LiteralPath $AdapterPath).ProviderPath
[void][IO.Directory]::CreateDirectory($OutputDirectory)
$outFull = (Resolve-Path -LiteralPath $OutputDirectory).ProviderPath
$before = (Get-FileHash -LiteralPath $adapterFull -Algorithm SHA256).Hash.ToLowerInvariant()
$adapterBytes = [IO.File]::ReadAllBytes($adapterFull)
[IO.File]::WriteAllBytes((Join-Path $outFull 'adapter.snapshot.ps1'), $adapterBytes)
# Put the extra empty statement inside the namespace, keeping both seeds legal PHP.
$fragment = if ($SeedShape -ceq 'bare') { 'X;' } else { 'X+X;' }
$repetitions = if ($SeedShape -ceq 'bare') { 300 } else { 150 }
$seed = '<?php namespace A;' + (';' * $Parity) + ' define(''A\X'',0);' + ($fragment * $repetitions) + ' try {} catch(\Throwable $e) {}'
$second = '<?php $e=new Exception(''x''); $s=$e->__toString(); echo ''clean'';'
[IO.File]::WriteAllText((Join-Path $outFull 'seed.php'), $seed, $utf8)
[IO.File]::WriteAllText((Join-Path $outFull 'second.php'), $second, $utf8)
$adapter = & $adapterFull
if ($null -eq $adapter -or $adapter.Run -isnot [scriptblock]) { throw 'Adapter did not return Run scriptblock' }
$run = $adapter.Run

function Invoke-Observed([string]$label, [string]$code) {
    $writer = New-Object System.IO.StringWriter([Globalization.CultureInfo]::InvariantCulture)
    $saved = [Console]::Out
    $pipeline = @()
    $failure = $null
    $clock = [Diagnostics.Stopwatch]::StartNew()
    try {
        [Console]::SetOut($writer)
        $pipeline = @(& $run -Code $code)
    } catch {
        $failure = [ordered]@{
            message = $_.Exception.Message
            type = $_.Exception.GetType().FullName
            fully_qualified_error_id = $_.FullyQualifiedErrorId
            position = $_.InvocationInfo.PositionMessage
            script_stack_trace = $_.ScriptStackTrace
        }
    } finally {
        [Console]::SetOut($saved)
        $clock.Stop()
    }
    $value = $writer.ToString()
    $writer.Dispose()
    [IO.File]::WriteAllText((Join-Path $outFull ($label + '.stdout.txt')), $value, $utf8)
    $observedPipeline = @($pipeline | ForEach-Object {
        [ordered]@{ type = if ($null -eq $_) { 'null' } else { $_.GetType().FullName }; value = [string]$_ }
    })
    return [pscustomobject]@{
        label = $label; stdout = $value; pipeline = $observedPipeline
        error = $failure; elapsed_ms = $clock.ElapsedMilliseconds
    }
}

$seedResult = Invoke-Observed 'seed' $seed
$secondResult = Invoke-Observed 'second' $second
$after = (Get-FileHash -LiteralPath $adapterFull -Algorithm SHA256).Hash.ToLowerInvariant()
$seedOk = $null -eq $seedResult.error -and $seedResult.stdout -ceq '' -and $seedResult.pipeline.Count -eq 0
$secondOk = $null -eq $secondResult.error -and $secondResult.stdout -ceq 'clean' -and $secondResult.pipeline.Count -eq 0
$ok = $seedOk -and $secondOk -and $before -ceq $after
$report = [ordered]@{
    schema_version = '1.0'
    status = if ($ok) { 'PASS' } else { 'FAIL' }
    process_id = $PID
    powershell_version = $PSVersionTable.PSVersion.ToString()
    parity = $Parity
    repetitions = $repetitions
    seed_shape = $SeedShape
    repeated_fragment = $fragment
    extra_semicolon_placement = 'after namespace A; before define'
    execution_mode = 'same adapter Run scriptblock, seed then second; fresh process per parity; no cache reset'
    adapter_path = $adapterFull
    adapter_sha256_before = $before
    adapter_sha256_after = $after
    inputs_unchanged = $before -ceq $after
    seed_sha256 = (Get-FileHash -LiteralPath (Join-Path $outFull 'seed.php') -Algorithm SHA256).Hash.ToLowerInvariant()
    second_sha256 = (Get-FileHash -LiteralPath (Join-Path $outFull 'second.php') -Algorithm SHA256).Hash.ToLowerInvariant()
    seed_expected = ''; second_expected = 'clean'
    seed_passed = $seedOk; second_passed = $secondOk
    seed = $seedResult; second = $secondResult
}
[IO.File]::WriteAllText((Join-Path $outFull 'report.json'), ($report | ConvertTo-Json -Depth 8), $utf8)
[Console]::WriteLine(($report | ConvertTo-Json -Depth 8 -Compress))
if ($ok) { exit 0 } else { exit 1 }
