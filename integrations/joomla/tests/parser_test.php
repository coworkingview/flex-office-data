<?php

/**
 * Parser checks against the recorded Price Index fixture.
 *
 * This file is not part of the installable module.
 */

declare(strict_types=1);

define('_JEXEC', 1);

require dirname(__DIR__) . '/mod_coworkingview/src/Helper/RatesParser.php';
require dirname(__DIR__) . '/mod_coworkingview/src/Helper/Retry.php';

use CoworkingView\Module\CoworkingView\Site\Helper\RatesParser;
use CoworkingView\Module\CoworkingView\Site\Helper\Retry;

$failed = 0;

function expect(bool $condition, string $message): void
{
    global $failed;

    if ($failed > 20) {
        return;
    }

    if (!$condition) {
        $failed++;
        fwrite(STDERR, "FAIL {$message}\n");
    }
}

$fixturePath = dirname(__DIR__, 3) . '/spec/fixtures/market_rates.json';
$payload     = json_decode((string) file_get_contents($fixturePath), true);
expect(is_array($payload), 'fixture decodes');

$berlin = RatesParser::parse($payload, 'Berlin');
expect($berlin['ok'] === true, 'berlin parses');
expect($berlin['cityName'] === 'Berlin', 'berlin name');
expect($berlin['currency'] === 'EUR', 'berlin currency');
expect($berlin['cacheable'] === true, 'berlin is cacheable');
expect(is_string($berlin['attribution']) && str_contains($berlin['attribution'], 'CoworkingView'), 'attribution kept');
expect($berlin['licenseUrl'] === 'https://creativecommons.org/licenses/by/4.0/', 'license url kept');
expect($berlin['asOfLabel'] === '2026-10-27', 'as of label');

$byProduct = [];

foreach ($berlin['rows'] as $row) {
    $byProduct[$row['product']] = $row;
}

expect(array_keys($byProduct) === ['flex_desk', 'fix_desk', 'private_office', 'day_pass', 'meeting_room'], 'berlin product order');
expect($byProduct['flex_desk']['median'] === 214.0, 'flex median');
expect($byProduct['flex_desk']['p25'] === 199.0, 'flex p25');
expect($byProduct['flex_desk']['p75'] === 292.0, 'flex p75');
expect($byProduct['flex_desk']['sampleSize'] === 72, 'flex sample');
expect($byProduct['flex_desk']['unit'] === 'month', 'flex unit');
expect($byProduct['flex_desk']['lowConfidence'] === false, 'flex confidence');
expect($byProduct['fix_desk']['median'] === 310.0, 'fix median');
expect($byProduct['private_office']['p25'] === 399.0, 'office p25');
expect($byProduct['day_pass']['unit'] === 'day', 'day pass unit');
expect($byProduct['day_pass']['median'] === 35.0, 'day pass median');
expect($byProduct['day_pass']['p25'] === null, 'day pass has no p25');
expect($byProduct['meeting_room']['unit'] === 'hour', 'meeting room unit');
expect($byProduct['meeting_room']['median'] === 32.0, 'meeting room median');

$limited = RatesParser::select($berlin, '', 2);
expect(count($limited['rows']) === 2, 'limit 2');
expect($limited['rows'][0]['product'] === 'flex_desk', 'limit keeps order');
expect(count($berlin['rows']) === 5, 'select does not mutate the cached rows');

$office = RatesParser::select($berlin, 'private_office', 6);
expect(count($office['rows']) === 1 && $office['rows'][0]['product'] === 'private_office', 'product filter');

$emptyProduct = RatesParser::select($berlin, 'membership', 6);
expect($emptyProduct['ok'] === true && $emptyProduct['rows'] === [], 'missing product is an empty table');

$abu = RatesParser::parse($payload, 'abu-dhabi');
$abuFlex = null;

foreach ($abu['rows'] as $row) {
    if ($row['product'] === 'flex_desk') {
        $abuFlex = $row;
    }
}

expect($abuFlex !== null && $abuFlex['lowConfidence'] === true, 'small sample is low confidence');

$hidden = RatesParser::parse($payload, 'example-town');
expect($hidden['ok'] === false && $hidden['code'] === 'unpublished', 'unpublished city');
expect($hidden['cacheable'] === true, 'unpublished is cacheable');
expect($hidden['cityName'] === 'Example Town', 'unpublished name');

