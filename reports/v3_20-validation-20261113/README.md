# PHP v3.20 actual-package checkpoint — incomplete

The isolated package adapter is
`5856687f7abd1471b4af7af9827ca2d17a011e836ad2852bf1d7993298fddc9f`.
It combines the independently developed literal, dynamic-call, CLI source-mode
and optional synchronous native diagnostic changes. The installed ALL and main
branch were not updated. This checkpoint predates the approved byte-model
migration; byte candidates are measured separately.

## Completed measurements

| Entry/profile | Result | Evidence |
| --- | --- | --- |
| Actual PS5.1 package default API | 965/965 PASS, exit 0, stderr 0 bytes | `default-api/verification.json` |
| Preflight | 102 PS scripts parse; 218 manifest entries; 2 C# helpers compile | `default-api/validation-summary.json` |
| Selected callback native source, normal outer-Main host | 15/15 exact comparisons | `native-callback15/verification.json` |
| Selected legacy native source, normal outer-Main host | 23/23 exact comparisons; 4 separate guards reject before native call | `native-legacy27/verification.json` |
| Actual independent CLI executable | 191/197 exact comparisons; 3 byte-model differences and 3 TIMEOUT | `cli197/report.json` |
| Separate examination of those 3 TIMEOUT inputs | 3/3 exact comparisons, same source/executable/30-second limit | `cli-timeout3-separate/report.json` |

The CLI197 result remains **191/197**. Its TIMEOUT observations are not replaced
by the later examination. Their cause has not been established. The byte-model
differences are octal FF, explicit FF, and surrogate-codepoint byte output.
All stdout/stderr comparisons are raw bytes, with actual process status and
no normalization. Selected fixture counts are not an exhaustive PHP denominator.

The default run took 793.190 seconds inside its validator and 799.064 seconds
for its parent process. No performance improvement is claimed. All 219 package
files matched their before/after snapshots. Original 940-test tracked sources
and expectations match the pinned original 34 paths. The broader regression
also includes the previously added 25 cases.

The default965, CLI197 and selected native groups use different entry profiles;
their counts must not be summed into a language-completion percentage. The CLI
case provenance describes which pre-existing source programs were fed to a file
entry point. Existing fixtures/expected results were not weakened.

## Remaining scope

PHP 8.5.12 full compatibility is not complete. Byte strings/keys and all their
operations/boundaries are being migrated separately after explicit approval.
Non-UTF8 source, general language/stdlib behavior, arbitrary native modules,
array/object/reference/resource ABI, all CLI options/INI/environment, Windows
Web SAPIs and Linux execution remain incomplete. ALL stage 2 has not started.

Old PowerShell-worker TIMEOUT/CLR exit abnormalities remain in their original
reports. The C# outer-Main host was measured independently; its success does not
establish that the old failure cause was repaired. Official PHP was used only
as an oracle, never to execute a candidate's program.

Integration composition and its manual lexical hook are reviewed in
`../php-v3_20-integration-review-20261113/`; sources and exact patch provenance
are under `tools/candidates/php-v3_20/` from the repository root.
