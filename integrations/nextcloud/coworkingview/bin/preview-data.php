<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 CoworkingView <info@coworkingview.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

require dirname(__DIR__) . '/vendor/autoload.php';

use OCA\CoworkingView\Service\Catalogue;
use OCA\CoworkingView\Service\TypeCatalog;

/**
 * JSON the screenshot page feeds to the widget. Live catalogue first.
 * If the API cannot be reached, the shared Berlin fixture is used so the
 * picture is still rendered from real listings, not made-up ones.
 */
$labels = [];
foreach (TypeCatalog::ORDER as $code) {
	$labels[] = ['code' => $code, 'label' => TypeCatalog::englishLabel($code)];
}

$present = static function (array $result): array {
	$workspaces = [];
	foreach ($result['workspaces'] as $workspace) {
		$names = [];
		foreach ($workspace['types'] as $code) {
			$names[] = TypeCatalog::englishLabel($code);
		}
		$workspaces[] = [
			'name' => $workspace['name'],
			'city' => $workspace['city'],
			'typeLabel' => implode(', ', $names),
			'url' => $workspace['url'],
		];
	}
	$type = $result['type'];
	return [
		'citySlug' => $result['citySlug'],
		'cityName' => $result['cityName'],
		'type' => $type,
		'typeLabel' => is_string($type) ? TypeCatalog::englishLabel($type) : null,
		'workspaces' => $workspaces,
		'total' => $result['total'],
		'detailFailures' => $result['detailFailures'],
		'citation' => $result['citation'],
		'notice' => $result['notice'],
		'moreUrl' => $result['moreUrl'],
	];
};

try {
	$catalogue = Catalogue::create();
	$cities = $catalogue->cities('en');
	$result = $present($catalogue->search('en', 'berlin', 'private_office', 5));
} catch (Throwable $e) {
	fwrite(STDERR, 'Live preview failed, using fixtures: ' . $e->getMessage() . "\n");
	$root = dirname(__DIR__, 4);
	$list = json_decode((string)file_get_contents($root . '/spec/fixtures/properties_berlin.json'), true);
	$detail = json_decode((string)file_get_contents($root . '/spec/fixtures/property_detail.json'), true);
	$transport = static function (string $url) use ($list, $detail): array {
		if (str_contains($url, '/v1/properties/')) {
			return [200, [], (string)json_encode($detail)];
		}
		return [200, [], (string)json_encode($list)];
	};
	$catalogue = Catalogue::create($transport, static function (float $seconds): void {
	});
	$cities = [
		['slug' => 'berlin', 'name' => 'Berlin', 'countryCode' => 'DE'],
		['slug' => 'madrid', 'name' => 'Madrid', 'countryCode' => 'ES'],
	];
	$result = $present($catalogue->search('en', 'berlin', 'private_office', 5));
}

$payload = [
	'cities' => $cities,
	'types' => $labels,
	'city' => 'berlin',
	'type' => 'private_office',
	'result' => $result,
];

echo json_encode($payload, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR);
