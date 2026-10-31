package io.github.coworkingview;

import java.net.http.HttpClient;
import java.time.Clock;
import java.time.Duration;
import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.function.Function;

/**
 * Client for the public CoworkingView API.
 *
 * <p>The API needs no key. A client holds no session and is safe to share between
 * threads. Building one does not touch the network. Queries are not safe to mutate
 * while a call is reading them.
 *
 * <p>On HTTP 429 or 5xx the client waits {@code Retry-After} seconds, else
 * {@code RateLimit-Reset}, else 2 seconds, and never more than 10 seconds, then
 * retries once. The API allows 120 requests per minute per IP and its responses are
 * cacheable for 10 minutes.
 *
 * <pre>{@code
 * Client client = Client.create();
 * Dataset<List<Rate>> berlin = client.rates(new RatesQuery().city("berlin"));
 * System.out.println(berlin.getAttribution());
 * Dataset<Space> space = client.space("sankt-oberholz-rosenthaler-berlin");
 * }</pre>
 */
public final class Client {
    /** Production API root. */
    public static final String DEFAULT_BASE_URL = "https://api.coworkingview.com";

    /** Environment variable that overrides {@link #DEFAULT_BASE_URL}. */
    public static final String BASE_URL_ENV = "COWORKINGVIEW_API_URL";

    /**
     * Most spaces {@link #spaces(SpacesQuery)} will return. The catalogue may be
     * searched and linked, not bulk-copied.
     */
    public static final int MAX_SPACES = Checks.MAX_SPACES;

    /** Row cap when {@link SpacesQuery#limit(int)} is not called. */
    public static final int DEFAULT_SPACES_LIMIT = 50;

    private static final int MAX_PAGE_SIZE = 50;
    private static final Duration DEFAULT_TIMEOUT = Duration.ofSeconds(20);

    private final Transport transport;
    private final Duration timeout;
    private final String userAgent;
    private final Locale locale;

    private Client(Builder builder) {
        if (builder.timeout == null || builder.timeout.isZero() || builder.timeout.isNegative()) {
            throw new IllegalArgumentException("timeout must be a positive duration, got " + builder.timeout + ".");
        }
        if (builder.locale == null) {
            throw new IllegalArgumentException("locale must be en, es or de.");
        }
        String resolved = builder.baseUrl;
        if (resolved == null || resolved.trim().isEmpty()) {
            String fromEnv = builder.environment.apply(BASE_URL_ENV);
            if (fromEnv != null && !fromEnv.trim().isEmpty()) {
                resolved = fromEnv;
            }
        }
        if (resolved == null || resolved.trim().isEmpty()) {
            resolved = DEFAULT_BASE_URL;
        }
        resolved = stripTrailingSlashes(resolved.trim());
        String agent = builder.userAgent == null || builder.userAgent.trim().isEmpty()
                ? Version.userAgent()
                : builder.userAgent;
        HttpClient http = HttpClient.newBuilder()
                .connectTimeout(builder.timeout)
                .followRedirects(HttpClient.Redirect.NORMAL)
                .build();
        this.transport = new Transport(resolved, builder.timeout, agent, builder.sleeper, builder.clock, http);
        this.timeout = builder.timeout;
        this.userAgent = agent;
        this.locale = builder.locale;
    }

    /**
     * A client for {@link #DEFAULT_BASE_URL}, or for {@code COWORKINGVIEW_API_URL} when
     * that variable is set, with English names and a 20 second timeout.
     *
     * @return the client
     */
    public static Client create() {
        return builder().build();
    }

    /**
     * Starts a {@link Builder}.
     *
     * @return a new builder
     */
    public static Builder builder() {
        return new Builder();
    }

    /**
     * The version this client reports in its {@code User-Agent}.
     *
     * @return the version, for example {@code 0.1.0}
     */
    public static String version() {
        return Version.version();
    }

    /**
     * API root this client talks to, without a trailing slash.
     *
     * @return the base URL
     */
    public String getBaseUrl() {
        return transport.baseUrl();
    }

