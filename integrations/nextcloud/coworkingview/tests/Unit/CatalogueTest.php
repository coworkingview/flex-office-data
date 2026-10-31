<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 CoworkingView <info@coworkingview.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\CoworkingView\Tests\Unit;

use OCA\CoworkingView\Service\ApiException;
use OCA\CoworkingView\Service\Catalogue;
use OCA\CoworkingView\Service\TypeCatalog;
use PHPUnit\Framework\TestCase;

final class QueueTransport {
	/** @var list<array{0: string, 1: array<string, string>}> */
	public array $calls = [];

	/** @var list<array{0: int, 1: array<string, string>, 2: string}|\Throwable> */
	public array $responses = [];

	/**
	 * @param array<string, string> $headers
	 * @return array{0: int, 1: array<string, string>, 2: string}
	 */
	public function __invoke(string $url, array $headers, float $timeout): array {
		$this->calls[] = [$url, $headers];
		if ($this->responses === []) {
			throw new \RuntimeException('No scripted response for ' . $url);
		}
		$next = array_shift($this->responses);
		if ($next instanceof \Throwable) {
			throw $next;
		}
		return $next;
	}
}

final class CatalogueTest extends TestCase {
	private function fixture(string $name): string {
		$path = dirname(__DIR__, 5) . '/spec/fixtures/' . $name;
		$contents = file_get_contents($path);
		$this->assertIsString($contents, $path);
		return $contents;
	}

	/**
	 * @param list<float>|null $sleeps
	 */
	private function catalogue(QueueTransport $transport, ?array &$sleeps = null): Catalogue {
		if ($sleeps === null) {
			$sleeps = [];
		}
		return new Catalogue(
			'https://api.coworkingview.com',
			\Closure::fromCallable($transport),
			static function (float $seconds) use (&$sleeps): void {
				$sleeps[] = $seconds;
			},
		);
	}

	public function testSearchKeepsNameCityTypeAndLinkOnly(): void {
		$list = $this->fixture('properties_berlin.json');
		$detail = $this->fixture('property_detail.json');
		$problem = '{"type":"about:blank","title":"Not found","status":404,"code":"NOT_FOUND","detail":"No such listing"}';
		$transport = new QueueTransport();
		$transport->responses = [
			[200, [], $list],
			[200, [], $detail],
			[404, [], $problem],
			[404, [], $problem],
		];
		$sleeps = [];
		$result = $this->catalogue($transport, $sleeps)->search('en', 'berlin', 'private_office', 8);

		$this->assertSame([], $sleeps);
		$this->assertCount(4, $transport->calls);
		$this->assertStringContainsString('/v1/properties?', $transport->calls[0][0]);
		$this->assertStringNotContainsString('page=2', $transport->calls[0][0]);
		$this->assertSame(
			'coworkingview-nextcloud/1.0.0 (+https://github.com/coworkingview/flex-office-data)',
			$transport->calls[0][1]['User-Agent'],
		);
		$this->assertSame('application/json', $transport->calls[0][1]['Accept']);
		$this->assertSame('berlin', $result['citySlug']);
		$this->assertSame('Berlin', $result['cityName']);
		$this->assertSame('private_office', $result['type']);
		$this->assertSame(110, $result['total']);
		$this->assertSame(2, $result['detailFailures']);
		$this->assertCount(3, $result['workspaces']);

		$first = $result['workspaces'][0];
		$this->assertSame(
			['name', 'city', 'types', 'url'],
			array_keys($first),
		);
		$this->assertSame('St. Oberholz Coworking Berlin Mitte – Rosenthaler Straße', $first['name']);
		$this->assertSame('Berlin', $first['city']);
		$this->assertSame(
			['flex_desk', 'fix_desk', 'private_office', 'meeting_room', 'virtual_office'],
			$first['types'],
		);
		$this->assertSame(
			'https://coworkingview.com/en/workspace/sankt-oberholz-rosenthaler-berlin',
			$first['url'],
		);
		$this->assertSame(['private_office'], $result['workspaces'][1]['types']);
		$this->assertStringStartsWith('https://coworkingview.com/en/workspace/', $result['workspaces'][1]['url']);
		$this->assertNotNull($result['citation']);
		$this->assertStringContainsString('https://coworkingview.com/en/coworking/berlin', (string)$result['citation']);
		$this->assertNotNull($result['notice']);
		$this->assertSame('https://coworkingview.com/en/coworking/berlin', $result['moreUrl']);

		$encoded = json_encode($result, JSON_UNESCAPED_SLASHES);
		$this->assertIsString($encoded);
		foreach (['excerpt', 'fromPrice', 'amenities', 'amount', 'Example description', 'example.com'] as $forbidden) {
			$this->assertStringNotContainsString($forbidden, $encoded);
		}
	}

