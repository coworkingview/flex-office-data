package io.github.coworkingview;

import java.io.IOException;
import java.net.URI;
import java.net.URISyntaxException;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.time.Clock;
import java.time.Duration;
import java.time.ZonedDateTime;
import java.time.format.DateTimeFormatter;
import java.time.format.DateTimeParseException;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;

/** One GET, JSON in, at most one retry. */
final class Transport {
    static final double FALLBACK_WAIT_SECONDS = 2.0d;
    static final double MAX_WAIT_SECONDS = 10.0d;

    private static final DateTimeFormatter HTTP_DATE = DateTimeFormatter.RFC_1123_DATE_TIME;

    private final String baseUrl;
    private final Duration timeout;
    private final String userAgent;
    private final Sleeper sleeper;
    private final Clock clock;
    private final HttpClient http;

    Transport(String baseUrl, Duration timeout, String userAgent, Sleeper sleeper, Clock clock, HttpClient http) {
        this.baseUrl = baseUrl;
        this.timeout = timeout;
        this.userAgent = userAgent;
        this.sleeper = sleeper;
        this.clock = clock;
        this.http = http;
    }

    String baseUrl() {
        return baseUrl;
    }

    /** @return the body of a 2xx response */
    HttpResult get(String path, Map<String, String> query) {
        String url = url(path, query);
        boolean retried = false;
        while (true) {
            HttpResponse<String> response = send(url);
            int status = response.statusCode();
            if (status >= 200 && status < 300) {
                String body = response.body();
                return new HttpResult(status, body == null ? "" : body);
            }
            if (!retried && (status == 429 || status >= 500)) {
                retried = true;
                long wait = retryMillis(
                        response.headers().firstValue("retry-after").orElse(null),
                        response.headers().firstValue("ratelimit-reset").orElse(null),
                        clock);
                try {
                    sleeper.sleepMillis(wait);
                } catch (InterruptedException ex) {
                    Thread.currentThread().interrupt();
                    throw new CoworkingViewException("Could not reach " + baseUrl + ": interrupted", ex);
                }
                continue;
            }
            throw problem(status, response.body());
        }
    }

    private HttpResponse<String> send(String url) {
        HttpRequest request;
        try {
            request = HttpRequest.newBuilder(new URI(url))
                    .timeout(timeout)
                    .header("Accept", "application/json")
                    .header("User-Agent", userAgent)
                    .GET()
                    .build();
        } catch (URISyntaxException ex) {
            throw new CoworkingViewException("Could not reach " + baseUrl + ": " + ex.getMessage(), ex);
        }
        try {
            return http.send(request, HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8));
        } catch (InterruptedException ex) {
            Thread.currentThread().interrupt();
            throw new CoworkingViewException("Could not reach " + baseUrl + ": interrupted", ex);
        } catch (IOException ex) {
            throw new CoworkingViewException("Could not reach " + baseUrl + ": " + ex.getMessage(), ex);
        }
    }

    private String url(String path, Map<String, String> query) {
        StringBuilder sb = new StringBuilder(baseUrl);
        if (!path.startsWith("/")) {
            sb.append('/');
        }
        sb.append(path);
        if (query != null && !query.isEmpty()) {
            sb.append('?');
            boolean first = true;
            for (Map.Entry<String, String> entry : query.entrySet()) {
                if (entry.getValue() == null) {
                    continue;
                }
                if (!first) {
                    sb.append('&');
                }
                first = false;
                sb.append(URLEncoder.encode(entry.getKey(), StandardCharsets.UTF_8));
                sb.append('=');
                sb.append(URLEncoder.encode(entry.getValue(), StandardCharsets.UTF_8));
            }
        }
        return sb.toString();
    }

    private ApiException problem(int status, String body) {
        Json.Value parsed = null;
        if (body != null && !body.trim().isEmpty()) {
            try {
                parsed = Json.parse(body);
            } catch (Json.JsonException ignored) {
                parsed = null;
            }
        }
        String reason = reasonPhrase(status);
        if (parsed == null || !parsed.isObject()) {
            return new ApiException(status, "HTTP_" + status, reason, null, null, Collections.<FieldError>emptyList());
        }
        String code = parsed.optString("code");
        String title = parsed.optString("title");
        if (code == null || code.isEmpty()) {
            code = "HTTP_" + status;
        }
        if (title == null || title.isEmpty()) {
            title = reason;
        }
        List<FieldError> errors = new ArrayList<FieldError>();
        Json.Value rawErrors = parsed.get("errors");
        if (rawErrors != null && rawErrors.isArray()) {
            for (Json.Value item : rawErrors.elements()) {
                if (!item.isObject()) {
                    continue;
                }
                String path = item.optString("path");
                String message = item.optString("message");
                if (path == null && message == null) {
                    continue;
                }
                errors.add(new FieldError(path, message));
            }
        }
        return new ApiException(status, code, title, parsed.optString("detail"), parsed.optString("type"), errors);
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
            // An HTTP-date is the other legal Retry-After form.
        }
        try {
            ZonedDateTime when = ZonedDateTime.parse(trimmed, HTTP_DATE);
            double delta = (when.toInstant().toEpochMilli() - clock.instant().toEpochMilli()) / 1000.0d;
            return delta < 0d ? 0d : delta;
        } catch (DateTimeParseException ignored) {
            return null;
        }
    }

    static String reasonPhrase(int status) {
        switch (status) {
            case 200:
                return "OK";
            case 400:
                return "Bad Request";
            case 401:
                return "Unauthorized";
            case 403:
                return "Forbidden";
            case 404:
                return "Not Found";
            case 408:
                return "Request Timeout";
            case 429:
                return "Too Many Requests";
            case 500:
                return "Internal Server Error";
            case 502:
                return "Bad Gateway";
            case 503:
                return "Service Unavailable";
            case 504:
                return "Gateway Timeout";
            default:
                return "HTTP " + status;
        }
    }

    static final class HttpResult {
        final int status;
        final String body;

        HttpResult(int status, String body) {
            this.status = status;
            this.body = body;
        }
    }

    interface Sleeper {
        void sleepMillis(long millis) throws InterruptedException;
    }
}
