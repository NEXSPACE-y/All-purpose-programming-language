from pathlib import Path
from difflib import unified_diff
import hashlib, zipfile, json, shutil, subprocess
p=Path('/mnt/data/ALL_PHP_v3_11_3areas_work')
src=p/'ALL_PHP_v3_10_test.ps1'
s=src.read_text(encoding='utf-8-sig')
s=s.replace('ALL_PHP_v3_10_adapter.ps1', 'ALL_PHP_v3_11_adapter.ps1')
s=s.replace('ALL PHP v3.10 (', 'ALL PHP v3.11 (')
old="    @{File='PHP_v3_10_typed_oracle_cases.json'; Count=66; Category='PHP v3.10 typed parameters and returns'}"
new=old[:-1]+",\n    @{File='PHP_v3_11_properties_oracle_cases.json'; Count=77; Category='PHP v3.11 properties/readonly/promotion'}"
if s.count(old)!=1: raise Exception('test insertion missing')
s=s.replace(old,new)
(p/'ALL_PHP_v3_11_test.ps1').write_bytes(b'\xef\xbb\xbf'+s.encode('utf-8'))
s2=(p/'ALL_PHP_v3_10_validate.ps1').read_text('utf-8-sig').replace('ALL_PHP_v3_10_test.ps1','ALL_PHP_v3_11_test.ps1')
(p/'ALL_PHP_v3_11_validate.ps1').write_bytes(b'\xef\xbb\xbf'+s2.encode('utf-8'))
a=(p/'ALL_PHP_v3_10_adapter.ps1').read_text(encoding='utf-8-sig').splitlines(keepends=True)
b=(p/'ALL_PHP_v3_11_adapter.ps1').read_text(encoding='utf-8-sig').splitlines(keepends=True)
diff=''.join(unified_diff(a,b,fromfile='ALL_PHP_v3_10_adapter.ps1',tofile='ALL_PHP_v3_11_adapter.ps1'))
(p/'CHANGE_v3_10_to_v3_11.patch').write_text(diff,encoding='utf-8')
(p/'README_PHP_V3_11_JA.md').write_text('''# ALL PHP v3.11 — 3分野拡張（実装・未検証ソース）

## 開発対象
- **変数・演算子・配列／関数・スコープ／オブジェクト指向**のみ。
- ALL独自言語、PHP既存バージョン、C#補助部品は改変なし。
- v3.10（Windows実機616/616 PASS）は保全し、v3.11を別アダプタとして追加。

## 今回の実装
- 型付きインスタンス／staticプロパティ：宣言時の型保持、初期値チェック、未初期化状態、読み書きの型検査。
- readonlyプロパティ：宣言、初回代入の制約、再代入の禁止（基本規則）。
- コンストラクタのプロパティ昇格：public／protected／private、初期化、既定引数、readonly、型付き引数の連携。
- readonlyクラス：基本宣言、動的プロパティ禁止、継承制約。
- `isset`・`empty`・`unset`と未初期化型付きプロパティの整合。
- クラス内の重複プロパティ宣言を拒否。traitから継承するプロパティの基本情報を保全。

## 検証の事実
- PHP **8.4.24** 実機で新規77件の正常系・異常系期待結果を確認（正常54件、異常23件）。
- **ALL側の693件（v3.10の616件＋新規77件）は未実行**。新実装が77件を満たすとは認定していない。
- PHP本体への委譲、PHPの`eval`/Invoke-Expressionなどによる偽装は行っていない。

## 残る重要な未対応
- `yield`／`yield from`・ジェネレータ、strict_types、正確なint/float・IEEE754挙動。
- PHP 8.4 property hooks、属性、完全な型分散規則、すべてのマジックメソッド・名前解決。
- 型付きプロパティへの参照バインドの制約追跡、および参照による間接書き換えの完全再現。
- PHP公式テストスイートによる全仕様の合否実証、Windows 5.1とLinux上での再実行。
- これらが未解決のため**指定3分野の100%完全互換は未達**。

## セーフティ
- v3.10の既存テスト・期待値は変更なし。
- 新規テスト器は v3.11アダプタを直接実行し、既存ALLのインストール先を変更しない。
- 未対応の参照付きプロパティ昇格は無言で実行せず、明示的な未対応エラーにする。
- `ALL_preflight.ps1` がPowerShell構文・SHA-256を確認し、成功した時だけ `ALL_PHP_v3_11_test.ps1` を走らせる。

## Windowsでの検査コマンド（将来の検証用／現在実行依頼なし）

```powershell
$ErrorActionPreference = 'Stop'
$zip = Get-Item -LiteralPath (Join-Path $HOME 'Downloads\\ALL_PHP_v3_11_3areas_work_20261104.zip') -ErrorAction Stop
$dest = Join-Path $env:TEMP ('ALL_v311_' + [guid]::NewGuid().ToString('N'))
Expand-Archive -LiteralPath $zip.FullName -DestinationPath $dest -ErrorAction Stop
$script = Get-ChildItem -LiteralPath $dest -Filter 'ALL_PHP_v3_11_validate.ps1' -File -Recurse | Select-Object -First 1
if ($null -eq $script) { throw 'v3.11 validator missing' }
& $script.FullName -CompileCSharp
```

このコマンドは非破壊。100%達成前にユーザーへ実行を要求しない。
''',encoding='utf-8')
(p/'PHP_THREE_AREAS_V3_11_STATUS.md').write_text('''# PHP 3分野 完了ゲート（v3.11）

**指定3分野の100%達成認定：NO**

| 完了条件 | 事実 |
|---|---|
| 旧テストの回帰 | v3.10 Windows 616/616 PASS（ユーザー提供ログ）／v3.11は未実行 |
| 変数・演算子・配列の全仕様 | 未網羅。数値、型変換、参照の複合操作、境界が残る |
| 関数・スコープの全仕様 | 未網羅。ジェネレータ、strict_types、クロージャー結合などが残る |
| OOPの全仕様 | 未網羅。property hooks、Attributes、型付き参照、継承の完全分散などが残る |
| PHP実機との新規オラクル | 77件の実行結果を取得。ALL側は未検証 |
| Windows PowerShell 5.1構文・実行 | 未検証 |

この一覧は全仕様の分母ではない。**過去の「約60%」「約65%」等の値は非実測なので引き継がない。**

追加の重要未対応：PHP実機で許される「参照渡し付きプロパティ昇格」はパーサが受理するものの、型付き参照セルへの書込み制約追跡が必要なためALL側では実行時に明示的に拒否する。これを互換済みと数えない。
''',encoding='utf-8')
# developer build scripts kept in a separate folder for audit.
(p/'development').mkdir(exist_ok=True)
for name in ['build_v311.py','make_v311_cases.py','finalize_v311.py']:
    # finalizer is executing now; it is safe to copy its own source
    shutil.copy2(p/name,p/'development'/name)
    (p/name).unlink()
