# 公式テスト（PHPT）再計測 — ALL PHP アダプタ v3.16（名前空間）

実施日：2026-11-10 ／ 対象：PHP 8.5.12 ／ 被験：コミット `dfa311c` の `package/ALL_PHP_v3_12_adapter.ps1`

分母と判定規則は基準計測（`PHPT_CORE_BASELINE_v3_12_1.md`）と同じ。`-PhpDiagnostics` で実行。

## 結果の推移

| 判定 | v3.12.1 | v3.13 | v3.14 | v3.15 | v3.16（名前空間） |
|---|---|---|---|---|---|
| PASS | 211（3.6%） | 409（7.0%） | 498（8.6%） | 691（11.9%） | **745（12.8%）** |
| ALL_ERROR | 5,120 | 4,833 | 4,669 | 4,298 | 4,114 |
| OUTPUT_DIFF | 461 | 547 | 614 | 785 | 905 |
| TIMEOUT | 16 | 20 | 26 | 29 | 43 |
| NOT_RUNNABLE | 9 | 9 | 9 | 9 | 9 |
| CRASH | 2 | 1 | 3 | 4 | 1 |
| MEMORY | 0 | 0 | 0 | 3 | 2 |

- v3.15 から新たに合格したのは 56 本。
- **v3.15 で合格していて今回不合格になったものが 2 本ある。** どちらも時間切れ（30 秒）：
  `tests/lang/operators/bitwiseShiftLeft_basiclong_64bit.phpt`、`tests/lang/operators/modulus_basiclong_64bit.phpt`。
  前者は単独実行では約 20 秒で合格することを確認した。後者の単独実行は未確認。
  どちらも名前空間を使わないテストで、3 並列実行時に制限時間を超えたもの。

### 場所別

| 場所 | 本数 | PASS | 割合 |
|---|---|---|---|
| `tests/lang` | 283 | 78 | 27.6% |
| `tests/classes` | 283 | 61 | 21.6% |
| `Zend/tests` | 5,253 | 606 | 11.5% |

全件の結果：`PHPT_CORE_ALL_v3_16.jsonl`

## 計測の経過

最初の計測（コミット `1690300`）では PASS 743 本で、v3.15 から 4 本の退行があった。うち 2 本は、予約語を定数名・
メソッド名に使ったコード（`const NAMESPACE`、`function namespace()`、`const __NAMESPACE__`）を名前解決の前処理が
`namespace`／`use` 文と誤認していたもので、`dfa311c` で修正した。

## 未解決の問題

1. **並列実行時の異常終了が再現しない。** 最初の計測では CRASH が 11 本あったが、その 11 本を 1 本ずつ実行すると
   1 本も異常終了しなかった。今回の計測では CRASH は 1 本（`magic_methods/bug51822`）で、対象も入れ替わっている。
   3 並列実行時のメモリ不足など計測環境側の要因を疑っているが、原因は特定できていない。
   このため、PASS 数は数本の幅で実行ごとに変動しうる。
2. **処理が遅い。** 名前解決の前処理を通るテストでは、定数 75 個を持つクラス 1 つの解析に約 13 秒かかった
   （`grammar/semi_reserved_005`）。TIMEOUT は 29 本から 43 本に増えた。
3. MEMORY 2 本は `memory_limit` の超過を試すテストで、ALL には相当する仕組みがない。

## 現在の停止理由の上位（修正前の計測 `1690300` 時点の集計）

| 本数 | メッセージ |
|---|---|
| 697 | Undefined function '…' |
| 437 | Unsupported expression starting with '…' |
| 426 | Undefined class '…' |
| 360 | Undefined constant in expression statement（yield／exit／declare など） |
| 349 | Expected '…', got '…' |
| 113 | Expected member name, got '…' |

「Unknown character at offset N」（v3.15 で 508 本）は上位から消えた。`\` が読めるようになったためで、
その分は未定義のクラス・関数など次の未対応箇所へ移っている。

未定義関数の上位：`spl_autoload_register` 72、`assert` 39、`eval` 38、`register_shutdown_function` 37、`fopen` 29、
`class_alias` 29、`settype` 18、`ob_start` 17、`is_callable` 16、`gc_collect_cycles` 13。
