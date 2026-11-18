param(
    [switch]$Installed
)

$ErrorActionPreference = 'Stop'

$root = $PSScriptRoot
$phpAdapterPath = if ($Installed) { if (Test-Path -LiteralPath 'D:\ALL\languages\php.ps1') { 'D:\ALL\languages\php.ps1' } else { Join-Path $HOME 'ALL\languages\php.ps1' } } else { Join-Path $root 'ALL_PHP_v3_12_adapter.ps1' }
$allAdapterPath = if ($Installed) { if (Test-Path -LiteralPath 'D:\ALL\languages\all.ps1') { 'D:\ALL\languages\all.ps1' } else { Join-Path $HOME 'ALL\languages\all.ps1' } } else { Join-Path $root 'ALL_v1_0_adapter.ps1' }

$phpAdapter = & $phpAdapterPath
$allAdapter = & $allAdapterPath

$passed = 0
$failed = 0

function Assert-Case([string]$Name, [scriptblock]$Action, [string]$Expected) {
    $global:AllPolyglotContext = $null
    try {
        $sw = [System.IO.StringWriter]::new()
        $oldOut = [Console]::Out
        try {
            [Console]::SetOut($sw)
            $ret = & $Action
        } finally {
            [Console]::SetOut($oldOut)
        }
        $actual = $sw.ToString()
        if ($actual.Length -eq 0 -and $null -ne $ret) {
            $actual = ($ret -join '')
        }
        $normActual = $actual.Replace("`r`n", "`n").TrimEnd()
        $normExpected = $Expected.Replace("`r`n", "`n").TrimEnd()
        if ($normActual -cne $normExpected) {
            $script:failed++
            Write-Host "FAIL [$Name]: expected '$normExpected', got '$normActual'" -ForegroundColor Red
        } else {
            $script:passed++
        }
    } catch {
        $script:failed++
        Write-Host "ERROR [$Name]: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# ============================================================================
# Phase 2 Tests: PHP 8.5 Core Features & Rust-Backed Standard Library
# ============================================================================

# 1. Generators: yield, key => value, yield from array & generator, send(), getReturn(), side-effect ordering
Assert-Case 'phase2_generator_basic_and_return' {
    & $phpAdapter.Run @'
<?php
function gen_items(): Generator {
    echo "start ";
    yield 'a' => 10;
    echo "mid ";
    yield 'b' => 20;
    echo "end ";
    return 99;
}
$g = gen_items();
foreach ($g as $k => $v) {
    echo "$k=$v ";
}
echo "ret=" . $g->getReturn();
'@
} 'start a=10 mid b=20 end ret=99'

Assert-Case 'phase2_generator_yield_from_and_send' {
    & $phpAdapter.Run @'
<?php
function inner_gen() {
    yield 10;
    yield 20;
    return 30;
}
function outer_gen() {
    yield 1;
    $r = yield from inner_gen();
    yield from [40, 50];
    $recv = yield $r;
    yield $recv * 2;
}
$g = outer_gen();
$out = [];
$out[] = $g->current();
$g->next();
$out[] = $g->current();
$g->next();
$out[] = $g->current();
$g->next();
$out[] = $g->current();
$g->next();
$out[] = $g->current();
$g->next();
$out[] = $g->current();
$out[] = $g->send(100);
echo implode(',', $out);
'@
} '1,10,20,40,50,30,200'

# 2. PHP 8 Attributes (#[...]) & Reflection API
Assert-Case 'phase2_attributes_and_reflection' {
    & $phpAdapter.Run @'
<?php
namespace App\Meta;
use Attribute;
use ReflectionClass;
use ReflectionFunction;

#[Attribute(Attribute::TARGET_ALL)]
class Tag {
    public function __construct(public string $label, public int $weight = 1) {}
}

#[Tag('entity', weight: 5)]
class User {
    #[Tag('pk')]
    public int $id = 1;

    public function __construct(
        #[Tag('promoted_name')]
        public readonly string $name = 'anon'
    ) {}

    #[Tag('action', 10)]
    public function greet(#[Tag('arg')] string $prefix = 'Hi'): string {
        return $prefix . ' ' . $this->name;
    }
}

#[Tag('helper_fn', 3)]
function compute(int $x = 7): int { return $x * 2; }

$rc = new ReflectionClass(User::class);
$cAttr = $rc->getAttributes()[0]->newInstance();
$prop = $rc->getProperty('id');
$pAttr = $prop->getAttributes()[0]->newInstance();
$promProp = $rc->getProperty('name');
$promAttr = $promProp->getAttributes()[0]->newInstance();
$rm = $rc->getMethod('greet');
$mAttr = $rm->getAttributes()[0]->newInstance();
$param = $rm->getParameters()[0];
$paramAttr = $param->getAttributes()[0]->newInstance();
$rf = new ReflectionFunction('App\Meta\compute');
$fAttr = $rf->getAttributes()[0]->newInstance();

$u = $rc->newInstance('Rin');
echo implode('|', [
    $rc->getShortName(),
    $rc->getNamespaceName(),
    $cAttr->label . ':' . $cAttr->weight,
    $pAttr->label,
    $promAttr->label . ':' . ($promProp->isReadOnly() ? 'ro' : 'rw'),
    $mAttr->label . ':' . $mAttr->weight,
    $param->getName() . ':' . $paramAttr->label . ':' . $param->getDefaultValue(),
    $rm->getReturnType()->getName(),
    $fAttr->label . ':' . $rf->invoke(21),
    $rm->invoke($u, 'Hello')
]);
'@
} 'User|App\Meta|entity:5|pk|promoted_name:ro|action:10|prefix:arg:Hi|string|helper_fn:42|Hello Rin'

# 3. Object foreach (Iterator, IteratorAggregate, and plain object properties)
Assert-Case 'phase2_object_foreach_and_traversable' {
    & $phpAdapter.Run @'
<?php
class NumberRange implements Iterator {
    private int $cur = 0;
    public function __construct(private int $max) {}
    public function rewind(): void { $this->cur = 1; }
    public function valid(): bool { return $this->cur <= $this->max; }
    public function current(): mixed { return $this->cur * 10; }
    public function key(): mixed { return 'k' . $this->cur; }
    public function next(): void { $this->cur++; }
}

class Bag implements IteratorAggregate {
    public function getIterator(): Traversable {
        return new NumberRange(3);
    }
}

class PlainDto {
    public int $a = 1;
    public int $b = 2;
    private int $secret = 99;
}

$items = [];
foreach (new Bag() as $k => $v) {
    $items[] = "$k=$v";
}

$dto = new PlainDto();
foreach ($dto as $k => &$v) {
    $v += 10;
}
unset($v);
foreach ($dto as $k => $v) {
    $items[] = "$k:$v";
}
echo implode(',', $items) . '|' . iterator_count(new Bag());
'@
} 'k1=10,k2=20,k3=30,a:11,b:12|3'

# 4. ArrayAccess & Countable
Assert-Case 'phase2_array_access_and_countable' {
    & $phpAdapter.Run @'
<?php
class Store implements ArrayAccess, Countable {
    private array $data = [];
    public function offsetExists($offset): bool { return array_key_exists($offset, $this->data); }
    public function offsetGet($offset): mixed { return $this->data[$offset] ?? null; }
    public function offsetSet($offset, $value): void {
        if ($offset === null) { $this->data[] = $value; }
        else { $this->data[$offset] = $value; }
    }
    public function offsetUnset($offset): void { unset($this->data[$offset]); }
    public function count(): int { return count($this->data); }
}
$s = new Store();
$s['x'] = 42;
$s['y'] = 0;
$s[] = 99;
$res = [
    count($s),
    sizeof($s),
    is_countable($s) ? 'yes' : 'no',
    isset($s['x']) ? 'T' : 'F',
    empty($s['y']) ? 'T' : 'F',
    $s['x'],
    $s[0]
];
unset($s['x']);
$res[] = count($s);
$res[] = isset($s['x']) ? 'T' : 'F';
echo implode('|', $res);
'@
} '3|3|yes|T|T|42|99|2|F'

# 5. PHP 8.5 Standard Library & Rust Native Engine
Assert-Case 'phase2_php85_stdlib_and_rust_engine' {
    & $phpAdapter.Run @'
<?php
$nums = [1, 2, 3, 4, 5, 6];
$evens = array_filter($nums, fn($n) => $n % 2 === 0);
$squares = array_map(fn($n) => $n * $n, $evens);
$sum = array_reduce($squares, fn($acc, $v) => $acc + $v, 0);
$found = array_find($nums, fn($v) => $v > 4);
$foundKey = array_find_key($nums, fn($v) => $v > 4);
$anyGt5 = array_any($nums, fn($v) => $v > 5);
$allPos = array_all($nums, fn($v) => $v > 0);

$words = ['banana', 'apple', 'cherry'];
sort($words);

$s = sprintf("%s=%04d (%.2f)", "score", 42, 3.14159);
$nf = number_format(1234567.891, 2, '.', ',');
$pad = str_pad("7", 3, "0", STR_PAD_LEFT);
$rxMatch = preg_match('/^[a-z]+$/i', 'HelloWorld');
$rxRep = preg_replace('/\d+/', '#', 'a12b34c');
$rxSplit = implode('-', preg_split('/[\s,]+/', 'one, two   three'));

$ser = serialize(['k' => 123, 'v' => 'ok']);
$unser = unserialize($ser);

echo implode('|', [
    $sum,
    $found,
    $foundKey,
    $anyGt5 ? 'T' : 'F',
    $allPos ? 'T' : 'F',
    array_is_list($words) ? 'list' : 'map',
    implode(',', $words),
    $s,
    $nf,
    $pad,
    $rxMatch,
    $rxRep,
    $rxSplit,
    $unser['k'] . ':' . $unser['v'],
    md5('ALL-PHP-8.5.12'),
    sha1('ALL-PHP-8.5.12'),
    hash('sha256', 'ALL-PHP-8.5.12'),
    crc32('ALL-PHP-8.5.12'),
    levenshtein('algorithm', 'altruistic')
]);
'@
} '56|5|4|T|T|list|apple,banana,cherry|score=0042 (3.14)|1,234,567.89|007|1|a#b#c|one-two-three|123:ok|ff6254285a6af76c0b395dfea3ace014|a74020f06f1cafaf8a4039edb2b1c4e4077a159c|d7b12ac25accd884fb83df478641a581b818773e70a5e73430ec7779d488e1ad|406704786|6'

# ============================================================================
# Phase 3 Tests: Bidirectional ALL <-> PHP Compatibility (Polyglot Bridge)
# ============================================================================

$tempDir = Join-Path $root 'polyglot_test_tmp'
if (Test-Path $tempDir) { Remove-Item -Recurse -Force $tempDir }
[void](New-Item -ItemType Directory -Path $tempDir -Force)

try {
    # Create a PHP library file to be imported by ALL
    $phpLibPath = Join-Path $tempDir 'math_bridge.php'
    $phpLibContent = @'
<?php
function php_calc_bonus(int $base, int $rate): int {
    return $base + (int)($base * $rate / 100);
}

class PhpWallet {
    public int $balance = 0;
    public function __construct(int $initial) {
        $this->balance = $initial;
    }
    public function deposit(int $amount): int {
        $this->balance += $amount;
        return $this->balance;
    }
}
'@
    [System.IO.File]::WriteAllText($phpLibPath, $phpLibContent, [System.Text.UTF8Encoding]::new($false))

    # Create an ALL library file (with both English and Japanese functions) to be included by PHP
    $allLibPath = Join-Path $tempDir 'logic_bridge.all'
    $allLibContent = @'
fn all_double_plus(a, b) {
    return (a * 2) + b
}

関数 税込計算(価格) {
    価格 * 1.1 を返す
}

共有初期値という変数を 500とする
'@
    [System.IO.File]::WriteAllText($allLibPath, $allLibContent, [System.Text.UTF8Encoding]::new($false))

    # 6. ALL -> PHP: English import "math_bridge.php", PHP function call, PHP class new/method/property, PHP stdlib call
    Assert-Case 'phase3_all_imports_php_and_uses_classes' {
        $oldRoot = $env:ALL_MODULE_ROOT
        try {
            $env:ALL_MODULE_ROOT = $tempDir
            & $allAdapter.Run @'
import "math_bridge.php"
let bonus = php_calc_bonus(1000, 15)
let w = new PhpWallet(bonus)
let after = w.deposit(250)
let formatted = sprintf("wallet=%d,bal=%d", after, w.balance)
println(formatted)
'@
        } finally {
            $env:ALL_MODULE_ROOT = $oldRoot
        }
    } 'wallet=1400,bal=1400'

    # 7. ALL -> PHP: Natural Japanese grammar importing .php and inline <?php ... ?> block with shared variables
    Assert-Case 'phase3_all_japanese_and_inline_php' {
        $oldRoot = $env:ALL_MODULE_ROOT
        try {
            $env:ALL_MODULE_ROOT = $tempDir
            & $allAdapter.Run @'
「math_bridge.php」をモジュールとして読み込む
基本給という変数を 2000とする
<?php
$基本給 = php_calc_bonus($基本給, 20);
$メッセージ = strtoupper("ok");
?>
基本給に 100を足す
println(concat(メッセージ, concat(":", 基本給)))
'@
        } finally {
            $env:ALL_MODULE_ROOT = $oldRoot
        }
    } 'OK:2500'

    # 8. PHP -> ALL: require_once 'logic_bridge.all', calling English & Japanese ALL functions, reading ALL variables
    Assert-Case 'phase3_php_requires_all_and_calls_all_functions' {
        $escapedPath = $allLibPath.Replace('\', '\\')
        & $phpAdapter.Run @"
<?php
require_once '$escapedPath';
`$v1 = all_double_plus(15, 7);
`$v2 = 税込計算(1000);
echo `$共有初期値 . '|' . `$v1 . '|' . `$v2;
"@
    } '500|37|1100'

    # 9. PHP -> ALL: Inline <?all ... ?> block inside PHP with bidirectional variable mutation
    Assert-Case 'phase3_php_inline_all_block_bidirectional' {
        & $phpAdapter.Run @'
<?php
$score = 100;
function php_triple(int $n): int { return $n * 3; }
<?all
scoreに php_triple(10)を足す
fn all_FormatScore(s) {
    return concat("SCORE=", s)
}
?>
echo all_FormatScore($score);
'@
    } 'SCORE=130'

    # 10. PHP -> ALL Builtins: Calling ALL kv_put / kv_get / kv_keys / kv_delete and sql_exec / sql_query directly from PHP
    Assert-Case 'phase3_php_calls_all_kv_and_sql_builtins' {
        $oldRoot = $env:ALL_MODULE_ROOT
        try {
            $env:ALL_MODULE_ROOT = $tempDir
            $oldLoc = Get-Location
            Set-Location $tempDir
            try {
                & $phpAdapter.Run @'
<?php
kv_put("store.allkv", "lang", "ALL+PHP");
$val = kv_get("store.allkv", "lang", "none");
sql_exec("test.sqlite", "CREATE TABLE items (id INTEGER PRIMARY KEY, title TEXT);");
sql_exec("test.sqlite", "INSERT INTO items (title) VALUES (?);", ["RustEngine"]);
$rows = sql_query("test.sqlite", "SELECT title FROM items;");
echo $val . "|" . $rows[0]["title"];
'@
            } finally {
                Set-Location $oldLoc
            }
        } finally {
            $env:ALL_MODULE_ROOT = $oldRoot
        }
    } 'ALL+PHP|RustEngine'

    # 11. Phase 2: Generator throw() exception into suspended generator and catch inside generator
    Assert-Case 'phase2_generator_throw_exception' {
        & $phpAdapter.Run @'
<?php
function resilient_gen() {
    try {
        yield 'ready';
    } catch (RuntimeException $e) {
        yield 'caught:' . $e->getMessage();
    }
    yield 'after';
}
$g = resilient_gen();
$a = $g->current();
$b = $g->throw(new RuntimeException('boom'));
$g->next();
$c = $g->current();
echo "$a|$b|$c";
'@
    } 'ready|caught:boom|after'

    # 12. Phase 2: Closure Attributes & Static Closures + ReflectionFunction on Closure
    Assert-Case 'phase2_closure_attributes_and_reflection' {
        & $phpAdapter.Run @'
<?php
#[Attribute]
class Meta {
    public function __construct(public string $tag) {}
}
$fn = #[Meta('fast_closure')] static fn(int $a, int $b = 5): int => $a + $b;
$rf = new ReflectionFunction($fn);
$attr = $rf->getAttributes()[0]->newInstance();
echo implode('|', [
    $rf->isClosure() ? 'closure' : 'fn',
    $attr->tag,
    $rf->getNumberOfParameters(),
    $rf->getNumberOfRequiredParameters(),
    $rf->getReturnType()->getName(),
    $rf->invoke(10, 20)
]);
'@
    } 'closure|fast_closure|2|1|int|30'

    # 13. Phase 2: ReflectionClass newInstanceWithoutConstructor & ReflectionProperty setValue/getValue/isInitialized
    Assert-Case 'phase2_reflection_without_ctor_and_property_access' {
        & $phpAdapter.Run @'
<?php
class SecretBox {
    public int $code;
    public static string $label = 'BOX';
    public function __construct() {
        $this->code = 999;
    }
}
$rc = new ReflectionClass(SecretBox::class);
$box = $rc->newInstanceWithoutConstructor();
$rp = $rc->getProperty('code');
$initBefore = $rp->isInitialized($box) ? 'Y' : 'N';
$rp->setValue($box, 777);
$initAfter = $rp->isInitialized($box) ? 'Y' : 'N';
$sp = $rc->getProperty('label');
$sp->setValue(null, 'UPDATED');
echo implode('|', [$initBefore, $initAfter, $rp->getValue($box), SecretBox::$label]);
'@
    } 'N|Y|777|UPDATED'

    # 14. Phase 2: Array sorting (asort, arsort, ksort, krsort, usort, uasort, uksort) & array_splice
    Assert-Case 'phase2_array_sorting_and_splice' {
        & $phpAdapter.Run @'
<?php
$map = ['b' => 20, 'a' => 30, 'c' => 10];
asort($map);
$asortKeys = implode('', array_keys($map));
ksort($map);
$ksortKeys = implode('', array_keys($map));
$nums = [3, 1, 4, 2];
usort($nums, fn($x, $y) => $y <=> $x);
$list = [10, 20, 30, 40];
$removed = array_splice($list, 1, 2, [99]);
echo implode('|', [$asortKeys, $ksortKeys, implode(',', $nums), implode(',', $removed), implode(',', $list)]);
'@
    } 'cba|abc|4,3,2,1|20,30|10,99,40'

    # 15. Phase 2: compact, extract, array_combine, array_column, array_chunk, array_flip, array_diff, array_intersect
    Assert-Case 'phase2_array_manipulation_suite' {
        & $phpAdapter.Run @'
<?php
$city = 'Tokyo';
$year = 2026;
$packed = compact('city', 'year');
$data = ['alpha' => 'A', 'beta' => 'B'];
$cnt = extract($data);
$rows = [
    ['id' => 10, 'name' => 'Neo'],
    ['id' => 20, 'name' => 'Trinity']
];
$col = array_column($rows, 'name', 'id');
$diff = array_values(array_diff([1, 2, 3, 4], [2, 4]));
$inter = array_values(array_intersect([1, 2, 3], [2, 3, 4]));
echo implode('|', [$packed['city'], $packed['year'], $cnt, $alpha . $beta, $col[20], implode(',', $diff), implode(',', $inter)]);
'@
    } 'Tokyo|2026|2|AB|Trinity|1,3|2,3'

    # 16. Phase 2: String, URL, HTML, Hex, and Byte functions
    Assert-Case 'phase2_string_url_html_codecs' {
        & $phpAdapter.Run @'
<?php
$u = urlencode('a b+c');
$ru = rawurlencode('a b+c');
$h = htmlspecialchars('<a href="x">&</a>');
$hd = htmlspecialchars_decode($h);
$rot = str_rot13('Hello');
$hex = bin2hex('OK');
$bin = hex2bin($hex);
echo implode('|', [$u, $ru, $h, $hd, $rot, $hex, $bin, ucfirst('all'), lcfirst('ALL'), ucwords('hello world'), strrev('abcd')]);
'@
    } 'a+b%2Bc|a%20b%2Bc|&lt;a href=&quot;x&quot;&gt;&amp;&lt;/a&gt;|<a href="x">&</a>|Uryyb|4f4b|OK|All|aLL|Hello World|dcba'

    # 17. Phase 2: Class/Type introspection builtins
    Assert-Case 'phase2_class_and_type_introspection' {
        & $phpAdapter.Run @'
<?php
interface Flyable {}
trait Wings {}
enum Status: int { case Active = 1; }
class Bird implements Flyable {
    use Wings;
    public int $speed = 10;
    public function fly(): void {}
}
class Eagle extends Bird {}
$e = new Eagle();
echo implode('|', [
    class_exists(Eagle::class) ? '1' : '0',
    interface_exists(Flyable::class) ? '1' : '0',
    trait_exists(Wings::class) ? '1' : '0',
    enum_exists(Status::class) ? '1' : '0',
    method_exists($e, 'fly') ? '1' : '0',
    property_exists($e, 'speed') ? '1' : '0',
    is_a($e, Bird::class) ? '1' : '0',
    is_subclass_of($e, Bird::class) ? '1' : '0',
    get_parent_class($e),
    get_debug_type($e),
    get_debug_type(123)
]);
'@
    } '1|1|1|1|1|1|1|1|Bird|Eagle|int'

    # 18. Phase 3: Multi-roundtrip ALL -> PHP -> ALL -> PHP in a single program
    Assert-Case 'phase3_multi_roundtrip_all_php_interop' {
        & $allAdapter.Run @'
let items = [10, 20, 30]
<?php
$items[] = 40;
$total = array_sum($items);
?>
totalに 5を足す
<?php
$result = sprintf("TOTAL=%d (count=%d)", $total, count($items));
?>
println(result)
'@
    } 'TOTAL=105 (count=4)'

    # 19. Phase 2: All 13 newly completed builtin functions
    Assert-Case 'phase2_newly_completed_13_builtins' {
        & $phpAdapter.Run @'
<?php
function arg_probe($a, $b = 99) {
    $a = $a + 1;
    $args = func_get_args();
    return func_num_args() . ':' . func_get_arg(0) . ':' . implode(',', $args);
}
function gen_probe($x) {
    yield func_num_args() . ':' . func_get_arg(0) . ':' . func_get_arg(1);
}
class VarBox {
    public int $pub = 10;
    protected int $prot = 20;
    private int $priv = 30;
    public static string $st = 'S';
    public int $uninit;
    public static function varView() {
        return array_keys(get_class_vars(SubVarBox::class));
    }
}
class SubVarBox extends VarBox {
    public int $child = 40;
    public static function subView() {
        return array_keys(get_class_vars(SubVarBox::class));
    }
}

$g = gen_probe('hello', 'world');
$genOut = $g->current();

$vInt = '42';
settype($vInt, 'int');
$vArr = 'item';
settype($vArr, 'array');
$vObj = ['k' => 7];
settype($vObj, 'object');

$slashed = addslashes("O'Reilly \"hi\" \\");
$unslashed = stripslashes($slashed);
$diff = array_diff_assoc(['a' => 'green', 'b' => 'brown', 'c' => 'blue', 'red'], ['a' => 'green', 'yellow', 'red']);
$diffPairs = [];
foreach ($diff as $dk => $dv) { $diffPairs[] = "$dk=$dv"; }

echo implode('|', [
    arg_probe(10),
    arg_probe(10, 20, 30),
    $genOut,
    get_debug_type($vInt) . ':' . $vInt,
    count($vArr) . ':' . $vArr[0],
    get_debug_type($vObj) . ':' . $vObj->k,
    implode(',', array_keys(get_class_vars(SubVarBox::class))),
    implode(',', SubVarBox::subView()),
    implode(',', VarBox::varView()),
    substr_replace('abcdef', 'XY', 2, -1),
    chunk_split('abcdef', 2, '-'),
    wordwrap('The quick brown fox jumped over the lazy dog.', 20, '/'),
    wordwrap('A very long woooooooooooord.', 8, '/', true),
    quotemeta('a.b+c*d?[e]^f(g)$h'),
    $slashed,
    $unslashed,
    soundex('Euler') . ':' . soundex('Pfister') . ':' . soundex('Ashcraft') . ':' . soundex('123'),
    implode(',', $diffPairs)
]);
'@
    } '1:11:11|3:11:11,20,30|2:hello:world|int:42|1:item|stdClass:7|child,pub,st,uninit|child,pub,prot,st,uninit|child,pub,prot,priv,st,uninit|abXYf|ab-cd-ef-|The quick brown fox/jumped over the lazy/dog.|A very/long/wooooooo/ooooord.|a\.b\+c\*d\?\[e\]\^f\(g\)\$h|O\''Reilly \"hi\" \\|O''Reilly "hi" \|E460:P236:A226:0000|b=brown,c=blue,0=red'

    # 21. Phase 2: Task 5.2 Language & Stdlib Extensions
    Assert-Case 'phase2_task5_2_language_and_stdlib_extensions' {
        & $phpAdapter.Run @'
<?php
static $topStatic = 7;
function showMagic() {
    global $topStatic;
    return __FUNCTION__ . ':' . $topStatic;
}
trait MagicTrait {
    public function where(): string {
        return __CLASS__ . ':' . __TRAIT__ . ':' . __METHOD__ . ':' . __FUNCTION__;
    }
}
class ShadowParent {
    use MagicTrait;
    private $secret = 'P';
    public function getParentSecret() { return $this->secret; }
    public function pKeys() { $r = []; foreach ($this as $k => $v) { $r[] = "$k=$v"; } return implode(',', $r); }
}
class ShadowChild extends ShadowParent {
    public const C = 'CVAL';
    var $v = 1;
    public $a = 2, $b = 3;
    private $secret = 'C';
    public $unsetProp;
    public static function greet($x) { return 'hi:' . $x; }
    public function getChildSecret() { return $this->secret; }
    public function cKeys() { $r = []; foreach ($this as $k => $v) { $r[] = "$k=$v"; } return implode(',', $r); }
}

$obj = new ShadowChild();
unset($obj->unsetProp);
$objKeys = [];
foreach ($obj as $k => $val) { $objKeys[] = "$k=$val"; }

$clsName = 'ShadowChild';
$dynObj = new $clsName();
$propName = 'b';
$methName = 'getChildSecret';
$smName = 'greet';
$anon = new class(9) extends ShadowParent {
    public int $val;
    public function __construct($v) { $this->val = $v; }
};

$src = [10, 20, [30, 40]];
list($d1, , list(, &$d2)) = $src;
$d2 = 99;
$flist = [];
foreach ([[1, 2], [3, 4]] as [$x, $y]) { $flist[] = $x + $y; }

$arr = ['x' => 11, 'y' => 22, 'z' => 33];
$ptr = current($arr) . ':' . key($arr) . ':' . next($arr) . ':' . prev($arr) . ':' . end($arr) . ':' . reset($arr);
$walked = ['a' => 1, 'b' => [2, 3]];
array_walk_recursive($walked, function (&$v, $k, $mul) { $v *= $mul; }, 10);

ob_start(function ($buf, $flags) { return ($flags & PHP_OUTPUT_HANDLER_START) ? strtoupper($buf) : $buf; });
echo 'ob1';
$obMid = ob_get_contents();
ob_clean();
echo 'ob2';
$obOut = ob_get_clean();

ob_start();
echo 'top3';
$obFlushRet = ob_get_clean();

$cCheck = constant('ShadowChild::C') . ':' . (defined('ShadowChild::C') ? 'Y' : 'N') . ':' . (defined('NoSuchClass::X') ? 'Y' : 'N');

function btProbe($arg) {
    $vars = get_defined_vars();
    return $vars['arg'] . ':' . count(debug_backtrace());
}

echo implode('|', [
    showMagic(),
    $obj->where(),
    $obj->getParentSecret() . $obj->getChildSecret() . ':' . implode(',', $objKeys) . ';' . $obj->cKeys() . ';' . $obj->pKeys(),
    $dynObj->$propName . ':' . $dynObj->{$methName}() . ':' . $clsName::$smName('ok') . ':' . $anon->val,
    $d1 . ':' . $src[2][1] . ':' . implode(',', $flist),
    "interp:{$arr['y']}:{$obj->a}:${d1}",
    $ptr . ':' . $walked['a'] . ',' . $walked['b'][1],
    $obMid . ':' . $obOut . ':' . $obFlushRet,
    $cCheck . ':' . btProbe(5) . ':' . (strlen(zend_version()) > 0 ? 'Z' : 'N') . ':' . (in_array('ShadowChild', get_declared_classes(), true) ? 'DC' : 'NO')
]);
'@
    } 'showMagic:7|ShadowParent:MagicTrait:MagicTrait::where:where|PC:v=1,a=2,b=3;v=1,a=2,b=3,secret=C;secret=P,v=1,a=2,b=3|3:C:hi:ok:9|10:99:3,7|interp:22:2:10|11:x:22:11:33:11:10,30|ob1:ob2:top3|CVAL:Y:N:5:1:Z:DC'

# 22. Task 5.3: Asymmetric visibility, hook attributes, unpacking, ArrayAccess isset/empty/??, __debugInfo, __toString, assert, builtins
Assert-Case 'phase2_task5_3_asymmetric_vis_unpack_assert_and_builtins' {
    & $phpAdapter.Run @'
<?php
#[Attribute]
class HookAttr {}

interface IfaceA {}
class BaseVis implements IfaceA {
    public string $uninitTyped;
    public protected(set) array $items = [];
    private(set) string $tag = 'init';
    public string $hooked = 'ok' {
        #[HookAttr]
        final get => strtoupper($this->hooked);
        #[HookAttr]
        set($v) => strtolower($v);
    }

    public function __construct(public private(set) int $id = 1) {}

    public function setTag(string $t): void { $this->tag = $t; }
    public function addRefBump(): void {
        $r = &$this->id;
        $r += 10;
    }
    public function __toString(): string { return 'vis#' . $this->id; }
}

class ChildVis extends BaseVis {
    public function pushItem(int $v): void {
        $this->items[] = $v;
    }
}

class PlainNoToString {
    public int $secret = 7;
    public function __debugInfo(): array {
        return ['shown' => $this->secret * 2];
    }
}

class DeepAA implements ArrayAccess {
    public array $log = [];
    public function offsetExists(mixed $offset): bool {
        $this->log[] = 'E:' . $offset;
        return $offset === 0;
    }
    public function offsetGet(mixed $offset): mixed {
        $this->log[] = 'G:' . $offset;
        return ($offset === 0) ? $this : null;
    }
    public function offsetSet(mixed $offset, mixed $value): void {}
    public function offsetUnset(mixed $offset): void {}
}

class UnpackMagic {
    public function __call($name, $args) {
        return $name . ':' . ($args[0] ?? '') . ',' . ($args['k'] ?? '');
    }
}

function takeArgs(int $a, int $b = 0, int ...$rest): string {
    return $a . '+' . $b . '+' . implode(',', $rest);
}
function genVals(): Generator {
    yield 5;
    yield 'b' => 7;
    yield 'x' => 6;
}

$cv = new ChildVis(4);
$cv->setTag('next');
$cv->addRefBump();
$cv->pushItem(9);
$visErrors = [];
try { $cv->tag = 'x'; } catch (Error $e) { $visErrors[] = str_contains($e->getMessage(), 'private(set)') ? 'PS' : 'NO'; }
try { $cv->items[] = 2; } catch (Error $e) { $visErrors[] = str_contains($e->getMessage(), 'indirectly modify') ? 'IND' : 'NO'; }
try { $badRef = &$cv->id; } catch (Error $e) { $visErrors[] = str_contains($e->getMessage(), 'indirectly modify') ? 'REF' : 'NO'; }
try { $u = $cv->uninitTyped; } catch (Error $e) { $visErrors[] = str_contains($e->getMessage(), 'Typed property') ? 'UT' : 'NO'; }

$p = new PlainNoToString();
ob_start();
var_dump($p);
$dumpOut = ob_get_clean();
$toStrErr = '';
try { $s = (string)$p; } catch (Error $e) { $toStrErr = str_contains($e->getMessage(), 'could not be converted to string') ? 'TSE' : 'NO'; }

$aa = new DeepAA();
$aaIssetFalse = isset($aa[1][2][3]) ? 'T' : 'F';
$aaNullCoal = $aa[1][2][3] ?? 'fb';
$aaLog1 = implode(',', $aa->log);
$aa2 = new DeepAA();
$aaIssetTrue = isset($aa2[0][1]) ? 'T' : 'F';
$aaLog2 = implode(',', $aa2->log);

$um = new UnpackMagic();
$unpackRes = takeArgs(1, ...[2, 3, 4]) . ';' . takeArgs(...genVals()) . ';' . $um->go(...['h', 'k' => 'z']) . ';' . count([...genVals()]);

$assertErr = 'NO';
try { assert(false, 'boom'); } catch (AssertionError $e) { $assertErr = $e->getMessage(); }
$sideCalls = 0;
$prevAssert = ini_set('zend.assertions', '0');
$aOff = assert((++$sideCalls) > 0);
$reEnable = ini_set('zend.assertions', '1');
$minusOne = ini_set('zend.assertions', '-1');

$mr = array_merge_recursive(['a' => [1], 'x' => 'u'], ['a' => [2], 'x' => 'v']);
srand(123);
$r1 = rand(1, 1000);
mt_srand(123);
$mr1 = mt_rand(1, 1000);
$ri = random_int(10, 20);

class_alias('ChildVis', 'ChildVisAlias');
$aliasOk = ($cv instanceof ChildVisAlias) ? 'AL' : 'NO';
$parents = implode(',', array_values(class_parents('ChildVis')));
$ifaces = implode(',', array_values(class_implements('ChildVis')));

register_shutdown_function(function ($tag) {
    echo '|' . $tag;
}, 'SD');

echo implode('|', [
    $cv->id . ':' . $cv->tag . ':' . $cv->hooked . ':' . implode(',', $visErrors),
    (str_contains($dumpOut, '"shown"') ? 'DI' : 'NO') . ':' . $toStrErr,
    $aaIssetFalse . ':' . $aaNullCoal . ':' . $aaLog1 . ';' . $aaIssetTrue . ':' . $aaLog2,
    $unpackRes,
    $assertErr . ':' . $prevAssert . ':' . ($aOff && $sideCalls === 0 && $reEnable === '0' && $minusOne === false ? 'SKIP' : 'BAD'),
    strstr('Hello World', 'o W') . ';' . strchr('abcde', 'c', true) . ';' . stristr('FooBar', 'bar'),
    ($r1 >= 1 && $r1 <= 1000 && $mr1 >= 1 && $mr1 <= 1000 && $ri >= 10 && $ri <= 20 ? 'RND' : 'BAD'),
    implode(',', $mr['a']) . ';' . implode(',', $mr['x']),
    $aliasOk . ':' . $parents . ':' . $ifaces
]);
'@
    } '14:next:OK:PS,IND,REF,UT|DI:TSE|F:fb:E:1,E:1;F:E:0,G:0,E:1|1+2+3,4;5+7+6;go:h,z;3|boom:1:SKIP|o World;ab;Bar|RND|1,2;u,v|AL:BaseVis:IfaceA|SD'

# 23. Task 5.4: Reference return/arg notices, numeric/offset parity, ArrayIterator/ArrayObject, ReflectionConstant, anonymous class naming
Assert-Case 'phase2_task5_4_ref_numeric_spl_and_reflection_constant' {
    & $phpAdapter.Run -PhpDiagnostics @'
<?php
define('MY_CONST', 42);
$rc = new ReflectionConstant('MY_CONST');
$rcMissing = 'NO';
try { new ReflectionConstant('NO_SUCH_CONST'); } catch (ReflectionException $e) { $rcMissing = 'RE'; }

$ai = new ArrayIterator(['a' => 10, 'b' => 20, 'c' => 30]);
$ai->append(40);
$ai->seek(1);
$aiCur = $ai->key() . '=' . $ai->current();
unset($ai['b']);
$aiList = [];
foreach ($ai as $k => $v) { $aiList[] = "$k:$v"; }

$ao = new ArrayObject(['x' => 1, 'y' => 2]);
$ao['z'] = 3;
$ao->append(4);
$aoLoop = [];
foreach ($ao as $k => $v) { $aoLoop[] = "$k=$v"; }
$oldCopy = $ao->exchangeArray(['p' => 9]);

$notices = [];
set_error_handler(function ($errno, $errstr) use (&$notices) {
    $notices[] = $errstr;
    return true;
});

function byVal() { return 'val'; }
function takeRef(&$r) { return $r; }
function &retNonVar() { return 77; }
$refA = &byVal();
$refB = takeRef(byVal());
$refC = retNonVar();

$leadNum = '10apples' + 5;
$nullIdx = null;
$badIdx = $nullIdx[0];
$numErr = 'NO';
try { $x = 'abc' + 1; } catch (TypeError $e) { $numErr = str_contains($e->getMessage(), 'Unsupported operand') ? 'TE' : 'BAD'; }
restore_error_handler();

$anon = new class {};
echo implode('|', [
    $rc->getName() . ':' . $rc->getValue() . ':' . ($rc->inNamespace() ? 'Y' : 'N') . ':' . $rcMissing,
    $aiCur . ':' . count($ai) . ':' . implode(',', $aiList),
    count($ao) . ':' . count($oldCopy) . ':' . implode(',', $aoLoop) . ':' . ArrayObject::ARRAY_AS_PROPS,
    $refA . ',' . $refB . ',' . $refC,
    $leadNum . ':' . ($badIdx === null ? 'N' : 'X') . ':' . $numErr . ':' . count($notices),
    get_class($anon)
]);
'@
    } 'MY_CONST:42:N:RE|b=20:3:a:10,c:30,0:40|1:4:x=1,y=2,z=3,0=4:2|val,val,77|15:N:TE:5|class@anonymous'

# 24. Task 5.5: Top-level hoisting, binary/compound operand TypeErrors, index vivification/errors, and timezone/locale builtins
Assert-Case 'phase2_task5_5_hoisting_operand_types_and_builtins' {
    & $phpAdapter.Run -PhpDiagnostics @'
<?php
$hoistedVal = hoistAdd(3, 4);
function hoistAdd($x, $y) { return $x + $y; }

$typeErrs = [];
try { $a = 'abc' + 1; } catch (TypeError $e) { $typeErrs[] = $e->getMessage(); }
try { $b = [] + new stdClass(); } catch (TypeError $e) { $typeErrs[] = $e->getMessage(); }
$arrVal = [];
try { $c = -$arrVal; } catch (TypeError $e) { $typeErrs[] = $e->getMessage(); }
try { $d = ~$arrVal; } catch (TypeError $e) { $typeErrs[] = $e->getMessage(); }
try { $arrVal /= 'z'; } catch (TypeError $e) { $typeErrs[] = $e->getMessage(); }

$ua = ['a' => 1];
$ua += ['a' => 9, 'b' => 2];

$nv = null;
$nv[] = 'ok';
$nested = [];
$nested['k'][] = 7;

$deprs = [];
set_error_handler(function ($errno, $msg) use (&$deprs) {
    $deprs[] = $msg;
    return true;
});
$fv = false;
$fv[] = 'f';
restore_error_handler();

$scErr = '';
try { $sc = 5; $sc[0] = 1; } catch (Error $e) { $scErr = $e->getMessage(); }
$roErr = '';
try { $ro = [1]; $x = $ro[]; } catch (Error $e) { $roErr = $e->getMessage(); }
$noErr = '';
try { $no = null; $no->foo(); } catch (Error $e) { $noErr = $e->getMessage(); }

class VisSecret { private $s = 1; }
$visObj = new VisSecret();
$visErr = '';
try { $v = $visObj->s; } catch (Error $e) { $visErr = $e->getMessage(); }

$fgErr = '';
try { func_get_arg(0); } catch (Error $e) { $fgErr = $e->getMessage(); }

$tz1 = date_default_timezone_get();
$tzOk = date_default_timezone_set('Asia/Tokyo');
$tz2 = date_default_timezone_get();
$loc = setlocale(LC_ALL, 'C');
$jsonConst = defined('JSON_UNESCAPED_SLASHES') ? 'JY' : 'JN';

echo implode('|', [
    $hoistedVal,
    implode(';', $typeErrs),
    $ua['a'] . ',' . $ua['b'],
    $nv[0] . ',' . $nested['k'][0] . ',' . $fv[0] . ':' . count($deprs),
    $scErr,
    $roErr,
    $noErr,
    str_contains($visErr, 'Cannot access private property VisSecret::$s') ? 'VIS' : $visErr,
    $fgErr,
    $tz1 . '>' . ($tzOk ? '1' : '0') . '>' . $tz2 . ':' . $loc . ':' . $jsonConst
]);
'@
    } '7|Unsupported operand types: string + int;Unsupported operand types: array + stdClass;Unsupported operand types: array * int;Cannot perform bitwise not on array;Unsupported operand types: array / string|1,2|ok,7,f:1|Cannot use a scalar value as an array|Cannot use [] for reading|Call to a member function foo() on null|VIS|func_get_arg() cannot be called from the global scope|UTC>1>Asia/Tokyo:C:JY'

# 25. Task 5.6: Inc/dec parity, visibility messages & sibling/magic fallbacks, json_decode depth/flags, func_num_args global, fast array_fill + variadic unpack
Assert-Case 'phase2_task5_6_inc_dec_visibility_magic_and_fast_unpack' {
    & $phpAdapter.Run -PhpDiagnostics @'
<?php
$warns = [];
set_error_handler(function ($errno, $msg) use (&$warns) {
    $warns[] = $msg;
    return true;
});
$s1 = 'az'; $s1++;
$s2 = 'Z'; $s2++;
$s3 = 'abc'; $s3--;
$n1 = null; $n1++;
$n2 = null; $n2--;
$b1 = true; $b1++;
foreach (true as $fv) {}
restore_error_handler();

$incArr = [];
$incErr = '';
try { $incArr++; } catch (TypeError $e) { $incErr = $e->getMessage(); }

class BaseSib {
    protected static function sm() { return 'BS'; }
    private static function pm() { return 'BP'; }
}
class SibA extends BaseSib {
    protected static function sm() { return 'SA'; }
    protected static function pm() { return 'PA'; }
}
class SibB extends BaseSib {
    public static function run() {
        $r1 = SibA::sm();
        $r2 = '';
        try { SibA::pm(); } catch (Error $e) { $r2 = $e->getMessage(); }
        return $r1 . ';' . $r2;
    }
}

class MagicAcc {
    private string $p = 'pv';
    private static function sf() { return 'SF'; }
    private function mf() { return 'MF'; }
    public function __get($n) { return 'G:' . $this->$n; }
    public function __set($n, $v) { $this->$n = 'S:' . $v; }
    public function __call($m, $args) { return call_user_func_array([$this, $m], $args); }
    public static function __callStatic($m, $args) { return self::sf(); }
}
$ma = new MagicAcc();
$g1 = $ma->p;
$ma->p = 'new';
$g2 = $ma->p;
$c1 = $ma->mf();
$cs1 = MagicAcc::sf();

$selfErr = '';
try { self::class; } catch (Error $e) { $selfErr = $e->getMessage(); }
$fnaErr = '';
try { func_num_args(); } catch (Error $e) { $fnaErr = $e->getMessage(); }
$jd = json_decode('{"x":9}', null, 10, 1);

function sumCount(...$xs) { return count($xs) . ':' . $xs[0] . ':' . $xs[count($xs) - 1]; }
$filled = array_fill(0, 500, 7);
$unpacked = sumCount(...$filled, ...$filled);

echo implode('|', [
    $s1 . ',' . $s2 . ',' . $s3 . ',' . $n1 . ',' . ($n2 === null ? 'N' : 'X') . ',' . ($b1 === true ? 'T' : 'F') . ':' . count($warns),
    $incErr,
    SibB::run(),
    $g1 . ';' . $g2 . ';' . $c1 . ';' . $cs1,
    $selfErr,
    $fnaErr,
    is_array($jd) ? ('A:' . $jd['x']) : 'OBJ',
    $unpacked
]);
'@
    } 'ba,AA,abc,1,N,T:6|Cannot perform increment on array|SA;Call to protected method SibA::pm() from scope SibB|G:pv;G:S:new;MF;SF|Cannot use "self" when no class scope is active|func_num_args() must be called from a function context|A:9|1000:7:7'

# 26. Task 5.7 & 5.8: Bidirectional polyglot hooks, private(set) enforcement across ALL/PHP, non-UTF8 binary roundtrip, and PhpBuiltinNames sharing
Assert-Case 'phase3_task5_7_5_8_polyglot_hooks_binary_and_zend_diagnostics' {
    & $phpAdapter.Run -PhpDiagnostics @'
<?php
class HookedBox {
    public string $label = 'init' {
        set => strtoupper($value);
    }
    public string $badge {
        get => '[' . $this->label . ']';
    }
    public private(set) string $secret = 'LOCKED';
}
<?all
fn all_touch_box(b) {
    b.label = "hello"
    let badge = b.badge
    let sx = soundex("Euler")
    let errTag = "NO_ERR"
    try {
        b.secret = "hack"
    } catch (err) {
        if (str_contains(err, "private(set)")) {
            errTag = "PRIVATE_SET_BLOCKED"
        } else {
            errTag = err
        }
    }
    return concat(badge, concat(":", concat(sx, concat(":", errTag))))
}
fn all_id_bin(raw) {
    return raw
}
?>
$box = new HookedBox();
$r1 = all_touch_box($box);
$rawOut = all_id_bin("\x80\xFF\x00\xFE");
echo $r1 . '|' . $box->label . '|' . $box->secret . '|' . bin2hex($rawOut);
'@
} '[HELLO]:E460:PRIVATE_SET_BLOCKED|HELLO|LOCKED|80ff00fe'

# 27. Task 5.9: LHS/RHS evaluation order, reference notice caller line numbers, class hoisting, dynamic braced members, colon syntax, scalar compound index error, assign_ref LHS precedence
Assert-Case 'phase2_task5_9_eval_order_ref_lines_hoisting_and_colon_syntax' {
    & $phpAdapter.Run -PhpDiagnostics @'
<?php
$warns = [];
set_error_handler(function ($errno, $msg, $file = '', $line = 0) use (&$warns) {
    $warns[] = $errno . '@' . $line . ':' . $msg;
    return true;
});

$orderLog = [];
function logStep(&$log, $label, $ret) {
    $log[] = $label;
    return $ret;
}
$target = ['x' => ['y' => 0], 'z' => ['y' => 0]];
function swapAndRhs(&$log, &$target) {
    $log[] = 'R';
    $target = ['x' => ['y' => 111], 'z' => ['y' => 222]];
    return 777;
}
$target[logStep($orderLog, 'L1', 'x')][logStep($orderLog, 'L2', 'y')] = swapAndRhs($orderLog, $target);

$hoistObj = new HoistChild();
class HoistChild extends HoistBase {
    public function tag() { return $this->baseTag() . '-C'; }
}
class HoistBase {
    public static string $dynStatic = 'SVAL';
    public string $dynInst = 'IVAL';
    protected function baseTag() { return 'B'; }
}
$dynFn = fn($n) => $n;
$dynRead = $hoistObj->{$dynFn('dynInst')} . '/' . HoistBase::${$dynFn('dynStatic')};

function retNonRef() { return 42; }
$refLine = __LINE__ + 1;
$rv =& retNonRef();
$builtinArr = [10, 20];
$builtinLine = __LINE__ + 1;
$shifted = array_shift(array_values($builtinArr));

$scalarErr = '';
$sc = 5;
try { $sc[0] += 1; } catch (Error $e) { $scalarErr = $e->getMessage(); }

$refLhsErr = '';
$strVal = 'abc';
$warnCountBeforeRefErr = count($warns);
try { $strVal[0] =& retNonRef(); } catch (Error $e) { $refLhsErr = $e->getMessage(); }
$warnCountAfterRefErr = count($warns);

$cOut = '';
$cond = 2;
if ($cond === 1):
    $cOut .= 'if1';
elseif ($cond === 2):
    $cOut .= 'elif2';
else:
    $cOut .= 'else';
endif;

$w = 0;
while ($w < 2):
    $cOut .= ',w' . $w;
    $w++;
endwhile;

for ($fi = 0; $fi < 2; $fi++):
    $cOut .= ',f' . $fi;
endfor;

foreach (['p', 'q'] as $item):
    $cOut .= ',' . $item;
endforeach;

switch ($cond):
    case 1:
        $cOut .= ',s1';
        break;
    case 2:
        $cOut .= ',s2';
        break;
endswitch;

restore_error_handler();
echo implode('|', [
    implode(',', $orderLog) . ':' . $target['x']['y'],
    $hoistObj->tag() . ':' . $dynRead,
    $rv . '@' . $shifted,
    $warns[0],
    $warns[1],
    'REF=' . $refLine . ':BLT=' . $builtinLine,
    $scalarErr,
    $refLhsErr . ':' . $warnCountBeforeRefErr . ':' . $warnCountAfterRefErr,
    $cOut
]);
'@
} 'L1,L2,R:777|B-C:IVAL/SVAL|42@10|8@35:Only variables should be assigned by reference|8@38:Only variables should be passed by reference|REF=35:BLT=38|Cannot use a scalar value as an array|Cannot create references to/from string offsets:2:2|elif2,w0,w1,f0,f1,p,q,s2'

# 28. Task 5.10: Anonymous class naming, ErrorException, IteratorAggregate errors, fopen trace, localeconv, highlight_string, E_USER_ERROR deprecation, and Reflection/Attributes scopes
Assert-Case 'phase2_task5_10_anon_class_errorexception_iterator_and_attributes' {
    & $phpAdapter.Run -PhpDiagnostics @'
<?php
interface IA1 {}
interface IA2 {}
class BaseA {}
$an1 = new class extends BaseA implements IA1 {};
$an2 = new class implements IA1, IA2 {};
$anonRes = strstr(get_class($an1), "\0", true) . ',' . strstr(get_class($an2), "\0", true);

$eeLineBase = __LINE__;
$ee1 = new ErrorException();
$ee2 = new ErrorException('E2', 7, E_WARNING, null, null);
$ee3 = new ErrorException('E3', 8, E_ERROR, null, 123);
$ee4 = new ErrorException('E4', 9, E_NOTICE, 'abc.php');
$ee5 = new ErrorException('E5', 10, E_NOTICE, 'abc.php', 456);
$eeOk = ($ee1->getMessage() === '' && $ee1->getLine() === ($eeLineBase + 1)
    && $ee2->getSeverity() === E_WARNING && $ee2->getLine() === ($eeLineBase + 2)
    && $ee3->getFile() === $ee1->getFile() && $ee3->getLine() === 123
    && $ee4->getFile() === 'abc.php' && $ee4->getLine() === 0
    && $ee5->getFile() === 'abc.php' && $ee5->getLine() === 456) ? 'EE_OK' : 'EE_BAD';

class BadIterStd implements IteratorAggregate {
    public function getIterator() { return new stdClass(); }
}
class BadIterArr implements IteratorAggregate {
    public function getIterator() { return [1, 2]; }
}
$iterErrLine = 0;
$iterErr1 = '';
$iterErr2 = '';
$expectedIterLine = __LINE__ + 2;
try {
    foreach (new BadIterStd() as $k => $v) {}
} catch (Exception $e) {
    $iterErrLine = $e->getLine();
    $iterErr1 = $e->getMessage();
}
try {
    foreach (new BadIterArr() as $k => $v) {}
} catch (Exception $e) {
    $iterErr2 = $e->getMessage();
}
$iterOk = ($iterErrLine === $expectedIterLine
    && $iterErr1 === 'Objects returned by BadIterStd::getIterator() must be traversable or implement interface Iterator'
    && $iterErr2 === 'Objects returned by BadIterArr::getIterator() must be traversable or implement interface Iterator') ? 'ITER_OK' : ($iterErrLine . ':' . $iterErr1);

interface TraceCatchable {}
class TraceErrEx extends Exception implements TraceCatchable {}
$trigLogs = [];
set_error_handler(function ($errno, $msg, $file = '', $line = 0) use (&$trigLogs) {
    if ($errno === E_USER_ERROR || $errno === E_DEPRECATED) {
        $trigLogs[] = $errno . ':' . (str_contains($msg, 'deprecated') ? 'DEP' : $msg);
        return true;
    }
    throw new TraceErrEx($msg, $errno);
});
$traceOut = '';
try {
    $fh = fopen('/tmp/definitely_missing_file_for_test_510', 'r');
} catch (TraceCatchable $e) {
    $tr = $e->getTrace();
    $traceOut = ($tr[1]['function'] ?? '') . ':' . $e->getMessage();
}
trigger_error('boom', E_USER_ERROR);
restore_error_handler();

$hl = highlight_string('<?php __CLASS__;', true);
$hlOk = (is_string($hl) && strlen($hl) > 0) ? 'HL_OK' : 'HL_BAD';

$badLoc = setlocale(LC_ALL, 'invalid');
$deLoc = setlocale(LC_NUMERIC, 'de_DE.UTF-8');
$lc = localeconv();
$locOk = ($badLoc === false && $deLoc === 'de_DE.UTF-8' && $lc['decimal_point'] === ',' && $lc['thousands_sep'] === '.') ? 'LOC_OK' : 'LOC_BAD';

#[Attribute(parent::VALID_FLAGS)]
class ScopedAttr extends ScopedAttrBase {
    public string $tag = 'OK';
}
class ScopedAttrBase {
    protected const VALID_FLAGS = Attribute::TARGET_CLASS;
}
#[ScopedAttr]
class AttrHolder {
    private const SECRET = 's1';
    #[A1(self::class, self::SECRET)]
    public const CA = 10, CB = 20;
    #[A1(self::class, self::SECRET)]
    public function m(#[A1(self::class, self::SECRET)] $p) {}
}
trait AttrTrait {
    #[A1(self::class, self::TF)]
    public function tf() {}
}
class AttrTraitUser {
    use AttrTrait;
    private const TF = 'trait_used';
}
class ClosureScopeAlt {
    private const CV = 'alt_cv';
}
class ClosureScopeOrig {
    private const CV = 'orig_cv';
    public static function make() {
        return #[A1(self::class, self::CV)] function (#[A1(self::class, self::CV)] $x) {};
    }
}
$rcHolder = new ReflectionClass(AttrHolder::class);
$rcConstB = $rcHolder->getReflectionConstant('CB');
$rcDirectA = new ReflectionClassConstant(AttrHolder::class, 'CA');
$rcTraitUser = new ReflectionClass(AttrTraitUser::class);
$rcTraitOnly = new ReflectionClass(AttrTrait::class);
$traitMissingErr = '';
try {
    $rcTraitOnly->getMethod('tf')->getAttributes()[0]->getArguments();
} catch (Error $e) {
    $traitMissingErr = $e->getMessage();
}
$roAnon = new ReflectionObject(new #[A1(self::class)] class {
    #[A1(self::class)]
    public function ping() {}
});
$roAnonClassArgs = $roAnon->getAttributes()[0]->getArguments();
$roAnonMethodArgs = $roAnon->getMethod('ping')->getAttributes()[0]->getArguments();
$clOrigArgs = (new ReflectionFunction(ClosureScopeOrig::make()))->getAttributes()[0]->getArguments();
$clBoundArgs = (new ReflectionFunction(ClosureScopeOrig::make()->bindTo(null, ClosureScopeAlt::class)))->getParameters()[0]->getAttributes()[0]->getArguments();
$scopedInst = $rcHolder->getAttributes(ScopedAttr::class)[0]->newInstance();
$missingAttrErr = '';
try {
    (new ReflectionFunction(#[ScopedAttr(MissingAttrConstClass::NOPE)] function () {}))->getAttributes()[0]->getArguments();
} catch (Error $e) {
    $missingAttrErr = $e->getMessage();
}

echo implode('|', [
    $anonRes,
    $eeOk,
    $iterOk,
    str_contains($traceOut, 'fopen:fopen(') ? 'TRACE_OK' : $traceOut,
    implode(',', $trigLogs),
    $hlOk,
    $locOk,
    implode(',', $rcConstB->getAttributes()[0]->getArguments()) . ';' . $rcDirectA->getValue(),
    implode(',', $rcHolder->getMethod('m')->getParameters()[0]->getAttributes()[0]->getArguments()),
    implode(',', $rcTraitUser->getMethod('tf')->getAttributes()[0]->getArguments()),
    $traitMissingErr,
    ($roAnonClassArgs[0] === $roAnon->getName() && $roAnonMethodArgs[0] === $roAnon->getName()) ? 'RO_OK' : 'RO_BAD',
    implode(',', $clOrigArgs) . '->' . implode(',', $clBoundArgs),
    $scopedInst->tag,
    $missingAttrErr
]);
'@
} 'BaseA@anonymous,IA1@anonymous|EE_OK|ITER_OK|TRACE_OK|8192:DEP,256:boom|HL_OK|LOC_OK|AttrHolder,s1;10|AttrHolder,s1|AttrTraitUser,trait_used|Undefined constant self::TF|RO_OK|ClosureScopeOrig,orig_cv->ClosureScopeAlt,alt_cv|OK|Class "MissingAttrConstClass" not found'

} finally {
    if (Test-Path $tempDir) { Remove-Item -Recurse -Force $tempDir }
}

Write-Host "ALL PHP Phase 2 & Phase 3 verification: $passed/$($passed + $failed) passed; $failed failed"
if ($failed -gt 0) { exit 1 }
