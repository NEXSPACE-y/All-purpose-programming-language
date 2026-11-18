# ALL (ALMIGHTY) × PHP 8.5.12 完全互換 ＆ ポリグロットランタイム 引き継ぎ書 (`HANDOFF.md`)

**更新日時**: 2026-11-18  
**引き継ぎ元セッション**: `163ff82d-e386-4a9d-b285-51e156de24d6`  
**引き継ぎ先プロジェクト**: `Projects > ALL`  
**対象ブランチ**: `codex/php-8.5.12-full-compat-20261112`（統合ディレクトリ: `D:\ALL` / ジャンクション: `C:\Users\rinpa\ALL -> D:\ALL`）

---

## 1. プロジェクト概要・目的

### 1.1 全体目標
- **ALL（ALMIGHTY）言語**は、英語構文および日本語の自然な構文（v0.6）の双方を解釈し、数値計算・Webサーバー・CLI・SQLite・KVストア・並列実行などを単一ランタイムで扱う汎用プログラミング言語である。
- 本プロジェクトの長期目標は、**主要開発言語（PHP を皮切りに Python / JavaScript / Rust / C# 等）をすべて ALL 上で完全互換動作させ、言語間でシームレスに相互呼び出しできる「Universal Polyglot Runtime Bridge (`ALL Polyglot Engine`)」を実現すること**にある。
- 直近の中核目標として以下を掲げている：
  1. **PHP 8.5.12 完全互換の実装**（Windows x64 / CLI & Web、Zend Engine API `20250925` 相当）。
  2. **ALL ⇔ PHP 双方向互換**（「ALL でも PHP を認識し、PHP でも ALL を認識する」相互読み込み・相互呼び出し・共有変数同期）。

### 1.2 アーキテクチャの基本前提
- **実行委譲（外部プロセス丸投げ）の禁止**:
  - 公式 `php.exe` (`D:\ALL\oracle\php-8.5.12-ts-x64\php.exe`) は**挙動比較用の検証オラクル専用**であり、ALL ランタイムの内部から外部 `php.exe` や `Invoke-Expression` に実行を委譲してはならない。
- **ハイブリッド3層ランタイム構成**:
  1. **言語アダプタ層（PowerShell AST インタープリタ）**:
     - `D:\ALL\languages\all.ps1`（パッケージ元: `D:\ALL\package\ALL_v1_0_adapter.ps1`）
     - `D:\ALL\languages\php.ps1`（パッケージ元: `D:\ALL\package\ALL_PHP_v3_12_adapter.ps1`）
  2. **インプロセス CLR バイトランタイム層（C# `Add-Type` キャッシュ）**:
     - `AllPhp.ByteValues.PhpBytes`（バイナリセーフな PHP 文字列・不変チャンクツリー）
     - `AllPhp.ByteCodecs.PhpBase64`（RFC 4648 Base64 エンコード／厳密デコード）
     - `AllPhp.NativeEngine.RustBridge`（`kernel32.dll` `LoadLibraryW` + P/Invoke による `all_engine.dll` 呼び出しブリッジ）
     - `AllPhp.ValidTextSymbols.Comparers`（UTF-8 検証済みシンボルの ASCII 比較器）
  3. **Rust ネイティブエンジン ＆ 並列ランナー層（`D:\ALL\native\all-engine`）**:
     - `all_engine.dll`（Zend Engine 8.5.12 `#[repr(C)]` C-ABI 構造体、言語非依存 `PolyglotStore`、RFC 1321 MD5 / FIPS 180-1 SHA-1 / FIPS 180-4 SHA-256 / IEEE 802.3 CRC32 / Levenshtein ネイティブ実装）
     - `all_runner.exe`（公式 PHPT 22,280件向けマルチスレッドスキャン＆ `run-phpt` テストランナー）

### 1.3 主要ディレクトリ・リポジトリパス一覧
- **統合ベースディレクトリ（ランタイム＋Gitリポジトリ）**: `D:\ALL`（`C:\Users\rinpa\ALL` は `D:\ALL` へのジャンクション）
- **リモート Git リポジトリ**: `https://github.com/NEXSPACE-y/All-purpose-programming-language`
- **パッケージソース**: `D:\ALL\package`
- **Rust ネイティブエンジン**: `D:\ALL\native\all-engine`
- **PHP 8.5.12 オラクル ＆ 公式 PHPT テスト群 (22,280件)**:
  - `D:\ALL\oracle\php-8.5.12-ts-x64\php.exe`
  - `D:\ALL\oracle\php-8.5.12-tests\`
- **仕様・設計ドキュメント**:
  - `D:\ALL\docs\ALL_ALMIGHTY_PHP_Full_Compatibility_Specification_v1.0_20261110.md`
  - `D:\ALL\docs\COMPAT_TARGET.md`
  - `D:\ALL\docs\PHP_REQUIREMENTS_COVERAGE.md`
  - `D:\ALL\docs\PHP_REQUIREMENTS_MATRIX.json`
  - `D:\ALL\docs\phpt_lang_report.json`
  - `D:\ALL\docs\phpt_zend_report.json`
  - `C:\Users\rinpa\Desktop\ALL_new_chat_handoff_20261102.md`

---

## 2. 完了済みフェーズと実装内容（Phase 1〜Phase 4）

### 2.1 Phase 1：分散候補モジュールの単一統合と性能ボトルネック解消
- `tools/candidates/php-byte-interpreter/composed14-array/ALL_PHP_byte_candidate.ps1`（17個のバイトインタープリタモジュール統合済みベース）に対し、後続9個の候補モジュール（`StrictTypesEdits`, `SourceLoaderEdits`, `TypeDeclarationEdits`, `ParameterDefaultEdits`, `VariadicBoundaryEdits`, `ClosureDisplayEdits`, `LoadedUnitEdits`, `ForeachIteratorEdits`, `Base64BuiltinEdits`）をすべて単一アダプタに統合。
- `PhpByteRuntime.cs` と `PhpBase64.cs` をアダプタ内の `Add-Type` に自己完結型で埋め込み、AppDomain 内の型存在チェック（`if (-not ('AllPhp.ByteValues.PhpBytes' -as [type]) ...)`）でガード。これにより、965件実行ごとに走っていた `Get-FileHash` I/O を排除し大幅な高速化を達成。
- CLI コンテキスト外での `eval("return 40 + 2;")` 許可判定（`LoadedUnitBody` / `$isCli` ガード）や、従来仕様のエラー文言互換（`$legacyMessage` 引数および `::get` フック型不一致時の文言マッピング）を修正し、既存 PHP 965件を 100% 通過。

### 2.2 突破策 A・B・C：Rust ネイティブエンジン（`D:\ALL\native\all-engine`）
- `D:\ALL\native\all-engine\` で管理し、`rustc` / `cargo` でリリースビルドした `all_engine.dll` と `all_runner.exe` を `package\` および `D:\ALL` に配備。
- **実装済みエクスポート (`src/lib.rs`)**:
  - Zend 8.5.12 ABI 互換 `#[repr(C)]` 構造体：`Zval`, `ZendValueUnion`, `ZendFunctionEntry`, `ZendModuleEntry`（`ZEND_MODULE_API_NO_8_5 = 20250925`）
  - ポリグロット共有バス：`all_engine_version`, `all_polyglot_set_json`, `all_polyglot_get_json`, `all_polyglot_clear`
  - ネイティブ高速標準関数：`all_stdlib_md5`, `all_stdlib_sha1`, `all_stdlib_sha256`, `all_stdlib_crc32`, `all_stdlib_levenshtein`
