# ALL PHP v3.5 候補 — 3領域の互換拡張（2026-11-02）

## 判定（必読）

**変数・演算子・配列／関数・スコープ／OOPの互換実装を拡張した候補版です。3領域の「完全互換認定」は未達成です。**

v3.4の227件はユーザーWindows PowerShell 5.1実機で227/227合格（報告済）。今回のv3.5はWindows未実行のため **329件の実行合格を宣言できません**。同一PHPコードに対する94件の期待値はPHP 8.4.24 CLI実行で確認済みです。明示的に未対応の8件は「誤って実行しない」ガードでありPHP互換合格数ではありません。

## 保全事項

- v3.4以前のZIP内すべての元ファイル・README・テストを変更せず同梱。候補は独立した`ALL_PHP_v3_5_adapter.ps1`。
- ALL本体言語処理系・CLI・SQLite・HTTP・C#・PHP旧アダプタには手を加えません。新しい実行時依存も追加しません。
- テストは新規の`ALL_PHP_v3_5_test.ps1`で**旧227件も含め**実行します。
- インストーラーの`ALL_PHP_v3_5_install.ps1`は任意。既存アダプタをバックアップし、更新後の試験失敗でロールバックします。

## 追加実装と対象

| 領域 | 今回追加した機能 |
| --- | --- |
| 変数・演算子・配列 | 前置／後置の数値++/--、整数ビット演算、シフト、三方比較、PHP配列の和集合、再帰的な配列等価/厳密等価、配列アンパック、配列分解代入の一部、globalスコープの配列代入 |
| 関数・スコープ | デフォルト引数、可変長引数、ユーザー関数/メソッドの名前付き引数、global、関数内static、無名関数、値キャプチャuse、アロー関数、関数値の呼び出し |
| OOP | extends継承、オーバーライド、親メソッドとコンストラクタ呼出し、public/protected/private可視性の基本制御、staticプロパティ/メソッド、クラス定数、instanceof、クローンと__clone、stdClass生成 |

**注意**：PHP本体の巨大な仕様をすべて網羅したわけではありません。新機能には同一コードの限定テストを用意しましたが、動的な動作の完全一致を証明するものではありません。

## 新規テスト一覧

| ケース集合 | 件数 | 基準 |
| --- | ---: | --- |
| PHP v3.1〜v3.4＋過去parity/guard | 227 | Windowsでv3.4合格済み。v3.5は再試験必要 |
| 変数・演算子・配列 | 40 | PHP 8.4.24出力取得済み。ALL未実行 |
| 関数・スコープ | 27 | 同上 |
| OOP | 27 | 同上 |
| 明示的な未対応構文の拒否 | 8 | ALL未実行。公式PHP互換ではない |
| **合計** | **329** | **v3.5のWindows試験未実施** |

## Windows PowerShell 5.1非破壊検証（推奨）

以下は実際にインストールされた`$HOME\ALL`に変更を加えません。ZIPはダウンロード済みである必要があります。

```powershell
$zip = Get-ChildItem (Join-Path $HOME 'Downloads') -Filter 'ALL_PHP_compat_v3_5_candidate_20261102*.zip' -File |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $zip) { throw 'ALL PHP v3.5 のZIPがDownloads内に見つかりません' }
$dest = Join-Path $env:TEMP ('ALL_php_v3_5_validation_' + [guid]::NewGuid().ToString('N'))
Expand-Archive -LiteralPath $zip.FullName -DestinationPath $dest -ErrorAction Stop
$test = Get-ChildItem -LiteralPath $dest -Recurse -File -Filter 'ALL_PHP_v3_5_test.ps1' |
    Select-Object -First 1
if (-not $test) { throw 'v3.5 テストスクリプトがZIP内に見つかりません' }
$root = $test.DirectoryName
& (Join-Path $root 'ALL_preflight.ps1') -CompileCSharp
if (-not $?) { throw '事前検査が失敗したため中止します' }
& $test.FullName
```

- 想定する合格時の最終表示は`ALL PHP v3.5 (direct candidate): 329/329 passed; 0 failed`。
- この数値は**期待値**であり実機で合格した事実ではありません。
- `ALL_preflight.ps1`のC#コンパイルは実行環境にコンパイラが必要です。不要なら`-CompileCSharp`を外して試験可能です。
- **失敗したら既存環境は更新しないこと**。エラーログを開発チャットに渡してください。

## 合格後の任意インストール（既存環境を書き換える）

```powershell
& (Join-Path $root 'ALL_PHP_v3_5_install.ps1')
```

- `$HOME\ALL\languages\php.ps1`のみバックアップ付きで更新。ALL独自言語はそのまま。
- 事前・事後の329件、旧v3.2互換テストを実行。失敗すると元アダプタへロールバック。
- **本体の523/527件の全統合回帰テストはこのインストーラーだけでは実施しません**。

## 完全互換を認定できない理由

以下は**今回指定された3領域にまだ属する未達事項**です。次回対象の標準ライブラリ等と混同しないこと。

- **変数・演算子・配列**：`&`参照・参照配列/循環、可変変数、全ビット代入演算、int/float厳密区別と境界条件、PHPと同じエラー・警告・評価順序、バイナリ文字列と配列キー全境界、完全COW最適化。
- **関数・スコープ**：参照引数/戻り、参照キャプチャ、型付き引数と戻り型、関数内関数、名前空間、ジェネレータ、named arguments全境界、`func_get_args`等の詳細。
- **OOP**：interface/trait/enum/abstract/final/readonly、型付きプロパティ、魔術メソッドの大半、遅延静的束縛全境界、継承とprivateプロパティ同名衝突、動的プロパティ警告、完全な可視性やシグネチャ互換性。

PHPと仕様互換になるにはPHP8.4の公式仕様・実エンジンと両者の差分検証が必要です。機能の実装、静的検査、PHP oracleの取得、ALL候補の実行合格、3領域の完全互換認定は区別します。

**状態：開発継続中。既存ALLインストール環境には未反映。PHP完全互換未達。**
