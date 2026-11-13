# Unchanged gettext extension: measured component checkpoint

The new independent callback core loaded the unchanged PHP8.5.12 Windows x64
TS `php_gettext.dll` and completed the original51 frozen cases. **49 matched,
0 failed, and2 required catalog translations were not observed.** All51 native
and reference processes exited0. `run05/report.json` preserves exact raw
stdout/stderr, per-operation values/errors/events, module identities, invocation
counts, lifecycle/cleanup checks and before/after hashes. All pinned inputs
remained unchanged; the deadline remained30 seconds and calls were not retried.

The core is `out/callback05/php8ts.dll`, SHA256
`96df49fe6a7dd83c3462c2b92d0b14922e0f292b2cf80212e47242a8932fdef3`.
Its own source is `generated05/callback/src/Runtime.cpp`, SHA256
`304d6e5178b24c6daa8bf56c6e29c07f892a1e9967e1bb9f0e38fa09a6c59521`.
The extension SHA256 remains
`ed395f80018920ba1b4551cdc33dd89871eb8b8ef362b1515ae93c0e7f1de3ad`.
Static PE inspection found no stock-PHP core imports or forwarded exports;
actual native-process module checks identified only this own core and the
unchanged extension as PHP modules. Official PHP ran separately as the oracle.

## Preserved failure and correction

`run04/report.json` remains48 matches,1 failure and2 unobserved translations.
Its nullable argument TypeError said `bool given`; the target said `true given`.
The pinned target `Zend/zend_API.c` distinguishes value-name diagnostics from
type names (lines156–172 and292–309, member SHA256
`b4cb01a5b771981572c060436570f2504f02b1647be0090968f6c7f0ad616a2e`).
The new own helper formats true/false literally only at the argument-error
producer. It does not replace unrelated type names. The same original failing
case matched on05; the remaining original cases were also rerun on the new code.
Additional false/weak/other-argument controls are still separate pending work.

Revision04 also separates an overlong initial CWD failure from UTF8 conversion
failure and preserves a failed Win32 attribute query's mapped errno. Existing
owned-path cases match, including Unicode and virtual-CWD isolation. Those51
cases did not specifically exercise overlong initial-CWD or raced attribute
query failure branches; build success is not runtime proof of those branches.
Original03 sources, binaries, fragments and preparation are retained unchanged.

## Catalog and broader limits

The two original catalog cases are **not passes**. Both engines returned the
untranslated message despite accepting the requested CRT locale. Run05 records
the effective locale environment: `LC_ALL=C.UTF-8`, `LANG=C.UTF-8`,
`LC_CTYPE=C.UTF-8`, `LANGUAGE=zz_ALL`, and no `LC_MESSAGES`. Run04 did not record
all inherited locale variables; later observations do not reconstruct that run.

The separate `../php-gettext-locale-20261113/oracle01/report.json` varies eight
process-local environment profiles without changing the original51 or MO file.
Five profiles produced actual official singular/plural translations, while
three produced identity. That is official-only discovery, with zero native
compatibility passes. Matching native execution on those additional conditions
remains pending; it must not overwrite the original two unobserved cases.

This is selected extension component evidence. General ABI, native arrays,
objects/references/resources/lifetimes, code-page/path corner cases, other
extensions, Linux, Web SAPIs and full PHP compatibility remain incomplete.
