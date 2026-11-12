# Isolated callback ABI core

This option-A prototype is separate from `native/php85abi` and the installed/package runtime. See [the prototype design](../../tools/candidates/php-native-callback/DESIGN.md) and [scope, reproduction, and limitations](../../tools/candidates/php-native-callback/README.md).

The core is independently built as `out/windows-x64-ts/php8ts.dll`. It owns its values/state and does not import or forward to stock PHP. Only the isolated callback managed host should load it for this experiment; that host enforces the pinned C dl_test hash. A successful build establishes compilation/linkage only. Runtime evidence is recorded separately in `reports/native-callback-20261112`.

`out/`, SDK extraction, and compiler/linker binaries are ignored locally. Keep source/header/build instructions and report logs/hashes under version control. Removing or retaining this isolated tree does not alter the frozen package or native runtime.
