<?php
// Oracle-only observations of registration and lookup. No PHP process is used
// by the independent symbol component or by the ALL interpreter candidate.
$cases = json_decode(file_get_contents($argv[1]), true, 512, JSON_THROW_ON_ERROR);
$rows = [];
foreach ($cases as $i => $case) {
    if (empty($case['oracle'])) { continue; }
    $left = base64_decode($case['left_base64'], true);
    $right = base64_decode($case['right_base64'], true);
    $tag = 'SymbolAudit' . $i;
    $error = null;
    $same = false;
    try {
        switch ($case['kind']) {
            case 'Function':
                eval('namespace ' . $tag . '; function ' . $left . '() {}');
                $same = function_exists($tag . '\\' . $right);
                break;
            case 'ClassLike':
                eval('namespace ' . $tag . '; class ' . $left . ' {}');
                $same = class_exists($tag . '\\' . $right, false);
                break;
            case 'Method':
            case 'Property':
            case 'ClassConstant':
                $leftClass = !empty($case['member']) ? base64_decode($case['left_container_base64'], true) : 'Container';
                $rightClass = !empty($case['member']) ? base64_decode($case['right_container_base64'], true) : 'Container';
                $separator = strrpos($leftClass, '\\');
                $ns = $separator === false ? $tag : $tag . '\\' . substr($leftClass, 0, $separator);
                $class = $separator === false ? $leftClass : substr($leftClass, $separator + 1);
                $body = $case['kind'] === 'Method' ? 'function ' . $left . '() {}' :
                    ($case['kind'] === 'Property' ? 'public $' . $left . ';' : 'const ' . $left . ' = 37;');
                eval('namespace ' . $ns . '; class ' . $class . ' {' . $body . '}');
                $target = $tag . '\\' . $rightClass;
                $same = $case['kind'] === 'Method' ? method_exists($target, $right) :
                    ($case['kind'] === 'Property' ? property_exists($target, $right) : defined($target . '::' . $right));
                break;
            case 'Variable':
                $same = (static function ($left, $right) { ${$left} = 37; return isset(${$right}) && ${$right} === 37; })($left, $right);
                break;
            case 'Parameter':
                eval('namespace ' . $tag . '; function Probe($' . $left . ' = 0) { return $' . $left . '; }');
                $same = call_user_func_array($tag . '\\Probe', [$right => 37]) === 37;
                break;
            case 'Constant':
                define($tag . '\\' . $left, 37);
                $same = defined($tag . '\\' . $right);
                break;
            case 'Namespace':
                define($left . '\\' . $tag . '\\Probe', 37);
                $same = defined($right . '\\' . $tag . '\\Probe');
                break;
            case 'FunctionImportAlias':
                eval('namespace ' . $tag . '; function Probe() { return 37; }');
                $same = eval('namespace ' . $tag . 'Use; use function \\' . $tag . '\\Probe as ' . $left . '; return ' . $right . '() === 37;');
                break;
            case 'ClassImportAlias':
                eval('namespace ' . $tag . '; class Probe {}');
                $same = eval('namespace ' . $tag . 'Use; use \\' . $tag . '\\Probe as ' . $left . '; return (new ' . $right . ') instanceof \\' . $tag . '\\Probe;');
                break;
            case 'ConstantImportAlias':
                define($tag . '\\Probe', 37);
                $same = eval('namespace ' . $tag . 'Use; use const \\' . $tag . '\\Probe as ' . $left . '; return ' . $right . ' === 37;');
                break;
            default: throw new LogicException('No oracle behavior for ' . $case['kind']);
        }
    } catch (Throwable $failure) {
        // Unknown named parameter or unknown lexical alias resolves to Error.
        // Preserve every failure for the comparator to classify explicitly.
        $error = ['class' => get_class($failure), 'message_base64' => base64_encode($failure->getMessage())];
    }
    $rows[] = ['id' => $case['id'], 'equal' => $same, 'error' => $error];
}
echo json_encode($rows, JSON_THROW_ON_ERROR | JSON_UNESCAPED_SLASHES);
