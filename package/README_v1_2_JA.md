# ALL v1.2 — CLI実行と公開Webサービスの入口（検証版）

**現状:** 旧v1.1で467件の実機合格。今回の変更は現段階でWindows PowerShell 5.1未検証。プロ用途／公開サービスの完成を保証するものではありません。

## 現行Phaseの範囲

ALL独自言語の完成度向上。PHP互換実装や最終セキュリティ監査は今回行いません。

### CLI

`all.cmd` は PowerShell を別プロセスで起動するネイティブ形式のエントリーポイントです。標準出力・標準エラー出力と `0`／非`0`終了コードを扱い、ファイル実行・引数を受け取ります。

```powershell
& "$HOME\ALL\all.cmd" help
& "$HOME\ALL\all.cmd" version
& "$HOME\ALL\all.cmd" run "C:\work\hello.all" A B
$LASTEXITCODE
```

`0`: 成功、`1`: 読み込みや実行のエラー。標準入力は既存の `input()` を利用します。プロが必要とするストリーム処理・高速起動の全面検証はまだです。

### 公開Webサービスの入口

ALL独自構文 `http_serve_live(port,"handler")` または `HTTP常時配信(port,"handler")` を追加。**待機時間や256件上限で自動停止しない**ローカルHTTPサーバーです。リクエストは順次処理し、異常要求は400、ハンドラ例外は500を返して継続します。最大リクエストヘッダー8KiB、本文64KiB、GET/POSTのみの既存制限は維持します。

```powershell
# Terminal 1 - foreground
& "$HOME\ALL\all.cmd" serve "C:\work\api.all" "C:\work\api.stop"

# Terminal 2
Invoke-WebRequest -UseBasicParsing http://127.0.0.1:18888/health
& "$HOME\ALL\all.cmd" stop "C:\work\api.stop"
```

停止ファイルを検出すると、新規リクエスト受信を止め、リスナーを閉じて終了します。プロセス強制終了の場合は保証しません。

**外部公開はTLSリバースプロキシ経由**とし、ALLを `127.0.0.1` にだけバインドします。`examples/public_service/Caddyfile.example` はCaddyを外部に導入・設定するための参考例です。DNS、ルーター／ファイアウォール、TLS証明書、Caddyのセットアップは別途必要です。ALL自身にはTLS終端・認証を実装していません。認証が必要なサービスはプロキシや別コンポーネント側で実装する必要があります。**認証が必要なデータや管理操作をこのまま公開しないでください。**

**未達事項:** 同時処理・複数プロセス管理・WebSocket・HTTP/2・TLSの内蔵・シグナル統合・統合監視・高負荷の長期試験・Windowsサービス化・Linux。実アプリや本番環境のプロ品質への到達は未評価です。

## インストール／試験

ZIPを展開し、インストーラーを実行します。旧ALLアダプタ、CLI、追加コマンド入口は事前にバックアップし、失敗時は復旧します。PHPとNEXは変更しません。

```powershell
$zip = "$HOME\Downloads\ALL_cli_web_v1_2.zip"
$dir = "$HOME\ALL_cli_web_v1_2_work"
Expand-Archive -LiteralPath $zip -DestinationPath $dir -Force
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
& "$dir\ALL_cli_web_v1_2\ALL_cli_web_v1_2_install.ps1"
```

新規テストと既存467件の回帰を実行します。通信試験は127.0.0.1内部のみで、インターネットへ公開しません。全件合格しても、公開環境での採用判断には追加の実証が必要です。
