package com.coworkingview.eclipse;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.net.InetAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.atomic.AtomicInteger;

import org.junit.Assert;
import org.junit.Test;

public class RatesTest {

    @Test
    public void fixtureCitiesMatchTheSharedContract() throws Exception {
        PriceIndex index = RatesParser.parse(Files.readString(fixture()));
        Assert.assertEquals(3, index.cities().size());
        Assert.assertEquals("Abu Dhabi", index.cities().get(0).name());
        CityPrice berlin = city(index, "berlin");
        Assert.assertEquals("Berlin", berlin.name());
        Assert.assertEquals("DE", berlin.countryCode());
        Assert.assertEquals("EUR", berlin.currency());
        Assert.assertEquals("199–292", PriceText.range(berlin.hotDesk(), Locale.US));
        Assert.assertEquals("290–421", PriceText.range(berlin.dedicatedDesk(), Locale.US));
        Assert.assertEquals("399–550", PriceText.range(berlin.privateOffice(), Locale.US));
        Assert.assertEquals(72, berlin.hotDesk().sampleSize());
        Assert.assertFalse(berlin.hotDesk().lowConfidence());
        Assert.assertTrue(berlin.hotDesk().percentileRange());
        CityPrice abuDhabi = city(index, "abu-dhabi");
        Assert.assertEquals("1,400–1,800*", PriceText.range(abuDhabi.hotDesk(), Locale.US));
        Assert.assertTrue(abuDhabi.hotDesk().lowConfidence());
        Assert.assertNull(cityOrNull(index, "example-town"));
        Assert.assertTrue(index.attribution().contains("CC BY 4.0"));
        Assert.assertTrue(index.attribution().contains("coworkingview.com"));
    }

    @Test
    public void byTypeUsesMinimumAndMaximumWhenFiguresAreAbsent() throws Exception {
        String json = """
                {"data":{"cities":[{"city":{"slug":"lyon","name":"Lyon"},"countryCode":"FR","currency":"EUR",
                "byType":[{"optionType":"flex_desk","median":{"amount":200,"currency":"EUR"},
                "min":{"amount":150,"currency":"EUR"},"max":{"amount":260,"currency":"EUR"},"sampleSize":12}]}],
                "asOf":"2026-10-01T00:00:00Z","attribution":"Source"}}
                """;
        CityPrice lyon = RatesParser.parse(json).cities().get(0);
        DeskQuote hot = lyon.hotDesk();
        Assert.assertFalse(hot.percentileRange());
        Assert.assertEquals("150–260", PriceText.range(hot, Locale.US));
        Assert.assertTrue(PriceText.tooltip(hot, "EUR", Locale.US).contains("Minimum–maximum"));
        Assert.assertNull(lyon.dedicatedDesk());
    }

    @Test
    public void medianOnlyWhenNoSpreadWasPublished() {
        DeskQuote quote = new DeskQuote("35", null, null, false, 59);
        Assert.assertEquals("35", PriceText.range(quote, Locale.US));
        Assert.assertTrue(PriceText.tooltip(quote, "EUR", Locale.US).contains("Percentiles were not published"));
    }

    @Test
    public void equalPercentilesRenderAsOneNumber() {
        DeskQuote quote = new DeskQuote("1800", "1800", "1800", true, 2);
        Assert.assertEquals("1,800*", PriceText.range(quote, Locale.US));
    }

    @Test
    public void jsonRejectsTrailingJunkAndReadsUnicode() {
        Assert.assertEquals("A", ((Json.Str) Json.parse("\"\\u0041\"")).value());
        try {
            Json.parse("{\"a\":1} true");
            Assert.fail("trailing data should fail");
        } catch (Json.JsonException expected) {
            Assert.assertTrue(expected.getMessage().contains("Unexpected"));
        }
    }

    @Test
    public void attributionEscapesMarkupAndLinksOnlyKnownHosts() {
        String linked = Attribution.linkText(
                "See https://evil.example/x and https://coworkingview.com/en/tools/price-index. <b>no</b>");
        Assert.assertFalse(linked.contains("<b>"));
        Assert.assertTrue(linked.contains("&lt;b&gt;"));
        Assert.assertFalse(linked.contains("href=\"https://evil.example/x\""));
        Assert.assertTrue(linked.contains("href=\"https://coworkingview.com/en/tools/price-index\""));
        Assert.assertTrue(linked.contains("href=\"https://coworkingview.com\">CoworkingView</a>"));
        Assert.assertTrue(Attribution.allowed("https://creativecommons.org/licenses/by/4.0/"));
        Assert.assertFalse(Attribution.allowed("http://coworkingview.com"));
        Assert.assertFalse(Attribution.allowed("https://user@coworkingview.com/"));
    }

