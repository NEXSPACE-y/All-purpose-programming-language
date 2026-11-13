# composed11 boundary profile, first measurement

Actual adapter/source SHA256:
`f7b61d06772ed661ac101347f454375ecfe8f18f952ea767f961cb77584e7706`.
One loop compared the actual compiled CLI with official PHP8.5.12 using the
same PHP source per side, exact raw channels/status and unchanged 30-second
limits. Comparator exit was 1. Driver inputs and 81 additional pins stayed
unchanged; all source hashes stayed unchanged. No candidate/input/expectation
was edited, no retry was performed and no timeout was extended.

| Group | Match |
| --- | --- |
| Original callback14 | 12/14 |
| Original raw callback2 | 2/2 |
| Original hex8 | 8/8 |
| Original value16 | 16/16 |
| Weak enum12 | 12/12 |
| Enum backing-type case2 | 2/2 |
| Array diagnostic4 | 3/4 |
| Trigger coercion8 | 1/8 |
| Total | 56/66 |

The ten differences are nine candidate TIMEOUT observations and one terminating
functional difference. The latter is byte.key-warning.quiet: candidate EXITED1
at 26.917s with strict-UTF8 host-text-boundary stderr, while PHP exits zero with
false/true/fallback. The source remained frozen; root prepared its quiet-path
repair in a separate later candidate.

The timeouts affect the first two callback cases and seven trigger coercion
examples. One timeout (closure-variadic) produced the exact expected stdout but
still failed process termination. Matching stdout is not PASS. Timeout causes
are undetermined; execution and shutdown require separate future phase tracing.
The supplied limit is unchanged for every case, and the original observations
remain authoritative for this source/hash. All measurement tool handles are
terminal; no claim is made about arbitrary unrelated system processes.

The original composed07 forty definitions are preserved as complete entries,
with the same source hashes and execution modes. Compared by their per-run
verdicts, the raw diagnostic repair now reaches and passes fourteen of sixteen
callback examples (two TIMEOUTs), and the former weak enum scalar difference
passes. Raw outputs are not compared across the different run directories.
The sixteen original value examples and fourteen new weak enum/type-case
examples pass on the same source hash. This does not certify strict_types,
full enums or full PHP/native/SAPI/Linux compatibility.

`process-observation01/02.json` and `journal-observation01/02.json` preserve
read-only own PID/parent/creation/commandline/CPU and already completed-case
states/elapsed times. They contain no process-control action or diagnosis by
assumption. Standard OS/.NET transitive dependencies are not claimed enumerated
as loaded modules. Later phase-traced or quiet-fixed candidates must have their
own evidence and must not relabel this run.
