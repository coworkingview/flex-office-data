// Copyright (c) 2026 CoworkingView. License: MIT.
module coworkingview.client;

import std.algorithm.comparison : min;
import std.conv : to;
import std.json : JSONValue;
import std.process : environment;
import std.string : strip;
import std.typecons : Nullable;

import coworkingview.check : checkCount, checkCurrency, checkLimit, checkLocale, checkPrice,
    checkPriceRange, checkProduct, checkSlug, checkSort, checkText, checkTimeout;
import coworkingview.error : APIException, CoworkingViewException, ShapeException;
import coworkingview.http : CurlTransport, HTTPResult, Sleeper, ThreadSleeper, Transport,
    buildURL, isRetryable, parseSuccessBody, problemOf, retryWait;
import coworkingview.jsonutil : decimalText;
import coworkingview.model : City, Dataset, Listing, Rate, Space;
import coworkingview.parse : parseCities, parseListings, parseRates, parseSpace;

/**
Client for the public CoworkingView API (https://coworkingview.com).

The API needs no key. Creating a client does not touch the network. On HTTP
429 or 5xx the client waits `Retry-After` seconds, else `RateLimit-Reset`,
else 2 seconds, and never more than 10 seconds, then retries once.

Price Index figures are CC BY 4.0. Keep `Dataset.attribution` next to anything
you republish. Catalogue names and prices are for search and reference.
Descriptions, photos and logos are not returned.
*/
class Client
{
    /// Production API root.
    enum defaultBaseURL = "https://api.coworkingview.com";
    /// Environment variable that overrides `defaultBaseURL`.
    enum baseURLEnvironment = "COWORKINGVIEW_API_URL";
    /// Version sent in the default `User-Agent`. The registry tag is `v0.1.0`.
    enum libraryVersion = "0.1.0";
    /// Most rows `spaces` will return.
    enum maxSpaces = 200;
    /// Default `User-Agent`.
    enum defaultUserAgent = "coworkingview-d/" ~ libraryVersion
        ~ " (+https://github.com/coworkingview/flex-office-data)";

    /// API root, without a trailing slash.
    string baseURL;
    /// Per-request timeout in seconds.
    double timeoutSeconds;
    /// `User-Agent` sent with every request.
    string userAgent;
    /// Locale used when a call does not set one. `en`, `es` or `de`.
    string locale;

    private Transport transport;
    private Sleeper sleeper;

    /**
    A client for `defaultBaseURL`, or for `COWORKINGVIEW_API_URL` when that variable is set.

    Params:
        baseURL = API root. A trailing slash is removed. `null` uses the environment
            variable, then `defaultBaseURL`.
        timeoutSeconds = Seconds to wait for each response. The default is 20.
        userAgent = `User-Agent` header. `null` or blank sends `defaultUserAgent`.
        locale = Default locale for calls that do not set one.
    */
    this(string baseURL = null, double timeoutSeconds = 20, string userAgent = null, string locale = "en")
    {
        this(baseURL, timeoutSeconds, userAgent, locale, null, null, true, null);
    }

    private this(string baseURL, double timeoutSeconds, string userAgent, string locale,
        Transport transport, Sleeper sleeper, bool readProcessEnvironment, string[string] env)
    {
        this.timeoutSeconds = checkTimeout(timeoutSeconds);
        this.locale = checkLocale(locale);
        this.baseURL = resolveBase(baseURL, readProcessEnvironment, env);
        auto agent = userAgent is null ? "" : userAgent.strip;
        this.userAgent = agent.length ? agent : defaultUserAgent;
        this.transport = transport is null ? new CurlTransport() : transport;
        this.sleeper = sleeper is null ? new ThreadSleeper() : sleeper;
    }

    /**
    Price Index figures, one row per published city and product.

    `GET /v1/market/rates`. Rows are ordered by city slug, then by product.
    Cities in `unpublished` produce no rows. A product the API adds later is kept.
    */
    Dataset!(Rate[]) rates(string city = null, string country = null,
        string currency = null, string locale = null)
    {
        auto query = ratesQuery(city, country, currency, locale);
        auto fetched = fetch("/v1/market/rates", query);
        try
            return parseRates(fetched.value);
        catch (ShapeException e)
            throw badShape(e, fetched.status, "/v1/market/rates");
    }

