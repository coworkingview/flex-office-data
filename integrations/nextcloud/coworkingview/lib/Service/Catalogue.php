<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 CoworkingView <info@coworkingview.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\CoworkingView\Service;

/**
 * Read-only client for the public CoworkingView API.
 *
 * Nothing is requested from the constructor. Prices, photos, logos and
 * descriptions are dropped before a result is returned. A search reads one
 * page of listings and the detail of each row on that page, so the workspace
 * type is the one the listing publishes.
 */
final class Catalogue {
	public const VERSION = '1.0.0';
	public const DEFAULT_BASE_URL = 'https://api.coworkingview.com';
	public const SITE_URL = 'https://coworkingview.com';
	public const USER_AGENT = 'coworkingview-nextcloud/' . self::VERSION . ' (+https://github.com/coworkingview/flex-office-data)';
	public const PAGE_SIZE = 8;
	public const MAX_PAGE_SIZE = 8;
	public const TIMEOUT = 20.0;

	private const LOCALES = ['en', 'de', 'es'];
	private const LISTING_PATH = [
		'en' => 'workspace',
		'es' => 'oficina',
		'de' => 'buero',
	];
	private const LISTING_HOSTS = ['coworkingview.com', 'www.coworkingview.com'];

	/**
	 * @param \Closure(string, array<string, string>, float): array{0: int, 1: array<string, string>, 2: string} $transport
	 * @param \Closure(float): void $sleep
	 */
	public function __construct(
		private readonly string $baseUrl,
		private readonly \Closure $transport,
		private readonly \Closure $sleep,
		private readonly float $timeout = self::TIMEOUT,
	) {
	}

	/**
	 * @param \Closure(string, array<string, string>, float): array{0: int, 1: array<string, string>, 2: string}|null $transport
	 * @param \Closure(float): void|null $sleep
	 */
	public static function create(?\Closure $transport = null, ?\Closure $sleep = null, ?string $baseUrl = null): self {
		return new self(
			self::normalizeBaseUrl($baseUrl ?? self::resolveBaseUrl()),
			$transport ?? \Closure::fromCallable(new CurlTransport()),
			$sleep ?? static function (float $seconds): void {
				if ($seconds > 0) {
					usleep((int)round($seconds * 1000000));
				}
			},
		);
	}

	public static function resolveBaseUrl(): string {
		$value = getenv('COWORKINGVIEW_API_URL');
		if (!is_string($value) || trim($value) === '') {
			return self::DEFAULT_BASE_URL;
		}
		return trim($value);
	}

	/**
	 * Cities that have at least one listed space, sorted by name.
	 *
	 * Uses GET /v1/geo/bootstrap. If that request fails, uses the published
	 * cities on GET /v1/market/rates. Unpublished price-index cities are omitted.
	 *
	 * @return list<array{slug: string, name: string, countryCode: ?string}>
	 */
	public function cities(string $locale): array {
		$locale = $this->locale($locale);
		try {
			$payload = $this->get('/v1/geo/bootstrap', ['locale' => $locale]);
			return $this->citiesFromBootstrap($payload);
		} catch (ApiException $first) {
			try {
				$payload = $this->get('/v1/market/rates', ['locale' => $locale]);
				return $this->citiesFromRates($payload);
			} catch (ApiException $second) {
				throw new ApiException(
					$second->status,
					$second->errorCode,
					'Could not load cities from the CoworkingView API.',
					$first->getMessage(),
					$second,
				);
			}
		}
	}

