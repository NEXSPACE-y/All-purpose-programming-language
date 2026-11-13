[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$PairsPath,[Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Utility\Microsoft.PowerShell.Utility.psd1') -ErrorAction Stop
if(Test-Path -LiteralPath $OutputPath){throw 'Preserve previous observation'}
$path=(Resolve-Path -LiteralPath $PairsPath).ProviderPath
$before=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
$pairs=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($path,[Text.UTF8Encoding]::new($false,$true)))
$rows=[Collections.Generic.List[object]]::new()
foreach($pair in $pairs){
    $left=[string]$pair.left;$right=[string]$pair.right
    $dictionary=[Collections.Generic.Dictionary[string,int]]::new([StringComparer]::OrdinalIgnoreCase)
    $dictionary[$left]=1
    $rows.Add([ordered]@{
        id=$pair.id;left=$left;right=$right
        left_utf8_base64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($left))
        right_utf8_base64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($right))
        ordinal=[StringComparer]::Ordinal.Equals($left,$right)
        ordinal_ignore_case=[StringComparer]::OrdinalIgnoreCase.Equals($left,$right)
        invariant_ignore_case=[StringComparer]::InvariantCultureIgnoreCase.Equals($left,$right)
        current_ignore_case=[StringComparer]::CurrentCultureIgnoreCase.Equals($left,$right)
        ps_ceq=($left-ceq$right);ps_ieq=($left-ieq$right)
        lower_left=$left.ToLowerInvariant();lower_right=$right.ToLowerInvariant()
        dictionary_contains_other=$dictionary.ContainsKey($right)
        regex_ignore_case=[regex]::IsMatch($right,('^'+[regex]::Escape($left)+'$'),[Text.RegularExpressions.RegexOptions]::IgnoreCase)
    })
}
$result=[ordered]@{
    scope='Read-only behavior of current .NET/PowerShell comparison APIs; no production comparer changed'
    powershell=$PSVersionTable.PSVersion.ToString();clr=[Environment]::Version.ToString()
    current_culture=[Globalization.CultureInfo]::CurrentCulture.Name
    current_ui_culture=[Globalization.CultureInfo]::CurrentUICulture.Name
    pairs_sha256_before=$before;pairs_sha256_after=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    rows=$rows.ToArray()
}
$target=[IO.Path]::GetFullPath($OutputPath)
[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))
[IO.File]::WriteAllText($target,($result|ConvertTo-Json -Depth 8)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
Write-Output ('Recorded '+$rows.Count+' .NET comparison pairs')
