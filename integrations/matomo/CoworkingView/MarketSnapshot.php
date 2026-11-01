<?php

/**
 * CoworkingView dashboard widget for Matomo.
 *
 * @link    https://coworkingview.com
 * @license https://www.gnu.org/licenses/gpl-3.0.html GPL v3 or later
 */

namespace Piwik\Plugins\CoworkingView;

/**
 * Turns public API payloads into the fields the widget shows.
 *
 * No I/O. Only values present on the response are copied. The unit is not an API
 * field: figures and byType are monthly Price Index rows, and a city-level object
 * that has median and sampleSize uses the same unit map as the other CoworkingView
 * clients (dayPass -> day, meetingRoom -> hour, eventSpace -> hour, virtualOffice ->
 * month). Anything else has no unit.
 */
class MarketSnapshot
{
    const ERROR_BAD_RESPONSE = 'bad_response';
    const ERROR_HTTP = 'http';
    const ERROR_UNAVAILABLE = 'unavailable';

    /**
     * @var array<string, int>
     */
    private static $productOrder = array(
        'flex_desk' => 0,
        'fix_desk' => 1,
        'private_office' => 2,
        'exclusive_bereich' => 3,
        'day_pass' => 4,
        'meeting_room' => 5,
        'event_space' => 6,
        'virtual_office' => 7,
        'membership' => 8,
    );

    /**
     * Units for city-level statistic objects. Figures and byType are always monthly.
     *
     * @var array<string, string>
     */
    private static $statUnits = array(
        'day_pass' => 'day',
        'meeting_room' => 'hour',
        'event_space' => 'hour',
        'virtual_office' => 'month',
    );

    /**
     * @param string $citySlug
     * @param mixed $body
     * @return array
     */
    public static function parseRates($citySlug, $body)
    {
        if (!is_array($body) || !isset($body['data']) || !is_array($body['data'])) {
            return array('error' => self::ERROR_BAD_RESPONSE);
        }

        $data = $body['data'];
        if (!isset($data['cities']) || !is_array($data['cities'])) {
            return array('error' => self::ERROR_BAD_RESPONSE);
        }

        $result = array(
            'error' => null,
            'cityName' => null,
            'countryCode' => null,
            'rows' => array(),
            'asOf' => self::optionalString(isset($data['asOf']) ? $data['asOf'] : null),
            'attribution' => self::optionalString(isset($data['attribution']) ? $data['attribution'] : null),
        );

        $city = self::findCity($data['cities'], $citySlug);
        if ($city === null) {
            return $result;
        }

        if (isset($city['city']) && is_array($city['city'])) {
            $result['cityName'] = self::optionalString(isset($city['city']['name']) ? $city['city']['name'] : null);
        }
        $result['countryCode'] = self::optionalString(isset($city['countryCode']) ? $city['countryCode'] : null);

        $items = array();
        if (isset($city['figures']) && is_array($city['figures']) && count($city['figures']) > 0) {
            $items = $city['figures'];
        } elseif (isset($city['byType']) && is_array($city['byType'])) {
            $items = $city['byType'];
        }

        $rows = array();
        foreach ($items as $item) {
            $row = self::rowFromItem($item, 'month', null);
            if ($row !== null) {
                $rows[] = $row;
            }
        }

        foreach ($city as $key => $value) {
            if (!is_string($key) || !self::isStat($value)) {
                continue;
            }
            $product = self::snake($key);
            $unit = isset(self::$statUnits[$product]) ? self::$statUnits[$product] : null;
            $row = self::rowFromItem($value, $unit, $product);
            if ($row !== null) {
                $rows[] = $row;
            }
        }

        usort($rows, function ($left, $right) {
            $leftRank = isset(self::$productOrder[$left['product']]) ? self::$productOrder[$left['product']] : 100;
            $rightRank = isset(self::$productOrder[$right['product']]) ? self::$productOrder[$right['product']] : 100;
            if ($leftRank === $rightRank) {
                return strcmp($left['product'], $right['product']);
            }

            return $leftRank < $rightRank ? -1 : 1;
        });

        $result['rows'] = $rows;

        return $result;
    }

    /**
     * Workspace count is meta.pagination.total. The length of data is one page, not the count.
     *
     * @param mixed $body
     * @return array{error: ?string, count: ?int}
     */
    public static function workspaceCount($body)
    {
        if (!is_array($body) || !isset($body['meta']) || !is_array($body['meta'])) {
            return array('error' => self::ERROR_BAD_RESPONSE, 'count' => null);
        }
        if (!isset($body['meta']['pagination']) || !is_array($body['meta']['pagination'])) {
            return array('error' => self::ERROR_BAD_RESPONSE, 'count' => null);
        }
        if (!array_key_exists('total', $body['meta']['pagination'])) {
            return array('error' => self::ERROR_BAD_RESPONSE, 'count' => null);
        }

        $total = $body['meta']['pagination']['total'];
        if (is_int($total) && $total >= 0) {
            return array('error' => null, 'count' => $total);
        }
        if (is_float($total) && $total >= 0 && floor($total) == $total) {
            return array('error' => null, 'count' => (int) $total);
        }
        if (is_string($total) && preg_match('/^\d+$/', $total) === 1) {
            return array('error' => null, 'count' => (int) $total);
        }

        return array('error' => self::ERROR_BAD_RESPONSE, 'count' => null);
    }

