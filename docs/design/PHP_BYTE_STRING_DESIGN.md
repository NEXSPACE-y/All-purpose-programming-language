# PHP byte-string値モデルの具体設計

文書状態：**方式1は2026-11-13に所有者承認済み。隔離候補でproduction部品・本体への段階的適用を実装・検証中**。PHP完全互換は未完了。承認記録は [PHP_BYTE_MODEL_APPROVAL_20261113.md](../decisions/PHP_BYTE_MODEL_APPROVAL_20261113.md)。以下の提案時の根拠・代案・復旧方法は保存し、最新の測定状況は `docs/ACTIVE_WORK.json` と各reportで区別する。

## 1. 判断してほしい内容

PHPの文字列値を、Unicodeの`.NET System.String`から、**型を明示した不変byte値**へ移す方式1を推奨する。配列の文字列keyもtyped keyへ移し、出力とnative境界でUnicodeへ暗黙変換しない。識別子・診断の固定文言・OSの文字列は、PHPの値と区別して扱う。

既存のnative設計「案A」とこの値モデル全体の適用範囲が一致するかは、rootが承認記録と照合する。本書は追加の所有者承認を得た記録ではない。仕様9.1が求める、現物依存、変更理由・利点、影響、代案、既存テスト、復旧方法を具体化した資料である。根本変更のcoreへの適用はその判断前に行わない。新たなOS導入、PHP C componentの採用、実行の公式PHPへの委譲、native実行core全体への移行は、本提案では行わない。

承認対象を「FFだけ許す例外処理」や「UTF8に収まる範囲」に縮めない。PHP8.5.12、Windows11x64/Linuxx64、既存native binaries、全対象SAPIという既存の目標を保つ。64bitの値長、全byte値、非UTF8データの演算・key・入出力も残る要件である。

## 2. 現物と観測根拠

依存調査の固定基準はv3.19アダプタSHA-256 `113d0c2b967a8726cd9a9dec3f032a725ed9c98ee093c4aedd0a4830737f155b`。rootがpackageを更新しても、`tools/candidates/php-cli-host/base113d.snapshot.ps1`と保存済みinventoryを参照できる。以下の行番号はこのhash版だけを指す。

| 根拠 | 観測・限界 |
|---|---|
| `reports/php-string-literals-20261113/assessment.json` | 48例中45一致。FFを含むoctal、単独FF、surrogateのUTF8byte列ED A0 80が、現Unicode値モデルでは明示拒否となる。これら3件は未対応のまま総数に保持 |
| `reports/php-byte-string-20261113/dependency-inventory-pinned113d.json` | 静的な行pattern調査。アダプタはstring型/castを含む234行、text操作119行、ToPhpText/出力63行、s:key変換等34行。重複を含み、値・識別子・metadataの区別は要レビュー。変更件数や網羅率ではない |
| `reports/php-identifiers-20261113/php-comparisons/report.json` | 固定PHPの関数名検索はASCII byte fold。É/é・Σ/σ等を同名としない。strtolowerもASCII範囲だけを変換する一次実測 |
| `reports/php-identifiers-20261113/dotnet51-comparisons.json` | 現.NET/PS5.1のOrdinalIgnoreCaseとPHP検索が相違。PS `-ceq`もNFC/NFDやK/Kを同一視する例がある。単にcase-sensitive指定するだけではbyte等価にならない |
| `reports/php-identifiers-20261113/registry-rules/report.json` | 識別子担当の一次実測では、名前付きconstantはnamespace prefixをASCII foldし、leaf名をraw case-sensitiveとして検索する。全registryを同じfold規則にしてはならない |
| `reports/php-byte-string-20261113/component02-extended75/report.json` | 隔離C# byte値とPHP referenceの同一operation入力75件が全record・実終了値・stdioで一致。PHPソース処理系を検証した結果ではない |
| `reports/php-byte-string-20261113/component02-boundaries.json` | 防御copy・strict UTF8境界・暗黙文字列化拒否・配列storage容量の明示拒否を4/4確認。代案の破損反例も保存 |

値比較にも影響する。固定sourceの`Php-Equal`3390–3403付近はstring strict equalityにPS `-ceq`を使う。`Compare-PhpArrays`3352付近もkeyのstrict比較に`-cne`を使う。`Compare-Values`3408付近のUTF16 ordinal順序は、U+10000とU+E000のUTF8 byte順と逆になる。実componentはこの組もPHPの順序と一致し、negative controlはUTF16順序との相違を確認した。

