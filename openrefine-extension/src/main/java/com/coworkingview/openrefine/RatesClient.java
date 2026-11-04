package com.coworkingview.openrefine;

import com.fasterxml.jackson.databind.node.ObjectNode;
import java.io.IOException;
import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Clock;
import java.time.Duration;
import java.time.ZonedDateTime;
import java.time.format.DateTimeFormatter;
import java.time.format.DateTimeParseException;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * {@code GET /v1/market/rates} for one city.
 *
 * <p>The public API needs no key. A successful body is kept until its
 * {@code Cache-Control: max-age} elapses (600 seconds when the header is
 * absent) so a column of the same city is one request. On HTTP 429 or 5xx the
 * client waits {@code Retry-After}, else {@code RateLimit-Reset}, else 2
 * seconds, and never more than 10 seconds, then retries once.
 */
final class RatesClient {
    static final String DEFAULT_BASE_URL = "https://api.coworkingview.com";
    static final String BASE_URL_ENV = "COWORKINGVIEW_API_URL";
    static final String USER_AGENT =
            "coworkingview-openrefine/0.1.0 (+https://github.com/coworkingview/flex-office-data)";

    private static final Duration TIMEOUT = Duration.ofSeconds(20);
    private static final int MAX_BODY_CHARS = 2_000_000;
    private static final long DEFAULT_MAX_AGE_SECONDS = 600L;
    private static final double FALLBACK_WAIT_SECONDS = 2.0d;
    private static final double MAX_WAIT_SECONDS = 10.0d;
    private static final Pattern MAX_AGE = Pattern.compile("(?i)max-age=(\\d+)");
    private static final DateTimeFormatter HTTP_DATE = DateTimeFormatter.RFC_1123_DATE_TIME;

    private final String baseUrl;
    private final Transport transport;
    private final Clock clock;
    private final Sleeper sleeper;
    private final Map<String, Cached> cache = new ConcurrentHashMap<String, Cached>();

    private RatesClient(String baseUrl, Transport transport, Clock clock, Sleeper sleeper) {
        this.baseUrl = stripTrailingSlashes(baseUrl);
        this.transport = transport;
        this.clock = clock;
        this.sleeper = sleeper;
    }

    static RatesClient create() {
        return create(System.getenv());
    }

    static RatesClient create(Map<String, String> environment) {
        String configured = environment == null ? null : environment.get(BASE_URL_ENV);
        String base = configured == null || configured.isBlank() ? DEFAULT_BASE_URL : configured.trim();
        HttpClient http = HttpClient.newBuilder()
                .connectTimeout(TIMEOUT)
                .followRedirects(HttpClient.Redirect.NORMAL)
                .build();
        return new RatesClient(base, new JdkTransport(http), Clock.systemUTC(), new ThreadSleeper());
    }

    static RatesClient forTest(String baseUrl, Transport transport, Clock clock, Sleeper sleeper) {
        return new RatesClient(baseUrl, transport, clock, sleeper);
    }

    /** The production HTTP client, for tests that point it at a local server. */
    static Transport httpTransport() {
        HttpClient http = HttpClient.newBuilder()
                .connectTimeout(TIMEOUT)
                .followRedirects(HttpClient.Redirect.NORMAL)
                .build();
        return new JdkTransport(http);
    }

    String baseUrl() {
        return baseUrl;
    }

    ObjectNode priceIndex(String citySlug, String product) throws PriceIndexException {
        String url = ratesUrl(citySlug);
        String body = cached(url);
        if (body == null) {
            body = fetch(url);
        }
        return PriceIndexParser.parse(body, citySlug, product);
    }

    private String ratesUrl(String citySlug) {
        return baseUrl
                + "/v1/market/rates?locale=en&city="
                + URLEncoder.encode(citySlug, StandardCharsets.UTF_8);
    }

    private String cached(String url) {
        Cached hit = cache.get(url);
        if (hit == null) {
            return null;
        }
        if (clock.millis() >= hit.expiresAtMillis) {
            cache.remove(url, hit);
            return null;
        }
        return hit.body;
    }

    private String fetch(String url) throws PriceIndexException {
        boolean retried = false;
        while (true) {
            HttpResult response;
            try {
                response = transport.get(URI.create(url));
            } catch (IOException ex) {
                throw new PriceIndexException("Could not reach the CoworkingView price index: " + ex.getMessage());
            } catch (InterruptedException ex) {
                Thread.currentThread().interrupt();
                throw new PriceIndexException("Could not reach the CoworkingView price index: interrupted");
            }
            int status = response.status;
            if (status >= 200 && status < 300) {
                String body = response.body == null ? "" : response.body;
                if (body.length() > MAX_BODY_CHARS) {
                    throw new PriceIndexException("rates response was larger than 2 MB");
                }
                long maxAge = maxAgeSeconds(response.cacheControl);
                if (maxAge > 0) {
                    cache.put(url, new Cached(clock.millis() + maxAge * 1000L, body));
                }
                return body;
            }
            if (!retried && (status == 429 || status >= 500)) {
                retried = true;
                long wait = retryMillis(response.retryAfter, response.rateLimitReset, clock);
                try {
                    sleeper.sleepMillis(wait);
                } catch (InterruptedException ex) {
                    Thread.currentThread().interrupt();
                    throw new PriceIndexException("Could not reach the CoworkingView price index: interrupted");
                }
                continue;
            }
            throw new PriceIndexException(problem(status, response.body));
        }
    }

