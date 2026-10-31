<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 CoworkingView <info@coworkingview.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\CoworkingView\Tests\Unit;

use OCA\CoworkingView\Service\ApiException;
use OCA\CoworkingView\Service\CacheStore;
use OCA\CoworkingView\Service\CachingCatalogue;
use OCA\CoworkingView\Service\Catalogue;
use PHPUnit\Framework\TestCase;

final class ArrayCache implements CacheStore {
	/** @var array<string, mixed> */
	public array $values = [];

	/** @var array<string, int> */
	public array $ttls = [];

	public function get(string $key): mixed {
		return $this->values[$key] ?? null;
	}

	public function set(string $key, mixed $value, int $ttl): void {
		$this->values[$key] = $value;
		$this->ttls[$key] = $ttl;
	}
}

final class CachingCatalogueTest extends TestCase {
	public function testSuccessfulSearchIsCachedAndStripped(): void {
		$calls = 0;
		$transport = static function (string $url, array $headers, float $timeout) use (&$calls): array {
			$calls++;
			if (str_contains($url, '/v1/properties/')) {
				$body = json_encode([
					'data' => [
						'title' => 'Space',
						'city' => ['name' => 'Berlin'],
						'webUrl' => 'https://coworkingview.com/en/workspace/space',
						'description' => 'Do not store',
						'pricingOptions' => [
							['optionType' => 'day_pass', 'price' => ['amount' => 35, 'currency' => 'EUR']],
						],
					],
				]);
				return [200, [], (string)$body];
			}
			$body = json_encode([
				'data' => [[
					'slug' => 'space',
					'title' => 'Space',
					'city' => ['name' => 'Berlin'],
					'excerpt' => 'Do not store',
					'fromPrice' => ['amount' => 35, 'currency' => 'EUR'],
				]],
				'meta' => [
					'pagination' => ['total' => 1],
					'citation' => ['text' => 'Source: CoworkingView', 'url' => 'https://coworkingview.com/en/coworking/berlin'],
					'catalogueNotice' => 'You may link to listing pages.',
				],
			]);
			return [200, [], (string)$body];
		};
		$cache = new ArrayCache();
		$catalogue = new CachingCatalogue(
			new Catalogue('https://api.coworkingview.com', $transport, static function (float $seconds): void {
			}),
			$cache,
		);
		$first = $catalogue->search('en', 'berlin', 'day_pass');
		$second = $catalogue->search('en', 'berlin', 'day_pass');
		$this->assertSame($first, $second);
		$this->assertSame(2, $calls);
		$this->assertSame(600, array_values($cache->ttls)[0]);
		$stored = (string)json_encode($cache->values, JSON_UNESCAPED_SLASHES);
		$this->assertStringNotContainsString('Do not store', $stored);
		$this->assertStringNotContainsString('amount', $stored);
		$this->assertStringNotContainsString('excerpt', $stored);
		$this->assertStringContainsString('https://coworkingview.com/en/workspace/space', $stored);
		$this->assertSame('https://coworkingview.com/en/workspace/space', $first['workspaces'][0]['url']);
	}

	public function testErrorsAreNotCached(): void {
		$calls = 0;
		$transport = static function (string $url, array $headers, float $timeout) use (&$calls): array {
			$calls++;
			return [400, [], '{"title":"Validation failed","status":400,"code":"VALIDATION_FAILED","detail":"no"}'];
		};
		$cache = new ArrayCache();
		$catalogue = new CachingCatalogue(
			new Catalogue('https://api.coworkingview.com', $transport, static function (float $seconds): void {
			}),
			$cache,
		);
		for ($i = 0; $i < 2; $i++) {
			try {
				$catalogue->cities('en');
				$this->fail('expected ApiException');
			} catch (ApiException $e) {
				$this->assertSame('VALIDATION_FAILED', $e->errorCode);
			}
		}
		$this->assertSame([], $cache->values);
		$this->assertGreaterThanOrEqual(2, $calls);
	}
}
