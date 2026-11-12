# 実package v3.19 cached Run隔離

実package絶対パス：`C:\Users\rinpa\ALL-php-compat-20261112\package\ALL_PHP_v3_12_adapter.ps1`。SHA-256：`113d0c2b967a8726cd9a9dec3f032a725ed9c98ee093c4aedd0a4830737f155b`。

元のcached10 source fileのバイト列をそのまま新しい測定先へコピーし、元source hashとの同一性を確認した。parityごとに新規PS5.1 processを使い、その中では旧native47 adapterの通常cache warmup1件、実package4Runを順に実行。内部cacheはreset/injectionしていない。

**10/10一致（旧adapter warmup2件＋実package Run8件）**。元入力・実package・worker・公式PHP等のhashは前後不変。

各RunのConsole文字列をUTF-8化し、同じPHP入力を独立した公式PHP8.5.12 processで動かしたstdout/stderr bytesと比較した。Run contextの終了値と実process終了は区別する。旧warmup2件を実packageの実行件数に加えていない。全CLI/SAPI/任意バイナリ文字列の完全互換証明ではない。

`run-01/report.json`に全比較、各parityの`sequence.json`・`observed.json`・実source・worker process記録を保存。`run_actual_package.py`の--packageは絶対パス必須で、期待hash不一致なら停止する。元候補・元報告・fixture・packageは編集していない。
