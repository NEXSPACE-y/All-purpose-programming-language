<?php
// Reference-only process. This file is never evaluated by the ALL runtime.
require __DIR__ . '/DlTest-Oracle-Strict.php';
function all_abi_weak_call($callable, array $args, bool $frameless) {
    return $frameless ? dl_test_frameless($args[0]) : $callable(...$args);
}
$cases = json_decode(file_get_contents($argv[1]), true, flags: JSON_THROW_ON_ERROR);
$records = [];
foreach ($cases as $case) {
    $args = array_map(static function ($arg) {
        return match ($arg['type']) {
            1 => null, 2 => false, 3 => true, 4 => $arg['integer'], 5 => $arg['real'],
            6 => base64_decode($arg['base64'], true), 7 => [],
            default => throw new LogicException('Unsupported fixture kind'),
        };
    }, $case['args']);
    $callable = $case['scope'] === '' ? $case['function'] : [new $case['scope'](), $case['function']];
    $diagnostics = '';
    set_error_handler(static function ($severity, $message) use (&$diagnostics) {
        $label = match ($severity) { E_DEPRECATED => 'Deprecated', E_WARNING => 'Warning', default => (string)$severity };
        $diagnostics .= $label . ': ' . $message . "\n";
        return true;
    });
    ob_start();
    try {
        $value = $case['strict'] ? all_abi_strict_call($callable, $args, $case['frameless']) : all_abi_weak_call($callable, $args, $case['frameless']);
        $result = ['Ok'=>true,'Status'=>0,'Type'=>get_debug_type($value),
            'Value'=>is_string($value)?base64_encode($value):$value,'ErrorClass'=>null,'ErrorMessage'=>null];
    } catch (Throwable $error) {
        $result = ['Ok'=>false,'Status'=>1,'Type'=>null,'Value'=>null,
            'ErrorClass'=>get_class($error),'ErrorMessage'=>$error->getMessage()];
    }
    $result['OutputBase64'] = base64_encode(ob_get_clean());
    $result['DiagnosticsBase64'] = base64_encode($diagnostics);
    restore_error_handler();
    $records[] = ['id'=>$case['id'],'result'=>$result];
}
$prop = new ReflectionProperty(DlTestSuperClass::class, 'a');
$object = new DlTestSuperClass;
$metadata = ['constant'=>DL_TEST_CONST,'parent'=>get_parent_class(DlTestSubClass::class),
    'property'=>[$prop->getModifiers(),16,$prop->isInitialized($object)],
    'inherited_property'=>[$prop->getModifiers(),16,$prop->isInitialized(new DlTestSubClass)],
    'ini_long'=>ini_get('dl_test.long'),'ini_string'=>ini_get('dl_test.string')];
if (function_exists('dl_test_use_register_functions_directly')) {
    $metadata['direct_registration'] = ['Ok'=>true,'Status'=>0,'Type'=>'string','Value'=>base64_encode(dl_test_use_register_functions_directly()),'ErrorClass'=>null,'ErrorMessage'=>null,'OutputBase64'=>'','DiagnosticsBase64'=>''];
}
ini_set('dl_test.long','97');ini_set('dl_test.string','changed');
$metadata['ini_changed']=[ini_get('dl_test.long'),ini_get('dl_test.string')];
file_put_contents($argv[2], json_encode(['method'=>'stock_PHP_separate_reference_process','cases'=>$records,'metadata'=>$metadata],JSON_PRETTY_PRINT|JSON_UNESCAPED_SLASHES|JSON_THROW_ON_ERROR)."\n");
