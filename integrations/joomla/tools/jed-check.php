<?php

/**
 * Checks the module against the JED Checker rules that apply to this package.
 *
 * The expressions for the GPL header and the _JEXEC guard match
 * joomla-extensions/jedchecker (GplRule and JexecRule). The full JED Checker
 * component runs inside a Joomla site; this script covers the same rules for
 * a site module without installing one.
 *
 * This file is not part of the installable module.
 */

declare(strict_types=1);

$root = dirname(__DIR__);
$module = $root . '/mod_coworkingview';
$errors = [];

function fail(string $message): void
{
    global $errors;
    $errors[] = $message;
}

function phpFiles(string $directory): array
{
    $files = [];
    $iterator = new RecursiveIteratorIterator(new RecursiveDirectoryIterator($directory));

    foreach ($iterator as $file) {
        if ($file->isFile() && $file->getExtension() === 'php') {
            $files[] = $file->getPathname();
        }
    }

    sort($files);

    return $files;
}

$defines = ['_JEXEC', 'JPATH_PLATFORM', 'JPATH_BASE', 'AKEEBAENGINE', 'WF_EDITOR'];

foreach ($defines as $index => $define) {
    $defines[$index] = preg_quote($define, '#');
}

$useSingle = '[0-9A-Za-z_\\\\]+(?: as [0-9A-Za-z_]+?)? ?';
$useGroup  = '[0-9A-Za-z_\\\\]+\\\\\\{ ?' . $useSingle . '(?:, ?' . $useSingle . ' ?)*\\} ?';
$useNs     = '(?:' . $useSingle . '|' . $useGroup . ')(?:, ?(?:' . $useSingle . '|' . $useGroup . '))*';
$jexec     = '#^\s*'
    . '<\?php\s+'
    . '(?:declare ?\(strict_types ?= ?1 ?\) ?; ?)?'
    . '(?:namespace [0-9A-Za-z_\\\\]+ ?; ?)?'
    . '(?:use (?:function |const )?' . $useNs . '; ?)*'
    . '\\\\?defined ?\( ?'
    . '([\'"])(?:' . implode('|', $defines) . ')\1'
    . ' ?\) ?(?:or |\|\| ?)(?:die|exit)\b'
    . '#i';

foreach (phpFiles($module) as $file) {
    $relative = substr($file, strlen($root) + 1);
    $raw      = (string) file_get_contents($file);

    if (str_starts_with($raw, "\xEF\xBB\xBF")) {
        fail("{$relative} starts with a BOM");
    }

    if ($raw === '' || preg_match('/\A\s/', $raw) === 1) {
        fail("{$relative} has leading whitespace");
    }

    if (!str_starts_with($raw, '<?php')) {
        fail("{$relative} does not start with <?php");
    }

    if (!str_contains($raw, 'GNU General Public License')) {
        fail("{$relative} is missing the GPL header");
    }

    $stripped = php_strip_whitespace($file);

    if (!preg_match($jexec, $stripped)) {
        fail("{$relative} is missing defined('_JEXEC') or die");
    }

    if (preg_match('/<\?(?!php|=)/', $raw) === 1) {
        fail("{$relative} uses a short PHP open tag");
    }

    if (preg_match('/\berror_reporting\s*\(/', $raw) === 1) {
        fail("{$relative} calls error_reporting");
    }

    foreach (['eval', 'base64_decode', 'gzinflate', 'shell_exec', 'assert', 'passthru', 'proc_open'] as $forbidden) {
        if (preg_match('/\b' . $forbidden . '\s*\(/', $raw) === 1) {
            fail("{$relative} calls {$forbidden}");
        }
    }

    if (preg_match('/\$_(GET|POST|REQUEST|COOKIE)\b/', $raw) === 1) {
        fail("{$relative} reads a request superglobal");
    }
}

$manifestPath = $module . '/mod_coworkingview.xml';
$manifest     = simplexml_load_file($manifestPath);