	/**
	 * One page of workspaces in a city, optionally one workspace type.
	 *
	 * @return array{
	 *   citySlug: string,
	 *   cityName: ?string,
	 *   type: ?string,
	 *   workspaces: list<array{name: string, city: string, types: list<string>, url: string}>,
	 *   total: ?int,
	 *   detailFailures: int,
	 *   skipped: int,
	 *   citation: ?string,
	 *   notice: ?string,
	 *   moreUrl: ?string
	 * }
	 */
	public function search(string $locale, string $citySlug, ?string $typeCode, int $limit = self::PAGE_SIZE): array {
		$locale = $this->locale($locale);
		$citySlug = $this->citySlug($citySlug);
		$typeCode = $this->typeCode($typeCode);
		$limit = $this->limit($limit);
		$query = [
			'locale' => $locale,
			'city' => $citySlug,
			'page' => 1,
			'pageSize' => $limit,
			'sortBy' => 'date-desc',
		];
		if ($typeCode !== null) {
			$query['pricingOptionType'] = $typeCode;
		}
		$payload = $this->get('/v1/properties', $query);
		$rows = $payload['data'] ?? null;
		if (!is_array($rows)) {
			throw new ApiException(200, 'BAD_RESPONSE', 'The CoworkingView API returned an unexpected workspace list.');
		}
		$workspaces = [];
		$failures = 0;
		$skipped = 0;
		$cityName = null;
		foreach ($rows as $row) {
			if (count($workspaces) >= $limit) {
				break;
			}
			$card = $this->card($row);
			if ($card === null) {
				$skipped++;
				continue;
			}
			if ($cityName === null && $card['city'] !== null) {
				$cityName = $card['city'];
			}
			$detail = $this->detail($locale, $card['slug']);
			if ($detail === null) {
				$failures++;
			} elseif ($cityName === null && $detail['city'] !== null) {
				$cityName = $detail['city'];
			}
			$workspace = $this->workspace($card, $detail, $typeCode, $locale);
			if ($workspace === null) {
				$skipped++;
				continue;
			}
			$workspaces[] = $workspace;
			if (count($workspaces) >= $limit) {
				break;
			}
		}
		return [
			'citySlug' => $citySlug,
			'cityName' => $cityName,
			'type' => $typeCode,
			'workspaces' => $workspaces,
			'total' => $this->pageTotal($payload),
			'detailFailures' => $failures,
			'skipped' => $skipped,
			'citation' => $this->citation($payload),
			'notice' => $this->notice($payload),
			'moreUrl' => $this->moreUrl($payload),
		];
	}

	/**
	 * Workspaces for a unified-search term.
	 *
	 * Property suggestions are listed first. When the term is a city name or
	 * city slug and no property suggestion came back, one page of that city
	 * is searched. Operators and countries are not returned as workspaces.
	 *
	 * @return array{
	 *   citySlug: ?string,
	 *   cityName: ?string,
	 *   type: ?string,
	 *   workspaces: list<array{name: string, city: string, types: list<string>, url: string}>,
	 *   total: ?int,
	 *   detailFailures: int,
	 *   skipped: int,
	 *   citation: ?string,
	 *   notice: ?string,
	 *   moreUrl: ?string
	 * }
	 */
	public function unified(string $locale, string $term, int $limit = self::PAGE_SIZE): array {
		$locale = $this->locale($locale);
		$term = trim($term);
		$limit = $this->limit($limit);
		if ($term === '' || mb_strlen($term) > 100) {
			return $this->emptySearch(null, null);
		}
		$payload = $this->get('/v1/search/suggest', [
			'locale' => $locale,
			'q' => $term,
			'limit' => $limit,
		]);
		$rows = $payload['data'] ?? null;
		if (!is_array($rows)) {
			throw new ApiException(200, 'BAD_RESPONSE', 'The CoworkingView API returned an unexpected suggestion list.');
		}
		$properties = [];
		$citySlug = null;
		$cityName = null;
		foreach ($rows as $row) {
			if (!is_array($row)) {
				continue;
			}
			$kind = $row['kind'] ?? '';
			if ($kind === 'property') {
				$properties[] = $row;
			}
			if ($kind === 'city' && $citySlug === null && $this->cityTermMatches($term, $row)) {
				$slug = $row['slug'] ?? '';
				if (is_string($slug) && preg_match('/^[a-z0-9-]{1,200}$/', $slug)) {
					$citySlug = $slug;
					$label = $row['label'] ?? null;
					$cityName = is_string($label) && trim($label) !== '' ? trim($label) : null;
				}
			}
		}
		if ($properties === [] && $citySlug !== null) {
			$result = $this->search($locale, $citySlug, null, $limit);
			if ($result['cityName'] === null) {
				$result['cityName'] = $cityName;
			}
			return $result;
		}
		$workspaces = [];
		$failures = 0;
		$skipped = 0;
		foreach ($properties as $row) {
			if (count($workspaces) >= $limit) {
				break;
			}
			$slug = $row['slug'] ?? '';
			$label = $row['label'] ?? '';
			if (!is_string($slug) || !preg_match('/^[A-Za-z0-9][A-Za-z0-9._-]{0,199}$/', $slug)) {
				$skipped++;
				continue;
			}
			if (!is_string($label) || trim($label) === '') {
				$skipped++;
				continue;
			}
			$sublabel = $row['sublabel'] ?? null;
			$city = is_string($sublabel) && trim($sublabel) !== '' ? trim($sublabel) : '';
			$detail = $this->detail($locale, $slug);
			$types = [];
			$url = self::listingUrl($locale, $slug);
			$name = trim($label);
			if ($detail === null) {
				$failures++;
			} else {
				if ($detail['name'] !== null) {
					$name = $detail['name'];
				}
				if ($detail['city'] !== null) {
					$city = $detail['city'];
				}
				$types = $detail['types'];
				$url = $detail['url'] ?? $url;
			}
			if ($city === '') {
				$skipped++;
				continue;
			}
			$workspaces[] = [
				'name' => $name,
				'city' => $city,
				'types' => $types,
				'url' => $url,
			];
		}
		return [
			'citySlug' => null,
			'cityName' => null,
			'type' => null,
			'workspaces' => $workspaces,
			'total' => count($workspaces),
			'detailFailures' => $failures,
			'skipped' => $skipped,
			'citation' => $this->citation($payload),
			'notice' => $this->notice($payload),
			'moreUrl' => $this->moreUrl($payload),
		];
	}

