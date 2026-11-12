<?php
declare(strict_types=1);

// Reference-only metadata collector. Never executes the ALL candidate.
$GLOBALS['all_api_warnings'] = [];
set_error_handler(static function (int $severity, string $message, string $file, int $line): bool {
    $GLOBALS['all_api_warnings'][] = [
        'severity' => $severity, 'message_base64' => base64_encode($message),
        'file_base64' => base64_encode($file), 'line' => $line,
    ];
    return false; // Keep PHP's actual diagnostic on stderr as well.
});

function all_api_name(string $name): array {
    return ['name' => preg_match('//u', $name) === 1 ? $name : '<non-UTF8 identifier>',
        'name_base64' => base64_encode($name)];
}

function all_api_error(Throwable $error): array {
    return ['class' => get_class($error), 'message' => all_api_value($error->getMessage())];
}

function all_api_value(mixed $value, int $depth = 0): array {
    if ($depth > 128) { return ['kind' => get_debug_type($value), 'status' => 'UNAVAILABLE', 'reason' => 'depth_limit_128']; }
    if ($value === null) { return ['kind' => 'null', 'value' => null]; }
    if (is_bool($value)) { return ['kind' => 'bool', 'value' => $value]; }
    if (is_int($value)) { return ['kind' => 'int', 'decimal' => (string)$value]; }
    if (is_float($value)) {
        return ['kind' => 'float', 'ieee754_big_endian_hex' => bin2hex(pack('E', $value)),
            'classification' => is_nan($value) ? 'nan' : (is_infinite($value) ? ($value > 0 ? '+infinity' : '-infinity') : 'finite'),
            'decimal_preview' => is_finite($value) ? json_encode($value, JSON_PRESERVE_ZERO_FRACTION | JSON_THROW_ON_ERROR) : null];
    }
    if (is_string($value)) {
        $result = ['kind' => 'string', 'length_bytes' => strlen($value), 'bytes_base64' => base64_encode($value)];
        $preview = substr($value, 0, 200);
        if (preg_match('//u', $preview) === 1) { $result['utf8_preview'] = $preview; $result['preview_truncated'] = strlen($value) > 200; }
        return $result;
    }
    if (is_array($value)) {
        $entries = [];
        foreach ($value as $key => $item) { $entries[] = ['key' => all_api_value($key, $depth + 1), 'value' => all_api_value($item, $depth + 1)]; }
        return ['kind' => 'array', 'count' => count($value), 'entries' => $entries];
    }
    if ($value instanceof UnitEnum) {
        $result = ['kind' => 'enum', 'class' => all_api_name(get_class($value)), 'case' => all_api_name($value->name)];
        if ($value instanceof BackedEnum) { $result['backing_value'] = all_api_value($value->value, $depth + 1); }
        return $result;
    }
    if (is_resource($value)) { return ['kind' => 'resource', 'status' => 'DESCRIBED_NOT_SERIALIZED', 'resource_type' => get_resource_type($value)]; }
    if (gettype($value) === 'resource (closed)') { return ['kind' => 'resource_closed', 'status' => 'DESCRIBED_NOT_SERIALIZED']; }
    if (is_object($value)) { return ['kind' => 'object', 'class' => all_api_name(get_class($value)), 'status' => 'DESCRIBED_NOT_SERIALIZED', 'reason' => 'no_user_serialization_or_constructor_invoked']; }
    return ['kind' => get_debug_type($value), 'status' => 'UNAVAILABLE', 'reason' => 'unsupported_reflection_value'];
}

function all_api_type(?ReflectionType $type): ?array {
    if ($type === null) { return null; }
    $result = ['display' => (string)$type, 'allows_null' => $type->allowsNull()];
    if ($type instanceof ReflectionNamedType) { $result += ['kind' => 'named', 'name' => $type->getName(), 'builtin' => $type->isBuiltin()]; }
    elseif ($type instanceof ReflectionUnionType || $type instanceof ReflectionIntersectionType) {
        $result += ['kind' => $type instanceof ReflectionUnionType ? 'union' : 'intersection', 'members' => array_map('all_api_type', $type->getTypes())];
    } else { $result['kind'] = get_class($type); }
    return $result;
}

