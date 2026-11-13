from pathlib import Path
import difflib
import hashlib
import json
import argparse

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
ap=argparse.ArgumentParser();ap.add_argument('--output',type=Path,required=True);a=ap.parse_args()
out=a.output.resolve()
if out.exists():raise SystemExit('Preserve existing revision; select fresh output')
base=ROOT/'package/ALL_PHP_v3_12_adapter.ps1';raw=base.read_bytes()
expected='113d0c2b967a8726cd9a9dec3f032a725ed9c98ee093c4aedd0a4830737f155b'
if hashlib.sha256(raw).hexdigest()!=expected:raise SystemExit('Reviewed base hash differs')
before=raw.decode('utf-8-sig');value=before
def replace(old,new,count=1):
 global value
 old=old.replace('\n','\r\n');new=new.replace('\n','\r\n')
 if value.count(old)!=count:raise SystemExit('Anchor differs: '+old[:90])
 value=value.replace(old,new)

helpers=(HERE/'CallableResolution.ps1').read_text(encoding='utf-8').replace('\n','\r\n')
anchor='        # Call a PHP callable value (closure, function name, [object, method], invokable object)'
if value.count(anchor)!=1:raise SystemExit('Insertion anchor differs')
value=value.replace(anchor,helpers+'\r\n'+anchor)
replace("""        function Invoke-PhpValueCallable($callee, $values) {
            $values = @($values)""", """        function Invoke-PhpValueCallable($callee, $values, [string]$callbackFunction='') {
            $callee = Assert-PhpValueCallable $callee $callbackFunction
            $values = @($values)
            if ($callbackFunction.Length -gt 0) { $values=Prepare-PhpCallbackValues $callee $values }""")
replace("return (Invoke-PhpValueCallable $callArgs[0] $rest)","return (Invoke-PhpValueCallable $callArgs[0] $rest 'call_user_func')")
replace("return (Invoke-PhpValueCallable $callArgs[0] @($callArgs[1].Items.Values))","return (Invoke-PhpValueCallable $callArgs[0] (Get-PhpCallbackArrayArguments $callArgs[1]) 'call_user_func_array')")
replace("""                    $first = Read-Expr 1
                    $key = $null
                    $value = $first
                    if ((Peek-Token) -ceq '=>') {
                        if ($spread) { throw 'ALL PHP: Spread cannot have explicit key' }
                        [void](Next-Token)
                        $key = $first
                        $value = Read-Expr 1
                    }
                    [void]$entries.Add([pscustomobject]@{ Key=$key; Value=$value; Spread=$spread })""", """                    $byReference=$false
                    if ((Peek-Token) -ceq '&') {
                        if ($spread) { throw 'ALL PHP: Array spread cannot be by reference' }
                        [void](Next-Token);$byReference=$true
                    }
                    $first = Read-Expr 1
                    $key = $null
                    $value = $first
                    if ((Peek-Token) -ceq '=>') {
                        if ($spread) { throw 'ALL PHP: Spread cannot have explicit key' }
                        if ($byReference) { throw 'ALL PHP: Array key cannot be a reference' }
                        [void](Next-Token)
                        $key = $first
                        if ((Peek-Token) -ceq '&') { [void](Next-Token);$byReference=$true }
                        $value = Read-Expr 1
                    }
                    [void]$entries.Add([pscustomobject]@{ Key=$key; Value=$value; Spread=$spread;ByReference=$byReference })""")
replace("""                    foreach ($entry in $node.Entries) {
                        $value = Invoke-PhpExpr $entry.Value""", """                    foreach ($entry in $node.Entries) {
                        if ($entry.PSObject.Properties['ByReference'] -and $entry.ByReference) {
                            $key=$null
                            if ($null -ne $entry.Key) { $key=Invoke-PhpExpr $entry.Key }
                            $cell=Get-PhpLValueCell $entry.Value
                            Set-PhpArrayItem $array $key $cell ($null -eq $entry.Key)
                            continue
                        }
                        $value = Invoke-PhpExpr $entry.Value""")
replace("""                'first_class_invoke' {
                    $callable=Invoke-PhpExpr $node.Callee""", """                'first_class_invoke' {
                    $callable=Assert-PhpValueCallable (Invoke-PhpExpr $node.Callee)""")
