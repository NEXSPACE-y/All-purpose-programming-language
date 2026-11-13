# Actual package v3.20: default API regression

**965/965 PASS, failures0, actual process exit0. This verifies the existing default API regression and preflight; PHP full compatibility remains NOT_COMPLETE.**

Executed adapter SHA-256: **`5856687f7abd1471b4af7af9827ca2d17a011e836ad2852bf1d7993298fddc9f`**.

A new Windows PowerShell **5.1.26100.9818 / Desktop** process executed the actual `package/ALL_PHP_v3_20_validate.ps1 -CompileCSharp`, through the capture script in this directory. It first passed syntax **102 scripts**, manifest **218 files**, and C# compilation **2 helpers**, then ran the unchanged default fixtures.

- The raw log contains **965 case PASS lines and zero FAIL lines**, including original940 and runtime-namespace25. The completion message was not used alone to count cases.
- Actual OS process exit was **0**, stderr **0 bytes**.
- All **219 package files**, including the manifest itself, have identical before/after length and SHA-256. A further read-only verification against the current files also matched all219.
- Original940's **34 tracked paths** (32 fixture collections, math fixture and original test script) have `git diff --exit-code` **0** before and after against `9d8171712828a0b57555b8eb1e1ca5c475391244`. No expectation or definition was changed.
- Validator duration **793.190s**, whole captured process **799.064s**. These are observations of this run, not a controlled performance comparison.

The two dynamically compiled C# helper assemblies had empty Location and no corresponding physical file was observed. No manual cleanup/delete action was performed.

`validation.stdout.bin` and `validation.stderr.bin` retain exact channels; `.log` copies contain the same bytes. `validation-process.json` records the executed validator, PID, timestamps, duration and requested status; actual terminal status is separately captured in `validation-summary.json`. PowerShell version, source/driver hashes, before/after package hashes and old940 Git checks are retained alongside them. `verification.json` independently checks the required counts and all current package hashes.

`run-validation.py` refuses an existing execution record. A later observation must verify the recorded PID/command or live tool session rather than assume that a state file proves liveness. For a fresh rerun, use a new report directory/capture path; do not overwrite this record.

This task did not execute installed ALL and did not certify SQL/HTTP runtime merely from compilation. CLI/literal/dynamic/native comparisons are separate evidence owned by the parent task; they are not added to the965 count here. Linux, Web, general native ABI and full PHP semantics remain outside this regression's proof.
