# ALL PHP v3.20 — 呼出し・文字列・CLI/native境界の統合候補

**開発中。PHP完全互換、全CLI・標準拡張・Web/Linux、ALL第2段階はいずれも未完了。**

source SHA-256：`5856687f7abd1471b4af7af9827ca2d17a011e836ad2852bf1d7993298fddc9f`。
基準113dへ次の独立候補を統合した。

- 動的呼出しの名前/型/存在確認、引数の評価順、first-class callable、callback引数・参照。
- heredoc/nowdocとescapeの字句解析、Unicode・hex/octal byte生成、コンパイル時診断順序。
- CLI用のcode body/file/stdin mode、argv/argc、タグとinline HTML、shebang/BOM。
- 任意の同期native診断callbackと旧NativeContextの互換経路。対応するnative呼出しを重複実行しない。

CLIは `tools/cli/` の独立C#/.NET Framework host、native実測は
`tools/candidates/php-callback-v3_20/` のouter-Main hostを使用する。
処理系内でPowerShell processを直接終了させず、hostがRunspace破棄後に終了値を返す。
元PS-workerで観測したTIMEOUT/CLR終了異常を解消済みとは扱わず、記録を保存する。

統合前の個別検証はCLI52、動的呼出し73、literal45/48（非UTF8 byte差3残存）、
native74・callback15等。これらは統合後の実測結果とは別で、全互換や網羅率を示さない。
統合後の実package検証は `reports/v3_20-validation-20261113/` へ保存する。
全965件の既存期待値は変更せず `ALL_PHP_v3_20_validate.ps1 -CompileCSharp` で確認する。

主な残件：任意byte文字列/非UTF8 source、完全な補間・構文診断、Unicode識別子とASCII fold、
generators/fibers/Reflection/attributes・標準ライブラリ全体、全CLI引数/INI/environment、
一般native ABI・arrays/refs/objects/resources/任意callback/lifecycle、Windows Web各SAPI、Linux。
nativeは固定dl_testのweak positional scalarと同期診断callbackの選定範囲に限る。

パッチの出所・手動lexical hook・初期INI/診断順序・非重複差分は
`tools/candidates/php-v3_20/` に記録する。公式PHPは照合側にだけ使い、実行を委譲しない。
導入済みALLとmainへの反映はしていない。
