<?php

declare(strict_types=1);

use CoworkingView\CoworkingPrices\Service\CardXml;
use CoworkingView\CoworkingPrices\Service\RatesParser;

$payload = json_decode((string) file_get_contents(__DIR__ . '/fixtures/rates.json'), true);
$snapshot = RatesParser::select(RatesParser::parse($payload, 'example'), 'flex_desk');

$labels = static function (string $key, array $params): string {
    return match ($key) {
        'products.flex_desk' => 'Flex desk',
        'units.month' => 'month',
        'sample' => 'Sample ' . $params['count'],
        'low_confidence' => 'Low confidence',
        'as_of' => 'As of ' . $params['date'],
        'empty' => 'None for ' . ($params['city'] ?? ''),
        'errors.unknown_city' => 'Unknown',
        'errors.unavailable' => 'Unavailable',
        default => $key,
    };
};

$xml = '<r><COWORKING city="example" product="flex_desk" locale="en">[coworking city=example product=flex_desk locale=en]</COWORKING></r>';
$out = CardXml::enrich($xml, static fn (): array => $snapshot, $labels);
check(str_contains($out, 'ready="1"'), 'card is marked ready');
check(str_contains($out, 'cityname="Example City"'), 'city name attribute');
check(str_contains($out, 'asof="As of 2026-01-02"'), 'as of label');
check(str_contains($out, 'label="Flex desk"'), 'product label');
check(str_contains($out, 'price="2.5 EUR / month"'), 'median currency and unit');
check(str_contains($out, 'spread=""'), 'missing percentiles leave the spread empty');
check(str_contains($out, 'sample="Sample 3"'), 'sample label');
check(str_contains($out, 'low="1"'), 'low confidence flag');
check(str_contains($out, 'Source: Example Index (https://coworkingview.com).'), 'attribution is copied');
check(!str_contains($out, '[coworking city=example'), 'original bbcode text is not left in the xml');
check(str_contains($out, '<COWORKINGROW '), 'row element is added');

$unsafe = $snapshot;
$unsafe['cityName'] = 'Ex & <ample>';
$unsafe['attribution'] = 'Credit <script>alert(1)</script>';
$escaped = CardXml::enrich($xml, static fn (): array => $unsafe, $labels);
check(str_contains($escaped, 'Ex &amp; &lt;ample&gt;'), 'city name is escaped');
check(str_contains($escaped, '&lt;script&gt;'), 'attribution is escaped');
check(!str_contains($escaped, '<script>'), 'raw script tag is not introduced');

$empty = RatesParser::select(RatesParser::parse($payload, 'example'), 'membership');
$emptyXml = CardXml::enrich($xml, static fn (): array => $empty, $labels);
check(str_contains($emptyXml, 'empty="None for Example City"'), 'missing product message');
check(!str_contains($emptyXml, '<COWORKINGROW'), 'no invented row');

$unknown = CardXml::enrich(
    '<r><COWORKING city="nowhere">[coworking city=nowhere]</COWORKING></r>',
    static fn (): array => RatesParser::failure('unknown_city', 'nowhere'),
    $labels,
);
check(str_contains($unknown, 'error="Unknown"'), 'unknown city error');
check(str_contains($unknown, 'ready="0"'), 'error card is not ready');

$plain = CardXml::enrich('<r><p>hello</p></r>', static function (): array {
    throw new RuntimeException('should not be called');
}, $labels);
check($plain === '<r><p>hello</p></r>', 'posts without the tag are unchanged');

$spread = RatesParser::select(RatesParser::parse($payload, 'example'), 'private_office');
$spreadXml = CardXml::enrich($xml, static fn (): array => $spread, $labels);
check(str_contains($spreadXml, 'spread="3&#x2013;5"'), 'p25 to p75 spread');
check(str_contains($spreadXml, 'low="0"'), 'larger sample is not low confidence');