    /**
     * Per-request timeout.
     *
     * @return the timeout
     */
    public Duration getTimeout() {
        return timeout;
    }

    /**
     * {@code User-Agent} sent with every request.
     *
     * @return the header value
     */
    public String getUserAgent() {
        return userAgent;
    }

    /**
     * Locale used when a call does not set one.
     *
     * @return the locale
     */
    public Locale getLocale() {
        return locale;
    }

    /**
     * The whole Price Index: one row per published city and product, in the client's
     * locale and each city's own currency.
     *
     * @return the figures, with attribution
     * @throws ApiException the API returned an error, or a 2xx body this client cannot read
     * @throws CoworkingViewException the API could not be reached
     */
    public Dataset<List<Rate>> rates() {
        return rates(new RatesQuery());
    }

    /**
     * The Price Index, filtered. {@code GET /v1/market/rates}.
     *
     * <p>Rows are ordered by city slug, then by product. Cities in {@code unpublished}
     * produce no rows. {@link RatesQuery#product(Product)} is applied locally.
     *
     * @param query the filters
     * @return the figures, with attribution
     * @throws NullPointerException when {@code query} is {@code null}
     * @throws ApiException the API returned an error, or a 2xx body this client cannot read
     * @throws CoworkingViewException the API could not be reached
     */
    public Dataset<List<Rate>> rates(RatesQuery query) {
        Objects.requireNonNull(query, "query");
        List<Product> products = new ArrayList<Product>(query.getProducts());
        Transport.HttpResult response = transport.get("/v1/market/rates", ratesParams(query));
        Dataset<List<Rate>> dataset = Parser.rates(response.status, response.body);
        if (products.isEmpty()) {
            return dataset;
        }
        Set<String> wanted = new LinkedHashSet<String>();
        for (Product product : products) {
            wanted.add(product.getApiName());
        }
        List<Rate> kept = new ArrayList<Rate>();
        for (Rate rate : dataset.getData()) {
            if (wanted.contains(rate.getProduct().getApiName())) {
                kept.add(rate);
            }
        }
        return dataset.withData(Collections.unmodifiableList(kept));
    }

    /**
     * Every city of the Price Index, published cities first.
     *
     * @return the cities, with attribution
     * @throws ApiException the API returned an error, or a 2xx body this client cannot read
     * @throws CoworkingViewException the API could not be reached
     */
    public Dataset<List<City>> cities() {
        return cities(new RatesQuery());
    }

    /**
     * Cities of the Price Index, filtered. Same request as {@link #rates(RatesQuery)}.
     * {@link RatesQuery#product(Product)} is ignored.
     *
     * @param query the filters
     * @return the cities, with attribution
     * @throws NullPointerException when {@code query} is {@code null}
     * @throws ApiException the API returned an error, or a 2xx body this client cannot read
     * @throws CoworkingViewException the API could not be reached
     */
    public Dataset<List<City>> cities(RatesQuery query) {
        Objects.requireNonNull(query, "query");
        Transport.HttpResult response = transport.get("/v1/market/rates", ratesParams(query));
        return Parser.cities(response.status, response.body);
    }

    /**
     * Searches the catalogue with the default query: 50 spaces, random order, the
     * client's locale. {@code GET /v1/properties}.
     *
     * @return the rows, with the citation and the catalogue notice
     * @throws ApiException the API returned an error, or a 2xx body this client cannot read
     * @throws CoworkingViewException the API could not be reached
     */
    public Dataset<List<Listing>> spaces() {
        return spaces(new SpacesQuery());
    }