    @Test
    public void apiUrlMustBeHttpsOrLoopback() {
        Assert.assertEquals(URI.create("https://api.coworkingview.com"),
                RatesClient.validate(URI.create("https://api.coworkingview.com")));
        RatesClient.validate(URI.create("http://127.0.0.1:9"));
        try {
            RatesClient.validate(URI.create("http://example.com"));
            Assert.fail("plain http to a public host should fail");
        } catch (IllegalArgumentException expected) {
            Assert.assertTrue(expected.getMessage().contains("https"));
        }
        Assert.assertEquals("de", RatesClient.normalizeLocale("de_DE"));
        Assert.assertEquals("en", RatesClient.normalizeLocale("fr"));
        Assert.assertEquals(
                URI.create("https://api.coworkingview.com/v1/market/rates?locale=en"),
                RatesClient.endpoint(RatesClient.DEFAULT_BASE, "en_US"));
    }

    @Test
    public void retryOnceOn503ThenReadTheBody() throws Exception {
        String payload = """
                {"data":{"cities":[{"city":{"slug":"berlin","name":"Berlin"},"countryCode":"DE","currency":"EUR",
                "figures":[{"optionType":"private_office","median":{"amount":480,"currency":"EUR"},
                "p25":{"amount":399,"currency":"EUR"},"p75":{"amount":550,"currency":"EUR"},"sampleSize":59}]}],
                "attribution":"Source: CoworkingView Price Index (https://coworkingview.com/en/tools/price-index). CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/)."}}
                """;
        List<String> responses = List.of(response(503, "Retry-After: 0", ""), response(200, "", payload));
        try (Loopback server = new Loopback(responses)) {
            RatesClient client = new RatesClient(server.base(), Duration.ofSeconds(5));
            String body = client.fetch("en");
            Assert.assertTrue(body.contains("private_office"));
            Assert.assertEquals(2, server.requests().size());
            Assert.assertTrue(server.requests().get(0).contains("User-Agent: " + RatesClient.USER_AGENT));
            Assert.assertTrue(server.requests().get(0).contains("GET /v1/market/rates?locale=en"));
            PriceIndex index = RatesParser.parse(body);
            Assert.assertEquals("399–550", PriceText.range(index.cities().get(0).privateOffice(), Locale.US));
        }
    }

    @Test
    public void clientErrorIsNotRetriedAndNamesTheProblemDetail() throws Exception {
        String problem = "{\"title\":\"Bad Request\",\"status\":400,\"detail\":\"currency is not supported\"}";
        try (Loopback server = new Loopback(List.of(response(400, "", problem)))) {
            RatesClient client = new RatesClient(server.base(), Duration.ofSeconds(5));
            try {
                client.fetch("en");
                Assert.fail("400 should fail");
            } catch (RatesException exception) {
                Assert.assertEquals("HTTP_400", exception.code());
                Assert.assertTrue(exception.getMessage().contains("currency is not supported"));
            }
            Assert.assertEquals(1, server.requests().size());
        }
    }

    @Test
    public void failedRequestFallsBackToTheBundledSnapshot() throws Exception {
        int port;
        try (ServerSocket socket = new ServerSocket(0, 1, InetAddress.getByName("127.0.0.1"))) {
            port = socket.getLocalPort();
        }
        PriceIndex index = new RatesClient(URI.create("http://127.0.0.1:" + port), Duration.ofSeconds(2)).load("en");
        Assert.assertEquals(Origin.SNAPSHOT, index.origin());
        Assert.assertNotNull(index.notice());
        Assert.assertTrue(index.cities().size() > 10);
        Assert.assertNotNull(city(index, "berlin").hotDesk());
        Assert.assertEquals("2026-11-01", Snapshot.capturedOn());
        String raw = Files.readString(Path.of("../com.coworkingview.eclipse/resources/snapshot.json"));
        Assert.assertFalse(raw.contains("\"buildings\""));
        Assert.assertTrue(index.attribution().contains("CC BY 4.0"));
    }

