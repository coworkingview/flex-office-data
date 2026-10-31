<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 CoworkingView <info@coworkingview.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\CoworkingView\Dashboard;

use OCA\CoworkingView\AppInfo\Application;
use OCP\Dashboard\IButtonWidget;
use OCP\Dashboard\IIconWidget;
use OCP\Dashboard\IWidget;
use OCP\Dashboard\Model\WidgetButton;
use OCP\IL10N;
use OCP\IURLGenerator;
use OCP\Util;

/**
 * Dashboard widget. The Vue bundle mounted from load() is the search form.
 */
class Widget implements IWidget, IIconWidget, IButtonWidget {
	public function __construct(
		private readonly IL10N $l10n,
		private readonly IURLGenerator $urlGenerator,
	) {
	}

	public function getId(): string {
		return 'coworkingview';
	}

	public function getTitle(): string {
		return $this->l10n->t('CoworkingView');
	}

	/**
	 * 0 to 9 are reserved for apps shipped with Nextcloud.
	 */
	public function getOrder(): int {
		return 30;
	}

	public function getIconClass(): string {
		return 'icon-coworkingview';
	}

	public function getIconUrl(): string {
		return $this->urlGenerator->getAbsoluteURL(
			$this->urlGenerator->imagePath(Application::APP_ID, 'app.svg')
		);
	}

	public function getUrl(): ?string {
		return 'https://coworkingview.com';
	}

	public function load(): void {
		Util::addScript(Application::APP_ID, Application::APP_ID . '-dashboard');
		Util::addStyle(Application::APP_ID, 'dashboard');
		Util::addStyle(Application::APP_ID, Application::APP_ID . '-dashboard');
	}

	public function getWidgetButtons(string $userId): array {
		return [
			new WidgetButton(
				WidgetButton::TYPE_MORE,
				'https://coworkingview.com',
				$this->l10n->t('More on CoworkingView'),
			),
		];
	}
}
