# ALL PHP互換拡張 v3.4 開発候補（2026-11-02）

**これは PHP完全互換版ではありません。v3.3を保全した上で、ALL独自PHP評価器へ実装を追加した候補です。**

## 1. 変更範囲・保全

- 元ZIP：`ALL_PHP_compat_v3_3_candidate_20261102.zip`。
- 新規：`ALL_PHP_v3_4_adapter.ps1`。旧 `ALL_PHP_v3_3_adapter.ps1` 及びv3.2以前のソースを維持。
- ALL独自言語処理系、HTTP/SQLite/C#、CLI及び既存523件の回帰試験の内容は変更しない。
- PHP実行エンジンを `php.exe` に委譲しない。新たな依存パッケージも導入しない。
- PHPの比較基準は、共通構文についてのローカル **PHP 8.4.24**。PHP互換対象バージョン自体の最終決定は未実施。

## 2. 今回の実装

1. **配列の値コピー**：通常の変数代入、配列要素への代入、ユーザー関数への配列引数引渡し、foreach値変数への引渡しで再帰的に配列をコピーする。PHPの配列値セマンティクス（外部から観測できるコピー分離）へ近づける変更。PHPの内部COW最適化と参照 `&` そのものは未実装。
2. **式中代入**：`($a=3)`、連鎖代入、`??=`を式として使用する構文。追加の `*=`, `/=`, `%=`, `**=`。既存のfor文ヘッダも同じ演算子に対応。
3. **JSONの基本機能**：`json_encode`、`json_decode`、`json_last_error`、`json_last_error_msg`。配列・連想配列・stdClass型オブジェクト・入れ子構造・スカラーを対象とする。JSON文字列のエスケープはPHP既定設定を参考に実装。
4. **明示的な制限**：JSON関数のオプション・深さ引数は未対応のため拒否する。無言で別の結果を返さない。

### 実装の既知の限界

- PHP型システム：現在の数値はdecimal中心で、`int`と`float`の区別・IEEE 754・浮動小数点境界挙動を再現していない。
- JSON：PowerShell 5.1の標準 `ConvertFrom-Json` に依存するため、同名キーの扱い・大小文字だけが異なるキー・巨大小数・不正UTF-8・深い入れ子・例外メッセージには差異があり得る。現時点でPHP JSON拡張完全互換とはみなさない。
- PHPの配列 `&` 参照・循環参照・copy-on-writeの性能特性・例外クラス・名前空間・継承等は未実装。
- 式の評価順序や代入先式の副作用は全面的な一致未認定。PHP 8.4仕様書との全組合せの差分検証は未実施。
- PHP 8.5固有の追加挙動はPHP 8.4.24では確認できていない。

## 3. 試験集合

| 集合 | 件数 | 状態 |
| --- | ---: | --- |
| 既存v3.1.1 | 45 | v3.3環境のWindows実機でPASS済み。v3.4は要再試験 |
| 既存v3.2 | 50 | 同上 |
| 既存v3.3 | 49 | 同上 |
| 既存ガード | 3 | 同上 |
| 旧数学PHP parity | 17 | 同上 |
| **新規PHP参照ケース** | **60** | PHP 8.4.24側で60/60通過。ALL実機は未検証 |
| **新規失敗時拒否ケース** | **3** | ALL実機は未検証 |
| **合計** | **227** | **候補v3.4の227件は未実行** |

**注意：** 旧164/164の合格結果はv3.3に対するものであり、v3.4へ流用しない。既存523/527件の統合回帰もv3.4では未実行。Linuxの開発環境にPowerShellが無いため、PowerShellの解析やv3.4の動的試験結果はユーザーWindows実機で取得する。

## 4. Windowsでの非破壊試験

前回のZIP内パス相違を避けるため、ダウンロードした ZIP を自動探索して専用作業フォルダへ展開する。以下は **既存の `$HOME\ALL` を変更しない**。

```powershell
$zip = Get-ChildItem (Join-Path $HOME 'Downloads') -Filter 'ALL_PHP_compat_v3_4_candidate_20261102*.zip' -File |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $zip) { throw 'v3.4 ZIPがDownloadsに見つかりません' }
$dest = Join-Path $env:TEMP ('ALL_php_v3_4_test_' + [guid]::NewGuid().ToString('N'))
Expand-Archive -LiteralPath $zip.FullName -DestinationPath $dest -ErrorAction Stop
$test = Get-ChildItem -LiteralPath $dest -Filter 'ALL_PHP_v3_4_test.ps1' -File -Recurse |
    Select-Object -First 1
if (-not $test) { throw 'テストスクリプトがZIPに存在しません' }
$root = $test.DirectoryName
& (Join-Path $root 'ALL_preflight.ps1')
& $test.FullName
```

`ALL preflight PASS` と `ALL PHP v3.4 (direct candidate): 227/227 passed; 0 failed` を両方確認する。後者が未達の場合は更新しない。

## 5. インストールは明示実行時のみ

```powershell
& (Join-Path $root 'ALL_PHP_v3_4_install.ps1')
```

バックアップは `~\ALL\languages\php.ps1.bak.<GUID>` に保持する。更新対象は `~\ALL\languages\php.ps1` のみ。インストール後の227件及び従来のv3.2互換テストが失敗すると元アダプタへロールバックする。**523/527件の統合回帰試験は自動実行しない**ため、本体の完了認定は別途必要。

## 6. 次の開発目標

残る本質的課題はPHPのint/float型・参照代入・名前空間とautoload・例外処理・継承/trait/interface・型宣言・クロージャー・ジェネレータ・SAPI/標準ライブラリ/拡張互換など。`PHP_COMPAT_GAP_MATRIX.md`を継続参照する。

**判定：PHP完全互換へ向けた開発候補。PHP完全互換またはPhase終了とは宣言しない。**
