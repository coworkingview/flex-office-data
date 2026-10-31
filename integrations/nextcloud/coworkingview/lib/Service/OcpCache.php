<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 CoworkingView <info@coworkingview.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\CoworkingView\Service;

use OCP\ICache;

/**
 * Nextcloud distributed cache. Values are the stripped catalogue arrays.
 */
final class OcpCache implements CacheStore {
	public function __construct(
		private readonly ICache $cache,
	) {
	}

	public function get(string $key): mixed {
		return $this->cache->get($key);
	}

	public function set(string $key, mixed $value, int $ttl): void {
		$this->cache->set($key, $value, $ttl);
	}
}
