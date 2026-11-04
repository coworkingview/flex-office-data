<?php

declare(strict_types=1);

namespace CoworkingView\CoworkingPrices\Service;

/**
 * Turns a Price Index payload into one city's rows.
 *
 * figures when that list is present and not empty, otherwise byType, then any
 * other city field that has median and sampleSize (dayPass, meetingRoom, and
 * later aggregates). A product already taken from figures or byType is kept
 * once. Unpublished cities produce no rows. Missing percentiles stay null.
 */
final class RatesParser
{
    public const PRODUCTS = [
        'flex_desk',
        'fix_desk',
        'private_office',
        'exclusive_bereich',
        'day_pass',
        'meeting_room',
        'event_space',
        'virtual_office',
        'membership',
    ];

    private const STAT_UNITS = [
        'day_pass' => 'day',
        'meeting_room' => 'hour',
        'event_space' => 'hour',
        'virtual_office' => 'month',
    ];

    public const ROW_LIMIT = 12;

    public static function isCitySlug(string $value): bool
    {
        return strlen($value) <= 64 && preg_match('/\A[A-Za-z0-9][A-Za-z0-9._-]*\z/', $value) === 1;
    }

    public static function isLocale(string $value): bool
    {
        return in_array($value, ['en', 'de', 'es'], true);
    }

    public static function isProductSlug(string $value): bool
    {
        return $value === '' || $value === 'all' || (strlen($value) <= 64 && preg_match('/\A[a-z0-9][a-z0-9_-]*\z/', $value) === 1);
    }

    /**
     * @return array<string, mixed>
     */
    public static function failure(string $code, string $city = '', ?string $detail = null, ?int $status = null): array
    {
        return [
            'ok' => false,
            'cacheable' => false,
            'code' => $code,
            'detail' => $detail,
            'status' => $status,
            'cityName' => null,
            'citySlug' => strtolower($city),
            'countryCode' => null,
            'currency' => null,
            'asOf' => null,
            'attribution' => null,
            'license' => null,
            'licenseUrl' => null,
            'rows' => [],
        ];
    }

    /**
     * @param array<mixed>|null $payload
     * @return array<string, mixed>
     */
    public static function parse(?array $payload, string $city): array
    {
        $wanted = strtolower($city);

        if ($payload === null || !isset($payload['data']) || !is_array($payload['data'])) {
            return self::failure('bad_response', $wanted);
        }

        $data = $payload['data'];
        if (!isset($data['cities']) || !is_array($data['cities'])) {
            return self::failure('bad_response', $wanted);
        }

        $found = self::findCity($data['cities'], $wanted);
        if ($found === null) {
            $failure = self::failure(self::unpublished($data, $wanted) ? 'unpublished' : 'unknown_city', $wanted);
            $failure['cacheable'] = true;
            $failure['cityName'] = self::unpublishedName($data, $wanted);
            $failure['asOf'] = self::optionalString($data['asOf'] ?? null);
            $failure['attribution'] = self::optionalString($data['attribution'] ?? null);
            $failure['license'] = self::optionalString($data['license'] ?? null);
            $failure['licenseUrl'] = self::httpsUrl(self::optionalString($data['licenseUrl'] ?? null));

            return $failure;
        }

        return [
            'ok' => true,
            'cacheable' => true,
            'code' => null,
            'detail' => null,
            'status' => null,
            'cityName' => self::cityName($found),
            'citySlug' => self::citySlug($found, $wanted),
            'countryCode' => self::optionalString($found['countryCode'] ?? null),
            'currency' => self::optionalString($found['currency'] ?? null),
            'asOf' => self::optionalString($data['asOf'] ?? null),
            'attribution' => self::optionalString($data['attribution'] ?? null),
            'license' => self::optionalString($data['license'] ?? null),
            'licenseUrl' => self::httpsUrl(self::optionalString($data['licenseUrl'] ?? null)),
            'rows' => self::rowsForCity($found),
        ];
    }

