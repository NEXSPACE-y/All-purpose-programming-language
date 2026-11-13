[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ByteRuntimePath,
    [Parameter(Mandatory=$true)][string]$ByteRuntimeSha256,
    [Parameter(Mandatory=$true)][string]$SymbolRuntimePath,
    [Parameter(Mandatory=$true)][string]$SymbolRuntimeSha256
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Utility\Microsoft.PowerShell.Utility.psd1') -ErrorAction Stop
foreach($pair in @(@($ByteRuntimePath,$ByteRuntimeSha256),@($SymbolRuntimePath,$SymbolRuntimeSha256))){if((Get-FileHash -LiteralPath $pair[0] -Algorithm SHA256).Hash.ToLowerInvariant()-cne$pair[1].ToLowerInvariant()){throw 'Invariant dependency hash mismatch'}}
[void][Reflection.Assembly]::LoadFrom([IO.Path]::GetFullPath($ByteRuntimePath))
[void][Reflection.Assembly]::LoadFrom([IO.Path]::GetFullPath($SymbolRuntimePath))
Add-Type -Path (Join-Path $PSScriptRoot 'SymbolTestHelpers.cs') -ReferencedAssemblies @([IO.Path]::GetFullPath($ByteRuntimePath),[IO.Path]::GetFullPath($SymbolRuntimePath))
$checks=New-Object 'Collections.Generic.List[object]'
function Check([string]$Name,[bool]$Pass,[object]$Observation){$checks.Add([ordered]@{id=$Name;pass=$Pass;observation=$Observation})}
function Bytes([string]$Text){[AllPhp.ByteValues.PhpBytes]::FromUtf8($Text)}
function Key([AllPhp.Symbols.PhpSymbolKind]$Kind,[string]$Text){[AllPhp.Symbols.PhpSymbolKey]::ForName($Kind,(Bytes $Text))}
function ExceptionName([scriptblock]$Action){try{&$Action;'NONE'}catch{$e=$_.Exception;while($e.InnerException){$e=$e.InnerException};$e.GetType().FullName}}

$names=[Enum]::GetValues([AllPhp.Symbols.PhpSymbolKind]);$domainPairs=0;$domainDistinct=$true
for($i=0;$i-lt$names.Length;$i++){for($j=$i+1;$j-lt$names.Length;$j++){$domainPairs++;if((Key $names[$i] 'Same').Equals((Key $names[$j] 'Same'))){$domainDistinct=$false}}}
Check 'all-domains-distinct' $domainDistinct $domainPairs
$leaf=Key Method 'Leaf'
$scoped=[AllPhp.Symbols.PhpSymbolKey]::ForMember([AllPhp.Symbols.PhpSymbolKind]::Method,(Bytes 'Container'),(Bytes 'Leaf'))
Check 'implicit-and-explicit-container-distinct' (-not$leaf.Equals($scoped)) @($leaf.HasContainer,$scoped.HasContainer)
$a=[AllPhp.Symbols.PhpSymbolKey]::ForMember([AllPhp.Symbols.PhpSymbolKind]::Method,(Bytes 'A::B'),(Bytes 'C'))
$b=[AllPhp.Symbols.PhpSymbolKey]::ForMember([AllPhp.Symbols.PhpSymbolKind]::Method,(Bytes 'A'),(Bytes 'B::C'))
Check 'structured-parts-do-not-join-colons' (-not$a.Equals($b)) 'No delimiter serialization in equality'
$a=[AllPhp.Symbols.PhpSymbolKey]::ForMember([AllPhp.Symbols.PhpSymbolKind]::Property,([AllPhp.ByteValues.PhpBytes]::FromBytes([byte[]]@(65,0,66))),(Bytes 'C'))
$b=[AllPhp.Symbols.PhpSymbolKey]::ForMember([AllPhp.Symbols.PhpSymbolKind]::Property,(Bytes 'A'),([AllPhp.ByteValues.PhpBytes]::FromBytes([byte[]]@(66,0,67))))
Check 'structured-parts-do-not-join-nul' (-not$a.Equals($b)) 'Opaque NUL-containing parts retained'
$a=Key Function 'MiXeD'
Check 'declaration-spelling-retained' ($a.OriginalParts[0].ToBase64()-ceq'TWlYZUQ=') $a.OriginalParts[0].ToBase64()
Check 'lookup-normalized-bytes' ($a.NormalizedParts[0].ToBase64()-ceq'bWl4ZWQ=') $a.NormalizedParts[0].ToBase64()
$readonly=[AllPhp.SymbolTests.Invariants]::MutateView($a,$false)
Check 'original-parts-readonly' ($readonly-ceq'System.NotSupportedException') $readonly
$readonly=[AllPhp.SymbolTests.Invariants]::MutateView($a,$true)
Check 'normalized-parts-readonly' ($readonly-ceq'System.NotSupportedException') $readonly
$source=[byte[]]@(65,255,0);$value=[AllPhp.ByteValues.PhpBytes]::FromBytes($source);$key=[AllPhp.Symbols.PhpSymbolKey]::ForName([AllPhp.Symbols.PhpSymbolKind]::Variable,$value);$source[0]=66
Check 'source-array-mutation-does-not-change-key' ($key.OriginalParts[0].ToBase64()-ceq'Qf8A') $key.OriginalParts[0].ToBase64()
$dict=New-Object 'Collections.Generic.Dictionary[AllPhp.Symbols.PhpSymbolKey,int]';$dict.Add($a,1);$dict[(Key Function 'mixed')]=2
Check 'equal-key-dictionary-replacement' ($dict.Count-eq1-and$dict[$a]-eq2) @($dict.Count,$dict[$a])
$retained=@($dict.Keys)[0].OriginalParts[0].ToBase64()
Check 'dictionary-keeps-initial-key-spelling' ($retained-ceq'TWlYZUQ=') $retained
Check 'forced-hash-collisions-resolved-by-equality' ([AllPhp.SymbolTests.Invariants]::ForcedCollisionLookup()) 'Three distinct keys and one equal replacement share hash zero'

$units=[AllPhp.ByteValues.PhpBytes]::Fill(65,1048576)
$shapes=@($units,(Bytes 'A').Repeat(1048576),([AllPhp.ByteValues.PhpBytes]::Fill(65,524288)).Concat([AllPhp.ByteValues.PhpBytes]::Fill(65,524288)),([AllPhp.ByteValues.PhpBytes]::Fill(65,1048578)).Slice(1,1048576))
$keys=@($shapes|ForEach-Object{[AllPhp.Symbols.PhpSymbolKey]::ForName([AllPhp.Symbols.PhpSymbolKind]::Function,$_ )})
$hashes=@($keys|ForEach-Object{$_.GetHashCode()});$same=$true
foreach($other in $keys){if(-not$keys[0].Equals($other)-or$other.GetHashCode()-ne$hashes[0]){$same=$false}}
Check 'content-hash-equal-across-real-storage-shapes' $same $hashes
$hugeLength=[long][int]::MaxValue+17
$huge=[AllPhp.ByteValues.PhpBytes]::Fill(65,$hugeLength)
$hugeKey=[AllPhp.Symbols.PhpSymbolKey]::ForName([AllPhp.Symbols.PhpSymbolKind]::Function,$huge)
Check 'function-name-length-beyond-int32' ($hugeKey.NormalizedParts[0].LongLength-eq$hugeLength-and$hugeKey.NormalizedParts[0].GetByte($hugeLength-1)-eq97) ([ordered]@{length=$hugeKey.NormalizedParts[0].LongLength;last=$hugeKey.NormalizedParts[0].GetByte($hugeLength-1)})
$slash=[string][char]92
$hugeConst=[AllPhp.Symbols.PhpSymbolKey]::ForName([AllPhp.Symbols.PhpSymbolKind]::Constant,$huge.Concat((Bytes ($slash+'Leaf'))))
Check 'constant-prefix-boundary-beyond-int32' ($hugeConst.NormalizedParts.Count-eq2-and$hugeConst.NormalizedParts[0].LongLength-eq$hugeLength-and$hugeConst.NormalizedParts[0].GetByte($hugeLength-1)-eq97-and$hugeConst.NormalizedParts[1].ToBase64()-ceq'TGVhZg==') ([ordered]@{prefix_length=$hugeConst.NormalizedParts[0].LongLength;leaf_base64=$hugeConst.NormalizedParts[1].ToBase64();hash_computed=$false})

$failures=@(
    @('null-name','System.ArgumentNullException',{[AllPhp.Symbols.PhpSymbolKey]::ForName([AllPhp.Symbols.PhpSymbolKind]::Function,$null)}),
    @('invalid-member-domain','System.ArgumentException',{[AllPhp.Symbols.PhpSymbolKey]::ForMember([AllPhp.Symbols.PhpSymbolKind]::Function,(Bytes 'C'),(Bytes 'M'))}),
    @('null-container','System.ArgumentNullException',{[AllPhp.Symbols.PhpSymbolKey]::ForMember([AllPhp.Symbols.PhpSymbolKind]::Method,$null,(Bytes 'M'))}),
    @('null-member','System.ArgumentNullException',{[AllPhp.Symbols.PhpSymbolKey]::ForMember([AllPhp.Symbols.PhpSymbolKind]::Method,(Bytes 'C'),$null)})
)
foreach($item in $failures){$found=ExceptionName $item[2];Check $item[0] ($found-ceq$item[1]) $found}
$found=[AllPhp.SymbolTests.Invariants]::InvalidKind();Check 'invalid-domain' ($found-ceq'System.ArgumentOutOfRangeException') $found
$none=Key Function 'none'
Check 'null-equality' (-not$none.Equals($null)) $false
Check 'foreign-type-equality' (-not$none.Equals('none')) $false
$report=[ordered]@{status='ISOLATED_COMPONENT_INVARIANTS_NOT_PHP_CONFORMANCE';scope='Real component storage/identity tests; >Int32 checks read real boundary bytes but do not hash or serialize the entire huge value';total=$checks.Count;passed=@($checks|Where-Object{$_.pass}).Count;checks=$checks.ToArray()}
[Console]::Out.Write(($report|ConvertTo-Json -Depth 8 -Compress))
if($report.passed-ne$report.total){exit 1}
