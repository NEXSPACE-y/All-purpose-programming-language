# 実package v3.19：NativeContext未指定のuser関数3例

実package絶対パス：`C:\Users\rinpa\ALL-php-compat-20261112\package\ALL_PHP_v3_12_adapter.ps1`。SHA-256：`113d0c2b967a8726cd9a9dec3f032a725ed9c98ee093c4aedd0a4830737f155b`。

元入力：`C:\Users\rinpa\ALL-php-compat-20261112\reports\native-php-integration-review-20261112\default-optout.cases.json`。SHA-256：`4f2a04f67f50f122a94c67e88b851ac860bf11aeceb758dfa1a62aed8b57529f`。元のJSON・PHP入力・期待条件を変更せず、公式PHP8.5.12と実packageへ同じsourceを与え、既存PhpCliCandidateWorkerでstdout/stderr生バイトと実process終了値を正規化なしで比較した。

**3/3 PASS、入力hash前後不変。** 意図したFatalを含む例はFatalの出力・終了値も比較している。全PHP言語・Web・ABIの完全互換認定ではなく、状態はNOT_COMPLETE。

NativeContextは未指定。native-opt-outの成功をnative preload互換の成功へ読み替えない。既存fixture・package・元報告は編集していない。

全command/source/hash/raw outputは`report.json`、要点は`summary.json`、実入力は`case-*.php`に保存。actual-package/workerのsnapshotも保存した。
