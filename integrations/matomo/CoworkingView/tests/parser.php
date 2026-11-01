<?php

/**
 * Parser checks for the CoworkingView widget. No network and no Matomo runtime.
 */

require_once dirname(__DIR__) . '/CitySlug.php';
require_once dirname(__DIR__) . '/MarketSnapshot.php';

use Piwik\Plugins\CoworkingView\CitySlug;
use Piwik\Plugins\CoworkingView\MarketSnapshot;

$failures = 0;

function expect_same($expected, $actual, $message)
{
    global $failures;
    if ($expected !== $actual) {
        fwrite(STDERR, $message . "\n expected: " . var_export($expected, true) . "\n actual:   " . var_export($actual, true) . "\n");
        $failures++;
    }
}

function load_json($name)
{
    $path = __DIR__ . '/fixtures/' . $name;
    $decoded = json_decode(file_get_contents($path), true);
    if (!is_array($decoded)) {
        fwrite(STDERR, "fixture is not JSON: $name\n");
        exit(1);
    }

    return $decoded;
}

expect_same(true, CitySlug::isValid('berlin'), 'berlin is a city slug');
expect_same(true, CitySlug::isValid('abu-dhabi'), 'hyphenated slug');
expect_same(false, CitySlug::isValid(''), 'empty slug');
expect_same(false, CitySlug::isValid('berlin madrid'), 'spaces are rejected');
expect_same(false, CitySlug::isValid('../berlin'), 'path traversal is rejected');
expect_same(false, CitySlug::isValid(str_repeat('a', 101)), 'slug length is capped');

$rates = MarketSnapshot::parseRates('berlin', load_json('rates-berlin.json'));
expect_same(null, $rates['error'], 'berlin rates parse');
expect_same('Berlin', $rates['cityName'], 'city name');
expect_same('DE', $rates['countryCode'], 'country code');
expect_same('2026-11-01T00:00:00.000Z', $rates['asOf'], 'asOf passed through');
expect_same(
    'Source: CoworkingView Price Index (https://coworkingview.com/en/tools/price-index).',
    $rates['attribution'],
    'attribution passed through'
);

$products = array();
foreach ($rates['rows'] as $row) {
    $products[] = $row['product'];
}
expect_same(
    array('flex_desk', 'fix_desk', 'private_office', 'day_pass', 'meeting_room'),
    $products,
    'product order uses figures, then dayPass and meetingRoom'
);

$byProduct = array();
foreach ($rates['rows'] as $row) {
    $byProduct[$row['product']] = $row;
}
expect_same('214 EUR', $byProduct['flex_desk']['median'], 'flex desk median from figures, not the ignored byType row');
expect_same('199 EUR', $byProduct['flex_desk']['p25'], 'flex desk p25');
expect_same('292 EUR', $byProduct['flex_desk']['p75'], 'flex desk p75');
expect_same('72', $byProduct['flex_desk']['sampleSize'], 'flex desk sample size');
expect_same('month', $byProduct['flex_desk']['unit'], 'figures are monthly');
expect_same('35 EUR', $byProduct['day_pass']['median'], 'day pass median');
expect_same(null, $byProduct['day_pass']['p25'], 'day pass has no p25 in the payload');
expect_same('day', $byProduct['day_pass']['unit'], 'day pass unit');
expect_same('32 EUR', $byProduct['meeting_room']['median'], 'meeting room median');
expect_same('hour', $byProduct['meeting_room']['unit'], 'meeting room unit');
expect_same('79', $byProduct['meeting_room']['sampleSize'], 'meeting room sample size');

$count = MarketSnapshot::workspaceCount(load_json('properties-total.json'));
expect_same(null, $count['error'], 'properties parse');
expect_same(143, $count['count'], 'workspace count is pagination.total, not the length of data');

$missingTotal = array(
    'data' => array(array('slug' => 'one'), array('slug' => 'two')),
    'meta' => array('pagination' => array('page' => 1, 'pageSize' => 2)),
);
$missing = MarketSnapshot::workspaceCount($missingTotal);
expect_same(MarketSnapshot::ERROR_BAD_RESPONSE, $missing['error'], 'missing total is an error');
expect_same(null, $missing['count'], 'missing total does not fall back to count(data)');

$empty = MarketSnapshot::parseRates('not-a-city', array(
    'data' => array(
        'cities' => array(),
        'asOf' => '2026-11-01T00:00:00.000Z',
    ),
));
expect_same(null, $empty['error'], 'unknown city is an empty result');
expect_same(array(), $empty['rows'], 'unknown city has no rows');
expect_same(null, $empty['cityName'], 'unknown city has no name');

$byTypeOnly = MarketSnapshot::parseRates('lisbon', array(
    'data' => array(
        'cities' => array(
            array(
                'city' => array('slug' => 'lisbon', 'name' => 'Lisbon'),
                'countryCode' => 'PT',
                'byType' => array(
                    array(
                        'optionType' => 'flex_desk',
                        'median' => array('amount' => 200, 'currency' => 'EUR'),
                        'min' => array('amount' => 100, 'currency' => 'EUR'),
                        'sampleSize' => 4,
                    ),
                ),
            ),
        ),
    ),
));
expect_same('200 EUR', $byTypeOnly['rows'][0]['median'], 'byType is used when figures is absent');
expect_same(null, $byTypeOnly['rows'][0]['p25'], 'byType row has no p25');
expect_same('month', $byTypeOnly['rows'][0]['unit'], 'byType rows are monthly');

$currency = MarketSnapshot::parseRates('dubai', array(
    'data' => array(
        'cities' => array(
            array(
                'city' => array('slug' => 'dubai', 'name' => 'Dubai'),
                'currency' => 'EUR',
                'figures' => array(
                    array(
                        'optionType' => 'flex_desk',
                        'median' => array('amount' => 10, 'currency' => 'USD'),
                        'sampleSize' => 2,
                    ),
                ),
                'eventSpace' => array(
                    'median' => array('amount' => 40, 'currency' => 'USD'),
                    'sampleSize' => 3,
                ),
                'futureStat' => array(
                    'median' => array('amount' => 7, 'currency' => 'USD'),
                    'sampleSize' => 1,
                ),
            ),
        ),
    ),
));
$currencyRows = array();
foreach ($currency['rows'] as $row) {
    $currencyRows[$row['product']] = $row;
}
expect_same('10 USD', $currencyRows['flex_desk']['median'], 'currency comes from the money object');
expect_same('hour', $currencyRows['event_space']['unit'], 'eventSpace unit');
expect_same(null, $currencyRows['future_stat']['unit'], 'unknown statistic has no invented unit');

$detail = MarketSnapshot::problemDetail(array(
    'title' => 'Validation failed',
    'errors' => array(
        array('path' => 'locale', 'message' => 'Invalid option: expected one of "en"|"de"|"es"'),
    ),
));
expect_same(
    'Validation failed Invalid option: expected one of "en"|"de"|"es"',
    $detail,
    'problem JSON title and error message'
);

if ($failures > 0) {
    fwrite(STDERR, $failures . " assertion(s) failed\n");
    exit(1);
}

fwrite(STDOUT, "parser ok\n");
