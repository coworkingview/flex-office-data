<?php

declare(strict_types=1);

namespace CoworkingView\CoworkingPrices\Service;

final class MemoryCache implements RatesCache
{
    /** @var array<string, array<string, mixed>> */
    private array $values = [];

    public function get(string $key): ?array
    {
        return $this->values[$key] ?? null;
    }

    public function set(string $key, array $value, int $ttlSeconds): void
    {
        unset($ttlSeconds);
        $this->values[$key] = $value;
    }
}
