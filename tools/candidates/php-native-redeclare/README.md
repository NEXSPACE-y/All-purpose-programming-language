# Registered function 衝突の最小修正候補

凍結 native 候補 **47c8edb9e39bffe3ed5475f2aeed7e36673a798d2f72baf0cb60abc39695322d** から生成した別候補。
候補 SHA-256：**53e8d1ba28b8cc375e35b72aa5d1e74807d733b40f03feffeb571332fecc30b1**。
`package/`、元 47c、private-helper/import-alias の各候補はこの担当では変更していない。

## 修正

- 現在の `phpBuiltinNames` の公開名と実際の `NativeContext.HasFunction` 登録名に限定した共通 predicate を追加。
  旧内部 helper `__all_throwable_string` は既存 `function_exists` と同じ public 条件から除外し、同名 user 関数を合法に保つ。
  公式 PHP の 925 関数をすべて実装・登録したように扱う処理ではない。
- トップ直下の global 関数宣言は、program 出力前に登録済み公開名との衝突を検査。
- conditional/nested 宣言は、その宣言が実行された時点の `functiondef` 登録経路で検査。
  namespace 内の別名、未実行宣言、同名 method を拒否しない。
- CLI では engine が Fatal、source line、実 call stack を出し、255 を保持する。
  既存の private control signal を使って PHP catch/finally を通さず終了し、host finally は動作させる。
- user 関数自身は predicate に含めず、従来の user-vs-user 重複診断を勝手に変更しない。

変更は helper 追加・実行前検査・登録時検査の **3 アンカー**。ReadPrimary、prelude、namespace resolver は変更しない。

## 実測

| 集合 | 修正前 | 修正後 |
|---|---:|---:|
| native global 衝突／大小文字／conditional／nested／namespace／method | 4/9 一致 | **9/9 一致** |
| 既存 public builtin `strlen` の同型衝突（元 2 入力を維持） | 0/2 一致 | **2/2 一致** |
| 合法 conditional/namespace/method/private helper と大小文字衝突 | — | **5/5 一致** |
| NativeContext なしの user 関数定義 | — | **3/3 一致** |

計 **19/19** は同一 PHP source の stdout/stderr 生バイト列・実終了値の比較で、正規化や参照出力による置換を行わない。
全比較器の終了コード 0、入力前後ハッシュ一致。最初の 9 例では自前 core identity、worker 内の前後 hash、native 呼出し回数と cleanup 記録も保持する。
証跡は `reports/native-php-integration-review-20261112/` の各 `*-after/report.json`。
修正前失敗は `redeclare-before/` と `known-builtin-before/` にそのまま保持した。

## 再現と統合

```powershell
python -B tools/candidates/php-native-redeclare/Build-RegisteredFunctionCandidate.py
python -B tools/candidates/php-native/Compare-NativePhp.py --adapter tools/candidates/php-native-redeclare/ALL_PHP_registered_function_candidate.ps1 --cases reports/native-php-integration-review-20261112/redeclare.cases.json --output reports/NEW-redeclare --timeout 30
```

生成器は元 47c のハッシュ不一致、アンカーの不一致、既存出力を検出して停止する。
既存候補・証跡を再生成で上書きしない。BOM と CRLF を保持し、通常 diff は `registered-function.patch`、生成の根拠は `provenance.json`。
private-helper/import-alias との統合と実 package の全回帰は別工程で行う。

この 19 例は PHP 全体の完全互換や既定 API 全件の代わりにはならない。
native の selected scalar 制限、callback、一般 object/resource/ref/array、Web/Linux、cleanup 自体の失敗経路などの未完了事項は維持する。
