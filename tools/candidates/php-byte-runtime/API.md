# Immutable PHP byte runtime candidate, runtime01

This assembly stores PHP data as immutable bytes. It does not execute PHP, call the official PHP interpreter, or supply PHP string argument coercion / loose equality / diagnostics policy. The interpreter helpers own those language rules. Windows PowerShell 5.1/.NET Framework 4 x64 execution is measured; Linux execution is unverified.

Canonical namespace: `AllPhp.ByteValues`; assembly: `AllPhp.ByteValues.Runtime.dll`.

## Pins and measured scope

- Source `PhpByteRuntime.cs`: SHA256 `334f24c9f714c707f81923abfcb9aae8a94a9c38a7aa77f9c8e0fd996424ca42`.
- Frozen DLL `out/runtime01/AllPhp.ByteValues.Runtime.dll`: SHA256 `18d50efb55d8a333424149e4ab37428e102b1ac938240e50358ee3c8ab89466b`.
- Existing 75 operation protocol cases and four raw-stdout probes match the PHP 8.5.12 oracle exactly, with process exit/stdout/stderr captured and inputs unchanged. This is a component protocol, not interpretation of the same PHP source by ALL.
- Twenty added synthetic storage contracts pass. Full `WriteTo` reads all **2,147,549,311 actual bytes** through 32,770 bounded writes; independent Python hashlib computes the same SHA256 `66c81101f9e1de6e28357bf9c807ef01f55c25c608b85995be5eda835e3099af`. The production value also supports tested long-index reads, slices, COW edits, space extension, bitwise maps and overflow rejection. No two-gigabyte array or file is needed. The worker peaked at 89,161,728 bytes working set in this run; this is a measured process result, not a general allocation bound.
- The prototype's former Int32 storage-capacity refusal is superseded by this measured long storage. Its frozen old proof remains unchanged. `ToArray` still intentionally bounds a host array export; storage, chunk copy and output have long lengths.

## Public surface

`PhpBytes` is sealed and immutable. `FromBytes(byte[])` copies caller data. `FromBase64(string)` and strict `FromUtf8(string)` construct values. `FromStream(Stream)` synchronously copies until EOF into privately owned 64KiB leaves; it neither retains nor closes the source. A bridge with a declared native length must separately check the final Length, because EOF itself is not proof of that declared length.

`Length` and `LongLength` are Int64. `GetByte(long)` bounds-checks; `CopyTo(long, byte[], int, int)` validates the complete range and copies in bounded chunks. `WriteTo(Stream)` and `WriteTo(Stream,long,long)` write real chunks without flattening. `ToArray` / `ToBase64` are small interop exports; `ToArray` rejects values above Int32.MaxValue. `TryDecodeUtf8(out string)` is strict and likewise bounds a host-string export. `ToString()` throws to prevent an implicit PHP byte-to-host text conversion.

`Concat`, `Slice(long,long?)`, `Repeat(long)` and static `Fill(byte,long)` return immutable values. Negative slice/count semantics are component operations already compared against PHP. `ReadOffset(long)` / `WithOffset(long,PhpBytes)` return `OffsetResult` with immutable `Value`, `ErrorClass`, `WarningLevel`, and host diagnostic `Message`; the caller emits the actual PHP diagnostic. `WithOffset` copies only the edited value's node structure and does not alter the original.

`Equals` is exact bytes; `CompareBinary` returns -1/0/1. `LowerAscii` / `UpperAscii` leave bytes above ASCII unchanged. `BitwiseNot`, `Bitwise(PhpBytes,char)`, `Truthy`, and `TryArrayInteger(out long)` avoid Unicode normalization. Canonical integer-key syntax is ASCII-only and checked against Int64 limits.

`GetHashCode` covers all bytes through chunks, caches on the immutable instance, and gives byte-equal values the same result across rope/view/repeat shapes. The current FNV1a implementation is deterministic, but persistent / cross-version hash stability is not part of the public contract. Do not serialize hashes as identities. `ChunkSize` is 65,536; `ContractVersion` is 1. `StorageHeight` diagnoses the balanced concatenation spine, not total composed-view depth.

`PhpKey.FromInteger(long)` and `PhpKey.FromString(PhpBytes)` produce typed PHP array keys with canonical integer-string coercion. `IsInteger`, `IntegerValue`, `BytesValue` expose the kind; a wrong-kind accessor throws. `Protocol` is a bounded diagnostic i:/s: export, not the PHP value or normal output. `ToString` throws. Symbol-name normalization belongs to a separate context-aware symbol component, not to `PhpKey`.

`OrderedByteMap` is a bytes-valued specialization only. Generic PHP arrays may keep arbitrary objects and reference cells in the existing OrderedDictionary with `PhpKey` keys; typed-key support does not require restricting their values to bytes.

`PhpByteBuilder.Append(PhpBytes)`, `AppendBytes(byte[])`, `AppendUtf8(string)`, `AppendAscii(string)`, `ToPhpBytes()`, `Clear()` and long `Length` provide byte formatting without host string concatenation. Append methods return void, avoiding PowerShell pipeline output. Input byte arrays are copied, ASCII/UTF-8 failures are explicit and atomic, and published snapshots remain immutable after further append/clear. The mutable builder is request-local and does not promise concurrent mutation safety.

## Storage and remaining validation

Private AVL concatenation nodes, leaf arrays, slice views, fully specified fill/pattern/repeat nodes and byte transformation nodes preserve long lengths with checked arithmetic. Iterative read work avoids CLR recursion across deeply composed views; 2,500 nested repeat/slice operations were read back. Repetition represents real specified bytes, including full-output verification above Int32; it is not an arbitrary declared length or empty stub.

No complete Int64.MaxValue traversal, multi-gigabyte independent nonrepeating input ingestion, PHP memory_limit/exhaustion behavior, concurrency stress, Linux execution, interpreter-wide string migration, native ABI integration, SAPI execution, or ALL interoperability is certified by these component checks. Those boundaries remain separate. No mandatory new dependency is introduced beyond the existing .NET/C# toolchain.

Rebuild into a fresh directory with `Build-ByteRuntime.ps1 -OutputDirectory ...`; never overwrite runtime01. Rollback consists of leaving the prior component/core unchanged and selecting its recorded assembly pin. Existing PHP fixtures, package source and prototype reports were not replaced by this candidate.
