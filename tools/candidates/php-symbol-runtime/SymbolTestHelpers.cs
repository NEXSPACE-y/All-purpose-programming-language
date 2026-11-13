using System;
using System.Collections.Generic;
using AllPhp.ByteValues;
using AllPhp.Symbols;

namespace AllPhp.SymbolTests
{
    // The CLR calls avoid PowerShell's collection-index and enum-conversion
    // validation, so these observations reach the component's public boundary.
    public static class Invariants
    {
        public static string MutateView(PhpSymbolKey key, bool normalized)
        {
            try
            {
                IList<PhpBytes> list = normalized ? key.NormalizedParts : key.OriginalParts;
                list[0] = PhpBytes.FromUtf8("replacement");
                return "NONE";
            }
            catch (Exception error) { return error.GetType().FullName; }
        }

        public static string InvalidKind()
        {
            try
            {
                PhpSymbolKey.ForName((PhpSymbolKind)999, PhpBytes.FromUtf8("x"));
                return "NONE";
            }
            catch (Exception error) { return error.GetType().FullName; }
        }

        private sealed class ConstantHashComparer : IEqualityComparer<PhpSymbolKey>
        {
            public bool Equals(PhpSymbolKey left, PhpSymbolKey right)
            { return Object.ReferenceEquals(left, right) || ((object)left != null && left.Equals(right)); }
            public int GetHashCode(PhpSymbolKey value) { return 0; }
        }

        public static bool ForcedCollisionLookup()
        {
            var map = new Dictionary<PhpSymbolKey, int>(new ConstantHashComparer());
            var functionA = PhpSymbolKey.ForName(PhpSymbolKind.Function, PhpBytes.FromUtf8("Same"));
            var functionB = PhpSymbolKey.ForName(PhpSymbolKind.Function, PhpBytes.FromUtf8("same"));
            var variableA = PhpSymbolKey.ForName(PhpSymbolKind.Variable, PhpBytes.FromUtf8("Same"));
            var variableB = PhpSymbolKey.ForName(PhpSymbolKind.Variable, PhpBytes.FromUtf8("same"));
            map.Add(functionA, 1);
            map[functionB] = 2;
            map.Add(variableA, 3);
            map.Add(variableB, 4);
            return map.Count == 3 && map[functionA] == 2 && map[functionB] == 2 &&
                map[variableA] == 3 && map[variableB] == 4;
        }
    }
}
