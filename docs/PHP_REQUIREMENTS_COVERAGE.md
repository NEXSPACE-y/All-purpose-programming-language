# PHP 要件・証拠の初回監査

更新日：2026-11-12。**NOT_COMPLETE / exhaustive=false**。
[機械可読表](PHP_REQUIREMENTS_MATRIX.json)は初回棚卸しで、全機能の分母ではない。集約行とleafは重なり、行数・実装行数・テスト合格数を完全互換率へ換算しない。

## 対象と監査境界

所有者が決めたStage1は **PHP8.5.12の完全互換**。言語、CLI、Web、標準拡張、**既存のコンパイル済みネイティブ拡張バイナリ**を含む。OS/CPUはWindows11x64とLinuxx64、Webは内蔵サーバー・CGI/FastCGI・Apacheモジュール・LinuxFPM。案Aの独立ネイティブABI基盤実装と必要な値/呼出し境界変更も承認済み。承認と実行検証は別扱い。
Stage2のALL自身のPHP相当の機能力、PHP/ALL双方向呼出し・データ共有も目標に残し、Stage1の後に扱う。

監査基準：`9d8171712828a0b57555b8eb1e1ca5c475391244`。開発版はv3.16だがファイル名は`package/ALL_PHP_v3_12_adapter.ps1`のまま。
実装SHA-256：`2f462dee734635968d540d1f8bf68fd30e0eebec662081c4ccb409bde57fc934`。行参照はこのコミットのもので、将来の編集後の現在位置ではない。

この監査はソース・テスト定義・既存レポートの読み取りと再集計を行い、**PHP/ALLコード、回帰、PHPTを実行していない**。公式ソーステキストを参照したが、オラクルのバイナリを再ダウンロードしていない。

rootが追加した厳密差分14プローブの結果は5PASS/9DIFFERENTと報告されている。`reports/strict-differential-20261112-initial/report.json`は別証拠で、旧PHPTの観測条件と混ぜない。rootの940/940回帰結果や今後のv3.17改修も、基準を書き換えず別の証拠として追記する。

## 状態の扱い

| 状態 | 管理行数 |
|---|---:|
| `NOT_IMPLEMENTED` | 98 |
| `IMPLEMENTED_UNVERIFIED` | 58 |
| `VERIFIED` | 0 |
| `BLOCKED` | 2 |

これは管理行数で進捗率ではない。`aggregate`は未分解の領域、`leaf`は具体化した義務、`control`は検証・保護・判断条件。初回VERIFIED=0は「動く機能0」ではなく、登録義務の全範囲に十分な証拠をまだ対応付けていないという意味。
BLOCKEDはその行の具体的な設計・環境・build組合せ依存を示し、独立した調査や比較器改善まで停止する意味ではない。

## 既存テストの証拠

v3.16入口は940チェックを定義する。正常出力のほか拒否を確認する`error_contains`ガード、歴史的PHP/ALL対比17件を含む。940はPHP正常系全機能の分母ではない。

`FIXTURE_ORACLE_PHP_8.5.12.json`は以前の716定義の**公式PHP側**の記録：MATCH642、ERROR_AGREES69、ALL_REJECTS_VALID_PHP3、MATCH_BUT_PHP_DIAGNOSTIC2。v3.16候補自体の新しい実行結果ではなく、716件全ての厳密互換証明でもない。

既存`PHPT_CORE_ALL_v3_16.jsonl`を再集計し、既存Markdownと一致した。

| 記録判定 | 件数 |
|---|---:|
| PASS | 745 |
| OUTPUT_DIFF | 905 |
| ALL_ERROR | 4,114 |
| TIMEOUT | 43 |
| NOT_RUNNABLE | 9 |
| CRASH | 1 |
| MEMORY | 2 |
| 合計 | 5,819 |

5,819は3領域（Zend/tests、tests/lang、tests/classes）から、当時のWindows公式PHP自身がPASSしたものだけ。元5,973件からSKIP148/WARN3/FAIL1/XFAIL1/ORACLE_ABORT1を除いた計測集合。154件を最終要件から除外する決裁ではない。ext全体/Web/ABI/実アプリは未計測。

次は厳密なフォルダー接頭辞での再集計で、新規実行ではない。

