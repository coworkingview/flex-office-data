<?php

namespace CoworkingView\Flarum;

use Flarum\Extend;

return [
    new Extend\Locales(__DIR__.'/locale'),

    (new Extend\Frontend('forum'))
        ->css(__DIR__.'/less/forum.less'),

    (new Extend\Frontend('admin'))
        ->js(__DIR__.'/js/dist/admin.js'),

    (new Extend\Settings())
        ->default('coworkingview.default_locale', 'de'),

    (new Extend\Formatter())
        ->configure(Configure::class)
        ->render(RenderLocale::class),
];
