# ALL v0.9 — ローカルHTTP APIサーバー

ALLのユーザー定義関数でHTTPリクエストを処理する同期型サーバーを実装。既存v0.8のHTTPクライアントも維持。

- `http_serve(port, "handlerName", requestCount)` / `HTTP配信(...)` を追加
- リスナーは **127.0.0.1限定**（LAN、インターネット公開には非対応）
- `fn handler(req)` / `関数 handler(req)` の戻り値をレスポンスとして送信
- request map のキー: `method`, `path`, `body`, `content_type`
- response map の必須キー: `status`（200〜599）, `body`（文字列）／任意 `content_type`
- 対応: GET, POST, HTTP/1.0・1.1、UTF-8、Content-Length指定
- 同期、最大20リクエスト、受付待ち12秒/件、ヘッダー8KiB、本文64KiB、応答64KiB
- 未対応: HTTPS終端、chunked、WebSocket、並列処理、Cookie・セッション、本番用Webサーバー機能
- 全処理はPowerShell 5.1/.NET FrameworkのTCP機能上で動作する。サーバーのリクエスト判定ロジックはALLで記述する。

## インストール・テスト

```powershell
$zip = "$HOME\Downloads\ALL_server_v0_9.zip"
$dir = "$HOME\ALL_server_v0_9_work"
Expand-Archive -LiteralPath $zip -DestinationPath $dir -Force
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
& "$dir\ALL_server_v0_9\ALL_http_v0_9_install.ps1"
```

テストは新規10件＋v0.8までの409件を再実行。失敗時は旧ALL言語アダプタを自動復元。PHP・NEX・`ALL.ps1`・`run.ps1`は変更しない。

## サンプル起動

別PowerShell画面で:

```powershell
& "$HOME\ALL\run.ps1" -File "$HOME\ALL_server_v0_9_work\ALL_server_v0_9\examples\server.all"
```

3回のリクエストを待つ（各12秒以内）ため、別のPowerShellで順次:

```powershell
Invoke-WebRequest -UseBasicParsing 'http://127.0.0.1:18888/hello'
Invoke-WebRequest -UseBasicParsing 'http://127.0.0.1:18888/json'
Invoke-WebRequest -UseBasicParsing 'http://127.0.0.1:18888/missing' -ErrorAction SilentlyContinue
```

※ PowerShellのInvoke-WebRequestは404で例外を発生させるが、ALLはHTTP 404応答を返す。

## 検証

この環境にはWindows PowerShellがないため、新規ケースのWindows実機での合否は未確認。完全なHTTPサーバーではなく、ローカル用の実験・開発サーバー。
