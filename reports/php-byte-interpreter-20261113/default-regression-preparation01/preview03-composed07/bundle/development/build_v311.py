from pathlib import Path
p=Path('/mnt/data/ALL_PHP_v3_11_3areas_work/ALL_PHP_v3_10_adapter.ps1')
s=p.read_text(encoding='utf-8-sig')

def rep_last(old,new):
    global s
    idx=s.rfind(old)
    if idx < 0: raise Exception(f'not found: {old[:80]!r}')
    s=s[:idx]+new+s[idx+len(old):]

def rep(old,new,n=1):
    global s
    count=s.count(old)
    if count!=n: raise Exception(f'expected {n} hits; got {count} for {old[:100]!r}')
    s=s.replace(old,new)

rep("if ($token -in @('abstract','final','class','trait')) {", "if ($token -in @('abstract','final','readonly','class','trait')) {")
rep("""                $isTrait=($token -eq 'trait')
                if ($token -eq 'abstract')""", """                $isTrait=($token -eq 'trait')
                $isReadonlyClass=$false
                if ($token -eq 'readonly') { $isReadonlyClass=$true; [void](Next-Token); Expect-Token 'class' }
                elseif ($token -eq 'abstract')""")
rep("""while ((Peek-Token) -in @('public','private','protected','static','abstract','final')) {""", """while ((Peek-Token) -in @('public','private','protected','static','abstract','final','readonly')) {""")
rep("""                    $isFinalMethod=$false
                    $modifiers""", """                    $isFinalMethod=$false
                    $isReadonlyProperty=$false
                    $modifiers""")
rep("""                        elseif ($modifier -eq 'final') { $isFinalMethod=$true }
""", """                        elseif ($modifier -eq 'final') { $isFinalMethod=$true }
                        elseif ($modifier -eq 'readonly') { $isReadonlyProperty=$true }
""")
rep("""                    if ((Peek-Token) -eq 'function') {
                        if ($isAbstractMethod -and $isFinalMethod) {""", """                    if ((Peek-Token) -eq 'function') {
                        if ($isReadonlyProperty) { throw 'ALL PHP: readonly modifier cannot be applied to method' }
                        if ($isAbstractMethod -and $isFinalMethod) {""")
rep("""                        $method = Read-Function $isAbstractMethod
                        $method.Visibility=$visibility
""", """                        $method = Read-Function $isAbstractMethod $true
                        $method.Visibility=$visibility
""")
rep_last("""                        [void]$methods.Add($method)
                    } elseif ((Peek-Token) -eq 'const') {""", """                        [void]$methods.Add($method)
                        if ($method.Name -ieq '__construct') {
                            foreach ($parameter in $method.Params) {
                                if (-not $parameter.Promoted) { continue }
                                [void]$properties.Add([pscustomobject]@{
                                    Name=$parameter.Name; Default=$null
                                    Visibility=$parameter.Visibility; Static=$false
                                    Owner=$name; TypeName=$parameter.TypeName
                                    Readonly=([bool]$parameter.Readonly -or $isReadonlyClass)
                                })
                            }
                        }
                    } elseif ((Peek-Token) -eq 'const') {""")