- **並列スキャナ ＆ 並列ランナー (`src/bin/all_runner.rs`)**:
  - `all_runner.exe scan-phpt <dir>` で `.phpt` ファイルをマルチスレッド走査し、`--TEST--`, `--FILE--`, `--EXPECT--`, `--EXPECTF--`, `--SKIPIF--` 等をパース可能。
  - `all_runner.exe run-phpt <dir> [--filter <substr>] [--limit <N>] [--adapter <php.ps1>] [--oracle <php.exe>] [--report <out.json>] [--workers <N>]` で公式 `.phpt` テストを並列実行し、`PASS` / `FAIL` / `SKIPIF` / `UNSUPPORTED` 集計 JSON レポートを生成可能（Task 5.1 で実装済み）。

### 2.3 Phase 2：PHP 8.5 コア機能・SPL・標準ライブラリ拡張（`ALL_PHP_v3_12_adapter.ps1`）
- **ジェネレータ (`Generator` / `Iterator` 実装)**:
  - `Read-Primary` で `yield` / `yield $k => $v` / `yield from` をパース、`Test-PhpContainsYield` により関数・メソッド・クロージャがジェネレータか判定。
  - 単一スレッドPowerShellランタイム上で正確に状態を再生する **Checkpoint + Replay-Silence (`GeneratorReplayMute`)** 方式により、`current()`, `key()`, `next()`, `rewind()`, `valid()`, `send($v)`, `throw($e)`, `getReturn()`, ネストした `yield from` を完全サポート（`Write-PhpBytes` はリプレイ区間を自動ミュートするため副作用の重複出力も発生しない）。
- **PHP 8 アトリビュート (`#[...]`) ＆ リフレクション API**:
  - `ConvertTo-PhpTokens` で `#\[` をトークン化しつつ従来の `#` 行コメントを維持。`Resolve-PhpNamespaceTokens` でアトリビュートクラス名（`use` / `namespace`）を完全解決。
  - クラス・インターフェース・トレイト・列挙型・enum case・関数・クロージャ・静的クロージャ・メソッド・プロパティ（コンストラクタ昇格プロパティ含む）・定数・引数に `Attributes` を保持。
  - `#[Attribute]` 定義、`ReflectionClass`, `ReflectionMethod`, `ReflectionFunction`, `ReflectionProperty`, `ReflectionParameter`, `ReflectionAttribute`, `ReflectionNamedType`, `ReflectionType`, `ReflectionException` を `__all_internal_dispatch` 経由で実装。
- **オブジェクト反復・SPL インターフェース**:
  - `$phpPreludeSource` に `Traversable`, `Iterator`, `IteratorAggregate`, `Countable`, `ArrayAccess` を追加し、プレリュード AST キャッシュ名を `ALLPhpPreludeAstPrivateThrowableSourceLoaderV3` へ更新。
  - `Test-PhpTypeAtom` の `iterable` が `Generator` / `Traversable` を受理。
  - `foreach` 文が `Generator`, `Iterator`, `IteratorAggregate`, および通常オブジェクトの可視プロパティ（値渡し・参照渡し `&$v` 両方）を反復可能。
  - `ArrayAccess` をインデックス読み取り (`Get-PhpArrayItem`)・書き込み (`Set-LValue`)・`isset`/`empty`・`unset` に統合、`Countable` を `count()` / `sizeof()` に統合。
- **PHP 8.5 標準ライブラリ（実装済み関数群）**:
  - **PHP 8.4/8.5 配列関数**: `array_find`, `array_find_key`, `array_any`, `array_all`, `array_is_list`
  - **配列操作・ソート**: `array_map`, `array_filter`, `array_reduce`, `array_unique`, `array_search`, `array_combine`, `array_chunk`, `array_column`, `array_fill`, `array_fill_keys`, `array_flip`, `array_diff`, `array_diff_key`, `array_intersect`, `array_intersect_key`, `array_pad`, `array_product`, `array_replace`, `array_splice`, `array_count_values`, `array_change_key_case`, `range`, `sort`, `rsort`, `asort`, `arsort`, `ksort`, `krsort`, `usort`, `uasort`, `uksort`, `compact`, `extract`, `iterator_to_array`, `iterator_count`
  - **正規表現・文字列・フォーマット・コーデック**: `preg_match`, `preg_match_all`, `preg_replace`, `preg_split`, `preg_quote`, `sprintf`, `printf`, `vsprintf`, `number_format`, `urlencode`, `urldecode`, `rawurlencode`, `rawurldecode`, `htmlspecialchars`, `htmlspecialchars_decode`, `ord`, `chr`, `hex2bin`, `ucfirst`, `lcfirst`, `ucwords`, `strrev`, `nl2br`, `ltrim`, `rtrim`, `chop`, `str_pad`, `str_split`, `stripos`, `strrpos`, `strripos`, `str_ireplace`, `substr_count`, `strcmp`, `strcasecmp`, `strncmp`, `strncasecmp`, `str_rot13`
  - **ハッシュ・数学・イントロスペクション・シリアライズ**: `md5`, `sha1`, `crc32`, `hash` (`md5`/`sha1`/`sha256`/`sha384`/`sha512`), `levenshtein`, `min`, `max`, `round`, `exp`, `log`, `log10`, `sin`, `cos`, `tan`, `pi`, `deg2rad`, `rad2deg`, `hypot`, `is_scalar`, `is_object`, `is_callable`, `is_iterable`, `is_countable`, `get_debug_type`, `class_exists`, `interface_exists`, `trait_exists`, `enum_exists`, `method_exists`, `property_exists`, `is_a`, `is_subclass_of`, `get_parent_class`, `get_class_methods`, `get_object_vars`, `spl_object_id`, `var_export`, `serialize`, `unserialize`
  - ※ **注意（未実装スイッチ分岐あり）**: `$phpBuiltinNames`（`ALL_PHP_v3_12_adapter.ps1` 内）には予約登録したが `Invoke-PhpFunction` の `switch` 分岐が未実装のものが一部残っている（後述 Section 4.4 を参照）。

