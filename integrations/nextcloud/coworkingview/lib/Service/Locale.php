<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 CoworkingView <info@coworkingview.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\CoworkingView\Service;

/**
 * Maps a Nextcloud language code to a CoworkingView locale.
 * Anything other than English, German or Spanish uses English.
 */
final class Locale {
	public static function fromLanguage(string $language): string {
		$primary = strtolower(substr(str_replace('-', '_', $language), 0, 2));
		return in_array($primary, ['en', 'de', 'es'], true) ? $primary : 'en';
	}
}