if ($manifest === false) {
    fail('manifest is not valid XML');
} else {
    if ((string) $manifest['type'] !== 'module' || (string) $manifest['client'] !== 'site') {
        fail('manifest must be a site module');
    }

    if ((string) $manifest['method'] !== 'upgrade') {
        fail('manifest method must be upgrade');
    }

    if ((string) $manifest->name !== 'CoworkingView Workspace Prices') {
        fail('manifest name must be CoworkingView Workspace Prices');
    }

    if (stripos((string) $manifest->name, 'joomla') !== false) {
        fail('manifest name must not contain Joomla');
    }

    if ((string) $manifest->version !== '1.0.0') {
        fail('manifest version must be 1.0.0');
    }

    $licence = (string) $manifest->licence;

    if ($licence === '' || (stripos($licence, 'gpl') === false && stripos($licence, 'general public licence') === false)) {
        fail('manifest licence tag must name the GPL');
    }

    if (stripos((string) $manifest->license, 'general public license') === false) {
        fail('manifest license tag must name the GPL for the installer');
    }

    $server = (string) $manifest->updateservers->server;

    if (stripos($server, 'http') !== 0 || !str_contains($server, 'mod_coworkingview.xml')) {
        fail('update server is missing');
    }

    if (!str_contains((string) $manifest->changelogurl, 'changelog.xml')) {
        fail('changelog url is missing');
    }

    $element = '';

    foreach ($manifest->files->children() as $child) {
        if (isset($child['module'])) {
            $element = (string) $child['module'];
        }
    }

    if ($element !== 'mod_coworkingview') {
        fail('module element must be mod_coworkingview');
    }

    if ((string) $manifest->namespace !== 'CoworkingView\\Module\\CoworkingView') {
        fail('namespace is missing');
    }

    if ((string) $manifest->authorUrl !== 'https://coworkingview.com') {
        fail('author URL must be https://coworkingview.com');
    }
}

$license = (string) file_get_contents($module . '/LICENSE.txt');

if (!str_contains($license, 'GNU GENERAL PUBLIC LICENSE')) {
    fail('LICENSE.txt is not the GPL');
}

$helper = (string) file_get_contents($module . '/src/Helper/CoworkingViewHelper.php');

if (!str_contains($helper, "const VERSION = '1.0.0'")) {
    fail('helper version does not match 1.0.0');
}

if (!str_contains($helper, 'https://api.coworkingview.com')) {
    fail('helper must call the public API');
}

$iniSets = [];

foreach (['en-GB', 'de-DE', 'es-ES'] as $tag) {
    foreach (['mod_coworkingview.ini', 'mod_coworkingview.sys.ini'] as $name) {
        $path = $module . '/language/' . $tag . '/' . $name;

        if (!is_file($path)) {
            fail("missing {$tag}/{$name}");
            continue;
        }

        $text = (string) file_get_contents($path);

        if (str_contains($text, "\r") || str_contains($text, "\xEF\xBB\xBF")) {
            fail("{$tag}/{$name} has a BOM or CR");
        }

        $keys = [];

        foreach (file($path) as $number => $line) {
            $trimmed = rtrim($line, "\n");

            if ($trimmed === '' || str_starts_with(ltrim($trimmed), ';')) {
                continue;
            }

            if (str_starts_with(ltrim($trimmed), '#')) {
                fail("{$tag}/{$name}:" . ($number + 1) . ' uses a hash comment');
                continue;
            }

            $parts = explode('=', $trimmed, 2);

            if (count($parts) !== 2 || trim($parts[0]) === '' || preg_match('/\s/', rtrim($parts[0])) === 1) {
                fail("{$tag}/{$name}:" . ($number + 1) . ' is not KEY="value"');
                continue;
            }

            $key = rtrim($parts[0]);

            if ($key !== strtoupper($key)) {
                fail("{$tag}/{$name} key {$key} is not uppercase");
            }

            if (isset($keys[$key])) {
                fail("{$tag}/{$name} duplicates {$key}");
            }

            $keys[$key] = true;

            if (!preg_match('/^"(?:[^"\\\\]|\\\\.)*"\s*$/', ltrim($parts[1]))) {
                fail("{$tag}/{$name} {$key} value is not a double-quoted string");
            }
        }

        if (parse_ini_file($path) === false) {
            fail("{$tag}/{$name} does not parse");
        }

        $iniSets[$tag . '/' . $name] = $keys;
    }
}

$enKeys = array_keys($iniSets['en-GB/mod_coworkingview.ini'] ?? []);
sort($enKeys);

foreach (['de-DE', 'es-ES'] as $tag) {
    $keys = array_keys($iniSets[$tag . '/mod_coworkingview.ini'] ?? []);
    sort($keys);

    if ($keys !== $enKeys) {
        fail("{$tag} ini keys differ from en-GB");
    }
}

