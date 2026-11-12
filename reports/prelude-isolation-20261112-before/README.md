# Preludeキャッシュ隔離の修正前再現

2026-11-12。Windows PowerShell 5.1の独立した新規プロセスで各parityを実行。各プロセス内では同じadapter.Runへseed→secondを与え、内部キャッシュは消去・書換えしていない。

実装SHA-256（全4プロセスの実行前後で不変）：`f9a5efbbb7ead6b3b8a81aef9a8f21138d647ffe0b3154955f3db46c6043ae36`。

## 実測

| seed | parity | seed | second | プロセス終了 |
|---|---:|---|---|---:|
| 指定通りの`X;`×300 | 0 | parserが定数式文を拒否 | `clean` | 1 |
| 指定通りの`X;`×300 | 1 | parserが定数式文を拒否 | `clean` | 1 |
| 追加の`X+X;`×150 | 0 | 出力なし・エラーなし | `clean`・エラーなし | 0 |
| 追加の`X+X;`×150 | 1 | 出力なし・エラーなし | `__all_throwable_string()`未定義で失敗 | 1 |

指定通りのbare定数seedはRead-StatementCoreの1866行で`ALL PHP: Undefined constant in expression statement`となり、preludeを汚染する段階へ到達しない。この結果から「キャッシュ汚染がない」とは判定できない。

追加seedは別名で保存し、元の入力・結果を置き換えていない。`X+X;`×150は600トークン・300個のX参照を持ち、`X;`×300と同じ偶奇のトークン位置へ参照を配置しながら、bare定数式文の拒否を回避する。parityの追加セミコロンは`namespace A;`直後へ置き、PHPのnamespace宣言前の文という別の異常を混ぜない。

失敗する追加parity1ではseed成功後のsecondが`ALL PHP: Uncaught Error: Call to undefined function __all_throwable_string()`を送出し、`clean`を出力しない。スタックはResolve-PhpFunctionNodeName:4898→Throwableの`__toString`へ到達する。prelude解析時に呼出し元のNamespaceFallbacksが残り、キャッシュされるASTへ影響する問題と整合する再現である。

## 成果物と再現

`processes.json`に元入力2件、`binary-processes.json`に追加入力2件のargv/終了コード/PID/hash/失敗内容を記録。各ディレクトリにseed.php、second.php、adapter.snapshot.ps1、report.json、観測stdoutを保存し、親階層にプロセスstdout/stderrのバイト列とhashを残した。空のprocess stderrは例外がなかったことを意味せず、捕捉した候補例外はreport.jsonに入っている。

```powershell
powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File tools/differential/Test-PreludeIsolation.ps1 -AdapterPath package/ALL_PHP_v3_12_adapter.ps1 -Parity 1 -SeedShape binary -OutputDirectory reports/prelude-isolation-new/parity-1
```

`-SeedShape bare`が初回指定通りの既定値。各parityは必ず別の新規PowerShellプロセスで実行する。この修正前入力と将来の修正後結果は異なるディレクトリへ保存する。

公式PHP8.5.12は保存済み8ソースを別プロセスで照合し、seedは空、secondは`clean`、全て終了0・stderr空を確認。`oracle-comparison.json`にargv・実際の出力・ソースhash・公式php.exeの実行前後hashを保存した。候補処理系の実行先へ公式PHPを使っていない。
