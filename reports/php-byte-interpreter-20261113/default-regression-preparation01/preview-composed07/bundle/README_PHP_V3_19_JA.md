# ALL PHP v3.19 — 独立native接続・関数登録と内部例外処理

PHP8.5.12 Windows向けの開発候補。PHP全体・CLI全体・ネイティブ拡張全体・Web・Linuxの完全互換は未達。

基準v3.18へ次を統合した。

- 任意のNativeContextを実評価器の名前解決・呼出し・型付きPHPエラー・診断へ接続。実登録された関数を検索し、対応するscalar呼出しを1回だけ実行する。
- 内部のThrowable文字列化をprelude専用ASTへ束縛。同名ユーザー関数で乗っ取られず、内部helperを公開関数として呼び出せない。preludeキャッシュも版を分離する。
- 同じ名前空間・symbol spaceでのimport alias重複を実行前に拒否。型別の大文字小文字規則と入力tokenの行情報を保持する。
- 現在の公開builtin registryと実native登録名に衝突するglobal関数定義を拒否。直下の宣言はプログラム実行前、条件内・入れ子の宣言は実際の登録時に判定する。

実装source SHA-256は `113d0c2b967a8726cd9a9dec3f032a725ed9c98ee093c4aedd0a4830737f155b`。
基準・各修正のhash・重ならない差分の統合記録は `tools/candidates/php-v3_19/provenance.json`。
既存965件の定義・期待値は変更せず、`ALL_PHP_v3_19_validate.ps1 -CompileCSharp`で確認する。
統合後の実行結果は `reports/v3_19-validation-20261112/` へ別に保存する。

native実行には承認済みのALL所有ABI DLLと別置きのC# bridgeが必要。検証hostは
`tools/abi/Invoke-NativePhpWorker.ps1`。未改変の公式拡張を事前ロードした実験profileであり、
ALLにPHPの全CLI extensionフラグや全拡張loaderが完成したという意味ではない。
NativeContextを省略した既定経路ではnative登録を公開しない。
公式PHPは別プロセスの照合側にだけ使い、候補の実行は委譲しない。

対応は選定したweak positional scalar profileに限る。user error handler、named native args、
arrays/refs/objects/resources等の未対応経路をnative実行前に拒否し、失敗後に別処理系で再試行しない。
完全なbinary string、同期native callback、lifecycle出力・診断、任意の第三者拡張ABI、Linux/Webは未完成。
別置きcallback prototypeは本版に含めていない。

未定義の動的callableのPHP Error分類にも既知差分が残る。全CLI引数/stdin/INI、strict_types、
generators/fibers、Reflection/attributes、全標準ライブラリなどの残件を合格へ読み替えない。
第2段階のALL自身のPHP完全対応・相互呼出し・データ共有も未完了である。