rep("""                        if ($isStatic -or $isAbstractMethod -or $isFinalMethod) {
                            throw 'ALL PHP: Unsupported constant modifier'
""", """                        if ($isStatic -or $isAbstractMethod -or $isFinalMethod -or $isReadonlyProperty) {
                            throw 'ALL PHP: Unsupported constant modifier'
""")
rep("""                    } elseif ((Peek-Token) -cmatch '^\$[A-Za-z_][A-Za-z_0-9]*$') {
                        if ($isAbstractMethod -or $isFinalMethod) {
                            throw 'ALL PHP: Abstract/final modifier not valid for properties'
                        }
                        $propName = (Next-Token).Substring(1)
                        $defaultExpr = $null
                        if ((Peek-Token) -ceq '=') {
                            [void](Next-Token)
                            $defaultExpr = Read-Expr 1
                        }
                        Expect-Token ';'
                        [void]$properties.Add([pscustomobject]@{
                            Name=$propName; Default=$defaultExpr
                            Visibility=$visibility; Static=$isStatic; Owner=$name
                        })
""", """                    } else {
                        $propertyType=''
                        if ((Peek-Token) -ceq '?' -or
                            (Peek-Token) -cmatch '^[A-Za-z_][A-Za-z_0-9]*$') {
                            $propertyType=Read-PhpTypeAnnotation
                        }
                        if ((Peek-Token) -cnotmatch '^\$[A-Za-z_][A-Za-z_0-9]*$') {
                            throw \"ALL PHP: Unsupported class member '$(Peek-Token)'\"
                        }
                        if ($isAbstractMethod -or $isFinalMethod) {
                            throw 'ALL PHP: Abstract/final modifier not valid for properties'
                        }
                        $isReadOnly=($isReadonlyProperty -or $isReadonlyClass)
                        if ($isReadOnly -and $isStatic) {
                            throw 'ALL PHP: readonly static property is not allowed'
                        }
                        if ($isReadOnly -and [string]::IsNullOrEmpty($propertyType)) {
                            throw 'ALL PHP: readonly property requires a type'
                        }
                        $propName = (Next-Token).Substring(1)
                        $defaultExpr = $null
                        if ((Peek-Token) -ceq '=') {
                            [void](Next-Token)
                            $defaultExpr = Read-Expr 1
                        }
                        if ($isReadOnly -and $null -ne $defaultExpr) {
                            throw 'ALL PHP: readonly property cannot have a default value'
                        }
                        Expect-Token ';'
                        [void]$properties.Add([pscustomobject]@{
                            Name=$propName; Default=$defaultExpr
                            Visibility=$visibility; Static=$isStatic; Owner=$name
                            TypeName=$propertyType; Readonly=$isReadOnly
                        })
""")
# After previous refactor, remove the old trailing else branch after property parsing.
rep("""                        })
                    } else {
                        throw \"ALL PHP: Unsupported class member '$(Peek-Token)'\"
                    }
                }
                Expect-Token '}'
                return [pscustomobject]@{
                    Kind=$(if ($isTrait)""", """                        })
                    }
                }
                Expect-Token '}'
                return [pscustomobject]@{
                    Kind=$(if ($isTrait)""")
rep("""                    Abstract=$isAbstract; Final=$isFinal; Traits=$traits.ToArray()
""", """                    Abstract=$isAbstract; Final=$isFinal; Readonly=$isReadonlyClass; Traits=$traits.ToArray()
""")
# Promotion parser. Read-Parameters used by Read-Function, Read-Closure, Read-Arrow.
rep("function Read-Parameters {", "function Read-Parameters([bool]$allowPromotion = $false) {")
rep("""                    $typeName = ''
                    if ((Peek-Token)""", """                    $visibility = ''
                    $promotedReadonly = $false
                    if ($allowPromotion) {
                        while ((Peek-Token) -in @('public','protected','private','readonly')) {
                            $modifier=Next-Token
                            if ($modifier -eq 'readonly') {
                                if ($promotedReadonly) { throw 'ALL PHP: Duplicate readonly parameter modifier' }
                                $promotedReadonly=$true
                            } elseif (-not [string]::IsNullOrEmpty($visibility)) {
                                throw 'ALL PHP: Duplicate promoted parameter visibility'
                            } else { $visibility=$modifier }
                        }
                        if ($promotedReadonly -and [string]::IsNullOrEmpty($visibility)) {
                            $visibility='public'
                        }
                    }
                    $typeName = ''
                    if ((Peek-Token)""")
rep("""                    $default = $null
                    if ((Peek-Token) -ceq '=') {""", """                    if (-not [string]::IsNullOrEmpty($visibility) -and
                        [string]::IsNullOrEmpty($typeName) -and $promotedReadonly) {
                        throw 'ALL PHP: Promoted readonly property must have a type'
                    }
                    if (-not [string]::IsNullOrEmpty($visibility) -and ($byRef -or $variadic)) {
                        throw 'ALL PHP: Promoted property cannot be by-reference or variadic'
                    }
                    $default = $null
                    if ((Peek-Token) -ceq '=') {""")
rep("""                        ByRef=$byRef; TypeName=$typeName
""", """                        ByRef=$byRef; TypeName=$typeName
                        Promoted=(-not [string]::IsNullOrEmpty($visibility))
                        Visibility=$visibility; Readonly=$promotedReadonly
""")
rep("function Read-Function([bool]$declarationOnly = $false) {", "function Read-Function([bool]$declarationOnly = $false, [bool]$allowPromotion = $false) {")
rep("""            $parameters = Read-Parameters
            $returnType=''""", """            $parameters = Read-Parameters $allowPromotion
            if ($name -ine '__construct') {
                foreach ($p in $parameters) {
                    if ($p.Promoted) { throw 'ALL PHP: Only constructor parameters may be promoted' }
                }
            }
            $returnType=''""")

