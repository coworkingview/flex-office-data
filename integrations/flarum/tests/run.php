<?php

declare(strict_types=1);

$failed = 0;

function check(bool $condition, string $message): void
{
    global $failed;
    if ($condition) {
        echo "ok  $message\n";

        return;
    }
    echo "FAIL $message\n";
    $failed++;
}

spl_autoload_register(static function (string $class): void {
    $prefix = 'CoworkingView\\CoworkingPrices\\';
    if (!str_starts_with($class, $prefix)) {
        return;
    }
    $path = dirname(__DIR__) . '/src/' . str_replace('\\', '/', substr($class, strlen($prefix))) . '.php';
    if (is_file($path)) {
        require $path;
    }
});

require __DIR__ . '/parser_test.php';
require __DIR__ . '/client_test.php';
require __DIR__ . '/card_test.php';

if ($failed > 0) {
    fwrite(STDERR, $failed . " failed\n");
    exit(1);
}

echo "all passed\n";
