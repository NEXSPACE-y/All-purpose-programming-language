"""Logical PHP reference ownership over the existing eager array/cell model.

Apply after byte values, typed keys, string builtin/offset modules. No native
ownership, CLR refcounts or stock PHP execution is introduced. Logical array
backings survive eager copies until a write separates them. The live graph
counts PHP storage slots, suspended frames and explicitly scoped arguments;
host caches/PS local variables are not guessed to be owners.
"""
import hashlib
import re
from textwrap import dedent, indent

BASE_INPUTS = {
    'offsets04': '257f9b94869f84dfc533eb77db695a08a0a9d86b2168d23f9a3798f8d8da8143',
    'base': '5856687f7abd1471b4af7af9827ca2d17a011e836ad2852bf1d7993298fddc9f',
}

HELPERS = dedent(r'''
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
    # Reference-free arrays can separate without traversing the live graph.
    # Every existing reference-slot writer invalidates this exact absence bit.
    if($array.ReferenceCellsKnownAbsent){$array.ReferenceBacking=[object]::new();return}
    $context=New-PhpReferenceContext @($array)
    $array.ReferenceCellsKnownAbsent=$true
    foreach($key in @($array.Items.Keys)) {
        $entry=$array.Items[$key]
        if(Is-PhpRefCell $entry) {
            if((Get-PhpReferenceOwnerCount $context $entry)-le1){$array.Items[$key]=Copy-PhpValue $entry.Value}
            else{$array.ReferenceCellsKnownAbsent=$false}
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
''').strip() + '\n'


