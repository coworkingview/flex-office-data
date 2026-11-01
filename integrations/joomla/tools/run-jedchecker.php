<?php

/**
 * Run the installed com_jedchecker rules against one extension zip.
 *
 * Boots the Joomla CLI application, extracts the zip the same way
 * JedcheckerControllerUploads does (tmp/jed_checker/unzipped/<archive>),
 * then calls check() on every installed rule class.
 *
 * This file is not part of the installable module.
 *
 * Usage: JOOMLA_BASE=/path/to/joomla php tools/run-jedchecker.php <zip> <report.html>
 */

const _JEXEC = 1;

if ($argc < 3) {
    fwrite(STDERR, "usage: php run-jedchecker.php <zip> <report.html>\n");
    exit(2);
}

$zip = $argv[1];
$out = $argv[2];

if (!is_file($zip)) {
    fwrite(STDERR, "zip not found: {$zip}\n");
    exit(2);
}

$joomlaBase = getenv('JOOMLA_BASE');

if ($joomlaBase === false || $joomlaBase === '') {
    fwrite(STDERR, "JOOMLA_BASE is not set\n");
    exit(2);
}

define('JPATH_BASE', $joomlaBase);
require JPATH_BASE . '/includes/defines.php';
require JPATH_BASE . '/includes/framework.php';

$container = Joomla\CMS\Factory::getContainer();
$container->alias('session', 'session.cli')
    ->alias('JSession', 'session.cli')
    ->alias(Joomla\CMS\Session\Session::class, 'session.cli')
    ->alias(Joomla\Session\Session::class, 'session.cli')
    ->alias(Joomla\Session\SessionInterface::class, 'session.cli');

$app = $container->get(Joomla\Console\Application::class);
Joomla\CMS\Factory::$application = $app;

if (!defined('JPATH_COMPONENT_ADMINISTRATOR')) {
    define('JPATH_COMPONENT_ADMINISTRATOR', JPATH_ADMINISTRATOR . '/components/com_jedchecker');
}

if (!defined('JPATH_COMPONENT')) {
    define('JPATH_COMPONENT', JPATH_COMPONENT_ADMINISTRATOR);
}

$language = Joomla\CMS\Factory::getLanguage();
$language->load('com_jedchecker', JPATH_ADMINISTRATOR);
$language->load('com_jedchecker.sys', JPATH_ADMINISTRATOR);

$tmp = Joomla\CMS\Factory::getConfig()->get('tmp_path');
$unzipped = $tmp . '/jed_checker/unzipped';
Joomla\CMS\Filesystem\Folder::create($unzipped);

$archiveName = strtolower(basename($zip));
$destination = $unzipped . '/' . $archiveName;

if (is_dir($destination)) {
    Joomla\CMS\Filesystem\Folder::delete($destination);
}

$archive = new Joomla\Archive\Archive();

if (!$archive->extract($zip, $destination)) {
    fwrite(STDERR, "extract failed\n");
    exit(1);
}

JLoader::discover('jedcheckerRules', JPATH_COMPONENT_ADMINISTRATOR . '/libraries/rules/');

$files = Joomla\CMS\Filesystem\Folder::files(
    JPATH_COMPONENT_ADMINISTRATOR . '/libraries/rules',
    '\.php$',
    false,
    false
);
$rules = array();

foreach ($files as $file) {
    $rule = substr($file, 0, -4);
    $class = 'jedcheckerRules' . ucfirst($rule);

    if (class_exists($class) && is_subclass_of($class, 'JEDcheckerRule')) {
        $rules[$rule] = $class::$ordering;
    }
}

asort($rules, SORT_NUMERIC);

$sections = array();
$summaryLines = array();
$verbatim = array();
$totals = array(
    'error' => 0,
    'warning' => 0,
    'compatibility' => 0,
    'notice' => 0,
    'info' => 0,
    'passed' => 0,
);

