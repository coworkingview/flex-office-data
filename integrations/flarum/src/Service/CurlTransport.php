<?php

declare(strict_types=1);

namespace CoworkingView\CoworkingPrices\Service;

/**
 * HTTPS GET with redirects disabled. cURL when the extension is present,
 * otherwise PHP streams.
 */
final class CurlTransport implements HttpTransport
{
    public function get(string $url, array $headers, int $timeoutSeconds): HttpResponse
    {
        if (function_exists('curl_init')) {
            return $this->viaCurl($url, $headers, $timeoutSeconds);
        }

        return $this->viaStreams($url, $headers, $timeoutSeconds);
    }

    /**
     * @param array<string, string> $headers
     */
    private function viaCurl(string $url, array $headers, int $timeoutSeconds): HttpResponse
    {
        $handle = curl_init($url);
        if ($handle === false) {
            return new HttpResponse(0, '', [], 'curl_init failed');
        }

        $lines = [];
        foreach ($headers as $name => $value) {
            $lines[] = $name . ': ' . $value;
        }

        curl_setopt_array($handle, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_HTTPHEADER => $lines,
            CURLOPT_TIMEOUT => $timeoutSeconds,
            CURLOPT_CONNECTTIMEOUT => min(10, $timeoutSeconds),
            CURLOPT_FOLLOWLOCATION => false,
            CURLOPT_PROTOCOLS => CURLPROTO_HTTP | CURLPROTO_HTTPS,
            CURLOPT_HEADER => true,
        ]);

        $raw = curl_exec($handle);
        if ($raw === false) {
            $error = curl_error($handle);
            curl_close($handle);

            return new HttpResponse(0, '', [], $error !== '' ? $error : 'connection failed');
        }

        $status = (int) curl_getinfo($handle, CURLINFO_RESPONSE_CODE);
        $headerSize = (int) curl_getinfo($handle, CURLINFO_HEADER_SIZE);
        curl_close($handle);

        $headerText = substr($raw, 0, $headerSize);
        $body = substr($raw, $headerSize);

        return new HttpResponse($status, $body, self::headerMap($headerText));
    }

    /**
     * @param array<string, string> $headers
     */
    private function viaStreams(string $url, array $headers, int $timeoutSeconds): HttpResponse
    {
        $lines = [];
        foreach ($headers as $name => $value) {
            $lines[] = $name . ': ' . $value;
        }

        $context = stream_context_create([
            'http' => [
                'method' => 'GET',
                'header' => implode("\r\n", $lines),
                'timeout' => $timeoutSeconds,
                'ignore_errors' => true,
                'follow_location' => 0,
            ],
        ]);

        $body = @file_get_contents($url, false, $context);
        $rawHeaders = null;
        if (function_exists('http_get_last_response_headers')) {
            $rawHeaders = http_get_last_response_headers();
        } elseif (isset($http_response_header)) {
            $rawHeaders = $http_response_header;
        }

        if (!is_array($rawHeaders) || $rawHeaders === []) {
            return new HttpResponse(0, '', [], 'connection failed');
        }

        $status = 0;
        if (preg_match('/\s(\d{3})\s/', $rawHeaders[0], $match) === 1) {
            $status = (int) $match[1];
        }

        return new HttpResponse($status, is_string($body) ? $body : '', self::headerMap(implode("\n", $rawHeaders)));
    }

    /**
     * @return array<string, string>
     */
    private static function headerMap(string $raw): array
    {
        $headers = [];
        foreach (preg_split("/\r\n|\n|\r/", $raw) ?: [] as $line) {
            $pos = strpos($line, ':');
            if ($pos === false) {
                continue;
            }
            $name = strtolower(trim(substr($line, 0, $pos)));
            if ($name === '' || isset($headers[$name])) {
                continue;
            }
            $headers[$name] = trim(substr($line, $pos + 1));
        }

        return $headers;
    }
}
