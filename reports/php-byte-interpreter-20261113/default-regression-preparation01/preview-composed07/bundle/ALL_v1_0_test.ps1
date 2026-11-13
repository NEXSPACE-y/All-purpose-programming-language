$ErrorActionPreference='Stop'
$core=Join-Path $HOME 'ALL\ALL.ps1'
$runner=Join-Path $HOME 'ALL\run.ps1'
$passed=0; $failed=0
function Record([string]$name,[bool]$ok,[string]$detail='') {
    if ($ok) { $script:passed++; Write-Host "PASS [Foundations]: $name" -ForegroundColor Green }
    else { $script:failed++; Write-Host "FAIL [Foundations]: $name" -ForegroundColor Red; if ($detail) { Write-Host "  $detail" } }
}
function RunAll([string]$code) {
    $writer=[System.IO.StringWriter]::new([System.Globalization.CultureInfo]::InvariantCulture)
    $old=[Console]::Out; $problem=''; $pipe=@()
    try { [Console]::SetOut($writer); $pipe=@(& $core -Language ALL -Code $code) }
    catch { $problem=$_.Exception.Message }
    finally { [Console]::SetOut($old) }
    $result=[pscustomobject]@{Text=$writer.ToString();Error=$problem;Pipeline=$pipe}
    $writer.Dispose()
    return $result
}
$tests=@(
    @{Name='Namespace English'; Code='namespace Calc { fn add(a,b){ return a+b } };print(Calc::add(4,5))'; Want='9'},
    @{Name='Namespace Japanese'; Code='名前空間 計算 { 関数 加算(a,b) { 返す a+b } };表示(計算::加算(4,8))'; Want='12'},
    @{Name='Namespace isolation'; Code='namespace First { fn num(){return 1} };namespace Second { fn num(){return 2} };print(First::num());print(Second::num())'; Want='12'},
    @{Name='Namespace statement call'; Code='namespace Demo { fn hello(){ print("ok") } };Demo::hello()'; Want='ok'},
    @{Name='Namespace mixed with basic math'; Code='namespace Calc { fn square(n){return n*n} };print(Calc::square(6))'; Want='36'},
    @{Name='Bad namespace member'; Code='namespace Demo { let x=1 }'; Error='Only function declarations'},
    @{Name='Duplicate namespace function'; Code='namespace X { fn f(){return 1} };namespace X { fn f(){return 2} }'; Error='already declared'},
    @{Name='Missing namespace call'; Code='print(X::missing())'; Error='Unknown function'},
    @{Name='Parallel zero rejected'; Code='parallel_all([])'; Error='Expected 1 to 4 tasks'},
    @{Name='Parallel too many rejected'; Code='parallel_all(["print(1)","print(2)","print(3)","print(4)","print(5)"])'; Error='Expected 1 to 4 tasks'}
)
foreach ($t in $tests) {
    $r=RunAll $t.Code
    $ok=if($t.ContainsKey('Error')){$r.Error.Contains($t.Error) -and $r.Text -ceq ''}else{$r.Error -ceq '' -and $r.Text -ceq $t.Want -and $r.Pipeline.Count -eq 0}
    Record $t.Name $ok "Output=[$($r.Text)] Error=[$($r.Error)]"
}
$folder=Join-Path ([System.IO.Path]::GetTempPath()) ('all_v10_test_'+[guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $folder)
$oldLocation=(Get-Location).Path
try {
    Set-Location $folder
    $f='test.allkv'
    $kvCases=@(
        @{Name='KV create and read'; Code='kv_put("test.allkv","name","太郎");print(kv_get("test.allkv","name"))'; Want='太郎'},
        @{Name='KV persists across calls'; Code='print(kv_get("test.allkv","name"))'; Want='太郎'},
        @{Name='KV nested objects'; Code='kv_put("test.allkv","data",{"age":23,"items":[1,2]});let x=kv_get("test.allkv","data");print(x["age"]);print(x["items"][1])'; Want='232'},
        @{Name='KV missing default'; Code='print(kv_get("test.allkv","missing","none"))'; Want='none'},
        @{Name='KV keys'; Code='print(len(kv_keys("test.allkv")))'; Want='2'},
        @{Name='KV delete'; Code='print(kv_delete("test.allkv","name"));print(len(kv_keys("test.allkv")))'; Want='true1'},
        @{Name='KV Japanese aliases'; Code='データ保存("test.allkv","jp",12);表示(データ取得("test.allkv","jp"))'; Want='12'},
        @{Name='KV wrong extension'; Code='kv_put("data.json","x",1)'; Error='Expected .allkv file'},
        @{Name='KV key type'; Code='kv_put("test.allkv",123,1)'; Error='Key must be string'}
    )
    foreach ($t in $kvCases) {
        $r=RunAll $t.Code
        $ok=if($t.ContainsKey('Error')){$r.Error.Contains($t.Error)}else{$r.Error -ceq '' -and $r.Text -ceq $t.Want}
        Record $t.Name $ok "Output=[$($r.Text)] Error=[$($r.Error)]"
    }
    [System.IO.File]::WriteAllText((Join-Path $folder 'corrupt.allkv'),'not json')
    $r=RunAll 'print(kv_get("corrupt.allkv","x"))'
    Record 'KV reject corrupt data' ($r.Error.Contains('Corrupt or incompatible')) $r.Error
    # run independent tasks with no shared mutable state.
    $parallelCases=@(
        @{Name='Parallel independent results'; Code='let results=parallel_all(["print(2+3)","print(7*3)"]);print(results[0]["output"]);print(results[1]["output"])'; Want='521'},
        @{Name='Parallel error is captured'; Code='let results=parallel_all(["print(1)","print(undefined)"]);print(results[0]["ok"]);print(results[1]["ok"])'; Want='truefalse'},
        @{Name='Parallel JP alias'; Code='let 結果=並列実行(["print(6)"]);print(結果[0]["output"])'; Want='6'}
    )
    foreach ($t in $parallelCases) {
        $r=RunAll $t.Code
        Record $t.Name ($r.Error -ceq '' -and $r.Text -ceq $t.Want) "Output=[$($r.Text)] Error=[$($r.Error)]"
    }
    # Offline package, integrity check and namespaced import.
    $project=Join-Path $folder 'project'; $source=Join-Path $folder 'source'
    [void](New-Item -ItemType Directory -Path $project,$source -Force)
    [System.IO.File]::WriteAllText((Join-Path $source 'main.all'), 'namespace Demo { fn plus(a,b){return a+b} }',[System.Text.UTF8Encoding]::new($false))
    $pack=Join-Path $PSScriptRoot 'ALL_package.ps1'
    & $pack -Action init -Project $project | Out-Null
    Record 'Packages manifest init' (Test-Path -LiteralPath (Join-Path $project 'all.packages.json'))
    & $pack -Action add -Project $project -Name demo -Source $source -Version '1.0.0' | Out-Null
    Record 'Packages offline add' (Test-Path -LiteralPath (Join-Path $project 'packages/demo/main.all'))
    $list=@(& $pack -Action list -Project $project)
    Record 'Packages list' ($list.Count -eq 1 -and $list[0] -ceq 'demo 1.0.0') ($list -join '|')
    $verify=@(& $pack -Action verify -Project $project)
    Record 'Packages hash verify' ($verify.Count -eq 1 -and $verify[0] -ceq 'VERIFIED: demo 1.0.0') ($verify -join '|')
    $projectModuleRoot=$env:ALL_MODULE_ROOT
    try {
        $env:ALL_MODULE_ROOT=$project
        $r=RunAll 'import "packages/demo/main.all"
print(Demo::plus(4,5))'
        Record 'Packages imported into ALL namespace' ($r.Error -ceq '' -and $r.Text -ceq '9') "Output=[$($r.Text)] Error=[$($r.Error)]"
    } finally { $env:ALL_MODULE_ROOT=$projectModuleRoot }
    [System.IO.File]::AppendAllText((Join-Path $project 'packages/demo/main.all'),'# tampered')
    $bad=''
    try { & $pack -Action verify -Project $project | Out-Null } catch { $bad=$_.Exception.Message }
    Record 'Packages detect tampering' ($bad.Contains('Hash mismatch')) $bad
} finally {
    Set-Location $oldLocation
    Remove-Item -LiteralPath $folder -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host "ALL foundations v1.0: $passed passed; $failed failed"
if ($failed -gt 0) { throw "ALL foundations failed: $failed" }