`.NET StringComparer.Ordinal`の等価性は、有効UTF8をlosslessにUnicodeへ変換した値どうしなら区別を保つ。ただし非UTF8byte列を表現できず、UTF16順序もbyte順そのものではない。`OrdinalIgnoreCase`、culture比較、PSの`-eq/-ceq`は別の問題を持つ。全host文字列を無差別に置換するのではなく、用途を分類する必要がある。

## 3. 3方式の比較

| 方式 | 利点 | 主要な変更・危険境界 | 判断 |
|---|---|---|---|
| 1. tagged immutable managed bytes | 全byteを区別。host textとの型混同を防ぐ。値copyは不変object共有でよい。既存CLR上で実装でき、native request寿命に依存しない | PHPのstring判定・演算・key・出力・JSON/native等を明示APIへ移す必要。巨大値には64bit storage設計が必要 | **推奨**。隔離componentで具体APIを実測済み |
| 2. Latin1 carrier string | byte→同番号UTF16 code unitとすればLength/index/ordinal等価は扱いやすく、既存`is string`を維持できる | 通常Unicode文字列と区別不能。Console/UTF8/native/JSONへ通すと再encoding。Unicode casefoldやPS比較も誤適用され得る。結局境界と演算の大幅監査が必要 | 不採用を推奨。厳密な全境界管理があれば実装可能だが、今回の既存構造では暗黙破損を検出しづらい |
| 3. own-native string handle | ABIのzend_stringと近く、size_t長・native操作・将来zero-copyに適する | retain/release、GC finalizerとowner thread、request終了、DLL unload、shared-data寿命を結び付ける。純PS経路にもnative DLLが必須になる可能性。既存native request trackerはforeign-thread freeを拒否する | 今回の既定値modelには選ばない。将来storage backendとして検討できるが、所有権・展開依存を別途実証する |

Latin1反例は抽象的な懸念だけではない。FFをcarrierへ写して通常UTF8出力するとC3 BFになる。C3 80をcarrierとしてUnicode lowerへ通すとE3 80になり、通常Unicode文字列としてlowerしてもC3 A0になる。一方、対象PHPのASCII-only strtolowerはC3 80を保持する。出力・大小文字変換を一箇所直すだけでは不十分である。

native案は既存のALL所有coreを捨てる案ではない。`native/php85abi/src/Runtime.cpp`の`string_new`91付近は`bytes + size_t len`を持ち、raw ABI probeは既に任意byteを運べる。現在の`InvokeScalar`がUTF8文字列へ戻す箇所を、byte値へのcopyに変えるのが方式1の初期接続になる。managed keyのhashをnative Zend hashとして使ってはならない。

## 4. 推奨する値・key・境界API

`PhpBytes`はsealedなCLR型で、PHPから偽装できる文字列tagだけに頼らない。入力byte配列と外部へ返す配列は防御copyする。暗黙の`ToString()`は失敗させ、取りこぼした`[string]`castが見かけの文字列を作らないようにする。通常のPHP string castは別の`ToPhpBytes`として実装する。

隔離実装の具体APIは `tools/candidates/php-byte-string/PhpByteValues.cs` にある。

| API・意味 | 統合時の扱い |
|---|---|
| `FromBytes / FromBase64 / FromUtf8` | source escapeのbyte結果、host UTF8 text、native bytesを区別して入れる。FromUtf8はhost text専用でstrict変換 |
| `Length` | byte数。PHPのstrlen/offset/substr/strposもbyte単位。現在のUTF16 `.Substring/.IndexOf`を流用しない |
| `Equals / CompareBinary` | byte単位・culture非依存。numeric-stringのloose比較は別段階でPHP規則を適用。componentのbinary比較を全loose比較の代わりにしない |
| `Slice / ReadOffset / WithOffset` | 不変値を返し、offset writeは変数/配列/propertyの既存cellへ新しい値を戻す。参照cellのaliasは同じcellを更新し、単なる値copyは元の値を保つ |
| `Concat / Bitwise / BitwiseNot / LowerAscii` | 結果が非UTF8になってもbyte値のまま保持。Unicode casefoldを使わない |
| `Truthy` | 空文字列と一byteのASCII `0`だけがfalse。他のNUL/FF等はそのまま判定 |
| `TryDecodeUtf8` | JSON等、実際にUTF8を要求する境界だけで使う。失敗時に置換しない。APIごとのPHPフラグ/診断へ接続 |
| `PhpKey.FromString / FromInteger` | PHPのASCII整数key coercion後の型と値を保持。`0`と`-0`、`1`と`01`、Int64境界/overflow、NUL/FF、正規化の違うUnicodeを区別 |
| `OrderedByteMap` | 上書き時も最初の挿入位置を維持。component用managed hashは内部実装でありPHP/native hash互換証明ではない |

