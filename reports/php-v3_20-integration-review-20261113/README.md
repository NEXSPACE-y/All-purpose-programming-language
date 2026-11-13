# v3.20 integrated source: independent targeted review

Source SHA-256: **`5856687f7abd1471b4af7af9827ca2d17a011e836ad2852bf1d7993298fddc9f`**.

**No blocking integration defect found in this targeted review. Full PHP compatibility is not established.** Source was not edited and full965/runtime owner loops were not repeated.

- The existing native/callback manifest was checked first: **345 entries, zero mismatches**.
- All three input part hashes and their individual edit ranges were independently recomputed. Applying the **49 nonoverlapping edits** to exact base113d recreated the final source bytes, not merely an equivalent diff.
- Windows PowerShell5.1 read-only parse and builtin-registry check exited0: no syntax errors; all **78** dispatcher names/aliases matched the registry.

The manually combined lexer retains this order: outside-HTML/open/close-tag handling, then whole heredoc/nowdoc token scanning, then ordinary regex tokens. Doc and HTML tokens use distinct control-character prefixes (29/30), separate dictionaries and separate AST consumers. Neither raw body is converted into PHP source text for re-evaluation.

Literal compile validation skips interpolation evaluation and defers runtime string expansion to its expression node. InitialIni and argv/argc initialization precede compile-warning delivery. The initial lex call remains inside the literal error boundary. Prelude setup precedes optional native callback registration; the existing private prelude cache and namespace fallback save/restore remain intact.

The native path has one scalar-invocation site and one returned-output write branch, and it skips already-delivered diagnostic events. Optional Set/Clear checks protect older NativeContext implementations. Clear is guarded in finally, and the previous unsupported scalar boundary text remains. Dynamic invocation evaluates its callee expression once and chooses one argument-evaluation/dispatch branch after initial validation. Some callback paths revalidate the already-bound value; they do not re-run the original expression or argument AST. No invocation fallthrough was found.

`review.json` records source line anchors, checks, limitations and the exact read-only command. `composition-check.json` records the independently verified hashes and edit reconstruction.

Remaining literal limitations, general native ABI/value/callback/lifecycle work, Linux/Web execution and the original PS-worker exit anomalies remain outside completion. A possible pre-existing backslash/newline quote-tokenization gap was noted from the unchanged baseline regex; this review did not execute an oracle test for it and does not classify it as a newly introduced regression. Root's complete integration tests remain required evidence.
