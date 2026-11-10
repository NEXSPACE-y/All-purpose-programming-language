# ALL v0.8 — HTTPクライアント（日英共用）

この版は、ALL v0.7の受け入れ基盤と既存PHP・NEXを変更せず、ALL言語アダプタだけにHTTPクライアントを追加する。
Windows PowerShell 5.1 / .NET Framework のHTTP機能を利用するため、独立したHTTPスタックの実装ではない。

## 追加した組み込み関数

| 英語 | 日本語別名 | 動作 |
| --- | --- | --- |
| `http_get(url)` | `HTTP取得(url)` | GET |
| `http_post(url, body)` / `http_post(url, body, content_type)` | `HTTP送信(...)` | POST |
| `http_post_json(url, value)` | `JSON送信(...)` | JSONシリアライズしてPOST |

返り値はALLの辞書。`status`（HTTPステータス番号）、`ok`（2xxならtrue）、`body`（UTF-8文字列）、`content_type`を持つ。
404・302などは例外にせず辞書を返す。HTTP以外のURL、認証情報入りURL、通信失敗、UTF-8でない応答、サイズ超過はエラー。
自動リダイレクトなし。送信本文は最大65536バイト、応答は最大1048576バイト、タイムアウト5秒。
バイナリ転送、HTTPサーバー、TLS設定、Cookieやセッション、WebSocket、ストリーミング、HTTP認証は未実装。

## コード例

```all
変数 応答 = HTTP取得("https://example.com/")
もし (応答["ok"] == true) {
    表示行(応答["body"])
}
```

JSONのPOST:

```all
変数 結果 = JSON送信("https://example.com/api", {"message": "こんにちは"})
表示行(結果["status"])
```

※この外部URLの例は構文例であり、テストではアクセスしない。

## インストール・自動テスト

ZIPを `Downloads` へ配置してWindows PowerShellから実行:

```powershell
$zip = "$HOME\Downloads\ALL_http_v0_8.zip"
$dir = "$HOME\ALL_http_v0_8_work"
Expand-Archive -LiteralPath $zip -DestinationPath $dir -Force
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
& "$dir\ALL_http_v0_8\ALL_http_v0_8_install.ps1"
```

- 新規16件：TCPループバック一時サーバーを起動してGET/POST・UTF-8・404・302・JSON・エラー処理を確認（外部通信なし）
- 既存393件：v0.7以降の全回帰テスト
- **合計409件**。全件合格したときだけ`all.ps1`更新が確定する。
- 失敗時には `all.ps1` のバックアップを復元する。`run.ps1`、PHPアダプタ、NEXは変更しない。
- インストール中にStart-Jobで一時サーバーを起動し、処理終了時に停止・削除する。ポートは127.0.0.1へ限定。

## 検証状態

この配布環境ではWindows PowerShellが使用できないため、PowerShell実機テスト409件の成否は**未確認**。
テストケース・コード構成を確認したが、合格を保証していない。
