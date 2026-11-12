# Native PHP 統合候補の独立レビュー

対象は凍結 native 候補 `47c8edb9e39bffe3ed5475f2aeed7e36673a798d2f72baf0cb60abc39695322d`、`Invoke-NativePhpWorker.ps1`、`AllNativeBridge.cs` と既存実測。
package と凍結候補は変更せず、元 965 件も再実行していない。

**実不具合：登録済み native 関数を global user 関数で再宣言できる。**
`functiondef` は user 辞書だけを重複検査し、native 登録を検査しない。
再現 9 例で **4 一致・5 不一致**。不一致はトップ宣言、大小文字差、条件 true、実行された nested 宣言、catch/finally 内の宣言。
公式 PHP は Fatal と終了 255、旧候補は user 宣言を受け入れて終了 0。
namespace 内の同 basename、条件 false、未実行 nested、同名 method は正しく動作した。
同型の public builtin `strlen` 衝突も native なしで **0/2 一致**となり、実測で確認した同型欠陥として同じ最小修正の対象へ含めた。
元の生 stdout/stderr/exit と入力 hash は `redeclare-before/report.json`、`known-builtin-before/report.json` に保持する。

## 指定した 6 観点

- **重複呼出し・失敗後 fallback**：adapter の native invocation は一か所。C# も実呼出しは一回で、失敗を別 runtime へ再試行する経路なし。
  既存 `initial27` の通常 23 例は 23/23 同一 source 完全一致。native API の型・引数数エラーも invocation 1 回で、PHP Throwable へ伝播した。
- **unsupported の副作用前拒否**：handler、named arg、populated array、参照返却の 4 例は、該当 native 呼出し **0 回**で拒否。
  scalar 型と UTF-8 入力の可否は C# の実 `Call` 前に検査する。引数式自体の通常評価より前の全 source preflight を保証する仕組みではない。
- **NativeContext 省略**：null 時の native lookup は false。host 契約証跡で、非拡張の公式 PHP と opt-out が一致。
  NativeContext parameter 自体がない adapter は AST 検査で source／module 実行前に拒否した。
- **対象範囲**：未改変 `php_dl_test.dll`、valid UTF-8/NUL を含む scalar・弱い positional 呼出しの選定範囲。
  他 DLL、全 native ABI、named args、callbacks、refs、object/resource、populated array、Linux/Web の成功とはされていない。
- **stdio／exit**：比較器は oracle と candidate に同じ PHP source path を渡し、stdout/stderr の生バイト列と実終了値を比較。
  対応させるための空白・改行・診断・終了値の置換や正規化はない。guard 拒否は互換 PASS とは別集計。
- **finally／module identity／hash**：既存 27 worker は全件で MINIT/MSHUTDOWN と RINIT/RSHUTDOWN が各 1、入力前後 hash 一致。
  選定した自前 core が唯一の `php8ts.dll` である記録と、core hash／path 検査を確認。

機械可読の元証跡集計は `original-review.json`。

## 残るリスク

成功・guard・通常の native Error の cleanup は実測されているが、RINIT/RSHUTDOWN 自体が失敗する経路は未注入。
worker は `Start` 成功後だけ started を立て、`End` 失敗時は再度 `End` を試し得る。そこでも失敗すると `Shutdown` へ進まないため、他 module へ広げる前に失敗経路の契約確認が必要。
module 一覧は source 実行前の snapshot で、実行後の追加 snapshot ではない。
native 出力／戻り値が不正 UTF-8 の場合は実呼出し後に unsupported となり、retry はしないが現 managed-string 経路で全 byte を扱えるわけではない。

実証した衝突修正は、別の `tools/candidates/php-native-redeclare/` に最小差分として作成。
private helper・import alias・package への統合は root が扱う。
