package io.github.coworkingview;

import com.sun.net.httpserver.HttpServer;
import java.io.IOException;
import java.net.InetSocketAddress;
import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentLinkedQueue;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** Local HTTP server. Tests never call api.coworkingview.com. */
final class FakeApi implements AutoCloseable {
    final String url;
    final List<Seen> requests = Collections.synchronizedList(new ArrayList<Seen>());
    final List<Long> sleeps = Collections.synchronizedList(new ArrayList<Long>());
    volatile Responder responder;

    private final HttpServer server;
    private final ExecutorService executor;
    private final ConcurrentLinkedQueue<Reply> queue = new ConcurrentLinkedQueue<Reply>();

    FakeApi() throws IOException {
        server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        executor = Executors.newCachedThreadPool(runnable -> {
            Thread thread = new Thread(runnable, "cwv-fake-api");
            thread.setDaemon(true);
            return thread;
        });
        server.setExecutor(executor);
        server.createContext("/", exchange -> {
            try {
                Seen seen = Seen.from(exchange.getRequestURI().getPath(), exchange.getRequestURI().getRawQuery(), headers(exchange));
                requests.add(seen);
                Reply reply = responder == null ? queue.poll() : responder.respond(seen);
                if (reply == null) {
                    reply = new Reply(500, "no reply queued", Collections.<String, String>emptyMap());
                }
                byte[] bytes = reply.body.getBytes(StandardCharsets.UTF_8);
                for (Map.Entry<String, String> header : reply.headers.entrySet()) {
                    exchange.getResponseHeaders().add(header.getKey(), header.getValue());
                }
                exchange.getResponseHeaders().set("Content-Type", "application/json; charset=utf-8");
                exchange.sendResponseHeaders(reply.status, bytes.length);
                exchange.getResponseBody().write(bytes);
            } finally {
                exchange.close();
            }
        });
        server.start();
        url = "http://127.0.0.1:" + server.getAddress().getPort();
    }

    Client client() {
        return Client.builder()
                .baseUrl(url)
                .environment(name -> null)
                .sleeper(millis -> sleeps.add(millis))
                .build();
    }

    void queue(Reply reply) {
        queue.add(reply);
    }

    @Override
    public void close() {
        server.stop(0);
        executor.shutdownNow();
    }

    private static Map<String, String> headers(com.sun.net.httpserver.HttpExchange exchange) {
        Map<String, String> headers = new LinkedHashMap<String, String>();
        exchange.getRequestHeaders().forEach((name, values) -> {
            if (!values.isEmpty()) {
                headers.put(name.toLowerCase(java.util.Locale.ROOT), values.get(0));
            }
        });
        return headers;
    }

    interface Responder {
        Reply respond(Seen seen);
    }

    static final class Seen {
        final String path;
        final Map<String, String> query;
        final Map<String, String> headers;

        private Seen(String path, Map<String, String> query, Map<String, String> headers) {
            this.path = path;
            this.query = query;
            this.headers = headers;
        }

        static Seen from(String path, String rawQuery, Map<String, String> headers) {
            Map<String, String> query = new LinkedHashMap<String, String>();
            if (rawQuery != null && !rawQuery.isEmpty()) {
                for (String part : rawQuery.split("&")) {
                    int eq = part.indexOf('=');
                    String key = eq < 0 ? part : part.substring(0, eq);
                    String value = eq < 0 ? "" : part.substring(eq + 1);
                    query.put(
                            URLDecoder.decode(key, StandardCharsets.UTF_8),
                            URLDecoder.decode(value, StandardCharsets.UTF_8));
                }
            }
            return new Seen(path, query, headers);
        }
    }

    static final class Reply {
        final int status;
        final String body;
        final Map<String, String> headers;

        Reply(int status, String body, Map<String, String> headers) {
            this.status = status;
            this.body = body;
            this.headers = headers;
        }

        static Reply json(String body) {
            return new Reply(200, body, Collections.<String, String>emptyMap());
        }

        static Reply status(int status, String body, String headerName, String headerValue) {
            Map<String, String> headers = new LinkedHashMap<String, String>();
            if (headerName != null) {
                headers.put(headerName, headerValue);
            }
            return new Reply(status, body, headers);
        }
    }
}
