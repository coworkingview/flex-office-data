<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 CoworkingView <info@coworkingview.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\CoworkingView\Service;

/**
 * HTTP transport used when the app is not going through Nextcloud's client.
 * Redirects are not followed. Only http and https are allowed.
 */
final class CurlTransport {
	/**
	 * @param array<string, string> $headers
	 * @return array{0: int, 1: array<string, string>, 2: string}
	 */
	public function __invoke(string $url, array $headers, float $timeout): array {
		if (!function_exists('curl_init')) {
			throw new ApiException(0, 'CONNECTION', 'Could not reach the CoworkingView API.', 'The curl extension is not available.');
		}
		$handle = curl_init($url);
		if ($handle === false) {
			throw new ApiException(0, 'CONNECTION', 'Could not reach the CoworkingView API.');
		}
		$headerLines = [];
		foreach ($headers as $name => $value) {
			$headerLines[] = $name . ': ' . $value;
		}
		$seconds = (int)ceil($timeout);
		if ($seconds < 1) {
			$seconds = 1;
		}
		curl_setopt_array($handle, [
			CURLOPT_RETURNTRANSFER => true,
			CURLOPT_HEADER => true,
			CURLOPT_TIMEOUT => $seconds,
			CURLOPT_CONNECTTIMEOUT => min(10, $seconds),
			CURLOPT_HTTPHEADER => $headerLines,
			CURLOPT_FOLLOWLOCATION => false,
			CURLOPT_PROTOCOLS => CURLPROTO_HTTP | CURLPROTO_HTTPS,
		]);
		$raw = curl_exec($handle);
		if (!is_string($raw)) {
			$error = curl_error($handle);
			curl_close($handle);
			throw new ApiException(0, 'CONNECTION', 'Could not reach the CoworkingView API.', $error);
		}
		$status = (int)curl_getinfo($handle, CURLINFO_RESPONSE_CODE);
		$headerSize = (int)curl_getinfo($handle, CURLINFO_HEADER_SIZE);
		curl_close($handle);
		$rawHeaders = substr($raw, 0, $headerSize);
		$body = substr($raw, $headerSize);
		return [$status, $this->parseHeaders($rawHeaders), $body];
	}

	/**
	 * @return array<string, string>
	 */
	private function parseHeaders(string $raw): array {
		$headers = [];
		foreach (preg_split("/\r\n|\n|\r/", $raw) ?: [] as $line) {
			$colon = strpos($line, ':');
			if ($colon === false) {
				continue;
			}
			$name = strtolower(trim(substr($line, 0, $colon)));
			$value = trim(substr($line, $colon + 1));
			if ($name !== '') {
				$headers[$name] = $value;
			}
		}
		return $headers;
	}
}