	public static function listingUrl(string $locale, string $slug): string {
		$path = self::LISTING_PATH[$locale] ?? self::LISTING_PATH['en'];
		return self::SITE_URL . '/' . $locale . '/' . $path . '/' . rawurlencode($slug);
	}

	/**
	 * @param array<string, mixed> $payload
	 * @return list<array{slug: string, name: string, countryCode: ?string}>
	 */
	private function citiesFromBootstrap(array $payload): array {
		$data = $payload['data'] ?? null;
		$cities = is_array($data) ? ($data['cities'] ?? null) : null;
		if (!is_array($cities)) {
			throw new ApiException(200, 'BAD_RESPONSE', 'The CoworkingView API returned an unexpected city list.');
		}
		return $this->normalizeCities($cities);
	}

	/**
	 * @param array<string, mixed> $payload
	 * @return list<array{slug: string, name: string, countryCode: ?string}>
	 */
	private function citiesFromRates(array $payload): array {
		$data = $payload['data'] ?? null;
		$rows = is_array($data) ? ($data['cities'] ?? null) : null;
		if (!is_array($rows)) {
			throw new ApiException(200, 'BAD_RESPONSE', 'The CoworkingView API returned an unexpected city list.');
		}
		$flat = [];
		foreach ($rows as $item) {
			if (!is_array($item)) {
				continue;
			}
			$city = $item['city'] ?? null;
			if (!is_array($city)) {
				continue;
			}
			$flat[] = [
				'slug' => $city['slug'] ?? null,
				'name' => $city['name'] ?? null,
				'countryCode' => $item['countryCode'] ?? null,
				'propertyCount' => $item['propertyCount'] ?? null,
			];
		}
		return $this->normalizeCities($flat);
	}

	/**
	 * @param list<mixed> $rows
	 * @return list<array{slug: string, name: string, countryCode: ?string}>
	 */
	private function normalizeCities(array $rows): array {
		$found = [];
		foreach ($rows as $row) {
			if (!is_array($row)) {
				continue;
			}
			$slug = $row['slug'] ?? null;
			$name = $row['name'] ?? null;
			if (!is_string($slug) || !preg_match('/^[a-z0-9-]{1,200}$/', $slug)) {
				continue;
			}
			if (!is_string($name) || trim($name) === '') {
				continue;
			}
			if (array_key_exists('propertyCount', $row)) {
				$count = $row['propertyCount'];
				if ($count === 0 || $count === 0.0 || $count === '0') {
					continue;
				}
			}
			$country = $row['countryCode'] ?? null;
			if (!is_string($country) || strlen(trim($country)) !== 2) {
				$country = null;
			} else {
				$country = strtoupper(trim($country));
			}
			$found[$slug] = [
				'slug' => $slug,
				'name' => trim($name),
				'countryCode' => $country,
			];
		}
		$cities = array_values($found);
		usort($cities, static function (array $a, array $b): int {
			$byName = strcasecmp($a['name'], $b['name']);
			return $byName !== 0 ? $byName : strcmp($a['slug'], $b['slug']);
		});
		return $cities;
	}

