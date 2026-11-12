# v3.17 初回統合検証（2026-11-12）

**状態：NOT_COMPLETE。965 件の全合格ではない。**

対象 adapter SHA-256：`f9a5efbbb7ead6b3b8a81aef9a8f21138d647ffe0b3154955f3db46c6043ae36`。
既存 HEAD は `9d8171712828a0b57555b8eb1e1ca5c475391244`。この報告は検証時の変更済み adapter を対象とする。

## Windows PowerShell 5.1 統合検証

`package/ALL_PHP_v3_17_validate.ps1 -CompileCSharp` を隔離作業ツリーから実行した。
構文 96 本、SHA マニフェスト 209 ファイル、C# 補助 2 件は PASS。
**既存 v3.16 回帰は 940/940 PASS**。

その後、新しい namespace 試験器の `Expected 25 runtime namespace oracle cases` で停止し、プロセス終了コードは **1**。
新 25 件はこの試験器では開始していない。検証器実行時間は **208.622 秒**、プロセス全体は **217.108 秒**。
原因は Windows PowerShell 5.1 の `ConvertFrom-Json` 出力を `@()` で包んだ際の 1 要素ネスト配列で、件数判定が 25 にならなかったこと。
既存 v3.16 試験器にはこの配列を平坦化する処理があり、新試験器にはなかった。

`package/` 全ファイルの実行前後 SHA-256 は一致し、検証中の package 変更はなかった。
完全な標準出力・標準エラー・プロセス終了コード・検証プロセス記録・前後ハッシュを同じフォルダーに保存した。

## 厳密なプロセス比較

公式 PHP 8.5.12 と候補を独立プロセスで実行し、stdout バイト列、stderr バイト列、実終了コードを正規化せず比較した。
既存条件の 1 ケース 30 秒を維持した。各報告の入力前後ハッシュは一致している。

- 元の固定 14 ケース：**6/14 一致、8 差分、評価器終了コード 1**。
  `reports/strict-differential-20261112-v3_17/report.json` に全実測を保存。
- 新 namespace 25 ケース：**25/25 一致、評価器終了コード 0**。
  このフォルダーの `strict25/report.json` に全実測を保存。

新 25 件は `package/PHP_v3_17_namespace_runtime_oracle_cases.json` の `name` をそのまま ID、`code` をそのまま入力として取り出した。
既存の期待出力は評価器へ渡していない。対応と元ファイルのハッシュは `source-provenance.json` に保存した。
元 14 ケースの定義は変更していない。

元 14 ケースの残る差分は、alias 重複、未定義変数診断、未捕捉例外診断・終了コード、exit、generator、heredoc、Unicode エスケープ、attribute/Reflection。
列挙したサンプルだけの測定で、機能全体の網羅性や PHP 完全互換を示すものではない。

## 検証器自身の単体試験

- strict comparator：**7/7 PASS、終了コード 0**。
- completion gate：実行時の現行テストは **7 件**。**7/7 PASS、終了コード 0**。

各 1 回だけ実行し、ログと終了コードを保存した。

## 再検証が必要な事項

root には namespace 試験器の配列読込不具合を報告した。
また、prelude 解析中に source 用 `NamespaceFallbacks` を切り離していない問題を root が発見しており、修正後に別の保存先で再検証する予定である。
この報告の旧ハッシュの結果を、以後の修正を含む最終ソースの検証済み結果として扱わない。

機械可読の要約は `validation-summary.json`。