# Additional class registration invariants.
rep("""                    if ($null -ne $node.Parent -and $state.Classes[$node.Parent].Final) {
                        throw \"ALL PHP: Cannot extend final class '$($node.Parent)'\"
                    }
""", """                    if ($null -ne $node.Parent -and $state.Classes[$node.Parent].Final) {
                        throw \"ALL PHP: Cannot extend final class '$($node.Parent)'\"
                    }
                    if ($null -ne $node.Parent -and $state.Classes[$node.Parent].Readonly -and -not $node.Readonly) {
                        throw 'ALL PHP: Non-readonly class cannot extend readonly class'
                    }
                    if ($node.Readonly -and $null -ne $node.Parent -and -not $state.Classes[$node.Parent].Readonly) {
                        throw 'ALL PHP: Readonly class cannot extend non-readonly class'
                    }
""")
rep("""                    $effectiveProperties=[System.Collections.Generic.List[object]]::new()
                    foreach ($prop in $node.Properties) { [void]$effectiveProperties.Add($prop) }
""", """                    $effectiveProperties=[System.Collections.Generic.List[object]]::new()
                    $declaredNames=[System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
                    foreach ($prop in $node.Properties) {
                        if (-not $declaredNames.Add($prop.Name)) {
                            throw \"ALL PHP: Duplicate property '$($prop.Name)'\"
                        }
                        [void]$effectiveProperties.Add($prop)
                    }
""")
rep("""                                Name=$prop.Name; Default=$prop.Default
                                Visibility=$prop.Visibility; Static=$prop.Static
                                Owner=$node.Name
""", """                                Name=$prop.Name; Default=$prop.Default
                                Visibility=$prop.Visibility; Static=$prop.Static
                                Owner=$node.Name; TypeName=$prop.TypeName
                                Readonly=([bool]$prop.Readonly -or [bool]$node.Readonly)
""")
rep("""                        if ($prop.Static) {
                            $default=$null
                            if ($null -ne $prop.Default) { $default=Invoke-PhpExpr $prop.Default }
                            $statics[$prop.Name]=Copy-PhpValue $default
                        }
""", """                        if ($prop.Static) {
                            if ($null -eq $prop.Default -and
                                -not [string]::IsNullOrEmpty([string]$prop.TypeName)) {
                                continue # typed static property stays uninitialized
                            }
                            $default=$null
                            if ($null -ne $prop.Default) { $default=Invoke-PhpExpr $prop.Default }
                            $statics[$prop.Name]=Copy-PhpValue (Convert-PhpTypedValue $default ([string]$prop.TypeName) ('property ' + $prop.Name))
                        }
""")
rep("""                        Abstract=$node.Abstract; Final=$node.Final
""", """                        Abstract=$node.Abstract; Final=$node.Final; Readonly=$node.Readonly
""")

# Typed property read/uninitialized and writes/readonly guard.
rep("""            $result = $state.Classes[$prop.Owner].StaticValues[$node.Name]
            if (Is-PhpRefCell $result)""", """            $store=$state.Classes[$prop.Owner].StaticValues
            if (-not $store.ContainsKey($node.Name)) {
                throw \"ALL PHP: Typed static property '$($node.Name)' must not be accessed before initialization\"
            }
            $result = $store[$node.Name]
            if (Is-PhpRefCell $result)""")
rep("""            $store = $state.Classes[$prop.Owner].StaticValues
            if (Is-PhpRefCell $store[$node.Name]) {""", """            $store = $state.Classes[$prop.Owner].StaticValues
            $value=Convert-PhpTypedValue $value ([string]$prop.TypeName) ('property ' + $node.Name)
            if ($store.ContainsKey($node.Name) -and (Is-PhpRefCell $store[$node.Name])) {""")
