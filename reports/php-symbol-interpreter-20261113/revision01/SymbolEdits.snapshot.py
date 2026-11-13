"""Valid-UTF8 symbol migration over 5856687f + RootCore; isolated only.

Stage boundary: source and metadata remain strict .NET text. This module adds
ASCII-only symbol comparers, valid-UTF8 label recognition, exact raw-sensitive
metadata comparisons, and descriptor spelling for newly constructed objects.
The AllPhp.Symbols PhpSymbolKey component remains the all-raw-byte design;
this valid-text bridge does not claim invalid-UTF8 source/name compatibility.

Apply after CoreByteEdits and TypedKeyEdits. No package, runtime, source decoder
or installed adapter is edited. Every exact anchor/count is guarded; original
CRLF/LF style is restored. No native execution architecture is introduced.
Further adoption must replace text metadata registries with PhpSymbolKey,
preserve byte token spans/declaration bytes, and migrate all dynamic name APIs.
"""
BASE_SHA256 = '5856687f7abd1471b4af7af9827ca2d17a011e836ad2852bf1d7993298fddc9f'

COMPARER_SOURCE = r'''using System;
namespace AllPhp.ValidTextSymbols
{
    // Equality bridge for already validated UTF-8 text metadata. No Unicode
    // normalization or invariant/current-culture comparisons are permitted.
    // Hashes are internal and are not byte-symbol hashes or Zend ABI hashes.
    public static class Comparers
    {
        public const string Contract = "allphp-valid-utf8-symbols-01";
        public static readonly StringComparer Ascii = new SymbolComparer(false);
        public static readonly StringComparer Constant = new SymbolComparer(true);
        public static string LowerAscii(string value)
        {
            if (value == null) throw new ArgumentNullException("value");
            char[] result = null;
            for (int i = 0; i < value.Length; i++)
                if (value[i] >= 'A' && value[i] <= 'Z')
                {
                    if (result == null) result = value.ToCharArray();
                    result[i] = (char)(value[i] + 32);
                }
            return result == null ? value : new String(result);
        }
        private sealed class SymbolComparer : StringComparer
        {
            private readonly bool constant;
            public SymbolComparer(bool constant) { this.constant = constant; }
            private char At(string value, int offset, int boundary)
            {
                char c = value[offset];
                return offset < boundary && c >= 'A' && c <= 'Z' ? (char)(c + 32) : c;
            }
            public override int Compare(string left, string right)
            {
                if (Object.ReferenceEquals(left, right)) return 0;
                if (left == null) return -1;
                if (right == null) return 1;
                int lb = constant ? left.LastIndexOf((char)92) : left.Length;
                int rb = constant ? right.LastIndexOf((char)92) : right.Length;
                int length = Math.Min(left.Length, right.Length);
                for (int i = 0; i < length; i++)
                {
                    char a = At(left, i, lb), b = At(right, i, rb);
                    if (a != b) return a < b ? -1 : 1;
                }
                return left.Length == right.Length ? 0 : left.Length < right.Length ? -1 : 1;
            }
            public override bool Equals(string left, string right) { return Compare(left, right) == 0; }
            public override int GetHashCode(string value)
            {
                if (value == null) throw new ArgumentNullException("value");
                int boundary = constant ? value.LastIndexOf((char)92) : value.Length;
                unchecked
                {
                    uint hash = 2166136261;
                    for (int i = 0; i < value.Length; i++) hash = (hash ^ At(value, i, boundary)) * 16777619;
                    return (int)hash;
                }
            }
        }
    }
}'''


