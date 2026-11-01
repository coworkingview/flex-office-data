<?php

/**
 * CoworkingView dashboard widget for Matomo.
 *
 * @link    https://coworkingview.com
 * @license https://www.gnu.org/licenses/gpl-3.0.html GPL v3 or later
 */

namespace Piwik\Plugins\CoworkingView;

use Piwik\Cache;
use Piwik\Http;

/**
 * Server-side reads of the public CoworkingView API. Nothing is requested from the browser.
 *
 * Successful responses are cached for about 12 hours. Failures are not cached.
 * The city is the only chosen value. locale=en is required by the API (a request
 * without it returns 400). pageSize=1 is sent so the workspace call returns
 * meta.pagination.total without a page of catalogue listings.
 */
class ApiClient
{
    const BASE_URL = 'https://api.coworkingview.com';
    const USER_AGENT = 'CoworkingView/0.1.0 (+https://coworkingview.com)';
    const TIMEOUT = 20;
    const CACHE_TTL_SECONDS = 43200;

    /**
     * @param string $city
     * @return array
     */
    public function load($city)
    {
        $cached = $this->readCache($city);
        if (is_array($cached)) {
            return $cached;
        }

        $snapshot = $this->fetch($city);
        if ($snapshot['ratesError'] === null && $snapshot['propertiesError'] === null) {
            $this->writeCache($city, $snapshot);
        }

        return $snapshot;
    }

    /**
     * @param string $city
     * @return array
     */
    private function fetch($city)
    {
        $rates = $this->getJson(self::BASE_URL . '/v1/market/rates?' . self::query(array(
            'city' => $city,
            'locale' => 'en',
        )));
        $properties = $this->getJson(self::BASE_URL . '/v1/properties?' . self::query(array(
            'city' => $city,
            'locale' => 'en',
            'pageSize' => 1,
        )));

        $snapshot = array(
            'citySlug' => $city,
            'cityName' => null,
            'countryCode' => null,
            'rows' => array(),
            'asOf' => null,
            'attribution' => null,
            'workspaceCount' => null,
            'ratesError' => null,
            'ratesDetail' => null,
            'propertiesError' => null,
            'propertiesDetail' => null,
        );

        if ($rates['error'] !== null) {
            $snapshot['ratesError'] = $rates['error'];
            $snapshot['ratesDetail'] = $rates['detail'];
        } else {
            $parsed = MarketSnapshot::parseRates($city, $rates['body']);
            if ($parsed['error'] !== null) {
                $snapshot['ratesError'] = $parsed['error'];
            } else {
                $snapshot['cityName'] = $parsed['cityName'];
                $snapshot['countryCode'] = $parsed['countryCode'];
                $snapshot['rows'] = $parsed['rows'];
                $snapshot['asOf'] = $parsed['asOf'];
                $snapshot['attribution'] = $parsed['attribution'];
            }
        }

        if ($properties['error'] !== null) {
            $snapshot['propertiesError'] = $properties['error'];
            $snapshot['propertiesDetail'] = $properties['detail'];
        } else {
            $parsedCount = MarketSnapshot::workspaceCount($properties['body']);
            if ($parsedCount['error'] !== null) {
                $snapshot['propertiesError'] = $parsedCount['error'];
            } else {
                $snapshot['workspaceCount'] = $parsedCount['count'];
            }
        }

        return $snapshot;
    }

    /**
     * @param string $url
     * @return array{error: ?string, detail: ?string, body: ?array}
     */
    private function getJson($url)
    {
        $unavailable = array(
            'error' => MarketSnapshot::ERROR_UNAVAILABLE,
            'detail' => null,
            'body' => null,
        );

        try {
            $transport = Http::getTransportMethod();
            if (!is_string($transport) || $transport === '') {
                return $unavailable;
            }

            $response = Http::sendHttpRequestBy(
                $transport,
                $url,
                self::TIMEOUT,
                self::USER_AGENT,
                null,
                null,
                0,
                '',
                false,
                false,
                true,
                'GET',
                null,
                null,
                null,
                array('Accept: application/json'),
                null,
                true
            );
        } catch (\Exception $exception) {
            return $unavailable;
        }

        if (!is_array($response)) {
            return $unavailable;
        }

        $status = isset($response['status']) ? (int) $response['status'] : 0;
        $raw = isset($response['data']) && is_string($response['data']) ? $response['data'] : '';
        $decoded = json_decode($raw, true);

        if ($status < 200 || $status >= 300) {
            return array(
                'error' => MarketSnapshot::ERROR_HTTP,
                'detail' => MarketSnapshot::problemDetail(is_array($decoded) ? $decoded : null),
                'body' => null,
            );
        }

        if (!is_array($decoded)) {
            return array(
                'error' => MarketSnapshot::ERROR_BAD_RESPONSE,
                'detail' => null,
                'body' => null,
            );
        }

        return array('error' => null, 'detail' => null, 'body' => $decoded);
    }

    /**
     * @param array $params
     * @return string
     */
    private static function query($params)
    {
        return http_build_query($params, '', '&');
    }

    /**
     * @param string $city
     * @return string
     */
    private function cacheKey($city)
    {
        return 'CoworkingView.0.1.0.' . $city;
    }

    /**
     * @param string $city
     * @return array|null
     */
    private function readCache($city)
    {
        try {
            $cache = Cache::getLazyCache();
            $key = $this->cacheKey($city);
            if (!$cache->contains($key)) {
                return null;
            }
            $cached = $cache->fetch($key);
        } catch (\Exception $exception) {
            return null;
        }

        return is_array($cached) ? $cached : null;
    }

    /**
     * @param string $city
     * @param array $snapshot
     */
    private function writeCache($city, $snapshot)
    {
        try {
            Cache::getLazyCache()->save($this->cacheKey($city), $snapshot, self::CACHE_TTL_SECONDS);
        } catch (\Exception $exception) {
            // A cache miss on the next view is preferable to failing the widget.
        }
    }
}
