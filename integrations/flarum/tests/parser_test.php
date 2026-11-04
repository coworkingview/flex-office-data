<?php

declare(strict_types=1);

use CoworkingView\CoworkingPrices\AttributeFilter;
use CoworkingView\CoworkingPrices\Service\RatesParser;

$payload = json_decode((string) file_get_contents(__DIR__ . '/fixtures/rates.json'), true);
check(is_array($payload), 'fixture decodes');

$parsed = RatesParser::parse($payload, 'example');
check($parsed['ok'] === true, 'example city is published');
check($parsed['cityName'] === 'Example City', 'city name');
check($parsed['citySlug'] === 'Example', 'slug is kept as published');
check($parsed['currency'] === 'EUR', 'currency');
check($parsed['asOf'] === '2026-01-02T03:04:05Z', 'asOf');
check($parsed['attribution'] === 'Source: Example Index (https://coworkingview.com).', 'attribution is kept');
check($parsed['licenseUrl'] === 'https://creativecommons.org/licenses/by/4.0/', 'https license url');
check($parsed['cacheable'] === true, 'published city is cacheable');

$products = array_column($parsed['rows'], 'product');
check($products === ['flex_desk', 'private_office', 'day_pass', 'meeting_room', 'event_space'], 'product order, figures win over byType');

$byProduct = [];
foreach ($parsed['rows'] as $row) {
    $byProduct[$row['product']] = $row;
}
check($byProduct['flex_desk']['median'] === 2.5, 'flex median comes from figures, not byType');
check($byProduct['flex_desk']['p25'] === null, 'missing p25 stays null');
check($byProduct['flex_desk']['p75'] === null, 'missing p75 stays null');
check($byProduct['flex_desk']['lowConfidence'] === true, 'sample under 10 is low confidence');
check($byProduct['flex_desk']['unit'] === 'month', 'figure unit is month');
check($byProduct['private_office']['p25'] === 3.0, 'p25 amount');
check($byProduct['private_office']['p75'] === 5.0, 'p75 amount');
check($byProduct['private_office']['lowConfidence'] === false, 'sample 12 is not low confidence');
check($byProduct['day_pass']['unit'] === 'day', 'day pass unit');
check($byProduct['meeting_room']['unit'] === 'hour', 'meeting room unit');
check($byProduct['meeting_room']['p75'] === null, 'one-sided percentile stays null');
check($byProduct['event_space']['unit'] === 'hour', 'event space unit');
check($byProduct['event_space']['median'] === 7.5, 'numeric string amount');

$hidden = RatesParser::parse($payload, 'HIDDEN');
check($hidden['ok'] === false && $hidden['code'] === 'unpublished', 'unpublished city');
check($hidden['cityName'] === 'Hidden City', 'unpublished name');
check($hidden['cacheable'] === true, 'unpublished is cacheable');
check($hidden['rows'] === [], 'unpublished has no rows');

$missing = RatesParser::parse($payload, 'nowhere');
check($missing['code'] === 'unknown_city' && $missing['cacheable'] === true, 'unknown city');

check(RatesParser::parse(null, 'example')['code'] === 'bad_response', 'null payload');
check(RatesParser::parse(['data' => []], 'example')['code'] === 'bad_response', 'payload without cities');

$httpLicense = $payload;
$httpLicense['data']['licenseUrl'] = 'http://creativecommons.org/licenses/by/4.0/';
check(RatesParser::parse($httpLicense, 'example')['licenseUrl'] === null, 'non-https license url is dropped');

$byTypeOnly = [
    'data' => [
        'cities' => [[
            'city' => ['slug' => 'other', 'name' => 'Other'],
            'currency' => 'USD',
            'figures' => [],
            'byType' => [[
                'optionType' => 'fix_desk',
                'median' => ['amount' => 8, 'currency' => 'USD'],
                'sampleSize' => 10,
            ]],
        ]],
        'asOf' => '2026-03-04',
        'attribution' => 'Credit',
    ],
];
$other = RatesParser::parse($byTypeOnly, 'other');
check(count($other['rows']) === 1 && $other['rows'][0]['product'] === 'fix_desk', 'empty figures falls back to byType');
check($other['rows'][0]['p25'] === null && $other['rows'][0]['lowConfidence'] === false, 'byType has no percentiles');
check(RatesParser::asOfDate($other['asOf']) === '2026-03-04', 'date-only asOf');

$one = RatesParser::select($parsed, 'day_pass');
check(count($one['rows']) === 1 && $one['rows'][0]['product'] === 'day_pass', 'product filter');
check(RatesParser::select($parsed, 'all')['rows'] === $parsed['rows'] || count(RatesParser::select($parsed, 'all')['rows']) === count($parsed['rows']), 'all keeps every row');
$none = RatesParser::select($parsed, 'membership');
check($none['ok'] === true && $none['code'] === 'no_product' && $none['rows'] === [], 'missing product is empty, not invented');
check(RatesParser::select($parsed, 'bad product')['code'] === 'bad_product', 'bad product slug');

check(RatesParser::formatAmount(2.0) === '2', 'whole amount');
check(RatesParser::formatAmount(2.5) === '2.5', 'fractional amount');
check(RatesParser::problemDetail(['title' => 'Bad', 'detail' => '<b>No</b>']) === 'Bad No', 'problem detail is plain text');

check(AttributeFilter::city(' Berlin ') === 'berlin', 'city filter lowercases');
check(AttributeFilter::city('../etc') === false, 'city filter rejects a path');
check(AttributeFilter::city('') === false, 'city filter rejects empty');
check(AttributeFilter::product('Flex_Desk') === 'flex_desk', 'product filter');
check(AttributeFilter::product('all') === false, 'product filter drops all');
check(AttributeFilter::product('nope!') === false, 'product filter rejects punctuation');
check(AttributeFilter::locale('DE') === 'de', 'locale filter');
check(AttributeFilter::locale('fr') === false, 'locale filter rejects fr');
check(AttributeFilter::showWidget(null) === true, 'widget defaults on');
check(AttributeFilter::showWidget('0') === false, 'widget can be switched off');
check(AttributeFilter::showWidget('1') === true, 'widget setting on');
