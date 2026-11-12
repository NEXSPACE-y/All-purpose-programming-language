<?php
declare(strict_types=1);
function all_abi_strict_call($callable, array $args, bool $frameless) {
    return $frameless ? dl_test_frameless($args[0]) : $callable(...$args);
}
