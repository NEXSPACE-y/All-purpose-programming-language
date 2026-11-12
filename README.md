# ALL (ALMIGHTY) — All-purpose programming language

ALL は、最終的にあらゆる既存プログラミング言語との互換を目指す独立した汎用言語処理系です。
現在は Windows PowerShell 5.1 上の独自処理系と、PHP 互換アダプタを開発しています。

**状態：開発中。PHP 完全互換は未達・未認定です。**

## 構成

| パス | 内容 |
|---|---|
| `package/` | 処理系・アダプタ・テスト一式（取り込み基準：v3.12.1。作業ブランチには後続改修を含む） |
| `docs/` | 仕様書 |
| `docs/provenance/` | 基準版の出どころを示すハッシュ記録と検証ログ |
| `reports/` | 入力ハッシュ・実行ログ・差分結果。過去の測定条件と新しい厳密比較を区別する |
| `tools/` | 公式PHPとの比較、要件管理、ABI・Linux環境の調査・検証ツール |

## 基準版（ベースライン）

- 元パッケージ：`ALL_PHP_v3_12_1_property_hooks_fix_20261104.zip`
- SHA-256：`219e225f86fc3c4a00d44e3c4fa4c93b62835e257f4584327e4c1b17dfe6e0d1`
- `main` の取り込みコミット `b281656` は上記ZIPの無改変展開です。後続のローカル開発ブランチの `package/` には改修があるため、正本と検証結果はブランチ・コミット・入力ハッシュで識別します。
- 2026-11-10、Windows PowerShell 5.1 で事前検査と PHP 回帰 716/716 PASS を確認しました
  （`docs/provenance/v3_12_1_validate_ps51_20261110.log`）。
  これは既存テスト集合の合格であり、PHP 完全互換を示すものではありません。

## 検証（インストールせずに実行）

以下は取り込み基準版の検証入口です。作業ブランチの検証済み候補については次節を参照してください。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\package\ALL_PHP_v3_12_1_validate.ps1 -CompileCSharp
```

## 2026-11-12の検証済み候補 v3.17

ローカル `work/php-core-compat` のv3.16（`9d81717`）を基準に、分離作業ブランチ `codex/php-8.5.12-full-compat-20261112` で改修しています。導入済み `C:\Users\rinpa\ALL` と `main` への反映はしていません。

- 名前空間の関数・定数を実行時に解決し、同一参照位置の解決を保持。不在の関数名は固定しない。
- 未定義の関数・first-class callableの解決時点、および内部例外クラスの連続実行時の分離を修正。
- Windows PowerShell 5.1で既存940件を維持し、追加25件と合わせ **965/965 PASS**。
- 追加25例は別プロセスの公式PHP8.5.12とstdout/stderrバイト列・終了コードが一致。
- 初回14プローブは **6/14一致・8差分** が残る。965件合格を完全互換と扱わない。

[最終検証の入力ハッシュとログ](reports/v3_17-validation-20261112-final/README.md)、[連続実行の分離試験](reports/prelude-isolation-20261112-after/README.md)。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\package\ALL_PHP_v3_17_validate.ps1 -CompileCSharp
```

## 2026-11-12の検証済み候補 v3.18

明示的なCLI実行contextを追加し、対応する診断をstderrへ、終了値を呼出し元へ渡す経路を実装しました。exit/die、isset/emptyのoffset評価、対応する構文エラーの診断も修正しています。

- 実packageで **965/965 PASS**。既存940件の定義と期待値は変更していません。
- 別プロセスの公式PHP8.5.12と、選定したCLI14例・exit23例のstdout/stderrバイト列と実終了値が一致。
- 構文98本・SHA212件・C#2件を確認し、package213ファイルの実行前後ハッシュが一致。

[実packageでの検証記録](reports/v3_18-validation-20261112/README.md)。これらは選定した回帰の結果で、PHP全体・CLI全体の完全互換は未達です。

公式PHPの[API参照台帳](reports/php-api-inventory-20261112/README.md)は、観測した13,934件をすべて未検証として記録しています。[base関数の登録照会](reports/php-registration-probe-20261112/run-01/README.md)では参照925件に対し候補は80件true・845件falseでした。登録照会の件数は、関数本体の実装完了数や互換率ではありません。

## 完了条件と開発順序

[所有者の対象決定](docs/COMPAT_TARGET.md)はPHP8.5.12、Windows11x64/Linuxx64、CLI・内蔵Web・CGI/FastCGI・Apache・LinuxFPM、標準拡張と既存ネイティブ拡張バイナリを含みます。
第1段階はPHP完全互換、第2段階はALL自身のPHP相当の機能力と双方向呼出し・共有データです。第2段階の実装は第1段階の完了後に行います。

[要件表](docs/PHP_REQUIREMENTS_MATRIX.json)は初回棚卸しで **exhaustive=false / NOT_COMPLETE**。未分解の領域が残り、管理行数を互換率にしません。**PHP完全互換・ALLのPHP完全対応はいずれも未完了**です。