### 2.4 Phase 3：ALL ⇔ PHP 双方向ポリグロット互換ブリッジ
- **`$global:AllPolyglotContext`**: PowerShell セッション内で `SharedVars`, `AllFunctions`, `PhpFunctions`, `PhpClasses`, `PhpInterfaces`, `PhpTraits`, `PhpConstants`, `PendingAllCall`, `PendingAllResult` を共有し、`ALL_v1_0_adapter.ps1` と `ALL_PHP_v3_12_adapter.ps1` の双方が値変換 (`Convert-PhpValueToAllPolyglot` / `Convert-AllPolyglotValueToPhp`) と前後同期を行う。
- **ALL → PHP 方向 (`ALL_v1_0_adapter.ps1`)**:
  - `import "file.php"` および `「file.php」をモジュールとして読み込む`（実在する `.php` ファイルの読み込み・インライン展開）
  - `.all` ソース内での `<?php ... ?>` インラインブロック実行（`Expand-AllModuleImports` 後に展開・Base64 化し、行番号マップ `sourceOrigins` と一致させるパディング付き）
  - `new ClassName(...)`, `.` および `->` 演算子によるプロパティ読み書き・メソッド呼び出し（`php-new`, `php-method` AST ノード）
  - ALL からの PHP ユーザー定義関数・PHP 標準関数、`php_eval(...)`, `php_call(...)` 呼び出し、および `SharedVars` への変数双方向同期
- **PHP → ALL 方向 (`ALL_PHP_v3_12_adapter.ps1`)**:
  - `include` / `require` / `include_once` / `require_once` による `.all` ファイルの直接読み込み
  - `.php` ソース内での `<?all ... ?>` インラインブロック実行（英語 ALL 構文および日本語自然な構文 v0.6 の双方を実行、標準出力キャプチャを `Write-PhpBytes` へ統合）
  - PHP からの ALL ユーザー定義関数（`fn` / `関数` / `namespace::fn`）・ALL 組み込み関数（`kv_put`, `kv_get`, `kv_delete`, `kv_keys`, `sql_query`, `sql_exec`, `sql_migrate`, `sql_transaction`）・`all_eval(...)` / `all_call(...)` 呼び出し、`SharedVars` との変数双方向同期
  - `ALL_sqlite_driver.cs` のパス探索に `$allAdapterDir` フォールバックを追加し、ステージング実行時でも SQLite が動作するよう修正。

### 2.5 Phase 4 〜 Task 5.1：主要変更・構成ファイル一覧
- **統合ディレクトリ / Git 作業ツリー (`D:\ALL`)**:
  - `package\ALL_PHP_v3_12_adapter.ps1`（統合＋Phase 2/3＋Task 5.1〜5.4 PHP アダプタ、セッションキャッシュ＆`MaxSteps`対応済み）
  - `package\ALL_v1_0_adapter.ps1`（Phase 3 ポリグロット対応 ALL アダプタ）
  - `package\ALL_PHP_phase2_3_test.ps1`（23件の Phase 2 & Phase 3 検証テストスイート）
  - `package\ALL_integrated_install.ps1`（`languages/php.ps1`, `all_engine.dll`, `languages/all_engine.dll`, `all_runner.exe` の配置、一時 `.bak.<guid>` 自動掃除、および全統合検証を実施）
  - `package\all_engine.dll` / `package\all_runner.exe`
  - `package\SHA256SUMS.txt`（全パッケージファイルの SHA-256 マニフェスト）
  - `native\all-engine\Cargo.toml`, `src\lib.rs`, `src\bin\all_runner.rs`
- **配備済み本番ランタイム (`D:\ALL` / ジャンクション `C:\Users\rinpa\ALL`)**:
  - `D:\ALL\languages\php.ps1`（`ALL_PHP_v3_12_adapter.ps1` より配置）
  - `D:\ALL\languages\all.ps1`（`ALL_v1_0_adapter.ps1` より配置）
  - `D:\ALL\all_engine.dll` ＆ `D:\ALL\languages\all_engine.dll`
  - `D:\ALL\all_runner.exe`

---

## 3. テスト検証結果の証跡

### 3.1 パッケージ整合性プリフライト（`package\ALL_preflight.ps1 -CompileCSharp`）
- **PowerShell 構文検証**: `PASS [PowerShell Syntax]: 103 scripts`
- **SHA-256 マニフェスト整合性**: `PASS [SHA-256]: 221 packaged files`
- **Windows C# コンパイル検査**: `ALL_sqlite_driver.cs` PASS, `ALL_ConcurrentGateway.cs` PASS
- **ステータス**: `ALL preflight PASS.`（Exit code 0）

### 3.2 ALL 言語 統合回帰テスト（`D:\ALL\package\ALL_integrated_install.ps1` 実行ログより）
インストール先 `D:\ALL`（`C:\Users\rinpa\ALL` 経由）に対して以下 **17スイート合計 527/527 PASS（0 failed）** を確認済み：

| テストスクリプト | テスト対象 | 結果 |
|---|---|---|
| `package\ALL_cli_v1_3_test.ps1` | CLI stdin/stderr/exit code・日本語エイリアス | **8 / 8 passed** |
| `package\ALL_cli_web_v1_2_test.ps1` | CLI+Web 常時配信・停止ファイル・障害耐性 | **11 / 11 passed** |
| `package\ALL_cli_http_v1_1_test.ps1` | CLI 引数・Batch HTTP サーバー | **18 / 18 passed** |
| `package\ALL_v1_0_test.ps1` | 名前空間・KV・並列実行・オフラインパッケージ | **29 / 29 passed** |
| `package\ALL_http_v0_9_test.ps1` | HTTP サーバー GET/POST/日本語エイリアス | **11 / 11 passed** |
| `package\ALL_http_v0_8_test.ps1` | HTTP クライアント GET/POST JSON | **16 / 16 passed** |
| `package\ALL_module_v0_7_test.ps1` | モジュール import（日英・循環/脱出検査・CLI売上集計） | **26 / 26 passed** |
| `package\ALL_Japanese_grammar_v0_6_test.ps1` | 日本語自然な構文 v0.6 | **34 / 34 passed** |
| `package\ALL_language_v0_5_test.ps1` | 制御構文・配列・辞書・関数・例外 v0.5 | **49 / 49 passed** |
| `package\ALL_JP_v0_4_test.ps1` | 日本語キーワード v0.4 | **27 / 27 passed** |
| `package\ALL_language_v0_3_test.ps1` | 基本言語構文 v0.3 ＆ PHP 対比 | **61 / 61 passed** |
| `package\ALL_PHP_v3_2_test.ps1` | Math (146/146) + PHP v3.2 拡張 (50/50) | **196 / 196 passed** |
| `package\ALL_sql_v1_4_test.ps1` | SQLite パラメータ化クエリ・トランザクション・インジェクション対策 | **24 / 24 passed** |
| `package\ALL_sql_migrations_test.ps1` | SQL バージョン管理マイグレーション・チェックサム | **5 / 5 passed** |
| `package\ALL_debug_test.ps1` | 構造化トレースログ・コールスタック | **3 / 3 passed** |
| `package\ALL_debug_source_test.ps1` | import/日本語構文の元ファイル・行番号マッピング | **4 / 4 passed** |
| `package\ALL_parallel_web_test.ps1` | 並列 Web ゲートウェイプール | **5 / 5 passed** |
| **合計** | **ALL 統合ランタイム全体** | **527 / 527 passed; 0 failed** |