    /// Cities of the Price Index, published cities first. Same request as `rates`.
    Dataset!(City[]) cities(string city = null, string country = null,
        string currency = null, string locale = null)
    {
        auto query = ratesQuery(city, country, currency, locale);
        auto fetched = fetch("/v1/market/rates", query);
        try
            return parseCities(fetched.value);
        catch (ShapeException e)
            throw badShape(e, fetched.status, "/v1/market/rates");
    }

    /**
    Searches the catalogue. One row per space, at most `maxSpaces`.

    `GET /v1/properties`. Pages are followed until `limit` rows or the last page.
    Page size is `min(50, limit)`. With `sort` `random`, the seed of the first
    page is sent again on the following pages.

    `operatorSlug` is sent as the query parameter `operator`. `product` is sent
    as `pricingOptionType`. `sort` is sent as `sortBy`.
    */
    Dataset!(Listing[]) spaces(string city = null, string country = null, string zone = null,
        string operatorSlug = null, string product = null,
        Nullable!long minCapacity = Nullable!long.init,
        Nullable!double minPrice = Nullable!double.init,
        Nullable!double maxPrice = Nullable!double.init, string currency = null,
        string sort = "random", int limit = 50, string locale = null, string seed = null)
    {
        auto requestLocale = checkLocale(locale is null ? this.locale : locale);
        auto requestSort = checkSort(sort);
        auto requestLimit = checkLimit(limit);
        auto low = checkPrice("min_price", minPrice);
        auto high = checkPrice("max_price", maxPrice);
        checkPriceRange(low, high);
        auto pageSize = min(50, requestLimit);

        string[2][] query;
        addQuery(query, "locale", requestLocale);
        addQuery(query, "city", checkText("city", city));
        addQuery(query, "country", checkText("country", country));
        addQuery(query, "zone", checkText("zone", zone));
        addQuery(query, "operator", checkText("operator", operatorSlug));
        addQuery(query, "pricingOptionType", checkProduct(product));
        auto capacity = checkCount("min_capacity", minCapacity);
        if (!capacity.isNull)
            addQuery(query, "minCapacity", to!string(capacity.get));
        if (!low.isNull)
            addQuery(query, "minPrice", decimalText(low.get));
        if (!high.isNull)
            addQuery(query, "maxPrice", decimalText(high.get));
        addQuery(query, "currency", checkCurrency(currency));
        addQuery(query, "sortBy", requestSort);

        string userSeed;
        if (seed !is null)
        {
            auto trimmed = seed.strip;
            if (trimmed.length)
                userSeed = trimmed;
        }
        string activeSeed = userSeed;
        Listing[] rows;
        string attribution, notice;
        Nullable!long total;
        auto page = 1;
        enum path = "/v1/properties";
        while (true)
        {
            auto pageQuery = query.dup;
            addQuery(pageQuery, "page", to!string(page));
            addQuery(pageQuery, "pageSize", to!string(pageSize));
            addQuery(pageQuery, "seed", activeSeed);
            auto fetched = fetch(path, pageQuery);
            string pageAttribution, pageNotice, pageSeed;
            Nullable!long pageCount, pageTotal;
            Listing[] parsed;
            try
            {
                parsed = parseListings(fetched.value, requestLocale, pageAttribution, pageNotice,
                    pageSeed, pageCount, pageTotal);
            }
            catch (ShapeException e)
                throw badShape(e, fetched.status, path);
            if (page == 1)
            {
                attribution = pageAttribution;
                notice = pageNotice;
                total = pageTotal;
                if (requestSort == "random" && userSeed is null && pageSeed !is null)
                    activeSeed = pageSeed;
            }
            rows ~= parsed;
            auto last = pageCount.isNull || page >= pageCount.get;
            if (rows.length >= requestLimit || parsed.length == 0 || last)
                break;
            page++;
        }
        if (rows.length > requestLimit)
            rows = rows[0 .. requestLimit];
        return Dataset!(Listing[])(rows, attribution, null, null, notice, total);
    }

