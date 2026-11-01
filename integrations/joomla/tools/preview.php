<?php

/**
 * Renders tmpl/default.php with a live Price Index response.
 *
 * Not part of the installable module. Used by php -S and tools/capture.sh.
 */

declare(strict_types=1);

namespace Joomla\CMS\Language {
    /**
     * Stand-in for the CMS language class. Strings come from the module ini file.
     */
    class Text
    {
        /**
         * Translate one key.
         *
         * @param   string  $string  Language key.
         *
         * @return  string
         */
        public static function _($string)
        {
            $strings = $GLOBALS['mod_coworkingview_strings'] ?? [];

            return $strings[$string] ?? $string;
        }

        /**
         * Translate a key and substitute arguments.
         *
         * @param   string  $string  Language key.
         * @param   mixed   ...$args  Values for %s.
         *
         * @return  string
         */
        public static function sprintf($string, ...$args)
        {
            return vsprintf((string) self::_($string), $args);
        }
    }
}

namespace {
    use CoworkingView\Module\CoworkingView\Site\Helper\RatesParser;

    define('_JEXEC', 1);

    require dirname(__DIR__) . '/mod_coworkingview/src/Helper/RatesParser.php';

    /**
     * GET /v1/market/rates for one city. One retry on 429 or 5xx.
     *
     * @param   string  $locale  en, de, or es.
     * @param   string  $city    City slug.
     *
     * @return  array<mixed>|null
     */
    function preview_fetch(string $locale, string $city): ?array
    {
        $url = 'https://api.coworkingview.com/v1/market/rates?' . http_build_query(
            ['locale' => $locale, 'city' => $city],
            '',
            '&',
            PHP_QUERY_RFC3986
        );

        for ($attempt = 0; $attempt < 2; $attempt++) {
            $handle = curl_init($url);

            if ($handle === false) {
                return null;
            }

            curl_setopt_array($handle, [
                CURLOPT_RETURNTRANSFER => true,
                CURLOPT_TIMEOUT => 20,
                CURLOPT_HTTPHEADER => [
                    'Accept: application/json',
                    'User-Agent: mod_coworkingview/1.0.0 (+https://github.com/coworkingview/flex-office-data)',
                ],
            ]);

            $body = curl_exec($handle);
            $status = (int) curl_getinfo($handle, CURLINFO_RESPONSE_CODE);
            curl_close($handle);

            if (($status === 429 || $status >= 500) && $attempt === 0) {
                sleep(2);
                continue;
            }

            if ($status < 200 || $status >= 300 || !is_string($body)) {
                return null;
            }

            $decoded = json_decode($body, true);

            return is_array($decoded) ? $decoded : null;
        }

        return null;
    }

    $shot = 'en';

    if (PHP_SAPI !== 'cli' && isset($_GET['shot']) && is_string($_GET['shot'])) {
        $shot = $_GET['shot'];
    }

    $shots = [
        'en' => [
            'tag' => 'en-GB',
            'locale' => 'en',
            'product' => '',
            'count' => 6,
            'page' => 'Example site',
            'articleTitle' => 'A week in Berlin',
            'article' => 'Indicative prices for flexible workspace, shown in the sidebar. The figures are medians from the CoworkingView Price Index.',
        ],
        'de' => [
            'tag' => 'de-DE',
            'locale' => 'de',
            'product' => 'private_office',
            'count' => 6,
            'page' => 'Beispielseite',
            'articleTitle' => 'Eine Woche in Berlin',
            'article' => 'Richtpreis für ein privates Büro. Die Zahl ist der Median aus dem CoworkingView Price Index.',
        ],
    ];

    if (!isset($shots[$shot])) {
        $shot = 'en';
    }

    $choice = $shots[$shot];
    $ini = dirname(__DIR__) . '/mod_coworkingview/language/' . $choice['tag'] . '/mod_coworkingview.ini';
    $GLOBALS['mod_coworkingview_strings'] = parse_ini_file($ini) ?: [];
    $payload = preview_fetch($choice['locale'], 'berlin');
    $parsed = $payload === null
        ? RatesParser::failure('unavailable')
        : RatesParser::parse($payload, 'berlin');
    $snapshot = RatesParser::select($parsed, $choice['product'], $choice['count']);
    $logoFile = dirname(__DIR__) . '/mod_coworkingview/media/images/logo.png';
    $logoUrl = 'data:image/png;base64,' . base64_encode((string) file_get_contents($logoFile));
    $module = (object) ['id' => 17];
    $css = (string) file_get_contents(dirname(__DIR__) . '/mod_coworkingview/media/css/mod_coworkingview.css');

    ob_start();
    include dirname(__DIR__) . '/mod_coworkingview/tmpl/default.php';
    $moduleHtml = (string) ob_get_clean();

    $page = htmlspecialchars($choice['page'], ENT_QUOTES, 'UTF-8');
    $articleTitle = htmlspecialchars($choice['articleTitle'], ENT_QUOTES, 'UTF-8');
    $article = htmlspecialchars($choice['article'], ENT_QUOTES, 'UTF-8');
    $lang = $choice['locale'] === 'de' ? 'de' : 'en';

    if (!headers_sent()) {
        header('Content-Type: text/html; charset=UTF-8');
    }

    echo '<!DOCTYPE html>';
    echo '<html lang="' . $lang . '"><head><meta charset="utf-8">';
    echo '<meta name="viewport" content="width=1280">';
    echo '<title>' . $page . '</title><style>';
    echo 'html,body{margin:0;background:#f3efe7;color:#1c1c1c;font-family:Georgia,"Iowan Old Style",serif;}';
    echo '.page{width:1280px;min-height:800px;margin:0 auto;}';
    echo '.page__bar{display:flex;align-items:center;height:64px;padding:0 40px;background:#1c1c1c;color:#f3efe7;';
    echo 'font-family:system-ui,sans-serif;font-size:15px;letter-spacing:.04em;}';
    echo '.page__grid{display:grid;grid-template-columns:1fr 400px;gap:36px;padding:36px 40px 48px;}';
    echo '.page__article h1{margin:0 0 12px;font-size:40px;font-weight:500;}';
    echo '.page__article p{margin:0;max-width:42rem;font-size:18px;line-height:1.5;}';
    echo $css;
    echo '</style></head><body><div class="page"><header class="page__bar">' . $page . '</header>';
    echo '<div class="page__grid"><article class="page__article"><h1>' . $articleTitle . '</h1>';
    echo '<p>' . $article . '</p></article><aside>' . $moduleHtml . '</aside></div></div></body></html>';
}
