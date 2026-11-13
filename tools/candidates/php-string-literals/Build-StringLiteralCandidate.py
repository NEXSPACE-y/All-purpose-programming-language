"""Build an isolated PHP literal candidate from exact v3.19 bytes."""
from pathlib import Path
import argparse
import hashlib
import difflib
import json

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
BASE=ROOT/'package/ALL_PHP_v3_12_adapter.ps1'
EXPECTED='113d0c2b967a8726cd9a9dec3f032a725ed9c98ee093c4aedd0a4830737f155b'
ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--output-directory',type=Path,required=True);a=ap.parse_args()
out=a.output_directory.resolve()
if out.exists():raise SystemExit('Output exists; preserve measured revisions')
raw=BASE.read_bytes()
if hashlib.sha256(raw).hexdigest()!=EXPECTED:raise SystemExit('Exact base hash changed')
before=raw.decode('utf-8-sig');value=before
def crlf(s):return s.replace('\r\n','\n').replace('\n','\r\n')
def replace(old,new):
    global value
    old=crlf(old);new=crlf(new)
    if value.count(old)!=1:raise SystemExit('Anchor not unique: '+old[:100])
    value=value.replace(old,new)
replace("""                NamespaceFallbacks = [System.Collections.Generic.Dictionary[int,string]]::new()
""", """                NamespaceFallbacks = [System.Collections.Generic.Dictionary[int,string]]::new()
                DocStrings = [System.Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
                LiteralWarnings = [System.Collections.Generic.List[object]]::new()
""")
replace('        function ConvertTo-PhpTokens([string]$text, $tokens, $lines) {',
        (HERE/'LiteralHelpers.ps1.fragment').read_text(encoding='utf-8')+'        function ConvertTo-PhpTokens([string]$text, $tokens, $lines) {')
replace("""            for ($offset = 0; $offset -lt $text.Length;) {
                $match = $rx.Match($text, $offset)""", """            for ($offset = 0; $offset -lt $text.Length;) {
                $doc = Read-PhpDocToken $text $offset $line
                if ($null -ne $doc) {
                    [void]$tokens.Add($doc.Token);[void]$lines.Add($line)
                    $offset += $doc.Length;$line += $doc.Newlines
                    continue
                }
                $match = $rx.Match($text, $offset)""")
replace("""        ConvertTo-PhpTokens $source $state.Tokens $state.TokenLines
        # Only programs""", """        try { ConvertTo-PhpTokens $source $state.Tokens $state.TokenLines }
        catch {
            if (-not $isCli -or -not ($CliContext.Keys -contains 'CompileError')) { throw }
            $literalError=$CliContext['CompileError']
            [Console]::Error.Write('Parse error: '+$literalError.Message+' in '+$literalError.SourcePath+' on line '+$literalError.Line+"`n")
            $CliContext['ExitCode']=[long]255;$CliContext['Terminated']=$true;$CliContext['TerminationReason']='compile_error'
            return
        }
        # Only programs""")
start=value.index('        function Expand-PhpDoubleString(');end=value.index('        function Take-PhpFirstClassCallableArgs',start)
value=value[:start]+crlf((HERE/'ExpandString.ps1.fragment').read_text(encoding='utf-8'))+value[end:]
replace("""            if ($token.StartsWith('"')) {
                [void](Next-Token)
                return [pscustomobject]@{ Kind='double_string'; Raw=$token }
            }""", """            if ($state.DocStrings.ContainsKey($token)) {
                $doc=$state.DocStrings[$token]
                [void](Next-Token)
                if ($doc.Nowdoc) { return [pscustomobject]@{Kind='literal';Value=$doc.Body} }
                [void](Expand-PhpDoubleString $doc.Body $true $true $true $doc.BodyLine)
                return [pscustomobject]@{Kind='double_string';Raw=$doc.Body;IsBody=$true;Heredoc=$true;StringLine=$doc.BodyLine}
            }
            if ($token.StartsWith('"')) {
                $literalLine=[long]$state.TokenLines[$state.Pos]
                [void](Expand-PhpDoubleString $token $false $false $true $literalLine)
                [void](Next-Token)
                return [pscustomobject]@{ Kind='double_string'; Raw=$token;IsBody=$false;Heredoc=$false;StringLine=$literalLine }
            }""")
replace("""                'double_string' { return (Expand-PhpDoubleString $node.Raw) }""", """                'double_string' {
                    $isBody=$false;$heredoc=$false;$stringLine=[long]$state.Line
                    if($node.PSObject.Properties['IsBody']){$isBody=[bool]$node.IsBody;$heredoc=[bool]$node.Heredoc;$stringLine=[long]$node.StringLine}
                    return (Expand-PhpDoubleString $node.Raw $isBody $heredoc $false $stringLine)
                }""")
replace('        # Load the built-in exception classes up front when the program mentions any of them, so', """        foreach($literalWarning in $state.LiteralWarnings) {
            $savedLine=$state.Line
            try{$state.Line=$literalWarning.Line;Write-PhpDiagnostic $literalWarning.Level $literalWarning.Message}
            finally{$state.Line=$savedLine}
        }
        # Load the built-in exception classes up front when the program mentions any of them, so""")
result=b'\xef\xbb\xbf'+value.encode('utf-8');out.mkdir(parents=True)
candidate=out/'ALL_PHP_string_literal_candidate.ps1';candidate.write_bytes(result)
(out/'literal.patch').write_text(''.join(difflib.unified_diff(before.splitlines(True),value.splitlines(True),fromfile='base113d',tofile='string-literals')),encoding='utf-8',newline='')
(out/'provenance.json').write_text(json.dumps({'status':'ISOLATED_NOT_VERIFIED','base':str(BASE),'base_sha256':EXPECTED,'candidate':str(candidate),'candidate_sha256':hashlib.sha256(result).hexdigest(),'package_modified':False,'scope':'Heredoc/nowdoc lexical tokens and indentation, verified UTF8 string escapes; arbitrary nonUTF8 bytes remain unsupported'},indent=2)+'\n',encoding='utf-8')
for name in ['Build-StringLiteralCandidate.py','LiteralHelpers.ps1.fragment','ExpandString.ps1.fragment']:
    (out/(name+'.snapshot')).write_bytes((HERE/name).read_bytes())
print(hashlib.sha256(result).hexdigest())
