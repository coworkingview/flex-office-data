package io.github.coworkingview;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.io.IOException;
import java.lang.reflect.Method;
import java.net.InetSocketAddress;
import java.net.ServerSocket;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.List;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

class ClientTest {
    private static final String RATES_OK = "{\"data\":{\"cities\":[],\"asOf\":\"2026-10-27T21:06:48.313Z\"},\"meta\":{}}";

    private FakeApi api;

    @BeforeEach
    void setUp() throws IOException {
        api = new FakeApi();
    }

    @AfterEach
    void tearDown() {
        api.close();
    }

    @Test
    void userAgentAndAccept() {
        api.queue(FakeApi.Reply.json(RATES_OK));
        api.client().rates();
        assertEquals(
                "coworkingview-java/" + Version.VERSION + " (+https://github.com/coworkingview/flex-office-data)",
                api.requests.get(0).headers.get("user-agent"));
        assertEquals("application/json", api.requests.get(0).headers.get("accept"));
    }

    @Test
    void customUserAgent() {
        api.queue(FakeApi.Reply.json(RATES_OK));
        Client.builder().baseUrl(api.url).environment(name -> null).userAgent("my-app/1.0").build().rates();
        assertEquals("my-app/1.0", api.requests.get(0).headers.get("user-agent"));
    }

    @Test
    void ratesQueryParameters() {
        api.queue(FakeApi.Reply.json(RATES_OK));
        api.client().rates(new RatesQuery().city("berlin").country("DE").currency("eur").locale("de"));
        FakeApi.Seen seen = api.requests.get(0);
        assertEquals("/v1/market/rates", seen.path);
        assertEquals("de", seen.query.get("locale"));
        assertEquals("berlin", seen.query.get("city"));
        assertEquals("DE", seen.query.get("country"));
        assertEquals("EUR", seen.query.get("currency"));
        assertEquals(4, seen.query.size());
    }

    @Test
    void vesIsPassedThrough() {
        api.queue(FakeApi.Reply.json(RATES_OK));
        api.client().rates(new RatesQuery().currency(Currency.VES));
        assertEquals("VES", api.requests.get(0).query.get("currency"));
    }

    @Test
    void spacesQueryParameters() {
        api.responder = paged(1);
        api.client()
                .spaces(new SpacesQuery()
                        .city(" berlin ")
                        .country("DE")
                        .zone("mitte")
                        .operator("regus")
                        .product("meeting_room")
                        .minCapacity(8)
                        .minPrice(10.0d)
                        .maxPrice(99.5d)
                        .currency("EUR")
                        .sort("price-asc")
                        .limit(10)
                        .locale("es"));
        FakeApi.Seen seen = api.requests.get(0);
        assertEquals("/v1/properties", seen.path);
        assertEquals("es", seen.query.get("locale"));
        assertEquals("berlin", seen.query.get("city"));
        assertEquals("DE", seen.query.get("country"));
        assertEquals("mitte", seen.query.get("zone"));
        assertEquals("regus", seen.query.get("operator"));
        assertEquals("meeting_room", seen.query.get("pricingOptionType"));
        assertEquals("8", seen.query.get("minCapacity"));
        assertEquals("10", seen.query.get("minPrice"));
        assertEquals("99.5", seen.query.get("maxPrice"));
        assertEquals("EUR", seen.query.get("currency"));
        assertEquals("price-asc", seen.query.get("sortBy"));
        assertEquals("10", seen.query.get("pageSize"));
        assertEquals("1", seen.query.get("page"));
        assertFalse(seen.query.containsKey("seed"));
    }

    @Test
    void spacesPaginatesAndReusesSeed() {
        api.responder = paged(500);
        Dataset<List<Listing>> result = api.client().spaces(new SpacesQuery().limit(120));
        assertEquals(120, result.getData().size());
        assertEquals("space-0", result.getData().get(0).getSlug());
        assertEquals("space-119", result.getData().get(119).getSlug());
        assertEquals(3, api.requests.size());
        assertEquals(List.of("1", "2", "3"), pages());
        assertTrue(api.requests.stream().allMatch(seen -> "50".equals(seen.query.get("pageSize"))));
        assertFalse(api.requests.get(0).query.containsKey("seed"));
        assertEquals("43", api.requests.get(1).query.get("seed"));
        assertEquals("43", api.requests.get(2).query.get("seed"));
        assertEquals("citation page 1", result.getAttribution());
        assertEquals("notice", result.getNotice());
        assertEquals(Long.valueOf(500), result.getTotal());
        assertEquals("https://coworkingview.com/en/workspace/space-0", result.getData().get(0).getUrl());
    }

