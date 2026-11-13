# ALL v1.0 Foundations — 実験版（Windows PowerShell 5.1）

前提：ALL v0.9 インストール済み（420件テスト合格）。このZIPは既存の `ALL.ps1`、`php.ps1`、NEX、`run.ps1` を変更しません。`languages/all.ps1` だけを置き換えます。

## 追加範囲

1. **関数の名前空間** — `namespace Calc { fn add(a,b){return a+b} }` のように関数名を区切る。日本語 `名前空間` も認識し `Calc::add(2,3)` と呼び出す。**名前空間ごとの変数スコープ、export/private、動的ロードは未対応。**
2. **永続キーバリューストア** — `kv_put("data.allkv","名前","太郎")`、`kv_get("data.allkv","名前")`、`kv_delete`、`kv_keys`。JSON形式のバージョン付きファイル。排他ロックと同一ボリュームでの原子的なファイル置換を試行。UTF-8、最大1MiB。**SQL、複数ファイルをまたぐトランザクションは未対応。**
3. **ローカルパッケージ管理ツール** — `ALL_package.ps1 -Action init/add/list/verify`。外部レジストリにアクセスせず、`.all` ファイルをプロジェクトの `packages/` へコピーしSHA-256で整合性を検査。**依存解決、署名、リモートレジストリは未対応。**
4. **独立タスクの並行実行** — `parallel_all(["print(1)","print(2)"])`。最大4つのALLソースを独立PowerShellジョブで実行し、出力・エラーを順番に返す。**共有メモリ・async/await・長時間常駐タスクは未対応。**
5. **性能測定** — `ALL_benchmark.ps1` が同一プロセス内でウォームアップ＋実測を行い、ミリ秒・稼働メモリをJSON出力。**高速化済み、Python同等などの保証ではない。**

## インストール

```powershell
$zip = "$HOME\Downloads\ALL_v1_0_foundations.zip"
$dir = "$HOME\ALL_v1_0_work"
Expand-Archive -LiteralPath $zip -DestinationPath $dir -Force
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
& "$dir\ALL_v1_0_foundations\ALL_v1_0_install.ps1"
```

成功時 `Result: 449 / 449 passed; 0 failed`（新規29+既存420）。Windows実機未検証のため、失敗時は旧`all.ps1`を自動復元。

## 実行例

```text
名前空間 計算 {
  関数 合算(a,b) { 返す a+b }
}
表示(計算::合算(10,20))

データ保存("data.allkv","最後の値",30)
表示(データ取得("data.allkv","最後の値"))

変数 結果 = 並列実行(["print(10)", "print(20)"])
表示(結果[0]["output"])
表示(結果[1]["output"])
```

### パッケージの例

```powershell
& "$dir\ALL_v1_0_foundations\ALL_package.ps1" -Action init -Project "$HOME\MyALLProject"
& "$dir\ALL_v1_0_foundations\ALL_package.ps1" -Action add -Project "$HOME\MyALLProject" -Name demo -Source "$HOME\MyPackageFolder" -Version 1.0.0
& "$dir\ALL_v1_0_foundations\ALL_package.ps1" -Action verify -Project "$HOME\MyALLProject"
```

ソース側の先頭に `import "packages/demo/main.all"` を書く（既存v0.7方式）。

### ベンチマーク

```powershell
& "$dir\ALL_v1_0_foundations\ALL_benchmark.ps1" -Iterations 7 -OutputPath "$HOME\ALL_benchmark.json"
```

## 到達判定

v1.0 は **機能実験パッケージのバージョン名**。安定版リリースや汎用言語としての成熟、完全PHP互換、全言語完全互換を宣言するものではありません。性能・セキュリティ・実運用は別途検証が必要です。