    /**
     * @param array<string, mixed> $snapshot
     * @return array<string, mixed>
     */
    public static function select(array $snapshot, string $product): array
    {
        $product = strtolower(trim($product));
        $rows = $snapshot['rows'] ?? [];
        if (!is_array($rows)) {
            $rows = [];
        }

        if ($product !== '' && $product !== 'all') {
            if (!self::isProductSlug($product)) {
                return self::failure('bad_product', (string) ($snapshot['citySlug'] ?? ''));
            }
            $filtered = [];
            foreach ($rows as $row) {
                if (is_array($row) && ($row['product'] ?? null) === $product) {
                    $filtered[] = $row;
                }
            }
            $rows = $filtered;
            if ($rows === [] && ($snapshot['ok'] ?? false) === true) {
                $snapshot['code'] = 'no_product';
            }
        }

        $snapshot['rows'] = array_slice(array_values($rows), 0, self::ROW_LIMIT);

        return $snapshot;
    }

    /**
     * Plain text from an RFC 9457 problem body.
     *
     * @param array<mixed>|null $body
     */
    public static function problemDetail(?array $body): ?string
    {
        if ($body === null) {
            return null;
        }

        $parts = [];
        foreach (['title', 'detail'] as $key) {
            if (isset($body[$key]) && is_string($body[$key]) && trim($body[$key]) !== '') {
                $parts[] = trim($body[$key]);
            }
        }

        if ($parts === []) {
            return null;
        }

        $text = trim((string) preg_replace('/\s+/', ' ', strip_tags(implode(' ', $parts))));
        if ($text === '') {
            return null;
        }
        if (strlen($text) > 240) {
            $text = substr($text, 0, 237) . '...';
        }

        return $text;
    }

    public static function formatAmount(float $amount): string
    {
        if (floor($amount) === $amount) {
            return (string) (int) $amount;
        }

        $text = number_format($amount, 2, '.', '');

        return rtrim(rtrim($text, '0'), '.');
    }

    public static function asOfDate(?string $value): ?string
    {
        if ($value === null) {
            return null;
        }
        if (preg_match('/\A(\d{4}-\d{2}-\d{2})/', $value, $match) === 1) {
            return $match[1];
        }

        return $value;
    }

    /**
     * @param array<mixed> $cities
     * @return array<mixed>|null
     */
    private static function findCity(array $cities, string $wanted): ?array
    {
        foreach ($cities as $city) {
            if (!is_array($city)) {
                continue;
            }
            $slug = self::citySlug($city, '');
            if ($slug !== '' && strtolower($slug) === $wanted) {
                return $city;
            }
        }

        return null;
    }

    /**
     * @param array<mixed> $data
     */
    private static function unpublished(array $data, string $wanted): bool
    {
        if (!isset($data['unpublished']) || !is_array($data['unpublished'])) {
            return false;
        }
        foreach ($data['unpublished'] as $city) {
            if (is_array($city) && strtolower(self::citySlug($city, '')) === $wanted && self::citySlug($city, '') !== '') {
                return true;
            }
        }

        return false;
    }

    /**
     * @param array<mixed> $data
     */
    private static function unpublishedName(array $data, string $wanted): ?string
    {
        if (!isset($data['unpublished']) || !is_array($data['unpublished'])) {
            return null;
        }
        foreach ($data['unpublished'] as $city) {
            if (!is_array($city) || strtolower(self::citySlug($city, '')) !== $wanted) {
                continue;
            }

            return self::cityName($city);
        }

        return null;
    }

