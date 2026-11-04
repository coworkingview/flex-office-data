<?php

declare(strict_types=1);

/*
 * CoworkingView Workplace plugin for Kimai.
 * Copyright (c) 2026 CoworkingView
 * SPDX-License-Identifier: MIT
 *
 * Checks the layout Kimai loads from var/plugins/CoworkingViewBundle/.
 * Kimai's kernel requires a *Bundle directory, the class
 * KimaiPlugin\<Bundle>\<Bundle>, PluginInterface, and composer.json
 * extra.kimai.require / extra.kimai.name.
 */

$root = dirname(__DIR__);
$errors = [];

$fail = static function (string $message) use (&$errors): void {
    $errors[] = $message;
};

$composerPath = $root . '/composer.json';
$composer = json_decode((string) file_get_contents($composerPath), true);
if (!is_array($composer)) {
    fwrite(STDERR, "composer.json is not valid JSON\n");
    exit(1);
}

$expect = static function (bool $condition, string $message) use ($fail): void {
    if (!$condition) {
        $fail($message);
    }
};

$expect(($composer['name'] ?? null) === 'coworkingview/workplace', 'composer name must be coworkingview/workplace');
$expect(($composer['type'] ?? null) === 'kimai-plugin', 'composer type must be kimai-plugin');
$expect(($composer['homepage'] ?? null) === 'https://coworkingview.com', 'composer homepage must be https://coworkingview.com');
$expect(($composer['license'] ?? null) === 'MIT', 'composer license must be MIT');
$expect(is_string($composer['version'] ?? null) && preg_match('/^\d+\.\d+\.\d+$/', $composer['version']) === 1, 'composer version must be a dotted version');
$expect(($composer['require']['php'] ?? null) === '>=8.2', 'composer require.php must be >=8.2');

$author = $composer['authors'][0] ?? null;
$expect(is_array($author), 'composer authors must list CoworkingView');
$expect(($author['name'] ?? null) === 'CoworkingView', 'author name must be CoworkingView');
$expect(($author['email'] ?? null) === 'info@coworkingview.com', 'author email must be info@coworkingview.com');
$expect(($author['homepage'] ?? null) === 'https://coworkingview.com', 'author homepage must be https://coworkingview.com');

$kimai = $composer['extra']['kimai'] ?? null;
$expect(is_array($kimai), 'extra.kimai is required');
$expect(is_int($kimai['require'] ?? null), 'extra.kimai.require must be an integer (major * 10000 + minor * 100 + patch)');
$expect(($kimai['require'] ?? 0) >= 20000, 'extra.kimai.require must target Kimai 2');
$expect(is_string($kimai['name'] ?? null) && $kimai['name'] !== '', 'extra.kimai.name must be a non-empty string');

$required = [
    'CoworkingViewBundle.php',
    'DependencyInjection/CoworkingViewExtension.php',
    'Resources/config/services.yaml',
    'Resources/config/routes.yaml',
    'Resources/translations/messages.en.xlf',
    'Resources/views/report/workplace.html.twig',
    'EventSubscriber/WorkplaceMetaSubscriber.php',
    'EventSubscriber/ReportingSubscriber.php',
    'Controller/WorkplaceReportController.php',
    'LICENSE',
    'README.md',
    'CHANGELOG.md',
];
foreach ($required as $relative) {
    $expect(is_file($root . '/' . $relative), 'missing ' . $relative);
}

$bundle = (string) file_get_contents($root . '/CoworkingViewBundle.php');
$expect(str_contains($bundle, 'namespace KimaiPlugin\\CoworkingViewBundle;'), 'bundle namespace must be KimaiPlugin\\CoworkingViewBundle');
$expect(str_contains($bundle, 'class CoworkingViewBundle extends Bundle implements PluginInterface'), 'bundle class must extend Bundle and implement PluginInterface');

$extension = (string) file_get_contents($root . '/DependencyInjection/CoworkingViewExtension.php');
$expect(str_contains($extension, 'namespace KimaiPlugin\\CoworkingViewBundle\\DependencyInjection;'), 'extension namespace');
$expect(str_contains($extension, 'class CoworkingViewExtension extends Extension'), 'extension class name must follow the bundle name');
$expect(str_contains($extension, "load('services.yaml')"), 'extension must load services.yaml');

