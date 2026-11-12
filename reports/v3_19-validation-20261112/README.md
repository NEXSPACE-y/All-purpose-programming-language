# v3.19 default API の全回帰（2026-11-12）

**965/965 PASS。ここで検証したのは default API の既存回帰と package 事前検査。PHP 全体の完全互換は NOT_COMPLETE。**

対象 `package/ALL_PHP_v3_12_adapter.ps1` の実行前後 SHA-256：
`113d0c2b967a8726cd9a9dec3f032a725ed9c98ee093c4aedd0a4830737f155b`。

Windows PowerShell **5.1.26100.9818** の新規実プロセスから、実 package の次の検証器を実行した。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File package/ALL_PHP_v3_19_validate.ps1 -CompileCSharp
```

## 実測結果

- 既存 940 件＋runtime namespace 25 件：**965/965 PASS、失敗 0**。
- 実プロセス終了コード **0**、stderr **0 バイト**。
- PASS 行を再集計して **965 行**、FAIL 行 **0**。完了表示だけでケース数を判定していない。
- PowerShell 構文 **100 スクリプト**、SHA マニフェスト **215 ファイル**、C# 補助 **2 件** PASS。
- マニフェスト自体を含む package **216 ファイル**について、実行前後の長さと SHA-256 が一致。
- 検証器実行 **340.860 秒**、プロセス起動・証跡採取を含む経過時間 **346.286 秒**。

この実行中は他の独立した比較プロセスも動いていた。時間はこの実行条件での所要時間である。
C# 補助アセンブリ 2 件の `Location` は空で、対応する DLL 実ファイルは確認されなかった。手動削除は行っていない。

元 940 件の試験器・32 fixture 集合・math fixture の計 **34 tracked paths** は、実行前後とも
基準コミット `9d8171712828a0b57555b8eb1e1ca5c475391244` に対する `git diff --exit-code` が **0**。
既存の定義・期待値を変更していない。

## 証跡

- `v3_19_validate_ps51.stdout.log`／`.stderr.log`：実プロセスの完全な raw 出力。
- `process-exit.json`：親プロセスが観測した実終了コード、PID、起動・終了時刻。
- `validation-process.json`：検証器の所要時間、終了状態、C# 補助、前後同一性。
- `package-hashes-before.json`／`package-hashes-after.json`：全 216 ファイルの長さ・SHA-256。
- `powershell-version.json`、`source-provenance.json`、`old940-git-verification.json`：実行環境と対象の根拠。
- `validation-summary.json`：上記を照合した機械可読の集約。

`ALL_PHP_v3_19_test.ps1` は従来の v3.18→v3.17→v3.16 の既存回帰集合を呼ぶ。
CLI/native/private helper/import alias/cached Run の別試験は、この 965 件へ加算していない。
この担当ではそれらと変更のない単体試験を重複実行していない。別比較の途中結果や再測定結果を、この default API 合格で置き換えない。

この結果は全 CLI／SAPI、全 PHP API、ネイティブ拡張 ABI、Web/Linux、実アプリの動作認定ではない。
公式参照 API inventory の関数件数・profile 数も候補の合格数として使用していない。
C# 補助はコンパイル検査であり、DB／HTTP の一般的な runtime 受入れではない。
インストール済み `C:\Users\rinpa\ALL` は実行していない。
