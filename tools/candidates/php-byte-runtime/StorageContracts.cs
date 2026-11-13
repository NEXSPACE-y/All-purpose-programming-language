using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using AllPhp.ByteValues;

namespace AllPhp.ByteValues.Proof
{
    public sealed class Check
    {
        public string Id, Error; public bool Passed;
    }
    public sealed class StorageReport
    {
        public List<Check> Checks = new List<Check>();
        public long LongLength, FullStreamBytes, FullStreamWrites, MutationOffset;
        public string FullStreamSha256, MutationWindowBase64, AppendedWindowBase64;
        public Dictionary<string, int> Samples = new Dictionary<string, int>();
        public int BuilderSpineHeight;
        public double ElapsedSeconds;
        public long PeakWorkingSetBytes;
    }
    internal sealed class HashStream : Stream
    {
        private readonly HashAlgorithm hash = new SHA256CryptoServiceProvider();
        private bool finished; internal long Written, Writes;
        internal string Finish()
        {
            if (!finished) { hash.TransformFinalBlock(new byte[0], 0, 0); finished = true; }
            return BitConverter.ToString(hash.Hash).Replace("-", "").ToLowerInvariant();
        }
        public override void Write(byte[] buffer, int offset, int count)
        { if (finished) throw new InvalidOperationException("Hash stream finalized"); hash.TransformBlock(buffer, offset, count, buffer, offset); Written = checked(Written + count); Writes++; }
        public override bool CanRead { get { return false; } }
        public override bool CanSeek { get { return false; } }
        public override bool CanWrite { get { return !finished; } }
        public override long Length { get { throw new NotSupportedException(); } }
        public override long Position { get { return Written; } set { throw new NotSupportedException(); } }
        public override int Read(byte[] buffer, int offset, int count) { throw new NotSupportedException(); }
        public override long Seek(long offset, SeekOrigin origin) { throw new NotSupportedException(); }
        public override void SetLength(long value) { throw new NotSupportedException(); }
        public override void Flush() { }
        protected override void Dispose(bool disposing) { if (disposing) hash.Dispose(); base.Dispose(disposing); }
    }
    internal sealed class ShortReadStream : MemoryStream
    {
        internal ShortReadStream(byte[] data) : base(data, false) { }
        public override int Read(byte[] buffer, int offset, int count) { return base.Read(buffer, offset, Math.Min(count, 7)); }
    }
    internal sealed class ThrowReadStream : Stream
    {
        private int calls;
        public override int Read(byte[] buffer, int offset, int count)
        { if (calls++ != 0) throw new IOException("injected read failure"); buffer[offset] = 255; return 1; }
        public override bool CanRead { get { return true; } }
        public override bool CanWrite { get { return false; } }
        public override bool CanSeek { get { return false; } }
        public override long Length { get { throw new NotSupportedException(); } }
        public override long Position { get { throw new NotSupportedException(); } set { throw new NotSupportedException(); } }
        public override void Write(byte[] buffer, int offset, int count) { throw new NotSupportedException(); }
        public override long Seek(long offset, SeekOrigin origin) { throw new NotSupportedException(); }
        public override void SetLength(long value) { throw new NotSupportedException(); }
        public override void Flush() { }
    }
    public static class StorageProbe
    {
        private static void Test(StorageReport report, string id, Func<bool> action)
        {
            var check = new Check { Id = id };
            try { check.Passed = action(); } catch (Exception e) { check.Error = e.ToString(); check.Passed = false; }
            report.Checks.Add(check);
        }
        private static byte[] Data(int length)
        { byte[] data = new byte[length]; for (int i = 0; i < length; ++i) data[i] = (byte)((i * 31 + 17) & 255); return data; }
        private static bool BytesEqual(byte[] a, byte[] b)
        { if (a.Length != b.Length) return false; for (int i = 0; i < a.Length; ++i) if (a[i] != b[i]) return false; return true; }
        public static StorageReport Run(string patternBase64, long repetitions, long mutationOffset, long[] samplePositions)
        {
            Stopwatch timer = Stopwatch.StartNew(); var report = new StorageReport(); byte[] pattern = Convert.FromBase64String(patternBase64);
            PhpBytes unit = PhpBytes.FromBytes(pattern), large = unit.Repeat(repetitions); report.LongLength = large.Length; report.MutationOffset = mutationOffset;
            Test(report, "long_length_exceeds_int32", delegate { return large.Length > Int32.MaxValue && large.Length == checked((long)pattern.Length * repetitions) && large.LongLength == large.Length; });
            Test(report, "long_random_access_real_pattern", delegate {
                foreach (long position in samplePositions) { byte value = large.GetByte(position); report.Samples[position.ToString(System.Globalization.CultureInfo.InvariantCulture)] = value; if (value != pattern[(int)(position % pattern.Length)]) return false; }
                return true;
            });
            Test(report, "copy_crosses_int32_and_chunk_boundary", delegate {
                long start = (long)Int32.MaxValue - 100; byte[] actual = new byte[300]; large.CopyTo(start, actual, 0, actual.Length);
                for (int i = 0; i < actual.Length; ++i) if (actual[i] != pattern[(int)((start + i) % pattern.Length)]) return false; return true;
            });
            Test(report, "long_slice_view_readback", delegate {
                PhpBytes view = large.Slice((long)Int32.MaxValue + 10, 1000); byte[] actual = view.ToArray();
                for (int i = 0; i < actual.Length; ++i) if (actual[i] != pattern[(int)(((long)Int32.MaxValue + 10 + i) % pattern.Length)]) return false;
                return view.Length == 1000 && large.Slice(-257, null).Equals(unit);
            });
            Test(report, "long_copy_on_write_preserves_original", delegate {
                PhpBytes changed = large.WithOffset(mutationOffset, PhpBytes.FromBytes(new byte[] { 165 })).Value;
                byte[] actual = changed.Slice(mutationOffset - 64, 129).ToArray(); report.MutationWindowBase64 = Convert.ToBase64String(actual);
                for (int i = 0; i < actual.Length; ++i) if (actual[i] != (i == 64 ? 165 : pattern[(int)((mutationOffset - 64 + i) % pattern.Length)])) return false;
                return changed.Length == large.Length && large.GetByte(mutationOffset) == pattern[(int)(mutationOffset % pattern.Length)];
            });
            Test(report, "long_offset_extension_spaces_are_readable", delegate {
                long offset = (long)Int32.MaxValue + 7; PhpBytes changed = PhpBytes.Empty.WithOffset(offset, PhpBytes.FromBytes(new byte[] { 255 })).Value;
                byte[] actual = changed.Slice(offset - 100, null).ToArray(); report.AppendedWindowBase64 = Convert.ToBase64String(actual);
                for (int i = 0; i < actual.Length - 1; ++i) if (actual[i] != 32) return false;
                return actual.Length == 101 && actual[100] == 255 && changed.Length == offset + 1 && changed.GetByte(0) == 32 && PhpBytes.Empty.Length == 0;
            });
            Test(report, "long_bitwise_and_ascii_maps", delegate {
                byte[] actual = large.Bitwise(PhpBytes.Fill(15, large.Length), '|').Slice((long)Int32.MaxValue, 300).ToArray();
                for (int i = 0; i < actual.Length; ++i) if (actual[i] != (byte)(pattern[(int)(((long)Int32.MaxValue + i) % pattern.Length)] | 15)) return false;
                return large.BitwiseNot().BitwiseNot().GetByte(mutationOffset) == large.GetByte(mutationOffset) && large.Bitwise(large, '^').GetByte(large.Length - 1) == 0;
            });
            Test(report, "bounded_exports_do_not_limit_storage", delegate {
                bool refused = false; try { large.ToArray(); } catch (NotSupportedException) { refused = true; }
                return refused && large.GetByte(large.Length - 1) == pattern[pattern.Length - 1];
            });
            Test(report, "full_long_stream_readback", delegate {
                using (var stream = new HashStream()) { large.WriteTo(stream); report.FullStreamSha256 = stream.Finish(); report.FullStreamBytes = stream.Written; report.FullStreamWrites = stream.Writes; }
                return report.FullStreamBytes == large.Length && report.FullStreamWrites > 32768;
            });
            Test(report, "segmented_builder_avl_readback", delegate {
                var builder = new PhpByteBuilder(); const int count = 10000;
                for (int i = 0; i < count; ++i) builder.AppendBytes(new byte[] { (byte)((i * 17) & 255) });
                PhpBytes value = builder.ToPhpBytes(); report.BuilderSpineHeight = value.StorageHeight; byte[] actual = value.ToArray();
                for (int i = 0; i < count; ++i) if (actual[i] != (byte)((i * 17) & 255)) return false;
                return value.Length == count && value.StorageHeight <= 32;
            });
            Test(report, "builder_snapshots_and_input_copy", delegate {
                var builder = new PhpByteBuilder(); byte[] input = new byte[] { 255, 0 }; builder.AppendBytes(input); PhpBytes before = builder.ToPhpBytes(); input[0] = 0;
                builder.AppendAscii("A"); PhpBytes after = builder.ToPhpBytes(); builder.Clear();
                return before.ToBase64() == "/wA=" && after.ToBase64() == "/wBB" && builder.Length == 0;
            });
            Test(report, "builder_text_failures_are_explicit_and_atomic", delegate {
                var builder = new PhpByteBuilder(); builder.AppendAscii("x"); bool ascii = false, utf8 = false;
                try { builder.AppendAscii("é"); } catch (ArgumentException) { ascii = true; }
                try { builder.AppendUtf8("\ud800"); } catch (EncoderFallbackException) { utf8 = true; }
                return ascii && utf8 && builder.ToPhpBytes().ToBase64() == "eA==";
            });
            Test(report, "from_stream_copies_and_releases_source", delegate {
                byte[] input = Data(150007), original = (byte[])input.Clone(); PhpBytes value;
                using (var stream = new ShortReadStream(input)) { value = PhpBytes.FromStream(stream); if (!stream.CanRead) return false; }
                input[0] ^= 255; return value.Length == original.Length && value.Equals(PhpBytes.FromBytes(original));
            });
            Test(report, "from_stream_failure_is_not_partial_success", delegate {
                try { using (var stream = new ThrowReadStream()) { PhpBytes.FromStream(stream); } } catch (IOException e) { return e.Message == "injected read failure"; } return false;
            });
            Test(report, "defensive_export_and_implicit_text_guard", delegate {
                byte[] input = new byte[] { 255, 0, 65 }; PhpBytes value = PhpBytes.FromBytes(input); input[0] = 0; byte[] exported = value.ToArray(); exported[0] = 0;
                bool rejected = false; try { value.ToString(); } catch (InvalidOperationException) { rejected = true; }
                string text; return value.ToBase64() == "/wBB" && rejected && !value.TryDecodeUtf8(out text) && text == null;
            });
            Test(report, "typed_keys_reject_wrong_access", delegate {
                PhpKey number = PhpKey.FromString(PhpBytes.FromUtf8("1")), bytes = PhpKey.FromString(PhpBytes.FromBytes(new byte[] { 255 })); bool a = false, b = false;
                try { PhpBytes ignored = number.BytesValue; } catch (InvalidOperationException) { a = true; }
                try { long ignored = bytes.IntegerValue; } catch (InvalidOperationException) { b = true; }
                return number.IsInteger && number.IntegerValue == 1 && !bytes.IsInteger && bytes.BytesValue.ToBase64() == "/w==" && a && b;
            });
            Test(report, "generic_ordered_dictionary_keeps_object_values", delegate {
                var map = new System.Collections.Specialized.OrderedDictionary(); object original = new object(), replacement = new object();
                map[PhpKey.FromString(PhpBytes.FromUtf8("1"))] = original; map[PhpKey.FromString(PhpBytes.FromBytes(new byte[] { 255 }))] = "other"; map[PhpKey.FromInteger(1)] = replacement;
                return map.Count == 2 && Object.ReferenceEquals(map[PhpKey.FromInteger(1)], replacement) && ((PhpKey)new List<object>(GetKeys(map))[0]).IntegerValue == 1;
            });
            Test(report, "equal_content_hash_independent_of_shape", delegate {
                PhpBytes repeat = unit.Repeat(600), flat = PhpBytes.FromBytes(repeat.ToArray());
                var builder = new PhpByteBuilder(); builder.AppendAscii("prefix"); builder.Append(flat.Slice(0, 100)); builder.Append(flat.Slice(100, null)); builder.AppendAscii("suffix"); PhpBytes view = builder.ToPhpBytes().Slice(6, flat.Length);
                return repeat.Equals(flat) && flat.Equals(view) && repeat.GetHashCode() == flat.GetHashCode() && view.GetHashCode() == flat.GetHashCode();
            });
            Test(report, "deep_composed_views_use_iterative_read", delegate {
                byte[] original = Data(65537); PhpBytes value = PhpBytes.FromBytes(original); const int depth = 2500;
                for (int i = 0; i < depth; ++i) value = value.Repeat(2).Slice(1, original.Length);
                foreach (long position in new long[] { 0, 1, 255, 65530, 65536 }) if (value.GetByte(position) != original[(int)((position + depth) % original.Length)]) return false;
                return value.Length == original.Length;
            });
            Test(report, "range_and_overflow_guards_do_not_wrap", delegate {
                bool copy = false, concat = false, repeat = false, offset = false;
                try { unit.CopyTo(unit.Length - 1, new byte[2], 0, 2); } catch (ArgumentOutOfRangeException) { copy = true; }
                try { PhpBytes.Fill(0, Int64.MaxValue).Concat(unit); } catch (OverflowException) { concat = true; }
                try { unit.Repeat(Int64.MaxValue); } catch (OverflowException) { repeat = true; }
                try { unit.WithOffset(Int64.MaxValue, unit); } catch (OverflowException) { offset = true; }
                return copy && concat && repeat && offset;
            });
            timer.Stop(); report.ElapsedSeconds = timer.Elapsed.TotalSeconds; report.PeakWorkingSetBytes = Process.GetCurrentProcess().PeakWorkingSet64; return report;
        }
        private static IEnumerable<object> GetKeys(System.Collections.Specialized.OrderedDictionary map)
        { foreach (object key in map.Keys) yield return key; }
    }
}