    /**
     * Short text from an RFC 9457 problem body, or null when the body has none.
     *
     * @param mixed $body
     * @return string|null
     */
    public static function problemDetail($body)
    {
        if (!is_array($body)) {
            return null;
        }

        $parts = array();
        if (isset($body['title']) && is_string($body['title']) && trim($body['title']) !== '') {
            $parts[] = trim($body['title']);
        }
        if (isset($body['detail']) && is_string($body['detail']) && trim($body['detail']) !== '') {
            $parts[] = trim($body['detail']);
        } elseif (isset($body['errors']) && is_array($body['errors'])) {
            foreach ($body['errors'] as $error) {
                if (is_array($error) && isset($error['message']) && is_string($error['message'])) {
                    $message = trim($error['message']);
                    if ($message !== '') {
                        $parts[] = $message;
                    }
                }
            }
        }

        if (count($parts) === 0) {
            return null;
        }

        $text = trim(preg_replace('/\s+/', ' ', strip_tags(implode(' ', $parts))));
        if ($text === '') {
            return null;
        }
        if (strlen($text) > 240) {
            $text = substr($text, 0, 237) . '...';
        }

        return $text;
    }

    /**
     * @param array $cities
     * @param string $citySlug
     * @return array|null
     */
    private static function findCity($cities, $citySlug)
    {
        $wanted = strtolower($citySlug);
        foreach ($cities as $city) {
            if (!is_array($city) || !isset($city['city']) || !is_array($city['city'])) {
                continue;
            }
            $slug = isset($city['city']['slug']) ? $city['city']['slug'] : '';
            if (is_string($slug) && strtolower($slug) === $wanted) {
                return $city;
            }
        }

        return null;
    }

    /**
     * @param mixed $value
     * @return bool
     */
    private static function isStat($value)
    {
        return is_array($value)
            && array_key_exists('median', $value)
            && array_key_exists('sampleSize', $value);
    }

    /**
     * @param mixed $item
     * @param string|null $unit
     * @param string|null $product
     * @return array|null
     */
    private static function rowFromItem($item, $unit, $product)
    {
        if (!is_array($item)) {
            return null;
        }
        if ($product === null) {
            if (!isset($item['optionType']) || !is_string($item['optionType']) || $item['optionType'] === '') {
                return null;
            }
            $product = $item['optionType'];
        }

        return array(
            'product' => $product,
            'unit' => $unit,
            'median' => self::formatMoney(isset($item['median']) ? $item['median'] : null),
            'p25' => self::formatMoney(array_key_exists('p25', $item) ? $item['p25'] : null),
            'p75' => self::formatMoney(array_key_exists('p75', $item) ? $item['p75'] : null),
            'sampleSize' => self::formatCount(array_key_exists('sampleSize', $item) ? $item['sampleSize'] : null),
        );
    }

    /**
     * @param mixed $money
     * @return string|null
     */
    private static function formatMoney($money)
    {
        if (!is_array($money) || !array_key_exists('amount', $money)) {
            return null;
        }

        $amount = self::formatAmount($money['amount']);
        if ($amount === null) {
            return null;
        }

        $currency = '';
        if (isset($money['currency']) && is_string($money['currency']) && $money['currency'] !== '') {
            $currency = $money['currency'];
        }

        return $currency === '' ? $amount : $amount . ' ' . $currency;
    }

    /**
     * @param mixed $amount
     * @return string|null
     */
    private static function formatAmount($amount)
    {
        if (is_int($amount)) {
            return (string) $amount;
        }
        if (is_float($amount)) {
            if (floor($amount) == $amount && abs($amount) < 1.0e15) {
                return sprintf('%.0F', $amount);
            }
            $text = rtrim(rtrim(sprintf('%.8F', $amount), '0'), '.');

            return $text === '' ? '0' : $text;
        }
        if (is_string($amount) && is_numeric($amount)) {
            return $amount;
        }

        return null;
    }

    /**
     * @param mixed $value
     * @return string|null
     */
    private static function formatCount($value)
    {
        if (is_int($value)) {
            return (string) $value;
        }
        if (is_float($value) && floor($value) == $value) {
            return sprintf('%.0F', $value);
        }
        if (is_string($value) && preg_match('/^\d+$/', $value) === 1) {
            return $value;
        }

        return null;
    }

    /**
     * @param string $key
     * @return string
     */
    private static function snake($key)
    {
        $snake = preg_replace('/(?<!^)(?=[A-Z])/', '_', $key);
        if (!is_string($snake)) {
            return strtolower($key);
        }

        return strtolower($snake);
    }

    /**
     * @param mixed $value
     * @return string|null
     */
    private static function optionalString($value)
    {
        if (!is_string($value)) {
            return null;
        }
        $value = trim($value);

        return $value === '' ? null : $value;
    }
}