function all_api_attributes(Reflector $reflection): array {
    $result = [];
    foreach ($reflection->getAttributes() as $attribute) {
        try { $arguments = all_api_value($attribute->getArguments()); }
        catch (Throwable $error) { $arguments = ['status' => 'UNAVAILABLE', 'error' => all_api_error($error)]; }
        $result[] = all_api_name($attribute->getName()) + ['arguments' => $arguments,
            'target' => $attribute->getTarget(), 'repeated' => $attribute->isRepeated()];
    }
    return $result;
}

function all_api_parameter(ReflectionParameter $parameter): array {
    $default = ['status' => 'NOT_AVAILABLE'];
    try {
        if ($parameter->isDefaultValueAvailable()) {
            $default = ['status' => 'AVAILABLE', 'value' => all_api_value($parameter->getDefaultValue()),
                'is_constant' => $parameter->isDefaultValueConstant()];
            if ($default['is_constant']) { $default['constant_name'] = $parameter->getDefaultValueConstantName(); }
        }
    } catch (Throwable $error) { $default = ['status' => 'UNAVAILABLE', 'error' => all_api_error($error)]; }
    return all_api_name($parameter->getName()) + ['position' => $parameter->getPosition(),
        'type' => all_api_type($parameter->getType()), 'by_reference' => $parameter->isPassedByReference(),
        'can_pass_by_value' => $parameter->canBePassedByValue(), 'variadic' => $parameter->isVariadic(),
        'optional' => $parameter->isOptional(), 'allows_null' => $parameter->allowsNull(),
        'promoted' => $parameter->isPromoted(), 'default' => $default, 'attributes' => all_api_attributes($parameter)];
}

function all_api_callable(ReflectionFunctionAbstract $function): array {
    $result = all_api_name($function->getName()) + [
        'internal' => $function->isInternal(), 'extension' => $function->getExtensionName(),
        'deprecated' => $function->isDeprecated(), 'returns_reference' => $function->returnsReference(),
        'variadic' => $function->isVariadic(), 'parameters' => array_map('all_api_parameter', $function->getParameters()),
        'parameter_count' => $function->getNumberOfParameters(), 'required_parameter_count' => $function->getNumberOfRequiredParameters(),
        'return_type' => all_api_type($function->getReturnType()),
        'tentative_return_type' => $function->hasTentativeReturnType() ? all_api_type($function->getTentativeReturnType()) : null,
        'attributes' => all_api_attributes($function),
    ];
    if ($function instanceof ReflectionMethod) {
        $result += ['declaring_class' => $function->getDeclaringClass()->getName(),
            'public' => $function->isPublic(), 'protected' => $function->isProtected(), 'private' => $function->isPrivate(),
            'static' => $function->isStatic(), 'abstract' => $function->isAbstract(), 'final' => $function->isFinal(),
            'constructor' => $function->isConstructor(), 'destructor' => $function->isDestructor(),
            'modifiers' => $function->getModifiers()];
    }
    return $result;
}

