# Linux x64 実行環境と検証経路

2026-11-12。対象は所有者承認済みのLinux x64。実際の検出結果は [preflight JSON](../../reports/linux-preflight-20261112.json)。**Linuxビルド・ELF実行・PHP8.5.12参照・Web SAPI・既存拡張.so互換は未実施。**

## このWindowsホストで確認したこと

- Windows 11、AMD64、build `10.0.26200`。
- `wsl.exe`は存在するが、`--list --verbose`は終了1、`--status`は終了50。「Linux用Windowsサブシステムがインストールされていません」と返る。ランチャーの存在はLinux実行環境の存在ではない。
- docker/podman/QEMU/VirtualBox/VMware/multipassの実行ファイルはPATHで見つからず、調べた既定導入先も存在しない。関連サービス/VMプロセス/Hyper-V管理コマンドも今回の読み取りでは見つからなかった。その他の場所にある全環境を否定する調査ではない。
- OpenSSHクライアントは存在する。接続先は指定されておらず、接続・鍵・SSH設定の探索はしていない。
- `ALL_php_oracle`直下にあるのは`php-8.5.12-tests`とWindows向け`php-8.5.12-ts-x64`。Linux用の実行確認済みPHP8.5.12参照ビルドは特定できていない。
- `package/ALL_linux_core.ps1`、`ALL_install_linux.ps1`、`ALL_linux_validation.ps1`、`ALL_sqlite_driver_linux.cs`は存在するが候補資産。Linux上の動作証拠とは扱わない。
- このWindowsのPATHにはLinux向けgcc/g++/cc、clang、cmake/ninja/makeを確認できていない。Windows用MSVCの利用可能性とは別の確認項目。

したがって、**現在アクセスできるLinux実行環境は発見できていない**。Windowsで生成したPE/ヘッダーレイアウト/C++構文確認をLinuxネイティブ実行の合格へ転記しない。

## 実行経路の候補

現在の機械上では、WSL機能とLinux x64ディストリビューションを準備する経路が候補になる。ただし現時点では未導入であり、準備にはOS機能・ディストリビューション・必要に応じた再起動の変更が伴う。今回の事前確認では実施していない。既存Linux x64ホストが提供される場合は、導入済みOpenSSHで接続する別経路も考えられるが、接続可能性・権限・ツールは未確認。Dockerが既に利用できると仮定した経路は採らない。

Linux環境が実際に用意できた時点で、次の順に証拠を揃える。

1. 同じリポジトリのコミットと入力ファイルhashを固定し、Linux上で`python3 tools/linux/linux_preflight.py --output reports/linux-preflight-<run>.json`を実行。x86_64、64bit、OS/ディストリビューション、libc、既存C/C++ツール、PowerShellの有無を記録する。
2. PHP8.5.12のLinux参照ビルドとソース/ヘッダーを固定し、バイナリhash、版、TS/NTS、debug、API/build ID、SAPI、拡張一覧、INI、依存.soを記録する。Windows VC2022/ZTSのSDK設定やDLLをLinuxの正本として流用しない。元PHPは照合専用。
3. 承認済み案AのALL所有ネイティブ層をLinux用の実ツールチェーンで構築する。Linuxの共有ライブラリ名、ELF export/relocation、呼出し規約、TLS、libc/loader、TS/NTSを明示する。Windowsの`Build-NativeAbi.ps1`が存在するだけではLinuxビルド経路が完成したことにならない。
4. コンパイル結果のELFと依存を調べた後、Linuxプロセス内で候補を実行する。実ロードされたライブラリのパスを記録し、stock PHPへの委譲がないこと、無改変の参照拡張.soの登録・MINIT/RINIT/RSHUTDOWN/MSHUTDOWN・値/出力/診断/終了を独立オラクルと照合する。
5. 既存ALL/PHP回帰と厳密差分をLinuxでも実施し、その後に内蔵Web、CGI/FastCGI、Apacheモジュール、LinuxFPMの各ホストでリクエスト/応答・設定・プロセス/スレッド/リクエスト状態・異常系を検証する。CLIの合格をWebへ転記しない。

Linuxの実コンパイラ、固定参照build、無改変拡張.soとホスト環境がまだないため、現段階で存在しないLinuxネイティブビルドコマンドや成功結果は提示しない。実装担当のLinux用ビルド入口ができたら、その実在する入口と実行ログをこの経路へ追加する。