	/**
	 * @return array{slug: string, name: ?string, city: ?string}|null
	 */
	private function card(mixed $row): ?array {
		if (!is_array($row)) {
			return null;
		}
		$slug = $row['slug'] ?? null;
		if (!is_string($slug) || !preg_match('/^[A-Za-z0-9][A-Za-z0-9._-]{0,199}$/', $slug)) {
			return null;
		}
		$title = $row['title'] ?? null;
		return [
			'slug' => $slug,
			'name' => is_string($title) && trim($title) !== '' ? trim($title) : null,
			'city' => $this->cityNameOf($row),
		];
	}

	/**
	 * @return array{name: ?string, city: ?string, types: list<string>, url: ?string}|null
	 */
	private function detail(string $locale, string $slug): ?array {
		$path = '/v1/properties/' . rawurlencode($slug);
		try {
			$payload = $this->get($path, ['locale' => $locale]);
		} catch (ApiException) {
			return null;
		}
		$data = $payload['data'] ?? null;
		if (!is_array($data)) {
			return null;
		}
		$types = [];
		$options = $data['pricingOptions'] ?? [];
		if (is_array($options)) {
			foreach ($options as $option) {
				if (is_array($option) && isset($option['optionType']) && is_string($option['optionType'])) {
					$types[] = $option['optionType'];
				}
			}
		}
		$title = $data['title'] ?? null;
		$webUrl = $data['webUrl'] ?? null;
		return [
			'name' => is_string($title) && trim($title) !== '' ? trim($title) : null,
			'city' => $this->cityNameOf($data),
			'types' => TypeCatalog::sort($types),
			'url' => is_string($webUrl) ? $this->acceptedListingUrl($webUrl, $locale, $slug) : null,
		];
	}

	/**
	 * @param array{slug: string, name: ?string, city: ?string} $card
	 * @param array{name: ?string, city: ?string, types: list<string>, url: ?string}|null $detail
	 * @return array{name: string, city: string, types: list<string>, url: string}|null
	 */
	private function workspace(array $card, ?array $detail, ?string $typeCode, string $locale): ?array {
		$name = $detail['name'] ?? $card['name'];
		$city = $detail['city'] ?? $card['city'];
		if ($name === null || $city === null) {
			return null;
		}
		$types = $detail['types'] ?? [];
		if ($types === [] && $typeCode !== null) {
			$types = [$typeCode];
		}
		$url = $detail['url'] ?? self::listingUrl($locale, $card['slug']);
		return [
			'name' => $name,
			'city' => $city,
			'types' => $types,
			'url' => $url,
		];
	}

	/**
	 * @param array<string, mixed> $source
	 */
	private function cityNameOf(array $source): ?string {
		$city = $source['city'] ?? null;
		if (!is_array($city)) {
			return null;
		}
		$name = $city['name'] ?? null;
		if (!is_string($name) || trim($name) === '') {
			return null;
		}
		return trim($name);
	}

	/**
	 * @param array<string, mixed> $payload
	 */
	private function pageTotal(array $payload): ?int {
		$meta = $payload['meta'] ?? null;
		$pagination = is_array($meta) ? ($meta['pagination'] ?? null) : null;
		if (!is_array($pagination)) {
			return null;
		}
		$total = $pagination['total'] ?? null;
		if (is_int($total)) {
			return $total;
		}
		if (is_string($total) && preg_match('/^\d+$/', $total)) {
			return (int)$total;
		}
		return null;
	}

