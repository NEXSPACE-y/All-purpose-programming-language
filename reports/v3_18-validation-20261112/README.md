# v3.18 package 統合後の実行検証（2026-11-12）

**既存回帰と指定 CLI 例は PASS。PHP 全体・CLI 全体の完全互換は NOT_COMPLETE。**

実際に実行した `package/ALL_PHP_v3_12_adapter.ps1` の SHA-256：
`6cfde5e729ff594741b6bb3a254a5bcbd25c2a1ef62f2ad4c9f2b9642b1efb8a`。
レビュー済み別置き候補とバイト列のハッシュが一致することを確認したうえで、**実 package のパス**を指定して検証した。

## Default API の全回帰

Windows PowerShell **5.1.26100.9818** の新規プロセスで `package/ALL_PHP_v3_18_validate.ps1 -CompileCSharp` を実行。

- **965/965 PASS、失敗 0、実プロセス終了コード 0**。
- 既存 940 件と、v3.17 runtime namespace 25 件の内訳を維持。
- 構文 **98 スクリプト**、SHA マニフェスト **212 ファイル**、C# コンパイル **2 件** PASS。
- マニフェスト自体を含む package **213 ファイル**の実行前後 SHA-256・長さが一致。
- 検証器 **374.978 秒**、起動・証跡採取を含むプロセス全体 **388.125 秒**。
- stderr **0 バイト**。PASS 行を再集計して **965 行**、FAIL 行 **0** を確認。

全回帰と 2 集合の CLI 比較は別プロセスで並行実行した。記載時間はこの実行条件での所要時間。

元 940 件の試験器・32 fixture 集合・math fixture の計 **34 tracked paths** は、実行前後とも
基準コミット `9d8171712828a0b57555b8eb1e1ca5c475391244` への `git diff --exit-code` が **0**。
既存定義・期待値は変更していない。

完全な stdout/stderr、実終了コード、PowerShell バージョン、前後 package ハッシュを保存した。
C# 補助アセンブリ 2 件の `Location` は空で、実ファイルは確認されなかった。手動削除処理は行っていない。

## 実 package の CliContext 入口

`tools/candidates/php-v3_18/Compare-Cli.py` の既定の別置き候補を使わず、
`--adapter package/ALL_PHP_v3_12_adapter.ps1` を明示した。
全 37 件の候補コマンドが実 package の絶対パス、`PhpCliCandidateWorker.ps1`、実際の source file を指定し、
オラクルと同じ source file を使っていることを記録から再確認した。

この worker は `Run -CliContext` へ `SourcePath` を渡し、engine が context に保持した終了値を実プロセス終了へ渡す。
stdout/stderr のバイト列と実終了コードを公式 PHP 8.5.12 と比較し、空白・改行・パス・診断・終了コードを正規化していない。
公式 PHP は照合側でだけ実行し、候補の処理を委譲していない。

| ケース集合 | 結果 | 比較器の実終了 | 証跡 |
|---|---:|---:|---|
| `tools/differential/cli-semantics.cases.json` | **14/14 完全一致** | 0 | `cli14/report.json` |
| `tools/candidates/php-v3_18/exit-extended.cases.json` | **23/23 完全一致** | 0 | `exit23/report.json` |

両集合で oracle/adapter/worker/cases 等の実行前後ハッシュが一致した。
1 ケース **30 秒**の既存条件を維持。入力と ID は変更していない。
この CLI 14 例は `cli-semantics.cases.json` の集合であり、以前の `core-smoke.cases.json` の 14 例とは別集合である。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File package/ALL_PHP_v3_18_validate.ps1 -CompileCSharp
python -B tools/candidates/php-v3_18/Compare-Cli.py --adapter package/ALL_PHP_v3_12_adapter.ps1 --cases tools/differential/cli-semantics.cases.json --output reports/NEW-cli14 --timeout 30
python -B tools/candidates/php-v3_18/Compare-Cli.py --adapter package/ALL_PHP_v3_12_adapter.ps1 --cases tools/candidates/php-v3_18/exit-extended.cases.json --output reports/NEW-exit23 --timeout 30
```

既存証跡を上書きせず、新しい保存先を指定する。

## 検証の限界

965 件は default API の既存回帰で、CLI の全仕様試験ではない。
37 件も指定された診断・終了動作の例に限る。全 CLI flags/stdin/argv/INI、全 lifecycle、Web、Linux、
ネイティブ拡張 ABI、実アプリ、PHP 全体の完全互換を証明しない。
既知の未対応事項は `package/README_PHP_V3_18_JA.md` を参照。

変更されていない単体試験は繰り返していない。公式参照 API inventory の profile 数や関数件数を、候補の実装・合格件数へ加算していない。
インストール済み `C:\Users\rinpa\ALL` は実行していない。

機械可読の要約は `validation-summary.json`、コード・worker・入力集合のハッシュは `source-provenance.json`。
