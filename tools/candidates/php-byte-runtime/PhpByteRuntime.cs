using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text;
using System.Threading;

namespace AllPhp.ByteValues
{
    // PHP data bytes. Host metadata/text require an explicit encoding boundary.
    // Storage nodes and published data are immutable. CopyTo uses an iterative
    // work stack so composed views do not consume the CLR call stack.
    public sealed class PhpBytes : IEquatable<PhpBytes>
    {
        public const int ChunkSize = 65536;
        public const int ContractVersion = 1;
        private abstract class Store
        {
            internal readonly long Length; internal readonly int Height;
            protected Store(long length, int height) { if (length < 0) throw new ArgumentOutOfRangeException("length"); Length = length; Height = height; }
        }
        private sealed class ArrayStore : Store
        {
            internal readonly byte[] Bytes;
            internal ArrayStore(byte[] bytes) : base(bytes.LongLength, bytes.Length == 0 ? 0 : 1) { Bytes = bytes; }
        }
        private sealed class Branch : Store
        {
            internal readonly Store Left, Right;
            internal Branch(Store left, Store right) : base(checked(left.Length + right.Length), Math.Max(left.Height, right.Height) + 1) { Left = left; Right = right; }
        }
        private sealed class SliceStore : Store
        {
            internal readonly Store Parent; internal readonly long Offset;
            internal SliceStore(Store parent, long offset, long length) : base(length, 1) { Parent = parent; Offset = offset; }
        }
        private sealed class FillStore : Store
        {
            internal readonly byte Byte;
            internal FillStore(byte value, long length) : base(length, length == 0 ? 0 : 1) { Byte = value; }
        }
        private sealed class PatternStore : Store
        {
            internal readonly byte[] Pattern;
            internal PatternStore(byte[] pattern, long length) : base(length, length == 0 ? 0 : 1)
            { if (pattern.Length == 0 && length != 0) throw new ArgumentException("Empty repeat pattern"); Pattern = pattern; }
        }
        private sealed class RepeatStore : Store
        {
            internal readonly Store Unit;
            internal RepeatStore(Store unit, long length) : base(length, 1) { if (unit.Length == 0) throw new ArgumentException("Empty repeat unit"); Unit = unit; }
        }
        private sealed class MapStore : Store
        {
            internal readonly Store Parent; internal readonly byte[] Map;
            internal MapStore(Store parent, byte[] map) : base(parent.Length, 1) { Parent = parent; Map = map; }
        }
        private sealed class BinaryStore : Store
        {
            internal readonly Store Left, Right; internal readonly char Operation;
            internal BinaryStore(Store left, Store right, char operation) : base(operation == '|' ? Math.Max(left.Length, right.Length) : Math.Min(left.Length, right.Length), 1)
            { Left = left; Right = right; Operation = operation; }
        }
        private sealed class Work
        {
            internal Store Source; internal long Position; internal byte[] Buffer, Other, Map;
            internal int Offset, Count, Action; internal char Operation;
            internal static Work Read(Store source, long position, byte[] buffer, int offset, int count)
            { return new Work { Source = source, Position = position, Buffer = buffer, Offset = offset, Count = count }; }
        }

        private static readonly Store EmptyStore = new ArrayStore(new byte[0]);
        public static readonly PhpBytes Empty = new PhpBytes(EmptyStore);
        private static readonly byte[] LowerMap = MakeMap(0), UpperMap = MakeMap(1), NotMap = MakeMap(2);
        private readonly Store store;
        private int cachedHash, hashReady;
        private PhpBytes(Store value) { store = value; }
        public long Length { get { return store.Length; } }
        public long LongLength { get { return store.Length; } }
        public int StorageHeight { get { return store.Height; } }
        public bool Truthy { get { return Length != 0 && !(Length == 1 && GetByte(0) == 48); } }