rep("""                if (-not $present) {
                    $magic=Find-OptionalPhpMethod $base.Class '__get'
""", """                if (-not $present) {
                    if ($null -ne $declared -and
                        -not [string]::IsNullOrEmpty([string]$declared.TypeName)) {
                        throw \"ALL PHP: Typed property '$($node.Name)' must not be accessed before initialization\"
                    }
                    $magic=Find-OptionalPhpMethod $base.Class '__get'
""")
rep("""                if ($present -and (Is-PhpRefCell $base.Props[$node.Name])) {
                    $base.Props[$node.Name].Value = Copy-PhpValue $value
""", """                if ($null -ne $declared) {
                    if ([bool]$declared.Readonly) {
                        if ($present) { throw \"ALL PHP: Cannot modify readonly property '$($node.Name)'\" }
                        if ($null -eq $state.ClassContext -or $state.ClassContext -ine $declared.Owner) {
                            throw \"ALL PHP: Cannot initialize readonly property '$($node.Name)' outside its declaring class\"
                        }
                    }
                    $value=Convert-PhpTypedValue $value ([string]$declared.TypeName) ('property ' + $node.Name)
                } elseif ($base.Class -ne 'stdClass' -and $state.Classes[$base.Class].Readonly) {
                    throw 'ALL PHP: Cannot create dynamic property on readonly class'
                }
                if ($present -and (Is-PhpRefCell $base.Props[$node.Name])) {
                    $base.Props[$node.Name].Value = Copy-PhpValue $value
""")
rep("""                                    if (-not $present) {
                                        $issetMethod=Find-OptionalPhpMethod $object.Class '__isset'
""", """                                    if (-not $present) {
                                        $typedProperty=$null
                                        if ($object.Class -ne 'stdClass') {
                                            $typedProperty=Find-PhpProperty $object.Class $arg.Name $false
                                        }
                                        if ($null -ne $typedProperty -and
                                            -not [string]::IsNullOrEmpty([string]$typedProperty.TypeName)) {
                                            if ($node.Name -ceq 'isset') { return $false }
                                            if ($node.Name -ceq 'empty') { return $true }
                                        }
                                        $issetMethod=Find-OptionalPhpMethod $object.Class '__isset'
""")
rep("""                                    [void]$object.Props.Remove($arg.Name)
""", """                                    if ($null -ne $declared -and $declared.Readonly) {
                                        throw \"ALL PHP: Cannot unset readonly property '$($arg.Name)'\"
                                    }
                                    [void]$object.Props.Remove($arg.Name)
""")
rep("""                            if ($prop.Static) { continue }
                            $val=$null
                            if ($null -ne $prop.Default) { $val=Invoke-PhpExpr $prop.Default }
                            $object.Props[$prop.Name]=Copy-PhpValue $val
""", """                            if ($prop.Static) { continue }
                            if ($null -eq $prop.Default -and
                                -not [string]::IsNullOrEmpty([string]$prop.TypeName)) {
                                continue # declared but uninitialized typed property
                            }
                            $val=$null
                            if ($null -ne $prop.Default) { $val=Invoke-PhpExpr $prop.Default }
                            $object.Props[$prop.Name]=Copy-PhpValue (Convert-PhpTypedValue $val ([string]$prop.TypeName) ('property ' + $prop.Name))
""")
rep("""                if ($null -ne $object) { $state.Vars['this'] = $object }
                $returnType=''""", """                if ($null -ne $object) {
                    $state.Vars['this'] = $object
                    if ($definition.Name -ieq '__construct') {
                        foreach ($parameter in $definition.Params) {
                            if (-not $parameter.Promoted) { continue }
                            $target=[pscustomobject]@{
                                Kind='property'
                                Base=[pscustomobject]@{ Kind='variable'; Name='this' }
                                Name=$parameter.Name; NullSafe=$false
                            }
                            Set-LValue $target (Get-PhpVariableValue $parameter.Name) '='
                        }
                    }
                }
                $returnType=''""")
# Do not pretend typed/readonly property references are enforced: reject rather than bypass invariant.
rep("""                    if ($null -ne $declared) {
                        Assert-PhpVisibility $declared.Visibility $declared.Owner
                    }
                }
                $present=if ($object.Props""", """                    if ($null -ne $declared) {
                        Assert-PhpVisibility $declared.Visibility $declared.Owner
                        if ($declared.Readonly -or -not [string]::IsNullOrEmpty([string]$declared.TypeName)) {
                            throw 'ALL PHP: Reference to typed/readonly property requires typed reference tracking'
                        }
                    }
                }
                $present=if ($object.Props""")
# Ensure class readonly on trait merged properties too (in Get-PhpTraitComposition class copy, preserved by property registration)
# A typed static variable can't be referenced without typed reference tracking.
rep("""                Assert-PhpVisibility $prop.Visibility $prop.Owner
                return [pscustomobject]@{
                    Store=$state.Classes[$prop.Owner].StaticValues; Key=$node.Name
                }
""", """                Assert-PhpVisibility $prop.Visibility $prop.Owner
                if (-not [string]::IsNullOrEmpty([string]$prop.TypeName)) {
                    throw 'ALL PHP: Reference to typed static property requires typed reference tracking'
                }
                return [pscustomobject]@{
                    Store=$state.Classes[$prop.Owner].StaticValues; Key=$node.Name
                }
""")
# Explicit defaults on typed properties are compile-time declarations, so a
# numeric-string default is NOT treated like a weak runtime assignment.
rep("""        function Copy-PhpTraitMethod($method, [string]$newName, [string]$visibility) {""", """        function Assert-PhpPropertyDefault($value, [string]$typeName, [string]$propertyName) {
            if ([string]::IsNullOrEmpty($typeName)) { return }
            if ($typeName.StartsWith('?') -and $null -eq $value) { return }
            if ($typeName.StartsWith('?')) { $typeName=$typeName.Substring(1) }
            foreach ($variant in $typeName.Split([char]'|')) {
                $all=$true
                foreach ($part in $variant.Split([char]'&')) {
                    if (-not (Test-PhpTypeAtom $value $part)) { $all=$false; break }
                }
                if ($all) { return }
            }
            throw \"ALL PHP: Type mismatch at property $propertyName (expected $typeName)\"
        }
        function Copy-PhpTraitMethod($method, [string]$newName, [string]$visibility) {""")
