# Private Throwable formatter binding candidate

**独立候補 / NOT_COMPLETE。元package・native候補は変更していない。**

- 基準：`tools/candidates/php-native/ALL_PHP_native_candidate.ps1`
- 基準SHA-256：`47c8edb9e39bffe3ed5475f2aeed7e36673a798d2f72baf0cb60abc39695322d`
- 候補：`ALL_PHP_private_throwable_candidate.ps1`
- 候補SHA-256：`2527caddc86273163981883d996a8969f3190a0bc86edda180b05605c9dfd78b`

`Build-PrivateThrowable.py`、`provenance.json`、`base-adapter.snapshot.ps1`、`private-throwable.patch`に再現元と最小差分を保存した。生成scriptはレビュー済み47c/6cf以外の基準hashでは停止する。patchはpackage6cfに対する通常の`git apply --check`を通した。生成scriptを再実行するとこの候補を再生成するため、検証中・採用後の無断再生成は行わない。

## 修正

prelude解析中だけ`__all_throwable_string($this)`を専用`internal_throwable_string` AST nodeへ束縛し、評価器から`Get-PhpThrowableString`を直接呼ぶ。ユーザーソースの同じ綴りは通常の関数呼出しとして解析する。

内部helperを公開builtin registryと公開dispatchから除いた。同名のユーザー関数は合法で、通常呼出し・dynamic call・function_existsは実際のユーザー定義を扱う。内部formatterがそのユーザー定義へ置き換わる経路を除いた。

`ParsingInternalPrelude`をRunごとにfalseで初期化。prelude解析時は元のflag・tokens・lines・position・namespace fallbackを保存し、専用解析コンテキストにした後finallyで復元する。cache keyを`ALLPhpPreludeAstPrivateThrowableV1`へ分け、旧public-call ASTの再利用を避ける。キャッシュをテスト側から消す方式は使っていない。

## 実測

証拠は`reports/php-private-throwable-20261112/`。

| 検証 | 結果 |
|---|---:|
| 同じPHPソースを使うhijack/公開性/通常Throwable等の厳密process比較 | 12/14 PASS |
| 同じPS5.1 process内のcache隔離（2 warmup＋8候補Run） | 10/10一致 |
| 変更していない既存fixtureのdefault/PhpDiagnostics部分集合 | 73/73 PASS |
| native補助回帰（native担当が同じ候補2527で測定） | 23/23 exact PASS |
| native未対応を実行前に拒否するguard | 4/4、互換PASSとは別集計 |

候補14例のsource・stdout/stderr bytes・実終了値は`private14-initial/report.json`、基準側の3 controlは`base-before-controls/report.json`へ保存。基準ではユーザー定義による`hijacked`出力を実際に観測し、候補では公式PHPと同じ通常のException文字列になった。

候補14例の残る2差分は、未定義のdynamic関数呼出しがPHPのcatch可能なErrorへ分類されず、host側の`ALL PHP: Undefined function`になる問題。無関係の未定義関数controlも基準で同じ差がある。内部formatterのdynamic-call公開は除いたが、汎用dynamic-error分類の修正へ範囲を広げていない。これらをPASSへ読み替えていない。

cache検証は`cached-runs-initial/report.json`。parityごとに別の新規PS5.1 processを使い、その中で旧native47 adapterのcacheを通常入力で暖めてから、候補のnamespace付きcold Run、同名user関数によるhijack入力、通常user呼出し、次のclean Runを順に実行した。全て同じPHP入力の独立した公式PHP processと比較し、内部cacheのreset/injectionは行っていない。観測したConsole文字列をUTF-8化して比較し、Run contextのstatusと候補process終了値は区別している。

native補助証拠：`reports/native-callback-20261112/private-regression/report.json`。既存fixture/期待値、runtime/worker/bridgeのhash不変。個別guardの成功をPHP互換成功に含めていない。

## 残件と統合境界

汎用dynamic未定義関数のError分類、既知のclosure/internal stack-frame表現、全PHP/SAPI/native ABIは未完了。解析器の強制fault injectionを行った結果ではなく、flag/fallbackのfinally復元はコード照合と通常のcold/cached Runで確認した。

全965件はこの単独候補では再実行していない。rootのredeclare/import修正との統合版は別のsource/hashであり、この候補の結果を統合版の実測へ転記しない。実packageの再検証は、絶対パス・新しい報告先で別途行う。
