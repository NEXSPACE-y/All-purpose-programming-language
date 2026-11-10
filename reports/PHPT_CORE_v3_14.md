# 公式テスト（PHPT）再計測 — ALL PHP アダプタ v3.14（例外処理）

実施日：2026-11-10 ／ 対象：PHP 8.5.12 ／ 被験：コミット `e523fd4` の `package/ALL_PHP_v3_12_adapter.ps1`

分母と判定規則は基準計測（`PHPT_CORE_BASELINE_v3_12_1.md`）と同じ。
この回から、捕捉されなかった例外を PHP の CLI と同じ文面で出力するモード（`-PhpDiagnostics`）で実行している。

## 結果の推移

| 判定 | v3.12.1（基準） | v3.13（値モデル） | v3.14（例外） |
|---|---|---|---|
| PASS | 211（3.6%） | 409（7.0%） | **498（8.6%）** |
| ALL_ERROR | 5,120 | 4,833 | 4,669 |
| OUTPUT_DIFF | 461 | 547 | 614 |
| TIMEOUT | 16 | 20 | 26 |
| NOT_RUNNABLE | 9 | 9 | 9 |
| CRASH | 2 | 1 | 3 |

- v3.13 で合格していた 409 本は、すべて引き続き合格（退行 0 本）。
- 新たに合格した 89 本は、すべて ALL_ERROR → PASS。
- ALL_ERROR → OUTPUT_DIFF が 67 本、ALL_ERROR → TIMEOUT が 6 本、ALL_ERROR → CRASH が 3 本。
  いずれも、以前は `try` の時点で停止していたテストが先へ進むようになったもの。
- 全体の実行時間は 750 秒から 1,203 秒に増えた。行番号の記録と組込み例外クラスの読み込みによる処理系の速度低下が
  含まれると見ているが、内訳は未計測。

全件の結果：`PHPT_CORE_ALL_v3_14.jsonl`

## 現在の停止理由の上位（ALL_ERROR 4,669 本）

| 本数 | メッセージ |
|---|---|
| 870 | Undefined function '…' |
| 552 | Unknown character at offset N（`\` 完全修飾名、`@` など） |
| 510 | Undefined constant in expression statement（namespace／const／yield／exit／declare など） |
| 399 | Unsupported expression starting with '…' |
| 318 | Undefined class '…' |
| 310 | Expected '…', got '…' |
| 139 | var_dump() of this value type is not implemented（オブジェクト・enum） |
| 103 | Expected member name, got '…' |

「Undefined constant in expression statement」は 1,213 本から 510 本に減った（`try` が原因だった分が解消）。
その分、次の未対応箇所（未定義関数など）で止まるテストが増えている。