# copy this new file into development too? files preserved already.
# Verify new PHP oracle results independently.
cases=json.loads((p/'PHP_v3_11_properties_oracle_cases.json').read_text('utf-8-sig'))
assert len(cases)==77
for c in cases:
    proc=subprocess.run(['php','-n','-d','display_errors=0','-d','log_errors=0'],input=c['code'],text=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    assert proc.returncode==c['oracle_php_exit'],c['name']
    if 'expected' in c: assert c['expected']==proc.stdout,c['name']
    else: assert proc.returncode!=0,c['name']
# Every .ps1 has at most one leading UTF-8 BOM and only that one.
for script in p.rglob('*.ps1'):
    data=script.read_bytes()
    assert not data.startswith(b'\xef\xbb\xbf\xef\xbb\xbf'),script.name
    assert not data.startswith(b'\xef\xbb\xbf\xef'),script.name
# regenerate manifest. skip existing if present.
manifest=p/'SHA256SUMS.txt'
items=[]
for f in sorted(p.rglob('*')):
    if not f.is_file() or f==manifest: continue
    rel=f.relative_to(p).as_posix()
    items.append((hashlib.sha256(f.read_bytes()).hexdigest().upper(),rel))
manifest.write_text(''.join(f'{h}  {rel}\n' for h,rel in items),encoding='utf-8')
for h,rel in items: assert hashlib.sha256((p/rel).read_bytes()).hexdigest().upper()==h
zpath=Path('/mnt/data/ALL_PHP_v3_11_3areas_work_20261104.zip')
with zipfile.ZipFile(zpath,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as z:
    for f in sorted(p.rglob('*')):
        if f.is_file(): z.write(f,arcname=p.name+'/'+f.relative_to(p).as_posix())
with zipfile.ZipFile(zpath) as z:
    assert z.testzip() is None
    assert len(z.namelist())==len(items)+1
print('RESULT',zpath,'files',len(items)+1,'bytes',zpath.stat().st_size,'oracle',len(cases),'sha256',hashlib.sha256(zpath.read_bytes()).hexdigest())