    @Test
    void spacesDoesNotSendSeedUnlessRandom() {
        api.responder = paged(80);
        Dataset<List<Listing>> result = api.client().spaces(new SpacesQuery().sort(Sort.DATE_DESC).limit(200));
        assertEquals(80, result.getData().size());
        assertEquals(2, api.requests.size());
        assertFalse(api.requests.get(1).query.containsKey("seed"));
    }

    @Test
    void callerSeedIsSentOnTheFirstPage() {
        api.responder = paged(1);
        api.client().spaces(new SpacesQuery().seed(7).limit(1));
        assertEquals("7", api.requests.get(0).query.get("seed"));
    }

    @Test
    void smallLimitIsOneSmallPage() {
        api.responder = paged(500);
        Dataset<List<Listing>> result = api.client().spaces(new SpacesQuery().limit(5));
        assertEquals(5, result.getData().size());
        assertEquals(1, api.requests.size());
        assertEquals("5", api.requests.get(0).query.get("pageSize"));
    }

    @Test
    void neverExceeds200() {
        api.responder = paged(10_000);
        assertEquals(200, api.client().spaces(new SpacesQuery().limit(200)).getData().size());
        assertEquals(4, api.requests.size());
    }

    @Test
    void stopsWithoutPagination() {
        api.queue(FakeApi.Reply.json("{\"data\":[{\"slug\":\"a\",\"title\":\"A\"}],\"meta\":{}}"));
        Dataset<List<Listing>> result = api.client().spaces();
        assertEquals(1, result.getData().size());
        assertNull(result.getData().get(0).getCitySlug());
        assertNull(result.getData().get(0).getFeatured());
        assertNull(result.getData().get(0).getLat());
        assertNull(result.getData().get(0).getMarketVerdict());
        assertNull(result.getAttribution());
        assertNull(result.getTotal());
        assertEquals(1, api.requests.size());
    }

    @Test
    void listingUrlsFollowLocale() {
        api.responder = paged(1);
        Client client = api.client();
        String english = client.spaces(new SpacesQuery().locale(Locale.EN).limit(1)).getData().get(0).getUrl();
        String spanish = client.spaces(new SpacesQuery().locale("es").limit(1)).getData().get(0).getUrl();
        String german = client.spaces(new SpacesQuery().locale(Locale.DE).limit(1)).getData().get(0).getUrl();
        assertEquals("https://coworkingview.com/en/workspace/space-0", english);
        assertEquals("https://coworkingview.com/es/oficina/space-0", spanish);
        assertEquals("https://coworkingview.com/de/buero/space-0", german);
    }

    @Test
    void productFilterIsLocal() throws IOException {
        api.queue(FakeApi.Reply.json(GoldenTest.fixture("market_rates.json")));
        List<Rate> rates = api.client().rates(new RatesQuery().product(Product.DAY_PASS)).getData();
        assertFalse(rates.isEmpty());
        assertTrue(rates.stream().allMatch(rate -> rate.getProduct().equals(Product.DAY_PASS)));
        assertEquals(1, api.requests.size());
        assertFalse(api.requests.get(0).query.containsKey("pricingOptionType"));
    }

    @Test
    void citiesIncludeUnpublished() throws IOException {
        api.queue(FakeApi.Reply.json(GoldenTest.fixture("market_rates.json")));
        List<City> cities = api.client().cities(new RatesQuery().locale(Locale.EN)).getData();
        assertTrue(cities.get(0).isPublished());
        City last = cities.get(cities.size() - 1);
        assertEquals("example-town", last.getCitySlug());
        assertFalse(last.isPublished());
        assertNull(last.getEntryMedian());
    }

    @Test
    void spaceUsesTheFixtureAndDropsOperatorProse() throws IOException {
        String body = GoldenTest.fixture("property_detail.json");
        api.queue(FakeApi.Reply.json(body));
        Dataset<Space> result = api.client().space("sankt-oberholz-rosenthaler-berlin", "en");
        Space space = result.getData();
        assertEquals("/v1/properties/sankt-oberholz-rosenthaler-berlin", api.requests.get(0).path);
        assertEquals("en", api.requests.get(0).query.get("locale"));
        assertEquals("mitte", space.getZoneSlug());
        assertEquals("St. Oberholz", space.getOperatorName());
        assertEquals(52.5294539d, space.getLat(), 0.0000001d);
        assertEquals(Boolean.TRUE, space.getFeatured());
        assertEquals("around", space.getMarketVerdict());
        assertEquals(214.0d, space.getMarketMedian());
        assertEquals(Long.valueOf(72), space.getMarketSampleSize());
        assertEquals("https://coworkingview.com/en/workspace/sankt-oberholz-rosenthaler-berlin", space.getUrl());
        assertEquals("Rosenthaler Straße 72a, 10119 Berlin, Germany", space.getAddress());
        assertNull(space.getCapacity());
        assertEquals("reception", space.getAmenities().get(0));
        assertEquals(5, space.getPricing().size());
        assertEquals(209.0d, space.getPricing().get(0).getPrice());
        assertNull(space.getPricing().get(1).getPrice());
        assertTrue(result.getNotice().contains("Systematic extraction"));
        for (Method method : Space.class.getMethods()) {
            String name = method.getName().toLowerCase(java.util.Locale.ROOT);
            assertFalse(name.contains("description") || name.contains("image") || name.contains("logo") || name.contains("excerpt"));
        }
    }