$missing = RatesParser::parse($payload, 'not-a-city');
expect($missing['code'] === 'unknown_city', 'unknown city');
expect(RatesParser::parse(null, 'berlin')['code'] === 'bad_response', 'null payload');
expect(RatesParser::parse(['data' => []], 'berlin')['code'] === 'bad_response', 'payload without cities');
expect(RatesParser::parse(['data' => []], 'berlin')['cacheable'] === false, 'bad response is not cached');

$future = [
    'data' => [
        'cities' => [
            [
                'city' => ['slug' => 'lisbon', 'name' => 'Lisbon'],
                'currency' => 'EUR',
                'figures' => [],
                'eventSpace' => [
                    'median' => ['amount' => 80, 'currency' => 'EUR'],
                    'sampleSize' => 4,
                ],
            ],
        ],
        'attribution' => 'Source: CoworkingView',
    ],
];
$lisbon = RatesParser::parse($future, 'lisbon');
expect(count($lisbon['rows']) === 1, 'future aggregate appears');
expect($lisbon['rows'][0]['product'] === 'event_space', 'eventSpace snake case');
expect($lisbon['rows'][0]['unit'] === 'hour', 'event space unit');
expect($lisbon['rows'][0]['lowConfidence'] === true, 'sample of 4 is low confidence');

expect(RatesParser::formatAmount(214.0) === '214', 'whole amount');
expect(RatesParser::formatAmount(214.5) === '214.5', 'fractional amount');
expect(RatesParser::formatMoney(35.0, 'EUR') === '35 EUR', 'money with currency');
expect(RatesParser::httpsUrl('http://coworkingview.com') === null, 'http url dropped');
expect(RatesParser::httpsUrl('javascript:alert(1)') === null, 'script url dropped');
expect(RatesParser::httpsUrl('https://coworkingview.com') === 'https://coworkingview.com', 'https url kept');
expect(RatesParser::isCitySlug('berlin') && RatesParser::isCitySlug('abu-dhabi'), 'slugs');
expect(!RatesParser::isCitySlug('') && !RatesParser::isCitySlug('berlin/mitte') && !RatesParser::isCitySlug(' berlin'), 'bad slugs');
expect(RatesParser::isProduct('') && RatesParser::isProduct('flex_desk') && !RatesParser::isProduct('desk'), 'products');

$detail = RatesParser::problemDetail([
    'title' => 'Bad request',
    'detail' => '<b>city</b> is unknown',
]);
expect($detail === 'Bad request city is unknown', 'problem detail is plain text');

expect(Retry::seconds(null, null) === 2, 'retry fallback');
expect(Retry::seconds('15', null) === 10, 'retry cap');
expect(Retry::seconds(null, '3') === 3, 'rate limit reset');
expect(Retry::seconds('0', '9') === 0, 'retry-after wins even at zero');
expect(Retry::seconds('Wed, 21 Oct 2015 07:28:00 GMT', null, strtotime('Wed, 21 Oct 2015 07:28:00 GMT') - 4) === 4, 'http date');

$manifest = simplexml_load_file(dirname(__DIR__) . '/mod_coworkingview/mod_coworkingview.xml');
$options  = [];

foreach ($manifest->config->fields->fieldset->field as $field) {
    if ((string) $field['name'] !== 'product') {
        continue;
    }

    foreach ($field->option as $option) {
        $value = (string) $option['value'];

        if ($value !== '') {
            $options[] = $value;
        }
    }
}

expect($options === RatesParser::PRODUCTS, 'manifest products match the parser');
expect((string) $manifest->name === 'CoworkingView Workspace Prices', 'manifest name');
expect((string) $manifest->version === '1.0.0', 'manifest version');

$helper = (string) file_get_contents(dirname(__DIR__) . '/mod_coworkingview/src/Helper/CoworkingViewHelper.php');
expect(str_contains($helper, "const VERSION = '1.0.0'"), 'helper version');

if ($failed > 0) {
    fwrite(STDERR, "{$failed} failed\n");
    exit(1);
}

echo "parser tests passed\n";
