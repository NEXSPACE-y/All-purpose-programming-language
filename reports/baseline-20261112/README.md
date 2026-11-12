# 現行 v3.16 基準の再現検証（2026-11-12）

対象コミットは `9d8171712828a0b57555b8eb1e1ca5c475391244`。
隔離作業ツリー `C:\Users\rinpa\ALL-php-compat-20261112` で、Windows PowerShell **5.1.26100.9818** により実行した。

## 実行結果

`package/ALL_PHP_v3_16_validate.ps1 -CompileCSharp` は、候補アダプタ直接実行で **940/940 PASS、失敗 0、プロセス終了コード 0**。
検証器の実行時間は **162.155 秒**。プロセス起動と証跡採取を含む経過時間は約 **174.093 秒**。

- PowerShell 構文検査：93 スクリプト PASS。
- 配布物 SHA-256：マニフェスト記載 204 ファイル PASS。
- C# コンパイル：`ALL_sqlite_driver.cs` と `ALL_ConcurrentGateway.cs` の 2 件 PASS。
- マニフェスト自体を含む `package/` の全 205 ファイルについて、実行前後の長さと SHA-256 が一致。
- 検証プロセスの stderr は 0 バイト。
- C# 補助型を含むロード済みアセンブリは 2 件。いずれも `Assembly.Location` が空で、検証終了時に該当する DLL 実ファイルは確認されなかった。`package/` に追加ファイルなし。削除処理は実施していない。

詳細は `baseline-evidence.json`、標準出力は `attempt02.stdout.log`、終了記録は `attempt02.process-exit.json`。
`attempt02/` に実行前後の全ファイルハッシュ、PowerShell バージョン、検証プロセスの記録を保存した。

## オラクル

`C:\Users\rinpa\ALL_php_oracle\php-8.5.12-ts-x64\php.exe -n -v` は終了コード 0。
実機表示は **PHP 8.5.12 CLI / ZTS Visual C++ 2022 x64 / Zend Engine v4.5.12**。
実行バイナリの SHA-256 は次の値で、確認時の `docs/COMPAT_TARGET.md` と一致した。

```text
0ac893499799256db6d3a54b0da73692e02311493922e6e4f86a062674a77d66
```

保存先は `oracle-evidence.json` と `oracle-php-n-v.log`。

## 最初の証跡採取の失敗

初回は証跡採取ラッパー内の `Get-FileHash` 自動読込に失敗し、**検証器を呼び出す前に**終了コード 1 で停止した。
初回の stdout、stderr、終了記録を元の名前で残し、エラーの UTF-8 表示用コピーも保存した。
Windows PowerShell 自身の `$PSHOME\Modules\Microsoft.PowerShell.Utility\Microsoft.PowerShell.Utility.psd1` を明示的に読み込んだ後の `attempt02` が、上記 940 件の実行結果である。
`package/`、テスト定義、期待値、SHA マニフェストは変更していない。

同じ標準モジュール読込を含む検証コマンドは次のとおり。PowerShell 5.1 内で実行する。

```powershell
Import-Module -Name (Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Utility\Microsoft.PowerShell.Utility.psd1') -ErrorAction Stop
& '.\package\ALL_PHP_v3_16_validate.ps1' -CompileCSharp
```

`capture-validation.ps1` は今回の証跡を採取したスクリプトで、既存証跡の上書きを避けるため保存先が既にある場合は再利用しない。

## 既存 PHPT 証跡の確認と限界

全 5,819 本の PHPT は再実行していない。既存 `reports/PHPT_CORE_ALL_v3_16.jsonl` の再集計は次のとおりで、既存報告と一致する。

| 判定 | 本数 |
|---|---:|
| PASS | 745 |
| ALL_ERROR | 4,114 |
| OUTPUT_DIFF | 905 |
| TIMEOUT | 43 |
| NOT_RUNNABLE | 9 |
| CRASH | 1 |
| MEMORY | 2 |

元 JSONL の SHA-256 と集計は `historical-phpt-counts.json` に保存した。

既存報告の条件は Windows PowerShell 5.1、3 ワーカー、1 本 30 秒、ワーカーのメモリ上限 1,500 MB。
現行 `Invoke-PhptRun.ps1` の引数既定値はタイムアウト 15 秒なので、単に既定引数で再実行しても既存報告と同条件にはならない。
既存報告には並列時の CRASH と TIMEOUT の変動、遅い構文解析、メモリ制限未実装が記録されている。
これらの原因は今回解消しておらず、試験条件も変更していない。

PHPT ワーカーは候補をプロセス内で実行し、PHP 本体へ委譲しない。既存判定は期待出力との一致で、前後空白・改行を正規化する。
`--INI--` は適用せず、標準入力・引数・GET/POST などの一部セクションは `NOT_RUNNABLE` にするため、公式 `run-tests.php` の実行条件を全面再現してはいない。
PASS 数だけで言語機能の正しい実装や PHP 完全互換を認定できない。

940 件の試験器は既存 fixture の期待出力／例外メッセージとの比較であり、公式 PHP との同時差分試験ではない。
インストール済み `C:\Users\rinpa\ALL` は実行していない。標準拡張、ネイティブ拡張 ABI、Web SAPI、実アプリの動作確認も今回の検証対象に含めていない。
