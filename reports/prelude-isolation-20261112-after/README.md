# Prelude キャッシュ隔離の修正後検証

2026-11-12。対象 adapter SHA-256：`244b5c1385a5c5c298d9e6ea43d7b28ba65b4b4b7b131577cf45729a62de7f39`。

`tools/differential/Test-PreludeIsolation.ps1` を **Windows PowerShell 5.1.26100.9818 の別々の新規プロセス**で実行した。
各プロセスでは同じ `adapter.Run` に seed、second の順で入力し、内部キャッシュは消去・書換えしていない。

seed は `X+X;` を 150 回並べた binary 形式。parity 0 と 1 の両方を確認した。

| parity | 修正前 | 修正後 seed | 修正後 second | 修正後 process exit |
|---|---|---|---|---:|
| 0 | PASS / `clean` | 空出力・エラーなし | `clean`・エラーなし | 0 |
| 1 | FAIL / `__all_throwable_string()` 未定義 | 空出力・エラーなし | `clean`・エラーなし | 0 |

各 parity の seed と second は、`reports/prelude-isolation-20261112-before/` の同じ binary ケースと **SHA-256 が一致**する。
入力を置き換えず、既知の修正前失敗が修正後に成功することを確認した。
adapter の実行前後 SHA-256 も各プロセスで一致した。

公式 PHP での入力確認は、修正前フォルダーの `oracle-comparison.json` に保存された同一ソースの実測を参照する。
今回はそのソースハッシュ一致を確認し、公式 PHP の同一入力試験は繰り返していない。

`processes.json` に PID・実終了コード・時刻、`before-after-comparison.json` に入力ハッシュ一致と結果比較を保存した。
各 `binary-parity-*` に入力・adapter スナップショット・完全な観測・報告 JSON がある。
親フォルダーにはプロセス stdout/stderr も保存した。

```powershell
powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File tools/differential/Test-PreludeIsolation.ps1 -AdapterPath package/ALL_PHP_v3_12_adapter.ps1 -Parity 1 -SeedShape binary -OutputDirectory reports/prelude-isolation-new/binary-parity-1
```

この結果は対象のクロス Run 隔離不具合を検証するもので、PHP 全体の完全互換を認定するものではない。
