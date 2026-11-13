# PHP8.5 signed array-index history — selected source profile verified

Candidate `composed14-array`, adapter SHA-256
`e7ccae465117179f0a5cf55126e9b43a4f8f448b17f452650a945ab542a460d0`,
matched **40/40** unchanged PHP source programs with exact stdout/stderr bytes
and actual process status, using the original 30-second deadline. Comparator
exit was 0 and all recorded inputs matched before/after. Evidence is
`composed14-run01/report.json`; input lineage is in
`composed14-40-provenance.json`.

The profile includes 4 raw-key/quiet reads and 36 next-index cases. It checks
negative-first integer keys, integer history after unset, copied-array history,
signed MIN/MAX boundaries, saturated MAX allocation and its occupied-key Error,
reference append, pop retreat, shift reindexing, and unshift with no added values.

The array's existing `NextIndex` remains Int64. Its initial PHP_INT_MIN sentinel
is mapped to zero only for an append; explicit negative writes update signed
history. MAX saturates rather than overflowing to Double. An occupied automatic
key raises PHP Error before inserting. Pop retreats only when removing exactly
next-1, including negative values; removing string keys or unrelated numeric
keys preserves prior history. Shift sets history to the count of reindexed
numerics even for string-only output.

A draft incorrectly returned early from zero-value `array_unshift`. Review of
the fixed PHP source and 4 additional official programs proved that even with
zero added values, numeric keys are reindexed and old integer history is rebuilt.
The early return was removed before this candidate was executed. Draft
`composed12-index` and the original 32 oracle observations remain preserved;
the successful 40-case result belongs only to composed14. The corrected builder
also reproduced composed14's exact adapter hash from recorded module bytes in
`composed14-reproduce/`; that reproduction is not a second runtime test.

`ArrayQuietReadEdits.py` separately returns null for a missing key under the
existing quiet-read context before attempting legacy host-text error formatting.
This removes the observed invalid-UTF8 error in isset/empty/coalesce raw-key
control while preserving the ordinary non-quiet legacy API error contract.

Source review, exact official source locations and the unshift counterexamples
are in `review01/`. Active iterator mutation, general foreach/reference/COW
combinations, all array functions/native HashTable ABI, full PHP semantics,
Linux and Web SAPIs remain unverified by this selected profile. Original CLI252
and default965 have not yet been run on this candidate. Full compatibility and
ALL stage2 remain incomplete.
