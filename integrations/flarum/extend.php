<?php

declare(strict_types=1);

use CoworkingView\CoworkingPrices\Api\ShowRatesController;
use CoworkingView\CoworkingPrices\AttributeFilter;
use CoworkingView\CoworkingPrices\ConfigureFormatter;
use CoworkingView\CoworkingPrices\CoworkingViewProvider;
use CoworkingView\CoworkingPrices\RenderPrices;
use Flarum\Extend;

return [
    (new Extend\Frontend('forum'))
        ->js(__DIR__ . '/js/dist/forum.js')
        ->css(__DIR__ . '/less/forum.less'),

    (new Extend\Frontend('admin'))
        ->js(__DIR__ . '/js/dist/admin.js'),

    (new Extend\Locales(__DIR__ . '/locale')),

    (new Extend\Routes('api'))
        ->get('/coworkingview/rates', 'coworkingview.rates', ShowRatesController::class),

    (new Extend\Settings())
        ->default('coworkingview.city', 'berlin')
        ->default('coworkingview.locale', 'en')
        ->default('coworkingview.product', 'all')
        ->default('coworkingview.show_widget', '1')
        ->serializeToForum('coworkingview.city', 'coworkingview.city', null, 'berlin')
        ->serializeToForum('coworkingview.locale', 'coworkingview.locale', null, 'en')
        ->serializeToForum('coworkingview.product', 'coworkingview.product', null, 'all')
        ->serializeToForum('coworkingview.showWidget', 'coworkingview.show_widget', [AttributeFilter::class, 'showWidget'], true),

    (new Extend\Formatter())
        ->configure(ConfigureFormatter::class)
        ->render(RenderPrices::class),

    (new Extend\ServiceProvider())
        ->register(CoworkingViewProvider::class),
];
