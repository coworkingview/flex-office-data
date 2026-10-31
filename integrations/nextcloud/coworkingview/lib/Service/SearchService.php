<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 CoworkingView <info@coworkingview.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\CoworkingView\Service;

use OCP\Http\Client\IClientService;
use OCP\ICacheFactory;

/**
 * The catalogue the dashboard and unified search share.
 * Responses are cached for ten minutes. The cache holds the stripped result.
 */
final class SearchService {
	private CachingCatalogue $cached;

	public function __construct(
		IClientService $clientService,
		ICacheFactory $cacheFactory,
	) {
		$catalogue = Catalogue::create(
			static function (string $url, array $headers, float $timeout) use ($clientService): array {
				return NextcloudTransport::request($clientService, $url, $headers, $timeout);
			},
		);
		$this->cached = new CachingCatalogue(
			$catalogue,
			new OcpCache($cacheFactory->createDistributed('coworkingview')),
		);
	}

	/**
	 * @return list<array{slug: string, name: string, countryCode: ?string}>
	 */
	public function cities(string $locale): array {
		return $this->cached->cities($locale);
	}

	/**
	 * @return array<string, mixed>
	 */
	public function search(string $locale, string $citySlug, ?string $typeCode, int $limit = Catalogue::PAGE_SIZE): array {
		return $this->cached->search($locale, $citySlug, $typeCode, $limit);
	}

	/**
	 * @return array<string, mixed>
	 */
	public function unified(string $locale, string $term, int $limit = Catalogue::PAGE_SIZE): array {
		return $this->cached->unified($locale, $term, $limit);
	}
}
