# ALL Professional Integrated Candidate — Windows / Linux 双対応を目指す統合改修

**判定: 開発候補版。正式安定版でも卒業済みでもありません。**

これはユーザー指定の残課題を単独の試作として小出しにせず、一つの配布物で組み合わせるための統合パッケージです。既存 ALL の日英記述と既存PHPアダプタを置換しません。

## 同梱した機能・実装

1. **CLI** — v1.3 のstdin / stderr / 終了コードに加え `all serve-pool` を追加。
2. **HTTPの並行処理** — C#のループバック専用HttpListenerゲートウェイ＋2〜32個の独立したALLワーカープロセス。ワーカー間のALL変数は共有しません。共有永続データはSQLiteを使用できます。複数ワーカーは真のプロセス並行性を持ちますが、負荷性能と各種攻撃耐性は未検証です。
3. **SQLite** — `sql_query` / `sql_exec` / `sql_transaction`。バインド変数、原子的COMMIT/ROLLBACK、Unicode列名、NULL、数値型、トランザクション一括実行。
4. **マイグレーション** — `sql_migrate` / `SQL移行`。連番SQLファイルの自動適用、SHA-256変更検知、トランザクションによるロールバック、冪等な再適用。
5. **デバッグ** — 前処理後の行/列情報付きJSONL命令トレース、関数呼び出しスタック、停止点と対話操作（`next` / `vars` / `stack` / `quit`）。前処理前の元ファイル行番号への厳密マッピングやGUIデバッガは未実装です。
6. **性能比較** — ALLとPythonの同一1000回加算計算の独立プロセス実測、起動込みの時間・CPU時間・PeakWorkingSet測定、JSON証跡。
7. **Windows / Linux** — Windows PowerShell 5.1 + `winsqlite3.dll` と、Linux PowerShell 7 + `libsqlite3.so.0` の別ドライバとインストーラー、Linux用起動スクリプト/検証器。Linux実機での成功は未確認です。
8. **実アプリの比較** — ALLとPythonで `/health`、`GET /items`、`POST /items` を扱い、SQLiteへの登録・取得とJSON出力の内容を照合するテスト。
9. **公開HTTPS** — Caddy用Caddyfile、Linux systemdサービス例、既存TLS試験器、公開HTTPS検証器。DNS・実サーバー・正規TLS証明書・外部回線の疎通は未実施です。


## インストール前の全ファイル検証（既存ALLを変更しません）

次のコマンドで、再帰的な PowerShell 構文解析、配布ファイル SHA-256、Windows C# コンパイルを先に実施してください。

```powershell
& "$dir\ALL_phase1_source_debug_candidate_20261102\ALL_preflight.ps1" -CompileCSharp
```

すべて PASS と表示された場合だけインストールしてください。`ALL_integrated_install.ps1` 自身も、
インストール直前に同じ事前検証を強制実行します。

```powershell
& "$dir\ALL_phase1_source_debug_candidate_20261102\ALL_integrated_install.ps1"
```

なおパスの中の `ALL_phase1_source_debug_candidate_20261102` は今回の ZIP 内フォルダー名です。

## 既存Windows環境へインストールし一括試験

前提: 既存の `%USERPROFILE%\ALL\ALL.ps1` および `languages\php.ps1` が動作していること。

```powershell
$zip = "$HOME\Downloads\ALL_phase1_source_debug_candidate_20261102.zip"
$dir = "$HOME\ALL_professional_integrated_work"
Expand-Archive -LiteralPath $zip -DestinationPath $dir -Force
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
& "$dir\ALL_phase1_source_debug_candidate_20261102\ALL_integrated_install.ps1"
```

このインストーラーはPS構文チェックとC#コンパイルチェックを最初に行い、既存486件、新規SQL24件、マイグレーション5件、デバッグ3件、並行HTTP5件を検証します。合計523件相当ですが**Windows実機で成功した事実はこの候補版ではまだありません**。失敗すると変更対象を旧版へ戻します。

## ALL独自コードによるSQL

```text
let migrationCount = sql_migrate("items.sqlite", "migrations")
let added = sql_exec("items.sqlite", "INSERT INTO items(name,qty) VALUES(?,?)", ["太郎", 3])
let rows = sql_query("items.sqlite", "SELECT name,qty FROM items WHERE qty >= ?", [2])
print(rows[0]["name"])
```

SQLのファイルパスはALLプログラムのカレントディレクトリ基準です。複数ワーカー起動時は`.all`ファイルの親フォルダへ移動して起動します。

## 真の並行HTTP（Caddyで外部公開する場合はゲートウェイを直接公開しない）

```powershell
& "$HOME\ALL\all.cmd" serve-pool "C:\path\to\service.all" "$HOME\ALL\pool.stop" 4
```

別のPowerShellで:

```powershell
Invoke-WebRequest -UseBasicParsing http://127.0.0.1:18888/health
& "$HOME\ALL\all.cmd" stop "$HOME\ALL\pool.stop"
```

Linuxでは `~/ALL/all serve-pool /path/to/service.all /path/to/stop 4`（`pwsh` のインストールが必要）。Windowsの `all.cmd` はWindows専用です。

## デバッガ

```powershell
& "$HOME\ALL\ALL_debug.ps1" -File "C:\path\test.all" -TracePath "$HOME\trace.jsonl"
& "$HOME\ALL\ALL_debug.ps1" -File "C:\path\test.all" -Breakpoints "2,5" -TracePath "$HOME\trace.jsonl"
```

行番号は自然日本語の正規化および `import` 展開後のソースに対応します。日本語の自然文法と複数ファイルで元ソース行位置まで完全一致するとは限りません。

## 卒業判定（未実施をPASS扱いしない）

```powershell
& "$dir\ALL_phase1_source_debug_candidate_20261102\ALL_full_gate.ps1" -RunInstalledTests -RunRealAppParity -RunPerformanceComparison -PythonExe python
```

追加実測レポート: ローカル負荷試験は `validation_load/ALL_qualification.ps1`、ローカルTLSは `validation_tls/ALL_local_https_test.ps1`、公開TLSは `validation_load/ALL_https_verify.ps1`。

## 必須の未検証事項

- **Windows実機**: 上記統合候補のC#コンパイルと新規試験の成否。
- **Linux実機**: `pwsh` + SQLiteネイティブライブラリのインストール、 `ALL_install_linux.ps1`、 `ALL_linux_validation.ps1` による試験。
- **公開HTTPS**: 実ドメイン、公開ホスト、DNS、TLS、異なる外部回線からの到達性。`*.example` は実URLとして使用できません。
- **継続運用**: システムに必要なRPS/p95/p99/障害復旧/運用期間の要求値を設定したうえで耐久試験。短期5分試験だけでは長期安定は保証されません。
- **完全な言語代替**: SQLite BLOB、SQLの全機能、非同期・ジョブ制御、プロトコル完全性、成熟したライブラリ資産などには未対応や未検証部分があります。

これらの不足が残る間、**完成・プロ用途全面合格・卒業を宣言しません。**