| Zend/tests/下 | 件数 | PASS | その他 |
|---|---:|---:|---|
| `generators` | 186 | 0 | ALL_ERROR=185, TIMEOUT=1 |
| `fibers` | 111 | 0 | ALL_ERROR=109, TIMEOUT=2 |
| `lazy_objects` | 229 | 0 | ALL_ERROR=229 |
| `attributes` | 196 | 16 | ALL_ERROR=88, OUTPUT_DIFF=92 |
| `namespaces` | 113 | 25 | ALL_ERROR=47, OUTPUT_DIFF=41 |
| `property_hooks` | 209 | 15 | ALL_ERROR=163, OUTPUT_DIFF=31 |
| `type_declarations` | 496 | 47 | ALL_ERROR=310, OUTPUT_DIFF=139 |
| `traits` | 215 | 38 | ALL_ERROR=149, OUTPUT_DIFF=27, NOT_RUNNABLE=1 |
| `enum` | 143 | 29 | OUTPUT_DIFF=29, ALL_ERROR=85 |
| `closures` | 135 | 15 | ALL_ERROR=112, OUTPUT_DIFF=7, TIMEOUT=1 |

`PhptWorker.ps1`はConsole.Out文字列を取り、改行・前後空白を正規化してEXPECT系と比較する。**独立stderr・終了コード・任意バイト・副作用の一致ではない**。INI/CLEAN/module設定は再現せず、stdin/argv/env/request/header等の入力セクションを入口制約で実行できない。属性をコメントとして捨てても出力が偶然一致しうるため、属性16PASSを機能実装証拠にしない。

3並列、1本30秒、メモリ上限という条件で、非再現CRASH/時間切れ/MEMORYが記録され、根因は未確定。

## ソースで確認した主要な残件

| 領域 | 基準ソース・記録上の事実 |
|---|---|
| Generator/Fiber | 継続処理の実装を特定できない。foreachはarrayのみ（6088–6093行）。対象186/111件にPASSなし |
| include/require | 最新READMEが未実装と明記。parserにロード経路なし |
| 属性 | tokenizerの#コメント処理（119–133行）が#[...]を消費 |
| 名前空間 | 143–397行の事前トークン変換。動的定義/別ファイル/衝突チェック等の制約 |
| 型付き参照 | property/staticへの参照を2468–2469/2488行で明示拒否 |
| strict_types | declareは予約語のみ、文・実行ノードなし |
| バイナリ文字列 | .NET文字列。strpos/substrも文字単位のAPI |
| 終了/診断/設定 | exit経路なし。診断は任意モードConsole.Out。INIは主に値保持のみ |
| 実行上限 | 5501–5504行で100,000文を超えると一律停止 |
| Web/ABI | PHP SAPI、独立Zend loader/export/layout/lifecycleの実装証拠なし |

古い「decimal中心」「try/catch/namespace未実装」を現在の不足として転記しない。v3.13はint64/double、v3.14は例外、v3.16は名前空間を**部分実装**した。rootの後続v3.17修正はこの基準の後に対応付ける。

## 公式ソースと残る棚卸し

[php-8.5.12公式ソース](https://github.com/php/php-src/tree/php-8.5.12)の文法/字句、closure/generator/fiber/attributes、Zend API/型/module、SAPI、拡張loader、標準stub、UPGRADINGを参照。[言語参照](https://www.php.net/manual/en/langref.php)・[関数参照](https://www.php.net/manual/en/funcref.php)は更新されるため、正確な版は固定ソースへ照合する。

ext/公式ディレクトリ72件を登録したが、zend_test/dl_test/skeletonは試験支援、lexbor/mysqlnd等は依存/内部機構を含み、「公開拡張API72個」とは扱わない。全関数/クラス/定数/INI/依存/PHPTとOS/build適用性のleaf棚卸しが必要。JSON/standard/SPLの一部コードが存在しても全API達成ではない。

[`zend_modules.h`](https://github.com/php/php-src/blob/php-8.5.12/Zend/zend_modules.h)はAPI番号20250925、size/API/debug/ZTS/build ID、module/request globalsとstartup/shutdownを定義。[`dl.c`](https://github.com/php/php-src/blob/php-8.5.12/ext/standard/dl.c)はAPI/build IDを照合。ABIは同名関数だけではなく、[値のlayout](https://github.com/php/php-src/blob/php-8.5.12/Zend/zend_types.h)、所有権/refcount、exports、呼出し規約、callbacks、寿命まで実バイナリで照合する必要がある。

`inventory_gaps`に全言語leaf、全API、native binary、SAPI、PHPT、観測器、実アプリの未棚卸しを登録。これらが残る間はexhaustive=trueにしない。**案A、Windows11x64/Linuxx64、内蔵Web/CGI/FastCGI/Apache/LinuxFPMは承認済み**。残るのは実行環境・具体的なホスト構成・既存バイナリ検証corpusなど。案Bや追加依存の採用は別途判断する。未確定を理由に目標を縮小したり、済んだ決裁を再要求したりしない。

完了ゲートは棚卸し・必要判断・各必須義務の受入れ可能なVERIFIED証拠・既存ALL/PHP回帰・差分/PHPT/CLI/Web/実アプリ/実binary試験・再現ログ/hash/rollback・所有者最終受入れが揃うまで失敗させる。管理行数を完成根拠にしない。
