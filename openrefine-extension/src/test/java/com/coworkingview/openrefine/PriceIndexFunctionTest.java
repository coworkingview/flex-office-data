package com.coworkingview.openrefine;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertInstanceOf;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.fasterxml.jackson.databind.node.ObjectNode;
import com.google.refine.expr.EvalError;
import java.io.IOException;
import java.io.InputStream;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.List;
import java.util.Properties;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

class PriceIndexFunctionTest {
    private static final String BERLIN = resource("berlin-rates.json");
    private static final String ATTRIBUTION =
            "Source: CoworkingView Price Index (https://coworkingview.com/en/tools/price-index), as of October 2026. Licensed under CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/). Aggregated figures only; no endorsement by CoworkingView or any operator is implied.";

    private final ScriptedTransport transport = new ScriptedTransport();
    private final PriceIndexFunction function = new PriceIndexFunction();

    @BeforeEach
    void installClient() {
        transport.enqueue(200, BERLIN, null, null, "max-age=600");
        PriceIndexFunction.use(RatesClient.forTest(
                "https://api.coworkingview.com",
                transport,
                Clock.fixed(Instant.parse("2026-11-04T00:00:00Z"), ZoneOffset.UTC),
                millis -> {
                }));
    }

    @AfterEach
    void restoreClient() {
        PriceIndexFunction.resetClient();
    }

    @Test
    void defaultProductIsTheFlexDeskMedianFromTheFixture() {
        ObjectNode figure = (ObjectNode) function.call(new Properties(), new Object[] {"Berlin"});

        assertEquals("berlin", figure.get("citySlug").asText());
        assertEquals("Berlin", figure.get("cityName").asText());
        assertEquals("DE", figure.get("countryCode").asText());
        assertEquals("EUR", figure.get("currency").asText());
        assertEquals("flex_desk", figure.get("product").asText());
        assertEquals("month", figure.get("unit").asText());
        assertEquals(214L, figure.get("median").longValue());
        assertEquals(199L, figure.get("p25").longValue());
        assertEquals(292L, figure.get("p75").longValue());
        assertEquals(80L, figure.get("min").longValue());
        assertEquals(750L, figure.get("max").longValue());
        assertEquals(72L, figure.get("sampleSize").longValue());
        assertEquals(66L, figure.get("propertyCount").longValue());
        assertEquals(38L, figure.get("operatorCount").longValue());
        assertFalse(figure.get("lowConfidence").booleanValue());
        assertEquals("2026-10-27T21:06:48.313Z", figure.get("asOf").asText());
        assertEquals(ATTRIBUTION, figure.get("attribution").asText());
        assertEquals("https://creativecommons.org/licenses/by/4.0/", figure.get("license").asText());
        assertEquals(
                "https://api.coworkingview.com/v1/market/rates?locale=en&city=berlin",
                transport.uris.get(0).toString());
        assertEquals(1, transport.uris.size());
    }

    @Test
    void namedProductAndFriendlySpelling() {
        ObjectNode figure = (ObjectNode) function.call(new Properties(), new Object[] {"berlin", "Private Office"});

        assertEquals("private_office", figure.get("product").asText());
        assertEquals(480L, figure.get("median").longValue());
        assertEquals(399L, figure.get("p25").longValue());
        assertEquals(70L, figure.get("min").longValue());
        assertEquals(1000L, figure.get("max").longValue());
    }

    @Test
    void dayPassComesFromTheAggregateAndHasNoInventedPercentile() {
        ObjectNode figure = (ObjectNode) function.call(new Properties(), new Object[] {"berlin", "day_pass"});

        assertEquals("day", figure.get("unit").asText());
        assertEquals(35L, figure.get("median").longValue());
        assertEquals(59L, figure.get("sampleSize").longValue());
        assertFalse(figure.has("p25"));
        assertFalse(figure.has("p75"));
        assertFalse(figure.has("min"));
    }

    @Test
    void meetingRoomIsHourly() {
        ObjectNode figure = (ObjectNode) function.call(new Properties(), new Object[] {"berlin", "meeting_room"});

        assertEquals("hour", figure.get("unit").asText());
        assertEquals(32L, figure.get("median").longValue());
    }

    @Test
    void secondCallForTheSameCityDoesNotFetchAgain() {
        function.call(new Properties(), new Object[] {"berlin", "flex_desk"});
        function.call(new Properties(), new Object[] {"berlin", "fix_desk"});

        assertEquals(1, transport.uris.size());
        ObjectNode fixed = (ObjectNode) function.call(new Properties(), new Object[] {"berlin", "fix_desk"});
        assertEquals(310L, fixed.get("median").longValue());
    }

    @Test
    void unpublishedCityIsNotGivenAPrice() {
        EvalError error = (EvalError) function.call(new Properties(), new Object[] {"example-town"});

        assertEquals("no published price index for 'example-town'", error.message);
    }

    @Test
    void unknownProductListsWhatTheResponsePublished() {
        EvalError error = (EvalError) function.call(new Properties(), new Object[] {"berlin", "virtual_office"});

        assertEquals(
                "unknown product 'virtual_office'. Available: flex_desk, fix_desk, private_office, day_pass, meeting_room",
                error.message);
    }

    @Test
    void blankCityDoesNotCallTheApi() {
        transport.uris.clear();
        transport.script.clear();
        EvalError error = (EvalError) function.call(new Properties(), new Object[] {"  "});

        assertEquals("city is required, for example berlin", error.message);
        assertTrue(transport.uris.isEmpty());
    }

    @Test
    void wrongArgumentCountIsAnError() {
        assertInstanceOf(EvalError.class, function.call(new Properties(), new Object[] {}));
        assertInstanceOf(EvalError.class, function.call(new Properties(), new Object[] {"berlin", "flex_desk", "median"}));
    }

    @Test
    void httpErrorIsReturnedAndNotReplacedWithANumber() {
        transport.script.clear();
        transport.enqueue(404, "{\"title\":\"Not found\",\"code\":\"NO_CITY\"}", null, null, null);

        EvalError error = (EvalError) function.call(new Properties(), new Object[] {"no-such-city"});

        assertEquals("Not found [NO_CITY]", error.message);
    }

    @Test
    void decimalAmountIsPreserved() throws Exception {
        String body = BERLIN.replace("\"amount\": 214", "\"amount\": 214.5");
        ObjectNode figure = PriceIndexParser.parse(body, "berlin", "flex_desk");

        assertEquals(214.5d, figure.get("median").doubleValue());
    }

    private static String resource(String name) {
        try (InputStream in = PriceIndexFunctionTest.class.getResourceAsStream("/" + name)) {
            if (in == null) {
                throw new IllegalStateException("missing " + name);
            }
            return new String(in.readAllBytes(), StandardCharsets.UTF_8);
        } catch (IOException ex) {
            throw new IllegalStateException(ex);
        }
    }

    private static final class ScriptedTransport implements RatesClient.Transport {
        final List<URI> uris = new ArrayList<URI>();
        final List<RatesClient.HttpResult> script = new ArrayList<RatesClient.HttpResult>();

        void enqueue(int status, String body, String retryAfter, String rateLimitReset, String cacheControl) {
            script.add(new RatesClient.HttpResult(status, body, retryAfter, rateLimitReset, cacheControl));
        }

        @Override
        public RatesClient.HttpResult get(URI uri) {
            uris.add(uri);
            if (script.isEmpty()) {
                throw new IllegalStateException("no scripted response for " + uri);
            }
            return script.remove(0);
        }
    }
}
