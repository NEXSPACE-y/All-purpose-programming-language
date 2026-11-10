# 既存テスト 716 件を公式 PHP 8.5.12 で答え合わせした結果

実施日：2026-11-10 ／ 実行器：`tools/oracle/Invoke-FixtureOracle.ps1` ／ 詳細：`FIXTURE_ORACLE_PHP_8.5.12.json`

これは「テストに書かれた期待値が公式 PHP 8.5.12 と合っているか」の確認であり、
ALL が PHP と互換であることの証明ではない。テストと期待値は変更していない。

| 判定 | 件数 | 意味 |
|---|---|---|
| MATCH | 642 | 期待出力が公式 PHP の stdout と完全一致。終了コード 0、診断なし |
| ERROR_AGREES | 69 | ALL にエラーを要求するテストで、公式 PHP も異常終了する |
| MATCH_BUT_PHP_DIAGNOSTIC | 2 | stdout は一致するが、公式 PHP は Warning／Deprecated を出す |
| ALL_REJECTS_VALID_PHP | 3 | 公式 PHP では正常に動くコードを、ALL が「未対応」として拒否している |
| MISMATCH | 0 | 期待出力が公式 PHP と食い違うもの |

## 注意が必要な 5 件

| テスト | コード | 公式 PHP 8.5.12 | 現在のテストの扱い |
|---|---|---|---|
| `PHP_v3_3_cases` interpolate undefined variable | `echo "x{$missing}y";` | `xy` ＋ `Warning: Undefined variable $missing` | 出力 `xy` のみ確認。Warning は未確認 |
| `PHP_v3_10_typed_oracle_cases` typed int fractional decimal | `function f(int $x){echo $x;} f(3.9);` | `3` ＋ `Deprecated: Implicit conversion from float 3.9 to int loses precision` | 出力 `3` のみ確認。Deprecated は未確認 |
| `PHP_v3_3_guard_cases` complex interpolation | `$a=["a"]; echo "$a[0]";` | `a` を出力 | ALL はエラーで拒否（未実装） |
| `PHP_v3_4_guard_cases` json_encode option | `echo json_encode([],1);` | `[]` を出力 | ALL はエラーで拒否（未実装） |
| `PHP_v3_4_guard_cases` json_decode depth | `echo json_decode("{}",true,1);` | 何も出力しない（終了コード 0） | ALL はエラーで拒否（未実装） |

## この確認の限界

- ERROR_AGREES は「公式 PHP も異常終了する」ことだけを見ている。エラーの種類・メッセージ・発生時点の一致は未確認。
- 既存テストは診断（Warning／Notice／Deprecated）を照合していないため、診断の一致は全件で未確認。
- 716 件は既存テストであり、PHP の仕様全体のうちどれだけを覆っているかは、要件マニフェスト作成後でないと分からない。
