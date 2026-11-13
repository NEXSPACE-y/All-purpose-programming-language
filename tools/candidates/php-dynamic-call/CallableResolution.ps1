        function Throw-PhpInvalidValueCallable([string]$message, [string]$callbackReason,
            [string]$callbackFunction, [string]$legacyText='ALL PHP: Value is not callable') {
            if ($callbackFunction.Length -gt 0) {
                Throw-PhpError 'TypeError' ($callbackFunction+'(): Argument #1 ($callback) must be a valid callback, '+$callbackReason) $legacyText
            }
            Throw-PhpError 'Error' $message $legacyText
        }
        function Assert-PhpMethodValueCallable([string]$className, [string]$methodName,
            [bool]$staticOnly, [string]$callbackFunction) {
            if ($className.StartsWith([string][char]92)) { $className=$className.Substring(1) }
            $className=Resolve-PhpClass $className
            if ($phpPreludeTriggers.Contains($className)) { Ensure-PhpPrelude }
            if ($className -ine 'stdClass' -and -not $state.Classes.ContainsKey($className)) {
                Throw-PhpInvalidValueCallable ('Class "'+$className+'" not found') ('class "'+$className+'" not found') $callbackFunction
            }
            $method=Find-OptionalPhpMethod $className $methodName
            if ($null -eq $method) {
                Throw-PhpInvalidValueCallable ('Call to undefined method '+$className+'::'+$methodName+'()') ('class '+$className+' does not have a method "'+$methodName+'"') $callbackFunction
            }
            try { Assert-PhpVisibility $method.Visibility $method.Owner }
            catch {
                if ($_.Exception.Message -notlike 'ALL PHP: Cannot access*') { throw }
                $scope=if ($null -eq $state.ClassContext) { 'global scope' } else { 'scope '+$state.ClassContext }
                Throw-PhpInvalidValueCallable ('Call to '+$method.Visibility+' method '+$method.Owner+'::'+$method.Name+'() from '+$scope) ('cannot access '+$method.Visibility+' method '+$method.Owner+'::'+$method.Name+'()') $callbackFunction
            }
            if ($staticOnly -and -not $method.Static) {
                Throw-PhpInvalidValueCallable ('Non-static method '+$method.Owner+'::'+$method.Name+'() cannot be called statically') ('non-static method '+$method.Owner+'::'+$method.Name+'() cannot be called statically') $callbackFunction
            }
            return $className
        }
        function Assert-PhpValueCallable($callee, [string]$callbackFunction='') {
            if ($null -ne $callee -and $callee.PSObject.Properties['PhpType'] -and
                $callee.PhpType -in @('closure','first_class_callable')) { return $callee }
            if ($callee -is [string]) {
                $name=$callee
                if ($name.StartsWith([string][char]92)) { $name=$name.Substring(1) }
                $split=$name.IndexOf('::')
                if ($split -gt 0) {
                    $className=Assert-PhpMethodValueCallable $name.Substring(0,$split) $name.Substring($split+2) $true $callbackFunction
                    return ($className+'::'+$name.Substring($split+2))
                }
                if (-not $state.Functions.ContainsKey($name) -and -not $phpBuiltinNames.Contains($name) -and
                    -not (Test-PhpNativeFunction $name)) {
                    Throw-PhpInvalidValueCallable ('Call to undefined function '+$name+'()') ('function "'+$callee+'" not found or invalid function name') $callbackFunction ("ALL PHP: Undefined function '"+$callee+"'")
                }
                return $name
            }
            if (Is-PhpObject $callee) {
                if ($null -eq (Find-OptionalPhpMethod $callee.Class '__invoke')) {
                    Throw-PhpInvalidValueCallable ('Object of type '+$callee.Class+' is not callable') 'no array or string given' $callbackFunction 'ALL PHP: Object is not callable'
                }
                return $callee
            }
            if (Is-PhpArray $callee) {
                if ($callee.Items.Count -ne 2) {
                    Throw-PhpInvalidValueCallable 'Array callback must have exactly two elements' 'array callback must have exactly two members' $callbackFunction 'ALL PHP: Array is not a valid callable'
                }
                if (-not $callee.Items.Contains('i:0') -or -not $callee.Items.Contains('i:1')) {
                    Throw-PhpInvalidValueCallable 'Array callback has to contain indices 0 and 1' 'array callback has to contain indices 0 and 1' $callbackFunction 'ALL PHP: Array is not a valid callable'
                }
                $target=Get-PhpArrayItem $callee ([long]0)
                $member=Get-PhpArrayItem $callee ([long]1)
                if ($target -isnot [string] -and -not (Is-PhpObject $target)) {
                    Throw-PhpInvalidValueCallable 'First array member is not a valid class name or object' 'first array member is not a valid class name or object' $callbackFunction 'ALL PHP: Array is not a valid callable'
                }
                if ($member -isnot [string]) {
                    Throw-PhpInvalidValueCallable 'Second array member is not a valid method' 'second array member is not a valid method' $callbackFunction 'ALL PHP: Array is not a valid callable'
                }
                if (Is-PhpObject $target) {
                    [void](Assert-PhpMethodValueCallable $target.Class $member $false $callbackFunction)
                } else { $target=Assert-PhpMethodValueCallable $target $member $true $callbackFunction }
                # Bind the selected array target before argument expressions can
                # mutate the source variable. Object identity is preserved.
                $bound=New-PhpArray
                Set-PhpArrayItem $bound $null $target $true
                Set-PhpArrayItem $bound $null $member $true
                return $bound
            }
            $type=if ($null -eq $callee) { 'null' } elseif ($callee -is [bool]) { 'bool' }
                elseif ($callee -is [long]) { 'int' } elseif ($callee -is [double]) { 'float' } else { 'unknown' }
            Throw-PhpInvalidValueCallable ('Value of type '+$type+' is not callable') 'no array or string given' $callbackFunction
        }
        function Get-PhpValueCallableDefinition($callee) {
            if ($null -ne $callee -and $callee.PSObject.Properties['PhpType']) {
                if ($callee.PhpType -ceq 'closure') { return $callee.Definition }
                if ($callee.PhpType -ceq 'first_class_callable') {
                    if ($callee.Mode -ceq 'function' -and $state.Functions.ContainsKey($callee.Name)) { return $state.Functions[$callee.Name] }
                    if ($callee.Mode -ceq 'method') { return (Find-OptionalPhpMethod $callee.BoundThis.Class $callee.Name) }
                    if ($callee.Mode -ceq 'static') { return (Find-OptionalPhpMethod $callee.Class $callee.Name) }
                }
            }
            if (Is-PhpObject $callee) { return (Find-OptionalPhpMethod $callee.Class '__invoke') }
            if (Is-PhpArray $callee) {
                $target=Get-PhpArrayItem $callee ([long]0);$member=Get-PhpArrayItem $callee ([long]1)
                $className=if (Is-PhpObject $target) { $target.Class } else { [string]$target }
                return (Find-OptionalPhpMethod $className $member)
            }
            if ($callee -is [string]) {
                if ($state.Functions.ContainsKey($callee)) { return $state.Functions[$callee] }
                $split=$callee.IndexOf('::')
                if ($split -gt 0) { return (Find-OptionalPhpMethod $callee.Substring(0,$split) $callee.Substring($split+2)) }
            }
            return $null
        }
        function Get-PhpCallbackArrayArguments($array) {
            $values=[System.Collections.Generic.List[object]]::new()
            foreach ($key in $array.Items.Keys) {
                $value=$array.Items[$key]
                if ($key.StartsWith('s:')) {
                    [void]$values.Add([pscustomobject]@{ PhpType='named_argument';Name=$key.Substring(2);Value=$value })
                } else { [void]$values.Add($value) }
            }
            return ,($values.ToArray())
        }
        function Prepare-PhpCallbackValues($callee,$values) {
            $definition=Get-PhpValueCallableDefinition $callee
            if ($null -eq $definition) { return ,$values }
            $prepared=[System.Collections.Generic.List[object]]::new()
            $position=0;$index=0
            foreach ($item in $values) {
                $name=$null;$value=$item;$parameter=$null
                if ($null -ne $item -and $item.PSObject.Properties['PhpType'] -and $item.PhpType -ceq 'named_argument') {
                    $name=$item.Name;$value=$item.Value
                    foreach ($p in $definition.Params) { if ($p.Name -ceq $name) { $parameter=$p;break } }
                } elseif ($position -lt $definition.Params.Count) {
                    $parameter=$definition.Params[$position]
                    if (-not $parameter.Variadic) { $position++ }
                }
                if ($null -ne $parameter -and $parameter.ByRef) {
                    if (Is-PhpRefCell $value) { $cell=$value }
                    elseif ($null -ne $value -and $value.PSObject.Properties['PhpType'] -and $value.PhpType -ceq 'refargument') { $cell=$value.Cell }
                    else {
                        $displayName=[string]$definition.Name
                        if ($definition.PSObject.Properties['Owner'] -and -not [string]::IsNullOrEmpty([string]$definition.Owner)) {
                            $displayName=$definition.Owner+'::'+$displayName
                        }
                        Write-PhpDiagnostic 2 ($displayName+'(): Argument #'+($index+1)+' ($'+$parameter.Name+') must be passed by reference, value given')
                        $cell=[pscustomobject]@{PhpType='refcell';Value=(Copy-PhpValue $value)}
                    }
                    $value=[pscustomobject]@{PhpType='refargument';Cell=$cell;Value=(Copy-PhpValue $cell.Value)}
                } elseif (Is-PhpRefCell $value) { $value=$value.Value }
                if ($null -ne $name) { $value=[pscustomobject]@{PhpType='named_argument';Name=$name;Value=$value} }
                [void]$prepared.Add($value);$index++
            }
            return ,($prepared.ToArray())
        }
