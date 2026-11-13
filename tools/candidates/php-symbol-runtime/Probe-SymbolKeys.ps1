[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ByteRuntimePath,
    [Parameter(Mandatory=$true)][string]$ByteRuntimeSha256,
    [Parameter(Mandatory=$true)][string]$SymbolRuntimePath,
    [Parameter(Mandatory=$true)][string]$SymbolRuntimeSha256,
    [Parameter(Mandatory=$true)][string]$CasesPath
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Utility\Microsoft.PowerShell.Utility.psd1') -ErrorAction Stop
foreach($pair in @(@($ByteRuntimePath,$ByteRuntimeSha256),@($SymbolRuntimePath,$SymbolRuntimeSha256))){if((Get-FileHash -LiteralPath $pair[0] -Algorithm SHA256).Hash.ToLowerInvariant()-cne$pair[1].ToLowerInvariant()){throw 'Probe dependency hash mismatch'}}
[void][Reflection.Assembly]::LoadFrom([IO.Path]::GetFullPath($ByteRuntimePath))
[void][Reflection.Assembly]::LoadFrom([IO.Path]::GetFullPath($SymbolRuntimePath))
$cases=Get-Content -LiteralPath $CasesPath -Raw -Encoding UTF8|ConvertFrom-Json
$rows=New-Object 'Collections.Generic.List[object]'
foreach($case in $cases){
    $kind=[AllPhp.Symbols.PhpSymbolKind][Enum]::Parse([AllPhp.Symbols.PhpSymbolKind],$case.kind,$false)
    $left=[AllPhp.ByteValues.PhpBytes]::FromBase64($case.left_base64)
    $right=[AllPhp.ByteValues.PhpBytes]::FromBase64($case.right_base64)
    if($case.member){
        $a=[AllPhp.Symbols.PhpSymbolKey]::ForMember($kind,[AllPhp.ByteValues.PhpBytes]::FromBase64($case.left_container_base64),$left)
        $b=[AllPhp.Symbols.PhpSymbolKey]::ForMember($kind,[AllPhp.ByteValues.PhpBytes]::FromBase64($case.right_container_base64),$right)
    }else{
        $a=[AllPhp.Symbols.PhpSymbolKey]::ForName($kind,$left)
        $b=[AllPhp.Symbols.PhpSymbolKey]::ForName($kind,$right)
    }
    $map=New-Object 'Collections.Generic.Dictionary[AllPhp.Symbols.PhpSymbolKey,int]'
    $map.Add($a,37)
    $rows.Add([ordered]@{id=$case.id;equal=$a.Equals($b);hash_equal=($a.GetHashCode()-eq$b.GetHashCode());dictionary_found=$map.ContainsKey($b);left_original_base64=@($a.OriginalParts|ForEach-Object{$_.ToBase64()});left_normalized_base64=@($a.NormalizedParts|ForEach-Object{$_.ToBase64()});right_original_base64=@($b.OriginalParts|ForEach-Object{$_.ToBase64()});right_normalized_base64=@($b.NormalizedParts|ForEach-Object{$_.ToBase64()})})
}
[Console]::Out.Write(($rows.ToArray()|ConvertTo-Json -Depth 7 -Compress))
