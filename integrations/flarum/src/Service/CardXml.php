<?php

declare(strict_types=1);

namespace CoworkingView\CoworkingPrices\Service;

/**
 * Fills parsed [coworking] XML with price rows before s9e renders it.
 * Text from the API is written as attributes, which the template escapes.
 */
final class CardXml
{
    /**
     * @param callable(string, string, string): array<string, mixed> $lookup city, product, locale
     * @param callable(string, array<string, string>): string $label
     */
    public static function enrich(string $xml, callable $lookup, callable $label): string
    {
        if (!str_contains($xml, '<COWORKING')) {
            return $xml;
        }

        $dom = new \DOMDocument('1.0', 'UTF-8');
        $previous = libxml_use_internal_errors(true);
        $loaded = $dom->loadXML($xml, LIBXML_NONET);
        libxml_clear_errors();
        libxml_use_internal_errors($previous);
        if ($loaded !== true) {
            return $xml;
        }

        $nodes = [];
        foreach ($dom->getElementsByTagName('COWORKING') as $node) {
            $nodes[] = $node;
        }

        foreach ($nodes as $node) {
            self::fill($dom, $node, $lookup, $label);
        }

        $out = $dom->saveXML($dom->documentElement);

        return is_string($out) && $out !== '' ? $out : $xml;
    }

    /**
     * @param callable(string, string, string): array<string, mixed> $lookup
     * @param callable(string, array<string, string>): string $label
     */
    private static function fill(\DOMDocument $dom, \DOMElement $node, callable $lookup, callable $label): void
    {
        $city = strtolower(trim($node->getAttribute('city')));
        $product = strtolower(trim($node->getAttribute('product')));
        $locale = strtolower(trim($node->getAttribute('locale')));

        self::clearChildren($node);

        try {
            $snapshot = $lookup($city, $product, $locale);
        } catch (\Throwable) {
            $snapshot = RatesParser::failure('unavailable', $city);
        }

        if (!is_array($snapshot) || ($snapshot['ok'] ?? false) !== true) {
            $code = is_array($snapshot) && is_string($snapshot['code'] ?? null) ? $snapshot['code'] : 'unavailable';
            $node->setAttribute('ready', '0');
            $node->setAttribute('error', self::plain($label('errors.' . $code, ['city' => $city]), 300));

            return;
        }

        $node->setAttribute('ready', '1');
        $node->setAttribute('error', '');
        $cityName = is_string($snapshot['cityName'] ?? null) && $snapshot['cityName'] !== ''
            ? $snapshot['cityName']
            : $city;
        $node->setAttribute('cityname', self::plain($cityName, 200));

        $asOf = RatesParser::asOfDate(is_string($snapshot['asOf'] ?? null) ? $snapshot['asOf'] : null);
        $node->setAttribute('asof', $asOf === null ? '' : self::plain($label('as_of', ['date' => $asOf]), 80));

        $attribution = is_string($snapshot['attribution'] ?? null) ? $snapshot['attribution'] : '';
        $node->setAttribute('attribution', self::plain($attribution, 2000));

        $rows = is_array($snapshot['rows'] ?? null) ? $snapshot['rows'] : [];
        if ($rows === []) {
            $node->setAttribute('empty', self::plain($label('empty', ['city' => $cityName]), 300));
        } else {
            $node->setAttribute('empty', '');
        }

        foreach ($rows as $row) {
            if (!is_array($row)) {
                continue;
            }
            $node->appendChild(self::rowElement($dom, $row, $label));
        }
    }

    /**
     * @param array<string, mixed> $row
     * @param callable(string, array<string, string>): string $label
     */
    private static function rowElement(\DOMDocument $dom, array $row, callable $label): \DOMElement
    {
        $element = $dom->createElement('COWORKINGROW');
        $product = is_string($row['product'] ?? null) ? $row['product'] : '';
        $element->setAttribute('label', self::plain(self::productLabel($product, $label), 80));
        $element->setAttribute('price', self::plain(self::price($row, $label), 80));

        $spread = '';
        if (is_float($row['p25'] ?? null) || is_int($row['p25'] ?? null)) {
            if (is_float($row['p75'] ?? null) || is_int($row['p75'] ?? null)) {
                $spread = RatesParser::formatAmount((float) $row['p25']) . '–' . RatesParser::formatAmount((float) $row['p75']);
            }
        }
        $element->setAttribute('spread', $spread);

        $sample = $row['sampleSize'] ?? null;
        if (is_int($sample)) {
            $element->setAttribute('sample', self::plain($label('sample', ['count' => (string) $sample]), 80));
        } else {
            $element->setAttribute('sample', '');
        }

        $low = ($row['lowConfidence'] ?? false) === true;
        $element->setAttribute('low', $low ? '1' : '0');
        $element->setAttribute('lowlabel', $low ? self::plain($label('low_confidence', []), 80) : '');

        return $element;
    }

    /**
     * @param callable(string, array<string, string>): string $label
     */
    private static function productLabel(string $product, callable $label): string
    {
        $text = $label('products.' . $product, []);
        $fallback = 'products.' . $product;
        if ($text === '' || $text === $fallback) {
            return ucwords(str_replace('_', ' ', $product));
        }

        return $text;
    }

    /**
     * @param array<string, mixed> $row
     * @param callable(string, array<string, string>): string $label
     */
    private static function price(array $row, callable $label): string
    {
        $median = $row['median'] ?? null;
        if (!is_float($median) && !is_int($median)) {
            return '';
        }
        $text = RatesParser::formatAmount((float) $median);
        $currency = $row['currency'] ?? null;
        if (is_string($currency) && $currency !== '') {
            $text .= ' ' . $currency;
        }
        $unit = $row['unit'] ?? null;
        if (is_string($unit) && $unit !== '') {
            $unitLabel = $label('units.' . $unit, []);
            if ($unitLabel === '' || $unitLabel === 'units.' . $unit) {
                $unitLabel = $unit;
            }
            $text .= ' / ' . $unitLabel;
        }

        return $text;
    }

    private static function clearChildren(\DOMElement $node): void
    {
        while ($node->firstChild !== null) {
            $node->removeChild($node->firstChild);
        }
    }

    private static function plain(string $value, int $limit): string
    {
        $value = preg_replace('/[\x00-\x08\x0B\x0C\x0E-\x1F]/', '', $value) ?? '';
        $value = trim($value);
        if (strlen($value) > $limit) {
            $value = substr($value, 0, $limit - 1) . '…';
        }

        return $value;
    }
}