foreach (['en-GB', 'de-DE', 'es-ES'] as $tag) {
    $parsed = parse_ini_file($module . '/language/' . $tag . '/mod_coworkingview.ini');

    if (($parsed['MOD_COWORKINGVIEW_ATTRIBUTION'] ?? '') !== 'Data: CoworkingView') {
        fail("{$tag} attribution link text must be Data: CoworkingView");
    }
}

$languageKeys = $iniSets['en-GB/mod_coworkingview.ini'] + $iniSets['en-GB/mod_coworkingview.sys.ini'];
$used         = [];

foreach (phpFiles($module) as $file) {
    $raw = (string) file_get_contents($file);

    if (preg_match_all('/\bText::(?:_|sprintf)\(\s*\'([^\']+)\'/', $raw, $matches)) {
        foreach ($matches[1] as $key) {
            $used[$key] = true;
        }
    }
}

if ($manifest !== false) {
    $xml = (string) file_get_contents($manifestPath);

    if (preg_match_all('/\b(MOD_[A-Z0-9_]+)\b/', $xml, $matches)) {
        foreach ($matches[1] as $key) {
            $used[$key] = true;
        }
    }
}

foreach (array_keys($used) as $key) {
    if (!isset($languageKeys[$key])) {
        fail("language key {$key} is missing from en-GB");
    }
}

$tree = new RecursiveIteratorIterator(new RecursiveDirectoryIterator($module));

foreach ($tree as $file) {
    if (!$file->isFile()) {
        continue;
    }

    $name = $file->getFilename();

    if (preg_match('/\.(sh|exe|bat|cmd|dll|so)$/i', $name) === 1) {
        fail('packaged file is not allowed: ' . $name);
    }

    if (str_contains($file->getPathname(), 'www.coworkingview.com')) {
        fail('www host found in ' . $name);
    }
}

$blob = '';

foreach (phpFiles($module) as $file) {
    $blob .= (string) file_get_contents($file);
}

$blob .= (string) file_get_contents($manifestPath);

foreach (['en-GB', 'de-DE', 'es-ES'] as $tag) {
    $blob .= (string) file_get_contents($module . '/language/' . $tag . '/mod_coworkingview.ini');
}

if (str_contains($blob, 'www.coworkingview.com')) {
    fail('module text uses www.coworkingview.com');
}

$update = simplexml_load_file($root . '/updates/mod_coworkingview.xml');
$changelog = simplexml_load_file($root . '/updates/changelog.xml');

if ($update === false || (string) $update->update->version !== '1.0.0') {
    fail('update stream version must be 1.0.0');
}

if ($update !== false) {
    if ((string) $update->update->element !== 'mod_coworkingview' || (string) $update->update->type !== 'module') {
        fail('update stream element must be the site module');
    }

    if ((string) $update->update->name !== 'CoworkingView Workspace Prices') {
        fail('update stream name must match the listing name');
    }

    $download = (string) $update->update->downloads->downloadurl;

    if (!str_contains($download, '/releases/download/joomla-v1.0.0/mod_coworkingview-1.0.0.zip')) {
        fail('update stream must point at the joomla-v1.0.0 release zip');
    }
}

if ($changelog === false || (string) $changelog->changelog->version !== '1.0.0') {
    fail('changelog version must be 1.0.0');
}

$zipPath = null;

foreach ($argv as $arg) {
    if (str_starts_with($arg, '--zip=')) {
        $zipPath = substr($arg, 6);
    }
}

if ($zipPath !== null) {
    $zip = new ZipArchive();

    if ($zip->open($zipPath) !== true) {
        fail('cannot open zip');
    } else {
        $names = [];

        for ($index = 0; $index < $zip->numFiles; $index++) {
            $names[] = (string) $zip->getNameIndex($index);
        }

        $zip->close();

        if (!in_array('mod_coworkingview.xml', $names, true)) {
            fail('zip must contain mod_coworkingview.xml at its root');
        }

        if (!in_array('LICENSE.txt', $names, true) || !in_array('services/provider.php', $names, true)) {
            fail('zip is missing LICENSE.txt or the service provider');
        }

        foreach ($names as $name) {
            if (str_contains($name, '..') || str_starts_with($name, '/') || str_starts_with($name, 'mod_coworkingview/')) {
                fail('zip path is nested or unsafe: ' . $name);
            }

            if (preg_match('/\.(sh|exe)$/i', $name) === 1) {
                fail('zip contains an executable: ' . $name);
            }
        }
    }
}

if ($errors !== []) {
    fwrite(STDERR, implode("\n", $errors) . "\n");
    exit(1);
}

echo "jed checks passed\n";
