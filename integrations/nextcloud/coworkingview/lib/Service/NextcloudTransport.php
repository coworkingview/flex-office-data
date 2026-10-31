<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 CoworkingView <info@coworkingview.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\CoworkingView\Service;

use OCP\Http\Client\IClientService;

/**
 * Sends catalogue requests through Nextcloud's HTTP client so the server
 * proxy configuration is used. Non-2xx responses are returned to the caller
 * instead of being thrown away, so retry and problem-document handling stay
 * in Catalogue.
 */
final class NextcloudTransport {
	/**
	 * @param array<string, string> $headers
	 * @return array{0: int, 1: array<string, string>, 2: string}
	 */
	public static function request(IClientService $clients, string $url, array $headers, float $timeout): array {
		$client = $clients->newClient();
		$options = [
			'timeout' => $timeout,
			'headers' => $headers,
		];
		try {
			$response = $client->get($url, $options);
		} catch (\Throwable $e) {
			$response = method_exists($e, 'getResponse') ? $e->getResponse() : null;
			if ($response === null) {
				throw new ApiException(0, 'CONNECTION', 'Could not reach the CoworkingView API.', '', $e);
			}
		}
		$status = $response->getStatusCode();
		$body = $response->getBody();
		$flat = [];
		foreach ($response->getHeaders() as $name => $value) {
			if (is_array($value)) {
				$value = $value[0] ?? '';
			}
			if (is_string($name) && (is_string($value) || is_numeric($value))) {
				$flat[strtolower($name)] = (string)$value;
			}
		}
		return [$status, $flat, $body];
	}
}
