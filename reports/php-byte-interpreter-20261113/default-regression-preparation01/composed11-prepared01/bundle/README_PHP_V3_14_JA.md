# ALL PHP v3.14 — 例外処理

対象：PHP 8.5.12（64bit、Windows）。

## 実装した挙動

- `try` / `catch` / `finally`。複数の `catch`、`catch (A | B $e)`、変数なしの `catch (A)`、入れ子。
- `throw` 文と、式としての `throw`（`$x ?? throw …`、`fn() => throw …`）。
- `finally` の制御：`return`・`break`・`continue` の途中でも実行、`finally` 内の `return` による上書きと例外の打ち消し、
  `finally` 内で投げた例外への `previous` の連結。
- 組込みの例外階層：`Throwable`、`Exception`、`Error`、`ErrorException`、`RuntimeException`、`LogicException`、
  `BadFunctionCallException`、`BadMethodCallException`、`DomainException`、`InvalidArgumentException`、`LengthException`、
  `OutOfRangeException`、`OutOfBoundsException`、`OverflowException`、`RangeException`、`UnderflowException`、
  `UnexpectedValueException`、`JsonException`、`TypeError`、`ArgumentCountError`、`ValueError`、`ArithmeticError`、
  `DivisionByZeroError`、`AssertionError`、`UnhandledMatchError`。
- メソッド：`getMessage`、`getCode`、`getPrevious`、`getFile`、`getLine`、`getTraceAsString`、`__toString`。
- ユーザー定義の例外クラス（継承、独自コンストラクタ、`$message`／`$code` の既定値の上書き）。
- 処理系が出すエラーのうち次のものを PHP と同じ例外にした：ゼロ除算（`DivisionByZeroError`：`Division by zero`／
  `Modulo by zero`）、`intdiv` の範囲外（`ArithmeticError`）、負のシフト（`ArithmeticError`）、`match` の不一致
  （`UnhandledMatchError`）、enum の `from()` の不正値（`ValueError`）、Throwable でないものの `throw`（`Error`）。
- 行番号：文ごとに開始行を記録し、例外オブジェクトの生成行（`getLine()`）と呼び出し履歴に使う。
- コンストラクタは、PHP と同じく親クラスとのシグネチャ互換検査の対象外にした（親が abstract の場合を除く）。
- 追加の関数：`get_class`。

## 捕捉されなかった例外の扱い（2 つのモード）

| 呼び出し方 | 動作 |
|---|---|
| 既定（従来どおり） | 出力はそこで止まり、PowerShell のエラーになる。メッセージは `ALL PHP: Uncaught <クラス>: <メッセージ>`。従来からあるエラー（例：`ALL PHP: Division by zero`）のメッセージは変えていない |
| `-PhpDiagnostics` 指定 | PHP の CLI と同じ文面（`Fatal error: Uncaught … Stack trace: … thrown in … on line N`）を出力に書いて終了する |

既存の回帰テストは既定の動作を前提にしているため、既定は変更していない。公式テスト（PHPT）の計測は `-PhpDiagnostics` で行う。

## テスト

- 既存 716 件と v3.13 の 92 件：期待値・定義とも無変更で全件維持。
- 追加 48 件：`PHP_v3_14_exceptions_oracle_cases.json`。期待値は公式 PHP 8.5.12 の実行結果から機械生成。
- 実行：`ALL_PHP_v3_14_validate.ps1 -CompileCSharp`（事前検査 → 856 件）。

## 未対応として残したもの（完全互換ではない）

- ファイル名：コードを文字列で受け取るため、`getFile()` と診断文のファイル名は常に `Command line code`。
- 行番号は文の開始行。1 つの文が複数行にまたがる場合、PHP が報告する行と異なることがある。
- `getTrace()`（配列）は未実装。`getTraceAsString()` の引数表示は基本型のみ。クロージャの表記は PHP 8.4 以降の
  `{closure:ファイル:行}` ではなく `{closure}`。
- 型の不一致、未定義関数・未定義メソッドの呼び出し、引数不足などは、まだ PHP の `TypeError`／`Error`／`ArgumentCountError`
  になっておらず、処理系独自のエラーで停止する（`try` では捕捉できない）。
- 例外でない致命的エラーと Warning／Notice／Deprecated の PHP 形式出力は未実装。
- `set_exception_handler`、`set_error_handler`、`error_reporting` は未実装。終了コード（PHP は 255）は返していない。
- 組込み例外のプロパティは PHP では一部 private だが、ここではすべて protected。内部用の `__trace` プロパティを持つ。
- `ErrorException` の severity などの追加引数、`Stringable` の自動付与、完全修飾名（`\Exception`）は未対応。
