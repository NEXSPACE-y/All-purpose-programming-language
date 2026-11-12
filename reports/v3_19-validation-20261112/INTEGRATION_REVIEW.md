# PHP v3.19 統合チェックポイント

**PHP完全互換は未完了。第2段階のALL自身のPHP完全対応も未完了・実装未着手。**

実packageのアダプタSHA-256は `113d0c2b967a8726cd9a9dec3f032a725ed9c98ee093c4aedd0a4830737f155b`。
v3.18へ、ALL所有native ABIとの任意接続、内部Throwable整形の専用AST束縛、import alias重複拒否、登録済み公開関数との再宣言衝突拒否を統合した。
各修正の固定hashと重ならない差分の統合記録は [provenance](../../tools/candidates/php-v3_19/provenance.json) にある。

## 実packageの実測

| 集合 | 観測結果 | 記録 |
|---|---|---|
| 既存default API | 965/965 PASS、実exit0 | [全回帰](README.md) |
| CLI・exit | 14/14、23/23完全一致 | [CLI](cli14/report.json)、[exit](exit23/report.json) |
| import重複・合法例・行分割 | 23/23完全一致 | [import](import23/report.json) |
| 登録名衝突と合法定義、opt-out | native9＋builtin2＋positive5＋opt-out3、計19/19一致 | [native9](redeclare-native9/report.json)、[positive5](redeclare-positive5/summary.json) |
| preludeキャッシュ分離 | 10/10一致（実package8 Run＋旧版warmup2） | [cache](cached-runs/summary.json) |
| 内部Throwableの公開・乗っ取り等 | 12/14一致。未定義dynamic関数の既知Error分類差が2例残存 | [private](private14/summary.json) |
| 実PHP評価器から未改変native DLLを呼出し | 全再測定で23/23完全一致。未対応4経路はnative呼出し前拒否 | [native再測定](native27-repeat/report.json) |

stdout/stderrの生バイト列と実プロセス終了値を比較し、診断・改行・空白・終了値を置換していない。
cache試験だけは同一プロセス内の捕捉出力とcontext状態の比較で、独立した候補プロセスの終了値とは呼ばない。
各集合は重なるため、合計して互換率や網羅件数にしない。拒否4経路は互換PASSではない。

全回帰の事前検査は構文100本、SHA215件、C#2件PASS。package216ファイルの前後ハッシュ一致を確認し、
strict比較の終了後にも全216ファイルが同じことを再確認した。既存940件の34tracked pathsは元の`9d817171`から変更していない。

## 保存した失敗と再測定

最初のnative27測定は23比較中22一致、`native.catch_count_error`が30秒の終了待ちでTIMEOUT。
出力が一致し、worker metadataの終了値が0でも、実プロセスの終了証拠にならないため合格としない。
同じcaseの個別再測定は1/1一致、続く全再測定は23/23一致＋拒否4/4。
最初の失敗を[元report](native27/report.json)に保持した。[独立レビュー](native-timeout-review.md)のとおり原因は未特定。
同じ30秒制限は実行引数の記録に基づき、旧report JSONだけで独立確認したとは扱わない。
full965終了後に再実行したが、並列負荷を固定した性能比較ではない。

比較ツールは今後のreportへdriver自身のhash・実argv・作業ディレクトリ・timeoutを保存するよう改善した。
旧reportへ遡及追加せず、当時のdriverを [snapshot](legacy-comparison-drivers/snapshot.json) に保存した。
新記録は同じ実packageのCLI/native各1例で実終了0・一致を確認し、`metadata-cli-one/`と`metadata-native-one/`に別置きした。

## 境界と残件

nativeの検証はWindows x64 TS、固定したALL所有DLLと元の`php_dl_test.dll`を事前ロードしたweak positional scalar profile。
全extension loader、全ABI、binary strings、同期callback、refs/arrays/objects/resources共有、lifecycle出力の完成を示さない。
別置きの同期callback prototypeは本packageに含めていない。

言語コア・標準ライブラリに未実装/不一致があり、Web各SAPIとLinuxは未検証。Linux環境の導入・指定は回答待ち。
13,934件の公式参照API台帳は未検証の候補要件で、実装済み件数ではない。
stage1完了やstage2着手を認定する結果ではない。

導入済み`C:\Users\rinpa\ALL`は45ファイルの一覧・長さ・SHAが初回と一致した。[保存確認](installed-runtime-preservation.json)。
元checkoutは`work/php-core-compat` / `9d817171`のclean状態を維持し、mainへのmerge・pushはしていない。
機械可読の集約は [checkpoint-summary.json](checkpoint-summary.json)。
