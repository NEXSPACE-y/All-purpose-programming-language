# ALL Phase 1 — Source Debug / Parser Index Candidate (2026-11-02)

**Phase 1継続用の追加候補版。正式完成版・本番利用認定版ではありません。**

## 現行ベースラインの保全

- 入力：`ALL_professional_integrated_candidate_v1_0_1_fix.zip`（元ZIPは変更しません）。
- 入力済みの既存機能・PHPアダプタ・言語構文・C# Gateway/SQLiteの機能仕様は変更していません。
- 既存の **523件（486+24+5+3+5）** を保持。引継ぎ書では旧統合版のWindows実機 **523/523 PASS** が報告されていますが、この候補版のWindows実機再試験ではありません。
- 追加の独立した **4件** は `ALL_debug_source_test.ps1`。期待値の書換えではなく新規テストです。

## 変更内容（限定）

1. `ALL_v1_0_adapter.ps1`：従来、命令ごとに先頭から部分文字列を作り改行数を数えていた解析を、前計算済みの行開始オフセットと二分探索に変更（推定計算量：O(文数×ソース長) → O(ソース長+文数×log 行数)）。**速度改善量は実測未確認**。
2. 同アダプタ：モジュール展開・日本語文型変換後でも、トレースの `source_file`（元ファイルの絶対パス）と `source_line`（元ファイル行番号）を出す。直接 `-Code` 実行では `source_file` は `<inline>`。既存 `line`、`column` は引き続き**前処理後位置**で、既存トレースの互換性を維持。
3. `ALL_run.ps1`：`ALL_SOURCE_FILE` を実行中のみ設定・終了時に必ず復元する。言語機能の結果には影響させない。
4. `ALL_debug_source_test.ps1`：import先と呼出元、自然日本語構文、inlineコードの4回帰テストを追加。
5. `ALL_integrated_install.ps1` と `ALL_full_gate.ps1` に追加4件を組み込む。**523件は依然として独立した回帰基準**。

## 導入前に必須の確認

Windows PowerShell 5.1 のあるユーザー環境で、まず読み取り専用の事前検査を行い、既存ファイルを書き換える前に妥当性を確認してください。

```powershell
$root = 'C:\path\to\ALL_phase1_source_debug_candidate_20261102'
& "$root\ALL_preflight.ps1" -CompileCSharp
```

**インストールと527件の試験は、実行環境を保全したうえで承認された場合のみ**行ってください。インストーラーはテスト失敗時に元ファイルへのロールバックを試みます。

```powershell
& "$root\ALL_integrated_install.ps1"
```

**現時点の未検証**：新候補版でのWindows PowerShell構文解析・C#コンパイル・523件再実行・追加4件、Linux実機稼働、実負荷性能、公開HTTPS、長期稼働。PowerShellがない開発環境ではこれらの実機試験を実施していません。SHA-256マニフェストは別途再生成済み。

## 位置メタデータの意味

`source_file`、`source_line` は構文トレースの**文の開始位置**を示します。日本語文型変換は1入力行を1出力行として扱うため、行単位の対応は保持できます。構文式内部の全ての文字位置を追跡するマッピング、ブレークポイントへの元ファイル位置指定、GUIデバッガは**引き続き未実装**です。既存 `ALL_DEBUG` のブレークポイント行指定は前処理後のまま変更していません。
