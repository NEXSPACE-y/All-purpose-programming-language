# 実package v3.19 private Throwable 14例

実package絶対パス：`C:\Users\rinpa\ALL-php-compat-20261112\package\ALL_PHP_v3_12_adapter.ps1`。SHA-256：`113d0c2b967a8726cd9a9dec3f032a725ed9c98ee093c4aedd0a4830737f155b`。

元の`tools/candidates/php-private-throwable/private-throwable.cases.json`の14入力を変更せず、公式PHP8.5.12と実packageを`PhpCliCandidateWorker.ps1`で実行した。候補コピーを代わりに使っていない。両側に同じPHP source fileを渡し、stdout/stderrの生バイト列と実process終了値を正規化なしで比較した。

**結果：12/14 PASS、2 DIFFERENT。入力hash前後不変。PHP完全互換はNOT_COMPLETE。**

helperによるreturn/throw乗っ取り、通常Exception/Error、ユーザー同名関数、公開visibility、direct/first-class不在、string cast、subclass override、previous chainは一致した。

残る差分は既知の汎用dynamic未定義関数のError分類。公式PHPではcatch可能なErrorを捕捉して終了0、実packageではhostの`ALL PHP: Undefined function`で終了1になる。内部formatterの公開を成功扱いにしたり、この差分をPASSへ変換したりしていない。

| 入力ID | 公式PHP終了 | 実package終了 |
|---|---:|---:|
| `private-throwable.dynamic-absent` | 0 | 1 |
| `private-throwable.unrelated-dynamic-absent-control` | 0 | 1 |

`report.json`に全入力・command・raw output base64・終了値・hash、`summary.json`に差分一覧、`case-*.php`に実際のsourceを保存した。実packageとworkerのsnapshotも保存。既存候補・既存報告・既存fixture・packageはこの測定で編集していない。
