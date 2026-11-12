# PHP 8.5.12 API 実測台帳（2026-11-12）

**公式 PHP の参照 API を採取した台帳。ALL の実装・互換性の合格結果ではない。**

固定した公式 `php.exe` の SHA-256：
`0ac893499799256db6d3a54b0da73692e02311493922e6e4f86a062674a77d66`。
全実行は Windows x64 / PHP **8.5.12 CLI / ZTS Visual C++ 2022**。ビルド日時は **2026-10-26 09:50:37**。
PHP API **20250925**、Zend Extension API **420250925**、PHP Extension Build **API20250925,TS,VS17**。
一般ビルド情報の実測値は `audit.json`、元の完全な `phpinfo(INFO_GENERAL)` は各 profile の JSON 内にある。

## 実際に採取した範囲

base の起動条件を次に固定し、実在する `ext/*.dll` **36 本を各々別の新規 PHP プロセス**に 1 本ずつ指定した。

```text
php.exe -n -d display_errors=stderr -d error_reporting=-1 -d date.timezone=UTC [ -d extension=ABSOLUTE_DLL ] tools/oracle/api/reflect.php
```

計 **37 profile** の raw stdout、raw stderr、実終了コード、警告、完全な Reflection 情報、base との差分、実行 argv を保存した。
各プロセスの作業ディレクトリは profile の証跡保存先で、php.ini は読み込んでいない。
INI ファイルやシステム設定、依存 DLL の追加・再設定は行っていない。
候補処理系の実行、サービス・ネットワーク試験、実 API メソッドの動作試験も行っていない。

**DLL 35/36 本は実ロード。`php_pdo_firebird.dll` は NOT_LOADED。**
後者は PHP プロセスが終了 0 でも module が増えず、Startup の dynamic library 読込警告が残った。
エラーは「指定されたモジュールが見つかりません」で、今回の Reflection 実測だけでは欠けた依存の名前まで断定しない。
依存を追加して成功に変更したり、対象から除外したりしていない。
この未採取 profile を残すため、台帳生成器の最終終了コードは **1**。JSON 生成や Reflection 収集そのものの失敗ではない。

各 process の stderr には、Reflection で `SUNFUNCS_RET_STRING` を既定値として取得したときの deprecation が共通して 2 件ある。
これらは worker 内警告として JSON にも記録し、stderr を消去・正規化していない。Startup 警告とは区別できる。

## 台帳の件数

登録名・公開先クラスごとの API exposure を数える。メソッドは継承されたものも各クラス側の名前として含み、private/protected は可視性付きで保持する。
型の alias も登録された検索名として保持する。件数は実装本数や互換率ではない。

| 種類 | base | 観測できた profile の union |
|---|---:|---:|
| 関数 | 925 | 2,196 |
| class 登録名 | 207 | 331 |
| interface 登録名 | 27 | 29 |
| trait 登録名 | 0 | 1 |
| enum 登録名 | 6 | 10 |
| method exposure | 3,660 | 4,614 |
| class constant exposure | 598 | 2,262 |
| property exposure | 1,016 | 1,246 |
| global constant | 905 | 2,919 |
| INI directive | 228 | 326 |
| 合計 | **7,572** | **13,934** |

`run-01/api-leaves.jsonl` に **13,934 件**の機械導出レコードがある。
各々に安定 ID、元 profile と JSON pointer、signature SHA-256、親要件の候補を付けた。
全件 `leaf_candidate / UNVERIFIED / candidate_implementation=NOT_ASSESSED` とし、検証済み要件へ昇格させていない。
`run-01/requirements-linkage.json` は既存 `docs/PHP_REQUIREMENTS_MATRIX.json` の起点ハッシュと関連候補を記録するが、既存要件ファイルは変更しない。
各 API の正常・異常・境界・副作用・SAPI・ABI の意味論的な下位要件と試験は今後の作業である。

## 情報と値の保持

全関数・メソッドについて、引数順序・名前・型・既定値・参照・可変長・任意引数、戻り値型・tentative return type、deprecated、所属拡張、attribute を採取した。
class/interface/trait/enum、継承・interface・trait 情報、enum backing type、class constant、property も採取した。
worker の user 関数と self-test enum は target API から除外した。

PHP string の値と識別子は元バイト列を base64 で保持する。int は decimal string、float は IEEE-754 bits と NaN/±INF の分類を保持する。
array は順序付きの型付き key/value、enum は class/case/backing value として保存する。
resource と任意 object は未直列化であることを明示し、未取得 default と Reflection 例外も明示レコードにする。

INI は profile 起動時の `global_value` と現在の `local_value` を保存する。
`-d` の適用後の global 値を compiled factory default と取り違えないよう、後者は **UNMEASURED** とした。

## 検証と再現

- `encoding-check/report.json`：公式 PHP での特殊値輸送 **14/14 PASS**。
- `audit.json`：全 37 profile の hash/flags/固定 target、内部 API 限定、全 parameter と値輸送、13,934 leaf の一意 ID・元データ参照・signature 整合を検査して **PASS**。
- Reflection 収集例外 **0 件**。DLL の未ロードは別に残る。
- oracle、全 DLL、worker、driver の実行前後ハッシュが一致し、監査時点でも同一。

```powershell
python -B tools/oracle/api/verify_encoding.py --php C:\Users\rinpa\ALL_php_oracle\php-8.5.12-ts-x64\php.exe --output reports/php-api-inventory-NEW/encoding
python -B tools/oracle/api/inventory.py --php C:\Users\rinpa\ALL_php_oracle\php-8.5.12-ts-x64\php.exe --output reports/php-api-inventory-NEW/run
python -B tools/oracle/api/audit.py --run reports/php-api-inventory-NEW/run --output reports/php-api-inventory-NEW/audit.json
```

既存保存先の再利用・上書きは拒否する。各 process の timeout guard は **60 秒**で記録され、今回 timeout はない。
`run-01/summary.json`、`run-01/reproduce.json`、`run-01/inputs-before.json` と `inputs-after.json`、profile 別記録、ソーススナップショットとハッシュを参照できる。

Linux、CLI 以外の SAPI、拡張の組合せ、ロード失敗 DLL の API、任意の第三者拡張、factory INI defaults、候補の動作・ABI は **UNMEASURED**。
この union を PHP 全環境の網羅的な分母や、完全互換の証明として使用しない。

Reflection/INI の項目の意味は [ReflectionFunctionAbstract](https://www.php.net/manual/en/class.reflectionfunctionabstract.php)、[ReflectionParameter](https://www.php.net/manual/en/class.reflectionparameter.php)、[ini_get_all](https://www.php.net/manual/en/function.ini-get-all.php) を参照した。