	public function testMissingDetailDoesNotInventAType(): void {
		$list = $this->fixture('properties_berlin.json');
		$problem = '{"title":"Not found","status":404,"code":"NOT_FOUND","detail":"No such listing"}';
		$transport = new QueueTransport();
		$transport->responses = [
			[200, [], $list],
			[404, [], $problem],
			[404, [], $problem],
			[404, [], $problem],
		];
		$result = $this->catalogue($transport)->search('de', 'berlin', null, 8);
		$this->assertSame([], $result['workspaces'][0]['types']);
		$this->assertSame(
			'https://coworkingview.com/de/buero/sankt-oberholz-rosenthaler-berlin',
			$result['workspaces'][0]['url'],
		);
	}

	public function testRejectsListingUrlsOutsideCoworkingView(): void {
		$card = [
			'slug' => 'space-1',
			'title' => 'Space One',
			'city' => ['slug' => 'madrid', 'name' => 'Madrid'],
		];
		$detail = [
			'data' => [
				'title' => 'Space One',
				'city' => ['slug' => 'madrid', 'name' => 'Madrid'],
				'webUrl' => 'javascript:alert(1)',
				'pricingOptions' => [
					['optionType' => 'meeting_room', 'price' => ['amount' => 10, 'currency' => 'EUR']],
				],
				'description' => 'Should not be copied',
				'images' => [['url' => 'https://example.com/photo.jpg']],
			],
			'meta' => [
				'citation' => [
					'text' => 'Source: CoworkingView',
					'url' => 'http://coworkingview.com/en/coworking/madrid',
				],
			],
		];
		$transport = new QueueTransport();
		$transport->responses = [
			[200, [], (string)json_encode(['data' => [$card], 'meta' => ['pagination' => ['total' => 1]]])],
			[200, [], (string)json_encode($detail)],
		];
		$result = $this->catalogue($transport)->search('es', 'madrid', 'meeting_room');
		$this->assertSame(
			'https://coworkingview.com/es/oficina/space-1',
			$result['workspaces'][0]['url'],
		);
		$this->assertSame(['meeting_room'], $result['workspaces'][0]['types']);
		$this->assertNull($result['moreUrl']);
		$encoded = (string)json_encode($result);
		$this->assertStringNotContainsString('javascript:', $encoded);
		$this->assertStringNotContainsString('example.com', $encoded);
		$this->assertStringNotContainsString('Should not be copied', $encoded);
		$this->assertStringNotContainsString('amount', $encoded);
	}

	public function testCitiesPreferBootstrapAndSkipEmptyCities(): void {
		$body = (string)json_encode([
			'data' => [
				'cities' => [
					['slug' => 'madrid', 'name' => 'Madrid', 'countryCode' => 'es', 'propertyCount' => 12],
					['slug' => 'empty-city', 'name' => 'Empty', 'countryCode' => 'DE', 'propertyCount' => 0],
					['slug' => 'berlin', 'name' => 'Berlin', 'countryCode' => 'DE', 'propertyCount' => 3],
				],
			],
		]);
		$transport = new QueueTransport();
		$transport->responses = [[200, [], $body]];
		$cities = $this->catalogue($transport)->cities('en');
		$this->assertSame(['berlin', 'madrid'], array_column($cities, 'slug'));
		$this->assertSame('DE', $cities[0]['countryCode']);
		$this->assertSame('ES', $cities[1]['countryCode']);
		$this->assertCount(1, $transport->calls);
	}

