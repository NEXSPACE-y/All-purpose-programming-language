"""PHP8.5 signed next-index history and saturated 64-bit append allocation.

Apply after typed keys and reference separation. New arrays use PHP_INT_MIN as
the no-integer-history sentinel; append maps only that sentinel to zero. Real
negative integer writes advance signed history. MAX remains saturated, with a
real occupied-key error instead of overflowing to double or wrapping a key.
Existing byte fixtures and reference/NextIndex copies stay unchanged.
"""
HELPERS=r'''        function Update-PhpNextIndex($array, [long]$integerKey) {
            if($integerKey-ge$array.NextIndex){
                if($integerKey-eq[long]::MaxValue){$array.NextIndex=[long]::MaxValue}
                else{$array.NextIndex=[long]($integerKey+1)}
            }
        }
        function Allocate-PhpAppendKey($array) {
            $index=[long]$array.NextIndex
            if($index-eq[long]::MinValue){$index=[long]0}
            $key=New-PhpIntegerKey $index
            if($array.Items.Contains($key)){
                Throw-PhpError 'Error' 'Cannot add element to the array as the next element is already occupied'
            }
            Update-PhpNextIndex $array $index
            return $key
        }
'''


def apply(value: str) -> str:
    newline='\r\n' if '\r\n' in value else '\n'
    value=value.replace('\r\n','\n')

    def replace(old,new,count=1):
        nonlocal value
        actual=value.count(old)
        if actual!=count:raise ValueError(f'ArrayIndexEdits expected {count}, found {actual}: {old[:80]!r}')
        value=value.replace(old,new)

    replace('        function New-PhpArray {\n',HELPERS+'        function New-PhpArray {\n')
    replace('                NextIndex=[long]0','                NextIndex=[long]::MinValue')
    replace('''                    $key=New-PhpIntegerKey $array.NextIndex
                    $array.NextIndex++''','''                    $key=Allocate-PhpAppendKey $array''')
    replace('if ($numeric -ge $array.NextIndex) { $array.NextIndex=$numeric+1 }','Update-PhpNextIndex $array $numeric')
    replace('''                $keyString = New-PhpIntegerKey $array.NextIndex
                $array.NextIndex++''','''                $keyString = Allocate-PhpAppendKey $array''')
    replace('if ($intKey -ge $array.NextIndex) { $array.NextIndex = $intKey + 1 }','Update-PhpNextIndex $array $intKey')
    replace('''                    # PHP resets the next free index after array_pop().
                    $high = [long]-1
                    foreach ($k in $arr.Items.Keys) {
                        if ($k.IsInteger) {
                            $number = [long]$k.IntegerValue
                            if ($number -gt $high) { $high = $number }
                        }
                    }
                    $arr.NextIndex = $high + 1''','''                    # Pop retreats only when the removed integer was exactly
                    # next-1. String keys and holes retain prior signed history.
                    if($lastKey.IsInteger-and$arr.NextIndex-ne[long]::MinValue-and
                        $lastKey.IntegerValue-eq($arr.NextIndex-1)){
                        $arr.NextIndex=[long]$lastKey.IntegerValue
                    }''')
    replace('''                    $arr.NextIndex = $replacement.NextIndex
                    if (Is-PhpRefCell $firstValue)''','''                    # array_shift reindexes numerics and resets empty/string-
                    # only next-index history to zero as well.
                    $arr.NextIndex = [long][Math]::Max([long]0,[long]$replacement.NextIndex)
                    if (Is-PhpRefCell $firstValue)''')
    return value.replace('\n',newline)
