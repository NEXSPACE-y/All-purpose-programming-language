# 名前空間 runtime fallback の独立レビュー

2026-11-12。`package/` は変更せず、6 件と追加 2 件を公式 PHP 8.5.12 と比較した。
対象パッチは `reviewed-adapter.ps1`（SHA-256 `35b7573773b3fa23383f4334e47345f9db9274591457b028ce81cee0efc7b202`）として保存した時点のもの。
比較基準は HEAD `9d8171712828a0b57555b8eb1e1ca5c475391244` の旧アダプタを取り出した `baseline-adapter.ps1`。
以後の修正の成否は、この報告では判定していない。

## 修正が必要な新規退行

`Resolve-PhpFunctionNodeName` は、namespace 内にも global にも存在しない関数名を global fallback としてキャッシュしていた。
PHP は存在しない callable の検索失敗をその呼出しサイトに固定しない。

次のコードは公式 PHP と HEAD 旧版で `first|local`、終了コード 0。
対象パッチでは `first|` の後に `Undefined function 'late'`、終了コード 1 となった。

```php
<?php
namespace A;
function probe($n) {
    try { return late($n); }
    finally { if ($n == 0) { return 'first'; } }
}
echo probe(0), '|';
if (true) { function late($n) { return 'local'; } }
echo probe(1);
```

同じ問題は first-class callable の作成サイトにもある。
次のコードは公式 PHP と HEAD 旧版で `local`、終了コード 0。
対象パッチでは出力なし、`Undefined function 'late'`、終了コード 1。

```php
<?php
namespace A;
function factory($n) {
    try { return late(...); }
    finally { if ($n == 0) { return null; } }
}
factory(0);
if (true) { function late() { return 'local'; } }
$f = factory(1);
echo $f();
```

対処は、namespace 関数または実在する global user/builtin を発見したときだけ binding を保存すること。
存在しない名前を保存しない。実在する callable を見つけた後は、引数や本体が例外を投げても binding を保持する必要がある。

## 既存の不一致

この 2 点は HEAD 旧版にも存在し、新しいパッチの退行とは分ける。

- 未定義関数の first-class callable を作成時に拒否せず、`created|finally` を出力して終了コード 0 となる。PHP は作成時に Error を投げ、`finally` のみ出力して異常終了する。
- 通常の未定義関数では引数を先に評価し、`arg|finally` という副作用を発生させる。PHP は関数の検索時点で Error を投げるので `finally` のみ。

`review.cases.json` の 3 件目と 4 件目、両結果の `report.json` に stdout・stderr・終了コードの実測を残した。

## 維持すべき挙動

- 実在する builtin を解決した後に引数が例外を投げても、そのサイトの binding を保持する。`cache.valid-builtin-before-argument-failure` は `caught|1` で公式 PHP と一致した。
- 同じ first-class callable の作成サイトから builtin を解決し、その後 local 関数を宣言しても、同じサイトは builtin に binding したまま。`cache.firstclass-valid-builtin-before-local-declaration` は `3|3` で一致した。
- closure と arrow 関数の別インスタンスでも、同じ構文サイトの binding を共有する挙動は今回の 2 件で PHP と一致した。

既存 `function_exists()` は user 関数辞書しか見ず builtin を認識しないため、builtin を含む存在検査にそのまま再利用できない。

## 証跡

- `review.cases.json`：6 件の入力。
- `patched-results/report.json`：対象パッチ 2/6 完全一致。前述の新規退行 2 件、既存不一致 2 件。
- `baseline-results/report.json`：HEAD 旧版 2/6 完全一致。新規退行の 2 件は旧版で合格する。
- `closure-cache.cases.json` と `closure-cache-results/report.json`：追加の closure/arrow 2/2 完全一致。
- `inputs.json`：確認時の revision とスナップショットの SHA-256。

比較は各ケースについて stdout バイト列、stderr バイト列、実プロセス終了コードを正規化せず照合した。
全 940 件や全 PHPT は再実行していない。
