# Import alias collision measurements

The final isolated source `c6dcc044e58682100eaba867381eb04f415364218ab981d04240d7fe8cdc016c` matched **23/23** selected cases in `final23/report.json`. The report includes input hashes, unchanged-input checks, real commands, raw stdout/stderr and exit codes for both processes. PHP is reference-only; the candidate does not delegate execution to it.

The original `before/` result is 4/17, and the first correction's `after-initial/` result is 17/17. `lines-initial/` preserves the subsequent 3/4 result; the split use statement was reported one line too early. `lines-final/` is 4/4 after the correction, followed by final23 on that exact corrected source. Earlier measurements were not overwritten or treated as the final candidate's results.

`reference-observation/` is exploratory reference output captured before the fix. The canonical final comparison is `final23/` using the shared strict process comparator, its documented flags and the same source file on both sides.

The official pinned source archive `php-8.5.12-1-src.zip` was read for `Zend/zend_compile.c` (`zend_compile_use`) and `Zend/zend_language_parser.y` import rules. Source was read as specification evidence; no PHP implementation component was adopted. The implementation retains separate import maps and their existing comparison rules.

See [candidate scope and reproduction](../../tools/candidates/php-import-alias/README.md). Full namespace semantics, all compiler errors, Linux, Web and the combined default regression remain outside this measurement. **NOT_COMPLETE**.
