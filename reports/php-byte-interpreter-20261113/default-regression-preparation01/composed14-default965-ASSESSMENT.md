# byte14 default API regression — completed observation

The unchanged v3.20 default validation command with `-CompileCSharp` completed
in isolated `composed14-prepared01/bundle` under Windows PowerShell 5.1 x64.
The adapter SHA256 was `e7ccae465117179f0a5cf55126e9b43a4f8f448b17f452650a945ab542a460d0`.
No retry, expected-value change or timeout change was made.

- Actual PowerShell process exit: 0; 965/965 assertions PASS in original order.
- Original 940 summary and additional namespace 25 summary both matched.
- The two C# helpers actually compiled and loaded: AllSqliteDriver and
  AllConcurrentGateway. This is assembly/type evidence, not a native database or
  concurrent application workload certification.
- Raw stdout: 59,361 bytes; raw stderr: 0 bytes. Driver duration: 751.603 seconds.
- All 19 final integrity/counter checks passed. Source package 219 files, candidate
  bundle 219 files, original 34 tracked fixture paths, installed ALL.ps1 and all
  pinned driver/runtime inputs were unchanged before/after.
- Installed ALL was not executed; main SHA256 remains
  `79bf8b7fb4cebb7be2527fa9e61b331b74eb299ee247ed9dc3169e30985c7951`.
- Canonical byte runtime remained
  `18d50efb55d8a333424149e4ab37428e102b1ac938240e50358ee3c8ab89466b`.

Evidence is in `composed14-default965-run01/summary.json`,
`validation-process.json`, `validation.stdout.bin`, `validation.stderr.bin`,
`process-start.json` and the before/after hash snapshots.

This establishes this candidate's historical default API regression result,
including the original refusal guards/parity cases. It is not a same-source
comparison to official PHP, CLI/SAPI certification, native extension ABI or Linux
validation, nor a complete PHP compatibility claim. The separate CLI252 timeouts
remain recorded failures in their original report.
