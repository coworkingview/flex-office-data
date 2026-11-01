package com.coworkingview.eclipse;

import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpHeaders;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.List;
import java.util.Locale;

/**
 * HTTPS client for {@code GET /v1/market/rates}. No API key. Redirects are not followed.
 * A 429 or 5xx is retried once. Any failure of {@link #load(String)} returns the bundled snapshot.
 */
public final class RatesClient {

    public static final String USER_AGENT =
            "coworkingview-eclipse/0.1.0 (+https://github.com/coworkingview/flex-office-data)";

    public static final URI DEFAULT_BASE = URI.create("https://api.coworkingview.com");

    private final URI base;
    private final Duration timeout;

    public RatesClient(URI base, Duration timeout) {
        this.base = validate(base);
        this.timeout = timeout;
    }

    public static RatesClient fromEnvironment() {
        String override = System.getenv("COWORKINGVIEW_API_URL");
        URI base = DEFAULT_BASE;
        if (override != null && !override.isBlank()) {
            base = URI.create(override.trim());
        }
        return new RatesClient(base, Duration.ofSeconds(20));
    }

    public PriceIndex load(String locale) {
        try {
            String body = fetch(locale);
            PriceIndex live = RatesParser.parse(body);
            return new PriceIndex(
                    live.cities(), live.asOf(), live.attribution(), live.licenseUrl(), Origin.LIVE, null);
        } catch (RatesException exception) {
            return snapshot(exception.getMessage());
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
            return snapshot("The request was interrupted.");
        }
    }

    public String fetch(String locale) throws RatesException, InterruptedException {
        URI uri = endpoint(base, locale);
        HttpClient client = HttpClient.newBuilder()
                .connectTimeout(timeout)
                .followRedirects(HttpClient.Redirect.NEVER)
                .build();
        HttpRequest request = HttpRequest.newBuilder(uri)
                .timeout(timeout)
                .header("Accept", "application/json")
                .header("User-Agent", USER_AGENT)
                .GET()
                .build();
        HttpResponse<String> response = send(client, request);
        int status = response.statusCode();
        if (status >= 200 && status < 300) {
            return body(response);
        }
        if (status == 429 || status >= 500) {
            sleep(retryDelay(response.headers()));
            response = send(client, request);
            status = response.statusCode();
            if (status >= 200 && status < 300) {
                return body(response);
            }
        }
        throw new RatesException("HTTP_" + status, problem(status, response.body()));
    }

    public static URI endpoint(URI base, String locale) {
        return URI.create(base.toString().replaceAll("/+$", "") + "/v1/market/rates?locale=" + normalizeLocale(locale));
    }

    public static String normalizeLocale(String locale) {
        if (locale == null) {
            return "en";
        }
        String language = locale.toLowerCase(Locale.ROOT);
        if (language.startsWith("de")) {
            return "de";
        }
        if (language.startsWith("es")) {
            return "es";
        }
        return "en";
    }

    public static URI validate(URI base) {
        if (base == null) {
            throw new IllegalArgumentException("The API URL is missing.");
        }
        if (base.getUserInfo() != null) {
            throw new IllegalArgumentException("The API URL must not include user info.");
        }
        String host = base.getHost();
        if (host == null || host.isBlank()) {
            throw new IllegalArgumentException("The API URL needs a host.");
        }
        boolean loopback = "localhost".equalsIgnoreCase(host) || "127.0.0.1".equals(host);
        String scheme = base.getScheme();
        boolean allowedScheme = "https".equalsIgnoreCase(scheme) || ("http".equalsIgnoreCase(scheme) && loopback);
        if (!allowedScheme) {
            throw new IllegalArgumentException("The API URL must use https.");
        }
        String path = base.getPath();
        if (path != null && !path.isEmpty() && !"/".equals(path)) {
            throw new IllegalArgumentException("The API URL must be an origin, without a path.");
        }
        if (base.getQuery() != null || base.getFragment() != null) {
            throw new IllegalArgumentException("The API URL must not include a query or a fragment.");
        }
        return base;
    }

    static Duration retryDelay(HttpHeaders headers) {
        Long seconds = seconds(headers.firstValue("Retry-After").orElse(null));
        if (seconds == null) {
            seconds = seconds(headers.firstValue("RateLimit-Reset").orElse(null));
        }
        if (seconds == null) {
            seconds = 2L;
        }
        if (seconds < 0) {
            seconds = 0L;
        }
        if (seconds > 10) {
            seconds = 10L;
        }
        return Duration.ofSeconds(seconds);
    }

    private static Long seconds(String header) {
        if (header == null || !header.matches("\\d+")) {
            return null;
        }
        try {
            return Long.parseLong(header);
        } catch (NumberFormatException exception) {
            return null;
        }
    }

    private static HttpResponse<String> send(HttpClient client, HttpRequest request)
            throws RatesException, InterruptedException {
        try {
            return client.send(request, HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8));
        } catch (IOException exception) {
            String message = exception.getMessage();
            throw new RatesException("CONNECTION", message == null || message.isBlank() ? "The connection failed." : message);
        }
    }

    private static String body(HttpResponse<String> response) throws RatesException {
        String body = response.body();
        if (body != null && body.length() > 8_000_000) {
            throw new RatesException("BAD_RESPONSE", "The response is too large.");
        }
        return body;
    }

    private static String problem(int status, String body) {
        String detail = null;
        if (body != null && body.stripLeading().startsWith("{")) {
            try {
                if (Json.parse(body) instanceof Json.Obj object) {
                    detail = object.str("detail");
                    if (detail == null || detail.isBlank()) {
                        detail = object.str("title");
                    }
                }
            } catch (RuntimeException ignored) {
                detail = null;
            }
        }
        if (detail == null || detail.isBlank()) {
            return "HTTP " + status;
        }
        String trimmed = detail.replace('\n', ' ').trim();
        if (trimmed.length() > 180) {
            trimmed = trimmed.substring(0, 180);
        }
        return "HTTP " + status + ": " + trimmed;
    }

    private static void sleep(Duration delay) throws InterruptedException {
        if (!delay.isZero() && !delay.isNegative()) {
            Thread.sleep(delay.toMillis());
        }
    }

    private static PriceIndex snapshot(String notice) {
        try {
            PriceIndex bundled = Snapshot.load();
            return new PriceIndex(
                    bundled.cities(),
                    bundled.asOf(),
                    bundled.attribution(),
                    bundled.licenseUrl(),
                    Origin.SNAPSHOT,
                    notice);
        } catch (RatesException exception) {
            return new PriceIndex(List.of(), null, null, null, Origin.SNAPSHOT,
                    notice + " The bundled snapshot could not be read: " + exception.getMessage());
        }
    }
}
