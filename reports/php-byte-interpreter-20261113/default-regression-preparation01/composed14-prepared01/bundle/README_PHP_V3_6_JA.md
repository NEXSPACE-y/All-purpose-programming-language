# ALL PHP v3.6 候補版 — 指定3分野の完全互換を目標とした拡張（2026-11-02）

## 判定

**候補実装。PHP完全互換100%ではない。**

対象はユーザーが指定した「変数・演算子・配列」「関数・スコープ」「オブジェクト指向」の3分野に限定する。正式な互換対象PHPバージョンがまだ確定していないため、今回の正常系テストの比較基準は利用可能なネイティブ **PHP 8.4.24** に固定した。PHP 8.5以降を完全に再現した証明はない。

前回のv3.5.1はWindows PowerShell 5.1で **329/329 PASS** とユーザーから報告された。これは当時の候補版の結果であり、v3.6の実行検証結果には流用しない。

## v3.6で追加したもの

### 1. 変数・演算子・配列

- 変数同士の単純な参照代入（例：`$b =& $a`）、参照された変数の更新・解除時の別名管理。
- ビット単位の複合代入 `&=`, `|=`, `^=`, `<<=`, `>>=`。
- 参照された変数がnullの状態から配列要素へ代入する際の配列初期化処理。

### 2. 関数・スコープ

- 関数・メソッドの単純な変数参照渡し（`function f(&$v)`）。通常の値渡しとは分けて評価する。
- クロージャーの単純な参照捕捉（`function () use (&$v)`）。
- ユーザー定義関数、動的関数、クロージャー、インスタンス／staticメソッド、コンストラクタの引数渡しを参照指定に基づいて処理。

### 3. オブジェクト指向

- `interface` と `extends`、`implements`、`instanceof` による基本的な実装判定、interface定数。
- `abstract class` / 抽象メソッド、`final class` / finalメソッド、抽象メソッド実装不足・final継承・final上書きの拒否。
- 単純な `trait` 宣言と `use T;` のメソッド・プロパティ取り込み。クラス自身のメソッド優先と、解決できないtrait同士の競合の検出。
- 非型付きメソッド間の基本的な実装検査。PHPの型互換性を網羅するものではない。

## 既存テストとの関係

- **旧v3.5.1アダプタ、旧テスト、旧READMEは無変更のまま収録**。新処理系は `ALL_PHP_v3_6_adapter.ps1`。
- 旧v3.5テスト総数329件のうち「参照引数を拒否」「クロージャー参照捕捉を拒否」の2件は、新機能実装により旧拒否期待が不適切になった。旧データは上書きせず、新版用に別の**正常系PHP期待値テスト**へ再分類。残る旧拒否6件は維持。
- 今回の新規正常系は65件（OOP 23、参照22、複合演算7、trait13）。新規拒否試験21件。
- v3.6検証予定総数：329（旧項目を別ファイルで再分類して維持）＋65＋21＝**415件**。

## 現在の検証状況

| 内容 | 状態 |
| --- | --- |
| ネイティブPHP 8.4.24で65件の正常系期待値を取得 | 完了 |
| 旧コード・旧テストファイルの内容照合 | 一致 |
| 新規ソースの字句レベルの括弧・文字列対応検査 | 一致 |
| 新規テストの字句トークン認識確認 | 確認済み |
| 全収録物のSHA-256ハッシュとZIPの一致 | ZIP生成時に実施 |
| PowerShell 5.1 AST構文検査 | **未実施（Windows実機で必須）** |
| v3.6の415件実行試験 | **未実施（Windows実機で必須）** |
| 旧523件のALL統合回帰試験 | 今回未実施 |

## Windows PowerShell 5.1での非破壊検証

ZIPをDownloadsに保存し、以下を丸ごと実行する。インストールは行わず、候補アダプタを直接実行する。

```powershell
$ErrorActionPreference = 'Stop'
$zip = Get-ChildItem (Join-Path $HOME 'Downloads') -Filter 'ALL_PHP_compat_v3_6_candidate_20261102*.zip' -File |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $zip) { throw '候補ZIPが見つかりません' }
$dest = Join-Path $env:TEMP ('ALL_php_v3_6_' + [guid]::NewGuid().ToString('N'))
Expand-Archive -LiteralPath $zip.FullName -DestinationPath $dest -ErrorAction Stop
$validate = Get-ChildItem -LiteralPath $dest -Filter 'ALL_PHP_v3_6_validate.ps1' -File -Recurse |
    Select-Object -First 1
if (-not $validate) { throw '検証スクリプトが見つかりません' }
& $validate.FullName -CompileCSharp
```

事前検査に成功した場合だけ415件を実行。成功した場合の最後の表示は `ALL PHP v3.6 (direct candidate): 415/415 passed; 0 failed`。これは**期待する文字列**であり、現時点の合格実績ではない。

## 禁止・保護

- 既存 `HOME\ALL` インストール、ALL本体、従来のv3.5以前PHPアダプタは変更しない。
- 旧329件の期待値を勝手に上書きしない。再分類は上記2件のみとし履歴を残す。
- PowerShell AST検査、実行試験が失敗した時は候補扱いに留める。
- 3分野とも100%達成とは判定しない。残件は `PHP_THREE_AREAS_COMPLETENESS_GATE.md` に記載。
