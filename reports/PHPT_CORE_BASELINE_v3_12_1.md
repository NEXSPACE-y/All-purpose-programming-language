# 公式テスト（PHPT）による現在地の計測 — ALL PHP アダプタ v3.12.1

実施日：2026-11-10 ／ 対象：PHP 8.5.12（ZTS x64、Windows）／ 被験：`package/ALL_PHP_v3_12_adapter.ps1`（無改変）

## 結論

**言語コアの公式テスト 5,819 本のうち、ALL が合格したのは 211 本（3.6%）。**

既存の回帰テスト 716/716 PASS とは別の物差しであり、716 件は引き続き全件合格している。

## 分母の決め方

1. 対象は公式テストパックの `Zend/tests`、`tests/lang`、`tests/classes`（計 5,973 本）。
2. 公式の `run-tests.php` を公式 PHP 8.5.12 で実行し、**この環境で公式 PHP 自身が合格したテストだけ**を分母にした。

| 公式 PHP の結果 | 本数 | 扱い |
|---|---|---|
| PASSED | 5,819 | 分母 |
| SKIPPED | 148 | 対象外（`zend_test` など配布版に無い拡張が必要、ほか） |
| WARNED | 3 | 対象外 |
| FAILED | 1 | 対象外 |
| XFAILED | 1 | 対象外 |
| ORACLE_ABORT | 1 | 対象外（ランナーが 2 回異常終了） |

一覧：`PHPT_CORE_ORACLE_STATUS_PHP_8.5.12.tsv`

## ALL の結果

実行器：`tools/phpt/Invoke-PhptRun.ps1`（Windows PowerShell 5.1 のワーカー 3 並列、1 本 30 秒・1.5GB 上限）。
ALL のアダプタを直接呼び出しており、公式 PHP には委譲していない。判定規則は `run-tests.php` と同じ
（`EXPECT` は完全一致、`EXPECTF`／`EXPECTREGEX` は正規表現、前後の空白と改行コードは正規化）。

| 判定 | 本数 | 割合 | 意味 |
|---|---|---|---|
| PASS | 211 | 3.6% | 出力が期待と一致し、ALL がエラーを出さなかった |
| ALL_ERROR | 5,120 | 88.0% | ALL が例外で停止（未対応の構文・関数など） |
| OUTPUT_DIFF | 461 | 7.9% | 最後まで動いたが出力が違う |
| TIMEOUT | 16 | 0.3% | 30 秒以内に終わらなかった |
| NOT_RUNNABLE | 9 | 0.2% | 標準入力・環境変数・GET/POST などが必要で、現在の入口（コード文字列のみ）では与えられない |
| CRASH | 2 | 0.0% | ワーカープロセスが異常終了 |

全件の結果：`PHPT_CORE_ALL_v3_12_1.jsonl`

### 場所別

| 場所 | 本数 | PASS | 割合 |
|---|---|---|---|
| `tests/classes` | 283 | 40 | 14.1% |
| `tests/lang` | 283 | 22 | 7.8% |
| `Zend/tests` | 5,253 | 149 | 2.8% |

`Zend/tests` の主なフォルダ（本数の多い順）：

| フォルダ | 本数 | PASS |
|---|---|---|
| type_declarations | 496 | 19 |
| lazy_objects | 229 | 0 |
| traits | 215 | 16 |
| property_hooks | 209 | 3 |
| attributes | 196 | 15 |
| generators | 186 | 0 |
| magic_methods | 155 | 10 |
| enum | 143 | 5 |
| closures | 135 | 9 |
| namespaces | 113 | 0 |
| fibers | 111 | 0 |
| exceptions | 93 | 0 |
| constants | 93 | 5 |
| return_types | 86 | 2 |
| try | 81 | 0 |

## ALL が停止した理由（ALL_ERROR 5,120 本）

エラーメッセージを正規化して集計した上位：

| 本数 | メッセージ |
|---|---|
| 1,209 | Undefined constant in expression statement |
| 1,077 | Undefined function '…' |
| 553 | Unknown character at offset N |
| 387 | Expected '…', got '…' |
| 367 | Unsupported expression starting with '…' |
| 248 | Undefined class '…' |
| 95 | Expected member name, got '…' |
| 80 | Invalid assignment expression target |
| 67 | Undefined interface '…' |

