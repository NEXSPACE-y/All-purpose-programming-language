# 関数登録認識の観測

2026-11-12。**登録認識のみ／PHP完全互換はNOT_COMPLETE**。

公式API存在台帳`reports/php-api-inventory-20261112/run-01/profiles/base/stdout.json`の実際のinternal関数登録名925件（aliasを含む）を、変更せず全件使用した。各名前について同一の有効なPHPソースを公式PHP8.5.12と実際のpackage処理系へ与え、`function_exists(name)`の返すboolを観測した。照会名を使って対象関数を動的に呼び出す試験は行っていない。PHP側で呼んだ関数は照会用のfunction_existsだけで、ほかはecho文による出力である。function_exists自身は照会primitiveとして実行される。

## 実測件数

- 参照base登録名：925件。公式PHPは全925件でtrue。
- 候補の応答：trueが80件、falseが845件。
- 追加2件は両処理系でfalse。
- 全927件の両側boolを取得し、未観測0件。10プロセス組、最大ソース7114文字、すべて100,000文字未満。
- 両側とも全プロセスが終了0、stderrは空。10組すべてstdoutのbool値に差があり、その他の厳密比較差分はない。
- inventory・ソース処理系・worker・参照PHP・ツールの実行前後hashは一致した。

**80は候補が登録済みと答えた件数**。80関数の実装完了・正しい呼出し規約・副作用・診断・互換率を認定する数字ではない。845 falseも各関数本体の有無を直接実行して判定した数字ではなく、参照の登録認識と食い違った観測である。名前の存在と本文意味論の検証を分ける。

## 追加観測

| 名前 | 公式PHP | 候補 |
|---|---|---|
| `__all_throwable_string` | false | false |
| `__all_unregistered_probe_33b822d0ad53ccacc1c0ee93acbfb2c9` | false | false |

このプログラムではユーザー関数を宣言していない。内部helperのprivate bindingや同名ユーザー定義との衝突は別問題で、このfalse観測だけで解決済みとは扱わない。

## extension分類別の登録応答

分類は参照inventoryのextensionフィールドをそのまま使った。実装・拡張ロード・API全面対応の合格表ではない。

| 参照extension分類 | 参照登録名 | 候補true | 候補false |
|---|---:|---:|---:|
| `Core` | 62 | 14 | 48 |
| `PDO` | 1 | 0 | 1 |
| `SPL` | 15 | 0 | 15 |
| `SimpleXML` | 3 | 0 | 3 |
| `Zend OPcache` | 8 | 0 | 8 |
| `bcmath` | 14 | 0 | 14 |
| `calendar` | 18 | 0 | 18 |
| `ctype` | 11 | 0 | 11 |
| `date` | 48 | 0 | 48 |
| `dom` | 2 | 0 | 2 |
| `filter` | 7 | 0 | 7 |
| `hash` | 20 | 0 | 20 |
| `iconv` | 10 | 0 | 10 |
| `json` | 5 | 4 | 1 |
| `libxml` | 8 | 0 | 8 |
| `pcre` | 11 | 0 | 11 |
| `random` | 9 | 0 | 9 |
| `readline` | 8 | 0 | 8 |
| `session` | 23 | 0 | 23 |
| `standard` | 546 | 62 | 484 |
| `tokenizer` | 2 | 0 | 2 |
| `xml` | 22 | 0 | 22 |
| `xmlwriter` | 42 | 0 | 42 |
| `zlib` | 30 | 0 | 30 |

## 証拠

- 全対応表：`observations.jsonl`（名前・元base64・参照分類・両側bool・chunk/ソースhash）。`names.json`に全入力名。
- 全体：`report.json`。各`chunk-*/probe.php`は実際に両側へ与えた同一入力。`processes.json`とstdout/stderrバイト列も保存。
- 再現引数：`reproduce.json`。固定したrandom literalも記録。再実行は別の出力ディレクトリを指定する。
- 被験：`package/ALL_PHP_v3_12_adapter.ps1`、SHA-256 `6cfde5e729ff594741b6bb3a254a5bcbd25c2a1ef62f2ad4c9f2b9642b1efb8a`。
- 参照PHP：同じ台帳で固定されたWindows x64/ZTS PHP8.5.12、SHA-256 `0ac893499799256db6d3a54b0da73692e02311493922e6e4f86a062674a77d66`。`-n -d display_errors=stderr -d error_reporting=-1 -d date.timezone=UTC`。
- worker：`tools/differential/PhpCliCandidateWorker.ps1`。実際のCliContext経路。正規化・出力置換なし。

生の出力は`000000:0\n`／`000000:1\n`の形式・順序・全バイトを検査した。CRLFへの変換や前後空白の削除はしていない。入力名を落とさず、1プロセス100観測の上限と文字数上限で分割した。

## 限界

対象は公式baseprofileだけ。追加ネイティブ拡張を事前ロードした候補profile、Linux、Web SAPI、本文の実行結果・型・引数・例外・副作用は未検証。既存API存在台帳・fixture・期待値・package・処理系コードは変更していない。
