# Combined03 byte interpreter: existing native source fixtures

The frozen legacy source fixture produced **23/23 exact raw stdout/stderr and actual process-status matches** with PHP8.5.12. Four additional unsupported cases were rejected before any native function invocation and remain separate from compatibility passes. The driver terminated with actual status0, all inputs retained their before/after hashes, and the timeout stayed30s.

This profile executes the same PHP source file through each process. The candidate uses combined03 `4d120c8f...c9e13a9c`, the copied legacy byte bridge from build05, the frozen own legacy core and unchanged original dl_test extension. The canonical runtime01 original file is loaded before the bridge; its assembly location is recorded per case. A new outer C# Main owns normal process exit after disposing its PowerShell runspace.

The existing fixture and expected behavior were not edited. `report.json` retains commands, source hashes, raw channels, actual statuses and native lifecycle metadata; phase traces remain separate from PHP stdout/stderr. The original PowerShell-worker TIMEOUT/CLR records were not retried or reclassified.

These are selected Windows x64 TS dl_test source cases. They do not prove general ABI compatibility, raw byte identifiers, Linux, Web or full PHP compatibility. The two independent module-info component differences remain unchanged and are not counted here.
