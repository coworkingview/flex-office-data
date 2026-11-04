<?php

declare(strict_types=1);

namespace CoworkingView\CoworkingPrices\Service;

use Illuminate\Contracts\Cache\Repository;

final class IlluminateCache implements RatesCache
{
    public function __construct(private readonly Repository $repository)
    {
    }

    public function get(string $key): ?array
    {
        $value = $this->repository->get($key);

        return is_array($value) ? $value : null;
    }

    public function set(string $key, array $value, int $ttlSeconds): void
    {
        $this->repository->put($key, $value, $ttlSeconds);
    }
}