    @Test
    void webUrlWinsOverTheLocaleLink() throws IOException {
        api.queue(FakeApi.Reply.json(GoldenTest.fixture("property_detail.json")));
        Space space = api.client().space("sankt-oberholz-rosenthaler-berlin", Locale.DE).getData();
        assertEquals("https://coworkingview.com/en/workspace/sankt-oberholz-rosenthaler-berlin", space.getUrl());
        assertEquals("de", api.requests.get(0).query.get("locale"));
    }

    @Test
    void invalidSlugDoesNotCallTheNetwork() {
        IllegalArgumentException error = assertThrows(
                IllegalArgumentException.class, () -> api.client().space("../etc"));
        assertTrue(error.getMessage().contains("slug"));
        assertTrue(api.requests.isEmpty());
        assertThrows(IllegalArgumentException.class, () -> api.client().space(""));
        assertThrows(IllegalArgumentException.class, () -> api.client().space("-leading"));
        assertThrows(IllegalArgumentException.class, () -> api.client().space("a b"));
        assertThrows(IllegalArgumentException.class, () -> api.client().space("café"));
        api.queue(FakeApi.Reply.json("{\"data\":{\"slug\":\"a.b_c-1\",\"title\":\"A\"},\"meta\":{}}"));
        assertEquals("a.b_c-1", api.client().space("a.b_c-1").getData().getSlug());
    }

    @Test
    void limitCapExplainsWhy() {
        IllegalArgumentException error = assertThrows(
                IllegalArgumentException.class, () -> new SpacesQuery().limit(201));
        assertTrue(error.getMessage().contains("maximum of 200"));
        assertTrue(error.getMessage().contains("not bulk-copied"));
        assertThrows(IllegalArgumentException.class, () -> new SpacesQuery().limit(0));
    }

    @Test
    void validationFailsBeforeARequest() {
        assertTrue(assertThrows(IllegalArgumentException.class, () -> new RatesQuery().locale("fr"))
                .getMessage()
                .contains("'en', 'es', 'de'"));
        assertTrue(assertThrows(IllegalArgumentException.class, () -> new RatesQuery().locale("EN"))
                .getMessage()
                .contains("not supported"));
        assertTrue(assertThrows(IllegalArgumentException.class, () -> new RatesQuery().currency("JPY"))
                .getMessage()
                .contains("EUR"));
        assertTrue(assertThrows(IllegalArgumentException.class, () -> new SpacesQuery().product("desk"))
                .getMessage()
                .contains("flex_desk"));
        assertTrue(assertThrows(IllegalArgumentException.class, () -> new SpacesQuery().sort("price"))
                .getMessage()
                .contains("price-asc"));
        assertTrue(assertThrows(IllegalArgumentException.class, () -> new SpacesQuery().minCapacity(-1))
                .getMessage()
                .contains("minCapacity"));
        assertTrue(assertThrows(IllegalArgumentException.class, () -> new SpacesQuery().minPrice(-1.0d))
                .getMessage()
                .contains("minPrice"));
        assertTrue(assertThrows(IllegalArgumentException.class, () -> new SpacesQuery().minPrice(100.0d).maxPrice(50.0d))
                .getMessage()
                .contains("greater than"));
        assertTrue(assertThrows(IllegalArgumentException.class, () -> new SpacesQuery().city("  "))
                .getMessage()
                .contains("city"));
        assertTrue(api.requests.isEmpty());
    }

    @Test
    void retriesOnceThenSucceeds() {
        for (int status : new int[] {429, 500, 502, 503}) {
            api.requests.clear();
            api.sleeps.clear();
            api.queue(FakeApi.Reply.status(status, "{\"title\":\"busy\"}", null, null));
            api.queue(FakeApi.Reply.json(RATES_OK));
            assertTrue(api.client().rates().getData().isEmpty());
            assertEquals(2, api.requests.size(), "status " + status);
            assertEquals(List.of(2000L), new ArrayList<Long>(api.sleeps));
        }
    }

