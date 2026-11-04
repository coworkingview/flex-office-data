<?php

declare(strict_types=1);

namespace CoworkingView\CoworkingPrices;

use CoworkingView\CoworkingPrices\Service\CurlTransport;
use CoworkingView\CoworkingPrices\Service\IlluminateCache;
use CoworkingView\CoworkingPrices\Service\RatesClient;
use Flarum\Foundation\AbstractServiceProvider;
use Illuminate\Contracts\Cache\Repository;

final class CoworkingViewProvider extends AbstractServiceProvider
{
    public function register(): void
    {
        $this->container->singleton(RatesClient::class, function () {
            return new RatesClient(
                new CurlTransport(),
                new IlluminateCache($this->container->make(Repository::class)),
            );
        });
    }
}
