# Four actual error-handler arguments

Official PHP 8.5.12 was observed with 12 callback forms. All eleven user handler
forms receive four actual values: integer level, raw PHP string message, PHP
string file and integer line. This includes zero/one formal parameters,
variadic functions/closures, first-class function references, static/instance
array methods and an invokable object. The builtin strlen callback reports
ArgumentCountError with four arguments given. The oracle process exited zero
with empty stderr. debug_backtrace is used only by this reference probe.

`CallbackArgumentEdits.py` removes exactly the existing declared-arity truncation
in Write-PhpDiagnostic. The four arguments already constructed by the byte
diagnostic path are passed intact. Get-PhpCallableArity remains unchanged. No old
callback fixture, expected output, native bridge or package is edited.

The isolated candidate is built on the frozen value-boundary draft and has
passed exact apply guards, CRLF/LF equivalence and PowerShell 5.1 parsing. It has
not been runtime measured. Parent schedules its interpreter run after the other
fixed profiles; no overlapping heavy loop was launched by this work.

`callback-arguments.cases.json` supplies fourteen new same-source observations.
Eight use PHP variadic capture to inspect all four arguments; four zero/one
formal controls, one builtin failure and one fixed-four control supplement them.
No candidate case uses func_num_args, func_get_args or debug_backtrace. These
fourteen message literals contain a literal backslash followed by xFF. Separate
`callback-raw2.cases.json` controls contain the PHP escape producing raw FF.
Neither definition set replaces or relabels the other. bin2hex is currently
absent from the adapter and the dl_test native context. Parent will implement an
independent byte builtin in HexBuiltinEdits before measuring these same sources;
NativeContext will not be required for it. The earlier assertion that the native
worker supplied bin2hex was incorrect and was corrected before any candidate
measurement. This report's built candidate does not yet contain that new builtin.

Existing fifteen legacy callback expectations stay untouched. The new cases and
the broader reference-only arity probe are separate evidence categories. Full
callback validation, reference semantics and diagnostic compatibility are not
certified by this small source patch.
