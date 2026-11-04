<?php

declare(strict_types=1);

use CoworkingView\CoworkingPrices\Service\HttpResponse;
use CoworkingView\CoworkingPrices\Service\HttpTransport;
use CoworkingView\CoworkingPrices\Service\MemoryCache;
use CoworkingView\CoworkingPrices\Service\RatesClient;

final class FakeTransport implements HttpTransport
{
    /** @var list<array{0: string, 1: array<string, string>, 2: int}> */
    public array $calls = [];

    /** @var list<HttpResponse> */
    public array $responses = [];

    public function get(string $url, array $headers, int $timeoutSeconds): HttpResponse
    {
        $this->calls[] = [$url, $headers, $timeoutSeconds];
        $next = array_shift($this->responses);
        if (!$next instanceof HttpResponse) {
            return new HttpResponse(0, '', [], 'no scripted response');
        }

        return $next;
    }
}

function sampleBody(): string
{
    return (string) file_get_contents(__DIR__ . '/fixtures/rates.json');
}

function client(FakeTransport $transport, ?MemoryCache $cache = null, ?array &$slept = null): RatesClient
{
    $sleep = null;
    if ($slept !== null) {
        $sleep = static function (int $seconds) use (&$slept): void {
            $slept[] = $seconds;
        };
    }

    return new RatesClient($transport, $cache, $sleep);
}

$saved = getenv('COWORKINGVIEW_API_URL');
putenv('COWORKINGVIEW_API_URL');

$transport = new FakeTransport();
$transport->responses[] = new HttpResponse(200, sampleBody(), ['content-type' => 'application/json']);
$cache = new MemoryCache();
$rates = client($transport, $cache);
$first = $rates->snapshot('Example', 'en');
check($first['ok'] === true && $first['cityName'] === 'Example City', 'client parses the rates payload');
check(count($transport->calls) === 1, 'one request');
check(str_starts_with($transport->calls[0][0], 'https://api.coworkingview.com/v1/market/rates?'), 'official rates url');
check(str_contains($transport->calls[0][0], 'locale=en'), 'locale is sent');
check(str_contains($transport->calls[0][0], 'city=example'), 'city slug is sent lowercase');
check($transport->calls[0][1]['Accept'] === 'application/json', 'accept json');
check(str_contains($transport->calls[0][1]['User-Agent'], 'flarum-coworkingview/' . RatesClient::VERSION), 'user agent names the extension');
check(str_contains($transport->calls[0][1]['User-Agent'], 'https://github.com/coworkingview/flarum-coworkingview'), 'user agent links the source repo');
check($transport->calls[0][2] === 20, 'timeout is 20 seconds');
check(!isset($transport->calls[0][1]['Authorization']), 'no authorization header');

$second = $rates->snapshot('example', 'en');
check($second['cityName'] === 'Example City' && count($transport->calls) === 1, 'cache skips a second request');

$bad = $rates->snapshot('../etc', 'en');
check($bad['code'] === 'bad_city' && count($transport->calls) === 1, 'bad slug does not call the network');
check($rates->snapshot('example', 'fr')['code'] === 'bad_locale', 'bad locale does not call the network');

$retry = new FakeTransport();
$retry->responses[] = new HttpResponse(429, '', ['retry-after' => '2']);
$retry->responses[] = new HttpResponse(200, sampleBody());
$slept = [];
$retried = client($retry, new MemoryCache(), $slept)->snapshot('example', 'de');
check($retried['ok'] === true && count($retry->calls) === 2, '429 is retried once');
check($slept === [2], 'retry waits Retry-After seconds');
check(str_contains($retry->calls[0][0], 'locale=de'), 'retry keeps the locale');

$down = new FakeTransport();
$down->responses[] = new HttpResponse(503, '{"title":"Busy","detail":"Later"}', ['ratelimit-reset' => '4']);
$down->responses[] = new HttpResponse(500, '{"title":"Still busy"}');
$slept = [];
$downCache = new MemoryCache();
$downResult = client($down, $downCache, $slept)->snapshot('example', 'en');
check($downResult['ok'] === false && $downResult['code'] === 'unavailable', 'failed retry is an error');
check($downResult['cacheable'] === false, 'errors are not cacheable');
check($slept === [4], 'RateLimit-Reset is the fallback wait');
check($downCache->get('coworkingview.rates.' . RatesClient::VERSION . '.en.example') === null, 'error is not stored');

$offline = new FakeTransport();
$offline->responses[] = new HttpResponse(0, '', [], 'timed out');
$slept = [];
check(client($offline, null, $slept)->snapshot('example', 'en')['code'] === 'unavailable', 'connection failure');
check($slept === [] && count($offline->calls) === 1, 'connection failure is not retried');

putenv('COWORKINGVIEW_API_URL=http://127.0.0.1:9/ignored?x=1');
$evil = new FakeTransport();
$evil->responses[] = new HttpResponse(200, sampleBody());
client($evil)->snapshot('example', 'en');
check(str_starts_with($evil->calls[0][0], 'https://api.coworkingview.com/'), 'query or userinfo in the override is ignored');

putenv('COWORKINGVIEW_API_URL=http://127.0.0.1:9');
$local = new FakeTransport();
$local->responses[] = new HttpResponse(200, sampleBody());
client($local)->snapshot('example', 'es');
check(str_starts_with($local->calls[0][0], 'http://127.0.0.1:9/v1/market/rates?'), 'origin override keeps scheme host and port');
check(str_contains($local->calls[0][0], 'locale=es'), 'override still sends locale');

putenv('COWORKINGVIEW_API_URL=javascript://evil.test');
$js = new FakeTransport();
$js->responses[] = new HttpResponse(200, sampleBody());
client($js)->snapshot('example', 'en');
check(str_starts_with($js->calls[0][0], 'https://api.coworkingview.com/'), 'non-http override is ignored');

if ($saved === false) {
    putenv('COWORKINGVIEW_API_URL');
} else {
    putenv('COWORKINGVIEW_API_URL=' . $saved);
}
