<?php

declare(strict_types=1);

namespace CoworkingView\CoworkingPrices;

use s9e\TextFormatter\Configurator;

/**
 * Registers the [coworking] BBCode. Prices are not part of the template:
 * RenderPrices adds them when the post is rendered, from the cached API reading.
 */
final class ConfigureFormatter
{
    public function __invoke(Configurator $config): void
    {
        $config->BBCodes->addCustom(
            '[COWORKING city={TEXT} product={TEXT?} locale={TEXT?}]',
            <<<'XML'
<aside class="CoworkingViewCard" data-city="{@city}" data-product="{@product}" data-locale="{@locale}" data-ready="{@ready}">
    <xsl:choose>
        <xsl:when test="@error != ''">
            <p class="CoworkingViewCard-error"><xsl:value-of select="@error"/></p>
            <p class="CoworkingViewCard-credit"><a href="https://coworkingview.com" rel="noopener noreferrer">CoworkingView</a></p>
        </xsl:when>
        <xsl:when test="@ready='1'">
            <p class="CoworkingViewCard-city"><a href="https://coworkingview.com/en/tools/price-index" rel="noopener noreferrer"><xsl:value-of select="@cityname"/></a></p>
            <xsl:if test="@asof != ''">
                <p class="CoworkingViewCard-asof"><xsl:value-of select="@asof"/></p>
            </xsl:if>
            <xsl:if test="@empty != ''">
                <p class="CoworkingViewCard-empty"><xsl:value-of select="@empty"/></p>
            </xsl:if>
            <ul class="CoworkingViewCard-rows"><xsl:apply-templates/></ul>
            <xsl:if test="@attribution != ''">
                <p class="CoworkingViewCard-attribution"><xsl:value-of select="@attribution"/></p>
            </xsl:if>
            <p class="CoworkingViewCard-credit"><a href="https://coworkingview.com" rel="noopener noreferrer">CoworkingView</a> · <a href="https://creativecommons.org/licenses/by/4.0/" rel="noopener noreferrer">CC BY 4.0</a></p>
        </xsl:when>
        <xsl:otherwise>
            <p class="CoworkingViewCard-pending"><xsl:value-of select="@city"/></p>
        </xsl:otherwise>
    </xsl:choose>
</aside>
XML
        );

        $config->tags->add('COWORKINGROW')->template = <<<'XML'
<li class="CoworkingViewCard-row">
    <span class="CoworkingViewCard-product"><xsl:value-of select="@label"/></span>
    <span class="CoworkingViewCard-price"><xsl:value-of select="@price"/></span>
    <xsl:if test="@spread != ''">
        <span class="CoworkingViewCard-spread"><xsl:value-of select="@spread"/></span>
    </xsl:if>
    <xsl:if test="@sample != ''">
        <span class="CoworkingViewCard-sample"><xsl:value-of select="@sample"/></span>
    </xsl:if>
    <xsl:if test="@low='1'">
        <span class="CoworkingViewCard-low"><xsl:value-of select="@lowlabel"/></span>
    </xsl:if>
</li>
XML;

        $tag = $config->tags['COWORKING'];
        $tag->rules->autoClose();
        $tag->rules->ignoreSurroundingWhitespace();
        $tag->rules->breakParagraph();
        $tag->attributes['city']->filterChain->append([AttributeFilter::class, 'city']);
        $tag->attributes['product']->filterChain->append([AttributeFilter::class, 'product']);
        $tag->attributes['locale']->filterChain->append([AttributeFilter::class, 'locale']);
    }
}
