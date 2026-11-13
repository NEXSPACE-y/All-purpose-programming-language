# Combined03 byte interpreter: existing synchronous callback sources

**15/15 frozen callback PHP sources matched exact raw stdout/stderr and actual process status** against separate PHP8.5.12 reference processes, including handler exit7. The comparison driver ended with actual status0 and all source/worker/host/runtime/bridge/core/extension/fixture hashes remained unchanged. The original timeout remained30s.

This is a new integration profile: combined03 `4d120c8f...c9e13a9c`, canonical runtime01 original assembly preloaded before byte bridge build05, and the frozen own synchronous callback core. Source execution uses the new byte diagnostic/value interface and normal outer-Main process exit. The existing fixture and expected channels/status were not edited.

Cases cover handled/default diagnostics, reporting masks and suppression, throw/exit, native reentry, recursive diagnostics and restoring a handler during the call. `report.json` contains complete commands, source hashes, raw channel bytes, actual statuses and controlled native teardown metadata. Phase traces are outside the PHP channels.

This selected Windows x64 TS C dl_test profile does not establish arbitrary native callbacks, general memory safety, Linux, Web or full PHP compatibility. Old PowerShell-worker failures and independent module-info differences remain unchanged.
