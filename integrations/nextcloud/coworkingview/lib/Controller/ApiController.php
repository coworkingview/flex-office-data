<?php

declare(strict_types=1);

/**
 * SPDX-FileCopyrightText: 2026 CoworkingView <info@coworkingview.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

namespace OCA\CoworkingView\Controller;

use OCA\CoworkingView\AppInfo\Application;
use OCA\CoworkingView\Service\ApiException;
use OCA\CoworkingView\Service\Locale;
use OCA\CoworkingView\Service\ResultPresenter;
use OCA\CoworkingView\Service\SearchService;
use OCA\CoworkingView\Service\TypeCatalog;
use OCP\AppFramework\Controller;
use OCP\AppFramework\Http;
use OCP\AppFramework\Http\Attribute\NoAdminRequired;
use OCP\AppFramework\Http\Attribute\UserRateLimit;
use OCP\AppFramework\Http\DataResponse;
use OCP\IRequest;
use OCP\L10N\IFactory;
use Psr\Log\LoggerInterface;

/**
 * Logged-in proxy in front of the public CoworkingView API.
 * The JSON it returns has the name, city, workspace type and listing URL.
 */
class ApiController extends Controller {
	public function __construct(
		IRequest $request,
		private readonly SearchService $searchService,
		private readonly ResultPresenter $presenter,
		private readonly IFactory $l10nFactory,
		private readonly LoggerInterface $logger,
	) {
		parent::__construct(Application::APP_ID, $request);
	}

	#[NoAdminRequired]
	#[UserRateLimit(limit: 20, period: 60)]
	public function cities(): DataResponse {
		try {
			$cities = $this->searchService->cities($this->locale());
		} catch (ApiException $e) {
			return $this->error($e);
		}
		$types = [];
		foreach (TypeCatalog::ORDER as $code) {
			$types[] = [
				'code' => $code,
				'label' => $this->presenter->typeLabel($code),
			];
		}
		return new DataResponse([
			'cities' => $cities,
			'types' => $types,
		]);
	}

	#[NoAdminRequired]
	#[UserRateLimit(limit: 30, period: 60)]
	public function workspaces(string $city = '', string $type = ''): DataResponse {
		try {
			$result = $this->searchService->search($this->locale(), $city, $type);
		} catch (ApiException $e) {
			return $this->error($e);
		}
		return new DataResponse($this->presenter->present($result));
	}

	private function locale(): string {
		return Locale::fromLanguage($this->l10nFactory->findLanguage(Application::APP_ID));
	}

	private function error(ApiException $e): DataResponse {
		$this->logger->warning('CoworkingView request failed', [
			'app' => Application::APP_ID,
			'code' => $e->errorCode,
			'status' => $e->status,
		]);
		$l = $this->l10nFactory->get(Application::APP_ID);
		$message = match ($e->errorCode) {
			'BAD_CITY' => $l->t('Choose a city from the list.'),
			'BAD_TYPE' => $l->t('That workspace type is not available.'),
			'CONNECTION', 'BAD_BASE_URL' => $l->t('Could not reach the CoworkingView API.'),
			default => $this->apiMessage($e, $l->t('The search could not be completed.')),
		};
		return new DataResponse([
			'message' => $message,
			'code' => $e->errorCode,
		], $this->status($e));
	}

	private function apiMessage(ApiException $e, string $fallback): string {
		$detail = trim($e->detail);
		$title = trim($e->getMessage());
		$text = $detail !== '' ? $detail : $title;
		if ($text === '' || strlen($text) > 300 || str_contains($text, '<') || str_contains($text, "\n")) {
			return $fallback;
		}
		return $text;
	}

	private function status(ApiException $e): int {
		if ($e->status >= 400 && $e->status <= 499) {
			return $e->status;
		}
		return Http::STATUS_BAD_GATEWAY;
	}
}
