# ALL PHP v3.13 — 数値の値モデル（int64／float）

対象：PHP 8.5.12（64bit、Windows）。所有者承認（2026-11-10）に基づく基盤変更。

## 変更の要点

これまで PHP の数値をすべて .NET の `decimal` で保持していたため、`int` と `float` の区別、
桁あふれ、IEEE-754 の丸めを再現できなかった。v3.13 で次のように改めた。

| PHP の型 | 内部表現 |
|---|---|
| int | `System.Int64` |
| float | `System.Double`（IEEE-754 倍精度） |

## 実装した挙動

- 整数リテラル：10 進・16 進（`0x`）・8 進（`0`／`0o`）・2 進（`0b`）・桁区切り `_`。64bit に収まらない場合は float。
- 浮動小数リテラル：`1.5`、`.5`、`6.`、`1e3`、`1.5e-3`。
- 加減乗算：int 同士で桁あふれした場合は float に切り替える。
- 除算：割り切れる int 同士は int、それ以外は float。
- 剰余・ビット演算・シフト：オペランドを int に変換。シフト幅 64 以上と負のシフトを PHP と同じに扱う。
- べき乗：int の非負整数乗は収まる限り int、それ以外は float。
- 比較：int 同士は厳密、int と float は float として比較。数値文字列同士は数値として比較。NAN を含む大小比較は常に false。
- `===`：int と float を別の型として区別（`1 === 1.0` は false）。
- float の文字列化：`echo`・連結・`(string)` は precision=14、`var_dump`・`json_encode` は最短往復表現
  （serialize_precision=-1）。指数表記への切り替え位置、`-0`、`INF`、`NAN` を含む。
- float から int への変換：0 方向への切り捨て。範囲外は 2^64 を法として折り返し、NAN／INF は 0。
- 数値文字列：前後の空白、符号、小数、指数を解釈。整数形式で 64bit を超えるものは float。
- 配列キー：float は切り捨てて int キー、整数形式の文字列は int キー。
- 型宣言：`int` と `float` を区別。int は float 宣言へ自動変換。弱い型変換と union 型での優先順（int → float → string → bool）。
- JSON：`json_encode` は int と float を区別して出力、`json_decode` は整数を int、小数を float に復元。

## 値モデルを観測するために追加したもの

- キャスト：`(int)` `(float)` `(string)` `(bool)`
- 関数：`var_dump`（null・bool・int・float・string・配列）、`gettype`、`is_int`／`is_integer`／`is_long`、
  `is_float`／`is_double`、`is_null`、`is_numeric`、`intval`、`floatval`／`doubleval`、`boolval`、`intdiv`、`fdiv`、
  `pow`、`sqrt`、`floor`、`ceil`、`is_nan`、`is_infinite`、`is_finite`
- 定数：`PHP_INT_MAX`、`PHP_INT_MIN`、`PHP_INT_SIZE`、`PHP_FLOAT_EPSILON`、`PHP_FLOAT_MAX`、`PHP_FLOAT_MIN`、
  `PHP_FLOAT_DIG`、`INF`、`NAN`、`M_PI`、`M_E`、`PHP_EOL`（対象が Windows の PHP なので CRLF）

## テスト

- 既存 716 件：期待値・定義とも無変更で全件維持。
- 追加 92 件：`PHP_v3_13_numeric_oracle_cases.json`。期待値はすべて公式 PHP 8.5.12 の実行結果から機械生成した
  （生成元 `tools/oracle/sources/PHP_v3_13_numeric.cases.txt`、生成器 `tools/oracle/New-OracleFixtures.ps1`）。
  公式 PHP が診断（Warning／Deprecated）を出すコードは、この件数に含めていない。
- 実行：`ALL_PHP_v3_13_validate.ps1 -CompileCSharp`（事前検査 → 808 件）。

アダプタのファイル名は `ALL_PHP_v3_12_adapter.ps1` のまま（既存の v3.12 テストスクリプトから参照されているため）。

## 未対応として残したもの（完全互換ではない）

- 診断の出力：PHP が出す Warning／Deprecated（例：小数部のある float を int に暗黙変換、範囲外の float を int にキャスト、
  NAN の文字列化）は出力していない。
- 先頭だけが数値の文字列（`"5 apples"`）を算術に使う場合：PHP は Warning を出して 5 として扱うが、ALL はエラーで停止する。
- 数値でない文字列を算術に使う場合：PHP は TypeError を投げるが、ALL は独自のエラーで停止する（例外機構が未実装）。
- ゼロ除算・剰余ゼロ：PHP は `DivisionByZeroError` を投げるが、ALL は独自のエラーで停止する。
- `json_encode` に INF／NAN を渡した場合：PHP は false を返して警告するが、ALL はエラーで停止する。
- `var_dump`：オブジェクト・enum・クロージャは未実装。配列内の参照マーカーも未実装。
- 配列の次の添字：負の整数キーの直後の `[]`（PHP 8.3 以降は「キー＋1」）は未対応。
- `intval` の第 2 引数（基数）、`round`、`number_format`、`printf` 系は未実装。
- `(array)` `(object)` キャストは未実装。
- float 文字列の解析は .NET Framework の `double.Parse` に依存しており、17 桁を超える入力の最終ビットの丸めは未検証。
- `declare(strict_types=1)` は未実装のため、型変換は常に弱いモード。
