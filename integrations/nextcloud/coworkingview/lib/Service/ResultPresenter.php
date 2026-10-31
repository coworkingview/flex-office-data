<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 CoworkingView <info@coworkingview.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\CoworkingView\Service;

use OCA\CoworkingView\AppInfo\Application;
use OCP\L10N\IFactory;

/**
 * Turns a stripped catalogue result into the JSON the widget and unified
 * search show: name, city, translated workspace type, and the listing URL.
 */
class ResultPresenter {
	public function __construct(
		private readonly IFactory $l10nFactory,
	) {
	}

	/**
	 * @param array<string, mixed> $result
	 * @return array<string, mixed>
	 */
	public function present(array $result): array {
		$workspaces = [];
		$rows = $result['workspaces'] ?? [];
		if (!is_array($rows)) {
			$rows = [];
		}
		foreach ($rows as $workspace) {
			if (!is_array($workspace)) {
				continue;
			}
			$types = is_array($workspace['types'] ?? null) ? $workspace['types'] : [];
			$labels = [];
			foreach ($types as $code) {
				if (is_string($code) && $code !== '') {
					$labels[] = $this->typeLabel($code);
				}
			}
			$workspaces[] = [
				'name' => (string)($workspace['name'] ?? ''),
				'city' => (string)($workspace['city'] ?? ''),
				'typeLabel' => implode(', ', $labels),
				'url' => (string)($workspace['url'] ?? ''),
			];
		}
		$type = $result['type'] ?? null;
		return [
			'citySlug' => $result['citySlug'] ?? null,
			'cityName' => $result['cityName'] ?? null,
			'type' => is_string($type) ? $type : null,
			'typeLabel' => is_string($type) ? $this->typeLabel($type) : null,
			'workspaces' => $workspaces,
			'total' => $result['total'] ?? null,
			'detailFailures' => (int)($result['detailFailures'] ?? 0),
			'citation' => $result['citation'] ?? null,
			'notice' => $result['notice'] ?? null,
			'moreUrl' => $result['moreUrl'] ?? null,
		];
	}

	/**
	 * English source strings here are the ones translators see.
	 * Keep them identical to TypeCatalog::LABELS.
	 */
	public function typeLabel(string $code): string {
		$l = $this->l10nFactory->get(Application::APP_ID);
		return match ($code) {
			'flex_desk' => $l->t('Flex desk'),
			'fix_desk' => $l->t('Dedicated desk'),
			'private_office' => $l->t('Private office'),
			'exclusive_bereich' => $l->t('Exclusive area'),
			'day_pass' => $l->t('Day pass'),
			'meeting_room' => $l->t('Meeting room'),
			'event_space' => $l->t('Event space'),
			'virtual_office' => $l->t('Virtual office'),
			'membership' => $l->t('Membership'),
			default => $code,
		};
	}
}
