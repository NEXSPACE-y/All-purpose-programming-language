# Correction to the earlier callback fixture description

The frozen callback README previously said its original fourteen cases used a
literal backslash followed by xFF as the runtime message. That description was
incorrect. The original PHP source contains the bytes
`112 97 121 108 111 97 100 92 120 70 70` for `payload\xFF`: one PHP-source
backslash before xFF. PHP's double-quoted string parser produces runtime byte FF.

The composed07 first measurement confirms the official reference handler sees
`7061796c6f6164ff` when the message is inspected with bin2hex. The sixteen callback
cases (original fourteen and the two later controls) have always retained their
original source bytes. No input, expected value or candidate was replaced or
edited to obtain this observation. The earlier frozen report is preserved, and
this correction records the mistaken interpretation explicitly.

The separate earlier claim that dl_test NativeContext supplied bin2hex was also
incorrect and had already been corrected before measurement. composed07 now
contains root's independent HexBuiltinEdits implementation; no native context
is required for bin2hex here.