	/**
	 * @param array<string, mixed> $payload
	 */
	private function citation(array $payload): ?string {
		$meta = $payload['meta'] ?? null;
		$citation = is_array($meta) ? ($meta['citation'] ?? null) : null;
		if (!is_array($citation)) {
			return null;
		}
		$text = $citation['text'] ?? null;
		if (!is_string($text) || trim($text) === '') {
			return null;
		}
		return trim($text);
	}

	/**
	 * @param array<string, mixed> $payload
	 */
	private function notice(array $payload): ?string {
		$meta = $payload['meta'] ?? null;
		if (!is_array($meta)) {
			return null;
		}
		$notice = $meta['catalogueNotice'] ?? null;
		if (!is_string($notice) || trim($notice) === '') {
			return null;
		}
		return trim($notice);
	}

	/**
	 * @param array<string, mixed> $payload
	 */
	private function moreUrl(array $payload): ?string {
		$meta = $payload['meta'] ?? null;
		$citation = is_array($meta) ? ($meta['citation'] ?? null) : null;
		if (!is_array($citation)) {
			return null;
		}
		$url = $citation['url'] ?? null;
		if (!is_string($url)) {
			return null;
		}
		return $this->acceptedSiteUrl($url);
	}

	private function acceptedListingUrl(string $url, string $locale, string $slug): string {
		$accepted = $this->acceptedSiteUrl($url);
		if ($accepted === null) {
			return self::listingUrl($locale, $slug);
		}
		return $accepted;
	}

	private function acceptedSiteUrl(string $url): ?string {
		$parsed = parse_url(trim($url));
		if (!is_array($parsed)) {
			return null;
		}
		$scheme = strtolower((string)($parsed['scheme'] ?? ''));
		$host = strtolower((string)($parsed['host'] ?? ''));
		$path = (string)($parsed['path'] ?? '');
		if ($scheme !== 'https' || !in_array($host, self::LISTING_HOSTS, true)) {
			return null;
		}
		if ($path === '' || $path === '/') {
			return null;
		}
		return trim($url);
	}

	/**
	 * @param array<string, mixed> $row
	 */
	private function cityTermMatches(string $term, array $row): bool {
		$needle = mb_strtolower($term);
		foreach (['label', 'slug'] as $key) {
			$value = $row[$key] ?? null;
			if (is_string($value) && mb_strtolower(trim($value)) === $needle) {
				return true;
			}
		}
		return false;
	}

	/**
	 * @return array{
	 *   citySlug: ?string,
	 *   cityName: ?string,
	 *   type: ?string,
	 *   workspaces: list<empty>,
	 *   total: int,
	 *   detailFailures: int,
	 *   skipped: int,
	 *   citation: null,
	 *   notice: null,
	 *   moreUrl: null
	 * }
	 */
	private function emptySearch(?string $citySlug, ?string $cityName): array {
		return [
			'citySlug' => $citySlug,
			'cityName' => $cityName,
			'type' => null,
			'workspaces' => [],
			'total' => 0,
			'detailFailures' => 0,
			'skipped' => 0,
			'citation' => null,
			'notice' => null,
			'moreUrl' => null,
		];
	}

	private function locale(string $locale): string {
		$locale = strtolower(substr(str_replace('-', '_', $locale), 0, 2));
		if (!in_array($locale, self::LOCALES, true)) {
			throw new ApiException(400, 'BAD_LOCALE', 'The locale must be en, de, or es.');
		}
		return $locale;
	}

	private function citySlug(string $citySlug): string {
		$citySlug = trim($citySlug);
		if (!preg_match('/^[a-z0-9-]{1,200}$/', $citySlug)) {
			throw new ApiException(400, 'BAD_CITY', 'Choose a city from the list.');
		}
		return $citySlug;
	}

	private function typeCode(?string $typeCode): ?string {
		if ($typeCode === null) {
			return null;
		}
		$typeCode = trim($typeCode);
		if ($typeCode === '') {
			return null;
		}
		if (!TypeCatalog::isKnown($typeCode)) {
			throw new ApiException(400, 'BAD_TYPE', 'That workspace type is not available.');
		}
		return $typeCode;
	}

	private function limit(int $limit): int {
		if ($limit < 1) {
			return 1;
		}
		return min(self::MAX_PAGE_SIZE, $limit);
	}