### 3.3 Phase 2 & Phase 3 新規機能・双方向互換テスト（`package\ALL_PHP_phase2_3_test.ps1 -Installed`）
インストール済み `D:\ALL\languages\php.ps1` および `all.ps1` に対して **23 / 23 passed; 0 failed** を確認済み（Task 5.1 で #19/#20、Task 5.2 で #21、Task 5.3 で #22、Task 5.4 で #23 を追加）：
1. `phase2_generator_basic_and_return`（`yield $k => $v` ＆ `getReturn()` ＆ 出力副作用順序）
2. `phase2_generator_yield_from_and_send`（`yield from` 配列/Generator ＆ `$g->send()`）
3. `phase2_attributes_and_reflection`（クラス・プロパティ・昇格プロパティ・メソッド・引数・関数の `#[...]` ＆ `Reflection*`）
4. `phase2_object_foreach_and_traversable`（`Iterator`, `IteratorAggregate`, 可視プロパティ参照渡し `foreach`）
5. `phase2_array_access_and_countable`（`ArrayAccess` `[]` 読み書き/`isset`/`empty`/`unset`, `Countable` `count()`/`sizeof()`）
6. `phase2_php85_stdlib_and_rust_engine`（`array_filter`/`map`/`reduce`/`find`/`find_key`/`any`/`all`, `sort`, `sprintf`, `number_format`, `str_pad`, `preg_*`, `serialize`/`unserialize`, Rust C-ABI `md5`/`sha1`/`hash('sha256')`/`crc32`/`levenshtein`）
7. `phase3_all_imports_php_and_uses_classes`（ALL `import "file.php"` ＋ PHP 関数・クラス・インスタンス・プロパティ・メソッド）
8. `phase3_all_japanese_and_inline_php`（日本語ALL構文 `「file.php」をモジュールとして読み込む` ＋ `<?php ... ?>` インライン＋変数共有）
9. `phase3_php_requires_all_and_calls_all_functions`（PHP `require_once '*.all'` ＋ 英語/日本語 ALL 関数＆変数参照）
10. `phase3_php_inline_all_block_bidirectional`（PHP 内 `<?all ... ?>` ブロック＋日本語構文＋双方向変数更新）
11. `phase3_php_calls_all_kv_and_sql_builtins`（PHP から ALL `kv_put`/`kv_get` ＆ `sql_exec`/`sql_query` 呼び出し）
12. `phase2_generator_throw_exception`（`$g->throw()` とジェネレータ内 `try/catch`）
13. `phase2_closure_attributes_and_reflection`（クロージャ／アロー関数 `#[...]` ＋ `static fn` ＋ `ReflectionFunction`）
14. `phase2_reflection_without_ctor_and_property_access`（`newInstanceWithoutConstructor()`, `ReflectionProperty::isInitialized`/`setValue`/`getValue`）
15. `phase2_array_sorting_and_splice`（`asort`, `ksort`, `usort`, `array_splice`）
16. `phase2_array_manipulation_suite`（`compact`, `extract`, `array_column`, `array_diff`, `array_intersect`）
17. `phase2_string_url_html_codecs`（`urlencode`, `rawurlencode`, `htmlspecialchars`, `htmlspecialchars_decode`, `str_rot13`, `bin2hex`, `hex2bin`, `ucfirst`, `lcfirst`, `ucwords`, `strrev`）
18. `phase2_class_and_type_introspection`（`class_exists`, `interface_exists`, `trait_exists`, `enum_exists`, `method_exists`, `property_exists`, `is_a`, `is_subclass_of`, `get_parent_class`, `get_debug_type`）
19. `phase3_multi_roundtrip_all_php_interop`（1ファイル内 ALL → PHP → ALL → PHP 多段階往復と配列同期）
20. `phase2_newly_completed_13_builtins`（`func_num_args`/`get_args`/`get_arg`, `settype`, `get_class_vars`, `substr_replace`, `chunk_split`, `wordwrap`, `quotemeta`, `addslashes`/`stripslashes`, `soundex`, `array_diff_assoc`）
21. `phase2_task5_2_language_and_stdlib_extensions`（マジック定数/`Trait`, `var`/カンマ区切り/親シャドウ `private` プロパティ, 無名クラス/動的 `new`/動的メンバ, `list()`/`foreach` 分割代入/スキップ/参照代入, トップレベル `static`, `{$expr}`/`${var}` 文字列補間, `current`/`next`/`prev`/`reset`/`end`/`array_walk_recursive`, `ob_start`/`ob_get_contents`/`ob_clean`/`ob_get_clean`/`PHP_OUTPUT_HANDLER_*`, `constant('C::K')`/`defined`/`get_declared_classes`/`get_defined_vars`/`debug_backtrace`/`zend_version`）
22. `phase2_task5_3_asymmetric_vis_unpack_assert_and_builtins`（非対称可視性 `public(set)`/`protected(set)`/`private(set)`・コンストラクタ昇格・間接変更/参照制限・プロパティフック `#[...]`/`final`, `...$expr` 引数展開と `Traversable`/`Generator` 展開, 多次元 `ArrayAccess` の `isset`/`empty`/`??` 短絡, `__debugInfo()`/`__toString()` Error, `assert()`/`zend.assertions`, `strstr`/`strchr`/`stristr`/`rand`/`mt_rand`/`random_int`/`array_merge_recursive`/`class_alias`/`class_implements`/`class_parents`/`register_shutdown_function`）
23. `phase2_task5_4_ref_numeric_spl_and_reflection_constant`（非参照関数の参照代入・参照渡し・非変数参照返却時の Notice 互換、先頭数値文字列演算警告・スカラー添字アクセス互換、`ReflectionConstant`、`ArrayIterator`、`ArrayObject`、無名クラス `class@anonymous` 命名）

