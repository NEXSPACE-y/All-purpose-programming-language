# ALL PHP v3.9.2 回帰不一致修正版（2026-11-03）

## 原因と修正（元のユーザーログ：547/550）

1. `reference return trait method` は**実装の不具合**。trait のメソッドをクラスへ取り込む際、`ReturnByRef` がコピーされていなかった。`ALL_PHP_v3_9_2_adapter.ps1` のクラス取り込み時に `ReturnByRef=$method.ReturnByRef` を追加。通常のメソッド・trait別名のパスは変更しない。
2. `closure return byref unsupported` と `byref variadic unsupported` は過去の**未実装拒否テスト**。機能実装済みとなったため当時のエラー要求が不適切。オリジナルの `PHP_v3_8_retained_v3_7_guards.json`（18件）は**一切変更せず保全**。16件だけ抽出した `PHP_v3_9_2_active_guards.json` と、PHP 8.4.24で期待値検証した2件の実動作テスト `PHP_v3_9_2_native_oracle_cases.json` にアクティブな検証を移した。

## テスト数と判定

- 全550件相当（既存550件から古い未対応拒否2件をアクティブゲートから移し、**同じ対象機能の実動作テスト2件**を追加）
- 旧テストJSONの期待値・ソースは**変更していない**。
- PHP 8.4.24 の新規2ケース実機照合：**2/2 PASS**。
- `ALL_PHP_v3_9_1_working.ps1`、旧テスト、ALL独自処理系：**変更なし**。
- PowerShell 5.1のv3.9.2全550件の実行：**未確認**（環境にPowerShell 5.1なし）。したがって550/550合格とは現段階では宣言しない。
- 指定3分野全仕様の完全互換100%：**未達**。他の未対応仕様は引き続き別途存在する。

## 非破壊のWindows検証コマンド（実行は任意）

```powershell
$ErrorActionPreference = 'Stop'
$zip = Get-ChildItem "$HOME\Downloads" -Filter 'ALL_PHP_v3_9_2_regression_fix_20261103*.zip' -File |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $zip) { throw 'ZIPが見つかりません' }
$dest = Join-Path $env:TEMP ('ALL_php_v392_' + [guid]::NewGuid().ToString('N'))
Expand-Archive -LiteralPath $zip.FullName -DestinationPath $dest -ErrorAction Stop
$validate = Get-ChildItem -LiteralPath $dest -Filter 'ALL_PHP_v3_9_2_validate.ps1' -File -Recurse |
    Select-Object -First 1
if (-not $validate) { throw '検証スクリプトが見つかりません' }
& $validate.FullName -CompileCSharp
```

候補アダプタを直接実行するだけで、インストール済みALLには変更を加えない。事前検査で失敗すればテストは起動しない。
