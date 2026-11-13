# ALL v0.7 ― 複数ファイル実行・CLI実用テスト

## 今回の目的

ALL独自言語（日英共用）の既存動作を維持したまま、`.all` の複数ファイル構成を可能にする。
PHPアダプタやNEXは変更しない。既存の367件＋新規26件のテストを実行する。

## 実装した文法

モジュールの読み込みはソースファイルの**先頭**（空行・コメントの後は可）に1行ずつ記述する。

```all
import "lib/math.all"
「lib/labels.all」をモジュールとして読み込む

print(金額(120, 2))
```

- モジュールは同一プロジェクトの `.all` ファイルだけ。相対パスは呼び出し元ファイルのフォルダから解決する。
- モジュール内で別のモジュールを読み込める。再度読み込まれた同一ファイルは1回だけ実行する。
- 循環読み込みと構文不正、未発見、絶対パス、プロジェクト外への `..` はエラー。
- 実装は**同一スコープへの展開**。importされた関数・変数は共有される。名前衝突時は従来どおりエラー。
- 名前空間・エクスポート制御・動的ロード・パッケージ管理は**未実装**。
- インポートはファイルの先頭だけ。関数・条件分岐内のimport、コードを書いた後のimportは拒否する。
- 最大32ファイル、入れ子16段、展開後100,000文字。UTF-8のみ。
- インポートのベースは `run.ps1 -File` のファイルの親ディレクトリ。`-Code` 直接呼び出し時はPowerShellの現在の作業ディレクトリ。
- パスの検査は字面の正規化に基づく。シンボリックリンクを通る逃避までは防止していないため、**信用できるプロジェクトのみ実行する**。

## インストール＋一括テスト

Windows PowerShell 5.1で、ZIPをDownloadsフォルダに保存した後：

```powershell
$zip = "$HOME\Downloads\ALL_module_v0_7.zip"
$dir = "$HOME\ALL_module_v0_7_work"
Expand-Archive -LiteralPath $zip -DestinationPath $dir -Force
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
& "$dir\ALL_module_v0_7\ALL_module_v0_7_install.ps1"
```

成功時の予定表示：

```text
ALL modules v0.7: 26 / 26 passed; 0 failed
ALL natural Japanese v0.6: 34 / 34 passed; 0 failed
ALL v0.5: 49 / 49 passed; 0 failed
Result: 393 / 393 passed; 0 failed
ALL modules v0.7 installed: ...
```

失敗した場合は `all.ps1` と `run.ps1` をバックアップから自動復元。
インストール時、既存 `ALL.ps1` と `php.ps1` は変更しない。

## CLIアプリの実行

インストールに成功したあと、ファイル `examples/cli_report/` をそのまま使用できる。

```powershell
Set-Location "$dir\ALL_module_v0_7\examples\cli_report"
& "$HOME\ALL\run.ps1" -File .\main.all
Get-Content .\result.json -Raw -Encoding UTF8
```

想定する画面出力は次のとおり。

```text
集計:商品売上
480
```

`orders.json`の複数明細を読み込み、`result.json`を生成する。**すでにresult.jsonがある場合は上書きする**ので注意。

## 検証状態

本ZIPを作成した環境にはWindows PowerShell実行環境がない。ZIP構造・JSON件数・既存のテスト用資産のハッシュ一致は検証したが、**393件の実機合格はまだ確認できていない**。合格前の版を完成と見なさない。
