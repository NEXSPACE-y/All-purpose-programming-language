# ALL (ALMIGHTY) — All-purpose programming language

ALL は、最終的にあらゆる既存プログラミング言語との互換を目指す独立した汎用言語処理系です。
現在は Windows PowerShell 5.1 上の独自処理系と、PHP 互換アダプタを開発しています。

**状態：開発中。PHP 完全互換は未達・未認定です。**

## 構成

| パス | 内容 |
|---|---|
| `package/` | 処理系・アダプタ・テスト一式（基準：PHP アダプタ v3.12.1） |
| `docs/` | 仕様書 |
| `docs/provenance/` | 基準版の出どころを示すハッシュ記録と検証ログ |

## 基準版（ベースライン）

- 元パッケージ：`ALL_PHP_v3_12_1_property_hooks_fix_20261104.zip`
- SHA-256：`219e225f86fc3c4a00d44e3c4fa4c93b62835e257f4584327e4c1b17dfe6e0d1`
- `package/` は上記 ZIP の中身を無改変で展開したものです。
- 2026-11-10、Windows PowerShell 5.1 で事前検査と PHP 回帰 716/716 PASS を確認しました
  （`docs/provenance/v3_12_1_validate_ps51_20261110.log`）。
  これは既存テスト集合の合格であり、PHP 完全互換を示すものではありません。

## 検証（インストールせずに実行）

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\package\ALL_PHP_v3_12_1_validate.ps1 -CompileCSharp
```
