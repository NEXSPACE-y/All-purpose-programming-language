"""Missing-key quiet reads return null before any diagnostic text formatting.

The existing quiet-evaluation caller still handles isset/empty/coalesce and
suppression. A missing key does not require host UTF-8 conversion in that path;
ordinary non-quiet legacy API errors retain their previous contract.
"""


def apply(value: str) -> str:
    newline='\r\n' if '\r\n' in value else '\n'
    value=value.replace('\r\n','\n')
    old='''            if (-not $array.Items.Contains($keyString)) {
                if (($PhpDiagnostics -or $isCli) -and $state.QuietDepth -eq 0) {'''
    new='''            if (-not $array.Items.Contains($keyString)) {
                if($state.QuietDepth-gt0){return $null}
                if (($PhpDiagnostics -or $isCli) -and $state.QuietDepth -eq 0) {'''
    if value.count(old)!=1:raise ValueError('ArrayQuietReadEdits expects one missing-key quiet branch')
    return value.replace(old,new).replace('\n',newline)
