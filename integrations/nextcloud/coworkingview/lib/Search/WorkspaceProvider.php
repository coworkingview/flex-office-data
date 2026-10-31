<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 CoworkingView <info@coworkingview.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\CoworkingView\Search;

use OCA\CoworkingView\AppInfo\Application;
use OCA\CoworkingView\Service\ApiException;
use OCA\CoworkingView\Service\Locale;
use OCA\CoworkingView\Service\ResultPresenter;
use OCA\CoworkingView\Service\SearchService;
use OCP\IL10N;
use OCP\IURLGenerator;
use OCP\IUser;
use OCP\L10N\IFactory;
use OCP\Search\IExternalProvider;
use OCP\Search\ISearchQuery;
use OCP\Search\SearchResult;
use OCP\Search\SearchResultEntry;
use Psr\Log\LoggerInterface;

/**
 * Unified Search over workspace names and city names.
 *
 * The query is sent to the CoworkingView API, so this provider is external
 * and stays off until the user enables search of connected services.
 */
class WorkspaceProvider implements IExternalProvider {
	public function __construct(
		private readonly SearchService $searchService,
		private readonly ResultPresenter $presenter,
		private readonly IFactory $l10nFactory,
		private readonly IL10N $l10n,
		private readonly IURLGenerator $urlGenerator,
		private readonly LoggerInterface $logger,
	) {
	}

	public function getId(): string {
		return 'coworkingview';
	}

	public function getName(): string {
		return $this->l10n->t('Workspaces');
	}

	public function getOrder(string $route, array $routeParameters): int {
		if (str_starts_with($route, Application::APP_ID . '.')) {
			return -1;
		}
		return 50;
	}

	public function isExternalProvider(): bool {
		return true;
	}

	public function search(IUser $user, ISearchQuery $query): SearchResult {
		$l = $this->l10n;
		$name = $l->t('Workspaces');
		$term = trim($query->getTerm());
		if ($term === '') {
			return SearchResult::complete($name, []);
		}
		$limit = $query->getLimit();
		if ($limit < 1) {
			$limit = 8;
		}
		try {
			$result = $this->searchService->unified(
				Locale::fromLanguage($this->l10nFactory->findLanguage(Application::APP_ID)),
				$term,
				min(8, $limit),
			);
		} catch (ApiException $e) {
			$this->logger->warning('CoworkingView unified search failed', [
				'app' => Application::APP_ID,
				'code' => $e->errorCode,
				'status' => $e->status,
			]);
			return SearchResult::complete($name, []);
		}
		$presented = $this->presenter->present($result);
		$icon = $this->urlGenerator->imagePath(Application::APP_ID, 'app.png');
		$entries = [];
		foreach ($presented['workspaces'] as $workspace) {
			$city = (string)$workspace['city'];
			$typeLabel = (string)$workspace['typeLabel'];
			if ($city !== '' && $typeLabel !== '') {
				$subline = $l->t('%1$s · %2$s', [$city, $typeLabel]);
			} else {
				$subline = $city !== '' ? $city : $typeLabel;
			}
			$entries[] = new SearchResultEntry(
				$icon,
				(string)$workspace['name'],
				$subline,
				(string)$workspace['url'],
				'icon-coworkingview',
				false,
			);
		}
		return SearchResult::complete($name, $entries);
	}
}