数値key以外のbool/null/float変換、offsetの型coercion・全診断優先順位、loose equality全体は、componentで完了した機能ではない。既存の型変換仕様を読み直して統合する。

### 容量とstorage

現在のcomponentはprivate `byte[]`なのでInt32長の配列容量を越える操作を明示拒否する。**この制限をPHP64bitの受入れ仕様にはしない。** `Length`/offsetの公開契約は64bitとし、productionでは`IByteStorage64`相当のsegmented storageまたは承認済みnative storageを必要とする。大きな値のslice view、chunk単位COW、streamへのchunk出力を実装し、`ToArray()`を通常出力の必須経路にしない。巨大値・allocation failureのPHP互換は未実証である。

## 5. 現物依存と具体的な移行箇所

| 固定sourceの入口 | 現状 | 必要な変更・守ること |
|---|---|---|
| `Copy-PhpValue`2561 | array以外をそのまま返す | 不変PhpBytesの共有は可能。offset書込は新値を正しいcellへ戻し、reference aliasと値copyを混同しない |
| `To-PhpText`3247 | stringへfallback cast、`__toString`の結果も.NET string判定 | `ToPhpBytes`へ分離。数値/bool/nullはPHP表現のASCII bytesへ。host text変換を独立APIにする |
| `To-Number`3273、numeric parser3019 | `.NET string`経由の解析 | ASCII byte grammarでPHPのnumeric/full-prefix判定を実装。Unicode `\d/\s`やculture parsingを流用しない |
| `Is-Truthy`3287、`Php-Equal`3374、`Compare-Values`3408 | string型とPS/Unicode演算 | PHP value kindの中央判定へ。strict bytesとnumeric/boolean loose規則を分離 |
| `To-PhpKey`3298、array/foreach/keys/JSON等 | `i:`/`s:`付きhost stringで保存し、Substringで逆変換 | 全key利用をtyped keyへ。base64 wireをPHPのkey値として漏らさない。挿入順/上書き/参照は保持 |
| typed値3511、`gettype/is_string`、enum backing | `[string]`判定 | PhpBytesをPHP stringとして認識。識別子・type名のhost stringまで機械置換しない |
| string builtins4561/4836以降 | strlenはUTF8再encoding、substr/strposはUTF16、大小文字はUnicode | bytes APIで値を処理。各functionの型変換・負offset・警告等も別途照合 |
| JSON2806/2862 | Unicode serializer/manual quote | UTF8妥当性とPHPのignore/substitute/throwフラグを境界で実装。invalid bytesの値自体を破棄しない |
| echo/print/dump/Throwable diagnostics | Consoleのtext writerへ変換 | requestのbyte sinkへ統一。既存native output bytesと順序を保つ。metadata文字列は明示encoding、PHP値/messageはraw bytesとして組み立てる |
| `AllNativeBridge.cs`142以降 / callback bridge | string入力をUTF8 encoding、string戻りと出力をstrict decode | PhpBytesの入力をpointer+lengthへ。戻りを解放前にmanaged所有bytesへcopy。byte出力のUTF8検証は不要にし、text diagnosticの境界と分離 |
| source入力/lexer | 多くの経路がstrict UTF8 source text | ASCII escapeからの全byte値だけで完了としない。raw source byte、byte offset、識別子bytes、OS path encodingを別途対応 |
| ALL plugin/CLI | Language別Run入口。PHP/ALLの共有値bridgeは未完成 | 第2段階でbyte値をlosslessに共有する契約が必要。ALL textへ暗黙変換せず、binary値または明示codec viewを用意。第2段階の実装開始を意味しない |

