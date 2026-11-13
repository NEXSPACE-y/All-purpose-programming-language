# ALL PHP v3.9.1 テストスクリプトのBOM修正版

## 修正の対象

- `ALL_PHP_v3_9_1_test.ps1` 先頭の重複UTF-8 BOM（EF BB BF EF BB BF）を単一BOMへ修正。
- 事前検査が不合格ならPHPテストを実行しない `ALL_PHP_v3_9_1_validate.ps1` を追加。
- 全ファイルのSHA256SUMS.txtを再作成。
- `ALL_PHP_v3_9_1_working.ps1` および全テストJSON・期待値は無変更。

## 実行

ZIPを展開し、展開ルートで以下を実行する。

```powershell
& (Join-Path $root 'ALL_PHP_v3_9_1_validate.ps1') -CompileCSharp
```

**注意**: これはPowerShellテストの構文修正版であり、PHP指定3分野の完全互換100%達成認定ではない。既存ALLは変更しない。