rep("""                    $traitMethods=[System.Collections.Generic.HashSet[string]]::new(
                        [System.StringComparer]::OrdinalIgnoreCase)
                    $composition=Get-PhpTraitComposition $node
""", """                    $traitMethods=[System.Collections.Generic.HashSet[string]]::new(
                        [System.StringComparer]::OrdinalIgnoreCase)
                    $composition=Get-PhpTraitComposition $node
""")
rep("""                    $statics=[System.Collections.Generic.Dictionary[string,object]]::new(
                        [System.StringComparer]::Ordinal)
                    foreach ($prop in $effectiveProperties) {
""", """                    foreach ($prop in $effectiveProperties) {
                        if ($null -ne $prop.Default) {
                            $defaultValue=Invoke-PhpExpr $prop.Default
                            Assert-PhpPropertyDefault $defaultValue ([string]$prop.TypeName) $prop.Name
                        }
                    }
                    $statics=[System.Collections.Generic.Dictionary[string,object]]::new(
                        [System.StringComparer]::Ordinal)
                    foreach ($prop in $effectiveProperties) {
""")
# PHP accepts promoted by-reference parameters. As typed-property reference
# constraints are not implemented yet, reject at runtime instead of pretending
# to support it; parser accepts the valid syntax.
rep("""                    if (-not [string]::IsNullOrEmpty($visibility) -and ($byRef -or $variadic)) {
                        throw 'ALL PHP: Promoted property cannot be by-reference or variadic'
                    }
""", """                    if (-not [string]::IsNullOrEmpty($visibility) -and $variadic) {
                        throw 'ALL PHP: Promoted property cannot be variadic'
                    }
""")
rep("""                            Set-LValue $target (Get-PhpVariableValue $parameter.Name) '='
""", """                            if ($parameter.ByRef) {
                                throw 'ALL PHP: Promoted by-reference property needs typed reference tracking'
                            }
                            Set-LValue $target (Get-PhpVariableValue $parameter.Name) '='
""")
# Reject unsupported type names on typed properties rather than executing incorrectly.
rep("""                        $isReadOnly=($isReadonlyProperty -or $isReadonlyClass)
""", """                        if ($propertyType -in @('void','never')) {
                            throw 'ALL PHP: void/never cannot be used as property types'
                        }
                        $isReadOnly=($isReadonlyProperty -or $isReadonlyClass)
""")
rep("""                        if ($method.Name -ieq '__construct') {
                            foreach ($parameter in $method.Params) {
                                if (-not $parameter.Promoted) { continue }
""", """                        if ($method.Name -ieq '__construct') {
                            foreach ($parameter in $method.Params) {
                                if (-not $parameter.Promoted) { continue }
                                if ($isReadonlyClass -and [string]::IsNullOrEmpty($parameter.TypeName)) {
                                    throw 'ALL PHP: readonly class promoted property requires a type'
                                }
""")
# Reject trait-contributed properties that violate readonly class invariants.
rep("""                    foreach ($prop in $effectiveProperties) {
                        if ($null -ne $prop.Default) {
""", """                    foreach ($prop in $effectiveProperties) {
                        if ($node.Readonly -and $prop.Static) {
                            throw 'ALL PHP: readonly static property is not allowed'
                        }
                        if ($node.Readonly -and [string]::IsNullOrEmpty([string]$prop.TypeName)) {
                            throw 'ALL PHP: readonly property requires a type'
                        }
                        if (($node.Readonly -or $prop.Readonly) -and $null -ne $prop.Default) {
                            throw 'ALL PHP: readonly property cannot have a default value'
                        }
                        if ($null -ne $prop.Default) {
""")
# Output
out=Path('/mnt/data/ALL_PHP_v3_11_3areas_work/ALL_PHP_v3_11_adapter.ps1')
out.write_bytes(b'\xef\xbb\xbf'+s.encode('utf-8'))
print('Built',out,'bytes',out.stat().st_size)
