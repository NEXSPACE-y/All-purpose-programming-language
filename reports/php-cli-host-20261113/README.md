# Actual independent CLI host measurements

**Development evidence, NOT_COMPLETE.** The PHP8.5.12 reference is executed only as the oracle. The actual ALL executable hosts the independent interpreter in its own .NET Framework process.

Final measured CLI source for this checkpoint: `42c17b474209afced61ee99c18b0b064d700041e5fd2ed0c69919b257754003a`.

| Revision / input set | Exact process comparison |
|---|---:|
| initial19 | 17/19; missing-file channel/newline and pre-source `--` behavior differed |
| revision02-19 | 18/19; empty stdin still rejected |
| revision03-19 | 19/19 |
| file-tags-revision04 | 15/18 |
| file-tags-revision05 | 17/18 |
| file-tags-revision06 | 18/18 |
| extra-revision06 | 12/15; shebang file/stdin and forbidden code-body opening-tag diagnostics differed |
| [revision07-all52](revision07-all52/report.json) | **52/52**, unchanged inputs, actual exits match |

Final52 concatenates the unmodified19+18+15 case records, with the three source hashes in `tools/cli/cli-all52.provenance.json`. No expectations were changed to match the candidate. All stdout/stderr bytes and actual exit codes are compared without trimming, newline conversion or diagnostic replacement. Matching invalid-input/error cases are included; this is not a count of52 implemented PHP features or a completeness percentage.

The earlier case ID `tags.short-disabled` was named before the compiled default was measured. Its actual profile contains no disabling override, and the reference executes the short tag. The later explicit `short_open_tag=0` cases test the disabled state. Both the original ID/input and this correction are preserved.

`file-tags-before03/` has no final report after its original observation handle disappeared. Its partial source artifacts are retained but it is not included as a completed measurement. No result count is inferred from generated source directories.

File source transitions are represented by dedicated `inline_html` AST nodes. Comments and quoted strings retain their own lexical boundaries, rather than replacing PHP input with generated echo statements. The CLI body mode preserves actual input lines. The initial namespace-after-HTML error is raised before program output. Subsequent parser and error semantics outside this measured set remain incomplete.

`host-load-observed.json` is one resource snapshot taken during the work, not a performance benchmark or proof of timeout cause. Other concurrent prototype measurements encountered timeouts; those reports remain distinct from this successful final52 run. This run retains its own fixed30-second per-process guard and executable/host/adapter/case/driver hashes.

The current package113d and installed ALL were not replaced. The final snapshot/build records are in `revision07-artifacts/`; full default965 and cross-candidate integration have not been claimed for this standalone source. See [build steps and limits](../../tools/cli/README.md).