	public function testCitiesFallBackToPublishedPriceIndexCities(): void {
		$transport = new QueueTransport();
		$transport->responses = [
			[502, [], '{"title":"Bad gateway","status":502,"code":"UPSTREAM_UNAVAILABLE","detail":"down"}'],
			[502, [], '{"title":"Bad gateway","status":502,"code":"UPSTREAM_UNAVAILABLE","detail":"down"}'],
			[200, [], $this->fixture('market_rates.json')],
		];
		$sleeps = [];
		$cities = $this->catalogue($transport, $sleeps)->cities('en');
		$slugs = array_column($cities, 'slug');
		$this->assertContains('berlin', $slugs);
		$this->assertContains('madrid', $slugs);
		$this->assertNotContains('example-town', $slugs);
		$this->assertNotContains('cowos-kolonnenstrasse-schoeneberg-berlin', $slugs);
		$encoded = (string)json_encode($cities);
		$this->assertStringNotContainsString('amount', $encoded);
		$this->assertStringNotContainsString('entryMedian', $encoded);
		$this->assertSame([2.0], $sleeps);
		$this->assertStringContainsString('/v1/market/rates', $transport->calls[2][0]);
	}

	public function testRetriesOnceAndCapsTheWait(): void {
		$transport = new QueueTransport();
		$transport->responses = [
			[500, ['Retry-After' => '99'], '{"title":"unavailable","status":500,"code":"INTERNAL_ERROR"}'],
			[200, [], '{"data":{"cities":[{"slug":"berlin","name":"Berlin","countryCode":"DE","propertyCount":4}]}}'],
		];
		$sleeps = [];
		$cities = $this->catalogue($transport, $sleeps)->cities('en');
		$this->assertSame('berlin', $cities[0]['slug']);
		$this->assertSame([10.0], $sleeps);
		$this->assertCount(2, $transport->calls);
	}

	public function testDoesNotRetryAValidationError(): void {
		$transport = new QueueTransport();
		$transport->responses = [
			[400, [], '{"title":"Validation failed","status":400,"code":"VALIDATION_FAILED","detail":"city is invalid"}'],
		];
		$sleeps = [];
		try {
			$this->catalogue($transport, $sleeps)->search('en', 'berlin', null);
			$this->fail('expected ApiException');
		} catch (ApiException $e) {
			$this->assertSame(400, $e->status);
			$this->assertSame('VALIDATION_FAILED', $e->errorCode);
			$this->assertSame('city is invalid', $e->detail);
		}
		$this->assertSame([], $sleeps);
		$this->assertCount(1, $transport->calls);
	}

	public function testNonJsonBodyIsABadResponse(): void {
		$transport = new QueueTransport();
		$transport->responses = [[200, [], '<html>nope</html>']];
		try {
			$this->catalogue($transport)->search('en', 'berlin', null);
			$this->fail('expected ApiException');
		} catch (ApiException $e) {
			$this->assertSame('BAD_RESPONSE', $e->errorCode);
		}
	}

	public function testConnectionFailureUsesRetryAfterHeaderNameFromRateLimitReset(): void {
		$transport = new QueueTransport();
		$transport->responses = [
			[429, ['RateLimit-Reset' => '3'], 'not-json'],
			[200, [], '{"data":{"cities":[]}}'],
		];
		$sleeps = [];
		$this->catalogue($transport, $sleeps)->cities('en');
		$this->assertSame([3.0], $sleeps);
	}

