# Combined03 byte interpreter: four additional raw native source cases

**4/4 PHP source programs matched exact raw stdout/stderr and actual status** against separate PHP8.5.12 processes. These new cases cover FF return/echo, native NUL printf semantics followed by an echo retaining NUL, surrogate UTF-8 bytes, and every nonzero byte returned and echoed. Each own native function ran once; no fallback/retry occurred. The timeout remained30s and input hashes were unchanged.

The programs execute through combined03 `4d120c8f...c9e13a9c` with the frozen own callback core and new byte bridge build05. The worker preloads the canonical runtime01 original assembly before loading the bridge; a normal outer C# Main owns process exit. The comparison driver terminated with actual status0.

The original native/callback fixtures remain separate and unchanged. This additional fixture does not replace their expected values. The unchanged dl_test function truncates its printf-style return at NUL; the NUL case records that actual behavior and separately emits the full PHP byte string. It is not evidence that the native printf result retains a NUL suffix.

Full channels, commands, source hashes, actual statuses and controlled teardown are in `report.json`. This profile covers selected Windows x64 TS C dl_test behavior. It does not establish complete native ABI, binary diagnostic generation by dl_test, raw byte names, Linux, Web or full PHP compatibility. Independent module-info output differences remain failed and are not counted here.
