<?php

declare(strict_types=1);

namespace CoworkingView\CoworkingPrices;

use CoworkingView\CoworkingPrices\Service\CardXml;
use CoworkingView\CoworkingPrices\Service\RatesClient;
use CoworkingView\CoworkingPrices\Service\RatesParser;
use Flarum\Locale\Translator;
use Flarum\Settings\SettingsRepositoryInterface;
use Psr\Http\Message\ServerRequestInterface;
use s9e\TextFormatter\Renderer;

/**
 * Loads current Price Index figures while a post is rendered.
 * The stored post text stays the BBCode; figures are not baked in at save time.
 */
final class RenderPrices
{
    public function __construct(
        private readonly RatesClient $client,
        private readonly SettingsRepositoryInterface $settings,
        private readonly Translator $translator,
    ) {
    }

    public function __invoke(Renderer $renderer, mixed $context, string $xml, ?ServerRequestInterface $request = null): string
    {
        unset($renderer, $context, $request);

        return CardXml::enrich(
            $xml,
            function (string $city, string $product, string $locale): array {
                if ($locale === '') {
                    $locale = strtolower(trim((string) $this->settings->get('coworkingview.locale', 'en')));
                }
                if (!RatesParser::isLocale($locale)) {
                    $locale = 'en';
                }

                return RatesParser::select($this->client->snapshot($city, $locale), $product);
            },
            fn (string $key, array $params): string => $this->label($key, $params),
        );
    }

    /**
     * @param array<string, string> $params
     */
    private function label(string $key, array $params): string
    {
        $id = 'coworkingview-flarum-coworkingview.forum.' . $key;
        $text = $this->translator->trans($id, $params);
        if (!is_string($text) || $text === '' || $text === $id) {
            $text = self::FALLBACK[$key] ?? $key;
            foreach ($params as $name => $value) {
                $text = str_replace('{' . $name . '}', $value, $text);
            }
        }

        return $text;
    }

    private const FALLBACK = [
        'as_of' => 'As of {date}',
        'sample' => 'Sample {count}',
        'low_confidence' => 'Low confidence',
        'empty' => 'This city does not publish that product.',
        'errors.bad_city' => 'That city slug is not valid.',
        'errors.bad_locale' => 'That language is not available.',
        'errors.bad_product' => 'That product slug is not valid.',
        'errors.unknown_city' => 'That city is not in the Price Index.',
        'errors.unpublished' => 'That city is not published in the Price Index.',
        'errors.unavailable' => 'Coworking prices are not available right now.',
        'errors.bad_response' => 'The Price Index response could not be read.',
        'products.flex_desk' => 'Flex desk',
        'products.fix_desk' => 'Fixed desk',
        'products.private_office' => 'Private office',
        'products.exclusive_bereich' => 'Exclusive area',
        'products.day_pass' => 'Day pass',
        'products.meeting_room' => 'Meeting room',
        'products.event_space' => 'Event space',
        'products.virtual_office' => 'Virtual office',
        'products.membership' => 'Membership',
        'units.month' => 'month',
        'units.day' => 'day',
        'units.hour' => 'hour',
    ];
}
