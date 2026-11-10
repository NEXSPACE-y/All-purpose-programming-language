# ALL PHP v3.12 — プロパティフック拡張（候補、実機未検証）

## 対象
PHP互換の指定3分野のうち「オブジェクト指向」。v3.11.1を保全し、新版アダプタを別ファイルで追加した。PHP本体呼出しへの委譲は行っていない。

## 追加内容
- PHP 8.4 の `get` / `set` フック（ブロック形式・`=>`形式）の候補実装。
- フックを持つプロパティのバックド／仮想の基本的な区別。フック本体の `$this->同名プロパティ` アクセスは backing value を読み書き。
- `set(string $input)` の明示パラメータと式形式 setter の自動 backing 代入。
- getter／setter の宣言重複、`readonly`／`static`との禁止組み合わせを拒否。
- 既存 v3.11 の693件を維持し、PHP 8.4.24 で確認した23件（正常16・異常7）を新規追加。合計716件。

## 未検証・非対応
- PowerShell 5.1での本体実行、716件の実行回帰テストは **未実施**。
- プロパティフック全仕様（継承と非対称可視性の全組み合わせ、型付き参照、`isset`/`empty`/`unset` と仮想プロパティの完全な挙動、hook内のスコープ等）は **未達**。
- PHP 8.4 の公式PHPT全網羅、既存3分野の100%認定には至っていない。
- 本版は旧版をインストール／上書きしない。実機に導入するコマンドは含まない。

## 実施済み検証
- PHP 8.4.24: 23/23の期待出力またはエラー終了を取得（ALL本体の合格ではない）。
- v3.11.1 元ファイル: 全ファイルを別名で保全、変更差分はv3.12追加ソースのみ。
- SHA-256全ファイル照合、ZIP CRC照合、BOM重複なしのバイト検査。

## PowerShell非破壊検証コマンド（現段階の実行依頼ではない）

```powershell
& {
    $ErrorActionPreference = 'Stop'
    $zipPath = Join-Path $HOME 'Downloads\ALL_PHP_v3_12_property_hooks_work_20261104.zip'
    if (-not (Test-Path -LiteralPath $zipPath -PathType Leaf)) { throw 'ZIP not found' }
    $dest = Join-Path $env:TEMP ('ALL_v312_' + [guid]::NewGuid().ToString('N'))
    Expand-Archive -LiteralPath $zipPath -DestinationPath $dest -ErrorAction Stop
    $validator = Get-ChildItem -LiteralPath $dest -Filter 'ALL_PHP_v3_12_validate.ps1' -File -Recurse | Select-Object -First 1
    if ($null -eq $validator) { throw 'v3.12 validator not found' }
    & $validator.FullName -CompileCSharp
}
```

この検査は既存インストール先を変更しない。予想値は716/716だが未実証。Windows実機の結果なしにPASSや完成を認定しない。