    @Test
    void retriesOnlyOnce() {
        api.queue(FakeApi.Reply.status(503, "{\"title\":\"Down\",\"code\":\"UNAVAILABLE\"}", null, null));
        api.queue(FakeApi.Reply.status(503, "{\"title\":\"Still down\",\"code\":\"UNAVAILABLE\"}", null, null));
        api.queue(FakeApi.Reply.json(RATES_OK));
        ApiException error = assertThrows(ApiException.class, () -> api.client().rates());
        assertEquals(2, api.requests.size());
        assertEquals(503, error.getStatus());
        assertEquals("Still down", error.getTitle());
        assertEquals("UNAVAILABLE", error.getCode());
        assertEquals(1, api.sleeps.size());
    }

    @Test
    void retryAfterIsHonouredAndCapped() {
        api.queue(FakeApi.Reply.status(429, "{}", "Retry-After", "3"));
        api.queue(FakeApi.Reply.json(RATES_OK));
        api.client().rates();
        assertEquals(List.of(3000L), new ArrayList<Long>(api.sleeps));

        api.requests.clear();
        api.sleeps.clear();
        api.queue(FakeApi.Reply.status(429, "{}", "Retry-After", "120"));
        api.queue(FakeApi.Reply.json(RATES_OK));
        api.client().rates();
        assertEquals(List.of(10000L), new ArrayList<Long>(api.sleeps));

        api.requests.clear();
        api.sleeps.clear();
        api.queue(FakeApi.Reply.status(429, "{}", "RateLimit-Reset", "4"));
        api.queue(FakeApi.Reply.json(RATES_OK));
        api.client().rates();
        assertEquals(List.of(4000L), new ArrayList<Long>(api.sleeps));
    }

    @Test
    void retryWaitParsesHeaders() {
        Clock clock = Clock.fixed(Instant.parse("2026-10-27T21:00:00Z"), ZoneOffset.UTC);
        assertEquals(3000L, Transport.retryMillis("Tue, 27 Oct 2026 21:00:03 GMT", null, clock));
        assertEquals(1500L, Transport.retryMillis("soon", "1.5", clock));
        assertEquals(0L, Transport.retryMillis("-3", null, clock));
        assertEquals(2000L, Transport.retryMillis(null, null, clock));
        assertEquals(10000L, Transport.retryMillis(null, "3600", clock));
    }

    @Test
    void doesNotRetryAClientError() {
        api.queue(FakeApi.Reply.status(400, "{\"title\":\"no\"}", null, null));
        api.queue(FakeApi.Reply.json(RATES_OK));
        ApiException error = assertThrows(ApiException.class, () -> api.client().rates());
        assertEquals(400, error.getStatus());
        assertEquals(1, api.requests.size());
        assertTrue(api.sleeps.isEmpty());
    }

    @Test
    void problemJsonBecomesApiException() throws IOException {
        api.queue(FakeApi.Reply.status(400, GoldenTest.fixture("error_validation.json"), null, null));
        ApiException error = assertThrows(ApiException.class, () -> api.client().rates(new RatesQuery().currency("VES")));
        assertEquals(400, error.getStatus());
        assertEquals("VALIDATION_FAILED", error.getCode());
        assertEquals("Validation failed", error.getTitle());
        assertTrue(error.getDetail().contains("VES"));
        assertEquals("currency", error.getErrors().get(0).getPath());
        assertTrue(error.getMessage().contains("400 VALIDATION_FAILED"));
        assertTrue(error instanceof CoworkingViewException);
    }

    @Test
    void nonJsonErrorFallsBackToTheReasonPhrase() {
        api.queue(FakeApi.Reply.status(403, "<html>Forbidden</html>", null, null));
        ApiException error = assertThrows(ApiException.class, () -> api.client().rates());
        assertEquals(403, error.getStatus());
        assertEquals("HTTP_403", error.getCode());
        assertEquals("Forbidden", error.getTitle());
        assertNull(error.getDetail());
    }

    @Test
    void nonJsonSuccessIsBadResponse() {
        api.queue(FakeApi.Reply.json("<html>maintenance</html>"));
        ApiException error = assertThrows(ApiException.class, () -> api.client().rates());
        assertEquals("BAD_RESPONSE", error.getCode());
        assertEquals(200, error.getStatus());
    }

