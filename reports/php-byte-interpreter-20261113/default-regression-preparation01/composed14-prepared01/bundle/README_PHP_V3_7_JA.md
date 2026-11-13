# ALL PHP v3.7 候補版 — 2026-11-03

## 状態と前提

**指定3領域の100%完全互換には未到達。** PHP 8.4.24の参照実行結果に基づいて新機能を追加した実装候補です。

- 旧v3.6.1の**415/415件 PASS**はユーザー提供のWindows PowerShell 5.1ログの実績です。今回のv3.7の実績へ流用しません。
- **v3.7では460件**（旧415件の項目を維持＋PHP参照正常系45件）の非破壊検証を準備しました。
- PHP 8.4.24実機では新規45件の期待出力の取得に成功。ただし**ALL処理系の460件のWindows実行は未検証**。
- 旧v3.6.1アダプタ・元のJSONテスト・ALL本体・PHPアダプタのインストール先は変更していません。

## 新規候補実装（指定3分野のみ）

**A. 変数・演算子・配列**
- `$$name` と `${$name}` / `${$name}[0]` を使う可変変数の一部。代入・参照・unset・局所変数の扱い。
- 変数名の変換・参照構造などPHPの全境界条件を実証したものではありません。

**B. 関数・スコープとの接続**
- 可変変数の関数内スコープ、クロージャーやメソッド経由で呼び出すオブジェクトの `__invoke`。
- `yield`、参照返却、型付き関数の完全仕様は未対応です。

**C. オブジェクト指向**
- `__invoke`、`__toString`、`__get`、`__set`、`__call`、`__callStatic` の基本的な呼出し経路。
- `trait` の `as`（別名・可視性）、`insteadof`（競合選択）、trait内での `use` の基本構成。
- 魔法メソッドのアクセス不能プロパティ、型宣言、全異常系、traitの全組合せは未検証です。

### 旧テストの取り扱い

旧 `PHP_v3_6_guard_cases.json` の21件は保持。うち2件（trait alias・入れ子trait）は今回の実装対象となったため、新検証でその2件を **PHP実機と一致する正常系** として再分類しました。19件の拒否テストは維持し、期待値は変更していません。再分類2件は `PHP_v3_7_implemented_prior_guards.json` に明示。

## 検証手順（Windows PowerShell 5.1）

```powershell
$ErrorActionPreference = 'Stop'
$zip = Get-ChildItem (Join-Path $HOME 'Downloads') -Filter 'ALL_PHP_compat_v3_7_candidate_20261103*.zip' -File |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $zip) { throw 'v3.7 ZIPが見つかりません' }
$dest = Join-Path $env:TEMP ('ALL_php_v3_7_' + [guid]::NewGuid().ToString('N'))
Expand-Archive -LiteralPath $zip.FullName -DestinationPath $dest -ErrorAction Stop
$validate = Get-ChildItem -LiteralPath $dest -Filter 'ALL_PHP_v3_7_validate.ps1' -File -Recurse |
    Select-Object -First 1
if (-not $validate) { throw 'v3.7検証スクリプトが見つかりません' }
& $validate.FullName -CompileCSharp
```

1. PowerShell AST構文解析・SHA-256照合・C#コンパイルに成功した場合のみPHPテストを続行。
2. 期待される最終結果文字列: `ALL PHP v3.7 (direct candidate): 460/460 passed; 0 failed`。
3. **期待値であり合格済みとは主張しません。** エラーを確認したら、そのログで実装修正します。

## 依然残る主要ギャップ

- A: 配列要素/オブジェクトプロパティ参照、foreach参照、周期参照、文字列ビット演算、型変換・数値境界など。
- B: 戻り値参照、参照可変長引数、ジェネレータ、スコープの全例外、first-class callableなど。
- C: enum、readonly、プロパティフック、型分散、全マジックメソッド、trait定数・プロパティ競合の完全規則など。
- 型システム・名前空間は次回の範囲とされており、今回3分野の完全互換にも関係するため、厳密な100%認定には統合検証が不可欠です。
