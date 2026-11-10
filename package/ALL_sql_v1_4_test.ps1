# Windows PowerShell 5.1 only. Isolated SQL tests; no existing user DB is touched.
$ErrorActionPreference='Stop'
$core=Join-Path $HOME 'ALL\ALL.ps1'
$passed=0;$failed=0
$testDirectory=Join-Path ([System.IO.Path]::GetTempPath()) ('ALL_SQL_TEST_'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testDirectory -ErrorAction Stop | Out-Null
$previous=(Get-Location).Path
function Invoke-TestCode([string]$code){
    $writer=[System.IO.StringWriter]::new([System.Globalization.CultureInfo]::InvariantCulture)
    $previousWriter=[Console]::Out;$errorMessage=''
    try { [Console]::SetOut($writer); & $core -Language ALL -Code $code | Out-Null }
    catch { $errorMessage=$_.Exception.Message }
    finally { [Console]::SetOut($previousWriter) }
    $r=[pscustomobject]@{Out=$writer.ToString();Err=$errorMessage}
    $writer.Dispose();return $r
}
function CheckCase([string]$name,[string]$code,[string]$expected,[string]$errorPart='') {
    $r=Invoke-TestCode $code
    $ok=if($errorPart){ $r.Err.Contains($errorPart) }else{$r.Err -ceq '' -and $r.Out -ceq $expected}
    if($ok){$script:passed++;Write-Host "PASS [SQL]: $name" -ForegroundColor Green}
    else{$script:failed++;Write-Host "FAIL [SQL]: $name" -ForegroundColor Red;Write-Host "  expected=[$expected] actual=[$($r.Out)] error=[$($r.Err)]"}
}
try {
    Set-Location $testDirectory
    CheckCase 'CREATE TABLE' 'print(sql_exec("test.sqlite","CREATE TABLE items (id INTEGER PRIMARY KEY, name TEXT UNIQUE NOT NULL, qty INTEGER, price REAL, note TEXT)"))' '0'
    CheckCase 'insert positional parameters' 'print(sql_exec("test.sqlite","INSERT INTO items(name,qty,price) VALUES(?,?,?)",["太郎",12,2.5]))' '1'
    CheckCase 'unicode select' 'print(sql_query("test.sqlite","SELECT name FROM items WHERE id=?",[1])[0]["name"])' '太郎'
    CheckCase 'integer result' 'print(sql_query("test.sqlite","SELECT qty FROM items WHERE name=?",["太郎"])[0]["qty"])' '12'
    CheckCase 'floating-point result' 'print(sql_query("test.sqlite","SELECT price FROM items")[0]["price"])' '2.5'
    CheckCase 'null binding and retrieval' 'print(sql_exec("test.sqlite","INSERT INTO items(name,qty,price,note) VALUES(?,?,?,?)",["次郎",0,1.5,null]));print(sql_query("test.sqlite","SELECT note FROM items WHERE name=?",["次郎"])[0]["note"])' '1null'
    CheckCase 'Japanese SQL alias' '表示(SQL検索("test.sqlite","SELECT qty FROM items WHERE name=?",["太郎"])[0]["qty"])' '12'
    CheckCase 'parameterized LIKE safe' 'print(len(sql_query("test.sqlite","SELECT name FROM items WHERE name LIKE ?",["太%"])))' '1'
    CheckCase 'SQL injection stays data' 'print(sql_exec("test.sqlite","INSERT INTO items(name,qty) VALUES(?,?)",["x''); DROP TABLE items;--",2]));print(len(sql_query("test.sqlite","SELECT id FROM items")))' '13'
    CheckCase 'update affected row count' 'print(sql_exec("test.sqlite","UPDATE items SET qty=? WHERE name=?",[13,"太郎"]))' '1'
    CheckCase 'delete affected row count' 'print(sql_exec("test.sqlite","DELETE FROM items WHERE name=?",["次郎"]))' '1'
    CheckCase 'empty result list' 'print(len(sql_query("test.sqlite","SELECT * FROM items WHERE qty < 0")))' '0'
    CheckCase 'transaction commit' 'print(sql_transaction("test.sqlite",[{"sql":"INSERT INTO items(name,qty) VALUES(?,?)","params":["三郎",1]},{"sql":"INSERT INTO items(name,qty) VALUES(?,?)","params":["四郎",2]}]))' '2'
    CheckCase 'committed rows durable' 'print(len(sql_query("test.sqlite","SELECT id FROM items WHERE name IN (?,?)",["三郎","四郎"])))' '2'
    CheckCase 'transaction duplicate unique fails' 'sql_transaction("test.sqlite",[{"sql":"INSERT INTO items(name,qty) VALUES(?,?)","params":["rollback_me",8]},{"sql":"INSERT INTO items(name,qty) VALUES(?,?)","params":["太郎",4]}])' '' 'UNIQUE'
    CheckCase 'transaction rollback is atomic' 'print(len(sql_query("test.sqlite","SELECT id FROM items WHERE name=?",["rollback_me"])))' '0'
    CheckCase 'parameter count mismatch' 'sql_query("test.sqlite","SELECT * FROM items WHERE name=?")' '' 'expected 1 SQL parameters'
    CheckCase 'sql query requires rows' 'sql_query("test.sqlite","CREATE TABLE wrong_call(x INTEGER)")' '' 'requires SELECT'
    CheckCase 'sql exec rejects SELECT' 'sql_exec("test.sqlite","SELECT * FROM items")' '' 'must not return rows'
    CheckCase 'SQL multi-statement rejected' 'sql_exec("test.sqlite","DELETE FROM items; DROP TABLE items;")' '' 'one statement per call'
    CheckCase 'invalid DB extension rejected' 'sql_query("test.txt","SELECT 1")' '' 'expected a .sqlite or .db file'
    CheckCase 'non-array SQL parameters rejected' 'sql_query("test.sqlite","SELECT 1",123)' '' 'SQL parameters must be an array'
    CheckCase 'missing query table' 'sql_query("test.sqlite","SELECT * FROM no_table")' '' 'no such table'
    CheckCase 'read-only SQL with real SELECT expression' 'print(sql_query("test.sqlite","SELECT 8*7 AS answer")[0]["answer"])' '56'
} finally {
    Set-Location $previous
    Remove-Item -LiteralPath $testDirectory -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host "ALL SQLite: $passed / 24 passed; $failed failed"
if($failed -ne 0) {throw "ALL SQLite tests failed: $failed"}