	/**
	 * @param array<string, scalar|null> $query
	 * @return array<string, mixed>
	 */
	private function get(string $path, array $query): array {
		$url = $this->url($path, $query);
		$headers = [
			'User-Agent' => self::USER_AGENT,
			'Accept' => 'application/json',
		];
		$last = null;
		for ($attempt = 1; $attempt <= 2; $attempt++) {
			try {
				[$status, $responseHeaders, $body] = ($this->transport)($url, $headers, $this->timeout);
			} catch (ApiException $e) {
				throw $e;
			} catch (\Throwable $e) {
				throw new ApiException(0, 'CONNECTION', 'Could not reach the CoworkingView API.', '', $e);
			}
			$responseHeaders = $this->normalizeHeaders($responseHeaders);
			if ($status >= 200 && $status <= 299) {
				$decoded = json_decode($body, true);
				if (!is_array($decoded)) {
					throw new ApiException($status, 'BAD_RESPONSE', 'The CoworkingView API returned a non-JSON response.');
				}
				return $decoded;
			}
			$last = $this->problem($status, $body);
			if ($attempt === 1 && ($status === 429 || $status >= 500)) {
				($this->sleep)($this->retryWait($responseHeaders));
				continue;
			}
			throw $last;
		}
		throw $last ?? new ApiException(0, 'HTTP', 'The CoworkingView API request failed.');
	}

	/**
	 * @param array<string, scalar|null> $query
	 */
	private function url(string $path, array $query): string {
		$pairs = [];
		foreach ($query as $key => $value) {
			if ($value === null || $value === '') {
				continue;
			}
			$pairs[$key] = $value;
		}
		$url = $this->baseUrl . $path;
		if ($pairs !== []) {
			$url .= '?' . http_build_query($pairs, '', '&', PHP_QUERY_RFC3986);
		}
		return $url;
	}

	private function problem(int $status, string $body): ApiException {
		$decoded = json_decode($body, true);
		if (!is_array($decoded)) {
			return new ApiException($status, 'BAD_RESPONSE', 'The CoworkingView API returned a non-JSON response.');
		}
		$code = $decoded['code'] ?? null;
		if (!is_string($code) || $code === '') {
			$code = 'HTTP_' . $status;
		}
		$title = $decoded['title'] ?? null;
		if (!is_string($title) || $title === '') {
			$title = 'CoworkingView request failed';
		}
		$detail = $decoded['detail'] ?? '';
		if (!is_string($detail)) {
			$detail = '';
		}
		return new ApiException($status, $code, $title, $detail);
	}

	/**
	 * @param array<string, string> $headers
	 */
	private function retryWait(array $headers): float {
		$retry = $headers['retry-after'] ?? null;
		$reset = $headers['ratelimit-reset'] ?? null;
		$seconds = 2.0;
		if ($retry !== null && is_numeric($retry)) {
			$seconds = (float)$retry;
		} elseif ($reset !== null && is_numeric($reset)) {
			$seconds = (float)$reset;
		}
		if ($seconds < 0) {
			$seconds = 0.0;
		}
		return min($seconds, 10.0);
	}

	/**
	 * @param array<string, mixed> $headers
	 * @return array<string, string>
	 */
	private function normalizeHeaders(array $headers): array {
		$flat = [];
		foreach ($headers as $name => $value) {
			if (is_array($value)) {
				$value = $value[0] ?? '';
			}
			if (!is_string($name) || (!is_string($value) && !is_numeric($value))) {
				continue;
			}
			$flat[strtolower($name)] = (string)$value;
		}
		return $flat;
	}

	private static function normalizeBaseUrl(string $baseUrl): string {
		$baseUrl = rtrim(trim($baseUrl), '/');
		$parsed = parse_url($baseUrl);
		$scheme = is_array($parsed) ? strtolower((string)($parsed['scheme'] ?? '')) : '';
		$host = is_array($parsed) ? (string)($parsed['host'] ?? '') : '';
		if (!in_array($scheme, ['https', 'http'], true) || $host === '') {
			throw new ApiException(0, 'BAD_BASE_URL', 'COWORKINGVIEW_API_URL must be an http(s) URL.');
		}
		return $baseUrl;
	}
}