### 3.4 PHP 既存回帰テストスイート ＆ PHPT ベンチマーク（Task 5.11 最終検証済み）
- **`package\ALL_PHP_v3_12_test.ps1 -Installed`**: **716 / 716 passed; 0 failed**
- **`package\ALL_PHP_v3_20_test.ps1`（`ALL_integrated_install.ps1` 内 PHP baseline 連鎖）**: **965 / 965 passed; 0 failed**
- **`package\ALL_PHP_phase2_3_test.ps1`（Phase 2 & Phase 3 検証）**: **28 / 28 passed; 0 failed**（+ 多言語 Phase 2/3 ポリグロット 19件）
- **公式 PHPT `tests\lang`（`D:\ALL\docs\phpt_lang_report.json`）**:
  - 総数 294件（実行対象 282件 / `SKIPIF` 12件）
  - **PASS**: **238件（実行対象比 84.40%、Task 5.6 の 208件 / 73.50% から +30件 / +10.90pt 向上）** / **FAIL**: 24件 / **UNSUPPORTED**: 20件（693.6540秒）
- **公式 PHPT `Zend` サンプル（`--limit 300`, `D:\ALL\docs\phpt_zend_report.json`）**:
  - 総数 300件（実行対象 298件 / `SKIPIF` 2件）
  - **PASS**: **172件（実行対象比 57.72%、Task 5.6 の 139件 / 46.64% から +33件 / +11.08pt 向上）** / **FAIL**: 103件 / **UNSUPPORTED**: 23件（847.9071秒）

---

## 4. 技術的制約・設計上の重要ルール

1. **日本語対応・推測補完の厳禁**:
   - ユーザーへの報告は日本語で行うこと。
   - 仕様にない独自挙動の推測実装や指示範囲外の勝手な拡張を行わず、仕様判断が必要な点は必ずユーザーに仰ぐこと。
2. **公式 `php.exe` への実行委譲禁止**:
   - PHP コードの実行は 100% ALL 側の実装で行う。`php.exe` はテスト期待値検証（オラクル比較）のみに使用する。
3. **PowerShell スコープとバイナリ安全性の罠（既存バグ修正知見）**:
   - **ラムダ内変数スコープ**: PowerShell の `[regex]::Replace(..., { ... })` やスクリプトブロック呼び出し内部では `$script:` スコープは呼び出し元ローカルと共有されない（例：`sprintf` は `$state['SprintfIndex']` を使用、`unserialize` は再帰スクリプトブロック内で `$script:unserPos` を使用）。関数リテラルの再帰ではローカル変数がシャドウされる点に注意すること。
   - **リプレイ静音 (`GeneratorReplayMute`)**: ジェネレータは先頭から `TargetStep` までリプレイする方式のため、`Write-PhpBytes` で `$state.GeneratorReplayMute -gt 0` を必ず検査する。また、全ての `catch` 節で `(Test-PhpCliExit $_)` と並んで `(Test-PhpGeneratorYield $_)` を再スローさせている。新しい `try/catch` をエンジン内に追加する際はこのガードを欠かさないこと。
   - **ファイル末尾まで `<?all ... ?>` やインラインブロックが正しく動くよう正規表現を保護**: Python の生成スクリプトで `\b`, `\?`, `\|`, `\.` を生文字列 `r"""..."""` にすること。
   - **PowerShell 5.1 対応**: 一部スクリプトは `ConvertFrom-Json` 等の PowerShell 5.1 差異を考慮して記述されている。`ALL_preflight.ps1` の構文チェック（PowerShell Parser）に必ず通すこと。
4. **既存テスト互換（特に `ALL_module_v0_7_test.ps1` と CLI 厳密エラー）**:
   - `ALL_module_v0_7_cases.json` のケース `"Extension rejected"` は `import "data.php"`（`data.php` ファイルが存在しない状態）に対して `"Expected .all module"` エラーを要求する。そのため `ALL_v1_0_adapter.ps1` の `Resolve-AllModulePath` は**対象ディレクトリ配下に `.php` ファイルが実在する場合のみ PHP モジュールとして受理し、存在しない `.php` パスには `"Expected .all module"` を投げる**設計になっている。絶対にこの条件を緩めないこと。
   - CLI / 非CLI 診断エラー互換（`Throw-PhpStrictCompileError` の `$legacyMessage` 等）を壊さないこと。
5. **関数実装リストの整合性（`$phpBuiltinNames` と `Invoke-PhpFunction`）**:
   - Task 5.1 にて未実装だった13関数（`soundex`, `func_num_args`, `func_get_args`, `func_get_arg`, `settype`, `get_class_vars`, `substr_replace`, `chunk_split`, `wordwrap`, `quotemeta`, `addslashes`, `stripslashes`, `array_diff_assoc`）はすべて `ALL_PHP_v3_12_adapter.ps1` に実装完了済み。今後も新規関数を追加する際は `$phpBuiltinNames` と `Invoke-PhpFunction` の双方を必ず一致させること。