function all_api_class(string $lookupName): array {
    $class = new ReflectionClass($lookupName);
    $methods = [];
    foreach ($class->getMethods() as $method) { $methods[] = all_api_callable($method); }
    usort($methods, static fn(array $a, array $b): int => strcmp($a['name'], $b['name']));
    $constants = [];
    foreach ($class->getReflectionConstants() as $constant) {
        try { $value = ['status' => 'AVAILABLE', 'value' => all_api_value($constant->getValue())]; }
        catch (Throwable $error) { $value = ['status' => 'UNAVAILABLE', 'error' => all_api_error($error)]; }
        $constants[] = all_api_name($constant->getName()) + [
            'declaring_class' => $constant->getDeclaringClass()->getName(),
            'public' => $constant->isPublic(), 'protected' => $constant->isProtected(), 'private' => $constant->isPrivate(),
            'final' => $constant->isFinal(), 'deprecated' => $constant->isDeprecated(),
            'enum_case' => $constant->isEnumCase(), 'type' => all_api_type($constant->getType()),
            'value' => $value, 'attributes' => all_api_attributes($constant)];
    }
    usort($constants, static fn(array $a, array $b): int => strcmp($a['name'], $b['name']));
    $properties = [];
    foreach ($class->getProperties() as $property) {
        $default = ['status' => 'NOT_AVAILABLE'];
        try { if ($property->hasDefaultValue()) { $default = ['status' => 'AVAILABLE', 'value' => all_api_value($property->getDefaultValue())]; } }
        catch (Throwable $error) { $default = ['status' => 'UNAVAILABLE', 'error' => all_api_error($error)]; }
        $properties[] = all_api_name($property->getName()) + ['declaring_class' => $property->getDeclaringClass()->getName(),
            'type' => all_api_type($property->getType()), 'public' => $property->isPublic(),
            'protected' => $property->isProtected(), 'private' => $property->isPrivate(),
            'static' => $property->isStatic(), 'readonly' => $property->isReadOnly(),
            'default' => $default, 'attributes' => all_api_attributes($property)];
    }
    usort($properties, static fn(array $a, array $b): int => strcmp($a['name'], $b['name']));
    $kind = $class->isEnum() ? 'enum' : ($class->isInterface() ? 'interface' : ($class->isTrait() ? 'trait' : 'class'));
    $parent = $class->getParentClass();
    $result = all_api_name($class->getName()) + ['lookup_name' => all_api_name($lookupName), 'kind' => $kind,
        'internal' => $class->isInternal(), 'extension' => $class->getExtensionName(),
        'parent' => $parent === false ? null : $parent->getName(),
        'interfaces' => $class->getInterfaceNames(), 'traits' => $class->getTraitNames(), 'trait_aliases' => $class->getTraitAliases(),
        'abstract' => $class->isAbstract(), 'final' => $class->isFinal(), 'readonly' => $class->isReadOnly(),
        'instantiable' => $class->isInstantiable(), 'cloneable' => $class->isCloneable(), 'modifiers' => $class->getModifiers(),
        'attributes' => all_api_attributes($class), 'methods' => $methods, 'constants' => $constants, 'properties' => $properties];
    if ($class->isEnum()) {
        $enum = new ReflectionEnum($lookupName);
        $result['enum_backing_type'] = all_api_type($enum->getBackingType());
    }
    return $result;
}

if (in_array('--encoding-self-test', $argv, true)) {
    enum ALL_API_EncodingProbe: string { case Binary = "\x00\xff"; }
    $values = ['invalid_utf8' => all_api_value("\x00\xff\x80A"), 'negative_zero' => all_api_value(-0.0),
        'nan' => all_api_value(NAN), 'positive_infinity' => all_api_value(INF), 'negative_infinity' => all_api_value(-INF),
        'int_max' => all_api_value(PHP_INT_MAX), 'enum' => all_api_value(ALL_API_EncodingProbe::Binary),
        'resource' => all_api_value(STDIN), 'object' => all_api_value(new stdClass()),
        'array' => all_api_value([1 => 'integer key', '01' => 'string key']),
        'required_default' => all_api_parameter((new ReflectionFunction('strlen'))->getParameters()[0])['default']];
    echo json_encode(['mode' => 'encoding-self-test-only', 'values' => $values], JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR), "\n";
    exit(0);
}

$inventory = ['schema_version' => '1.0', 'mode' => 'OFFICIAL_ORACLE_REFLECTION_ONLY',
    'candidate_execution' => false, 'target' => ['php_version' => PHP_VERSION, 'php_version_id' => PHP_VERSION_ID,
        'extra_version' => PHP_EXTRA_VERSION, 'zend_version' => zend_version(), 'sapi' => PHP_SAPI,
        'os' => PHP_OS, 'os_family' => PHP_OS_FAMILY, 'uname' => php_uname(), 'zts' => PHP_ZTS,
        'debug' => PHP_DEBUG, 'int_size' => PHP_INT_SIZE, 'binary' => all_api_value(PHP_BINARY),
        'ini_loaded_file' => all_api_value(php_ini_loaded_file()), 'ini_scanned_files' => all_api_value(php_ini_scanned_files())],
    'collection_errors' => [], 'functions' => [], 'types' => [], 'constants' => [], 'ini' => [], 'extensions' => []];
