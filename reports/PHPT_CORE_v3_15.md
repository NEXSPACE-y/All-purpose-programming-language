# 公式テスト（PHPT）再計測 — ALL PHP アダプタ v3.15（表示・定数・診断）

実施日：2026-11-10 ／ 対象：PHP 8.5.12 ／ 被験：コミット `884fcbd` の `package/ALL_PHP_v3_12_adapter.ps1`

分母と判定規則は基準計測（`PHPT_CORE_BASELINE_v3_12_1.md`）と同じ。`-PhpDiagnostics` で実行。

## 結果の推移

| 判定 | v3.12.1（基準） | v3.13（値モデル） | v3.14（例外） | v3.15（表示・定数・診断） |
|---|---|---|---|---|
| PASS | 211（3.6%） | 409（7.0%） | 498（8.6%） | **691（11.9%）** |
| ALL_ERROR | 5,120 | 4,833 | 4,669 | 4,298 |
| OUTPUT_DIFF | 461 | 547 | 614 | 785 |
| TIMEOUT | 16 | 20 | 26 | 29 |
| NOT_RUNNABLE | 9 | 9 | 9 | 9 |
| CRASH | 2 | 1 | 3 | 4 |
| MEMORY | 0 | 0 | 0 | 3 |

- v3.14 から新たに合格したのは 194 本。
- **v3.14 で合格していて今回不合格になったものが 1 本ある**（`Zend/tests/coalesce/bug81684.phpt`）。
  `$GLOBALS` 経由の `??=` による書き込みを使うテストで、v3.14 までは「未定義エラーを `??=` が握りつぶす」ことで
  偶然出力が一致していた。v3.15 で `$GLOBALS` を読み取り専用のスナップショットとして実装した結果、書き込みが反映されず
  出力が変わった。`$GLOBALS` への書き込みは未対応。

### 場所別

| 場所 | 本数 | PASS | 割合 |
|---|---|---|---|
| `tests/lang` | 283 | 79 | 27.9% |
| `tests/classes` | 283 | 61 | 21.6% |
| `Zend/tests` | 5,253 | 551 | 10.5% |

全件の結果：`PHPT_CORE_ALL_v3_15.jsonl`

## 計測の経過

最初の計測（コミット `dcd0159`）では PASS 680 本で、v3.14 から 6 本の退行があった。
未定義の変数への書き込み（`$a[] = 1` など）で不要な Warning を出していたことが主因で、`884fcbd` で修正して再計測した。

## 異常終了とメモリ超過

- MEMORY 3 本：`oom_str_repeat`、`oom_soft_limit_exceeded`、`oom_soft_limit_exceeded_fcall`。
  `memory_limit` の超過を試すテストで、ALL には `memory_limit` に相当する仕組みがないため、ワーカーの上限 1.5GB に達する。
- CRASH 4 本：`generators/bug76946`、`generators/gh15330-004`、`register_shutdown_function_refcount`、`traits/constant_015`。
  ワーカープロセスが終了コード 1 で終了した。原因は未調査。1 回目の計測で CRASH だった別の 4 本は、単独実行では
  CRASH しなかったため、並列実行時の一時的な要因（メモリ超過テストとの競合など）の可能性があるが、特定できていない。

## 現在の停止理由の上位（ALL_ERROR 4,298 本）

| 本数 | メッセージ |
|---|---|
| 614 | Undefined function '…' |
| 508 | Unknown character at offset N（`\` 完全修飾名など） |
| 405 | Unsupported expression starting with '…' |
| 396 | Undefined constant in expression statement（namespace／yield／exit／declare など） |
| 347 | Undefined class '…' |
| 327 | Expected '…', got '…' |

未定義関数の上位：`spl_autoload_register` 71、`eval` 37、`assert` 33、`register_shutdown_function` 31、`fopen` 27、
`class_alias` 22、`settype` 18、`ob_start` 16、`is_callable` 15、`gc_collect_cycles` 13、`serialize` 11、`range` 10。