foreach ($rules as $rule => $ordering) {
    $class = 'jedcheckerRules' . ucfirst($rule);
    $police = new $class(array('basedir' => Joomla\CMS\Filesystem\Path::clean($destination)));
    $police->check();
    $report = $police->get('report');
    $html = $report->getHTML();

    $property = new ReflectionProperty($report, 'data');
    $property->setAccessible(true);
    $data = $property->getValue($report);
    $count = $data['count'];

    $summaryLines[] = sprintf(
        '%s errors=%d warnings=%d compatibility=%d notices=%d info=%d passed=%d',
        $rule,
        $count->error,
        $count->warning,
        $count->compatibility,
        $count->notice,
        $count->info,
        $count->passed
    );

    foreach ($totals as $level => $value) {
        $totals[$level] += $count->$level;
    }

    foreach (array_keys($totals) as $level) {
        foreach ($data[$level] as $item) {
            $verbatim[] = strtoupper($level)
                . ($item->subtype !== '' ? ' ' . $item->subtype : '')
                . ' ' . $rule
                . ' ' . $item->location
                . ($item->line !== null ? ' line ' . $item->line : '')
                . "\n" . (string) $item->text;
        }
    }

    $sections[] = '<section id="' . htmlspecialchars($rule, ENT_QUOTES, 'UTF-8') . '"><h2>'
        . htmlspecialchars($rule, ENT_QUOTES, 'UTF-8') . '</h2>' . $html . '</section>';
}

$checkerVersion = 'unknown';
$installedXml = JPATH_ADMINISTRATOR . '/components/com_jedchecker/jedchecker.xml';

if (is_file($installedXml)) {
    $xml = simplexml_load_file($installedXml);

    if ($xml && isset($xml->version)) {
        $checkerVersion = (string) $xml->version;
    }
}

$joomlaVersion = Joomla\CMS\Version::MAJOR_VERSION . '.'
    . Joomla\CMS\Version::MINOR_VERSION . '.'
    . Joomla\CMS\Version::PATCH_VERSION;

$summary = implode("\n", $summaryLines) . "\n\n"
    . 'TOTAL errors=' . $totals['error']
    . ' warnings=' . $totals['warning']
    . ' compatibility=' . $totals['compatibility']
    . ' notices=' . $totals['notice']
    . ' info=' . $totals['info']
    . ' passed=' . $totals['passed'] . "\n";
$verbatimBlock = $verbatim === array() ? '' : "\n" . implode("\n\n", $verbatim) . "\n";

$preamble = '<p>JED Checker ' . htmlspecialchars($checkerVersion, ENT_QUOTES, 'UTF-8')
    . ' on Joomla ' . htmlspecialchars($joomlaVersion, ENT_QUOTES, 'UTF-8')
    . ', PHP ' . htmlspecialchars(PHP_VERSION, ENT_QUOTES, 'UTF-8')
    . '. Package: ' . htmlspecialchars(basename($zip), ENT_QUOTES, 'UTF-8')
    . '. Extracted to tmp/jed_checker/unzipped/' . htmlspecialchars($archiveName, ENT_QUOTES, 'UTF-8')
    . ' by Joomla\\Archive\\Archive, then each installed rule class check() was called. '
    . 'The sections below are the HTML returned by JEDcheckerReport::getHTML(). '
    . 'The preformatted block is the same report object: one line of counters per rule, then each issue text as stored.</p>'
    . '<pre>' . htmlspecialchars($summary, ENT_QUOTES, 'UTF-8') . $verbatimBlock . '</pre>';

$document = '<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><title>JED Checker report</title>'
    . '<style>body{font-family:Georgia,serif;max-width:960px;margin:2rem auto;color:#1c1c1c}'
    . 'pre{white-space:pre-wrap}.alert{border:1px solid #ccc;padding:.6rem .8rem;margin:.4rem 0}</style></head><body>'
    . $preamble . implode('', $sections) . '</body></html>';

file_put_contents($out, $document);

fwrite(STDOUT, $summary . $verbatimBlock);

exit($totals['error'] > 0 ? 1 : 0);
