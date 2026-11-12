# 実PHP評価器＋native ABI接続の測定

2026-11-12。候補SHA-256：`47c8edb9e39bffe3ed5475f2aeed7e36673a798d2f72baf0cb60abc39695322d`。

| 結果 | ファイル |
|---|---|
| 同じPHPソース、stdout/stderr生バイト列・実終了値が23/23一致 | `initial27/report.json` |
| 4未対応経路はnative呼出し0で拒否。参照PHPとの差分も保存し、互換PASSには算入しない | 同reportのguard rows |
| NativeContext未宣言ならsource/moduleを実行せず拒否、nullならnative無効の既定動作 | `host-contract2/report.json` |
| 元の73 fixtureと期待値を変更せず、NativeContext省略で73/73 PASS | `default73.json` |

各caseの`*.native.json`に、ASTで確認した引数宣言、実際のロード済みcore/拡張パス、function catalog、CLI context、native呼出し回数、request/TLSの後始末、前後ハッシュを記録した。公式PHPは別の参照プロセスだけで実行した。

これは、ALL所有のnative componentが**実際のALL PHP評価器から呼ばれた**結果であり、先のC bridge単体試験とは別の測定である。元のCLI source6cf、candidate47c、own core b2ffd、元extension532bの組合せを維持した。packageへの反映はrootのレビューと統合回帰後に行う。

基準・変更範囲・再現コマンド・未実装は[候補README](../../tools/candidates/php-native/README.md)を参照。user error handlerの同期callbackを後付けイベントで偽装せず、該当呼出しを拒否した。native出力は1回だけ反映し、PHPエラーは既存Throwable経路、診断は既存severity/source-context経路へ接続した。

23例は事前ロード済み拡張のweak positional scalar profileだけを対象とする。CLIのextensionフラグ、全native module、完全なbyte-string/identity/callback、全965回帰、Linux、各Web SAPIの成功は示さない。native lifecycle出力輸送も未検証。`PHP_FULL_COMPATIBLE=false`。
