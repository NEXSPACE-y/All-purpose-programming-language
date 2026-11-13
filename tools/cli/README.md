# Independent PHP CLI prototype

This is an ALL-owned Windows x64 executable using the existing Windows PowerShell 5.1/.NET Framework interpreter in the same process. It does not spawn stock PHP or submit PHP source to PowerShell as script code. User arguments are passed as objects to the host; PHP source is data consumed by the independent parser.

**Prototype only. Full PHP/CLI compatibility is not complete and package adoption has not occurred.** The installed ALL and the current package are unchanged by this work.

Revision07 interpreter source: `42c17b474209afced61ee99c18b0b064d700041e5fd2ed0c69919b257754003a`.
The actual executable, body/file/stdin input, argument globals, diagnostic profile and exit status matched **52/52** selected same-input comparisons. See [measurements and retained failures](../../reports/php-cli-host-20261113/README.md).

Implemented in this profile:

- `-r`, `-f`, positional file input, stdin without a source file, and `--` argument boundaries.
- Exact argv transport, including spaces/quotes/backslashes/Unicode; `$argc`, `$argv` and the corresponding `$_SERVER` argument entries.
- Actual PHP code-body mode for `-r`, without adding an artificial opening tag.
- Outside-PHP text as dedicated AST nodes; PHP tags, short echo tags, enabled/disabled short tags, closing-tag newline handling, shebang and BOM handling for the measured UTF-8 source profile.
- Engine exit values mapped to real Windows process exit values; warnings/parser errors use their recorded source context.

The fixed test profile is `-n -d display_errors=stderr -d error_reporting=-1 -d date.timezone=UTC`. Only these INI values and `short_open_tag=0/1` are accepted so far. The measured Windows target has short tags enabled under `-n`; the host sets that explicit initial value. This is not a cross-platform compiled default assertion.

INI discovery/loading, other directives and CLI options, full `$_SERVER`/environment initialization, interactive mode, lint/info/module modes, streaming modes, signals, full arbitrary byte strings and binary source, Web SAPIs and Linux execution remain incomplete. Unsupported flags/directives are rejected explicitly. `-f -` was observed to reject the missing filename `-` in this target; it is not treated as a substitute for stdin.

## Rebuild and measure

Choose fresh output paths. The generator rejects an input that differs from the pinned113d source; the build does not install the result.

```powershell
python -B tools/candidates/php-cli-host/Build-CliHostCandidate.py --base tools/candidates/php-cli-host/base113d.snapshot.ps1 --output-directory tools/candidates/php-cli-host/NEW --file-lexer
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/cli/Build-AllPhpCli.ps1 -AdapterPath tools/candidates/php-cli-host/NEW/ALL_PHP_cli_host_candidate.ps1 -OutputDirectory tools/cli/out/NEW
python -B tools/cli/Compare-AllPhpCli.py --executable tools/cli/out/NEW/all-php.exe --cases tools/cli/cli-all52.cases.json --output reports/NEW-cli --timeout 30
```

Build output is ignored under `out/`; build manifests, source snapshots and runtime evidence are retained in reports. Full965 regression and integration with the other candidate branches are separate checks still required before adopting the combined source.
