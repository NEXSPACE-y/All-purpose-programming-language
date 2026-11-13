# ALL PHP v3.8 / 指定3分野の追加改修候補

**ステータス: 3分野100%には未到達。PowerShell 5.1による新候補の実機試験は未実施。**

## 現在の客観的な基準

- v3.7 はユーザー実機により **460/460 PASS**（2026-11-03）。今回の新候補はその合格結果を流用しない。
- 今回の新規47件は PHP 8.4.24 実機にて期待出力を取得済み（全47件）。これは **ALL v3.8 自体の試験合格ではない**。
- v3.8 は既存460件の検査項目に新規47件を加えて **507件**。内訳：v3.7の拒否テスト1件を「新たにサポートされた機能」へ分類し直したが、元のJSONファイル・元の期待値は変更していない。
- 既存v3.7の133ファイルはすべてバイト一致で保全。これを含む候補は別ファイル `ALL_PHP_v3_8_adapter.ps1` に実装している。

## 今回実装した対象

1. **変数・演算子・配列**: 配列要素、オブジェクトプロパティ、staticプロパティの参照セル。参照代入・参照更新・配列コピー後の参照維持。`foreach`の参照走査。
2. **関数・スコープ**: 配列要素／オブジェクトプロパティ／staticプロパティを参照引数に渡す処理。PHP 8.1以降のfirst-class callable（グローバル関数・一部組み込み・公開インスタンスメソッド・staticメソッド・クロージャー等）。
3. **オブジェクト指向**: 未定義プロパティに対する `__isset`／`__unset` の基本動作。

## 検証コマンド（Windows PowerShell 5.1）

DownloadsのZIPを展開せずに、以下をPowerShellに貼り付けて実行：

```powershell
$ErrorActionPreference = 'Stop'
$zip = Get-ChildItem (Join-Path $HOME 'Downloads') -Filter 'ALL_PHP_compat_v3_8_candidate_20261103*.zip' -File |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $zip) { throw 'v3.8 ZIPが見つかりません' }
$dest = Join-Path $env:TEMP ('ALL_php_v3_8_' + [guid]::NewGuid().ToString('N'))
Expand-Archive -LiteralPath $zip.FullName -DestinationPath $dest -ErrorAction Stop
$validation = Get-ChildItem -LiteralPath $dest -Filter 'ALL_PHP_v3_8_validate.ps1' -File -Recurse | Select-Object -First 1
if (-not $validation) { throw '検証スクリプトが見つかりません' }
& $validation.FullName -CompileCSharp
```

期待値: `ALL PHP v3.8 (direct candidate): 507/507 passed; 0 failed`。**実行済みの結果ではない**。

## 注意事項

- 既存のPHPアダプタ、ALL独自言語、PHPのインストール先は変更しない。インストーラーは追加していない。
- 現実のPHPの全参照挙動、型システム・enum・プロパティフック・ジェネレータ・参照返却・循環参照・数値境界は未実装／未検証のまま。
- 未実装を拒否して正常系に見せたり、テストに合わせてPHP本体と異なる実装へ妥協したりしない。
- 今回のテスト数に成功したとしても指定3分野100%の証拠ではない。
