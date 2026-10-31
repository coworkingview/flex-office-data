<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 CoworkingView <info@coworkingview.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\CoworkingView\Service;

/**
 * Small cache used for stripped catalogue responses.
 *
 * Implementations must store only the values this app puts in. Those values
 * are name, city, workspace type and listing URL, plus the citation.
 */
interface CacheStore {
	public function get(string $key): mixed;

	public function set(string $key, mixed $value, int $ttl): void;
}
