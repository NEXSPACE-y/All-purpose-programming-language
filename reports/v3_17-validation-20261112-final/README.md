# v3.17 最終回帰検証（2026-11-12）

**回帰検証 PASS。PHP 全体の完全互換は NOT_COMPLETE。**

対象 adapter SHA-256：`244b5c1385a5c5c298d9e6ea43d7b28ba65b4b4b7b131577cf45729a62de7f39`。
基準 HEAD は `9d8171712828a0b57555b8eb1e1ca5c475391244`。対象はそこからの変更を含む記録済みハッシュのソース。

## Windows PowerShell 5.1 実行

Windows PowerShell **5.1.26100.9818** の新規プロセスで `package/ALL_PHP_v3_17_validate.ps1 -CompileCSharp` を実行。

- **965/965 PASS、失敗 0、プロセス終了コード 0**。
- 内訳：既存 v3.16 回帰 **940/940**、新 namespace 回帰 **25/25**。
- 事前検査：構文 **96 スクリプト**、SHA-256 **209 対象ファイル**、C# 補助 **2 件** PASS。
- 検証器の実行時間 **205.436 秒**、プロセス起動と証跡採取を含む経過時間 **213.561 秒**。
- マニフェスト自体を含む `package/` **210 ファイル**の実行前後 SHA-256 と長さが一致。
- プロセス stderr は **0 バイト**。C# 補助アセンブリ 2 件の `Location` は空で、実ファイルは確認されなかった。手動の削除処理は実施していない。

ログの PASS 行は実際に **965 行**、FAIL 行 0。最後の完了表示だけで合格数を判定していない。
実行前後の全 package ハッシュ、PowerShell バージョン、標準出力・標準エラー、プロセス終了記録を同じフォルダーに保存した。

旧 940 件の試験器、32 の fixture 集合、math fixture の計 **34 tracked paths** は、実行前後とも基準コミットに対する `git diff --exit-code` が **0**。
既存の定義・期待値を変更していない。パス一覧と実際の diff 終了コードは `old940-git-verification.json` と `validation-summary.json` に保存した。

## 公式 PHP との厳密比較

同じソースを公式 PHP 8.5.12 と候補の独立プロセスへ与え、stdout バイト列・stderr バイト列・実プロセス終了コードを正規化せず比較した。
1 ケース 30 秒の条件を維持し、入力ファイル・オラクル・adapter・worker の実行前後ハッシュも一致した。

- 元の固定 14 ケース：**6/14 完全一致、8 差分**、評価器終了コード **1**。
  `reports/strict-differential-20261112-v3_17-final/report.json`。
- 新 namespace 25 ケース：**25/25 完全一致**、評価器終了コード **0**。
  `strict25/report.json`。

新 25 件の ID は元 fixture の `name` そのもの。`code` のみを取り出し、fixture の期待出力を strict 評価器へ渡していない。
元 fixture の SHA-256、元 14 ケースの SHA-256、各ツールの SHA-256 は `source-provenance.json` に保存した。

元 14 ケースの残る差分は、alias 重複、未定義変数診断、未捕捉例外診断・終了コード、exit、generator、heredoc、Unicode エスケープ、attribute/Reflection。
これらの 14 件は限定された診断サンプルであり、PHP 全機能の分母ではない。

## Prelude の別 Run への隔離

`reports/prelude-isolation-20261112-after/` に、fresh PS5.1 process の binary seed parity 0・1 の結果を保存。
各プロセス内では同じ `adapter.Run` に seed、second の順で入力し、内部キャッシュは消去しなかった。
両 parity で seed は空出力・エラーなし、second は `clean`・エラーなし、終了コード **0**。
修正前に失敗した parity 1 も成功へ変わり、修正前後の seed と second の SHA-256 は一致する。

## 過去の失敗記録と検証範囲

初回 v3.17 統合検証は、940 件成功後に新試験器の PS5.1 配列読込で失敗した。
その完全な記録は `reports/v3_17-validation-20261112/` に保持し、今回の結果で上書きしていない。
今回の最終ソースは、配列読込修正と prelude metadata 隔離修正を含む別ハッシュで検証した。

strict comparator 7/7 と completion gate 7/7 の単体試験は、変更のないコードに対する既存記録を保持し、繰り返していない。

965 件の回帰成功は PHP 完全互換を認定するものではない。全 PHPT の再実行、拡張 ABI、Web SAPI、実アプリの検証は今回行っていない。
インストール済み `C:\Users\rinpa\ALL` も実行していない。

機械可読の集約は `validation-summary.json`。
