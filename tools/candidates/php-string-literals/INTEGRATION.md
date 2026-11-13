# Integration contract

The frozen base is package v3.19 SHA-256 `113d0c2b967a8726cd9a9dec3f032a725ed9c98ee093c4aedd0a4830737f155b`. Package and original fixtures have not been modified by this task. Each generated revision has its own exact bytes, patch and provenance; existing revisions and reports are not overwritten.

The current candidate is `revision05/ALL_PHP_string_literal_candidate.ps1`, SHA-256 `e150594bb520e984fcb61a9288b695a044271b11559dcc5d8ceda4fae9ab3bb2`. Runtime measurement is separate from generation.

For the root's CLI file lexer, retain its HTML/PHP mode transitions and add the following **after outside-HTML and close-tag handling, immediately before ordinary token matching**:

```powershell
$doc = Read-PhpDocToken $text $offset $line
if ($null -ne $doc) {
    [void]$tokens.Add($doc.Token); [void]$lines.Add($line)
    $offset += $doc.Length; $line += $doc.Newlines
    continue
}
```

`Read-PhpDocToken` uses the unchanged input text and offset. It returns null for ordinary tokens, or `{Token, Length, Newlines}` for a heredoc/nowdoc or binary-prefix quoted token. Heredoc payloads are stored in `state.DocStrings`, keyed by `[char]29 + 'DOC:' + sequence`; this is distinct from the root's `[char]30 + 'HTML:'` token channel. The closing label is consumed; its following punctuation remains for the ordinary PHP parser. A binary string prefix is lexically lowered to its equivalent ordinary string token without changing source bytes.

Other required edits are recorded in `literal.patch`:

- Add `DocStrings` and `LiteralWarnings` to Run state; insert `LiteralHelpers.ps1.fragment` before the tokenizer.
- Wrap the **initial source tokenization** in the existing structured ParseError/exit255 route. Preserve the root's FileMode/StartsInPhp call in that wrapper. Prelude tokenization continues using its normal PHP mode.
- Recognize DocStrings in Read-Primary and lower to literal or double-string AST with body/line metadata. Quoted double strings validate escape syntax during parsing.
- Replace Expand-PhpDoubleString with the byte-buffer implementation, and pass optional body/heredoc/line metadata from Invoke-PhpExpr. Old cached prelude AST nodes without these properties retain the existing quoted-token path.
- Emit queued literal compiler warnings **after host InitialIni setup and after diagnostic helpers are defined, before any program statements**. Runtime `error_reporting()` calls and user handlers must not retroactively suppress or intercept a compiler warning.

Literal validation does not execute interpolation, and does not reject unsupported interpolation in unexecuted branches. Runtime simple interpolation uses actual variable slots. The existing default API's quiet missing-variable result is preserved; CliContext/PhpDiagnostics expose the PHP warning. The original v3.3 guard for complex interpolation remains an explicit unsupported path.

The helper's mixed-closing-indent diagnostics model scanner ordering: literal segments before interpolation are indentation-checked before the final malformed marker is reached; a non-interpolated body/nowdoc reaches that marker before its pending newline count is committed. The official source and separately captured oracle probes support this distinction.

No PHP C implementation component was adopted. See `reports/php-string-literals-20261113/official-source-reference.json` for the pinned source archive and scanner entry hashes.

## Representation boundary

The runtime still uses .NET strings. The decoder constructs PHP escape bytes and decodes them with strict UTF-8 only when the literal is evaluated. Valid UTF-8, NUL, Unicode scalar escapes, and matching hex/octal UTF-8 sequences are lossless. Invalid UTF-8 and surrogate codepoint encodings raise explicit engine unsupported errors; no replacement character or alternate PHP execution is used. Those refusals are **not PHP conformance passes**.

This is a literal boundary improvement, not a complete PHP byte-string value model. Other runtime string operations, complex interpolation, every malformed lexer/parser diagnostic, arbitrary source byte encodings, all Web/Linux profiles, and full PHP compatibility remain unproven or incomplete. Do not extrapolate selected comparisons to those requirements.
