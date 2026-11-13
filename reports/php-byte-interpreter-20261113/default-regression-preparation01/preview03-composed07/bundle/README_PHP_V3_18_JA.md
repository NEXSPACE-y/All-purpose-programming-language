# ALL PHP v3.18 — 明示的なCLI実行context

PHP8.5.12 Windows向けの候補。PHP全体・CLI全体・Web・Linuxの完全互換は未達。

`Run -CliContext <IDictionary>` を指定した経路で、SourcePathに基づく警告・未捕捉例外をstderrへ出し、
実処理の終了値をcontextのExitCodeへ保持する。呼出し側はこの値を実プロセス終了へ渡す。
既存のdefault APIとPhpDiagnosticsの入口・期待値を維持する。

この経路のexit/dieは、引数なし・整数・文字列と検証済みの弱い型変換に対応する。
PHPのcatch/finallyを通らない専用制御signalを使い、host側finallyの後始末を維持する。
対応する構文異常はparser自身がtoken種・内容・位置を記録し、対応した診断と255を出す。
未対応の構文/host障害を参照PHPの出力で置き換えない。

isset/emptyのarray offsetでは、containerの静かな検索とkey式の通常評価を分離する。
欠けたbaseでもkeyの副作用・診断・例外・終了を実行し、nullsafe chainは後続keyを省略する。

統合候補の入力SHA-256は `6cfde5e729ff594741b6bb3a254a5bcbd25c2a1ef62f2ad4c9f2b9642b1efb8a`。
統合前の同一バイト列でCLI14/14、追加exit23/23、既存fixture抜粋73/73、context再利用3/3が合格した。
統合後の全965件回帰は `ALL_PHP_v3_18_validate.ps1 -CompileCSharp` で確認し、reportsへ別途記録する。
プロセス経路は `tools/differential/PhpCliCandidateWorker.ps1`、検証候補の出所は
`tools/candidates/php-v3_18/README.md` と `reports/php-cli-candidate-20261112/assessment.json` を参照。

未対応：全CLI引数/stdin/INI、完全な構文・コンパイル診断、strict_types、任意バイト文字列、
全ArrayAccess/文字列offset/魔術プロパティのquiet-read、例外handlerの正確なclosure/internal stack frame、
shutdown/destructor/output buffering、内部Throwable helperのprivate binding。
既知のhelper乗っ取り例の不一致も保存してあり、合格へ読み替えない。