$services = (string) file_get_contents($root . '/Resources/config/services.yaml');
$expect(str_contains($services, 'KimaiPlugin\\CoworkingViewBundle\\'), 'services.yaml must register the plugin namespace');
$expect(str_contains($services, 'autowire: true'), 'services must autowire');

$routes = (string) file_get_contents($root . '/Resources/config/routes.yaml');
$expect(str_contains($routes, 'prefix: /{_locale}'), 'routes must use the Kimai locale prefix');
$expect(str_contains($routes, '@CoworkingViewBundle/Controller/'), 'routes must load the controller directory');
$expect(str_contains($routes, 'type: attribute'), 'routes must use PHP attributes');

$controller = (string) file_get_contents($root . '/Controller/WorkplaceReportController.php');
$subscriber = (string) file_get_contents($root . '/EventSubscriber/ReportingSubscriber.php');
$expect(str_contains($controller, "name: 'coworkingview_workplace_report'"), 'controller route name');
$expect(str_contains($subscriber, "'coworkingview_workplace_report'"), 'report route must match the controller');
$expect(str_contains($controller, "IsGranted('view_reporting')"), 'report must require view_reporting');

$translation = (string) file_get_contents($root . '/Resources/translations/messages.en.xlf');
$xml = simplexml_load_string($translation);
$expect($xml !== false, 'messages.en.xlf must be well-formed XML');
foreach ([
    'coworkingview.workplace',
    'coworkingview.home',
    'coworkingview.office',
    'coworkingview.coworking',
    'coworkingview.unset',
    'coworkingview.report_title',
] as $key) {
    $expect(str_contains($translation, $key), 'English translation missing ' . $key);
}

$readme = (string) file_get_contents($root . '/README.md');
$expect(str_contains($readme, 'https://coworkingview.com'), 'README must link to the homepage');
$expect(str_contains($readme, 'https://coworkingview.com/en/tools/price-index'), 'README must link to the Price Index');
$expect(preg_match('/var\/plugins\/CoworkingViewBundle/', $readme) === 1, 'README must document the plugin directory name');

$pricePattern = '/(?:€|£|\$)\s*\d|\b\d+(?:[.,]\d{2})\s*(?:EUR|USD|GBP)\b|\b(?:EUR|USD|GBP)\s*\d/';
$prose = [$root . '/README.md', $root . '/CHANGELOG.md'];
$store = $root . '/store-listing';
if (is_dir($store)) {
    $iterator = new RecursiveIteratorIterator(new RecursiveDirectoryIterator($store, FilesystemIterator::SKIP_DOTS));
    foreach ($iterator as $file) {
        if ($file->isFile()) {
            $prose[] = $file->getPathname();
        }
    }
}
foreach ($prose as $path) {
    $text = (string) file_get_contents($path);
    $expect(preg_match($pricePattern, $text) !== 1, 'price figure found in ' . substr($path, strlen($root) + 1));
}

$phpFiles = new RecursiveIteratorIterator(new RecursiveDirectoryIterator($root, FilesystemIterator::SKIP_DOTS));
foreach ($phpFiles as $file) {
    if (!$file->isFile() || $file->getExtension() !== 'php') {
        continue;
    }
    $relative = substr($file->getPathname(), strlen($root) + 1);
    if (str_starts_with($relative, 'vendor/') || str_starts_with($relative, 'store-listing/')) {
        continue;
    }
    $contents = (string) file_get_contents($file->getPathname());
    $expect(str_contains($contents, 'declare(strict_types=1);'), $relative . ' must declare strict types');

    if (str_starts_with($relative, 'tests/') || str_starts_with($relative, 'bin/')) {
        continue;
    }

    $namespace = 'KimaiPlugin\\CoworkingViewBundle';
    $directory = dirname($relative);
    if ($directory !== '.') {
        $namespace .= '\\' . str_replace('/', '\\', $directory);
    }
    $expect(str_contains($contents, 'namespace ' . $namespace . ';'), $relative . ' namespace must be ' . $namespace);
}

if ($errors !== []) {
    fwrite(STDERR, "Kimai bundle structure check failed:\n");
    foreach ($errors as $error) {
        fwrite(STDERR, ' - ' . $error . "\n");
    }
    exit(1);
}

fwrite(STDOUT, "Kimai bundle structure check passed\n");