    /**
    One space and its pricing table.

    `GET /v1/properties/{slug}`. The slug is checked before it is put in the path.
    */
    Dataset!Space space(string slug, string locale = null)
    {
        auto requestLocale = checkLocale(locale is null ? this.locale : locale);
        auto checked = checkSlug(slug);
        auto path = "/v1/properties/" ~ checked;
        string[2][] query;
        addQuery(query, "locale", requestLocale);
        auto fetched = fetch(path, query);
        try
        {
            auto parsed = parseSpace(fetched.value, requestLocale);
            return Dataset!Space(parsed, parsed.attribution, null, null, parsed.notice);
        }
        catch (ShapeException e)
            throw badShape(e, fetched.status, path);
    }

    override string toString()
    {
        return "Client(baseURL: " ~ baseURL ~ ", timeout: " ~ to!string(timeoutSeconds) ~ ")";
    }

    private string[2][] ratesQuery(string city, string country, string currency, string locale)
    {
        string[2][] query;
        addQuery(query, "locale", checkLocale(locale is null ? this.locale : locale));
        addQuery(query, "city", checkText("city", city));
        addQuery(query, "country", checkText("country", country));
        addQuery(query, "currency", checkCurrency(currency));
        return query;
    }

    private static struct Fetched
    {
        int status;
        JSONValue value;
    }

    private Fetched fetch(string path, string[2][] query)
    {
        auto url = buildURL(baseURL, path, query);
        string[string] headers;
        headers["Accept"] = "application/json";
        headers["User-Agent"] = userAgent;
        auto attempt = 0;
        while (true)
        {
            attempt++;
            HTTPResult response;
            try
                response = transport.get(url, headers, timeoutSeconds);
            catch (CoworkingViewException e)
                throw e;
            catch (Exception e)
            {
                throw new CoworkingViewException(
                    "Could not reach " ~ baseURL ~ ": " ~ e.msg);
            }
            if (response.status >= 200 && response.status < 300)
                return Fetched(response.status, parseSuccessBody(response, path));
            if (attempt == 1 && isRetryable(response.status))
            {
                sleeper.sleepSeconds(retryWait(response.headers));
                continue;
            }
            throw problemOf(response);
        }
    }
}

private void addQuery(ref string[2][] query, string name, string value)
{
    if (value !is null)
        query ~= [name, value];
}

private string resolveBase(string explicitBase, bool readProcessEnvironment, string[string] env)
{
    string resolved;
    if (explicitBase !is null)
        resolved = explicitBase.strip;
    else
    {
        string fromEnv;
        if (readProcessEnvironment)
            fromEnv = environment.get(Client.baseURLEnvironment, "").strip;
        else if (auto found = Client.baseURLEnvironment in env)
            fromEnv = (*found).strip;
        resolved = fromEnv.length ? fromEnv : Client.defaultBaseURL;
    }
    while (resolved.length && resolved[$ - 1] == '/')
        resolved = resolved[0 .. $ - 1];
    validateBase(resolved);
    return resolved;
}

private void validateBase(string url)
{
    import std.string : indexOf, startsWith, toLower;

    auto lower = url.toLower;
    auto https = lower.startsWith("https://");
    auto http = lower.startsWith("http://");
    if (!https && !http)
        throw badBase(url);
    auto rest = url[(https ? "https://" : "http://").length .. $];
    auto slash = rest.indexOf('/');
    auto host = slash < 0 ? rest : rest[0 .. slash];
    if (host.length == 0 || host[0] == '.' || host.indexOf(' ') >= 0 || host.indexOf('@') == 0)
        throw badBase(url);
}

private CoworkingViewException badBase(string url)
{
    return new CoworkingViewException(
        "base URL is not a valid http(s) URL, got '" ~ url ~ "'.");
}

private APIException badShape(ShapeException e, int status, string path)
{
    return new APIException(status, "BAD_RESPONSE", e.msg, "GET " ~ path);
}

