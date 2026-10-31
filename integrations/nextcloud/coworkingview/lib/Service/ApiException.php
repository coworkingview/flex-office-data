<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 CoworkingView <info@coworkingview.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\CoworkingView\Service;

/**
 * A CoworkingView request could not be completed.
 *
 * status is the HTTP status, or 0 when the API was not reached.
 * errorCode is the problem code, HTTP_<status>, BAD_RESPONSE, or CONNECTION.
 */
final class ApiException extends \RuntimeException {
	public function __construct(
		public readonly int $status,
		public readonly string $errorCode,
		string $title,
		public readonly string $detail = '',
		?\Throwable $previous = null,
	) {
		$message = $detail !== '' ? $title . ' ' . $detail : $title;
		parent::__construct(trim($message), $status, $previous);
	}
}
