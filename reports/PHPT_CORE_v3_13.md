# 公式テスト（PHPT）再計測 — ALL PHP アダプタ v3.13（int64／float 値モデル）

実施日：2026-11-10 ／ 対象：PHP 8.5.12 ／ 被験：コミット `3b58160` の `package/ALL_PHP_v3_12_adapter.ps1`

分母・実行条件・判定規則は基準計測（`PHPT_CORE_BASELINE_v3_12_1.md`）と同じ。

## 結果

| 判定 | v3.12.1（基準） | v3.13 | 差 |
|---|---|---|---|
| PASS | 211（3.6%） | **409（7.0%）** | +198 |
| ALL_ERROR | 5,120 | 4,833 | −287 |
| OUTPUT_DIFF | 461 | 547 | +86 |
| TIMEOUT | 16 | 20 | +4 |
| NOT_RUNNABLE | 9 | 9 | 0 |
| CRASH | 2 | 1 | −1 |
| 合計 | 5,819 | 5,819 | |

- 基準で合格していた 211 本は、すべて引き続き合格（退行 0 本）。
- 新たに合格した 198 本の内訳：ALL_ERROR → PASS が 193 本、OUTPUT_DIFF → PASS が 5 本。
- ALL_ERROR → OUTPUT_DIFF の 91 本は、`var_dump` などが使えるようになって最後まで動くようになったが、
  出力がまだ PHP と一致しないもの。
- ALL_ERROR → TIMEOUT の 4 本は、以前は途中でエラー停止していたテストが先へ進むようになり、30 秒以内に終わらなくなったもの。

全件の結果：`PHPT_CORE_ALL_v3_13.jsonl`

## 現在の停止理由の上位（ALL_ERROR 4,833 本）

| 本数 | メッセージ |
|---|---|
| 1,213 | Undefined constant in expression statement（try／namespace／const／yield／exit など未対応の文） |
| 707 | Undefined function '…' |
| 553 | Unknown character at offset N（`\` 完全修飾名、`@` など） |
| 373 | Unsupported expression starting with '…' |
| 282 | Expected '…', got '…' |
| 257 | Undefined class '…' |
| 123 | var_dump() of this value type is not implemented（オブジェクト・enum） |

未定義関数の上位：`set_error_handler` 74、`error_reporting` 63、`spl_autoload_register` 48、`define` 42、
`register_shutdown_function` 26、`print_r` 25、`class_alias` 21、`fopen` 20、`str_repeat` 20、`eval` 19、`call_user_func` 18。

## 注意

- 合格数の増加の多くは、値モデルそのものよりも、`var_dump` とキャストが使えるようになったことによる。
- PASS は出力の一致だけを示し、機能が正しく実装されている証明ではない（基準レポートの「限界」を参照）。
