<?php

namespace CoworkingView\Flarum;

use InvalidArgumentException;
use s9e\TextFormatter\Parser\Tag;

/**
 * Allowlist of CoworkingView city hubs.
 *
 * Each href was requested with curl on 2026-11-04 and returned HTTP 200
 * with no redirect. https://coworkingview.com/de/coworking/muenchen returned
 * 301, so Munich uses https://coworkingview.com/de/coworking/munich.
 * The city attribute is never concatenated into a URL.
 */
final class Hubs
{
    public const FALLBACK_URL = 'https://coworkingview.com';

    /**
     * Canonical slug => hub. Names are display labels, not URL segments.
     *
     * @var array<string, array{href: string, name: string}>
     */
    public const HUBS = [
        'berlin' => [
            'href' => 'https://coworkingview.com/de/coworking/berlin',
            'name' => 'Berlin',
        ],
        'hamburg' => [
            'href' => 'https://coworkingview.com/de/coworking/hamburg',
            'name' => 'Hamburg',
        ],
        'munich' => [
            'href' => 'https://coworkingview.com/de/coworking/munich',
            'name' => 'München',
        ],
        'barcelona' => [
            'href' => 'https://coworkingview.com/es/coworking/barcelona',
            'name' => 'Barcelona',
        ],
        'madrid' => [
            'href' => 'https://coworkingview.com/es/coworking/madrid',
            'name' => 'Madrid',
        ],
    ];

    /**
     * Normalised spelling => canonical slug. Includes München without the umlaut.
     *
     * @var array<string, string>
     */
    public const ALIASES = [
        'barcelona' => 'barcelona',
        'berlin' => 'berlin',
        'hamburg' => 'hamburg',
        'madrid' => 'madrid',
        'muenchen' => 'munich',
        'munchen' => 'munich',
        'munich' => 'munich',
    ];

    /** @var list<string> */
    public const LOCALES = ['de', 'es', 'en'];

    public static function locale(?string $value): string
    {
        return in_array($value, self::LOCALES, true) ? $value : 'de';
    }

    public static function canonical(?string $city): ?string
    {
        $key = mb_strtolower(trim((string) $city), 'UTF-8');
        $key = strtr($key, [
            'ä' => 'ae',
            'ö' => 'oe',
            'ü' => 'ue',
            'ß' => 'ss',
        ]);
        $key = preg_replace('/[^a-z0-9]+/', '', $key) ?? '';

        return self::ALIASES[$key] ?? null;
    }

    /**
     * Rewrite the city attribute to a canonical slug, or drop it.
     * Called by the TextFormatter parser. Must stay a static method so the
     * formatter configuration can be serialized.
     */
    public static function filter(Tag $tag): void
    {
        if (!$tag->hasAttribute('city')) {
            return;
        }

        $slug = self::canonical((string) $tag->getAttribute('city'));

        if ($slug === null) {
            $tag->removeAttribute('city');

            return;
        }

        $tag->setAttribute('city', $slug);
    }

    /**
     * XSL template. Every href is a literal from the allowlist, so an
     * unrecognised city cannot change the address.
     */
    public static function template(): string
    {
        self::assertAllowlist();

        $branches = '';

        foreach (self::HUBS as $slug => $hub) {
            $branches .= '<xsl:when test="@city = \''.$slug.'\'">'
                .'<xsl:attribute name="href">'.$hub['href'].'</xsl:attribute>'
                .self::cardBody(self::cityTitle($hub['name']))
                .'</xsl:when>';
        }

        return '<a class="CoworkingViewCard" rel="noopener noreferrer">'
            .'<xsl:choose>'.$branches
            .'<xsl:otherwise>'
            .'<xsl:attribute name="href">'.self::FALLBACK_URL.'</xsl:attribute>'
            .self::cardBody(self::fallbackTitle())
            .'</xsl:otherwise></xsl:choose></a>';
    }

    private static function cardBody(string $titleXml): string
    {
        return '<span class="CoworkingViewCard-brand">CoworkingView</span>'
            .'<span class="CoworkingViewCard-title">'.$titleXml.'</span>';
    }

    private static function cityTitle(string $name): string
    {
        $safe = self::xmlText($name);

        return '<xsl:choose>'
            .'<xsl:when test="$COWORKINGVIEW_LOCALE = \'es\'">Espacios de coworking en '.$safe.'</xsl:when>'
            .'<xsl:when test="$COWORKINGVIEW_LOCALE = \'en\'">Coworking spaces in '.$safe.'</xsl:when>'
            .'<xsl:otherwise>Coworking-Spaces in '.$safe.'</xsl:otherwise>'
            .'</xsl:choose>';
    }

    private static function fallbackTitle(): string
    {
        return '<xsl:choose>'
            .'<xsl:when test="$COWORKINGVIEW_LOCALE = \'es\'">Descubrir espacios de coworking</xsl:when>'
            .'<xsl:when test="$COWORKINGVIEW_LOCALE = \'en\'">Browse coworking spaces</xsl:when>'
            .'<xsl:otherwise>Coworking-Spaces entdecken</xsl:otherwise>'
            .'</xsl:choose>';
    }

    private static function xmlText(string $value): string
    {
        return htmlspecialchars($value, ENT_XML1 | ENT_QUOTES, 'UTF-8');
    }

    private static function assertAllowlist(): void
    {
        if (self::FALLBACK_URL !== 'https://coworkingview.com') {
            throw new InvalidArgumentException('The fallback URL must be the CoworkingView homepage.');
        }

        foreach (self::HUBS as $slug => $hub) {
            if (!preg_match('/^[a-z]+$/', $slug)) {
                throw new InvalidArgumentException('City slug must be lowercase letters.');
            }

            $href = $hub['href'];

            if (str_contains($href, 'best-coworking') || str_contains(self::FALLBACK_URL, 'best-coworking')) {
                throw new InvalidArgumentException('A CoworkingView card must not use that path.');
            }

            $allowed = [
                'berlin' => 'https://coworkingview.com/de/coworking/berlin',
                'hamburg' => 'https://coworkingview.com/de/coworking/hamburg',
                'munich' => 'https://coworkingview.com/de/coworking/munich',
                'barcelona' => 'https://coworkingview.com/es/coworking/barcelona',
                'madrid' => 'https://coworkingview.com/es/coworking/madrid',
            ];

            if (($allowed[$slug] ?? null) !== $href) {
                throw new InvalidArgumentException('Refusing a city hub URL outside the checked allowlist.');
            }
        }
    }
}
