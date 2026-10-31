<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 CoworkingView <info@coworkingview.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\CoworkingView\Service;

/**
 * Workspace-type codes the public API accepts as pricingOptionType.
 *
 * Labels are the English source strings. ApiController translates the same
 * literals. Unknown codes are kept as returned and are not given a new name.
 */
final class TypeCatalog {
	public const ORDER = [
		'flex_desk',
		'fix_desk',
		'private_office',
		'exclusive_bereich',
		'day_pass',
		'meeting_room',
		'event_space',
		'virtual_office',
		'membership',
	];

	public const LABELS = [
		'flex_desk' => 'Flex desk',
		'fix_desk' => 'Dedicated desk',
		'private_office' => 'Private office',
		'exclusive_bereich' => 'Exclusive area',
		'day_pass' => 'Day pass',
		'meeting_room' => 'Meeting room',
		'event_space' => 'Event space',
		'virtual_office' => 'Virtual office',
		'membership' => 'Membership',
	];

	public static function isKnown(string $code): bool {
		return isset(self::LABELS[$code]);
	}

	public static function englishLabel(string $code): string {
		return self::LABELS[$code] ?? $code;
	}

	/**
	 * @param list<string> $codes
	 * @return list<string>
	 */
	public static function sort(array $codes): array {
		$seen = [];
		foreach ($codes as $code) {
			if (!is_string($code) || $code === '' || isset($seen[$code])) {
				continue;
			}
			if (!preg_match('/^[a-z0-9_]{1,40}$/', $code)) {
				continue;
			}
			$seen[$code] = true;
		}
		$ordered = array_keys($seen);
		$rank = array_flip(self::ORDER);
		usort($ordered, static function (string $a, string $b) use ($rank): int {
			$aKnown = array_key_exists($a, $rank);
			$bKnown = array_key_exists($b, $rank);
			if ($aKnown && $bKnown) {
				return $rank[$a] <=> $rank[$b];
			}
			if ($aKnown !== $bKnown) {
				return $aKnown ? -1 : 1;
			}
			return $a <=> $b;
		});
		return $ordered;
	}
}