version (unittest)
{
    import std.algorithm.searching : canFind;
    import std.conv : to;
    import std.string : indexOf, split;
    import std.uri : decodeComponent;

    import coworkingview.http : FakeTransport, RecordingSleeper, httpResult;

    private string[string] queryMap(string url)
    {
        string[string] result;
        auto q = url.indexOf('?');
        if (q < 0)
            return result;
        foreach (part; url[q + 1 .. $].split('&'))
        {
            auto eq = part.indexOf('=');
            if (eq < 0)
                continue;
            result[decodeComponent(part[0 .. eq])] = decodeComponent(part[eq + 1 .. $]);
        }
        return result;
    }

    private string pathOf(string url)
    {
        auto q = url.indexOf('?');
        auto bare = q < 0 ? url : url[0 .. q];
        auto scheme = bare.indexOf("://");
        auto rest = bare[scheme + 3 .. $];
        auto slash = rest.indexOf('/');
        return slash < 0 ? "/" : rest[slash .. $];
    }

    private Client scripted(Transport transport, Sleeper sleeper = null)
    {
        if (sleeper is null)
            sleeper = new RecordingSleeper();
        string[string] env;
        return new Client(null, 20, null, "en", transport, sleeper, false, env);
    }

    private HTTPResult pages(string url, int total, int seedBase = 42)
    {
        auto query = queryMap(url);
        auto page = "page" in query ? to!int(query["page"]) : 1;
        auto size = "pageSize" in query ? to!int(query["pageSize"]) : 50;
        auto start = (page - 1) * size;
        auto end = start + size;
        if (end > total)
            end = total;
        if (start > total)
            start = total;
        if (start < 0)
            start = 0;
        string cards;
        foreach (i; start .. end)
        {
            if (cards.length)
                cards ~= ",";
            cards ~= `{"slug":"space-` ~ to!string(i) ~ `","title":"Space ` ~ to!string(i)
                ~ `","city":{"slug":"berlin"}}`;
        }
        auto pageCount = size == 0 ? 0 : (total + size - 1) / size;
        auto body = `{"data":[` ~ cards ~ `],"meta":{"pagination":{"page":` ~ to!string(page)
            ~ `,"pageSize":` ~ to!string(size) ~ `,"total":` ~ to!string(total) ~ `,"pageCount":`
            ~ to!string(pageCount) ~ `},"seed":` ~ to!string(seedBase + page)
            ~ `,"citation":{"text":"citation page ` ~ to!string(page)
            ~ `"},"catalogueNotice":"notice"}}`;
        return httpResult(200, body);
    }

    private void expect(Client client, string fragment, void delegate() call)
    {
        bool threw;
        try
            call();
        catch (APIException e)
            assert(false, "not an API error: " ~ e.msg);
        catch (CoworkingViewException e)
        {
            threw = true;
            assert(e.msg.canFind(fragment), e.msg);
        }
        assert(threw, "expected " ~ fragment);
        assert(client !is null);
    }

    unittest
    {
        auto transport = new FakeTransport();
        auto client = scripted(transport);
        assert(transport.urls.length == 0);
        assert(client.baseURL == Client.defaultBaseURL);
        assert(client.toString.canFind("https://api.coworkingview.com"));

        string[string] env;
        env[Client.baseURLEnvironment] = "http://env.invalid";
        auto explicit = new Client("http://arg.invalid", 5, null, "en",
            new FakeTransport(), new RecordingSleeper(), false, env);
        assert(explicit.baseURL == "http://arg.invalid");
        env[Client.baseURLEnvironment] = "http://env.example/";
        auto fromEnv = new Client(null, 20, "  ", "de", new FakeTransport(),
            new RecordingSleeper(), false, env);
        assert(fromEnv.baseURL == "http://env.example");
        assert(fromEnv.userAgent == Client.defaultUserAgent);
        assert(fromEnv.locale == "de");

        bool rejected;
        try
            new Client("ftp://example.com", 20, null, "en", new FakeTransport(),
                new RecordingSleeper(), false, null);
        catch (CoworkingViewException e)
        {
            rejected = e.msg.canFind("not a valid http(s) URL");
        }
        assert(rejected);
        rejected = false;
        try
            new Client(null, 0, null, "en", new FakeTransport(), new RecordingSleeper(), false, null);
        catch (CoworkingViewException e)
        {
            rejected = e.msg.canFind("timeout must be a positive number");
        }
        assert(rejected);
    }

    unittest
    {
        enum ratesOK = `{"data":{"cities":[],"asOf":"2026-10-27T21:06:48.313Z"},"meta":{}}`;
        auto transport = new FakeTransport();
        transport.queued = [httpResult(200, ratesOK)];
        auto client = scripted(transport);
        auto dataset = client.rates();
        assert(dataset.data.length == 0);
        assert(Client.libraryVersion == "0.1.0");
        assert(Client.defaultUserAgent
            == "coworkingview-d/0.1.0 (+https://github.com/coworkingview/flex-office-data)");
        assert(transport.headerLog[0]["User-Agent"] == Client.defaultUserAgent);
        assert(transport.headerLog[0]["Accept"] == "application/json");
        assert(pathOf(transport.urls[0]) == "/v1/market/rates");
        assert(queryMap(transport.urls[0])["locale"] == "en");

        transport = new FakeTransport();
        transport.queued = [httpResult(200, ratesOK)];
        client = new Client(null, 20, "my-app/1.0", "en", transport, new RecordingSleeper(), false, null);
        client.rates();
        assert(transport.headerLog[0]["User-Agent"] == "my-app/1.0");

        transport = new FakeTransport();
        transport.queued = [httpResult(200, ratesOK)];
        scripted(transport).rates(city: "berlin", country: "DE", currency: "eur", locale: "de");
        auto query = queryMap(transport.urls[0]);
        assert(query["locale"] == "de");
        assert(query["city"] == "berlin");
        assert(query["country"] == "DE");
        assert(query["currency"] == "EUR");

        transport = new FakeTransport();
        transport.queued = [httpResult(200, ratesOK)];
        scripted(transport).rates(currency: "VES");
        assert(queryMap(transport.urls[0])["currency"] == "VES");
    }

    unittest
    {
        enum ratesOK = `{"data":{"cities":[]}}`;
        foreach (status; [429, 500, 502, 503])
        {
            auto transport = new FakeTransport();
            auto sleeper = new RecordingSleeper();
            transport.queued = [
                httpResult(status, `{"title":"busy"}`),
                httpResult(200, ratesOK),
            ];
            auto dataset = scripted(transport, sleeper).rates();
            assert(dataset.data.length == 0);
            assert(transport.urls.length == 2);
            assert(sleeper.delays == [2.0]);
        }

        auto transport = new FakeTransport();
        auto sleeper = new RecordingSleeper();
        transport.queued = [
            httpResult(503, `{"title":"Down","code":"UNAVAILABLE"}`),
            httpResult(503, `{"title":"Still down","code":"UNAVAILABLE"}`),
            httpResult(200, ratesOK),
        ];
        bool failed;
        try
            scripted(transport, sleeper).rates();
        catch (APIException e)
        {
            failed = true;
            assert(transport.urls.length == 2);
            assert(e.status == 503);
            assert(e.title == "Still down");
            assert(sleeper.delays.length == 1);
            assert(e.msg == "503 UNAVAILABLE: Still down");
        }
        assert(failed);

        transport = new FakeTransport();
        sleeper = new RecordingSleeper();
        string[string] retryAfter;
        retryAfter["Retry-After"] = "3";
        string[string] capped;
        capped["Retry-After"] = "120";
        capped["RateLimit-Reset"] = "5";
        string[string] resetOnly;
        resetOnly["RateLimit-Reset"] = "4";
        transport.queued = [
            httpResult(429, "{}", retryAfter),
            httpResult(200, ratesOK),
            httpResult(429, "{}", capped),
            httpResult(200, ratesOK),
            httpResult(429, "{}", resetOnly),
            httpResult(200, ratesOK),
        ];
        auto client = scripted(transport, sleeper);
        client.rates();
        client.rates();
        client.rates();
        assert(sleeper.delays == [3.0, 10.0, 4.0]);
    }

    unittest
    {
        auto transport = new FakeTransport();
        transport.queued = [
            httpResult(404, `{"type":"https://coworkingview.com/problems/not-found","title":"Not found","status":404,"code":"NOT_FOUND","detail":"No property with slug 'nope'."}`),
        ];
        bool failed;
        try
            scripted(transport).space("nope");
        catch (APIException e)
        {
            failed = true;
            assert(e.status == 404);
            assert(e.code == "NOT_FOUND");
            assert(e.title == "Not found");
            assert(e.detail == "No property with slug 'nope'.");
            assert(e.errors.length == 0);
            assert(e.msg.canFind("404 NOT_FOUND: Not found"));
        }
        assert(failed);

        transport = new FakeTransport();
        transport.queued = [httpResult(400, import("error_validation.json"))];
        failed = false;
        try
            scripted(transport).rates(currency: "VES");
        catch (APIException e)
        {
            failed = true;
            assert(e.status == 400);
            assert(e.code == "VALIDATION_FAILED");
            assert(e.errors.length == 1);
            assert(e.errors[0].path == "currency");
        }
        assert(failed);

        transport = new FakeTransport();
        transport.queued = [httpResult(403, "<html>Forbidden</html>")];
        failed = false;
        try
            scripted(transport).rates();
        catch (APIException e)
        {
            failed = true;
            assert(e.status == 403);
            assert(e.code == "HTTP_403");
            assert(e.title == "Forbidden");
            assert(e.detail is null);
        }
        assert(failed);

        transport = new FakeTransport();
        transport.queued = [httpResult(200, "<html>maintenance</html>")];
        failed = false;
        try
            scripted(transport).rates();
        catch (APIException e)
        {
            failed = true;
            assert(e.code == "BAD_RESPONSE");
            assert(e.status == 200);
        }
        assert(failed);

        transport = new FakeTransport();
        transport.queued = [httpResult(200, "[1,2,3]")];
        failed = false;
        try
            scripted(transport).rates();
        catch (APIException e)
        {
            failed = true;
            assert(e.code == "BAD_RESPONSE");
            assert(e.title == "The API returned JSON that is not an object");
        }
        assert(failed);

        foreach (pair; [["{\"meta\":{}}", "rates"], ["{\"data\":[]}", "rates"],
                ["{\"data\":{}}", "spaces"], ["{\"data\":[]}", "space"]])
        {
            transport = new FakeTransport();
            transport.queued = [httpResult(200, pair[0])];
            auto call = scripted(transport);
            failed = false;
            try
            {
                if (pair[1] == "spaces")
                    call.spaces();
                else if (pair[1] == "space")
                    call.space("x");
                else
                    call.rates();
            }
            catch (APIException e)
            {
                failed = e.code == "BAD_RESPONSE";
            }
            assert(failed);
        }

        transport = new FakeTransport();
        transport.failure = new Exception("connection refused");
        failed = false;
        try
            scripted(transport).rates();
        catch (APIException e)
            assert(false, e.msg);
        catch (CoworkingViewException e)
        {
            failed = true;
            assert(e.msg.canFind("Could not reach"));
            assert(e.msg.canFind("connection refused"));
        }
        assert(failed);
    }

    unittest
    {
        auto transport = new FakeTransport();
        transport.responder = (string url, string[string] headers) => pages(url, 1);
        auto client = scripted(transport);
        client.spaces(city: "berlin", country: "DE", zone: "mitte", operatorSlug: "regus",
            product: "meeting_room", minCapacity: Nullable!long(8), minPrice: Nullable!double(10),
            maxPrice: Nullable!double(99.5), currency: "EUR", sort: "price-asc", limit: 10,
            locale: "es");
        auto query = queryMap(transport.urls[0]);
        assert(pathOf(transport.urls[0]) == "/v1/properties");
        assert(query["locale"] == "es");
        assert(query["city"] == "berlin");
        assert(query["country"] == "DE");
        assert(query["zone"] == "mitte");
        assert(query["operator"] == "regus");
        assert(query["pricingOptionType"] == "meeting_room");
        assert(query["minCapacity"] == "8");
        assert(query["minPrice"] == "10");
        assert(query["maxPrice"] == "99.5");
        assert(query["currency"] == "EUR");
        assert(query["sortBy"] == "price-asc");
        assert(query["page"] == "1");
        assert(query["pageSize"] == "10");

        transport = new FakeTransport();
        transport.responder = (string url, string[string] headers) => pages(url, 500);
        auto dataset = scripted(transport).spaces(limit: 120);
        string[] slugs;
        foreach (row; dataset.data)
            slugs ~= row.slug;
        string[] expectSlugs;
        foreach (i; 0 .. 120)
            expectSlugs ~= "space-" ~ to!string(i);
        assert(slugs == expectSlugs);
        string[] pagesSeen;
        foreach (url; transport.urls)
            pagesSeen ~= queryMap(url)["page"];
        assert(pagesSeen == ["1", "2", "3"]);
        foreach (url; transport.urls)
            assert(queryMap(url)["pageSize"] == "50");
        assert(("seed" in queryMap(transport.urls[0])) is null);
        assert(queryMap(transport.urls[1])["seed"] == "43");
        assert(queryMap(transport.urls[2])["seed"] == "43");
        assert(dataset.attribution == "citation page 1");
        assert(dataset.notice == "notice");
        assert(!dataset.total.isNull && dataset.total.get == 500);

        transport = new FakeTransport();
        transport.responder = (string url, string[string] headers) => pages(url, 80);
        dataset = scripted(transport).spaces(sort: "date-desc", limit: 200);
        assert(dataset.data.length == 80);
        assert(transport.urls.length == 2);
        assert(("seed" in queryMap(transport.urls[1])) is null);

        transport = new FakeTransport();
        transport.responder = (string url, string[string] headers) => pages(url, 30);
        dataset = scripted(transport).spaces(limit: 200);
        assert(dataset.data.length == 30);
        assert(transport.urls.length == 1);

        transport = new FakeTransport();
        transport.responder = (string url, string[string] headers) => pages(url, 500);
        dataset = scripted(transport).spaces(limit: 5);
        assert(dataset.data.length == 5);
        assert(transport.urls.length == 1);
        assert(queryMap(transport.urls[0])["pageSize"] == "5");

        transport = new FakeTransport();
        transport.responder = (string url, string[string] headers) => pages(url, 10_000);
        dataset = scripted(transport).spaces(limit: 200);
        assert(dataset.data.length == 200);
        assert(transport.urls.length == 4);

        transport = new FakeTransport();
        transport.queued = [httpResult(200, `{"data":[{"slug":"a","title":"A"}],"meta":{}}`)];
        dataset = scripted(transport).spaces();
        assert(dataset.data.length == 1);
        assert(dataset.attribution is null);
        assert(dataset.notice is null);
        assert(dataset.total.isNull);
        auto row = dataset.data[0];
        assert(row.citySlug is null);
        assert(row.zoneSlug is null);
        assert(row.operatorName is null);
        assert(row.lat.isNull);
        assert(row.featured.isNull);
        assert(row.marketVerdict is null);
        assert(row.updatedAt is null);
        assert(row.url == "https://coworkingview.com/en/workspace/a");
    }

    unittest
    {
        auto transport = new FakeTransport();
        auto client = scripted(transport);
        foreach (limit; [201, 1000])
        {
            bool failed;
            try
                client.spaces(limit: limit);
            catch (APIException e)
                assert(false, e.msg);
            catch (CoworkingViewException e)
            {
                failed = true;
                assert(e.msg.canFind("maximum of 200"));
                assert(e.msg.canFind("not bulk-copied"));
            }
            assert(failed);
        }
        assert(transport.urls.length == 0);

        expect(client, "locale='fr' is not supported", { client.spaces(locale: "fr"); });
        expect(client, "currency='JPY' is not supported", { client.spaces(currency: "JPY"); });
        expect(client, "product='desk' is not supported", { client.spaces(product: "desk"); });
        expect(client, "sort='price' is not supported", { client.spaces(sort: "price"); });
        expect(client, "limit must be a positive integer", { client.spaces(limit: 0); });
        expect(client, "min_capacity must be a non-negative integer", {
            client.spaces(minCapacity: Nullable!long(-1));
        });
        expect(client, "min_price must be a non-negative number", {
            client.spaces(minPrice: Nullable!double(-1));
        });
        expect(client, "min_price (100) is greater than max_price (50)", {
            client.spaces(minPrice: Nullable!double(100), maxPrice: Nullable!double(50));
        });
        expect(client, "city must be a non-empty string", { client.spaces(city: "  "); });
        expect(client, "locale='EN' is not supported", { client.rates(locale: "EN"); });
        expect(client, "currency='BTC' is not supported", { client.rates(currency: "BTC"); });
        expect(client, "country must be a non-empty string", { client.rates(country: "  "); });

        bool failed;
        try
            client.space("../etc");
        catch (CoworkingViewException e)
        {
            failed = e.msg.canFind("not a valid slug");
        }
        assert(failed);
        assert(transport.urls.length == 0);

        transport.queued = [httpResult(200, import("market_rates.json"))];
        auto berlin = client.rates(city: "berlin");
        assert(berlin.data.length > 0);
        assert(berlin.attribution.canFind("CoworkingView Price Index"));
        assert(queryMap(transport.urls[0])["city"] == "berlin");
        assert(queryMap(transport.urls[0])["locale"] == "en");
    }
}