replace("""                    if ($null -ne $callable -and $callable -is [string]) {
                        return [pscustomobject]@{
                            PhpType='first_class_callable'; Id=(New-PhpObjectId); Mode='function'; Name=$callable
                        }
                    }""", """                    if ($null -ne $callable -and $callable -is [string]) {
                        $split=$callable.IndexOf('::')
                        if ($split -gt 0) {
                            return [pscustomobject]@{ PhpType='first_class_callable'; Id=(New-PhpObjectId)
                                Mode='static'; Class=$callable.Substring(0,$split); Name=$callable.Substring($split+2) }
                        }
                        return [pscustomobject]@{
                            PhpType='first_class_callable'; Id=(New-PhpObjectId); Mode='function'; Name=$callable
                        }
                    }
                    if (Is-PhpArray $callable) {
                        $target=Get-PhpArrayItem $callable ([long]0);$member=Get-PhpArrayItem $callable ([long]1)
                        if (Is-PhpObject $target) {
                            return [pscustomobject]@{ PhpType='first_class_callable'; Id=(New-PhpObjectId)
                                Mode='method'; BoundThis=$target; Name=$member }
                        }
                        return [pscustomobject]@{ PhpType='first_class_callable'; Id=(New-PhpObjectId)
                            Mode='static'; Class=[string]$target; Name=$member }
                    }""")
replace("""                'invoke' {
                    $callee=Invoke-PhpExpr $node.Callee""", """                'invoke' {
                    $callee=Assert-PhpValueCallable (Invoke-PhpExpr $node.Callee)""")
# The reference-call path must also normalize its callee before selecting a user function.
replace("""            if ($node.Kind -eq 'invoke') {
                $callee=Invoke-PhpExpr $node.Callee""", """            if ($node.Kind -eq 'invoke') {
                $callee=Assert-PhpValueCallable (Invoke-PhpExpr $node.Callee)""")
replace("""                    if (Is-PhpObject $callee) {
                        $magic=Find-OptionalPhpMethod $callee.Class '__invoke'""", """                    if (Is-PhpArray $callee) {
                        $definition=Get-PhpValueCallableDefinition $callee
                        $args=Evaluate-PhpUserArguments $node.Args $definition
                        return (Invoke-PhpValueCallable $callee $args)
                    }
                    if (Is-PhpObject $callee) {
                        $magic=Find-OptionalPhpMethod $callee.Class '__invoke'""")
# Direct known-global/qualified/imported callback calls use PHP's early binding.
# A namespace fallback or dynamic invocation instead validates in the builtin body.
replace("""                    $callName = Resolve-PhpFunctionNodeName $node
                    if ($state.Functions.ContainsKey($callName)) {""", """                    $callName = Resolve-PhpFunctionNodeName $node
                    $callbackName=$callName.ToLowerInvariant()
                    if ($node.Name -ieq $callName -and
                        -not $state.Functions.ContainsKey($callName) -and
                        (($callbackName -ceq 'call_user_func' -and $node.Args.Count -ge 1) -or
                         ($callbackName -ceq 'call_user_func_array' -and $node.Args.Count -eq 2))) {
                        $plainArguments=$true
                        foreach ($expression in $node.Args) { if ($expression.Kind -ceq 'named_argument') { $plainArguments=$false } }
                        if ($plainArguments) {
                            $boundCallback=Assert-PhpValueCallable (Invoke-PhpExpr $node.Args[0]) $callbackName
                            $earlyArgs=[System.Collections.Generic.List[object]]::new()
                            [void]$earlyArgs.Add($boundCallback)
                            for ($argumentIndex=1;$argumentIndex -lt $node.Args.Count;$argumentIndex++) {
                                [void]$earlyArgs.Add((Invoke-PhpExpr $node.Args[$argumentIndex]))
                            }
                            return (Invoke-PhpFunction $callName ($earlyArgs.ToArray()))
                        }
                    }
                    if ($state.Functions.ContainsKey($callName)) {""")
out.mkdir(parents=True);candidate=out/'ALL_PHP_dynamic_call_candidate.ps1'
result=b'\xef\xbb\xbf'+value.encode('utf-8');candidate.write_bytes(result)
(out/'dynamic-call.patch').write_text(''.join(difflib.unified_diff(before.splitlines(True),value.splitlines(True),fromfile='base113d',tofile='dynamic-call')),encoding='utf-8',newline='')
(out/'provenance.json').write_text(json.dumps({'status':'ISOLATED_NOT_COMPLETE','base':str(base),'base_sha256':expected,'candidate':str(candidate),'candidate_sha256':hashlib.sha256(result).hexdigest(),'helpers_sha256':hashlib.sha256((HERE/'CallableResolution.ps1').read_bytes()).hexdigest(),'package_modified':False},indent=2)+'\n',encoding='utf-8')
(out/'base.snapshot.ps1').write_bytes(raw)
(out/'helpers.snapshot.ps1').write_bytes((HERE/'CallableResolution.ps1').read_bytes())
(out/'generator.snapshot.py').write_bytes(Path(__file__).read_bytes())
print(hashlib.sha256(result).hexdigest())
