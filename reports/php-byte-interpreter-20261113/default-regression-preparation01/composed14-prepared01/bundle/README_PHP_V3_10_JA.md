# ALL PHP v3.10 型付き関数・戻り値実装候補（2026-11-04）

## 状態

**指定3分野の完全互換100%には未到達。これは完成品ではなく新規改修の実ファイル。**

- 対象：変数・演算子・配列／関数・スコープ／OOP、PHP 8.4をリファレンスとして実装。
- 既存の `ALL_PHP_v3_9_2_adapter.ps1` と550件の既存テストデータは変更していない。
- 新規 `ALL_PHP_v3_10_adapter.ps1` に引数・戻り値の型宣言パーサと実行時検査を追加。
- 型宣言：基本スカラー、nullable、union、intersectionsの字句構造、クラス／インターフェース型、`array`、`object`、`callable`、`mixed`、真偽値リテラル型、`void`の基礎。
- 関数・クロージャー・アロー関数・インスタンス／staticメソッド・trait取り込みメソッドに型情報を伝搬。
- 既存の値渡し・参照渡し・可変長引数・名前付き引数と併用して型検査を実施。

## 生成時の自動検証

- PHP 8.4.24（実物のPHP CLI）で**新規66テスト（正常系53・拒否系13）**を実行し、正常系の出力取得・拒否系の非ゼロ終了を確認。
- **ALL v3.10での616件（既存550＋新規66）は未実行。** PHP側の一致はALLの一致ではない。
- 既存v3.9.2の161ファイルは改変せず保全。
- 本ZIPのmanifest・ファイルハッシュ一致とパッケージ中のPowerShellの先頭BOM、閉括弧・引用符の確認を行う。

## 未解決・未認定

型宣言といっても全機能ではない。`declare(strict_types=1)`、PHPのint/float分離とIEEE754、継承の厳密な分散規則、型付きプロパティ、promoted property、readonly、PHP 8.4 property hooks、ジェネレータ、属性、GCや拡張機能との交差、オブジェクト型の完全性、厳密な `callable`・`iterable` の挙動は未達。

また、**PowerShell 5.1構文解析・実行テストはこの環境で実施できていない**。静的検査を実機合格と同一視しない。

## 参考：非破壊検証コマンド（100%到達前の実行を依頼するものではない）

```powershell
$ErrorActionPreference = 'Stop'
$zip = Get-ChildItem -LiteralPath "$HOME\Downloads" -Filter 'ALL_PHP_v3_10_typed_functions_work_20261104.zip' -File | Select-Object -First 1
if ($null -eq $zip) { throw '候補ZIPが見つかりません' }
$dest = Join-Path $env:TEMP ('ALL_v310_' + [guid]::NewGuid().ToString('N'))
Expand-Archive -LiteralPath $zip.FullName -DestinationPath $dest -ErrorAction Stop
$script = Get-ChildItem -LiteralPath $dest -Filter 'ALL_PHP_v3_10_validate.ps1' -File -Recurse | Select-Object -First 1
if ($null -eq $script) { throw 'v3.10検証スクリプトが見つかりません' }
& $script.FullName -CompileCSharp
```

ここでの検証は候補アダプタを直接実行するだけで、インストール済みALLを変更しない。