ob_start();
phpinfo(INFO_GENERAL);
$inventory['target']['phpinfo_general'] = all_api_value(ob_get_clean());
$functions = get_defined_functions();
sort($functions['internal'], SORT_STRING);
foreach ($functions['internal'] as $name) {
    try { $reflection = new ReflectionFunction($name); if ($reflection->isInternal()) { $inventory['functions'][] = all_api_callable($reflection); } }
    catch (Throwable $error) { $inventory['collection_errors'][] = ['kind' => 'function', 'symbol' => all_api_name($name), 'error' => all_api_error($error)]; }
}
$declared = array_merge(get_declared_classes(), get_declared_interfaces(), get_declared_traits());
sort($declared, SORT_STRING);
$excludedTypes = [];
foreach ($declared as $name) {
    try {
        if (!(new ReflectionClass($name))->isInternal()) { $excludedTypes[] = all_api_name($name); continue; }
        $inventory['types'][] = all_api_class($name);
    } catch (Throwable $error) { $inventory['collection_errors'][] = ['kind' => 'type', 'symbol' => all_api_name($name), 'error' => all_api_error($error)]; }
}
$constantGroups = get_defined_constants(true);
ksort($constantGroups, SORT_STRING);
foreach ($constantGroups as $group => $constants) {
    if ($group === 'user') { continue; }
    ksort($constants, SORT_STRING);
    foreach ($constants as $name => $value) {
        try {
            $reflection = new ReflectionConstant($name);
            $inventory['constants'][] = all_api_name($name) + ['group' => $group,
                'extension' => $reflection->getExtensionName(), 'deprecated' => $reflection->isDeprecated(),
                'value' => all_api_value($value), 'attributes' => all_api_attributes($reflection)];
        } catch (Throwable $error) { $inventory['collection_errors'][] = ['kind' => 'constant', 'symbol' => all_api_name($name), 'error' => all_api_error($error), 'value' => all_api_value($value)]; }
    }
}
$iniOwners = [];
$extensionNames = array_values(array_unique(array_merge(get_loaded_extensions(false), get_loaded_extensions(true))));
sort($extensionNames, SORT_STRING);
foreach ($extensionNames as $name) {
    try {
        $extension = new ReflectionExtension($name);
        $entries = $extension->getINIEntries();
        foreach ($entries as $iniName => $_) { $iniOwners[$iniName][] = $name; }
        $inventory['extensions'][] = all_api_name($name) + ['version' => $extension->getVersion(),
            'dependencies' => $extension->getDependencies(), 'persistent' => $extension->isPersistent(),
            'temporary' => $extension->isTemporary(), 'ini_names' => array_keys($entries)];
    } catch (Throwable $error) { $inventory['collection_errors'][] = ['kind' => 'extension', 'symbol' => all_api_name($name), 'error' => all_api_error($error)]; }
}
$ini = ini_get_all(null, true);
ksort($ini, SORT_STRING);
foreach ($ini as $name => $entry) {
    $inventory['ini'][] = all_api_name($name) + ['extensions' => $iniOwners[$name] ?? [],
        'profile_startup_global_value' => all_api_value($entry['global_value']),
        'current_local_value' => all_api_value($entry['local_value']), 'access' => $entry['access'],
        'factory_default' => ['status' => 'UNMEASURED', 'reason' => 'global_value_is_profile_startup_after_command_line_overrides']];
}
$inventory['exclusions'] = ['rule' => 'Only Reflection isInternal entities; no user constants; no worker helpers in target API',
    'user_functions_excluded' => array_map('all_api_name', $functions['user']), 'user_types_excluded' => $excludedTypes,
    'user_constants_excluded' => array_map('all_api_name', array_keys($constantGroups['user'] ?? []))];
$inventory['warnings_during_worker'] = $GLOBALS['all_api_warnings'];
echo json_encode($inventory, JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR), "\n";