    /**
     * @param array<mixed> $city
     * @return list<array<string, mixed>>
     */
    private static function rowsForCity(array $city): array
    {
        $items = [];
        if (isset($city['figures']) && is_array($city['figures']) && $city['figures'] !== []) {
            $items = $city['figures'];
        } elseif (isset($city['byType']) && is_array($city['byType'])) {
            $items = $city['byType'];
        }

        $rows = [];
        $seen = [];
        $currency = self::optionalString($city['currency'] ?? null);

        foreach ($items as $item) {
            $row = self::rowFromItem($item, 'month', null, $currency);
            if ($row === null) {
                continue;
            }
            $rows[] = $row;
            $seen[$row['product']] = true;
        }

        foreach ($city as $key => $value) {
            if (!is_string($key) || !self::isStat($value)) {
                continue;
            }
            $product = self::snake($key);
            if (isset($seen[$product])) {
                continue;
            }
            $unit = self::STAT_UNITS[$product] ?? null;
            $row = self::rowFromItem($value, $unit, $product, $currency);
            if ($row === null) {
                continue;
            }
            $rows[] = $row;
            $seen[$product] = true;
        }

        $order = array_flip(self::PRODUCTS);
        usort($rows, static function (array $left, array $right) use ($order): int {
            $leftRank = $order[$left['product']] ?? 100;
            $rightRank = $order[$right['product']] ?? 100;
            if ($leftRank !== $rightRank) {
                return $leftRank <=> $rightRank;
            }

            return strcmp((string) $left['product'], (string) $right['product']);
        });

        return $rows;
    }

    /**
     * @return array<string, mixed>|null
     */
    private static function rowFromItem(mixed $item, ?string $unit, ?string $product, ?string $currency): ?array
    {
        if (!is_array($item)) {
            return null;
        }

        if ($product === null) {
            $option = $item['optionType'] ?? null;
            if (!is_string($option) || $option === '') {
                return null;
            }
            $product = $option;
        }

        $median = self::amount($item['median'] ?? null);
        if ($median === null) {
            return null;
        }

        $sample = self::countOrNull($item['sampleSize'] ?? null);

        return [
            'product' => $product,
            'unit' => $unit,
            'median' => $median,
            'currency' => self::moneyCurrency($item['median'] ?? null) ?? $currency,
            'p25' => self::amount($item['p25'] ?? null),
            'p75' => self::amount($item['p75'] ?? null),
            'sampleSize' => $sample,
            'lowConfidence' => is_int($sample) && $sample < 10,
        ];
    }

    private static function isStat(mixed $value): bool
    {
        return is_array($value) && array_key_exists('median', $value) && array_key_exists('sampleSize', $value);
    }

    private static function snake(string $key): string
    {
        $snake = preg_replace('/(?<!^)(?=[A-Z])/', '_', $key);

        return strtolower((string) $snake);
    }

    private static function amount(mixed $money): ?float
    {
        if (!is_array($money) || !array_key_exists('amount', $money)) {
            return null;
        }
        $amount = $money['amount'];
        if (is_int($amount) || is_float($amount)) {
            return (float) $amount;
        }
        if (is_string($amount) && is_numeric($amount)) {
            return (float) $amount;
        }

        return null;
    }

    private static function moneyCurrency(mixed $money): ?string
    {
        if (!is_array($money)) {
            return null;
        }

        return self::optionalString($money['currency'] ?? null);
    }

    private static function countOrNull(mixed $value): ?int
    {
        if (is_int($value) && $value >= 0) {
            return $value;
        }
        if (is_float($value) && $value >= 0 && floor($value) === $value) {
            return (int) $value;
        }

        return null;
    }

    private static function optionalString(mixed $value): ?string
    {
        if (!is_string($value)) {
            return null;
        }
        $value = trim($value);

        return $value === '' ? null : $value;
    }

    private static function httpsUrl(?string $value): ?string
    {
        if ($value === null || preg_match('#\Ahttps://[^\s]+\z#', $value) !== 1) {
            return null;
        }
        $parts = parse_url($value);
        if (!is_array($parts) || ($parts['scheme'] ?? '') !== 'https' || empty($parts['host'])) {
            return null;
        }

        return $value;
    }

    /**
     * @param array<mixed> $city
     */
    private static function citySlug(array $city, string $fallback): string
    {
        $ref = $city['city'] ?? null;
        if (!is_array($ref)) {
            return $fallback;
        }

        return self::optionalString($ref['slug'] ?? null) ?? $fallback;
    }

    /**
     * @param array<mixed> $city
     */
    private static function cityName(array $city): ?string
    {
        $ref = $city['city'] ?? null;
        if (!is_array($ref)) {
            return null;
        }

        return self::optionalString($ref['name'] ?? null);
    }
}