def apply(value: str) -> str:
    newline = '\r\n' if '\r\n' in value else '\n'
    value = value.replace('\r\n', '\n')
    if 'function Separate-PhpReferenceBacking(' in value:
        raise ValueError('Reference ownership module already present')

    def replace(old, new, count=1):
        nonlocal value
        actual = value.count(old)
        if actual != count:
            raise ValueError(f'Reference display anchor count {actual}, expected {count}: {old[:110]!r}')
        value = value.replace(old, new)

    def edit_function(name, edit):
        nonlocal value
        pattern = re.compile(r'^        function '+re.escape(name)+r'(?=[ (]).*?^        }\n', re.M | re.S)
        matches = list(pattern.finditer(value))
        if len(matches) != 1:
            raise ValueError(f'Expected one reference function {name}, found {len(matches)}')
        match = matches[0]
        old = match.group()
        body = edit(old)
        if body == old:
            raise ValueError(f'No reference edit in {name}')
        value = value[:match.start()] + body + value[match.end():]

    def local(old, new, count=1):
        def edit(body):
            found = body.count(old)
            if found != count:
                raise ValueError(f'Reference local anchor count {found}, expected {count}: {old[:100]!r}')
            return body.replace(old, new)
        return edit

    # Metadata belongs to request state and existing array wrappers only.
    replace('        $state = @{\n', '        $state = @{\n                ReferenceOwnerFrames=[Collections.Generic.List[object]]::new()\n                ReferenceTemporaryRoots=[Collections.Generic.List[object]]::new()\n')
    replace('        function New-PhpArray {\n', indent(HELPERS,' '*8)+'        function New-PhpArray {\n')
    edit_function('New-PhpArray', local("                PhpType='array'\n", "                PhpType='array'\n                ReferenceBacking=[object]::new()\n                ReferenceCellsKnownAbsent=$true\n"))
    edit_function('Copy-PhpValue', local('            $copy.NextIndex = $value.NextIndex\n', '            $copy.ReferenceBacking=$value.ReferenceBacking\n            $copy.ReferenceCellsKnownAbsent=$value.ReferenceCellsKnownAbsent\n            $copy.NextIndex = $value.NextIndex\n'))
    edit_function('Set-PhpArrayItem', local("            if (-not (Is-PhpArray $array)) { throw 'ALL PHP: Index assignment requires array' }\n", "            if (-not (Is-PhpArray $array)) { throw 'ALL PHP: Index assignment requires array' }\n            Separate-PhpReferenceBacking $array\n            if(Is-PhpRefCell $value){$array.ReferenceCellsKnownAbsent=$false}\n"))
    def reference_slot(body):
        body=local("                if (-not (Is-PhpArray $array)) { throw 'ALL PHP: Reference index requires array' }\n", "                if (-not (Is-PhpArray $array)) { throw 'ALL PHP: Reference index requires array' }\n                Separate-PhpReferenceBacking $array\n")(body)
        return local('                return [pscustomobject]@{ Store=$array.Items; Key=$key }', '                return [pscustomobject]@{ Store=$array.Items; Key=$key; ReferenceArray=$array }')(body)
    edit_function('Resolve-PhpLValueSlot', reference_slot)
    edit_function('Get-PhpLValueCell', local('            $slot.Store[$slot.Key]=$cell\n', "            $slot.Store[$slot.Key]=$cell\n            if($slot.PSObject.Properties['ReferenceArray']){$slot.ReferenceArray.ReferenceCellsKnownAbsent=$false}\n"))

    # A source reference is an actual temporary owner until its destination is
    # bound. Counting arbitrary PS locals would instead retain dead aliases.
    def scope_function(body, before='', after=''):
        opening = body.index('\n')+1
        return body[:opening] + before + '            try {\n' + body[opening:-10] + '            } finally {\n' + after + '            }\n        }\n'

    edit_function('Set-PhpReferenceTarget', lambda s: scope_function(local('            $slot.Store[$slot.Key]=$cell\n', "            $slot.Store[$slot.Key]=$cell\n            if($slot.PSObject.Properties['ReferenceArray']){$slot.ReferenceArray.ReferenceCellsKnownAbsent=$false}\n")(s),
        '            $referenceTargetRoot=$state.ReferenceTemporaryRoots.Count\n            [void]$state.ReferenceTemporaryRoots.Add($cell)\n',
        '                Remove-PhpReferenceTemporaryRoots $referenceTargetRoot\n'))

    # Argument expressions can trigger later array separation before a callee
    # binds earlier arguments. Register precisely the evaluated PHP arguments.
    def argument_scope(body, collection, end_anchor):
        body = scope_function(body,
            '            $referenceArgumentsRoot=$state.ReferenceTemporaryRoots.Count\n',
            '                Remove-PhpReferenceTemporaryRoots $referenceArgumentsRoot\n')
        if body.count(end_anchor) != 1:
            raise ValueError('Reference argument loop endpoint changed')
        return body.replace(end_anchor, '                Add-PhpReferenceArgumentRoot $value\n'+end_anchor)
    edit_function('Evaluate-PhpUserArguments', lambda s: argument_scope(s, '$args', '            }\n            return ,($args.ToArray())'))
    edit_function('Evaluate-PhpBuiltinArguments', lambda s: argument_scope(s, '$result', '            }\n            return ,($result.ToArray())'))

    # Keep suspended caller storage and active closures reachable; unbind these
    # roots in the existing finally, independently of return/throw/CLI exit.
    def callable(body):
        old = '            $state.Vars = [System.Collections.Generic.Dictionary[string,object]]::new('
        if body.count(old) != 1:
            raise ValueError('Callable variable-frame anchor changed')
        body = body.replace(old,
            "            [void]$state.ReferenceOwnerFrames.Add([pscustomobject]@{Vars=$oldVars;Globals=$oldGlobals;Statics=$oldStatics})\n"
            "            $referenceFrameRoot=$state.ReferenceTemporaryRoots.Count\n"
            "            if($null-ne$closure){[void]$state.ReferenceTemporaryRoots.Add($closure)}\n"
            +old)
        old = '                foreach ($param in $definition.Params) {\n                    if ($param.Variadic) {'
        if body.count(old) != 1:
            raise ValueError('Callable argument binding anchor changed')
        body = body.replace(old,
            '                $referenceBindingRoot=$state.ReferenceTemporaryRoots.Count\n'
            '                foreach($referenceArgument in $callArgs){Add-PhpReferenceArgumentRoot $referenceArgument}\n'+old)
        old = '                # Enforce declared parameter types after resolving named/default/variadic'
        if body.count(old) != 1:
            raise ValueError('Callable argument binding endpoint changed')
        body = body.replace(old, '                Remove-PhpReferenceTemporaryRoots $referenceBindingRoot\n'+old)
        old = '                            else { $argsArray.Items[$key]=$checked }'
        if body.count(old) != 1:
            raise ValueError('Typed variadic direct array write changed')
        body = body.replace(old, '                            else { Separate-PhpReferenceBacking $argsArray;$argsArray.Items[$key]=$checked }')
        old = '            } finally {\n                $state.CallDepth--'
        if body.count(old) != 1:
            raise ValueError('Callable frame finally changed')
        return body.replace(old,
            '            } finally {\n'
            '                Remove-PhpReferenceTemporaryRoots $referenceFrameRoot\n'
            '                $state.ReferenceOwnerFrames.RemoveAt($state.ReferenceOwnerFrames.Count-1)\n'
            '                $state.CallDepth--')
    edit_function('Invoke-PhpCallable', callable)

    # Existing array mutations that bypass Set-PhpArrayItem.
    edit_function('Invoke-PhpExpr', local(
        '                                if ($array.Items.Contains($key)) { $array.Items.Remove($key) }',
        '                                if ($array.Items.Contains($key)) { Separate-PhpReferenceBacking $array;$array.Items.Remove($key) }'))
    def foreach_scope(body):
        old = '                    $walk=$arr\n                    if (-not $node.ByReference) { $walk=Copy-PhpValue $arr }'
        if body.count(old) != 1:
            raise ValueError('Foreach reference setup changed')
        body = body.replace(old,
            '                    $walk=$arr\n'
            '                    if (-not $node.ByReference) { $walk=Copy-PhpValue $arr }\n'
            '                    else { Separate-PhpReferenceBacking $walk;$walk.ReferenceCellsKnownAbsent=$false }\n'
            '                    $referenceWalkRoot=$state.ReferenceTemporaryRoots.Count\n'
            '                    [void]$state.ReferenceTemporaryRoots.Add($walk)')
        old = '                    } finally { $state.Flow.LoopDepth-- }\n                    return\n                }\n            }\n            throw'
        if body.count(old) != 1:
            raise ValueError('Foreach reference lifetime endpoint changed')
        return body.replace(old, '                    } finally { Remove-PhpReferenceTemporaryRoots $referenceWalkRoot;$state.Flow.LoopDepth-- }\n                    return\n                }\n            }\n            throw')
    edit_function('Invoke-PhpStatement', foreach_scope)

    def builtin_mutations(body):
        for name in ['array_pop','array_shift','array_unshift']:
            pattern = re.compile(r"^                '"+name+r"' \{.*?^                }", re.M | re.S)
            matches=list(pattern.finditer(body))
            if len(matches)!=1:
                raise ValueError('Array mutator arm changed: '+name)
            arm=matches[0].group()
            old='                    $arr = $callArgs[0]\n'
            if arm.count(old)!=1:
                raise ValueError('Array mutator receiver changed: '+name)
            arm=arm.replace(old,old+'                    Separate-PhpReferenceBacking $arr\n')
            old='                    $arr.Items = $replacement.Items\n'
            if name!='array_pop':
                if arm.count(old)!=1:
                    raise ValueError('Array mutator replacement changed: '+name)
                arm=arm.replace(old,old+'                    $arr.ReferenceBacking=$replacement.ReferenceBacking\n                    $arr.ReferenceCellsKnownAbsent=$replacement.ReferenceCellsKnownAbsent\n')
            match=matches[0];body=body[:match.start()]+arm+body[match.end():]
        old="                    foreach ($item in $callArgs) { Write-PhpBytes (Format-PhpBytesDump $item '') }"
        if body.count(old)!=1:
            raise ValueError('Raw byte var_dump dispatch changed')
        return body.replace(old,
            '                    $referenceDumpContext=New-PhpReferenceContext $callArgs\n'
            "                    foreach ($item in $callArgs) { Write-PhpBytes (Format-PhpBytesDump $item '' $referenceDumpContext) }")
    edit_function('Invoke-PhpFunction', builtin_mutations)

    def dump(body):
        old='        function Format-PhpBytesDump($value, [string]$pad) {'
        if body.count(old)!=1:
            raise ValueError('Byte dump function signature changed')
        body=body.replace(old,'        function Format-PhpBytesDump($value, [string]$pad, $referenceContext=$null) {')
        old='            if (Is-PhpRefCell $value) { $value=$value.Value }'
        if body.count(old)!=1:
            raise ValueError('Byte dump reference prefix anchor changed')
        body=body.replace(old,
            "            $referenceMark=''\n"
            '            if (Is-PhpRefCell $value) {\n'
            "                if($pad.Length-gt0 -and $null-ne$referenceContext -and (Get-PhpReferenceOwnerCount $referenceContext $value)-gt1){$referenceMark='&'}\n"
            '                $value=$value.Value\n'
            '            }')
        for old,new in [
            ("$pad+\"NULL`n\"", "$pad+$referenceMark+\"NULL`n\""),
            ("$pad+'bool('", "$pad+$referenceMark+'bool('"),
            ("$pad+'int('", "$pad+$referenceMark+'int('"),
            ("$pad+'float('", "$pad+$referenceMark+'float('"),
            ("$pad+'string('", "$pad+$referenceMark+'string('"),
            ("$pad+'array('", "$pad+$referenceMark+'array('"),
            ("$pad+'enum('", "$pad+$referenceMark+'enum('"),
            ("$pad+'object('", "$pad+$referenceMark+'object('"),
            ("Format-PhpBytesDump $value.Items[$key] ($pad+'  ')", "Format-PhpBytesDump $value.Items[$key] ($pad+'  ') $referenceContext"),
            ("Format-PhpBytesDump $entry.Value ($pad+'  ')", "Format-PhpBytesDump $entry.Value ($pad+'  ') $referenceContext"),
        ]:
            if body.count(old)!=1:
                raise ValueError('Byte dump local anchor changed: '+old)
            body=body.replace(old,new)
        old='            if (Is-PhpArray $value) {\n'
        if body.count(old)!=1:
            raise ValueError('Byte dump array path changed')
        body=body.replace(old,
            '            if (Is-PhpArray $value) {\n'
            '                if($null-eq$referenceContext){$referenceContext=New-PhpReferenceContext @($value)}\n'
            '                foreach($backing in $referenceContext.DumpArrays){\n'
            '                    if([object]::ReferenceEquals($backing,$value.ReferenceBacking)){$builder.AppendUtf8($pad+"*RECURSION*`n");return $builder.ToPhpBytes()}\n'
            '                }\n'
            '                [void]$referenceContext.DumpArrays.Add($value.ReferenceBacking)\n'
            '                try {\n')
        old='                $builder.AppendUtf8($pad+"}`n");return $builder.ToPhpBytes()\n            }\n            if (Is-PhpObject $value) {'
        if body.count(old)!=1:
            raise ValueError('Byte dump array lifetime endpoint changed')
        body=body.replace(old,
            '                $builder.AppendUtf8($pad+"}`n");return $builder.ToPhpBytes()\n'
            '                } finally {$referenceContext.DumpArrays.RemoveAt($referenceContext.DumpArrays.Count-1)}\n'
            '            }\n            if (Is-PhpObject $value) {')
        return body
    edit_function('Format-PhpBytesDump', dump)
    return value.replace('\n',newline)
