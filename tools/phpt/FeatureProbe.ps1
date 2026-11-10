param([string]$AdapterPath)
$adapter = & $AdapterPath
$run = $adapter.Run
$cases = [ordered]@{
    'try/catch'            = '<?php try { throw new Exception("x"); } catch (Exception $e) { echo "c"; }'
    'try/finally'          = '<?php try { echo "a"; } finally { echo "f"; }'
    'namespace'            = '<?php namespace Foo; echo "n";'
    'declare strict'       = '<?php declare(strict_types=1); echo "d";'
    'close tag + html'     = "<?php echo 'a'; ?>`nDone"
    'var_dump'             = '<?php var_dump(1);'
    'print_r'              = '<?php print_r([1]);'
    'echo const'           = '<?php echo PHP_EOL;'
    'const stmt'           = '<?php const A = 1; echo A;'
    'define'               = '<?php define("A", 1); echo A;'
    'switch'               = '<?php switch (1) { case 1: echo "s"; break; }'
    'match'                = '<?php echo match(1) { 1 => "m" };'
    'do while'             = '<?php $i=0; do { $i++; } while ($i<2); echo $i;'
    'for'                  = '<?php for ($i=0;$i<2;$i++) { echo $i; }'
    'list destructure'     = '<?php [$a,$b]=[1,2]; echo $a,$b;'
    'heredoc'              = "<?php echo <<<EOT`nhi`nEOT;`n"
    'static call'          = '<?php class A { static function f(){ return 1; } } echo A::f();'
    'class const'          = '<?php class A { const X=1; } echo A::X;'
    'closure'              = '<?php $f=function($x){return $x+1;}; echo $f(1);'
    'arrow fn'             = '<?php $f=fn($x)=>$x+1; echo $f(1);'
    'attribute'            = '<?php #[Attr] class A {} echo "a";'
    'line comment #'       = "<?php # c`necho 'h';"
    'fq name'              = '<?php echo \strlen("ab");'
    'error suppress @'     = '<?php echo @$x; echo "e";'
    'int cast'             = '<?php echo (int)"5";'
    'instanceof'           = '<?php class A {} echo (new A) instanceof A ? "y":"n";'
    'null coalesce'        = '<?php echo $x ?? "d";'
    'spread'               = '<?php function f(...$a){return count($a);} echo f(...[1,2]);'
    'global'               = '<?php $g=1; function f(){ global $g; return $g; } echo f();'
    'static var'           = '<?php function f(){ static $n=0; return ++$n; } f(); echo f();'
    'generator'            = '<?php function g(){ yield 1; yield 2; } foreach (g() as $v) echo $v;'
    'enum'                 = '<?php enum E { case A; } echo E::A->name;'
    'interface const'      = '<?php interface I { const X=1; } echo I::X;'
    'exit'                 = '<?php echo "a"; exit; echo "b";'
    'printf'               = '<?php printf("%d", 3);'
    'string fn'            = '<?php echo strlen("abc"), strtoupper("a"), implode(",", [1,2]);'
    'hex escape'           = '<?php echo "\x41";'
    'goto'                 = '<?php goto a; echo "x"; a: echo "g";'
    'new anon class'       = '<?php $o = new class { public $p = 1; }; echo $o->p;'
    'nullsafe'             = '<?php $o=null; echo $o?->x ?? "n";'
    'first-class callable' = '<?php $f = strlen(...); echo $f("ab");'
    'backtick-free $GLOBALS' = '<?php $a=1; echo $GLOBALS["a"];'
    'include'              = '<?php echo __LINE__, __FILE__ === "" ? "" : "f";'
    'float echo'           = '<?php echo 0.1+0.2, " ", 1e100, " ", 7/2, " ", PHP_INT_MAX + 1;'
    'int overflow'         = '<?php echo 9223372036854775807 + 1;'
    'int div'              = '<?php echo intdiv(7,2), 7 % 3, 2 ** 10, 2 ** 0.5;'
}
foreach ($k in $cases.Keys) {
    $w = New-Object System.IO.StringWriter
    $saved = [Console]::Out
    $err = $null
    try { [Console]::SetOut($w); $null = @(& $run -Code $cases[$k]) } catch { $err = $_.Exception.Message } finally { [Console]::SetOut($saved) }
    $o = $w.ToString() -replace "`r?`n", '\n'
    if ($err) { '{0,-24} ERROR  {1}' -f $k, $err } else { '{0,-24} ok     {1}' -f $k, $o }
}
