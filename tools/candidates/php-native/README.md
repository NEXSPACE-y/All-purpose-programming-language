# 実PHP評価器とネイティブABIの接続候補

**別置き候補／NOT_COMPLETE。package・導入済みALLへは、この担当作業では適用していない。**

基準はレビュー済みv3.18候補
`tools/candidates/php-v3_18/ALL_PHP_v3_18_candidate.ps1`、SHA-256
`6cfde5e729ff594741b6bb3a254a5bcbd25c2a1ef62f2ad4c9f2b9642b1efb8a`。
生成後のnative候補は`ALL_PHP_native_candidate.ps1`、最終SHA-256
**`47c8edb9e39bffe3ed5475f2aeed7e36673a798d2f72baf0cb60abc39695322d`**。
この版を固定し、以後のprivateThrowable binding修正は別ディレクトリから最小差分を作る。

`Build-NativeCandidate.py`は基準ハッシュが違えば停止する。`provenance.json`と`native-context.patch`に出所と変更点を記録した。元v3.18ファイルは変更していない。

## 変更内容

`Run`に任意の`NativeContext = $null`を追加した。既定値のままならnative機構は呼ばない。

- 動的`HasFunction`により、実登録されたnative関数を名前解決・namespace fallback・first-class/string callable・`function_exists`へ接続する。DL関数名をdispatcherへ列挙しない。
- 既存のPHPユーザー関数と組込処理を優先し、未解決関数の最後の分岐からnative scalar invokerを1回だけ呼ぶ。native呼出し後の別実装への再試行は行わない。
- 正常なscalar戻り値を評価器へ返し、PHP error class/messageを既存`Throw-PhpError`へ渡す。native出力の生バイト列を一度だけstdoutへ反映する。
- `DiagnosticEvents`のlevel/messageを既存`Write-PhpDiagnostic`へ渡す。評価器のsource path/line、`error_reporting`と`@`抑制を使う。harness用のcanonical `Diagnostics`文字列をCLI stderrへ直接転記しない。
- **PHP user error handlerが存在すれば、native呼出しの前にengine unsupportedとして拒否する。** 後から渡す診断イベントでは、native処理の途中に同期実行されるuser callbackの挙動を再現できないため。これをhandler互換とは扱わない。
- named native args、reference return、arrays／object／resource等の未対応値は明示拒否する。native側の副作用が起きた後でfallback再実行しない。

## 実行host

`tools/abi/Invoke-NativePhpWorker.ps1`が、実際のPHPソースをこの評価器で実行する。固定されたALL所有のcore DLLと未改変の拡張DLLをロードし、**1回のRunだけをBridge.Start／Endのtry/finallyで囲む**。その後shutdownし、実際の`CliContext.ExitCode`をプロセス終了値へ反映する。

workerは`Run.Ast.ParamBlock`から`NativeContext`と`CliContext`の宣言を確認する。未宣言のPowerShell引数が黙って無視される経路では実行しない。coreの指定ハッシュも実ロード前に照合する。

このhostは**拡張を事前ロードした実験profile**である。ALL自身に`php -d extension=...`等のCLIフラグを実装したとは主張しない。公式PHPは別の参照プロセスで同じソースを実行する側だけに使用する。

## 実測

証拠は`reports/native-php-integration-20261112/`。

| 検証 | 結果 | 証跡 |
|---|---:|---|
| 同一PHPソースのstdout/stderr生バイト列・実終了値 | **23/23完全一致** | `initial27/report.json` |
| 未対応handler／named args／populated array／reference returnの明示拒否 | **4/4でnative invocations=0** | 同report。互換PASSとは別集計 |
| NativeContext未宣言のAST拒否・既定nullでnativeを公開しない | **2/2確認** | `host-contract2/report.json` |
| 元の21診断・27namespace・25実行時namespace fixture、期待値無改変 | **73/73 PASS** | `default73.json` |

23例には動的function_exists、namespace fallback/use alias/user precedence、first-class/string/qualified-string calls、call_user_func、PHP TypeError/ArgumentCountErrorのcatch、Unicode、NUL入力、int64上下限、引数と出力の1回性、診断source contextと抑制を含む。

NUL例は**有効UTF-8ソースの引用文字列内に実NULバイトを置いたもの**。基準評価器で未対応の`\0`／hex／octal escape構文を実装したことにはしない。文字列値からnativeへはlengthを保って渡し、元拡張のC `%s`処理によるNUL位置での切断も公式PHPと一致した。

すべてのprocess比較で、source/candidate/worker/C# bridge/own DLL/original DLL/frozen base等のハッシュ前後一致を確認した。worker metadataのロード済みPHP coreは自前の`php8ts.dll`だけで、元`php_dl_test.dll`のパスとハッシュも残した。core SHA-256は
`b2ffd9f38abd20894b064b53a94e4a05e5d39eaa2055e910db6d762558e46757`。
元拡張は
`532b9f0944d482a704eb81ac1cb9af3b59aa0f54c753c53a5709c17f57d4e938`。

## 再現

リポジトリrootから実行する。既存reportを上書きせず、新しい出力先を指定する。

```powershell
python .\tools\candidates\php-native\Build-NativeCandidate.py
python .\tools\candidates\php-native\Compare-NativePhp.py --output .\reports\native-php-new-run
python .\tools\candidates\php-native\Check-NativeContextContract.py --output .\reports\native-contract-new-run
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\candidates\php-v3_18\Check-DefaultContracts.ps1 -AdapterPath .\tools\candidates\php-native\ALL_PHP_native_candidate.ps1 -ReportPath C:\actual\new-default73-report.json
```

実DLLがまだビルドされていない場合は、承認済みの`native/php85abi/Build-NativeAbi.ps1`を先に使用し、新しく得たcoreハッシュを比較器に記録する。既存coreや公式DLLへ黙って置き換えない。

## 未確認・未実装

全965件の回帰はこのnative候補で再実行していない。PHP全機能、拡張全機能、全CLI/SAPI、標準ライブラリ全体の認定ではない。frozen v3.18には`strict_types`実装がないため、このsource接続は**weak positional scalar profile**であり、C bridgeのstrict呼出し能力をそのままPHPソースの対応と数えない。

user error handlerの同期native callback、native-to-PHP user function callback、named native args、ref／object／resource／populated arrayの共有、native class property実行、全byte-string意味論、正確なnative/internal stack frameは未完成。無効UTF-8の戻り値をmanaged scalarへ変換する場合も明示unsupportedで、変換後にnativeを再実行しない。

native RINIT/RSHUTDOWN等の出力・診断のhostへの完全な輸送は未検証。今回の`dl_test` RINITは出力しないため、この23例からその一般動作を認定しない。承認済みLinuxと各Web SAPIも未検証。Stage 2のALL言語成長・双方向呼出し・共有データを完了した成果ではない。**PHP_FULL_COMPATIBLE=false**。
