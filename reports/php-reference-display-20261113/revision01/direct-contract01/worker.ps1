Add-Type -Path 'C:\Users\rinpa\ALL-php-compat-20261112\tools\candidates\php-byte-runtime\out\runtime01\AllPhp.ByteValues.Runtime.dll'

$ErrorActionPreference='Stop'
function To-PhpBytes($value){if($value-is[AllPhp.ByteValues.PhpBytes]){return $value};return [AllPhp.ByteValues.PhpBytes]::FromUtf8([string]$value)}
function Reset-ReferenceState {
 $script:state=@{Vars=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal);Globals=$null;FunctionStatics=@{};Classes=@{};GlobalBindings=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);StaticBindings=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);ReferenceOwnerFrames=[Collections.Generic.List[object]]::new();ReferenceTemporaryRoots=[Collections.Generic.List[object]]::new();DumpStack=[Collections.Generic.List[object]]::new()};$script:state.Globals=$script:state.Vars
}
function Cell {return [pscustomobject]@{PhpType='refcell';Value=[AllPhp.ByteValues.PhpBytes]::FromBytes([byte[]]@(255,0))}}
function Put($array,[long]$key,$value){$array.Items[[AllPhp.ByteValues.PhpKey]::FromInteger($key)]=$value}
function Render($id,$values){$context=New-PhpReferenceContext $values;$stream=[IO.MemoryStream]::new();foreach($value in $values){(Format-PhpBytesDump $value '' $context).WriteTo($stream)};[pscustomobject]@{id=$id;output_base64=[Convert]::ToBase64String($stream.ToArray());counts=@($context.Counts)}|ConvertTo-Json -Compress -Depth 6}
function Add-PhpReferenceIdentity($list, $value) {
    foreach($seen in $list){if([object]::ReferenceEquals($seen,$value)){return $false}}
    [void]$list.Add($value);return $true
}
function Add-PhpReferenceStore($context, $store, $globals=$null, $statics=$null) {
    if($null-eq$store -or -not(Add-PhpReferenceIdentity $context.Stores $store)){return}
    foreach($key in $store.Keys) {
        if($null-ne$globals -and $globals.Contains($key)){continue}
        if($null-ne$statics -and $statics.Contains($key)){continue}
        $context.Pending.Push($store[$key])
    }
}
function Get-PhpReferenceOwnerCount($context, $cell) {
    for($i=0;$i-lt$context.Cells.Count;$i++) {
        if([object]::ReferenceEquals($context.Cells[$i],$cell)){return [long]$context.Counts[$i]}
    }
    return [long]0
}
function New-PhpReferenceContext($additionalRoots) {
    $context=[pscustomobject]@{
        Cells=[Collections.Generic.List[object]]::new()
        Counts=[Collections.Generic.List[long]]::new()
        ExpandedCells=[Collections.Generic.List[object]]::new()
        Arrays=[Collections.Generic.List[object]]::new()
        Objects=[Collections.Generic.List[object]]::new()
        Stores=[Collections.Generic.List[object]]::new()
        Pending=[Collections.Generic.Stack[object]]::new()
        DumpArrays=[Collections.Generic.List[object]]::new()
    }
    Add-PhpReferenceStore $context $state.Globals
    Add-PhpReferenceStore $context $state.FunctionStatics
    Add-PhpReferenceStore $context $state.Vars $state.GlobalBindings $state.StaticBindings
    foreach($frame in $state.ReferenceOwnerFrames) {
        Add-PhpReferenceStore $context $frame.Vars $frame.Globals $frame.Statics
    }
    foreach($definition in $state.Classes.Values) {
        if($definition.PSObject.Properties['StaticValues']){Add-PhpReferenceStore $context $definition.StaticValues}
    }
    foreach($root in $state.ReferenceTemporaryRoots){$context.Pending.Push($root)}
    foreach($root in $additionalRoots){$context.Pending.Push($root)}
    while($context.Pending.Count-gt0) {
        $value=$context.Pending.Pop()
        if($null-eq$value){continue}
        if(Is-PhpRefCell $value) {
            $found=$false
            for($i=0;$i-lt$context.Cells.Count;$i++) {
                if([object]::ReferenceEquals($context.Cells[$i],$value)){$context.Counts[$i]++;$found=$true;break}
            }
            if(-not$found){[void]$context.Cells.Add($value);[void]$context.Counts.Add([long]1)}
            if(Add-PhpReferenceIdentity $context.ExpandedCells $value){$context.Pending.Push($value.Value)}
            continue
        }
        if(Is-PhpArray $value) {
            if(-not$value.PSObject.Properties['ReferenceBacking']){throw 'ALL PHP: missing logical array backing metadata'}
            if(Add-PhpReferenceIdentity $context.Arrays $value.ReferenceBacking) {
                foreach($key in $value.Items.Keys){$context.Pending.Push($value.Items[$key])}
            }
            continue
        }
        if(Is-PhpObject $value) {
            if(Add-PhpReferenceIdentity $context.Objects $value){Add-PhpReferenceStore $context $value.Props}
            continue
        }
        if($value.PSObject.Properties['PhpType'] -and $value.PhpType-ceq'closure') {
            if(Add-PhpReferenceIdentity $context.Objects $value){Add-PhpReferenceStore $context $value.Captures}
        }
    }
    return $context
}
function Separate-PhpReferenceBacking($array) {
    if(-not(Is-PhpArray $array)){throw 'ALL PHP: logical backing separation requires array'}
    $context=New-PhpReferenceContext @($array)
    foreach($key in @($array.Items.Keys)) {
        $entry=$array.Items[$key]
        if((Is-PhpRefCell $entry) -and (Get-PhpReferenceOwnerCount $context $entry)-le1) {
            $array.Items[$key]=Copy-PhpValue $entry.Value
        }
    }
    $array.ReferenceBacking=[object]::new()
}
function Add-PhpReferenceArgumentRoot($value) {
    if($null-ne$value -and $value.PSObject.Properties['PhpType']) {
        if($value.PhpType-ceq'named_argument'){Add-PhpReferenceArgumentRoot $value.Value;return}
        if($value.PhpType-ceq'refargument'){[void]$state.ReferenceTemporaryRoots.Add($value.Cell);return}
    }
    [void]$state.ReferenceTemporaryRoots.Add($value)
}
function Remove-PhpReferenceTemporaryRoots([int]$start) {
    if($start-lt0 -or $start-gt$state.ReferenceTemporaryRoots.Count){throw 'ALL PHP: reference temporary lifetime mismatch'}
    if($state.ReferenceTemporaryRoots.Count-gt$start){$state.ReferenceTemporaryRoots.RemoveRange($start,$state.ReferenceTemporaryRoots.Count-$start)}
}
        function New-PhpArray {
            return [pscustomobject]@{
                PhpType='array'
                ReferenceBacking=[object]::new()
                Items=[System.Collections.Specialized.OrderedDictionary]::new()
                NextIndex=[long]0
            }
        }

        function Copy-PhpValue($value, [int]$depth = 0) {
            if (-not (Is-PhpArray $value)) { return (ConvertTo-PhpOwnedValue $value) }
            if ($depth -ge 64) {
                throw 'ALL PHP: Array nesting exceeds supported copy depth (64)'
            }
            $copy = New-PhpArray
            # Clone directly to preserve insertion order and NextIndex. Do not
            # call Set-PhpArrayItem, which also copies incoming array values.
            foreach ($key in $value.Items.Keys) {
                $copy.Items[$key] = Copy-PhpValue $value.Items[$key] ($depth + 1)
            }
            $copy.ReferenceBacking=$value.ReferenceBacking
            $copy.NextIndex = $value.NextIndex
            return $copy
        }

        function Is-PhpArray($value) {
            return ($null -ne $value -and $value.PSObject.Properties['PhpType'] -and
                $value.PhpType -ceq 'array')
        }

        function Is-PhpObject($value) {
            return ($null -ne $value -and $value.PSObject.Properties['PhpType'] -and
                $value.PhpType -ceq 'object')
        }

        function Is-PhpRefCell($value) {
            return ($null -ne $value -and $value.PSObject.Properties['PhpType'] -and
                $value.PhpType -ceq 'refcell')
        }

        function ConvertTo-PhpOwnedValue($value) {
            if ($value -is [string]) { return [AllPhp.ByteValues.PhpBytes]::FromUtf8($value) }
            return $value
        }

        function Is-PhpStringValue($value) {
            if (Is-PhpRefCell $value) { $value=$value.Value }
            # Legacy text from an existing builtin is normalized on value entry.
            # This bridge is temporary and is not a claim all text producers moved.
            return ($value -is [AllPhp.ByteValues.PhpBytes] -or $value -is [string])
        }

        function Format-PhpBytesDump($value, [string]$pad, $referenceContext=$null) {
            $builder=[AllPhp.ByteValues.PhpByteBuilder]::new()
            $referenceMark=''
            if (Is-PhpRefCell $value) {
                if($pad.Length-gt0 -and $null-ne$referenceContext -and (Get-PhpReferenceOwnerCount $referenceContext $value)-gt1){$referenceMark='&'}
                $value=$value.Value
            }
            if ($null -eq $value) { $builder.AppendUtf8($pad+$referenceMark+"NULL`n");return $builder.ToPhpBytes() }
            if ($value -is [bool]) {
                $text=if($value){'true'}else{'false'}
                $builder.AppendUtf8($pad+$referenceMark+'bool('+$text+")`n");return $builder.ToPhpBytes()
            }
            if ($value -is [long]) {
                $builder.AppendUtf8($pad+$referenceMark+'int('+$value.ToString([Globalization.CultureInfo]::InvariantCulture)+")`n")
                return $builder.ToPhpBytes()
            }
            if ($value -is [double]) {
                $builder.AppendUtf8($pad+$referenceMark+'float('+(Format-PhpFloat $value 0)+")`n");return $builder.ToPhpBytes()
            }
            if (Is-PhpStringValue $value) {
                $bytes=To-PhpBytes $value
                $builder.AppendUtf8($pad+$referenceMark+'string('+$bytes.Length+') "');$builder.Append($bytes)
                $builder.AppendUtf8("`"`n");return $builder.ToPhpBytes()
            }
            if (Is-PhpArray $value) {
                if($null-eq$referenceContext){$referenceContext=New-PhpReferenceContext @($value)}
                foreach($backing in $referenceContext.DumpArrays){
                    if([object]::ReferenceEquals($backing,$value.ReferenceBacking)){$builder.AppendUtf8($pad+"*RECURSION*`n");return $builder.ToPhpBytes()}
                }
                [void]$referenceContext.DumpArrays.Add($value.ReferenceBacking)
                try {
                $builder.AppendUtf8($pad+$referenceMark+'array('+$value.Items.Count+") {`n")
                foreach($key in $value.Items.Keys) {
                    if($key.IsInteger){$builder.AppendUtf8($pad+'  ['+$key.IntegerValue+"]=>`n")}
                    else{$builder.AppendUtf8($pad+'  ["');$builder.Append($key.BytesValue);$builder.AppendUtf8("`"]=>`n")}
                    $builder.Append((Format-PhpBytesDump $value.Items[$key] ($pad+'  ') $referenceContext))
                }
                $builder.AppendUtf8($pad+"}`n");return $builder.ToPhpBytes()
                } finally {$referenceContext.DumpArrays.RemoveAt($referenceContext.DumpArrays.Count-1)}
            }
            if (Is-PhpObject $value) {
                if ($state.Classes.ContainsKey($value.Class) -and
                    $state.Classes[$value.Class].PSObject.Properties['Enum'] -and
                    $state.Classes[$value.Class].Enum) {
                    $builder.AppendUtf8($pad+$referenceMark+'enum('+$value.Class+'::')
                    $builder.Append((To-PhpBytes $value.Props['name']))
                    $builder.AppendUtf8(")`n");return $builder.ToPhpBytes()
                }
                foreach($seen in $state.DumpStack) {
                    if([object]::ReferenceEquals($seen,$value)) {
                        $builder.AppendUtf8($pad+"*RECURSION*`n");return $builder.ToPhpBytes()
                    }
                }
                [void]$state.DumpStack.Add($value)
                try {
                    $entries=Get-PhpObjectDumpEntries $value
                    $count=0
                    foreach($entry in $entries){if($entry.Present){$count++}}
                    $id=0
                    if($value.PSObject.Properties['Id']){$id=$value.Id}
                    $builder.AppendUtf8($pad+$referenceMark+'object('+$value.Class+')#'+$id+' ('+$count+") {`n")
                    foreach($entry in $entries) {
                        $builder.AppendUtf8($pad+'  ["'+$entry.Name+'"'+$entry.Suffix+"]=>`n")
                        if($entry.Present){$builder.Append((Format-PhpBytesDump $entry.Value ($pad+'  ') $referenceContext))}
                        else{$builder.AppendUtf8($pad+'  uninitialized('+$entry.TypeName+")`n")}
                    }
                    $builder.AppendUtf8($pad+"}`n");return $builder.ToPhpBytes()
                } finally {$state.DumpStack.RemoveAt($state.DumpStack.Count-1)}
            }
            throw 'ALL PHP: var_dump() of this value type is not implemented'
        }

Reset-ReferenceState;$v=Cell;$state.Vars['v']=$v;$a=New-PhpArray;Put $a 0 $v;$state.Vars['a']=$a;Render 'array_external_alias' @($a)
[void]$state.Vars.Remove('v');Render 'array_single_cell_after_unset' @($a)
Reset-ReferenceState;$v=Cell;$state.Vars['v']=$v;$a=New-PhpArray;Put $a 0 $v;$state.Vars['a']=$a;$b=Copy-PhpValue $a;$state.Vars['b']=$b;Render 'array_cell_copy_alias_alive' @($a,$b);[void]$state.Vars.Remove('v');Render 'array_cell_copy_then_alias_unset' @($a,$b)
Reset-ReferenceState;$v=Cell;$state.Vars['v']=$v;$a=New-PhpArray;Put $a 0 $v;$state.Vars['a']=$a;$b=Copy-PhpValue $a;$state.Vars['b']=$b;Separate-PhpReferenceBacking $b;Put $b 1 ([long]1);[void]$state.Vars.Remove('v');Render 'array_cow_before_unset' @($a,$b)
Reset-ReferenceState;$v=Cell;$state.Vars['v']=$v;$a=New-PhpArray;Put $a 0 $v;$state.Vars['a']=$a;$b=Copy-PhpValue $a;$state.Vars['b']=$b;[void]$state.Vars.Remove('v');Separate-PhpReferenceBacking $b;Put $b 1 ([long]1);Render 'array_cow_after_unset' @($a,$b)
Reset-ReferenceState;$v=Cell;$state.Vars['v']=$v;$a=New-PhpArray;Put $a 0 $v;$state.Vars['a']=$a;[void]$state.Vars.Remove('v');$b=Copy-PhpValue $a;$state.Vars['b']=$b;Separate-PhpReferenceBacking $a;Put $a 0 ([AllPhp.ByteValues.PhpBytes]::FromUtf8('x'));Render 'array_single_copy_write' @($a,$b)
Reset-ReferenceState;$v=Cell;$a=New-PhpArray;Put $a 0 $v;Put $a 1 $v;$state.Vars['a']=$a;Render 'array_two_slots' @($a);Separate-PhpReferenceBacking $a;$a.Items.Remove([AllPhp.ByteValues.PhpKey]::FromInteger(1));Render 'array_two_slots_one_unset' @($a)
Reset-ReferenceState;$v=Cell;$a=New-PhpArray;Put $a 0 $v;$state.Vars['a']=$a;$outer=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal);$outer['v']=$v;[void]$state.ReferenceOwnerFrames.Add([pscustomobject]@{Vars=$outer;Globals=$null;Statics=$null});Render 'function_suspended_outer_local' @($a)
Reset-ReferenceState;$v=Cell;$a=New-PhpArray;Put $a 0 $v;$state.Vars['a']=$a;$state.Vars['f']=[pscustomobject]@{PhpType='closure';Captures=@{v=$v}};Render 'closure_capture_reference_live' @($a);[void]$state.Vars.Remove('f');Render 'closure_capture_reference_unset' @($a)
Reset-ReferenceState;$a=New-PhpArray;$v=[pscustomobject]@{PhpType='refcell';Value=$a};Put $a 0 $v;$state.Vars['a']=$v;Render 'reference_array_self' @($a)
