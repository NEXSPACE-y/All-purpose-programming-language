# PHP v3.18 CLI追加候補

**別置き候補 / NOT_COMPLETE。packageへは適用していない。**

正本はprelude隔離修正後の`package/ALL_PHP_v3_12_adapter.ps1`、SHA-256
`244b5c1385a5c5c298d9e6ea43d7b28ba65b4b4b7b131577cf45729a62de7f39`。
`base-adapter.snapshot.ps1`、`provenance.json`、`cli-context.patch`に出所と差分を残した。

レビュー後の候補SHA-256：
`6cfde5e729ff594741b6bb3a254a5bcbd25c2a1ef62f2ad4c9f2b9642b1efb8a`。
`cli-context.patch`は正本に対する通常の`git apply --check`を通した。適用はroot担当のレビュー・回帰確認後に行う。

## 追加した入口

`Run`へ任意の`-CliContext [System.Collections.IDictionary]`を追加。

| フィールド | 内容 |
|---|---|
| SourcePath | 実際のソースパス。診断・Throwableへ保持 |
| ExitCode | 実処理による終了値。Windowsのuint32ビット列をlongで保持 |
| Terminated | exit/未捕捉PHP例外/対応済みコンパイルエラーによる終了 |
| TerminationReason | exit / uncaught_php_throwable / compile_error |
| CompileError | 対応済み構文異常の型・tokenkind/content・行・パス。呼出しごとに消去 |

新しい`tools/differential/PhpCliCandidateWorker.ps1`はこのcontextを使い、実際の終了ビット列を`Environment.Exit`へ渡す。オラクル出力の参照、診断の置換、空白・改行の正規化はしない。既存の`PhpCandidateWorker.ps1`は変更していない。

CliContextがある場合は、既存の警告と未捕捉PHP例外を実stderrへ先頭空行なしで出し、実際のSourcePathを使用。未捕捉例外は255で終了する。対応した構文異常は「セミコロンを期待した位置の引用文字列」で、parserがtoken種・内容・行を記録し、engineが診断と255を出す。その他のparser/host異常をPHPの参照文面へ偽装しない。

exit/dieは整数・文字列・引数なしと、今回のオラクルで確認した弱い型変換に対応。PHPから作れないhost制御signalを使い、PHP catch/finallyを実行せず終了する。PowerShell側のfinallyによるscope/stack等の後始末は動く。例外ハンドラ内のexitも専用境界で受け、contextの実終了値を保持する。

isset/emptyのarray offsetについては、containerの静かな検索とkey式の通常評価を分けた。欠けたbaseでもkeyの副作用・診断・例外・exitを実行し、nested keyを順に評価する。nullsafe chainは後続keyを省略。全式をQuietDepthで抑制する方式へはしていない。

公開function_existsは内部Throwable整形helperを組込関数として公開せず、同名のユーザー定義は認識する。**helper自体のpublic dispatchと同名定義によるprelude乗っ取りは既存問題として残る。** private opcode化などの広い修正は行っていない。

## 実行結果

最終SHA`6cfde5...`での実測：

| 試験 | 結果 | 証拠 |
|---|---:|---|
| 指定CLI14例のstdout/stderrバイト列・実終了値 | 14/14 PASS | `reports/php-cli-candidate-20261112/cli14-reviewed/report.json` |
| 追加exit型変換・nested unwind等（元23入力を維持） | 23/23 PASS | `exit23-reviewed/report.json` |
| 元の21診断・27名前空間・25実行時名前空間fixture | 73/73 PASS | `default73-reviewed.json` |
| Generic Dictionaryでexit→compile error→context再使用 | 3/3 PASS | `context3-reviewed.json` |
| 内部helper非公開・同名ユーザー定義の可視性 | 2/2 PASS | `builtin-visibility-reviewed/report.json`内の最初の2例 |
| 同名helperによるprelude乗っ取りの既知問題 | DIFFERENTのまま | 同reportの3例目。全体は2/3 PASS |

すべての最終14/23例で入力hashの前後一致を確認。73件のfixtureも元のJSONと期待値を変更していない。**全965件をこの候補で再実行した結果ではない**。root側の統合回帰が必要。

直前SHA`cd4c47...`（最終版との差はfunction_existsの公開helper除外と引数文字列化1回への整理）で、offset順序/診断/例外/nullsafe14例も14/14 PASS。`isset-offsets-fixed/report.json`に記録。同SHAの`handler-fixed/report.json`ではhandler内exit(7)はPASS、handlerからの再送出は実終了255/stdoutが一致する一方、closure/internal stack-frame表現が異なるため全体1/2 PASS。未一致をPASSへ読み替えていない。

修正前23例の22/23 PASSと、undefined baseがoffset内exitを省略した失敗も`exit-extended-initial/`へ保存してある。

## 再現

```powershell
python tools/candidates/php-v3_18/Build-CliCandidate.py
python tools/candidates/php-v3_18/Compare-Cli.py --output reports/php-cli-new-14
python tools/candidates/php-v3_18/Compare-Cli.py --cases tools/candidates/php-v3_18/exit-extended.cases.json --output reports/php-cli-new-23
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/candidates/php-v3_18/Check-DefaultContracts.ps1 -ReportPath C:\actual\new-report.json
```

generatorは正本hashが違えば停止し、別の基準へ黙って作り直さない。比較器は既存reportを上書きせず、別の出力ディレクトリを要求する。公式PHPは照合側だけで実行し、候補は独立したALL処理系を動かす。

## 未完了

全CLIフラグ/argv/stdin/INI/終了ライフサイクル、その他の構文・コンパイル診断、strict_types、バイナリ文字列・文字列offset、ArrayAccess/全magic-property quiet-read、正確なclosure/internal stack frame、shutdown/destructor/output buffering、内部helperのprivate bindingは未完了。Web/native ABI、PHP全体完全互換、ALL Stage2の達成を示す候補ではない。
