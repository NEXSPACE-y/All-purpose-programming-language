# COMPAT_TARGET — PHP 互換の対象基準

最終更新：2026-11-10（JST）

## 1. 所有者の決裁記録（2026-11-10）

| 項目 | 決裁 |
|---|---|
| 対象 PHP 版 | **PHP 8.5.12（64bit）** |
| 進め方 | まず言語コア（変数・演算子・配列／関数・スコープ／オブジェクト指向）を公式 PHP との差分試験で VERIFIED にする。標準ライブラリ全体・拡張・Web SAPI・Composer／実アプリは後続フェーズとし、それまで `NOT_COMPLETE` として管理する |
| リポジトリ | 公開のまま。ライセンスは未設定（現状は外部利用を想定していない） |
| 正本 | `ALL_PHP_v3_12_1_property_hooks_fix_20261104.zip`（所有者のローカル生成 ZIP は現存しないため） |

## 2. 未決裁（確定するまで「PHP 全体 100%」は宣言しない）

- 対象 SAPI の範囲（現時点で検証対象は CLI のみ）
- 対象拡張の一覧と、任意のネイティブ拡張の ABI 互換を要求するか
- 対象 OS（現時点の基準は Windows 11 / Windows PowerShell 5.1 のみ）
- 値モデル（int／float／文字列／参照）の基盤変更方式

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