    /**
     * Searches the catalogue. Pages are followed until {@link SpacesQuery#getLimit()}
     * rows, at most {@link #MAX_SPACES}, or the last page. Page size is
     * {@code min(50, limit)}. With random order the seed of the first page is reused,
     * unless {@link SpacesQuery#seed(long)} set one.
     *
     * @param query the filters
     * @return the rows, with the citation, the catalogue notice and {@code pagination.total}
     * @throws NullPointerException when {@code query} is {@code null}
     * @throws ApiException the API returned an error, or a 2xx body this client cannot read
     * @throws CoworkingViewException the API could not be reached
     */
    public Dataset<List<Listing>> spaces(SpacesQuery query) {
        Objects.requireNonNull(query, "query");
        int limit = query.getLimit();
        int pageSize = Math.min(MAX_PAGE_SIZE, limit);
        Locale requestLocale = query.getLocale() == null ? locale : query.getLocale();
        boolean random = query.getSort() == Sort.RANDOM;
        boolean userSeed = query.getSeed() != null;
        String seed = userSeed ? query.getSeed().toString() : null;

        Map<String, String> base = new LinkedHashMap<String, String>();
        put(base, "locale", requestLocale.getCode());
        put(base, "city", query.getCity());
        put(base, "country", query.getCountry());
        put(base, "zone", query.getZone());
        put(base, "operator", query.getOperator());
        put(base, "pricingOptionType", query.getProduct() == null ? null : query.getProduct().getApiName());
        put(base, "minCapacity", query.getMinCapacity() == null ? null : query.getMinCapacity().toString());
        put(base, "minPrice", query.getMinPrice() == null ? null : Checks.decimal(query.getMinPrice()));
        put(base, "maxPrice", query.getMaxPrice() == null ? null : Checks.decimal(query.getMaxPrice()));
        put(base, "currency", query.getCurrency() == null ? null : query.getCurrency().getCode());
        put(base, "sortBy", query.getSort().getApiName());

        List<Listing> rows = new ArrayList<Listing>();
        Dataset<List<Listing>> first = null;
        int page = 1;
        while (true) {
            Map<String, String> params = new LinkedHashMap<String, String>(base);
            params.put("page", Integer.toString(page));
            params.put("pageSize", Integer.toString(pageSize));
            if (seed != null) {
                params.put("seed", seed);
            }
            Transport.HttpResult response = transport.get("/v1/properties", params);
            Parser.Page parsed = Parser.spaces(response.status, response.body, requestLocale);
            if (page == 1 && random && !userSeed && parsed.seed != null) {
                seed = parsed.seed;
            }
            if (first == null) {
                first = parsed.dataset;
            }
            for (Listing listing : parsed.dataset.getData()) {
                if (rows.size() >= limit) {
                    break;
                }
                rows.add(listing);
            }
            boolean last = parsed.pageCount == null || page >= parsed.pageCount.longValue();
            if (rows.size() >= limit || parsed.dataset.getData().isEmpty() || last) {
                break;
            }
            page++;
        }
        return first.withData(Collections.unmodifiableList(rows));
    }

    /**
     * One space and its pricing table, in the client's locale. {@code GET /v1/properties/{slug}}.
     *
     * @param slug the space slug from a search
     * @return the space, with the citation and the catalogue notice
     * @throws IllegalArgumentException when {@code slug} is not a valid slug
     * @throws ApiException the API returned an error, or a 2xx body this client cannot read
     * @throws CoworkingViewException the API could not be reached
     */
    public Dataset<Space> space(String slug) {
        return space(slug, locale);
    }

    /**
     * One space and its pricing table.
     *
     * @param slug the space slug from a search
     * @param locale {@code en}, {@code es} or {@code de}. Used for the request and, when
     *     the response has no {@code webUrl}, for the listing link
     * @return the space, with the citation and the catalogue notice
     * @throws IllegalArgumentException when {@code slug} or {@code locale} is not valid
     * @throws ApiException the API returned an error, or a 2xx body this client cannot read
     * @throws CoworkingViewException the API could not be reached
     */
    public Dataset<Space> space(String slug, String locale) {
        return space(slug, Locale.parse(locale));
    }

