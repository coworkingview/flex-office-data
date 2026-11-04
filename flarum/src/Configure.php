<?php

namespace CoworkingView\Flarum;

use s9e\TextFormatter\Configurator;

/**
 * Registers the [coworkingview] BBCode tag.
 *
 * The tag is void. A closing tag is accepted and ignored.
 */
final class Configure
{
    public function __invoke(Configurator $config): void
    {
        $config->rendering->parameters->add('COWORKINGVIEW_LOCALE', 'de');

        $config->BBCodes->addCustom(
            '[COWORKINGVIEW city={TEXT?}]',
            Hubs::template()
        );

        $config->tags->get('COWORKINGVIEW')->filterChain->append([Hubs::class, 'filter']);
    }
}
