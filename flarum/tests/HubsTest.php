<?php

namespace CoworkingView\Flarum\Tests;

use CoworkingView\Flarum\Configure;
use CoworkingView\Flarum\Hubs;
use PHPUnit\Framework\TestCase;
use s9e\TextFormatter\Configurator;

final class HubsTest extends TestCase
{
    public function testTemplateUsesOnlyCheckedHubs(): void
    {
        $template = Hubs::template();

        $this->assertStringNotContainsString('best-coworking', $template);

        preg_match_all('#https://coworkingview\.com[^<"]*#', $template, $matches);

        $allowed = [Hubs::FALLBACK_URL];
        foreach (Hubs::HUBS as $hub) {
            $allowed[] = $hub['href'];
        }

        $this->assertNotEmpty($matches[0]);
        foreach ($matches[0] as $url) {
            $this->assertContains($url, $allowed);
        }
    }

    public function testCanonicalCities(): void
    {
        $this->assertSame('berlin', Hubs::canonical('Berlin'));
        $this->assertSame('hamburg', Hubs::canonical(' hamburg '));
        $this->assertSame('munich', Hubs::canonical('munich'));
        $this->assertSame('munich', Hubs::canonical('muenchen'));
        $this->assertSame('munich', Hubs::canonical('München'));
        $this->assertSame('barcelona', Hubs::canonical('Barcelona'));
        $this->assertSame('madrid', Hubs::canonical('MADRID'));
        $this->assertNull(Hubs::canonical(''));
        $this->assertNull(Hubs::canonical('best-coworking'));
        $this->assertNull(Hubs::canonical('berlin/best-coworking'));
        $this->assertNull(Hubs::canonical('javascript:alert(1)'));
    }

    public function testLocaleFallsBackToGerman(): void
    {
        $this->assertSame('de', Hubs::locale(null));
        $this->assertSame('de', Hubs::locale('fr'));
        $this->assertSame('es', Hubs::locale('es'));
        $this->assertSame('en', Hubs::locale('en'));
    }

    public function testKnownCitiesRenderAllowlistedLinks(): void
    {
        [$parser, $renderer] = $this->formatter();

        foreach (Hubs::HUBS as $slug => $hub) {
            $html = $renderer->render($parser->parse('[coworkingview city="'.$slug.'"]'));

            $this->assertStringContainsString('href="'.$hub['href'].'"', $html);
            $this->assertStringContainsString('CoworkingView', $html);
            $this->assertStringContainsString($hub['name'], $html);
            $this->assertStringNotContainsString('best-coworking', $html);
            $this->assertStringStartsWith('<a class="CoworkingViewCard"', $html);
        }
    }

    public function testAliasesAndUnknownCities(): void
    {
        [$parser, $renderer] = $this->formatter();

        $munich = $renderer->render($parser->parse('[coworkingview city="muenchen"]'));
        $this->assertStringContainsString('href="https://coworkingview.com/de/coworking/munich"', $munich);

        $umlaut = $renderer->render($parser->parse('[coworkingview city="München"]'));
        $this->assertStringContainsString('href="https://coworkingview.com/de/coworking/munich"', $umlaut);

        foreach (['best-coworking', 'berlin/best-coworking', 'javascript:alert(1)', ''] as $city) {
            $tag = $city === '' ? '[coworkingview]' : '[coworkingview city="'.$city.'"]';
            $html = $renderer->render($parser->parse($tag));

            $this->assertStringContainsString('href="https://coworkingview.com"', $html);
            $this->assertStringNotContainsString('best-coworking', $html);
            $this->assertStringNotContainsString('javascript:', $html);
        }
    }

    public function testLanguageSettingChangesTheSentenceOnly(): void
    {
        [$parser, $renderer] = $this->formatter();
        $xml = $parser->parse('[coworkingview city="madrid"]');

        $renderer->setParameter('COWORKINGVIEW_LOCALE', 'es');
        $spanish = $renderer->render($xml);
        $this->assertStringContainsString('Espacios de coworking en Madrid', $spanish);
        $this->assertStringContainsString('href="https://coworkingview.com/es/coworking/madrid"', $spanish);

        $renderer->setParameter('COWORKINGVIEW_LOCALE', 'en');
        $english = $renderer->render($xml);
        $this->assertStringContainsString('Coworking spaces in Madrid', $english);
        $this->assertStringContainsString('href="https://coworkingview.com/es/coworking/madrid"', $english);

        $renderer->setParameter('COWORKINGVIEW_LOCALE', 'de');
        $this->assertStringContainsString('Coworking-Spaces in Madrid', $renderer->render($xml));
    }

    /**
     * @return array{0: \s9e\TextFormatter\Parser, 1: \s9e\TextFormatter\Renderer}
     */
    private function formatter(): array
    {
        $config = new Configurator();
        (new Configure())($config);
        $bundle = $config->finalize();

        return [$bundle['parser'], $bundle['renderer']];
    }
}