    /**
     * One space and its pricing table.
     *
     * @param slug the space slug from a search
     * @param locale language of the request. When the response has no {@code webUrl},
     *     the listing link is built in this locale
     * @return the space, with the citation and the catalogue notice
     * @throws IllegalArgumentException when {@code slug} is not a valid slug
     * @throws NullPointerException when {@code locale} is {@code null}
     * @throws ApiException the API returned an error, or a 2xx body this client cannot read
     * @throws CoworkingViewException the API could not be reached
     */
    public Dataset<Space> space(String slug, Locale locale) {
        String checked = Checks.slug(slug);
        Locale requestLocale = Objects.requireNonNull(locale, "locale");
        Map<String, String> params = new LinkedHashMap<String, String>();
        params.put("locale", requestLocale.getCode());
        String path = "/v1/properties/" + checked;
        Transport.HttpResult response = transport.get(path, params);
        return Parser.space(response.status, response.body, requestLocale, checked);
    }

    private Map<String, String> ratesParams(RatesQuery query) {
        Locale requestLocale = query.getLocale() == null ? locale : query.getLocale();
        Map<String, String> params = new LinkedHashMap<String, String>();
        put(params, "locale", requestLocale.getCode());
        put(params, "city", query.getCity());
        put(params, "country", query.getCountry());
        put(params, "currency", query.getCurrency() == null ? null : query.getCurrency().getCode());
        return params;
    }

    private static void put(Map<String, String> params, String key, String value) {
        if (value != null) {
            params.put(key, value);
        }
    }

    private static String stripTrailingSlashes(String url) {
        int end = url.length();
        while (end > 0 && url.charAt(end - 1) == '/') {
            end--;
        }
        return url.substring(0, end);
    }

    @Override
    public String toString() {
        return "Client(baseUrl=" + getBaseUrl() + ", timeout=" + timeout + ")";
    }

    /**
     * Builds a {@link Client}. A builder is not safe to share between threads.
     */
    public static final class Builder {
        private String baseUrl;
        private Duration timeout = DEFAULT_TIMEOUT;
        private String userAgent;
        private Locale locale = Locale.EN;
        private Function<String, String> environment = System::getenv;
        private Transport.Sleeper sleeper = new Transport.Sleeper() {
            @Override
            public void sleepMillis(long millis) throws InterruptedException {
                if (millis > 0) {
                    Thread.sleep(millis);
                }
            }
        };
        private Clock clock = Clock.systemUTC();

        private Builder() {}

        /**
         * API root. The default is {@code COWORKINGVIEW_API_URL}, else
         * {@link Client#DEFAULT_BASE_URL}. A trailing slash is removed.
         *
         * @param baseUrl the root, for example {@code https://api.coworkingview.com}
         * @return this builder
         */
        public Builder baseUrl(String baseUrl) {
            this.baseUrl = baseUrl;
            return this;
        }

        /**
         * Overall timeout per request, including the connection. The default is 20 seconds.
         *
         * @param timeout a positive duration
         * @return this builder
         */
        public Builder timeout(Duration timeout) {
            this.timeout = timeout;
            return this;
        }

        /**
         * {@code User-Agent} header. The default names this library and the source
         * repository. Append your own product token if you build on top of the client,
         * so the operators of the API can reach you.
         *
         * @param userAgent the header value
         * @return this builder
         */
        public Builder userAgent(String userAgent) {
            this.userAgent = userAgent;
            return this;
        }

        /**
         * Default locale for calls that do not set one. The default is {@link Locale#EN}.
         *
         * @param locale the locale
         * @return this builder
         * @throws NullPointerException when {@code locale} is {@code null}
         */
        public Builder locale(Locale locale) {
            this.locale = Objects.requireNonNull(locale, "locale");
            return this;
        }

        Builder environment(Function<String, String> environment) {
            this.environment = Objects.requireNonNull(environment, "environment");
            return this;
        }

        Builder sleeper(Transport.Sleeper sleeper) {
            this.sleeper = Objects.requireNonNull(sleeper, "sleeper");
            return this;
        }

        Builder clock(Clock clock) {
            this.clock = Objects.requireNonNull(clock, "clock");
            return this;
        }

        /**
         * Builds the client. Makes no network call.
         *
         * @return the client
         * @throws IllegalArgumentException when the timeout is not positive
         */
        public Client build() {
            return new Client(this);
        }
    }
}
