# ALL PHP v3.11 — 3分野拡張（実装・未検証ソース）

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
$zip = Get-Item -LiteralPath (Join-Path $HOME 'Downloads\ALL_PHP_v3_11_3areas_work_20261104.zip') -ErrorAction Stop
$dest = Join-Path $env:TEMP ('ALL_v311_' + [guid]::NewGuid().ToString('N'))
Expand-Archive -LiteralPath $zip.FullName -DestinationPath $dest -ErrorAction Stop
$script = Get-ChildItem -LiteralPath $dest -Filter 'ALL_PHP_v3_11_validate.ps1' -File -Recurse | Select-Object -First 1
if ($null -eq $script) { throw 'v3.11 validator missing' }
& $script.FullName -CompileCSharp
```

このコマンドは非破壊。100%達成前にユーザーへ実行を要求しない。
