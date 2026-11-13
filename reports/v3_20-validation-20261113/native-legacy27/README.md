# Actual package: legacy native context profile

Actual package SHA-256 **`5856687f7abd1471b4af7af9827ca2d17a011e836ad2852bf1d7993298fddc9f`** was passed by absolute path to the frozen normal outer-Main host, using the old native core and bridge without `SetDiagnosticHandler`/`ClearDiagnosticHandler` methods.

**23/23 selected PHP sources matched exact raw stdout/stderr and actual process status** against independent PHP 8.5.12 reference processes. Four additional unsupported cases were rejected before native invocation, with actual process status 1; these guards are separate from the 23 compatibility comparisons. Input hashes remained unchanged and each case retained the 30 s timeout.

The selected cases cover native callable resolution, namespace precedence, first-class/dynamic/array callable forms, scalar values including NUL and int64 limits, caught errors, diagnostic source context and suppression. The guard cases retain the existing installed-error-handler, named-argument, populated-array and reference-return restrictions of this old profile. The new callback profile separately exercises synchronous error handlers.

`report.json` retains all commands, input hashes, raw channels, actual statuses and native metadata. `verification.json` independently checks raw equality for the 23 comparisons and pre-invocation rejection for the four guards. All 27 controlled cases recorded balanced module/request/TLS lifecycles and zero tracked request allocations. These counters do not prove general memory safety.

The driver, original fixture, host, return worker, old core, bridge and extension were frozen from `reports/native-callback-integration-20261113/`. No PHP source, expected value, diagnostic, whitespace or exit status was rewritten. This result concerns the pinned Windows x64 TS C `dl_test` scalar profile; it does not establish arbitrary extension compatibility, Linux or Web. The original PowerShell-worker TIMEOUT/CLR exit anomalies remain preserved and are not retroactively marked as passing.