    @Test
    public void descriptorsNameTheViewFeatureAndCategory() throws Exception {
        String plugin = Files.readString(Path.of("../com.coworkingview.eclipse/plugin.xml"));
        Assert.assertTrue(plugin.contains("name=\"CoworkingView\""));
        Assert.assertTrue(plugin.contains("CoworkingView Workspace Prices"));
        Assert.assertTrue(plugin.contains("com.coworkingview.eclipse.views.prices"));
        String feature = Files.readString(Path.of("../com.coworkingview.eclipse.feature/feature.xml"));
        Assert.assertTrue(feature.contains("id=\"com.coworkingview.eclipse.feature\""));
        Assert.assertTrue(feature.contains("provider-name=\"CoworkingView\""));
        String category = Files.readString(Path.of("../com.coworkingview.eclipse.site/category.xml"));
        Assert.assertTrue(category.contains("label=\"CoworkingView\""));
    }

    private static CityPrice city(PriceIndex index, String slug) {
        CityPrice found = cityOrNull(index, slug);
        Assert.assertNotNull(slug, found);
        return found;
    }

    private static CityPrice cityOrNull(PriceIndex index, String slug) {
        for (CityPrice city : index.cities()) {
            if (slug.equals(city.slug())) {
                return city;
            }
        }
        return null;
    }

    private static Path fixture() {
        Path path = Path.of("../../../spec/fixtures/market_rates.json");
        Assert.assertTrue("missing " + path.toAbsolutePath(), Files.isRegularFile(path));
        return path;
    }

    private static String response(int status, String extraHeader, String body) {
        String reason = switch (status) {
            case 200 -> "OK";
            case 400 -> "Bad Request";
            case 503 -> "Service Unavailable";
            default -> "Status";
        };
        byte[] bytes = body.getBytes(StandardCharsets.UTF_8);
        String header = extraHeader == null || extraHeader.isBlank() ? "" : extraHeader + "\r\n";
        return "HTTP/1.1 " + status + " " + reason + "\r\n"
                + "Content-Type: application/json; charset=utf-8\r\n"
                + "Content-Length: " + bytes.length + "\r\n"
                + header
                + "Connection: close\r\n\r\n"
                + body;
    }

    private static final class Loopback implements AutoCloseable {
        private final ServerSocket socket;
        private final List<String> responses;
        private final List<String> requests = new CopyOnWriteArrayList<>();
        private final AtomicInteger cursor = new AtomicInteger();
        private final Thread thread;

        Loopback(List<String> responses) throws Exception {
            this.responses = new ArrayList<>(responses);
            this.socket = new ServerSocket(0, 10, InetAddress.getByName("127.0.0.1"));
            this.thread = new Thread(this::serve, "rates-loopback");
            this.thread.setDaemon(true);
            this.thread.start();
        }

        URI base() {
            return URI.create("http://127.0.0.1:" + socket.getLocalPort());
        }

        List<String> requests() {
            return requests;
        }

        private void serve() {
            while (!socket.isClosed()) {
                try (Socket client = socket.accept()) {
                    client.setSoTimeout(5_000);
                    InputStream input = client.getInputStream();
                    ByteArrayOutputStream buffer = new ByteArrayOutputStream();
                    int seen = 0;
                    while (seen < 4) {
                        int value = input.read();
                        if (value < 0) {
                            break;
                        }
                        buffer.write(value);
                        byte[] raw = buffer.toByteArray();
                        int n = raw.length;
                        seen = n >= 4 && raw[n - 4] == '\r' && raw[n - 3] == '\n' && raw[n - 2] == '\r' && raw[n - 1] == '\n'
                                ? 4
                                : 0;
                    }
                    requests.add(buffer.toString(StandardCharsets.UTF_8));
                    int index = Math.min(cursor.getAndIncrement(), responses.size() - 1);
                    client.getOutputStream().write(responses.get(index).getBytes(StandardCharsets.UTF_8));
                    client.getOutputStream().flush();
                } catch (Exception exception) {
                    if (!socket.isClosed()) {
                        exception.printStackTrace();
                    }
                    return;
                }
            }
        }

        @Override
        public void close() throws Exception {
            socket.close();
            thread.join(1_000);
        }
    }
}