未定義関数の上位：`var_dump` 430、`set_error_handler` 72、`error_reporting` 63、`spl_autoload_register` 48、
`define` 32、`register_shutdown_function` 24、`print_r` 22、`class_alias` 21、`str_repeat` 19、`call_user_func` 18、`eval` 16。

ALL_ERROR のうち 1,352 本は、期待出力に `Fatal error`／`Parse error` を含む（PHP でもエラーになるのが正解のテスト）。
ALL もエラーにはなっているが、PHP と同じ診断文を出力していないため合格にはしていない。

## 基本構文の個別確認（`tools/phpt/FeatureProbe.ps1`）

上の集計だけでは原因が分かりにくいメッセージがあるため、短いコードで直接確認した。

**現在エラーになる基本機能**

| 機能 | 例 | ALL の応答 |
|---|---|---|
| try / catch / finally | `try { … } catch (Exception $e) { … }` | Undefined constant in expression statement |
| namespace | `namespace Foo;` | 同上 |
| const 文 | `const A = 1;` | 同上 |
| ジェネレータ | `yield 1;` | 同上 |
| exit | `exit;` | 同上 |
| goto | `goto a;` | 同上 |
| declare | `declare(strict_types=1);` | Invalid assignment expression target |
| 閉じタグと HTML | `?>` の後ろにテキスト | Unsupported expression starting with '?' |
| heredoc | `<<<EOT` | Unsupported expression starting with '<<' |
| 完全修飾名 | `\strlen("ab")` | Unknown character at offset |
| エラー抑制 | `@$x` | Unknown character at offset |
| 型キャスト | `(int)"5"` | Expected ';' |
| 可変長引数 | `function f(...$a)` / `f(...[1,2])` | Unsupported expression starting with '...' |
| 無名クラス | `new class { … }` | Expected ';' |
| `$GLOBALS` | `$GLOBALS["a"]` | Undefined variable 'GLOBALS' |
| 指数表記 | `1e100` | Expected ';' |
| 16 進などの文字列エスケープ | `"\x41"` | not implemented |
| 出力・定義関数 | `var_dump` `print_r` `printf` `define` `intdiv` | Undefined function |

**エラーにならないが結果が PHP と違うもの**

| コード | 公式 PHP 8.5.12 | ALL |
|---|---|---|
| `echo PHP_EOL;` | 改行 | 文字列 `PHP_EOL` |
| `echo 9223372036854775807 + 1;` | `9.2233720368548E+18` | `9223372036854775808` |
| `echo __LINE__;` | `1` | 文字列 `__LINE__` |
| `#[Attr] class A {}` | 属性として解釈 | `#` 以降を行コメントとして無視 |

2 つめは、数値を .NET の `decimal` で持っていることによる差で、仕様書 §5 が指摘している値モデルの問題にあたる。

**動いたもの**：switch、match、do-while、for、配列の分解代入、static メソッド、クラス定数、クロージャ、アロー関数、
instanceof、`??`、global、static 変数、enum、interface 定数、nullsafe 演算子、first-class callable。

## この計測の限界

- PASS は「出力が一致した」ことだけを示す。属性を行コメントとして読み飛ばした結果たまたま一致した、という合格も含まれうる
  （`attributes` フォルダの 15 本など）。機能が正しく実装されている証明ではない。
- `--INI--` で設定を指定するテストは、設定を与えずに実行している。
- 公式テストの多くは `var_dump` で結果を表示するため、`var_dump` が無いだけで落ちているテストが多数ある。
  言語機能そのものの出来は、これらの関数を実装してからでないと測れない。
- 対象は言語コアの 3 フォルダのみ。標準ライブラリや拡張（`ext/`、16,000 本超）は未計測。
- TIMEOUT の 16 本は 30 秒という上限での結果で、時間をかければ終わる可能性がある。

## ここから読み取れる優先順位

1. **テストの土台になる機能**：`var_dump`、`print_r`、`printf`、`define`、`error_reporting`、`set_error_handler`、
   PHP 形式の診断出力（`Warning:`／`Fatal error:` … `in %s on line %d`）。これが無いと他の機能を測れない。
2. **抜けている基本構文**：try/catch/finally と例外、namespace、const、型キャスト、可変長引数、heredoc、
   `?>` と HTML、`@`、完全修飾名、無名クラス、exit、declare、ジェネレータ。
3. **値モデル**：int64 と float の区別（桁あふれで float へ）、float の表示規則、マジック定数と組込定数。
   後から直すと影響が大きいので、所有者の承認を得たうえで早い段階で行う。
