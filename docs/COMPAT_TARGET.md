# COMPAT_TARGET — PHP 互換の対象基準

最終更新：2026-11-12（JST）

## 1. 所有者の決裁記録（2026-11-10）

| 項目 | 決裁 |
|---|---|
| 対象 PHP 版 | **PHP 8.5.12（64bit）** |
| 進め方 | まず言語コア（変数・演算子・配列／関数・スコープ／オブジェクト指向）を公式 PHP との差分試験で VERIFIED にする。標準ライブラリ全体・拡張・Web SAPI・Composer／実アプリは後続フェーズとし、それまで `NOT_COMPLETE` として管理する |
| リポジトリ | 公開のまま。ライセンスは未設定（現状は外部利用を想定していない） |
| 正本 | `ALL_PHP_v3_12_1_property_hooks_fix_20261104.zip`（所有者のローカル生成 ZIP は現存しないため） |

## 1.1 所有者の追加決裁（2026-11-12、この開発セッション）

以下は所有者の明示回答による追加要件であり、2026-11-10の記録を置き換えて範囲を縮めるものではない。

| 項目 | 決裁 |
|---|---|
| 第1段階 | PHP 8.5.12の完全互換。CLI・Web実行・標準拡張に加え、既存ネイティブ拡張バイナリの無改変互換も含む |
| 第2段階 | 第1段階の完了後、ALL独自の日英構文でPHP相当の全機能を記述・実行できる水準まで成長させる。PHPとALLの相互呼出し・データ共有も含む |
| 実施順序 | 第1段階 → 第2段階。この2段階が完了するまで他言語へ着手しない |
| PHPの対象版 | PHP 8.5.12（既存決裁を再確認） |
| 対象OS・CPU | Windows 11 x64 と Linux x64 |
| Web SAPI | 内蔵Webサーバー、CGI/FastCGI、Apacheモジュール、LinuxのFPM |
| 基盤設計 | `docs/design/PHP_NATIVE_ABI_DESIGN.md` の案Aを承認。既存C++ツールと固定SDK型定義を使うALL所有ネイティブABI層・値/呼出し境界の候補実装。公式PHP処理系へ委譲しない。案Bの広い実行コア移行や追加依存は未採用 |

現時点の状態は両段階とも **NOT_COMPLETE**。候補回帰の合格、公式テストの一部分の合格、ABI設計書の作成だけでは第1段階を完了扱いにしない。第2段階の実装は第1段階の完了前に開始しない。

既存の公式PHPは引き続き照合専用。既存PHP処理系へ実行を委譲してALLの互換実装として扱う方式は採用しない。新規の基盤方式・依存は仕様書9.1/14の設計決裁に従う。

作業基準は、GitHub mainのv3.12.1取り込みではなく、ローカル `work/php-core-compat` の `9d8171712828a0b57555b8eb1e1ca5c475391244`（v3.16）。既存のインストール済み `C:\Users\rinpa\ALL` は作業対象とは分離する。

## 2. 未確定事項（確定するまで「PHP 全体 100%」は宣言しない）

- Web SAPIの具体的なホスト構成・配置・試験環境（対象SAPIの範囲は上記のとおり決裁済み。既存の実測はWindows CLIのみ）
- 対象拡張の具体的な一覧・バイナリのビルド条件（既存ネイティブ拡張のABI互換を含む要求は決裁済み）
- Linux x64の具体的な配布環境・参照ビルド・試験環境
- 案Aで対応しきれない実行コア・値モデルの追加変更方式（案Bなどは別途設計決裁）

## 3. オラクル（照合用の公式 PHP）

公式 PHP は照合専用であり、ALL の PHP 互換処理系が実行を委譲することはない。

| 項目 | 値 |
|---|---|
| 配布元 | `https://downloads.php.net/~windows/releases/archives/` |
| ビルド | `PHP 8.5.12 (cli) (built: Oct 26 2026 09:50:37) (ZTS Visual C++ 2022 x64)` |
| Zend Engine | v4.5.12 |
| スレッドセーフ | ZTS（Thread Safe） |
| 整数幅 | `PHP_INT_SIZE = 8` |
| OS | Windows（`PHP_OS_FAMILY = Windows`） |
| `php.exe` SHA-256 | `0ac893499799256db6d3a54b0da73692e02311493922e6e4f86a062674a77d66` |
| 設定ファイル | 使用しない（常に `php -n` で実行） |
| 既定値（`-n` 時） | `precision=14`、`serialize_precision=-1`、タイムゾーン `UTC` |

### 配布 ZIP の SHA-256

公式の `sha256sum.txt`（`https://downloads.php.net/~windows/releases/sha256sum.txt`）と 5 本すべて一致。

```
0dacd6484b092b5e9ae9fa3d7f96a937caf9d874eee2d980b68ed3129741144a  php-8.5.12-1-Win32-vs17-x64.zip
c0a8a9a97aea2bda94011a6316a58714ea18421b7f509242bd992d90c66c2b5a  php-debug-pack-8.5.12-1-Win32-vs17-x64.zip
52cb020402c3165e7cb37ec0d96ae43e26997f01d0fdb5474aa92801246810e9  php-devel-pack-8.5.12-1-Win32-vs17-x64.zip
79df191cab418a5277e7ad504143255c7b7ead06a2e6ebfa3b5b24503e94a519  php-test-pack-8.5.12-1.zip
9dac05f72f328afd0a2b0e795a519ae4cb3d056bc3f3b55147bd048bd64e45e8  php-8.5.12-1-src.zip
```

### `php -n -m`（設定ファイルなしで読み込まれるモジュール）

bcmath, calendar, Core, ctype, date, dom, filter, hash, iconv, json, lexbor, libxml, mysqlnd, pcre, PDO,
Phar, random, readline, Reflection, session, SimpleXML, SPL, standard, tokenizer, uri, xml, xmlreader,
xmlwriter, Zend OPcache, zlib

### オラクルの実行条件

```
php -n -d display_errors=stderr -d error_reporting=-1 -d date.timezone=UTC <file>
```

診断（Warning／Deprecated／Fatal）は stderr に分離し、stdout はプログラムの出力だけにする。

## 4. 公式テスト（PHPT）

`php-test-pack-8.5.12-1.zip` に 22,280 本。言語コアに直接関係する主な場所：

| 場所 | 本数 |
|---|---|
| `Zend/tests` | 5,396 |
| `tests/lang` | 294 |
| `tests/classes` | 283 |

採用・除外の判断は今後 `PHP_PHPT_COVERAGE_REPORT.md` に記録する。

## 5. ローカルの配置（リポジトリ外）

- オラクル本体：`C:\Users\rinpa\ALL_php_oracle\php-8.5.12-ts-x64\php.exe`
- 公式テスト：`C:\Users\rinpa\ALL_php_oracle\php-8.5.12-tests\`
