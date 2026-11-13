# SQL versioned migrations, checksum, idempotence, rollback.
$ErrorActionPreference='Stop'
$core=Join-Path $HOME 'ALL/ALL.ps1'
$tmp=Join-Path ([IO.Path]::GetTempPath()) ('ALL_MIGRATIONS_'+[guid]::NewGuid().ToString('N'))
$original=(Get-Location).Path
$passed=0;$failed=0
function TestMigration([string]$label,[string]$code,[string]$expected,[string]$errorExpected='') {
    $writer=[IO.StringWriter]::new()
    $before=[Console]::Out;$err=''
    try{[Console]::SetOut($writer);& $core -Language ALL -Code $code | Out-Null}catch{$err=$_.Exception.Message}
    finally{[Console]::SetOut($before)}
    $actual=$writer.ToString();$writer.Dispose()
    $okay=if($errorExpected){$err.Contains($errorExpected)}else{$actual -ceq $expected -and -not $err}
    if($okay){$script:passed++;Write-Host "PASS [Migrations]: $label" -ForegroundColor Green}
    else{$script:failed++;Write-Host "FAIL [Migrations]: $label expected=[$expected] actual=[$actual] error=[$err]" -ForegroundColor Red}
}
try {
    New-Item -ItemType Directory -Path "$tmp/migrations" -Force | Out-Null
    Set-Location $tmp
    [IO.File]::WriteAllText("$tmp/migrations/001_create.sql",'CREATE TABLE people (id INTEGER PRIMARY KEY,name TEXT NOT NULL);',[Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText("$tmp/migrations/002_seed.sql",'INSERT INTO people(name) VALUES(''Alice''); INSERT INTO people(name) VALUES(''Bob'');',[Text.UTF8Encoding]::new($false))
    TestMigration 'initial migrations' 'print(sql_migrate("data.sqlite","migrations"))' '2'
    TestMigration 'idempotence' 'print(sql_migrate("data.sqlite","migrations"))' '0'
    TestMigration 'rows survive' 'print(len(sql_query("data.sqlite","SELECT id FROM people")))' '2'
    [IO.File]::WriteAllText("$tmp/migrations/002_seed.sql",'INSERT INTO people(name) VALUES(''Tampered'');',[Text.UTF8Encoding]::new($false))
    TestMigration 'modified migration rejected' 'sql_migrate("data.sqlite","migrations")' '' 'checksum changed'
    TestMigration 'failed migration leaves previous schema intact' 'print(len(sql_query("data.sqlite","SELECT id FROM people")))' '2'
} finally {
    Set-Location $original
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host "ALL migrations: $passed / 5 passed; $failed failed"
if($failed){throw "ALL migrations failed: $failed"}
