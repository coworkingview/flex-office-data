package com.coworkingview.openrefine;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.fasterxml.jackson.databind.node.ObjectNode;
import com.sun.net.httpserver.HttpServer;
import java.io.IOException;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

/** The JDK client against a local server, so the test never calls api.coworkingview.com. */
class RatesClientHttpTest {
    private static final String BODY = resource();

    private HttpServer server;
    private final List<String> paths = new ArrayList<String>();
    private final List<String> agents = new ArrayList<String>();
    private final AtomicInteger hits = new AtomicInteger();
    private final List<Long> sleeps = new ArrayList<Long>();

    @BeforeEach
    void start() throws IOException {
        server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        server.createContext("/v1/market/rates", exchange -> {
            hits.incrementAndGet();
            paths.add(exchange.getRequestURI().getRawQuery());
            agents.add(exchange.getRequestHeaders().getFirst("User-Agent"));
            agents.add(exchange.getRequestHeaders().getFirst("Accept"));
            byte[] bytes;
            int status;
            if (hits.get() == 1) {
                status = 500;
                bytes = "{\"title\":\"unavailable\",\"code\":\"HTTP_500\"}".getBytes(StandardCharsets.UTF_8);
                exchange.getResponseHeaders().add("Retry-After", "0");
            } else {
                status = 200;
                bytes = BODY.getBytes(StandardCharsets.UTF_8);
                exchange.getResponseHeaders().add("Cache-Control", "max-age=600");
            }
            exchange.sendResponseHeaders(status, bytes.length);
            try (OutputStream out = exchange.getResponseBody()) {
                out.write(bytes);
            }
        });
        server.start();
    }

    @AfterEach
    void stop() {
        server.stop(0);
    }

    @Test
    void retriesOnceThenReadsTheFixture() throws Exception {
        RatesClient client = RatesClient.forTest(
                "http://127.0.0.1:" + server.getAddress().getPort(),
                RatesClient.httpTransport(),
                Clock.fixed(Instant.parse("2026-11-04T00:00:00Z"), ZoneOffset.UTC),
                millis -> {
                    sleeps.add(millis);
                });

        ObjectNode figure = client.priceIndex("berlin", "flex_desk");

        assertEquals(214L, figure.get("median").longValue());
        assertEquals(2, hits.get());
        assertEquals(List.of(0L), sleeps);
        assertEquals("locale=en&city=berlin", paths.get(0));
        assertEquals("locale=en&city=berlin", paths.get(1));
        assertTrue(agents.get(0).startsWith("coworkingview-openrefine/0.1.0 "));
        assertEquals("application/json", agents.get(1));

        client.priceIndex("berlin", "fix_desk");
        assertEquals(2, hits.get());
    }

    @Test
    void doesNotRetryANotFound() throws Exception {
        server.removeContext("/v1/market/rates");
        server.createContext("/v1/market/rates", exchange -> {
            hits.incrementAndGet();
            byte[] bytes = "nope".getBytes(StandardCharsets.UTF_8);
            exchange.sendResponseHeaders(404, bytes.length);
            try (OutputStream out = exchange.getResponseBody()) {
                out.write(bytes);
            }
        });
        RatesClient client = RatesClient.forTest(
                "http://127.0.0.1:" + server.getAddress().getPort() + "/",
                RatesClient.httpTransport(),
                Clock.systemUTC(),
                millis -> {
                    throw new AssertionError("404 must not be retried");
                });

        PriceIndexException error = assertThrows(PriceIndexException.class, () -> client.priceIndex("berlin", "flex_desk"));

        assertEquals("HTTP 404", error.getMessage());
        assertEquals(1, hits.get());
    }

    private static String resource() {
        try (var in = RatesClientHttpTest.class.getResourceAsStream("/berlin-rates.json")) {
            return new String(in.readAllBytes(), StandardCharsets.UTF_8);
        } catch (IOException ex) {
            throw new IllegalStateException(ex);
        }
    }
}