def apply(value: str) -> str:
    if not isinstance(value, str):
        raise TypeError('SymbolEdits.apply requires source text')
    newline = '\r\n' if '\r\n' in value else '\n'
    value = value.replace('\r\n', '\n')

    def replace(audit_id, old, new, count=1):
        nonlocal value
        actual = value.count(old)
        if actual != count:
            raise ValueError(f'SymbolEdits {audit_id}: expected {count} exact anchors, found {actual}')
        value = value.replace(old, new)

    bootstrap = """        if (-not ('AllPhp.ValidTextSymbols.Comparers' -as [type])) {
            Add-Type -TypeDefinition @'
""" + COMPARER_SOURCE + """
'@
        }
        if ([AllPhp.ValidTextSymbols.Comparers]::Contract -cne 'allphp-valid-utf8-symbols-01') {
            throw 'ALL PHP valid-text symbol comparer contract mismatch'
        }
        function ConvertTo-PhpAsciiLower([string]$name) { return [AllPhp.ValidTextSymbols.Comparers]::LowerAscii($name) }
        function Test-PhpNameEqual([string]$left,[string]$right) { return [AllPhp.ValidTextSymbols.Comparers]::Ascii.Equals($left,$right) }
        function Test-PhpRawNameEqual([string]$left,[string]$right) { return [StringComparer]::Ordinal.Equals($left,$right) }
        function Test-PhpNameIn([string]$name,$names) {
            foreach($other in $names) { if (Test-PhpNameEqual $name $other) { return $true } }
            return $false
        }
"""
    replace('bootstrap', "        $ErrorActionPreference = 'Stop'\n", "        $ErrorActionPreference = 'Stop'\n" + bootstrap)
    replace('case-fold-registries', '[System.StringComparer]::OrdinalIgnoreCase', '[AllPhp.ValidTextSymbols.Comparers]::Ascii', 19)
    for label, old in [('state-constants', "Constants = [System.Collections.Generic.Dictionary[string,object]]::new(\n                    [System.StringComparer]::Ordinal)"), ('builtin-constants', "$phpConstants = [System.Collections.Generic.Dictionary[string,object]]::new(\n            [System.StringComparer]::Ordinal)"), ('declaration-constants', "$declConsts = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)")]:
        replace(label, old, old.replace('[System.StringComparer]::Ordinal', '[AllPhp.ValidTextSymbols.Comparers]::Constant'))

    # A decoded supplementary scalar occupies two UTF-16 units, both in the
    # extended range. No invalid surrogate text is introduced by this bridge.
    replace('label-start', '[A-Za-z_]', r'[A-Za-z_\x80-\uffff]', 48)
    replace('label-continuation', '[A-Za-z_0-9]', r'[A-Za-z_0-9\x80-\uffff]', 18)
    replace('qualified-label-continuation', r'[A-Za-z_0-9\\]', r'[A-Za-z_0-9\x80-\uffff\\]', 30)
    replace('lexer-whitespace', r"$pattern = '(?:\s+|", r"$pattern = '(?:[ \t\r\n]+|")
    replace('token-whitespace-skip', '-not [string]::IsNullOrWhiteSpace($token)', r"$token -cnotmatch '^[ \t\r\n]+$'")
    replace('open-tag-whitespace', r'php(?=\s|$)', r'php(?=[ \t\r\n]|$)', 2)
    replace('number-token-decimal-start', r"$token -cmatch '^(?:\d|\.\d)'", r"$token -cmatch '^(?:[0-9]|\.[0-9])'")
    replace('number-integer-decimal', r"$text -match '^\d+$'", r"$text -match '^[0-9]+$'")
    replace('number-token-pattern', r'(?:\d[\d_]*(?:\.[\d_]*)?|\.\d[\d_]*)(?:[eE][+-]?\d[\d_]*)?', r'(?:[0-9][0-9_]*(?:\.[0-9_]*)?|\.[0-9][0-9_]*)(?:[eE][+-]?[0-9][0-9_]*)?')

    for expression, count in [('$t',1),('(Next-Token)',1),('$type',1),('$variant',1),('$typeName',1),('$name',1),('$callName',1)]:
        replace('ascii-lower-'+expression, expression+'.ToLowerInvariant()', '(ConvertTo-PhpAsciiLower '+expression+')', count)

    # Metadata-only comparisons. Raw-sensitive names are ordinal, avoiding
    # PowerShell -ceq's canonical-equivalence behavior for NFC/NFD and Kelvin.
    for left, right, count in [('$previous.Name','$param.Substring(1)',1),('$p.Name','$name',1),('$candidate.Name','$name',1),('$param.Name','$arg.Name',1),('$prior.Name','$prop.Name',1),('$prop.Name','$propertyName',1),('$existing.Name','$prop.Name',1),('$state.Tokens[$hi + 2]','$propName',1)]:
        replace('raw-name-'+left+'-'+right, left+' -ceq '+right, '(Test-PhpRawNameEqual '+left+' '+right+')', count)
    for left, op, right in [('$prior.Name','ieq','$item.Name'),('$iface.Name','ieq','$interfaceName'),('$actual','ieq','$target'),('$cls.Name','ieq','$target'),('$state.ClassContext','ine','$owner'),('$state.ClassContext','ine','$declared.Owner'),('$node.Name','ieq','$callName'),('$_ .Name','ieq','$rule.Method')]:
        if left == '$_ .Name':
            continue
        condition='(Test-PhpNameEqual '+left+' '+right+')'
        if op == 'ine': condition='(-not '+condition+')'
        replace('fold-name-'+left+'-'+right, left+' -'+op+' '+right, condition)
    replace('trait-winner-method', '$_.Name -ieq $rule.Method', '(Test-PhpNameEqual $_.Name $rule.Method)')
    for left,right,count in [('$rule.Method','$method.Name',1),('$rule.Trait','$traitName',2),('$method.Name','$rule.Method',1)]:
        replace('trait-exact-fold-'+left+'-'+right, left+' -ine '+right, '(-not (Test-PhpNameEqual '+left+' '+right+'))', count)
    replace('trait-selection-membership', '$rule.Trait -notin $use.Names', '(-not (Test-PhpNameIn $rule.Trait $use.Names))')
    replace('trait-exclusion-membership', '$loserName -notin $use.Names -or $loserName -ieq $rule.Trait', '(-not (Test-PhpNameIn $loserName $use.Names)) -or (Test-PhpNameEqual $loserName $rule.Trait)')
    replace('object-class-exact-metadata', '$a.Class -cne $b.Class', '(-not (Test-PhpNameEqual $a.Class $b.Class))')
    replace('object-declaration-spelling', """                    $className=Resolve-PhpClass $node.Name
                    if ($state.Classes.ContainsKey($className) -and""", """                    $className=Resolve-PhpClass $node.Name
                    if ($state.Classes.ContainsKey($className)) { $className=[string]$state.Classes[$className].Name }
                    if ($state.Classes.ContainsKey($className) -and""")

    # Core normalizes scalar callables once. Array member values are PHP-owned
    # PhpBytes, so each selected class/method crosses the strict metadata boundary.
    replace('array-callable-selected-values', """                $target=Get-PhpArrayItem $callee ([long]0)
                $member=Get-PhpArrayItem $callee ([long]1)""", """                $target=Get-PhpArrayItem $callee ([long]0)
                $member=Get-PhpArrayItem $callee ([long]1)
                if (Is-PhpStringValue $target) { $target=Get-PhpHostText $target }
                if (Is-PhpStringValue $member) { $member=Get-PhpHostText $member }""")
    replace('array-callable-definition-values', '$target=Get-PhpArrayItem $callee ([long]0);$member=Get-PhpArrayItem $callee ([long]1)', '$target=Get-PhpArrayItem $callee ([long]0);$member=Get-PhpArrayItem $callee ([long]1)\n                if (Is-PhpStringValue $target) { $target=Get-PhpHostText $target }\n                if (Is-PhpStringValue $member) { $member=Get-PhpHostText $member }')
    replace('array-callable-invocation-values', '$pair = @($callee.Items.Values)', '$pair = @($callee.Items.Values)\n                for($i=0;$i-lt$pair.Count;$i++) { if (Is-PhpStringValue $pair[$i]) { $pair[$i]=Get-PhpHostText $pair[$i] } }')
    return value.replace('\n', newline)
