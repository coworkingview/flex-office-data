<?php

namespace CoworkingView\Flarum;

use Flarum\Settings\SettingsRepositoryInterface;
use s9e\TextFormatter\Renderer;

/**
 * Applies the admin language setting when a post is rendered.
 *
 * The city hub URL is chosen when the post is parsed. This parameter only
 * changes the sentence on the card, including for posts that already exist.
 */
final class RenderLocale
{
    public function __construct(private readonly SettingsRepositoryInterface $settings)
    {
    }

    /**
     * @param mixed $context
     * @param mixed $request Flarum passes the current server request. It may be null.
     */
    public function __invoke(Renderer $renderer, $context, string $xml, $request = null): string
    {
        $stored = $this->settings->get('coworkingview.default_locale', 'de');

        $renderer->setParameter(
            'COWORKINGVIEW_LOCALE',
            Hubs::locale(is_string($stored) ? $stored : null)
        );

        return $xml;
    }
}
