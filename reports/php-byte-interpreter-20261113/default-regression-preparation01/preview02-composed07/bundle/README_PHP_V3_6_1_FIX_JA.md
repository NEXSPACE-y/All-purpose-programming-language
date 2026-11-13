# ALL PHP v3.6.1 診断メッセージ修正版（2026-11-02）

## 変更内容

Windows PowerShell 5.1 実機での v3.6 検証結果：**413/415 PASS**。
失敗した2件の共通点は、不正入力を正しく拒否しているにもかかわらず、検査用の `error_contains` と実際のエラーメッセージが一致しないことだった。

**元の試験データと期待値は変更していない。** `ALL_PHP_v3_6_adapter.ps1` の拒否メッセージだけ以下の2箇所で修正した。

1. `function f(&$x){}; f(4)` 相当：`ALL PHP: must be a variable passed by reference (argument 'x')` を出す。
2. `trait T extends P {}` 相当：`ALL PHP: Expected '{' after trait name; traits cannot extend classes or implement interfaces` を出す。

両者ともPHP 8.4.24でエラーになることを再確認済み（前者は実行時エラー、後者は構文エラー）。その他のアダプタ実装、テストコード、JSONテストケース、既存のALL本体、PHP v3.5以前のソースには変更を加えていない。

## 互換性検証の状態

- 元版v3.6：Windows PowerShell 5.1の構文・SHA-256・C#事前検査は通過。415件中413件PASS、2件は診断文言の不一致。
- v3.6.1：ソースの文字列2箇所を修正。SHA-256とZIP整合性は再生成・照合済み。
- v3.6.1のWindows PowerShell 5.1実機での415件実行：**未検証**。
- 既存ALLのインストール、その他523件の統合回帰検査：未実施。
- 今回の指定3領域のPHP完全互換：未達成。

## Windows PowerShell 5.1での非破壊検証

修正版ZIPをDownloadsに保存して実行する。

```powershell
$ErrorActionPreference = 'Stop'
$zip = Get-ChildItem (Join-Path $HOME 'Downloads') -Filter 'ALL_PHP_compat_v3_6_1_fix_20261102*.zip' -File |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $zip) { throw 'v3.6.1修正版ZIPが見つかりません' }
$dest = Join-Path $env:TEMP ('ALL_php_v3_6_1_' + [guid]::NewGuid().ToString('N'))
Expand-Archive -LiteralPath $zip.FullName -DestinationPath $dest -ErrorAction Stop
$validate = Get-ChildItem -LiteralPath $dest -Filter 'ALL_PHP_v3_6_validate.ps1' -File -Recurse |
    Select-Object -First 1
if (-not $validate) { throw '検証スクリプトが見つかりません' }
& $validate.FullName -CompileCSharp
```

事前検査成功後に候補アダプタの415件を直接検証する。既存ALLインストール先には書き込まない。テスト成功時に期待する出力は `ALL PHP v3.6 (direct candidate): 415/415 passed; 0 failed`（テスト器の名称はv3.6のまま）だが、**現時点で実測確認された値ではない**。
