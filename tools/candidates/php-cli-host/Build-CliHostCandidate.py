"""Extend existing CLI context for real code-body input and argument globals."""
from pathlib import Path
import hashlib
import difflib
import json

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
BASE=ROOT/'package/ALL_PHP_v3_12_adapter.ps1'
EXPECTED='113d0c2b967a8726cd9a9dec3f032a725ed9c98ee093c4aedd0a4830737f155b'
raw=BASE.read_bytes()
if hashlib.sha256(raw).hexdigest()!=EXPECTED:raise SystemExit('Package input differs from reviewed v3.19')
before=raw.decode('utf-8-sig');value=before
def replace(old,new):
    global value
    old=old.replace('\n','\r\n');new=new.replace('\n','\r\n')
    if value.count(old)!=1:raise SystemExit('Anchor is not unique')
    value=value.replace(old,new)

replace("""        $source = $Code.Trim()
        if ($source -notmatch '^<\\?php(?:\\s|$)') {
            throw 'ALL PHP: A <?php opening tag is required'
        }
        $source = [regex]::Replace($source, '^<\\?php\\b', '')
        $source = $source.TrimEnd()
        if ($source.EndsWith('?>')) {
            $source = $source.Substring(0, $source.Length - 2)
        }""", """        if ($isCli -and ($CliContext.Keys -contains 'SourceMode') -and
            $CliContext['SourceMode'] -ceq 'body') {
            # CLI -r starts in PHP code mode. Preserve the actual input body,
            # including leading lines; do not add a synthetic opening tag.
            $source = $Code
        } else {
            $source = $Code.Trim()
            if ($source -notmatch '^<\\?php(?:\\s|$)') {
                throw 'ALL PHP: A <?php opening tag is required'
            }
            $source = [regex]::Replace($source, '^<\\?php\\b', '')
            $source = $source.TrimEnd()
            if ($source.EndsWith('?>')) {
                $source = $source.Substring(0, $source.Length - 2)
            }
        }""")

replace("""        function Get-PhpVariableSlot([string]$name) {
            if ($state.GlobalBindings.Contains($name)) {""", """        function Get-PhpVariableSlot([string]$name) {
            # CLI-provided server data is a superglobal, including inside user
            # function frames. Existing non-host runs retain their prior setup.
            if ($name -ceq '_SERVER' -and $state.Globals.ContainsKey('_SERVER')) {
                return [pscustomobject]@{ Store=$state.Globals; Key=$name }
            }
            if ($state.GlobalBindings.Contains($name)) {""")

replace("""        # Load the built-in exception classes up front when the program mentions any of them, so""", """        if ($isCli -and ($CliContext.Keys -contains 'InitialIni')) {
            foreach ($setting in $CliContext['InitialIni'].Keys) {
                $state.Ini[[string]$setting] = [string]$CliContext['InitialIni'][$setting]
            }
            if ($state.Ini.ContainsKey('error_reporting')) {
                $state.ErrorReporting = [long]$state.Ini['error_reporting']
            }
        }
        if ($isCli -and ($CliContext.Keys -contains 'ScriptArguments')) {
            $scriptArguments = @($CliContext['ScriptArguments'])
            $argumentArray = New-PhpArray
            foreach ($argument in $scriptArguments) {
                Set-PhpArrayItem $argumentArray $null ([string]$argument) $true
            }
            $state.Globals['argc'] = [long]$scriptArguments.Count
            $state.Globals['argv'] = $argumentArray
            $server = New-PhpArray
            Set-PhpArrayItem $server 'argc' ([long]$scriptArguments.Count) $false
            Set-PhpArrayItem $server 'argv' $argumentArray $false
            $state.Globals['_SERVER'] = $server
        }
        # Load the built-in exception classes up front when the program mentions any of them, so""")

output=b'\xef\xbb\xbf'+value.encode('utf-8')
candidate=HERE/'ALL_PHP_cli_host_candidate.ps1'
if candidate.exists():raise SystemExit('Candidate already exists; preserve measured revisions')
candidate.write_bytes(output)
(HERE/'cli-host-context.patch').write_text(''.join(difflib.unified_diff(before.splitlines(True),value.splitlines(True),fromfile='base113d',tofile='cli-host-context')),encoding='utf-8',newline='')
(HERE/'provenance.json').write_text(json.dumps({'status':'ISOLATED_NOT_VERIFIED','base':str(BASE),'base_sha256':EXPECTED,'candidate':str(candidate),'candidate_sha256':hashlib.sha256(output).hexdigest(),'package_modified':False,'scope':'CLI code-body mode, initial diagnostic INI profile and argv/argc; not all CLI flags/INI/server globals'},indent=2)+'\n',encoding='utf-8')
print(hashlib.sha256(output).hexdigest())
