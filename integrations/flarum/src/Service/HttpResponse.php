<?php

declare(strict_types=1);

namespace CoworkingView\CoworkingPrices\Service;

final class HttpResponse
{
    /**
     * @param array<string, string> $headers Lower-case header names.
     */
    public function __construct(
        public readonly int $status,
        public readonly string $body,
        public readonly array $headers = [],
        public readonly ?string $error = null,
    ) {
    }
}
