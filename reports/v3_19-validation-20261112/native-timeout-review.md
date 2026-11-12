# Native TIMEOUT 記録の独立確認

既存 3 report、対応 metadata、保存済み source bytes のみを比較した。追加のプロセス実行・既存記録の変更はしていない。

- **初回 `native27`：22/23 一致＋1 TIMEOUT、別枠 guard 4/4。**
  唯一の `native.catch_count_error` は stdout/stderr が公式 PHP と同じでも、実 process は **TIMEOUT、exit code は null、30.132 秒**。
  このケースを PASS へ読み替えない。
- 対応 metadata は native invocation 1、request start/end と MINIT/MSHUTDOWN・RINIT/RSHUTDOWN が各 1、記録上の選択終了値 0。
  これは metadata 書出しまでの状態であり、実 process の終了成功ではない。metadata は `Environment.Exit` より前に書かれ、退出呼出しの実行・完了を独立に記録していない。
- **単独再測定：1/1 一致。** 同じ source bytes で実 **EXITED / exit 0、9.188 秒**、native invocation **1**、worker と全入力の前後 hash 一致。
- **全 27 再測定：通常 23/23 一致＋別枠 guard 4/4。** 同じケースも実 **EXITED / exit 0、9.191 秒**、native invocation **1**。
  初回と全再測定の case IDs・全 27 program bytes・元ケース集合 hash が一致。単独試験の集合 hash は 1 ケースの subset なので異なるが、対象 program bytes は 3 回とも同一。

3 回で adapter/core/extension/worker/bridge、公式 PHP、PowerShell、凍結 base の hash はすべて一致し、各 report の前後入力 hash も一致した。
対象 adapter は `113d0c2b967a8726cd9a9dec3f032a725ed9c98ee093c4aedd0a4830737f155b`。

**同じ timeout 30 秒という根拠は、root が残した各 `exec_command` の実引数記録に限る。**
この 3 report 自体には timeout 秒数・driver argv/hash がないため、JSON だけから独立に確認できたとは記述しない。
後から既存 report へ設定値を追加していない。

全再測定は full 965 完了後に同 timeout 30 秒で実行されたが、他 agent の比較も並行していた。
並列負荷を固定した性能比較ではなく、「静かな条件」「負荷ゼロ」とは扱わない。
後の成功は確認できる一方、**初回 TIMEOUT の原因は未特定**。高負荷や cleanup 停止など、原因を断定しない。

元の失敗と 2 段階の再測定はすべて保持され、互いを上書きしていない。比較結果と report/metadata hash は `native-timeout-review.json` に保存した。