    private static long maxAgeSeconds(String cacheControl) {
        if (cacheControl == null || cacheControl.isBlank()) {
            return DEFAULT_MAX_AGE_SECONDS;
        }
        if (cacheControl.toLowerCase(java.util.Locale.ROOT).contains("no-store")) {
            return 0L;
        }
        Matcher matcher = MAX_AGE.matcher(cacheControl);
        if (matcher.find()) {
            return Long.parseLong(matcher.group(1));
        }
        return DEFAULT_MAX_AGE_SECONDS;
    }

    static long retryMillis(String retryAfter, String rateLimitReset, Clock clock) {
        Double wait = seconds(retryAfter, clock);
        if (wait == null) {
            wait = seconds(rateLimitReset, clock);
        }
        if (wait == null) {
            wait = FALLBACK_WAIT_SECONDS;
        }
        if (wait > MAX_WAIT_SECONDS) {
            wait = MAX_WAIT_SECONDS;
        }
        return Math.round(wait * 1000.0d);
    }

    private static Double seconds(String value, Clock clock) {
        if (value == null) {
            return null;
        }
        String trimmed = value.trim();
        if (trimmed.isEmpty()) {
            return null;
        }
        try {
            double parsed = Double.parseDouble(trimmed);
            if (Double.isFinite(parsed)) {
                return parsed < 0d ? 0d : parsed;
            }
        } catch (NumberFormatException ignored) {
            // Retry-After may be an HTTP-date.
        }
        try {
            ZonedDateTime when = ZonedDateTime.parse(trimmed, HTTP_DATE);
            double delta = (when.toInstant().toEpochMilli() - clock.instant().toEpochMilli()) / 1000.0d;
            return delta < 0d ? 0d : delta;
        } catch (DateTimeParseException ignored) {
            return null;
        }
    }

    private static String problem(int status, String body) {
        if (body == null || body.isBlank()) {
            return "HTTP " + status;
        }
        try {
            com.fasterxml.jackson.databind.JsonNode node = new com.fasterxml.jackson.databind.ObjectMapper().readTree(body);
            if (!node.isObject()) {
                return "HTTP " + status;
            }
            String code = node.path("code").isTextual() ? node.path("code").asText() : "HTTP_" + status;
            String title = node.path("title").isTextual() ? node.path("title").asText() : "request failed";
            return title + " [" + code + "]";
        } catch (IOException ex) {
            return "HTTP " + status;
        }
    }

    private static String stripTrailingSlashes(String url) {
        String trimmed = url.trim();
        while (trimmed.endsWith("/")) {
            trimmed = trimmed.substring(0, trimmed.length() - 1);
        }
        return trimmed;
    }

    interface Transport {
        HttpResult get(URI uri) throws IOException, InterruptedException;
    }

    interface Sleeper {
        void sleepMillis(long millis) throws InterruptedException;
    }

    static final class HttpResult {
        final int status;
        final String body;
        final String retryAfter;
        final String rateLimitReset;
        final String cacheControl;

        HttpResult(int status, String body, String retryAfter, String rateLimitReset, String cacheControl) {
            this.status = status;
            this.body = body;
            this.retryAfter = retryAfter;
            this.rateLimitReset = rateLimitReset;
            this.cacheControl = cacheControl;
        }
    }

    private static final class Cached {
        final long expiresAtMillis;
        final String body;

        Cached(long expiresAtMillis, String body) {
            this.expiresAtMillis = expiresAtMillis;
            this.body = body;
        }
    }

    private static final class ThreadSleeper implements Sleeper {
        @Override
        public void sleepMillis(long millis) throws InterruptedException {
            if (millis > 0) {
                Thread.sleep(millis);
            }
        }
    }

    private static final class JdkTransport implements Transport {
        private final HttpClient http;

        JdkTransport(HttpClient http) {
            this.http = http;
        }

        @Override
        public HttpResult get(URI uri) throws IOException, InterruptedException {
            HttpRequest request = HttpRequest.newBuilder(uri)
                    .timeout(TIMEOUT)
                    .header("Accept", "application/json")
                    .header("User-Agent", USER_AGENT)
                    .GET()
                    .build();
            HttpResponse<String> response = http.send(request, HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8));
            return new HttpResult(
                    response.statusCode(),
                    response.body(),
                    response.headers().firstValue("retry-after").orElse(null),
                    response.headers().firstValue("ratelimit-reset").orElse(null),
                    response.headers().firstValue("cache-control").orElse(null));
        }
    }
}
