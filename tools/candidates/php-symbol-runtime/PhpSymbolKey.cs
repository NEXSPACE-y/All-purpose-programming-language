using System;
using System.Collections.ObjectModel;
using AllPhp.ByteValues;

namespace AllPhp.Symbols
{
    // These are registry domains, not PHP descriptor kinds. In particular,
    // classes/interfaces/traits/enums use the same ClassLike domain.
    public enum PhpSymbolKind
    {
        Function = 1,
        ClassLike = 2,
        Method = 3,
        Variable = 4,
        Property = 5,
        Parameter = 6,
        Constant = 7,
        ClassConstant = 8,
        Namespace = 9,
        FunctionImportAlias = 10,
        ClassImportAlias = 11,
        ConstantImportAlias = 12,
        Keyword = 13
    }

    // A key is not a PHP string or array key. It has no implicit text conversion,
    // Unicode normalization, numeric-string coercion, or API-specific validation.
    // Callers first resolve source qualification/runtime aliases into a logical
    // name. Original declaration spelling belongs to the descriptor, not a key
    // that a dictionary may retain from an earlier equal insertion.
    public sealed class PhpSymbolKey : IEquatable<PhpSymbolKey>
    {
        private readonly PhpSymbolKind kind;
        private readonly bool scoped;
        private readonly PhpBytes[] normalized;
        private readonly ReadOnlyCollection<PhpBytes> originalsView;
        private readonly ReadOnlyCollection<PhpBytes> normalizedView;

        private PhpSymbolKey(PhpSymbolKind kind, bool scoped,
            PhpBytes[] originals, PhpBytes[] normalized)
        {
            this.kind = kind;
            this.scoped = scoped;
            this.normalized = normalized;
            originalsView = Array.AsReadOnly(originals);
            normalizedView = Array.AsReadOnly(normalized);
        }

        public PhpSymbolKind Kind { get { return kind; } }
        public bool HasContainer { get { return scoped; } }
        public ReadOnlyCollection<PhpBytes> OriginalParts { get { return originalsView; } }
        public ReadOnlyCollection<PhpBytes> NormalizedParts { get { return normalizedView; } }

        private static bool FoldsWholeName(PhpSymbolKind value)
        {
            switch (value)
            {
                case PhpSymbolKind.Function:
                case PhpSymbolKind.ClassLike:
                case PhpSymbolKind.Method:
                case PhpSymbolKind.Namespace:
                case PhpSymbolKind.FunctionImportAlias:
                case PhpSymbolKind.ClassImportAlias:
                case PhpSymbolKind.Keyword:
                    return true;
                case PhpSymbolKind.Variable:
                case PhpSymbolKind.Property:
                case PhpSymbolKind.Parameter:
                case PhpSymbolKind.Constant:
                case PhpSymbolKind.ClassConstant:
                case PhpSymbolKind.ConstantImportAlias:
                    return false;
                default:
                    throw new ArgumentOutOfRangeException("value", "Unknown symbol registry domain");
            }
        }

        // Only a bounded interop buffer is int-sized; the name length, offsets
        // and prefix boundaries remain 64-bit. No complete name is flattened.
        private static long LastNamespaceSeparator(PhpBytes name)
        {
            long end = name.LongLength;
            byte[] chunk = new byte[65536];
            while (end != 0)
            {
                int count = (int)Math.Min(end, (long)chunk.Length);
                long start = end - count;
                name.CopyTo(start, chunk, 0, count);
                for (int i = count - 1; i >= 0; i--)
                    if (chunk[i] == 92) return start + i;
                end = start;
            }
            return -1;
        }

        public static PhpSymbolKey ForName(PhpSymbolKind kind, PhpBytes logicalName)
        {
            if (logicalName == null) throw new ArgumentNullException("logicalName");
            bool fold = FoldsWholeName(kind); // Validate the domain even for empty input.
            if (kind == PhpSymbolKind.Constant)
            {
                long separator = LastNamespaceSeparator(logicalName);
                if (separator >= 0)
                {
                    PhpBytes prefix = logicalName.Slice(0, separator);
                    PhpBytes leaf = logicalName.Slice(separator + 1, null);
                    return new PhpSymbolKey(kind, false,
                        new PhpBytes[] { prefix, leaf },
                        new PhpBytes[] { prefix.LowerAscii(), leaf });
                }
            }
            return new PhpSymbolKey(kind, false,
                new PhpBytes[] { logicalName },
                new PhpBytes[] { fold ? logicalName.LowerAscii() : logicalName });
        }

        // resolvedClassName denotes the descriptor/container selected by the
        // caller. This factory does not resolve class aliases, inheritance or
        // private-property ownership, and never joins opaque parts by a delimiter.
        public static PhpSymbolKey ForMember(PhpSymbolKind kind,
            PhpBytes resolvedClassName, PhpBytes memberName)
        {
            if (resolvedClassName == null) throw new ArgumentNullException("resolvedClassName");
            if (memberName == null) throw new ArgumentNullException("memberName");
            if (kind != PhpSymbolKind.Method && kind != PhpSymbolKind.Property &&
                kind != PhpSymbolKind.ClassConstant)
                throw new ArgumentException("Container keys require a method, property or class-constant domain", "kind");
            return new PhpSymbolKey(kind, true,
                new PhpBytes[] { resolvedClassName, memberName },
                new PhpBytes[] { resolvedClassName.LowerAscii(),
                    kind == PhpSymbolKind.Method ? memberName.LowerAscii() : memberName });
        }

        public bool Equals(PhpSymbolKey other)
        {
            if (ReferenceEquals(this, other)) return true;
            if (ReferenceEquals(other, null) || kind != other.kind ||
                scoped != other.scoped || normalized.Length != other.normalized.Length)
                return false;
            for (int i = 0; i < normalized.Length; i++)
                if (!normalized[i].Equals(other.normalized[i])) return false;
            return true;
        }

        public override bool Equals(object other) { return Equals(other as PhpSymbolKey); }

        public override int GetHashCode()
        {
            // This is an internal hash, never a persistent ID or Zend ABI hash.
            // Equal byte values supply equal content hashes independent of rope
            // shape. Full equality always resolves possible hash collisions.
            unchecked
            {
                uint hash = 2166136261u;
                hash = (hash ^ (uint)kind) * 16777619u;
                hash = (hash ^ (scoped ? 1u : 0u)) * 16777619u;
                hash = (hash ^ (uint)normalized.Length) * 16777619u;
                for (int i = 0; i < normalized.Length; i++)
                {
                    long length = normalized[i].LongLength;
                    hash = (hash ^ (uint)length) * 16777619u;
                    hash = (hash ^ (uint)(length >> 32)) * 16777619u;
                    hash = (hash ^ (uint)normalized[i].GetHashCode()) * 16777619u;
                }
                return (int)hash;
            }
        }
    }
}
