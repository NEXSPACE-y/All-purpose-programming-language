# Existing error-message export lacks a byte length

The frozen legacy and callback cores expose `all_php_error_message(void)` as `tls.error.c_str()`. PHP string values, output and structured diagnostics already have lengths, so the new bridge can copy them without text decoding. The error-message export supplies no length and therefore cannot represent the portion after an embedded NUL to its caller.

The new `ByteScalarInvocation.ErrorMessage` copies the bounded C string into `PhpBytes` without UTF-8 decoding. It preserves invalid UTF-8 bytes before the terminator, but cannot claim lossless transport for an embedded-NUL error message or a message beyond the existing 16 MiB scan bound. Host error-class names and JSON metadata retain their separate text contracts. No frozen core source or DLL has been changed.

A possible additive own-ABI extension is `const char *all_php_error_message_bytes(size_t *length)`, returning `tls.error.data()` with `*length=tls.error.size()`, while preserving the old export. A separate core revision and source/build/runtime evidence would be required before adopting it. This document records the missing contract; it does not authorize or implement that core change.
