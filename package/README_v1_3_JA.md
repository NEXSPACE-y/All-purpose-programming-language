# ALL v1.3 CLI 改善版（卒業試験の部分成果）

**重要：これはALL独自言語Phaseの完了品ではありません。** 現行v1.2の実装をベースに、CLIのパイプ入力・標準エラー・明示的終了コードを実装した独立パッチです。HTTP並列処理・SQL・外部公開HTTPS・性能改善・デバッガ・OS移植・商用リリース判定は未完了です。

## 追加言語機能

- `stdin_text()` / `標準入力()`：リダイレクト済み標準入力を最大1,048,576文字読み取る。入力が端末のときはエラー。
- `stderr_text("message")` / `標準エラー出力("message")`：標準エラーに1行出力。
- `set_exit_code(23)` / `終了コード設定(23)`：CLIの終了コードを0～255で指定する。命令後も実行を継続する。指定なしは0。実行エラーは1。

## 導入前提

Windows PowerShell 5.1 + 前回ALL v1.2が正常にインストールされていること。インストーラーは既存ファイルをバックアップし、**テスト失敗時は旧版へ復元**します。PHPアダプタとNEXは変更しません。

## 実行手順

```powershell
$zip = "$HOME\Downloads\ALL_professional_v1_3_cli.zip"
$dir = "$HOME\ALL_professional_v1_3_cli_work"
Expand-Archive -LiteralPath $zip -DestinationPath $dir -Force
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
& "$dir\ALL_professional_v1_3_cli\ALL_cli_v1_3_install.ps1"
```

追加8件と、既存478件の合計486件の実行検証を設計。**この環境にはWindows PowerShellが無いため実機での全件合格は未確認**。

## プログラム例

`hello.all`:

```text
変数 入力値 = 標準入力()
表示(入力値)
標準エラー出力("処理しました")
終了コード設定(0)
```

## 卒業判定の未完了項目

1. CLI: shell pipeline, exit codes, stderr (this package aims to address); debugger, trace, signals remain.
2. HTTP: true parallel request processing, retries/timeouts, resource limits, reverse-proxy deployments; load tests.
3. DB: SQL driver, transactions, migrations, concurrency.
4. Runtime: migration/independence from Windows PowerShell, performance comparison with PHP/Python.
5. Ops: Linux, package dependencies, service lifecycle, real domain HTTPS and monitoring.
6. Acceptance: implement the *same* multi-user application in ALL and a reference language; match semantics and run long-duration + concurrency + fault tests.

**公開サーバーの安全性保証はしていません。** 本パッチではHTTPの動作仕様を変更していません。

## 卒業ゲートの実行（診断のみ）

以下は**卒業を宣言するスクリプトではありません**。未実装機能を `NOT_IMPLEMENTED` と判定するため、現段階は必ず `Graduation: INCOMPLETE` になります。

```powershell
& "$dir\ALL_professional_v1_3_cli\ALL_graduation_gate.ps1" -RunRegression -RunLoad
```

ローカルTLSも同時に試す場合は、ご自身のCaddy実行ファイルの正確なパスを与えます。

```powershell
& "$dir\ALL_professional_v1_3_cli\ALL_graduation_gate.ps1" -RunRegression -RunLoad -RunLocalTLS -CaddyExe "C:\path\to\caddy_windows_amd64.exe"
```

公開HTTPS検証はドメイン・外部ネットワークからの実行が必要。仮URLでの代替はしません。
