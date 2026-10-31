<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 CoworkingView <info@coworkingview.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\CoworkingView\Service;

/**
 * Caches successful catalogue reads for the API's published max-age.
 * Failures are not cached. The cached value is the stripped result only.
 */
final class CachingCatalogue {
	public const TTL = 600;

	public function __construct(
		private readonly Catalogue $catalogue,
		private readonly CacheStore $cache,
		private readonly int $ttl = self::TTL,
	) {
	}

	/**
	 * @return list<array{slug: string, name: string, countryCode: ?string}>
	 */
	public function cities(string $locale): array {
		$key = 'v1:cities:' . $locale;
		$hit = $this->cache->get($key);
		if (is_array($hit)) {
			/** @var list<array{slug: string, name: string, countryCode: ?string}> $hit */
			return $hit;
		}
		$value = $this->catalogue->cities($locale);
		$this->cache->set($key, $value, $this->ttl);
		return $value;
	}

	/**
	 * @return array<string, mixed>
	 */
	public function search(string $locale, string $citySlug, ?string $typeCode, int $limit = Catalogue::PAGE_SIZE): array {
		$type = $typeCode ?? '';
		$key = 'v1:search:' . $locale . ':' . $citySlug . ':' . $type . ':' . $limit;
		return $this->remember($key, fn (): array => $this->catalogue->search($locale, $citySlug, $typeCode, $limit));
	}

	/**
	 * @return array<string, mixed>
	 */
	public function unified(string $locale, string $term, int $limit = Catalogue::PAGE_SIZE): array {
		$key = 'v1:unified:' . $locale . ':' . hash('sha256', trim($term)) . ':' . $limit;
		return $this->remember($key, fn (): array => $this->catalogue->unified($locale, $term, $limit));
	}

	/**
	 * @param \Closure(): array<string, mixed> $load
	 * @return array<string, mixed>
	 */
	private function remember(string $key, \Closure $load): array {
		$hit = $this->cache->get($key);
		if (is_array($hit)) {
			return $hit;
		}
		$value = $load();
		$this->cache->set($key, $value, $this->ttl);
		return $value;
	}
}
