[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$AssemblyPath,[Parameter(Mandatory=$true)][string]$ReportPath)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Utility\Microsoft.PowerShell.Utility.psd1') -ErrorAction Stop
if(Test-Path -LiteralPath $ReportPath){throw 'Preserve previous boundary report'}
Add-Type -Path $AssemblyPath
$checks=[Collections.Generic.List[object]]::new()
$bytes=[byte[]]@(255,0,65);$value=[AllPhp.ByteValues.PhpBytes]::FromBytes($bytes);$bytes[0]=0;$copy=$value.ToArray();$copy[0]=0
$checks.Add([ordered]@{id='input_and_export_defensive_copy';passed=$value.ToBase64()-ceq'/wBB'})
$text=$null;$valid=$value.TryDecodeUtf8([ref]$text)
$checks.Add([ordered]@{id='strict_utf8_boundary_no_replacement';passed=(-not$valid-and$null-eq$text)})
$rejected=$false
try{[void]$value.ToString()}catch{$rejected=$_.Exception.ToString().Contains('explicit raw-byte')}
$checks.Add([ordered]@{id='implicit_text_conversion_refused';passed=$rejected})
$rejected=$false
try{[void]$value.WithOffset([long][int]::MaxValue,[AllPhp.ByteValues.PhpBytes]::FromBase64('QQ=='))}catch{$rejected=$_.Exception.ToString().Contains('segmented backend')}
$checks.Add([ordered]@{id='prototype_capacity_is_explicit_not_wrapped';passed=$rejected})
$latin1=[Text.Encoding]::GetEncoding(28591);$utf8=[Text.UTF8Encoding]::new($false,$true)
$ff=[byte[]]@(255);$carrier=$latin1.GetString($ff);$reencoded=$utf8.GetBytes($carrier)
$accent=[byte[]]@(195,128);$carrierLower=$latin1.GetBytes($latin1.GetString($accent).ToLowerInvariant())
$textLower=$utf8.GetBytes($utf8.GetString($accent).ToLowerInvariant())
$supplementary=[AllPhp.ByteValues.PhpBytes]::FromBase64('8JCAgA==');$bmp=[AllPhp.ByteValues.PhpBytes]::FromBase64('7oCA')
$utf16Comparison=[string]::CompareOrdinal($utf8.GetString($supplementary.ToArray()),$utf8.GetString($bmp.ToArray()))
$control=[ordered]@{
    latin1_reencoded_ff=[ordered]@{input='/w==';actual_utf8_base64=[Convert]::ToBase64String($reencoded);preserves_php_bytes=([Convert]::ToBase64String($reencoded)-ceq'/w==')}
    latin1_unicode_casefold=[ordered]@{input=[Convert]::ToBase64String($accent);actual_carrier_lower_base64=[Convert]::ToBase64String($carrierLower);preserves_ascii_only_php_casefold=([Convert]::ToBase64String($carrierLower)-ceq[Convert]::ToBase64String($accent))}
    normal_unicode_casefold=[ordered]@{input=[Convert]::ToBase64String($accent);actual_lower_base64=[Convert]::ToBase64String($textLower);preserves_ascii_only_php_casefold=([Convert]::ToBase64String($textLower)-ceq[Convert]::ToBase64String($accent))}
    unicode_order=[ordered]@{left='8JCAgA==';right='7oCA';utf16_ordinal_sign=[Math]::Sign($utf16Comparison);byte_ordinal_sign=$supplementary.CompareBinary($bmp);same_order=([Math]::Sign($utf16Comparison)-eq$supplementary.CompareBinary($bmp))}
}
$report=[ordered]@{status='ISOLATED_COMPONENT_BOUNDARY_CONTRACTS';full_php_compatibility=$false;assembly_sha256=(Get-FileHash -LiteralPath $AssemblyPath -Algorithm SHA256).Hash.ToLowerInvariant();powerShell=$PSVersionTable.PSVersion.ToString();clr=[Environment]::Version.ToString();checks=$checks.ToArray();negative_controls=$control;meaning='Synthetic component/alternative counterexamples only; not PHP interpreter or Linux/native ABI validation'}
[IO.File]::WriteAllText($ReportPath,($report|ConvertTo-Json -Depth 8)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
$passed=@($checks|Where-Object{$_.passed}).Count
Write-Output ('Component boundary checks '+$passed+'/'+$checks.Count)
if($passed-ne$checks.Count){exit 1}
