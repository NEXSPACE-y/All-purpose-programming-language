# Native ABI implementation measurement — 2026-11-12

**状態：案Aの最初のモジュールに対する選定挙動の実装・実行確認。PHP完全互換は未達。**

所有者承認済みの案Aに基づき、ALL所有のC/C++互換DLLとC#/C接続部を実装した。公式PHP本体・stock `php8ts.dll`へのリンク、転送、実行委譲は行っていない。既存`php_dl_test.dll`はバイト列を変更せず使用した。導入済みALLと`package/`はこの担当作業では変更していない。

## 実装と実行結果

- 自前`php8ts.dll`のMSVCコンパイル・リンク成功。正確な`__vectorcall`装飾名と必要DATAを含む。
- Windows PowerShell 5.1の独立した子プロセスで、未改変の`php_dl_test.dll`を実際にロードし、そのzif・frameless・メソッドハンドラを呼んだ。
- **37種類の呼出しケースをnormal／legacyの2モードで実行し、別プロセスの公式PHP参照結果と74/74一致**。同じ37ケースの2条件再実行であり、74種類の独立機能ではない。
- 比較対象は戻り値の型・値、生の文字列／出力バイト列、エラーのクラス・メッセージ、error handlerで取得した診断のseverity/message。日本語、NUL入力、無効UTF-8のPHPバイト文字列、int64上下限、弱／厳密変換、引数不正を含む。
- 4クラス、継承、未初期化typed property、定数42、INIの登録内容を公式PHPと照合した。**これは登録metadataの検査であり、native property read/writeを実行した証明ではない。**
- 2スレッドが同時に別々のINI値100/101を保持し、同じスレッドの次requestで既定0へ戻ることと、各スレッドの実ネイティブ呼出し結果を確認した。各workerでMINIT/MSHUTDOWNが1対、RINIT/RSHUTDOWNが6対、TLS context生成／解放が3対。
- メモリprobeで実割当て・文字列refcountの2→1→解放、他スレッドからの解放拒否と所有者bufferの保持を確認。制御したrequestの追跡割当て残数は0。全割当て・全競合についての一般的なリーク／race証明ではない。
- 動的catalog／HasFunction、UTF-8を保つscalar invoker、structured diagnostics、未対応型とNUL入り識別子の呼出し前拒否を含む**C bridge 24検査PASS**。これはC bridge単体の契約確認で、PHP評価器のソース実行との接続確認は別に必要。
- `php_shmop.dll`は自前coreの不足ABIによりWin32 error127でロード拒否された。stock coreへのfallbackは起きず、ロード済みPHP coreのパスは自前DLLのみだった。

legacy試験ではCRT `getenv`がプロセス起動時の環境を参照するため、環境変数を**子プロセス起動前に継承**させた。worker内部で設定した最初の試行は別登録関数が現れず不一致となり、この原因を直して再実行した。現在の保存結果は修正後であり、期待値は公式PHPの結果から変更していない。

## 証跡

| ファイル | 内容 |
|---|---|
| `build.json`, `build.log` | 自前DLL・ソースのSHA-256、SDK・compiler、ビルド実結果 |
| `candidate-imports.log`, `candidate-exports.log` | stock PHPへのimportsがないことと正確なexports |
| `candidate-worker.json`, `candidate-legacy-worker.json` | 実DLL呼出し、登録、INI、TLS、メモリ、loaded-moduleパス |
| `oracle-worker.json`, `oracle-legacy-worker.json` | 別公式PHPプロセスの同一fixture結果 |
| `acceptance.json` | 74比較と整合・境界チェックの機械判定 |
| `scalar-bridge-contract.json` | C bridgeの24項目と実dynamic catalog |
| `unsupported-module-load.json` | 未対応binaryを偽装成功させず拒否した実結果 |
| `remaining-symbol-contracts.json` | 36既存DLLごとの必要symbols、現在のexportsとの不足表 |
| `SHA256SUMS.json` | ソース・検証器・証跡のハッシュ |

`acceptance.json`が判定するのはこの表の範囲だけで、完全互換率の分母ではない。元DLLのハッシュは静的調査時の値と再照合している。stock PHPの使用は参照workerだけであり、ALL workerには自前coreと元拡張DLLがロードされたことを記録した。

## 残る実装契約

`php_dl_test.dll`の29 importsは名前解決されるが、各APIの全入力・全副作用を検証したわけではない。`std_object_handlers`のproperty/dimension/enumeration/castは明示unsupported guard。汎用object、ref、populated array、resource、user callback、native診断の完全なPHP実行状態は未完成である。MINFOの呼出しは行ったが、phpinfo出力全体の互換認定はしていない。

次の現物binaryの不足は、現在の機械可読表で確認できる。

| DLL | 必要core symbols | 現時点の不足symbols |
|---|---:|---:|
| `php_sqlite3.dll` | 83 | 64 |
| `php_ffi.dll` | 78 | 59 |
| `php_zend_test.dll` | 207 | 182 |

SQLite3には実object/resource・破棄・native callback・HashTable・例外状態等が必要。zend_testはそれに加えてVM stack、op array、observer、fiber等を要求する。既存DLLをラッパーや再コンパイル版へ置き換えて不足を消した扱いにはしない。独自native stateを拡張する案Aの範囲と、別決裁の広い実行core移行案Bを区別する。

承認済みのWindows 11 x64／Linux x64と、builtin server／CGI／FastCGI／Apache／Linux FPMの全対象は維持する。**Linux実行と各Web SAPIは、このnative測定では未検証**。単一Windows DLLの選定試験から全環境・全PHP・全native extensionの成功を宣言しない。

## 再現

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\native\php85abi\Build-NativeAbi.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\abi\Invoke-DlTestWorker.ps1 -Core .\native\php85abi\out\windows-x64-ts\php8ts.dll -Extension C:\Users\rinpa\ALL_php_oracle\php-8.5.12-ts-x64\ext\php_dl_test.dll -Cases .\tools\abi\DlTest-Cases.json -Output .\reports\native-abi-implementation-20261112\candidate-worker.json
```

legacy workerには`PHP_DL_TEST_USE_OLD_REGISTER_INI_ENTRIES=1`と`PHP_DL_TEST_USE_REGISTER_FUNCTIONS_DIRECTLY=1`を親から継承させる。公式PHP参照は同じJSON fixtureと`tools/abi/DlTest-Oracle.php`を**独立プロセス**で使用する。C bridgeと拒否probeも`tools/abi/`にある。各再実行の終了コードを確認してから、最後に`python .\tools\abi\Summarize-NativeAcceptance.py`で現在の証跡を集計する。

出力DLLは`native/php85abi/out/`に実在するがGit管理対象から除外している。ソースとビルド・測定証跡を保持し、導入済みALLやmainへ反映しない。`PHP_FULL_COMPATIBLE=false`。
