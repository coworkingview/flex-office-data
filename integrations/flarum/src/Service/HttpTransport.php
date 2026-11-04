<?php

declare(strict_types=1);

namespace CoworkingView\CoworkingPrices\Service;

interface HttpTransport
{
    /**
     * @param array<string, string> $headers
     */
    public function get(string $url, array $headers, int $timeoutSeconds): HttpResponse;
}