    @Test
    void jsonThatIsNotAnObjectIsBadResponse() {
        api.queue(FakeApi.Reply.json("[1,2,3]"));
        ApiException error = assertThrows(ApiException.class, () -> api.client().rates());
        assertEquals("BAD_RESPONSE", error.getCode());
    }

    @Test
    void missingDataIsBadResponse() {
        api.queue(FakeApi.Reply.json("{\"meta\":{}}"));
        assertEquals("BAD_RESPONSE", assertThrows(ApiException.class, () -> api.client().rates()).getCode());
        api.queue(FakeApi.Reply.json("{\"data\":[]}"));
        assertEquals("BAD_RESPONSE", assertThrows(ApiException.class, () -> api.client().cities()).getCode());
        api.queue(FakeApi.Reply.json("{\"data\":{}}"));
        assertEquals("BAD_RESPONSE", assertThrows(ApiException.class, () -> api.client().spaces()).getCode());
    }

    @Test
    void unreachableHostRaisesTheBaseException() throws IOException {
        int port;
        try (ServerSocket socket = new ServerSocket()) {
            socket.bind(new InetSocketAddress("127.0.0.1", 0));
            port = socket.getLocalPort();
        }
        Client client = Client.builder()
                .baseUrl("http://127.0.0.1:" + port)
                .timeout(Duration.ofSeconds(2))
                .environment(name -> null)
                .build();
        CoworkingViewException error = assertThrows(CoworkingViewException.class, client::rates);
        assertFalse(error instanceof ApiException);
        assertTrue(error.getMessage().contains("Could not reach"));
    }

    @Test
    void baseUrlResolution() {
        Client fromEnv = Client.builder().environment(name -> api.url + "/").build();
        assertEquals(api.url, fromEnv.getBaseUrl());
        Client explicit = Client.builder()
                .baseUrl("http://arg.invalid")
                .environment(name -> "http://env.invalid")
                .build();
        assertEquals("http://arg.invalid", explicit.getBaseUrl());
        Client fallback = Client.builder().environment(name -> "  ").build();
        assertEquals(Client.DEFAULT_BASE_URL, fallback.getBaseUrl());
        assertTrue(fallback.getUserAgent().startsWith("coworkingview-java/"));
        assertEquals(Duration.ofSeconds(20), fallback.getTimeout());
        assertEquals(Locale.EN, fallback.getLocale());
        assertThrows(IllegalArgumentException.class, () -> Client.builder().timeout(Duration.ZERO).build());
        assertThrows(IllegalArgumentException.class, () -> Client.builder().timeout(Duration.ofSeconds(-1)).build());
    }

    @Test
    void pomVersionMatchesTheClient() throws IOException {
        Path pom = Path.of("pom.xml");
        if (!Files.exists(pom)) {
            pom = Path.of("integrations/java/pom.xml");
        }
        String xml = Files.readString(pom);
        assertTrue(xml.contains("<version>" + Version.VERSION + "</version>"));
        assertTrue(xml.contains("<groupId>io.github.coworkingview</groupId>"));
        assertTrue(xml.contains("<artifactId>coworkingview</artifactId>"));
        assertTrue(xml.contains("<autoPublish>false</autoPublish>"));
        assertTrue(xml.contains("maven-gpg-plugin"));
        assertTrue(xml.contains("central-publishing-maven-plugin"));
    }

    private List<String> pages() {
        List<String> pages = new ArrayList<String>();
        for (FakeApi.Seen seen : api.requests) {
            pages.add(seen.query.get("page"));
        }
        return pages;
    }

    private static FakeApi.Responder paged(int total) {
        return seen -> {
            int page = Integer.parseInt(seen.query.get("page"));
            int size = Integer.parseInt(seen.query.get("pageSize"));
            int start = (page - 1) * size;
            int end = Math.min(start + size, total);
            StringBuilder cards = new StringBuilder();
            cards.append('[');
            for (int i = start; i < end; i++) {
                if (i > start) {
                    cards.append(',');
                }
                cards.append("{\"slug\":\"space-")
                        .append(i)
                        .append("\",\"title\":\"Space ")
                        .append(i)
                        .append("\",\"city\":{\"slug\":\"berlin\"}}");
            }
            cards.append(']');
            int pageCount = size == 0 ? 0 : (total + size - 1) / size;
            return FakeApi.Reply.json("{\"data\":" + cards + ",\"meta\":{\"pagination\":{\"page\":" + page
                    + ",\"pageSize\":" + size + ",\"total\":" + total + ",\"pageCount\":" + pageCount
                    + "},\"seed\":" + (42 + page) + ",\"citation\":{\"text\":\"citation page " + page
                    + "\"},\"catalogueNotice\":\"notice\"}}");
        };
    }
}
