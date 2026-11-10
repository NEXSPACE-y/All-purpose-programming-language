# ALL PHP互換拡張 v3.3 — 開発候補（2026-11-02）

**正式なPHP完全互換版ではありません。既存ALLのPHPアダプタのみを対象とする独立した開発候補です。**

## 1. ベース・変更範囲

- ベース: `ALL_phase1_source_debug_candidate_20261102.zip`（現行候補の全ファイルを保持）。
- 変更する実装: 既存の `ALL_PHP_v3_2_adapter.ps1` は保持し、新規 `ALL_PHP_v3_3_adapter.ps1` を追加。
- `ALL_v1_0_adapter.ps1`（ALL独自言語）、`ALL_ConcurrentGateway.cs`、SQLite、CLI、PHP以外の旧ファイルは変更なし。
- 既存の統合インストーラー `ALL_integrated_install.ps1` は **PHPアダプタをインストールしない** ため、本版では新規 `ALL_PHP_v3_3_install.ps1` を用いる。
- PHP本体（php.exe等）をアダプタの実行エンジンとして呼び出さない。既存のALL独自PHP処理系を拡張する方式を維持する。
- 互換対象バージョンの最終決定はユーザー判断。既存v3.2がPHP 8.5相当の機能を一部実装していることから、基礎構文は8.x共通部分を優先。

## 2. 今回追加した実装（コードは追加済み、Windowsでの実行確認待ち）

| 分野 | 内容 | 主な制限 |
| --- | --- | --- |
| 制御文 | `switch/case/default`、フォールスルー、`break`、関数内`return` | `case ...;`表記、複数階層の`break N`未対応 |
| 式 | `??=` の変数／配列キーへの代入、右辺の遅延評価 | PHP汎用代入式・深い配列自動生成・参照代入未対応 |
| アクセス | `?->` の直接プロパティ／メソッド呼出し、null時の引数評価抑止 | 深いチェーン全体の伝播、動的メンバー名未対応 |
| 文字列 | ダブルクォートの `$name` / `{$name}` 補間、基本エスケープ | 複雑な配列・オブジェクト補間、バイナリ文字列完全性、警告一致は未対応 |
| 配列 | `array_push/pop/shift/unshift/reverse/merge/slice` | PHP参照渡し規則、全てのキー境界値や型の完全一致は未認定 |

既存の `array_keys` 等も残る。エンジン・アーキテクチャの置換や依存パッケージ追加はない。

## 3. 検証データ

- **新規49件**：コンテナ上の PHP 8.4.24 CLI の実行出力から期待値を自動生成。PHP参照側は **49/49 実行成功**。
- **旧版95件**：v3.1.1の45件とv3.2の50件を保持。8.4環境に存在しない `array_first/array_last` 4件を除き、旧テストのうち91件でPHP 8.4 CLIとの出力一致を確認（エラー期待のケースはエラー発生で照合）。
- **防御的拒否3件**：未実装文法を誤動作で隠さずエラーにすることを検査。
- **過去のPHP対照17件**：`ALL_math_cases.json` の `mode=pair` を追加で実施。
- 候補直実行テストは合計 **164件**（45＋50＋49＋3＋17）。
- **重要**：現在の開発用コンテナに PowerShell がないため、今回のALLアダプタに対する164件の実行結果は **未検証**。静的な括弧・引用符の照合のみ実施。ユーザーWindows実機で確認する必要がある。
- PHP 8.5ランタイムでの差分実行、PHP警告・例外クラス名・終了コード・バイト単位出力の厳密照合は未実施。
- 既存523件、Phase 1候補の追加4件は今回再実行していない。旧合格報告を新候補の合格結果へ流用しない。

## 4. Windowsで既存ALLを変更せず試す

ダウンロードしたZIPを任意の場所に展開し、`ALL_PHP_v3_3_test.ps1` のあるフォルダを `$root` に指定する。

```powershell
$root = "C:\実際の展開先\ALL_PHP_compat_v3_3_candidate_20261102"
& "$root\ALL_preflight.ps1"
& "$root\ALL_PHP_v3_3_test.ps1"
```

`$root` の推測で繰り返し失敗しないよう、ファイルを直接探す場合は以下を使う。

```powershell
$test = Get-ChildItem "$HOME\Downloads" -Filter 'ALL_PHP_v3_3_test.ps1' -File -Recurse |
    Select-Object -First 1
if (-not $test) { throw 'ZIPを展開し、展開フォルダを確認してください' }
& (Join-Path $test.DirectoryName 'ALL_preflight.ps1')
& $test.FullName
```

**`ALL_PHP_v3_3_test.ps1`（オプションなし）はインストール済みPHPを読み込まず候補の `Run` を直接呼び出す。** 本体や既存PHPの上書きは一切行わない。

## 5. 全件合格後のPHPのみ更新（任意）

```powershell
& (Join-Path $root 'ALL_PHP_v3_3_install.ps1')
```

本インストーラーの手順：

1. 静的構文解析・ZIPファイルのSHA-256一致確認。
2. 候補PHPアダプタの独立164件テスト。
3. 既存の `$HOME\ALL\languages\php.ps1` をGUID付きファイル名でバックアップ。
4. **PHPアダプタのみ**差し替え。ALL独自処理系やその他のコンポーネントは変更しない。
5. インストールされたPHPの164件テスト、旧 `ALL_PHP_v3_2_test.ps1`（ALL数学を含む196件）を実行。
6. 不合格・例外発生時は旧PHPアダプタを復元。成功時もバックアップを残す。

**このインストーラーは全523件／527件の統合回帰試験を自動では再実行しない。** PHP以外を含む統合認定には別途全回帰試験が必要。

## 6. 完全互換までの未達事項

詳しくは `PHP_COMPAT_GAP_MATRIX.md` を参照。特にPHPの整数／浮動小数点型の区別（現処理系はdecimalを中心に扱う）、複合代入・式中代入、参照／copy-on-write、例外／Throwable、名前空間、クラス継承・型、クロージャー・ジェネレータ、Composer/拡張機能、Webの実SAPI処理は大きな課題。

**判定：PHP互換開発の継続候補。PHP完全互換・業務品質・Phase終了を宣言しない。**