6. **パッケージ更新・デプロイの鉄則**:
   - `package\` 配下を変更したら必ず `SHA256SUMS.txt` を更新し、`ALL_preflight.ps1 -CompileCSharp` → `ALL_integrated_install.ps1` の順で `D:\ALL` 本番ファイルへ反映すること（`ALL_integrated_install.ps1` は成功時・ロールバック時ともに `.bak.<guid>` を残さず削除する）。

---

## 5. 未完了タスクと次フェーズの具体的アクションプラン

### 5.1 全体ロードマップ（Phase 5 以降）
1. **公式 PHP 8.5.12 PHPT (22,280件) 差分テストの自動実行基盤確立** (`all_runner.exe run-phpt`: Task 5.1 で実装・`tests\lang` ベースライン測定完了)
2. **PHPT 結果に基づく PHP 8.5 言語仕様・標準ライブラリのカバレッジ拡大**（Task 5.2 以降）
3. **Rust エンジン（`all_engine.dll`）側へのホットパス・ネイティブVM/Zend拡張ブリッジの段階的移行**
4. **他主要言語（Python / JavaScript / C# / Rust 等）の Universal Polyglot Bridge 対応**

### 5.2 完了済み（Task 5.1）と次タスク（Task 5.2）
- **Task 5.1（完了）**:
  - `ALL_PHP_v3_12_test.ps1 -Installed` (716/716)、`ALL_PHP_v3_20_test.ps1` 連鎖 (965/965)、未実装13ビルトイン完遂＋`ALL_PHP_phase2_3_test.ps1 -Installed` (20/20)、`all_runner.exe run-phpt` 実装、`tests\lang` ベースライン測定 (294件中 150 PASS / 52 FAIL / 11 SKIPIF / 81 UNSUPPORTED)、および `D:\ALL` 一元化クリーン移行を完了。
- **Task 5.2（完了：高優先度 PHP 8.5 文法・標準機能の拡張＋`tests\lang` / `Zend` PHPT 計測）**:
  - **文法・OOP拡張**: マジック定数 (`__FUNCTION__`, `__CLASS__`, `__TRAIT__`, `__METHOD__` / `Trait` 内解決対応)、`var` プロパティ修飾子＆カンマ区切り宣言、祖先の `private` プロパティ分離保存（`PrivateProps`）＆オブジェクト `unset` ダンプ修正、動的 `new $cls()` / `new ($expr)()`、無名クラス（`new [#[...]] [readonly] class (...) extends ... implements ...`）、動的メンバアクセス（`$obj->$p`, `$obj->{$e}()`, `$cls::$m()`）、トップレベル `static` 変数、`list()`・スキップ・参照・`foreach` 分割代入、複雑文字列補間（`{$expr}`, `${expr}`, CLI/診断限定 `"$a[0]"`/`"$obj->p"`）。
  - **標準ライブラリ拡張**: 配列内部ポインタ（`current`/`pos`/`key`/`next`/`prev`/`reset`/`end` + `array_walk`/`array_walk_recursive`）、出力バッファ（`ob_start`/`ob_get_contents`/`ob_end_clean`/`ob_get_clean`/`ob_clean`/`ob_flush`/`ob_end_flush`/`ob_get_flush`/`ob_get_length`/`ob_get_level`, `PHP_OUTPUT_HANDLER_*`, 終了時フラッシュ）、イントロスペクション等（`get_declared_classes`/`interfaces`/`traits`, `get_defined_functions`/`constants`/`vars`, `zend_version`, `debug_backtrace`, `debug_print_backtrace`, `set_time_limit`, `define('::')`, `constant('Cls::CONST')`, Windows 大文字小文字非区別 `SourceFilesSet`）。
  - **ランナー＆性能改善**: `all_runner.rs` にて `EXPECTF` 診断行前空行正規化 (`normalize_diag_newlines`) と `MaxSteps = 25000` を実装、さらにアダプタ内の静的定数・ビルトイン名・正規表現・プレリュードクラス/インターフェース登録キャッシュ（`$script:ALLPhpPreludeClassesCacheV3` 等）によりベンチマーク実行を大幅高速化・決定論化。
  - **検証結果**: ALL 統合 527/527、Phase 2/3 **21/21**、v3.12 **716/716**、v3.20 **965/965**（すべて 0 failed、`.bak.*` 0件）。PHPT `tests\lang` は **179/283 (63.25%)**（+29件/+10.25pt）、`Zend --limit 300` は **53/298 (17.79%)** を記録。
- **Task 5.3（完了：PHP 8.4/8.5 非対称可視性・引数展開・`ArrayAccess` 短絡・`assert()`・標準関数群の拡張）**:
  - **文法・OOP拡張**: `Is-PhpRefCell` の定義順序修正（コンパイル時診断での未定義参照解消）、非対称可視性 (`public(set)`, `protected(set)`, `private(set)`) の構文解析・コンパイル検証・`Assert-PhpSetVisibility` による直接代入/間接添字変更/参照取得/未初期化配列自動初期化/`unset`/`__set`/`__unset` 連携、プロパティフック (`get`/`set`) 前の `#[...]` アトリビュートと `final` 修飾子対応、`Get-LValue` の未初期化型付きプロパティ `Error` 化、`__toString()` 未実装オブジェクト変換エラー整合、`__debugInfo()` の `var_dump` / `print_r` 対応。
  - **展開・配列アクセス・アサーション**: `Read-Arguments` / `Expand-PhpSpreadValue` による関数・メソッド・クロージャ・コンストラクタ・`__call`/`__callStatic` での `...$expr` 引数展開および `Generator`/`Traversable` 展開対応、`Get-PhpCliQuietPath` の多次元 `ArrayAccess` (`offsetExists`/`offsetGet`) 短絡および未初期化型付きプロパティ対応（`isset` / `empty` / `??`）、`assert()` と `zend.assertions` / `assert.exception` の `ini_set` 連携。
  - **標準ライブラリ拡張**: `strstr` / `strchr` / `stristr`, `rand` / `mt_rand` / `random_int` / `srand` / `mt_srand`, `array_merge_recursive`, `class_alias`（`Test-PhpInstanceOf` 連携）/ `class_implements` / `class_parents`, `register_shutdown_function`（正常終了および `exit`/`die` 時の `Invoke-PhpShutdownFunctions` 実行）。
  - **検証結果**: ALL 統合 **527/527**、Phase 2/3 **22/22**、v3.12 **716/716**、v3.20 **965/965**（すべて 0 failed、`.bak.*` 0件）。PHPT `tests\lang` は **182/283 (64.31%)**（+3件）、`Zend --limit 300` は **97/298 (32.55%)**（53/298 = 17.79% から **+44件 / +14.76pt**）へ向上。
- **Task 5.4（完了：参照/数値/添字パリティ、`ReflectionConstant`・`ArrayIterator`・`ArrayObject`・`EXPECTF` 正規化）**:
  - **ランナー改善 (`all_runner.rs`)**: `match_expectf` でパターンに `Stack trace:` が含まれない場合、コンパイルエラー末尾の `\nStack trace:\n#0 {main}` を正規化して比較するよう修正し、再ビルド・配備。
  - **参照・数値・添字パリティ (`ALL_PHP_v3_12_adapter.ps1`)**: CLI/診断モードでの非参照関数への参照代入・参照引数渡し・非変数参照返却の `Notice` 互換、`To-Number` の先頭数値文字列警告・不正オペランド `TypeError`、`Get-PhpArrayItem` のスカラー添字アクセス警告（`null` 返却）および通常オブジェクト添字 `Error`、オブジェクト `UnsetProps` 追跡による `__set`/`__unset` 厳密分岐、`Get-PhpCliQuietPath` による連鎖 `isset($aa[0]->foo)` 短絡、`zend.assertions` の `0 <-> 1` ランタイム切替と `-1` 固定、`assert` スタックトレース 2引数積載、`Expand-PhpSpreadValue` の型名付き `TypeError`、単一無名クラス名 `class@anonymous`。
  - **プレリュード追加クラス**: `ReflectionConstant`、`ArrayIterator`、`ArrayObject`（および共通変換ヘルパー `ConvertTo-PhpContainerArray`、`V4` キャッシュ更新）。
  - **検証結果**: ALL 統合 **527/527**、Phase 2/3 **23/23**、v3.12 **716/716**、v3.20 **965/965**（すべて 0 failed、`.bak.*` 0件）。PHPT `tests\lang` は **186/283 (65.72%)**（`UNSUPPORTED` 63→36）、`Zend --limit 300` は **118/298 (39.60%)**（`UNSUPPORTED` 97→75、+21件 PASS）へ向上。
- **Task 5.5（完了：演算子 `TypeError` パリティ・トップレベル関数ホイスト・添字自動初期化・タイムゾーン/ロケール/`json_encode` CLIオプション）**:
  - **演算子・型パリティ (`ALL_PHP_v3_12_adapter.ps1`)**: `Get-PhpBuiltinTypeName` に `Closure` 判定を追加し、`Test-PhpCanConvertToNumber` / `Convert-PhpBinaryNumericOperands` / `Convert-PhpUnaryNumericOperand` を実装して二項・単項・複合代入演算子の `Unsupported operand types: <left> <op> <right>`（および単項 `<op><type>`）を PHP 8.5 準拠形式へ統一、`+=` 配列和結合にも対応。
  - **トップレベル関数ホイスト**: `Throw-PhpUserFunctionRedeclaration` を追加し、ルート `$statements` および `Invoke-PhpLoadedUnit` 事前スキャンでトップレベル `functiondef` を先頭登録（`Hoisted = $true`）し、宣言前呼び出しに対応。
  - **添字自動初期化・アクセス/可視性エラーパリティ**: `Set-LValue` `'index'` で中間添字/プロパティの `null` および `false`（非推奨診断付き）を自動配列初期化、`Set-PhpArrayItem` での非配列代入エラー、`Cannot use [] for reading`（空添字読み取り）、`Call to a member function ... on ...`（非オブジェクトメソッド呼び出し）、`Assert-PhpVisibility` の `Error` 化、クラスメンバ修飾子重複の `CompileError` 化（`Throw-PhpStrictCompileError`）を実装。
  - **組み込み関数・定数拡張 (`V4`/`V5` キャッシュ)**: `func_get_arg*` / `func_num_args` のグローバルスコープ呼び出し文言を `cannot be called from the global scope` へ更新、`date_default_timezone_set` / `date_default_timezone_get` / `setlocale` および `LC_*` / `JSON_*` 定数を追加、CLI 実行時の `json_encode($value, $flags, $depth)`（`JSON_HEX_*` / `JSON_FORCE_OBJECT` / `JSON_UNESCAPED_SLASHES` / `JSON_PRETTY_PRINT` / `JSON_UNESCAPED_UNICODE` / `$depth`）に対応（非 CLI の既存 fail-closed ガードは維持）。
  - **検証結果**: プリフライト（構文103・SHA-256 221・C#）合格、ALL 統合 **527/527**（ベースライン523 + debug-source 4）、Phase 2/3 **24/24**（テスト #24 追加）、v3.12 **716/716**、v3.20 **965/965**（`.bak.*` 0件）。PHPT `tests\lang` は **200/283 (70.67%)**（Task 5.4 比 +14件 PASS、`UNSUPPORTED` 36→31）、`Zend --limit 300` は **131/298 (43.96%)**（+13件 PASS、`UNSUPPORTED` 75→54）へ向上。
- **Task 5.6（完了：単項演算/`++`/`--` パリティ・可視性とマジックメソッド・修飾子検査・`json_decode`・可変長展開高速化）**:
  - **単項演算・インクリメント/デクリメント (`ALL_PHP_v3_12_adapter.ps1`)**: `Convert-PhpUnaryNumericOperand` を更新して単項 `+`/`-` の `Unsupported operand types: <type> * int` と単項 `~` の `Cannot perform bitwise not on <type>` を実装。`Step-PhpIncrementDecrement` を追加し、`++`/`--` の PHP 8.5 挙動（`int`/`float`/`null`/`bool` 警告・数値文字列・非数値英数字繰り上がりと非推奨通知・配列/オブジェクト `TypeError`）に対応。
  - **可視性・マジックメソッド・クラス/呼び出し検査**: `Test-PhpVisibilityAllowed` / `Assert-PhpVisibility` に `$memberKind`（`property` / `method` / `constant`）・`$memberName` を導入して PHP 8 準拠のエラー文言と共通祖先由来の兄弟 `protected` メソッドアクセスを実装し、不可視メンバへの `__get` / `__set` / `__call` / `__callStatic` フォールバックを追加。さらにクラス/メンバ修飾子重複・`abstract final` の `CompileError` 検査、クラス外 `self`/`parent`/`static` の `Error`、`func_num_args` / `foreach` 警告メッセージ改善、`json_decode` 第3/4引数（`$depth` / `$flags` の `JSON_OBJECT_AS_ARRAY`）を実装。
  - **展開処理の高速化**: `array_fill` の配列生成をインライン化し、フレーム引数コピーを `Resolve-PhpFramePassedArgs` で遅延評価化するとともに、非参照可変長引数展開 `$varargs` の直接挿入を実装。
  - **検証結果**: プリフライト（構文103・SHA-256 221・C#コンパイル）合格、`ALL_integrated_install.ps1` で ALL **527/527**（ベースライン523 + debug-source 4）・多言語 Phase 2/3 **19件**・PHP ベースライン v3.20 **965/965**・PHP Phase 2/3 **25/25**（テスト #24 更新・#25 追加）合格、v3.12 **716/716** 合格（`.bak.*` 0件）。公式 PHPT `tests\lang` は **208/283 (73.50%)**（total 294 / fail 44 / skipif 11 / unsupported 31 / 745.8377秒、Task 5.5 比 +8件 PASS、1040.91s→745.84s）、`Zend --limit 300` は **139/298 (46.64%)**（total 300 / fail 109 / skipif 2 / unsupported 50 / 768.8799秒、Task 5.5 比 +8件 PASS、2015.70s→768.88s）。
- **Task 5.7（完了：`readonly` 非CLI/非診断エラー整合）**:
  - `ALL_PHP_v3_12_adapter.ps1` の `Set-LValue` `'property'` にて、`-not $isCli -and -not $PhpDiagnostics` のクラス外 `readonly` 初期化で従来エラー文言を維持（716/716 PASS、Phase 2/3 25/25 PASS）。
- **Task 5.8（完了：双方向ポリグロット完全接続・Hooks/可視性/バイナリ往復）**:
  - `Ensure-AllPolyglotContext` での `$phpBuiltinNames` 共有（`Test-AllCanCallPhp` 側で ALL 予約数学関数を除外）、`PhpBytes` Base64 ラウンドトリップ (`__ALL_PHP_B64__:`)、`Test-PhpPolyglotEqual`、`[Console]::Error` キャプチャ。
  - ALL 側のプロパティ読み書き (`Get-AllListItem` / `set-index`)・メソッド呼び出しを PHP 側 `Get-LValue` / `Set-LValue` に接続し、プロパティフック・`readonly`・`private(set)` を ALL 経由でも厳密強制。ポリグロット経由の PHP 例外も `try/catch` で捕捉可能化（Test #26 追加、26/26 PASS、716/716 PASS）。
- **Task 5.9（完了：評価順序・参照 Notice 行番号・型ホイスティング・コロン構文）**:
  - パーサでの AST `Line` 付与、`->${expr}` / `::${expr}` 動的メンバ構文、`Read-PhpColonBlock` / `Read-PhpColonElseIfTail` による `if/elseif/else/endif`, `while/endwhile`, `for/endfor`, `foreach/endforeach`, `switch/endswitch`（+ `case ;` 非推奨警告）対応。
  - `Resolve-PhpPreEvaluatedTarget` による `=` / `??=` 代入の LHS 事前評価（評価順序および不要な再 `Get-LValue` 回避）、`Set-LValue` 複合添字の重複読み取り排除とスカラー配列化 `Error`、`Invoke-PhpCallable`/`Invoke-PhpReferenceCall`/`assign_ref` での呼出元行番号復元・左辺スロットエラー優先（`PendingNonRefNotice` 遅延通知）、およびトップレベル型宣言の安全なマルチパス・ホイスティング実装（Test #27 追加、27/27 PASS、716/716 PASS）。
- **Task 5.10（完了：匿名クラス・`ErrorException`・`IteratorAggregate`・属性スコープ・標準関数拡張）**:
  - 無名クラス命名規則（親/第1インターフェース継承、`$isCli` または接頭辞付き時の `\0file:line$hex` 付与、Test #23 互換維持）。
  - `trigger_error(..., E_USER_ERROR)` の PHP 8.4 非推奨警告＋CLI Fatal 終了、`Throwable::getTrace()` + `Build-PhpStackTraceArray`、`ErrorException::__construct`/`getSeverity()`、`Write-PhpDiagnostic` 内エラーハンドラ実行時の `ActiveBuiltinFrame` 一時スタック積載。
  - `Resolve-PhpAggregateIterator` による `IteratorAggregate::getIterator()` 戻り値検証の統一、`fopen` / `fclose` / `highlight_string` / `show_source` / `highlight_file` / `localeconv`（`setlocale` `LC_NUMERIC` 連携）追加。
  - `ReflectionObject` / `ReflectionClassConstant` / `ReflectionClass::getReflectionConstant`、トレイトのリフレクションと `self::` 未定義エラー、クラス定数属性引き継ぎ、`ReflectionAttribute` のクラス/クロージャ/バリデーション評価スコープ追従、`Closure::bindTo` 実装（Test #28 追加、28/28 PASS、716/716 PASS）。
- **Task 5.11（完了：PHPT ランナー `--STDIN--`/`--EXPECTREGEX--` 対応・補助ビルトイン・最終ベンチマーク）**:
  - `ALL_PHP_v3_12_adapter.ps1` (`V7`) へ `file_get_contents`, `file_put_contents`, `php_strip_whitespace`, `unlink`, `getenv` を追加。
  - `all_runner.rs` へ `--STDIN--` パイプ、`--CLEAN--` 後処理、純 Rust 標準ライブラリ製 Thompson NFA `--EXPECTREGEX--` マッチャ、`phpt`/`run-phpt` サブコマンド受付を追加し Release ビルド・配備・全検証（構文103 / SHA-256 221 / C# / ALL 527件 / PHP v3.20 965件 / 多言語 19件 / Phase 2/3 28件 / v3.12 716件）を完遂。
  - 公式 PHPT ベンチマーク：`tests\lang` **238/282 (84.40%)**（Task 5.6 比 +30件）、`Zend --limit 300` **172/298 (57.72%)**（Task 5.6 比 +33件）。
- **今後の拡張候補**:
  - `tests\lang`（24件 fail / 20件 unsupported）および `Zend`（上位残因：参照引数の型追跡、プリティプリント付き `assert()`、静的配列キーの定数評価、`Closure` ビルトインメソッド群、`DateTime` 等未実装標準クラス・関数の順次拡充）。
  - **運用ノート**: PHPT 大規模スイート (`Zend` 全体 5,395件等) は全実行すると4コアで約40〜60分要するため、定期確認は `--limit 300` 等を使用し、必ず他ベンチマークとは直列で実行すること。

### 5.3 ビルド・検証コマンド集（`D:\ALL` 統一版）

```powershell
# 1. Rust ネイティブエンジン & 並列 PHPT ランナーのリビルド
cargo build --release --manifest-path "D:\ALL\native\all-engine\Cargo.toml"

# 2. 公式 PHPT ディレクトリのスキャン／実行
D:\ALL\all_runner.exe scan-phpt "D:\ALL\oracle\php-8.5.12-tests"
D:\ALL\all_runner.exe run-phpt "D:\ALL\oracle\php-8.5.12-tests\tests\lang" --report "D:\ALL\docs\phpt_lang_report.json"

# 3. パッケージ構文・SHA-256・C#プリフライト検査
powershell -NoProfile -ExecutionPolicy Bypass -File "D:\ALL\package\ALL_preflight.ps1" -CompileCSharp

# 4. 本番デプロイ ＋ ALL 527件 ＋ Phase2/3 20件 一括検証
powershell -NoProfile -ExecutionPolicy Bypass -File "D:\ALL\package\ALL_integrated_install.ps1"

# 5. PHP 回帰スイート (v3.12 716件 / v3.20連鎖 965件) の確認
powershell -NoProfile -ExecutionPolicy Bypass -File "D:\ALL\package\ALL_PHP_v3_12_test.ps1" -Installed
powershell -NoProfile -ExecutionPolicy Bypass -File "D:\ALL\package\ALL_PHP_v3_20_test.ps1"

# 6. Phase 2 / 3 検証スイート単体実行（本番環境向け）
powershell -NoProfile -ExecutionPolicy Bypass -File "D:\ALL\package\ALL_PHP_phase2_3_test.ps1" -Installed
```