識別子も、PHPのbyte識別子へ移す必要がある。ASCII foldはA–Zだけを小文字化し、É/éやΣ/σを同名にしない。ただし**arrayの`PhpKey`と文脈別の`PhpSymbolKey`は別契約**とする。function/class/methodのcaseless検索、variable/property等のcase-sensitive名、namespace prefixだけをfoldする名前付きconstantを混同しない。class constant/enum case/import alias等も文脈を確定してから実装する。全名をfoldする共通辞書や全名をrawにする共通辞書では足りない。

識別子担当の実測では、PHPはemoji・NBSP・先頭combining markも識別子として受理した。`.NET Unicode Letter`だけのlexerへ置き換える案では要件を満たさない。byte値・byte符号名の保存と、kindごとの妥当性・namespace分割・foldを別にする。NUL等の制約も対象API/内部名の種類ごとに照合し、string値のNUL対応を全symbolへ機械的に適用しない。既存Vars/ConstantsのOrdinal辞書が有効UTF8で区別を保つことと、全byte識別子対応は別である。PS比較やUnicode comparerをvalue/key/symbolに無差別に使わない。

## 6. 統合の順序と受入れ証拠

1. 承認境界をrootが照合し、適用する値方式・storage段階・対象経路を固定する。既存CLI/literal/callback等の最新checkpointへ再調査する。113dへの設計行番号を最新sourceへ盲目的に適用しない。
2. `GetPhpValueKind / IsPhpString / ToPhpBytes / ToHostText`とtyped keyを隔離candidateへ入れる。host metadataとPHP値を分類し、literalだけPhpBytesにして他の`is string`が値を誤分類する中間状態を配布しない。
3. literal、代入/参照cell、型、比較/key、基本演算、raw outputを一貫して結ぶ。現literal48例の3差分を、拒否ではなく本来のbyte出力で一致させる。Latin1 carrierへの置換や公式PHPのfallbackはしない。
4. stdlib、JSON、source入力、native input/return/output/diagnostic、SAPI、ALL将来bridgeの境界をそれぞれ明示する。nativeではGC/finalizerからrequest-owned pointerを解放する方式へ勝手に広げない。
5. 元の期待値を変えずdefault965、CLI/file modes、literal48、callable、namespace/cache、native74/bridge24/callback/synthetic契約等を対象hashで再測定する。変更による本当の旧契約衝突は消さずに対応表を出す。
6. Linuxx64・Web各SAPI・全native/標準API・巨大値・I/O byte境界も別の証拠が必要。componentの75件や4 raw出力を全要件の分母にしない。全PHPやstage2の完了認定は既存ACに従う。

今回のcomponentはWindows x64 / PowerShell5.1.26100.9818 / CLR4.0.30319.42000で実測した。DLL SHA-256 `f5297c6522d4aa702424879c4d733c5de495b4fc18f040e0c88865771fba816f`、C# source SHA-256 `63bd6eeb6b903c2521d8b0500a8f9440d1ccba28ed4ee6f885c25cca2cd357f0`。単にbuildできた結果とは分け、75 operation record、FF/NUL/ED A0 80/all256byteのraw stdout4件、synthetic境界4件を別集計した。最初のcomponent67/70の不一致も保存し、対象Windows PHPのbinary比較返値へ実装を修正している。Linuxでの同一実行は未確認である。

## 7. 復旧方法と未完了事項

現在はcoreを変更していないため、既存packageの復旧操作は不要。component/DLL/reportsは独立ディレクトリに保存している。将来の統合は専用branchと新規build directoryに限定し、変更前adapter/manifest/native boundary hashと直前の検証済checkpointを残す。問題が出ればその統合commitを分離branchでrevertし、旧bundleを新しいhost processで起動して再検証する。.NET Framework assemblyやnative DLLを同じprocess中で入れ替えたと偽らない。導入済みALL・main・他の未保存変更・既存報告を削除して戻さない。

未完了：production64bit storage、全PHP文字列/識別子/stdlib/JSON/診断/OS I/O、全native所有権・ABI、Linux/Web、ALL相互呼出し・共有data。本案とcomponentの採用だけでこれらを完成扱いにしない。所有者が方式を判断できる具体資料と実測を用意した段階である。
