# ALL PHP v3.15 — オブジェクトの表示・定数・診断（警告）とエラーハンドラ

対象：PHP 8.5.12（64bit、Windows）。

## 実装した挙動

### 値の表示
- `var_dump`：オブジェクト（`object(クラス)#番号 (件数) { … }`）。可視性の注記（`:protected`、`:"クラス":private`）、
  継承したプロパティの並び順、未初期化の型付きプロパティ（`uninitialized(型)`）、動的プロパティ、入れ子、自己参照
  （`*RECURSION*`）、enum（`enum(クラス::ケース)`）。
- オブジェクト番号：`new`・`clone`・クロージャ・first-class callable の生成順に 1 から振る。
- `print_r`：スカラー・配列・オブジェクト、第 2 引数による文字列返却。

### 定数
- `const A = 式;`（複数宣言可）、`define()`、`defined()`、`constant()`。
- 組込み定数：`E_ALL`（30719）ほか `E_*`、`PHP_VERSION`（`8.5.12`）、`PHP_MAJOR_VERSION`、`PHP_MINOR_VERSION`、
  `PHP_RELEASE_VERSION`、`PHP_VERSION_ID`、`PHP_OS`、`PHP_OS_FAMILY`、`DIRECTORY_SEPARATOR`。
  版と OS の定数は、互換の対象（PHP 8.5.12 / Windows）の値を返す。

### 診断とエラーハンドラ
- `set_error_handler`（レベルのマスク、戻り値は直前のハンドラ）、`restore_error_handler`、
  `set_exception_handler`、`restore_exception_handler`、`trigger_error`／`user_error`、
  `error_reporting`、`ini_set`／`ini_get`（値の保持と `error_reporting` への反映のみ）。
- エラー抑制演算子 `@`。
- ハンドラは、クロージャ・関数名・`[オブジェクト, 'メソッド']`・`['クラス', 'メソッド']`・`'クラス::メソッド'` を受け付ける。
  引数の少ないハンドラ、ハンドラ内で発生した診断の再入防止、ハンドラからの例外送出に対応。
- `error_reporting()` の既定値は −1（`docs/COMPAT_TARGET.md` のオラクル実行条件 `error_reporting=-1` に合わせた）。

### 関数
- `str_repeat`、`function_exists`、`call_user_func`、`call_user_func_array`。

## 2 つのモードでの違い

| 事象 | 既定（従来どおり） | `-PhpDiagnostics` |
|---|---|---|
| 未定義の変数・配列キー・プロパティの読み取り | 処理系のエラーで停止（従来と同じ） | PHP と同じく Warning を出して null で続行。エラーハンドラがあれば先に呼ぶ |
| `trigger_error`・`define` の二重定義 | エラーハンドラがあれば呼ぶ。表示はしない | エラーハンドラがあれば呼ぶ。なければ PHP の CLI と同じ文面で表示 |
| 捕捉されなかった例外 | `set_exception_handler` があれば呼ぶ。なければ PowerShell のエラー | `set_exception_handler` があれば呼ぶ。なければ `Fatal error: Uncaught …` を表示 |

`??`、`??=`、`isset()`、`empty()` の中では、どちらのモードでも警告を出さない。

## テスト

- 既存 856 件：期待値・定義とも無変更で全件維持。
- 追加 36 件：`PHP_v3_15_objects_constants_oracle_cases.json`（既定モードで実行）。
- 追加 21 件：`PHP_v3_15_diagnostics_oracle_cases.json`（`-PhpDiagnostics` で実行）。
- 期待値はすべて公式 PHP 8.5.12 の実行結果から機械生成。
- 実行：`ALL_PHP_v3_15_validate.ps1 -CompileCSharp`（事前検査 → 913 件）。

診断の表示文面（`Warning: … in ファイル on line N`）はファイル名を含むため、回帰テストでは照合していない。
診断まわりの回帰テストは、エラーハンドラで受け取った内容と、抑制時に何も出ないことを確認している。
表示文面の照合は公式テスト（PHPT）の計測で行う。

## 未対応として残したもの（完全互換ではない）

- 警告を出す場面のうち実装したのは、未定義の変数・配列キー・プロパティ、定数の二重定義、`trigger_error` のみ。
  float から int への暗黙変換（Deprecated）、配列から文字列への変換、数値でない文字列の演算などは未実装。
- オブジェクト番号は生成順の連番。PHP は解放されたオブジェクトの番号を再利用するが、それは再現していない。
  enum のケースは番号を消費しない（PHP は初回アクセス時に消費する）。
- `var_dump`／`print_r`：クロージャは未対応。配列内の参照マーカーも未対応。
- `var_export`、`debug_zval_refcount` など他の表示関数は未実装。
- `@` の内側で `error_reporting()` が返す値（PHP は 4437）は再現していない。
- `ini_set`／`ini_get` は値を覚えるだけで、`precision` などの設定は動作に反映されない。
- エラーハンドラの第 3 引数（ファイル名）は常に `Command line code`。
- 未定義の定数を直接参照した場合、PHP は `Error` を投げるが、ALL は定数名を文字列として返す（従来の挙動のまま）。
- `E_USER_ERROR` の `trigger_error` は表示のみで、実行を停止しない。
