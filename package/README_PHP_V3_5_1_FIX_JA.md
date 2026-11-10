# ALL PHP v3.5.1 — v3.5構文エラー修正版（2026-11-02）

## 修正範囲

Windows PowerShell 5.1の事前検査で `ALL_PHP_v3_5_adapter.ps1` の2078行にある `Invoke-PhpCallable` の呼び出しを途中で改行していたため、PowerShellの構文解析が失敗した。

- `ALL_PHP_v3_5_adapter.ps1` の **当該呼び出し1箇所だけを1行に修正**。ロジックは変更していない。
- 新規 `ALL_PHP_v3_5_1_validate.ps1` は事前検査合格後にのみ旧 `ALL_PHP_v3_5_test.ps1` を実行する読み取り専用ラッパー。
- 旧v3.4以前のファイル、ALL本体、PHP旧アダプタ、既存のテストデータは変更していない。
- `SHA256SUMS.txt` は再生成した。

## 実機での試験（既存インストール変更なし）

以下を **Windows PowerShell 5.1** に一括貼り付けして実行する。Downloadsに ZIP を保存済みであること。

```powershell
$ErrorActionPreference = 'Stop'
$zip = Get-ChildItem (Join-Path $HOME 'Downloads') -Filter 'ALL_PHP_compat_v3_5_1_fix_20261102*.zip' -File |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $zip) { throw '修正版のZIPがDownloadsに見つかりません' }
$dest = Join-Path $env:TEMP ('ALL_php_v3_5_1_validate_' + [guid]::NewGuid().ToString('N'))
Expand-Archive -LiteralPath $zip.FullName -DestinationPath $dest -ErrorAction Stop
$validate = Get-ChildItem -LiteralPath $dest -Filter 'ALL_PHP_v3_5_1_validate.ps1' -File -Recurse |
    Select-Object -First 1
if (-not $validate) { throw '検証スクリプトが見つかりません' }
& $validate.FullName -CompileCSharp
```

出力に `ALL preflight PASS` が出た場合のみ329件の実行テストへ進む。最終行 `329/329 passed; 0 failed` は期待値であり、実行前の時点では結果未確認。

## 実施済みの検査と制限

- 配布物の全ファイル内容とZIP格納内容を再照合し、SHA-256全件一致を確認した。
- 元v3.5のファイルとの差分は当該1行、追加検証ラッパー、README、SHA-256マニフェストだけ。
- Pythonの字句レベルで引用符・括弧の釣り合いを確認した。
- **作成環境にはPowerShell実行環境がないため、PowerShell構文解析の実行と329件テストは未実施。** Windows実機のPASSが得られるまで合格とは扱わない。
- v3.5の3領域を含むPHP完全互換は未達。今回の作業は構文不具合の修正に限定。