	public function testRejectsUnknownTypeAndCityBeforeCallingTheApi(): void {
		$transport = new QueueTransport();
		$catalogue = $this->catalogue($transport);
		try {
			$catalogue->search('en', 'Berlin', 'private_office');
			$this->fail('expected bad city');
		} catch (ApiException $e) {
			$this->assertSame('BAD_CITY', $e->errorCode);
		}
		try {
			$catalogue->search('en', 'berlin', 'hot_desk');
			$this->fail('expected bad type');
		} catch (ApiException $e) {
			$this->assertSame('BAD_TYPE', $e->errorCode);
		}
		$this->assertSame([], $transport->calls);
	}

	public function testUnifiedSearchUsesPropertySuggestions(): void {
		$suggest = [
			'data' => [
				[
					'kind' => 'property',
					'slug' => 'sankt-oberholz-rosenthaler-berlin',
					'label' => 'St. Oberholz',
					'sublabel' => 'Berlin',
				],
				[
					'kind' => 'operator',
					'slug' => 'sankt-oberholz',
					'label' => 'St. Oberholz',
				],
			],
			'meta' => ['contractVersion' => '1.0.0'],
		];
		$transport = new QueueTransport();
		$transport->responses = [
			[200, [], (string)json_encode($suggest)],
			[200, [], $this->fixture('property_detail.json')],
		];
		$result = $this->catalogue($transport)->unified('en', 'Oberholz', 5);
		$this->assertCount(1, $result['workspaces']);
		$this->assertSame('Berlin', $result['workspaces'][0]['city']);
		$this->assertContains('flex_desk', $result['workspaces'][0]['types']);
		$this->assertStringStartsWith('https://coworkingview.com/en/workspace/', $result['workspaces'][0]['url']);
		foreach ($transport->calls as $call) {
			$this->assertStringNotContainsString('/v1/properties?', $call[0]);
		}
	}

	public function testUnifiedSearchOfACityNameLoadsThatCity(): void {
		$suggest = [
			'data' => [
				['kind' => 'city', 'slug' => 'berlin', 'label' => 'Berlin', 'sublabel' => 'Germany'],
			],
			'meta' => ['contractVersion' => '1.0.0'],
		];
		$transport = new QueueTransport();
		$transport->responses = [
			[200, [], (string)json_encode($suggest)],
			[200, [], $this->fixture('properties_empty.json')],
		];
		$result = $this->catalogue($transport)->unified('en', 'Berlin');
		$this->assertSame('berlin', $result['citySlug']);
		$this->assertSame([], $result['workspaces']);
		$this->assertStringContainsString('/v1/properties?', $transport->calls[1][0]);
		$this->assertStringContainsString('city=berlin', $transport->calls[1][0]);
	}

	public function testEmptyUnifiedTermDoesNotCallTheApi(): void {
		$transport = new QueueTransport();
		$result = $this->catalogue($transport)->unified('en', '   ');
		$this->assertSame([], $result['workspaces']);
		$this->assertSame([], $transport->calls);
	}

	public function testTypeOrderMatchesTheApi(): void {
		$this->assertSame(
			['flex_desk', 'meeting_room', 'other_type'],
			TypeCatalog::sort(['other_type', 'meeting_room', 'flex_desk', 'flex_desk', '<script>']),
		);
	}

	public function testTranslatedLabelsMatchTheCatalog(): void {
		$source = (string)file_get_contents(dirname(__DIR__, 2) . '/lib/Service/ResultPresenter.php');
		foreach (TypeCatalog::LABELS as $label) {
			$this->assertStringContainsString("'" . $label . "'", $source);
		}
		$widget = (string)file_get_contents(dirname(__DIR__, 2) . '/lib/Dashboard/Widget.php');
		$frontend = (string)file_get_contents(dirname(__DIR__, 2) . '/src/dashboard.js');
		$this->assertStringContainsString("return 'coworkingview';", $widget);
		$this->assertStringContainsString("dashboard.register('coworkingview'", $frontend);
	}

	public function testRejectsABadBaseUrl(): void {
		$this->expectException(ApiException::class);
		Catalogue::create(null, null, 'ftp://files.example');
	}
}