        private static Store Balance(Store left, Store right)
        {
            if (left.Length == 0) return right; if (right.Length == 0) return left;
            if (left.Height > right.Height + 1)
            {
                Branch l = (Branch)left;
                if (l.Left.Height >= l.Right.Height) return new Branch(l.Left, new Branch(l.Right, right));
                Branch middle = (Branch)l.Right;
                return new Branch(new Branch(l.Left, middle.Left), new Branch(middle.Right, right));
            }
            if (right.Height > left.Height + 1)
            {
                Branch r = (Branch)right;
                if (r.Right.Height >= r.Left.Height) return new Branch(new Branch(left, r.Left), r.Right);
                Branch middle = (Branch)r.Left;
                return new Branch(new Branch(left, middle.Left), new Branch(middle.Right, r.Right));
            }
            return new Branch(left, right);
        }
        private static Store Join(Store left, Store right)
        {
            if (left.Length == 0) return right; if (right.Length == 0) return left;
            if (left.Height > right.Height + 1)
            { Branch l = (Branch)left; return Balance(l.Left, Join(l.Right, right)); }
            if (right.Height > left.Height + 1)
            { Branch r = (Branch)right; return Balance(Join(left, r.Left), r.Right); }
            return new Branch(left, right);
        }
        private static byte[] MakeMap(int operation)
        {
            byte[] map = new byte[256];
            for (int i = 0; i < 256; ++i) map[i] = operation == 0 && i >= 65 && i <= 90 ? (byte)(i + 32) : operation == 1 && i >= 97 && i <= 122 ? (byte)(i - 32) : operation == 2 ? (byte)~i : (byte)i;
            return map;
        }
        private static void FillBuffer(byte[] buffer, int offset, int count, byte value)
        {
            if (count == 0) return; buffer[offset] = value; int filled = 1;
            while (filled < count) { int size = Math.Min(filled, count - filled); Buffer.BlockCopy(buffer, offset, buffer, offset + filled, size); filled += size; }
        }
        private static void CopyPattern(PatternStore pattern, long position, byte[] destination, int offset, int count)
        {
            int phase = (int)(position % pattern.Pattern.Length), seed = Math.Min(count, pattern.Pattern.Length);
            int first = Math.Min(seed, pattern.Pattern.Length - phase);
            Buffer.BlockCopy(pattern.Pattern, phase, destination, offset, first);
            if (seed > first) Buffer.BlockCopy(pattern.Pattern, 0, destination, offset + first, seed - first);
            int filled = seed;
            while (filled < count) { int size = Math.Min(filled, count - filled); Buffer.BlockCopy(destination, offset, destination, offset + filled, size); filled += size; }
        }
        private static void ReadChunk(Store source, long position, byte[] destination, int offset, int count)
        {
            if (count == 0) return;
            Stack<Work> pending = new Stack<Work>(); pending.Push(Work.Read(source, position, destination, offset, count));
            while (pending.Count != 0)
            {
                Work work = pending.Pop();
                if (work.Action == 1)
                { for (int i = 0; i < work.Count; ++i) work.Buffer[work.Offset + i] = work.Map[work.Buffer[work.Offset + i]]; continue; }
                if (work.Action == 2)
                {
                    for (int i = 0; i < work.Count; ++i)
                    {
                        byte a = work.Buffer[work.Offset + i], b = work.Other[i];
                        work.Buffer[work.Offset + i] = work.Operation == '&' ? (byte)(a & b) : work.Operation == '^' ? (byte)(a ^ b) : (byte)(a | b);
                    }
                    continue;
                }
                ArrayStore array = work.Source as ArrayStore;
                if (array != null) { Buffer.BlockCopy(array.Bytes, checked((int)work.Position), work.Buffer, work.Offset, work.Count); continue; }
                FillStore fill = work.Source as FillStore;
                if (fill != null) { FillBuffer(work.Buffer, work.Offset, work.Count, fill.Byte); continue; }
                PatternStore pattern = work.Source as PatternStore;
                if (pattern != null) { CopyPattern(pattern, work.Position, work.Buffer, work.Offset, work.Count); continue; }
                SliceStore slice = work.Source as SliceStore;
                if (slice != null) { pending.Push(Work.Read(slice.Parent, checked(slice.Offset + work.Position), work.Buffer, work.Offset, work.Count)); continue; }
                Branch branch = work.Source as Branch;
                if (branch != null)
                {
                    if (work.Position >= branch.Left.Length) pending.Push(Work.Read(branch.Right, work.Position - branch.Left.Length, work.Buffer, work.Offset, work.Count));
                    else
                    {
                        int leftCount = (int)Math.Min((long)work.Count, branch.Left.Length - work.Position);
                        if (leftCount < work.Count) pending.Push(Work.Read(branch.Right, 0, work.Buffer, work.Offset + leftCount, work.Count - leftCount));
                        pending.Push(Work.Read(branch.Left, work.Position, work.Buffer, work.Offset, leftCount));
                    }
                    continue;
                }
                RepeatStore repeat = work.Source as RepeatStore;
                if (repeat != null)
                {
                    List<Work> pieces = new List<Work>(); int copied = 0; long phase = work.Position % repeat.Unit.Length;
                    while (copied < work.Count)
                    { int amount = (int)Math.Min((long)(work.Count - copied), repeat.Unit.Length - phase); pieces.Add(Work.Read(repeat.Unit, phase, work.Buffer, work.Offset + copied, amount)); copied += amount; phase = 0; }
                    for (int i = pieces.Count - 1; i >= 0; --i) pending.Push(pieces[i]);
                    continue;
                }
                MapStore map = work.Source as MapStore;
                if (map != null)
                {
                    pending.Push(new Work { Action = 1, Buffer = work.Buffer, Offset = work.Offset, Count = work.Count, Map = map.Map });
                    pending.Push(Work.Read(map.Parent, work.Position, work.Buffer, work.Offset, work.Count)); continue;
                }
                BinaryStore binary = work.Source as BinaryStore;
                if (binary != null)
                {
                    Array.Clear(work.Buffer, work.Offset, work.Count); byte[] other = new byte[work.Count];
                    int leftCount = work.Position < binary.Left.Length ? (int)Math.Min((long)work.Count, binary.Left.Length - work.Position) : 0;
                    int rightCount = work.Position < binary.Right.Length ? (int)Math.Min((long)work.Count, binary.Right.Length - work.Position) : 0;
                    pending.Push(new Work { Action = 2, Buffer = work.Buffer, Offset = work.Offset, Count = work.Count, Other = other, Operation = binary.Operation });
                    if (rightCount != 0) pending.Push(Work.Read(binary.Right, work.Position, other, 0, rightCount));
                    if (leftCount != 0) pending.Push(Work.Read(binary.Left, work.Position, work.Buffer, work.Offset, leftCount));
                    continue;
                }
                throw new InvalidOperationException("Unknown immutable byte storage node");
            }
        }
        private static PhpBytes FromOwned(byte[] bytes)
        {
            if (bytes.Length == 0) return Empty;
            Store result = EmptyStore;
            for (int position = 0; position < bytes.Length;)
            {
                int count = Math.Min(ChunkSize, bytes.Length - position);
                byte[] part;
                if (position == 0 && count == bytes.Length) part = bytes;
                else { part = new byte[count]; Buffer.BlockCopy(bytes, position, part, 0, count); }
                result = Join(result, new ArrayStore(part)); position += count;
            }
            return new PhpBytes(result);
        }
        public static PhpBytes FromBytes(byte[] bytes)
        { if (bytes == null) throw new ArgumentNullException("bytes"); return FromOwned((byte[])bytes.Clone()); }
        public static PhpBytes FromBase64(string value) { return FromOwned(Convert.FromBase64String(value)); }
        public static PhpBytes FromUtf8(string value) { return FromOwned(new UTF8Encoding(false, true).GetBytes(value)); }
        public static PhpBytes FromStream(Stream source)
        {
            if (source == null) throw new ArgumentNullException("source"); if (!source.CanRead) throw new ArgumentException("Stream is not readable", "source");
            Store result = EmptyStore;
            while (true)
            {
                byte[] part = new byte[ChunkSize]; int used = 0;
                while (used < part.Length) { int read = source.Read(part, used, part.Length - used); if (read == 0) break; used += read; }
                if (used == 0) break;
                if (used != part.Length) { byte[] shortPart = new byte[used]; Buffer.BlockCopy(part, 0, shortPart, 0, used); part = shortPart; }
                result = Join(result, new ArrayStore(part)); if (used < ChunkSize) break;
            }
            return result.Length == 0 ? Empty : new PhpBytes(result);
        }
        public static PhpBytes Fill(byte value, long length)
        { if (length < 0) throw new ArgumentOutOfRangeException("length"); return length == 0 ? Empty : new PhpBytes(new FillStore(value, length)); }
        public PhpBytes Repeat(long count)
        {
            if (count < 0) throw new ArgumentOutOfRangeException("count"); if (count == 0 || Length == 0) return Empty; if (count == 1) return this;
            long length = checked(Length * count);
            FillStore fill = store as FillStore; if (fill != null) return Fill(fill.Byte, length);
            PatternStore oldPattern = store as PatternStore; if (oldPattern != null) return new PhpBytes(new PatternStore(oldPattern.Pattern, length));
            RepeatStore oldRepeat = store as RepeatStore; if (oldRepeat != null) return new PhpBytes(new RepeatStore(oldRepeat.Unit, length));
            if (Length == 1) return Fill(GetByte(0), length);
            if (Length <= ChunkSize) return new PhpBytes(new PatternStore(ToArray(), length));
            return new PhpBytes(new RepeatStore(store, length));
        }
        public void CopyTo(long sourceOffset, byte[] destination, int destinationOffset, int count)
        {
            if (destination == null) throw new ArgumentNullException("destination");
            if (sourceOffset < 0 || sourceOffset > Length || count < 0 || (long)count > Length - sourceOffset) throw new ArgumentOutOfRangeException("sourceOffset");
            if (destinationOffset < 0 || destinationOffset > destination.Length || count > destination.Length - destinationOffset) throw new ArgumentOutOfRangeException("destinationOffset");
            while (count > 0) { int part = Math.Min(count, ChunkSize); ReadChunk(store, sourceOffset, destination, destinationOffset, part); sourceOffset += part; destinationOffset += part; count -= part; }
        }
        public byte GetByte(long offset)
        { if (offset < 0 || offset >= Length) throw new ArgumentOutOfRangeException("offset"); byte[] b = new byte[1]; ReadChunk(store, offset, b, 0, 1); return b[0]; }
        public byte[] ToArray()
        {
            if (Length > Int32.MaxValue) throw new NotSupportedException("ToArray is a bounded interop API; use CopyTo or WriteTo for long PHP bytes");
            byte[] result = new byte[(int)Length]; CopyTo(0, result, 0, result.Length); return result;
        }
        public string ToBase64() { return Convert.ToBase64String(ToArray()); }
        public void WriteTo(Stream destination) { WriteTo(destination, 0, Length); }
        public void WriteTo(Stream destination, long offset, long count)
        {
            if (destination == null) throw new ArgumentNullException("destination"); if (!destination.CanWrite) throw new ArgumentException("Stream is not writable", "destination");
            if (offset < 0 || offset > Length || count < 0 || count > Length - offset) throw new ArgumentOutOfRangeException("offset");
            byte[] buffer = new byte[ChunkSize];
            while (count > 0) { int part = (int)Math.Min(count, buffer.Length); CopyTo(offset, buffer, 0, part); destination.Write(buffer, 0, part); offset += part; count -= part; }
        }
        public bool TryDecodeUtf8(out string text)
        {
            if (Length > Int32.MaxValue) throw new NotSupportedException("Decoded host text is bounded; preserve long PHP data as bytes");
            try { text = new UTF8Encoding(false, true).GetString(ToArray()); return true; }
            catch (DecoderFallbackException) { text = null; return false; }
        }
        public override string ToString() { throw new InvalidOperationException("PhpBytes requires an explicit raw-byte or strict decoded-text boundary"); }
        public PhpBytes Concat(PhpBytes right)
        { if ((object)right == null) throw new ArgumentNullException("right"); return new PhpBytes(Join(store, right.store)); }
        public PhpBytes Slice(long offset, long? count)
        {
            long start = offset < 0 ? Math.Max(Length + offset, 0) : Math.Min(offset, Length), end = Length;
            if (count.HasValue) end = count.Value < 0 ? Math.Max(start, Length + count.Value) : start + Math.Min(count.Value, Length - start);
            long length = Math.Max(0, end - start); if (length == 0) return Empty; if (start == 0 && length == Length) return this;
            SliceStore old = store as SliceStore; return new PhpBytes(old == null ? new SliceStore(store, start, length) : new SliceStore(old.Parent, checked(old.Offset + start), length));
        }
        public OffsetResult ReadOffset(long offset)
        {
            long position = offset < 0 ? Length + offset : offset;
            if (position < 0 || position >= Length) return new OffsetResult(Empty, "", 2, "Uninitialized string offset " + offset.ToString(CultureInfo.InvariantCulture));
            return new OffsetResult(FromOwned(new byte[] { GetByte(position) }), "", 0, "");
        }
        public OffsetResult WithOffset(long offset, PhpBytes replacement)
        {
            if ((object)replacement == null) throw new ArgumentNullException("replacement");
            long position = offset < 0 ? Length + offset : offset;
            if (position < 0) return new OffsetResult(this, "", 2, "Illegal string offset " + offset.ToString(CultureInfo.InvariantCulture));
            if (replacement.Length == 0) return new OffsetResult(this, "Error", 0, "Cannot assign an empty string to a string offset");
            long required = checked(position + 1); PhpBytes first = FromOwned(new byte[] { replacement.GetByte(0) });
            PhpBytes result = position < Length ? Slice(0, position).Concat(first).Concat(Slice(required, null)) : Concat(Fill(32, position - Length)).Concat(first);
            return new OffsetResult(result, "", replacement.Length > 1 ? 2 : 0, replacement.Length > 1 ? "Only the first byte will be assigned to the string offset" : "");
        }
        public int CompareBinary(PhpBytes right)
        {
            if ((object)right == null) throw new ArgumentNullException("right"); if (Object.ReferenceEquals(store, right.store)) return 0;
            long common = Math.Min(Length, right.Length), position = 0; byte[] a = new byte[ChunkSize], b = new byte[ChunkSize];
            while (position < common)
            {
                int count = (int)Math.Min(common - position, ChunkSize); CopyTo(position, a, 0, count); right.CopyTo(position, b, 0, count);
                for (int i = 0; i < count; ++i) if (a[i] != b[i]) return a[i] < b[i] ? -1 : 1;
                position += count;
            }
            return Length == right.Length ? 0 : Length < right.Length ? -1 : 1;
        }
        public bool Equals(PhpBytes right)
        { return Object.ReferenceEquals(this, right) || ((object)right != null && Length == right.Length && CompareBinary(right) == 0); }
        public override bool Equals(object other) { return Equals(other as PhpBytes); }
        public override int GetHashCode()
        {
            if (Thread.VolatileRead(ref hashReady) != 0) return cachedHash;
            uint hash = 2166136261; byte[] buffer = new byte[ChunkSize]; long position = 0;
            unchecked { while (position < Length) { int count = (int)Math.Min(Length - position, ChunkSize); CopyTo(position, buffer, 0, count); for (int i = 0; i < count; ++i) hash = (hash ^ buffer[i]) * 16777619; position += count; } }
            cachedHash = (int)hash; Thread.VolatileWrite(ref hashReady, 1); return cachedHash;
        }
        private PhpBytes Map(byte[] table)
        {
            if (Length == 0) return this;
            FillStore fill = store as FillStore; if (fill != null) return Fill(table[fill.Byte], Length);
            PatternStore pattern = store as PatternStore;
            if (pattern != null) { byte[] mapped = new byte[pattern.Pattern.Length]; for (int i = 0; i < mapped.Length; ++i) mapped[i] = table[pattern.Pattern[i]]; return new PhpBytes(new PatternStore(mapped, Length)); }
            MapStore old = store as MapStore;
            if (old != null) { byte[] combined = new byte[256]; bool identity = true; for (int i = 0; i < 256; ++i) { combined[i] = table[old.Map[i]]; identity &= combined[i] == i; } return identity ? new PhpBytes(old.Parent) : new PhpBytes(new MapStore(old.Parent, combined)); }
            return new PhpBytes(new MapStore(store, table));
        }
        public PhpBytes LowerAscii() { return Map(LowerMap); }
        public PhpBytes UpperAscii() { return Map(UpperMap); }
        public PhpBytes BitwiseNot() { return Map(NotMap); }
        public PhpBytes Bitwise(PhpBytes right, char operation)
        {
            if ((object)right == null) throw new ArgumentNullException("right"); if (operation != '&' && operation != '^' && operation != '|') throw new ArgumentOutOfRangeException("operation");
            if (Object.ReferenceEquals(store, right.store)) return operation == '^' ? Fill(0, Length) : this;
            long length = operation == '|' ? Math.Max(Length, right.Length) : Math.Min(Length, right.Length);
            if (length == 0) return Empty; if (operation == '|' && Length == 0) return right; if (operation == '|' && right.Length == 0) return this;
            return new PhpBytes(new BinaryStore(store, right.store, operation));
        }
        public bool TryArrayInteger(out long value)
        {
            value = 0; if (Length == 0 || Length > 20) return false; byte[] data = ToArray();
            bool negative = data[0] == 45; int start = negative ? 1 : 0;
            if (start == data.Length) return false; if (data[start] == 48) { if (negative || data.Length != 1) return false; return true; }
            if (data[start] < 49 || data[start] > 57) return false;
            ulong limit = negative ? 9223372036854775808UL : 9223372036854775807UL, magnitude = 0;
            for (int i = start; i < data.Length; ++i) { if (data[i] < 48 || data[i] > 57) return false; uint digit = (uint)(data[i] - 48); if (magnitude > (limit - digit) / 10) return false; magnitude = magnitude * 10 + digit; }
            value = negative ? magnitude == 9223372036854775808UL ? Int64.MinValue : -(long)magnitude : (long)magnitude; return true;
        }
    }
    public sealed class OffsetResult
    {
        public readonly PhpBytes Value; public readonly string ErrorClass, Message; public readonly int WarningLevel;
        internal OffsetResult(PhpBytes value, string errorClass, int warningLevel, string message) { Value = value; ErrorClass = errorClass; WarningLevel = warningLevel; Message = message; }
    }
    public sealed class PhpKey : IEquatable<PhpKey>
    {
        private readonly bool integer; private readonly long number; private readonly PhpBytes bytes;
        private PhpKey(long value) { integer = true; number = value; }
        private PhpKey(PhpBytes value) { if ((object)value == null) throw new ArgumentNullException("value"); integer = false; bytes = value; }
        public bool IsInteger { get { return integer; } }
        public long IntegerValue { get { if (!integer) throw new InvalidOperationException("Key is a PHP byte string"); return number; } }
        public PhpBytes BytesValue { get { if (integer) throw new InvalidOperationException("Key is a PHP integer"); return bytes; } }
        public static PhpKey FromInteger(long value) { return new PhpKey(value); }
        public static PhpKey FromString(PhpBytes value) { long number; return value.TryArrayInteger(out number) ? new PhpKey(number) : new PhpKey(value); }
        public string Protocol { get { return integer ? "i:" + number.ToString(CultureInfo.InvariantCulture) : "s:" + bytes.ToBase64(); } }
        public override string ToString() { throw new InvalidOperationException("Use typed PHP key properties or explicit diagnostic Protocol"); }
        public bool Equals(PhpKey other) { return (object)other != null && integer == other.integer && (integer ? number == other.number : bytes.Equals(other.bytes)); }
        public override bool Equals(object other) { return Equals(other as PhpKey); }
        public override int GetHashCode() { return integer ? number.GetHashCode() ^ 0x15a36 : bytes.GetHashCode() ^ 0x2c6d9; }
    }
    public sealed class ByteEntry
    {
        public readonly PhpKey Key; public readonly PhpBytes Value;
        internal ByteEntry(PhpKey key, PhpBytes value) { Key = key; Value = value; }
    }
    // Byte-valued specialization only. Generic PHP arrays may keep their
    // existing object/refcell values in OrderedDictionary using PhpKey keys.
    public sealed class OrderedByteMap
    {
        private readonly List<ByteEntry> entries = new List<ByteEntry>(); private readonly Dictionary<PhpKey, int> index = new Dictionary<PhpKey, int>();
        public void Set(PhpKey key, PhpBytes value) { int position; if (index.TryGetValue(key, out position)) entries[position] = new ByteEntry(entries[position].Key, value); else { index.Add(key, entries.Count); entries.Add(new ByteEntry(key, value)); } }
        public ByteEntry[] Snapshot() { return entries.ToArray(); }
    }
    public sealed class PhpByteBuilder
    {
        private PhpBytes value = PhpBytes.Empty;
        public long Length { get { return value.Length; } }
        public void Append(PhpBytes bytes) { if ((object)bytes == null) throw new ArgumentNullException("bytes"); value = value.Concat(bytes); }
        public void AppendBytes(byte[] bytes) { Append(PhpBytes.FromBytes(bytes)); }
        public void AppendUtf8(string text) { Append(PhpBytes.FromUtf8(text)); }
        public void AppendAscii(string text) { if (text == null) throw new ArgumentNullException("text"); foreach (char c in text) if (c > 127) throw new ArgumentException("Host text is not ASCII", "text"); Append(PhpBytes.FromUtf8(text)); }
        public PhpBytes ToPhpBytes() { return value; }
        public void Clear() { value = PhpBytes.Empty; }
    }
}
