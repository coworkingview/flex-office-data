<?php

declare(strict_types=1);

namespace CoworkingView\CoworkingPrices\Service;

/**
 * One GET of https://api.coworkingview.com/v1/market/rates for a city.
 * No API key. A 429 or 5xx is retried once. Successful and stable negative
 * readings are cached for ten minutes, matching the API Cache-Control max-age.
 */
final class RatesClient
{
    public const VERSION = '0.1.0';

    public const API_ORIGIN = 'https://api.coworkingview.com';

    public const TIMEOUT_SECONDS = 20;

    public const CACHE_SECONDS = 600;

    public function __construct(
        private readonly HttpTransport $transport,
        private readonly ?RatesCache $cache = null,
        private readonly ?\Closure $sleep = null,
    ) {
    }

    /**
     * @return array<string, mixed>
     */
    public function snapshot(string $city, string $locale): array
    {
        $city = strtolower(trim($city));
        $locale = strtolower(trim($locale));

        if (!RatesParser::isCitySlug($city)) {
            return RatesParser::failure('bad_city', $city);
        }
        if (!RatesParser::isLocale($locale)) {
            return RatesParser::failure('bad_locale', $city);
        }

        $key = 'coworkingview.rates.' . self::VERSION . '.' . $locale . '.' . $city;
        if ($this->cache !== null) {
            $cached = $this->cache->get($key);
            if (is_array($cached) && ($cached['cacheable'] ?? false) === true) {
                return $cached;
            }
        }

        $parsed = $this->fetch($city, $locale);
        if ($this->cache !== null && ($parsed['cacheable'] ?? false) === true) {
            $this->cache->set($key, $parsed, self::CACHE_SECONDS);
        }

        return $parsed;
    }

    /**
     * @return array<string, mixed>
     */
    private function fetch(string $city, string $locale): array
    {
        $url = $this->origin() . '/v1/market/rates?' . http_build_query([
            'locale' => $locale,
            'city' => $city,
        ], '', '&', PHP_QUERY_RFC3986);

        $headers = [
            'Accept' => 'application/json',
            'User-Agent' => 'flarum-coworkingview/' . self::VERSION . ' (+https://github.com/coworkingview/flarum-coworkingview)',
        ];

        $response = $this->transport->get($url, $headers, self::TIMEOUT_SECONDS);
        if ($this->shouldRetry($response)) {
            $this->pause($this->delay($response));
            $response = $this->transport->get($url, $headers, self::TIMEOUT_SECONDS);
        }

        if ($response->status === 0) {
            return RatesParser::failure('unavailable', $city);
        }

        $decoded = json_decode($response->body, true);
        $payload = is_array($decoded) ? $decoded : null;

        if ($response->status === 200) {
            return RatesParser::parse($payload, $city);
        }

        return RatesParser::failure('unavailable', $city, RatesParser::problemDetail($payload), $response->status);
    }

    private function shouldRetry(HttpResponse $response): bool
    {
        return $response->status === 429 || $response->status >= 500;
    }

    private function delay(HttpResponse $response): int
    {
        foreach (['retry-after', 'ratelimit-reset'] as $name) {
            $value = $response->headers[$name] ?? null;
            if (is_string($value) && preg_match('/\A\d+\z/', trim($value)) === 1) {
                return min(10, (int) trim($value));
            }
        }

        return 2;
    }

    private function pause(int $seconds): void
    {
        if ($seconds < 1) {
            return;
        }
        if ($this->sleep !== null) {
            ($this->sleep)($seconds);

            return;
        }
        sleep($seconds);
    }

    private function origin(): string
    {
        $env = getenv('COWORKINGVIEW_API_URL');
        if (!is_string($env) || trim($env) === '') {
            return self::API_ORIGIN;
        }

        $parts = parse_url(trim($env));
        if (!is_array($parts)) {
            return self::API_ORIGIN;
        }

        $scheme = strtolower((string) ($parts['scheme'] ?? ''));
        $host = (string) ($parts['host'] ?? '');
        if (!in_array($scheme, ['https', 'http'], true) || $host === '') {
            return self::API_ORIGIN;
        }
        if (isset($parts['user']) || isset($parts['pass']) || isset($parts['query']) || isset($parts['fragment'])) {
            return self::API_ORIGIN;
        }

        $origin = $scheme . '://' . $host;
        if (isset($parts['port'])) {
            $origin .= ':' . $parts['port'];
        }

        return $origin;
    }
}
