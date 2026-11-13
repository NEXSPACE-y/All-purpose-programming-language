# ALL PHP v3.12.1 — プロパティフック不具合修正

## 修正対象

Windows PowerShell 5.1でのv3.12実機結果は **713/716 PASS・3件FAIL**。既存693件はPASS。次の3件に限定してアダプタを修正した。

1. `get-only property rejects assignment`：診断文の先頭を `ALL PHP: get-only` に統一。
2. `duplicate getter rejected`：hook定義のオブジェクトとは独立した `HashSet` で `get`／`set` の重複を拒否。重複判定漏れの不具合に対応。
3. `setter only virtual cannot read`：診断文の先頭を `ALL PHP: write-only` に統一。

## 変更範囲

- **変更した既存ファイルは `ALL_PHP_v3_12_adapter.ps1` のみ**。既存のテスト定義・期待値・716件の内訳は変更なし。
- `CHANGE_v3_12_to_v3_12_1.patch` と本README、`ALL_PHP_v3_12_1_validate.ps1` を追加。
- 過去のバージョンのアダプタ、ALL独自言語処理系、PHPアダプタのインストール先に変更なし。
- 本修正はプロパティフック3件の失敗解消を対象とし、指定3分野の完全互換100%を認定するものではない。

## 検証結果の区別

- 前版の実機結果：713/716 PASS（ユーザーログ）。
- 今回実施：対象箇所・テスト期待値・元データの差分検査、SHA-256ファイル照合、ZIP CRC/バイト照合、BOM検査、PHP 8.4.24での該当3ケースの異常終了確認。
- 今回**未実施**：Windows PowerShell 5.1の構文検査、ALL v3.12.1の716件の実行回帰試験。

## Windows PowerShell 5.1 非破壊検証コマンド

```powershell
& {
    $ErrorActionPreference = 'Stop'
    $zipPath = Join-Path $HOME 'Downloads\ALL_PHP_v3_12_1_property_hooks_fix_20261104.zip'
    if (-not (Test-Path -LiteralPath $zipPath -PathType Leaf)) {
        throw "ZIP not found: $zipPath"
    }
    $dest = Join-Path $env:TEMP ('ALL_v3121_' + [guid]::NewGuid().ToString('N'))
    Expand-Archive -LiteralPath $zipPath -DestinationPath $dest -ErrorAction Stop
    $validate = Get-ChildItem -LiteralPath $dest -Filter 'ALL_PHP_v3_12_1_validate.ps1' -File -Recurse |
        Select-Object -First 1
    if ($null -eq $validate) { throw 'v3.12.1 validator not found' }
    & $validate.FullName -CompileCSharp
}
```

事前検査合格後に既存の716件を実行する。既存ALLのインストール先は変更しない。合格はユーザーのWindows実機結果が得られるまで未認定。
