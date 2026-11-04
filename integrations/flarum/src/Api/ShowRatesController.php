<?php

declare(strict_types=1);

namespace CoworkingView\CoworkingPrices\Api;

use CoworkingView\CoworkingPrices\Service\RatesClient;
use CoworkingView\CoworkingPrices\Service\RatesParser;
use Flarum\Settings\SettingsRepositoryInterface;
use Laminas\Diactoros\Response\JsonResponse;
use Psr\Http\Message\ResponseInterface;
use Psr\Http\Message\ServerRequestInterface;
use Psr\Http\Server\RequestHandlerInterface;

/**
 * Public read of one city's Price Index rows for the sidebar widget and the
 * composer preview. Guests can call it. The only upstream request is the
 * public rates endpoint.
 */
final class ShowRatesController implements RequestHandlerInterface
{
    public function __construct(
        private readonly RatesClient $client,
        private readonly SettingsRepositoryInterface $settings,
    ) {
    }

    public function handle(ServerRequestInterface $request): ResponseInterface
    {
        $city = $this->query($request, 'city');
        if ($city === '') {
            $city = trim((string) $this->settings->get('coworkingview.city', 'berlin'));
        }
        $locale = $this->query($request, 'locale');
        if ($locale === '') {
            $locale = trim((string) $this->settings->get('coworkingview.locale', 'en'));
        }
        $product = $this->query($request, 'product');
        if ($product === '') {
            $product = trim((string) $this->settings->get('coworkingview.product', 'all'));
        }

        $city = strtolower($city);
        $locale = strtolower($locale);
        $product = strtolower($product);

        $snapshot = $this->client->snapshot($city, $locale);
        if (in_array($snapshot['code'] ?? null, ['bad_city', 'bad_locale'], true)) {
            return new JsonResponse($this->present($snapshot), 400);
        }

        $snapshot = RatesParser::select($snapshot, $product);
        $status = ($snapshot['code'] ?? null) === 'bad_product' ? 400 : 200;

        return new JsonResponse($this->present($snapshot), $status);
    }

    private function query(ServerRequestInterface $request, string $key): string
    {
        $params = $request->getQueryParams();
        $value = $params[$key] ?? '';
        if (!is_string($value)) {
            return '';
        }

        return trim($value);
    }

    /**
     * @param array<string, mixed> $snapshot
     * @return array<string, mixed>
     */
    private function present(array $snapshot): array
    {
        $rows = $snapshot['rows'] ?? [];

        return [
            'ok' => ($snapshot['ok'] ?? false) === true,
            'code' => $snapshot['code'] ?? null,
            'cityName' => $snapshot['cityName'] ?? null,
            'citySlug' => $snapshot['citySlug'] ?? '',
            'countryCode' => $snapshot['countryCode'] ?? null,
            'currency' => $snapshot['currency'] ?? null,
            'asOf' => $snapshot['asOf'] ?? null,
            'attribution' => $snapshot['attribution'] ?? null,
            'license' => $snapshot['license'] ?? null,
            'licenseUrl' => $snapshot['licenseUrl'] ?? null,
            'rows' => array_values(is_array($rows) ? $rows : []),
        ];
    }
}
