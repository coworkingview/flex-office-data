// Copyright (c) 2026 CoworkingView. License: MIT.
module coworkingview.parse;

import std.algorithm.sorting : sort;
import std.json : JSONType, JSONValue;
import std.typecons : Nullable;

import coworkingview.check : products;
import coworkingview.error : ShapeException;
import coworkingview.jsonutil : amount, asDouble, field, isStat, optionalString, readBool,
    readLong, readNumber, readSeed, requireMember;
import coworkingview.model : City, Dataset, Listing, PricingOption, Rate, Space;

package string snake(string key)
{
    char[] result;
    foreach (i, c; key)
    {
        if (c >= 'A' && c <= 'Z')
        {
            if (i > 0)
                result ~= '_';
            result ~= cast(char) (c + 32);
        }
        else
            result ~= c;
    }
    return result.idup;
}

package string unitFor(string product)
{
    switch (product)
    {
    case "day_pass":
        return "day";
    case "meeting_room":
    case "event_space":
        return "hour";
    case "virtual_office":
        return "month";
    default:
        return null;
    }
}

package string listingURL(string slug, string locale)
{
    string section = "workspace";
    if (locale == "es")
        section = "oficina";
    else if (locale == "de")
        section = "buero";
    return "https://coworkingview.com/" ~ locale ~ "/" ~ section ~ "/" ~ slug;
}

package Dataset!(Rate[]) parseRates(JSONValue envelope)
{
    auto data = ratesData(envelope);
    return Dataset!(Rate[])(rateRows(data), optionalString(field(data, "attribution")),
        optionalString(field(data, "licenseUrl")), optionalString(field(data, "asOf")));
}

package Dataset!(City[]) parseCities(JSONValue envelope)
{
    auto data = ratesData(envelope);
    return Dataset!(City[])(cityRows(data), optionalString(field(data, "attribution")),
        optionalString(field(data, "licenseUrl")), optionalString(field(data, "asOf")));
}

package Listing[] parseListings(JSONValue envelope, string locale, out string attribution,
    out string notice, out string seed, out Nullable!long pageCount, out Nullable!long total)
{
    auto data = requireMember(envelope, "data");
    if (data.type != JSONType.array)
        throw new ShapeException("Unexpected shape for properties");
    catalogueMeta(envelope, attribution, notice, seed, pageCount, total);
    Listing[] rows;
    foreach (card; data.array)
    {
        if (card.type != JSONType.object)
            continue;
        rows ~= parseListing(card, locale);
    }
    return rows;
}

package Space parseSpace(JSONValue envelope, string locale)
{
    auto detail = requireMember(envelope, "data");
    if (detail.type != JSONType.object)
        throw new ShapeException("Unexpected shape for a property");
    string attribution, notice, seed;
    Nullable!long pageCount, total;
    catalogueMeta(envelope, attribution, notice, seed, pageCount, total);
    auto space = parseListing(detail, locale, "Unexpected shape for a property");
    auto web = optionalString(field(detail, "webUrl"));
    if (web.length)
        space.url = web;

    string[] amenities;
    auto rawAmenities = field(detail, "amenities");
    if (rawAmenities.type == JSONType.array)
    {
        foreach (item; rawAmenities.array)
        {
            if (item.type == JSONType.string)
                amenities ~= item.str;
            else if (item.type == JSONType.true_)
                amenities ~= "true";
            else if (item.type == JSONType.false_)
                amenities ~= "false";
            else if (item.type == JSONType.integer || item.type == JSONType.uinteger
                || item.type == JSONType.float_)
                amenities ~= readNumber(item).text;
        }
    }

    PricingOption[] pricing;
    auto rawPricing = field(detail, "pricingOptions");
    if (rawPricing.type == JSONType.array)
    {
        foreach (item; rawPricing.array)
        {
            if (item.type != JSONType.object)
                throw new ShapeException("Unexpected shape for a property");
            auto priceValue = field(item, "price");
            auto price = amount(priceValue);
            string currency;
            if (price.present)
                currency = optionalString(field(priceValue, "currency"));
            auto onRequest = readBool(field(item, "priceOnRequest"));
            if (onRequest.isNull)
                throw new ShapeException("Unexpected shape for a property");
            pricing ~= PricingOption(requiredString(item, "optionType"),
                requiredString(item, "title"), asDouble(price), price.present ? price.text : null,
                currency, requiredString(item, "billingPeriod"), onRequest.get,
                readLong(field(item, "minCapacity")), readLong(field(item, "maxCapacity")));
        }
    }

    return Space(space.slug, space.title, space.citySlug, space.zoneSlug, space.operatorSlug,
        space.operatorName, space.countryCode, space.lat, space.latText, space.lng, space.lngText,
        space.featured, space.marketVerdict, space.marketMedian, space.marketMedianText,
        space.marketSampleSize, space.url, space.updatedAt, optionalString(field(detail, "address")),
        readLong(field(detail, "capacity")), amenities, pricing, attribution, notice);
}

private JSONValue ratesData(JSONValue envelope)
{
    auto data = requireMember(envelope, "data");
    if (data.type != JSONType.object)
        throw new ShapeException("Unexpected shape for market rates");
    return data;
}

private Rate[] rateRows(JSONValue data)
{
    auto asOf = optionalString(field(data, "asOf"));
    Rate[] rows;
    auto cities = field(data, "cities");
    if (cities.type == JSONType.array)
    {
        foreach (city; cities.array)
        {
            if (city.type != JSONType.object)
                throw new ShapeException("Unexpected shape for market rates");
            auto slug = placeField(field(city, "city"), "slug");
            auto name = placeField(field(city, "city"), "name");
            auto currency = optionalString(field(city, "currency"));
            if (slug is null || name is null || currency is null)
                throw new ShapeException("Unexpected shape for market rates");
            auto country = optionalString(field(city, "countryCode"));
            foreach (item; series(city))
            {
                if (item.type != JSONType.object)
                    throw new ShapeException("Unexpected shape for market rates");
                rows ~= makeRate(slug, name, country, currency,
                    requiredString(item, "optionType", "Unexpected shape for market rates"),
                    "month", item, asOf);
            }
            foreach (key, value; city.object)
            {
                if (!isStat(value))
                    continue;
                auto product = snake(key);
                rows ~= makeRate(slug, name, country, currency, product, unitFor(product), value, asOf);
            }
        }
    }
    rows.sort!((a, b) {
        if (a.citySlug != b.citySlug)
            return a.citySlug < b.citySlug;
        auto left = productRank(a.product);
        auto right = productRank(b.product);
        if (left != right)
            return left < right;
        return a.product < b.product;
    });
    return rows;
}

private City[] cityRows(JSONValue data)
{
    auto asOf = optionalString(field(data, "asOf"));
    City[] rows;
    auto cities = field(data, "cities");
    if (cities.type == JSONType.array)
    {
        foreach (city; cities.array)
        {
            if (city.type != JSONType.object)
                throw new ShapeException("Unexpected shape for market rates");
            auto slug = placeField(field(city, "city"), "slug");
            auto name = placeField(field(city, "city"), "name");
            auto currency = optionalString(field(city, "currency"));
            if (slug is null || name is null || currency is null)
                throw new ShapeException("Unexpected shape for market rates");
            auto entryMedian = amount(field(city, "entryMedian"));
            auto entryMin = amount(field(city, "entryMin"));
            auto entryMax = amount(field(city, "entryMax"));
            auto p25 = amount(field(city, "p25"));
            auto p75 = amount(field(city, "p75"));
            rows ~= City(slug, name, optionalString(field(city, "countryCode")), currency, true,
                readLong(field(city, "propertyCount")), readLong(field(city, "operatorCount")),
                asDouble(entryMedian), entryMedian.present ? entryMedian.text : null,
                asDouble(entryMin), entryMin.present ? entryMin.text : null,
                asDouble(entryMax), entryMax.present ? entryMax.text : null,
                asDouble(p25), p25.present ? p25.text : null,
                asDouble(p75), p75.present ? p75.text : null,
                readLong(field(city, "sampleSize")), asOf);
        }
    }
    auto unpublished = field(data, "unpublished");
    if (unpublished.type == JSONType.array)
    {
        foreach (city; unpublished.array)
        {
            if (city.type != JSONType.object)
                throw new ShapeException("Unexpected shape for market rates");
            auto slug = placeField(field(city, "city"), "slug");
            auto name = placeField(field(city, "city"), "name");
            if (slug is null || name is null)
                throw new ShapeException("Unexpected shape for market rates");
            rows ~= City(slug, name, optionalString(field(city, "countryCode")),
                optionalString(field(city, "currency")), false, Nullable!long.init,
                Nullable!long.init, Nullable!double.init, null, Nullable!double.init, null,
                Nullable!double.init, null, Nullable!double.init, null, Nullable!double.init, null,
                Nullable!long.init, asOf);
        }
    }
    rows.sort!((a, b) {
        if (a.published != b.published)
            return a.published && !b.published;
        return a.citySlug < b.citySlug;
    });
    return rows;
}

private Listing parseListing(JSONValue card, string locale,
    string message = "Unexpected shape for properties")
{
    auto slug = requiredString(card, "slug", message);
    auto title = requiredString(card, "title", message);
    auto market = field(card, "marketPosition");
    string verdict;
    auto median = amount(JSONValue.init);
    Nullable!long sample;
    if (market.type == JSONType.object)
    {
        verdict = optionalString(field(market, "verdict"));
        median = amount(field(market, "median"));
        sample = readLong(field(market, "sampleSize"));
    }
    auto coordinates = field(card, "coordinates");
    auto lat = readNumber(JSONValue.init);
    auto lng = readNumber(JSONValue.init);
    if (coordinates.type == JSONType.object)
    {
        lat = readNumber(field(coordinates, "lat"));
        lng = readNumber(field(coordinates, "lng"));
    }
    return Listing(slug, title, placeField(field(card, "city"), "slug"),
        placeField(field(card, "zone"), "slug"), placeField(field(card, "operator"), "slug"),
        placeField(field(card, "operator"), "name"), optionalString(field(card, "countryCode")),
        asDouble(lat), lat.present ? lat.text : null, asDouble(lng), lng.present ? lng.text : null,
        readBool(field(card, "featured")), verdict, asDouble(median),
        median.present ? median.text : null, sample, listingURL(slug, locale),
        optionalString(field(card, "updatedAt")));
}

private void catalogueMeta(JSONValue envelope, out string attribution, out string notice,
    out string seed, out Nullable!long pageCount, out Nullable!long total)
{
    auto meta = field(envelope, "meta");
    if (meta.type != JSONType.object)
        return;
    auto citation = field(meta, "citation");
    if (citation.type == JSONType.object)
        attribution = optionalString(field(citation, "text"));
    notice = optionalString(field(meta, "catalogueNotice"));
    seed = readSeed(field(meta, "seed"));
    auto pagination = field(meta, "pagination");
    if (pagination.type == JSONType.object)
    {
        pageCount = readLong(field(pagination, "pageCount"));
        total = readLong(field(pagination, "total"));
    }
}

private JSONValue[] series(JSONValue city)
{
    auto figures = field(city, "figures");
    if (figures.type == JSONType.array && figures.array.length)
        return figures.array;
    auto byType = field(city, "byType");
    if (byType.type == JSONType.array)
        return byType.array;
    return null;
}

private Rate makeRate(string citySlug, string cityName, string countryCode, string currency,
    string product, string unit, JSONValue stat, string asOf)
{
    auto median = amount(field(stat, "median"));
    if (!median.present)
        throw new ShapeException("Unexpected shape for market rates");
    auto sample = readLong(field(stat, "sampleSize"));
    if (sample.isNull)
        throw new ShapeException("Unexpected shape for market rates");
    auto p25 = amount(field(stat, "p25"));
    auto p75 = amount(field(stat, "p75"));
    return Rate(citySlug, cityName, countryCode, currency, product, unit, median.value, median.text,
        asDouble(p25), p25.present ? p25.text : null, asDouble(p75), p75.present ? p75.text : null,
        sample.get, readLong(field(stat, "propertyCount")), readLong(field(stat, "operatorCount")),
        sample.get < 10, asOf);
}

private string placeField(JSONValue place, string key)
{
    if (place.type != JSONType.object)
        return null;
    return optionalString(field(place, key));
}

private string requiredString(JSONValue obj, string key, string message = "Unexpected shape for a property")
{
    auto text = optionalString(field(obj, key));
    if (text is null)
        throw new ShapeException(message);
    return text;
}

private int productRank(string product)
{
    foreach (i, name; products)
    {
        if (name == product)
            return cast(int) i;
    }
    return cast(int) products.length;
}

version (unittest)
{
    import std.algorithm.searching : canFind, startsWith;
    import std.array : replace;
    import std.json : parseJSON;
    import std.stdio : stderr;
    import std.string : split;

    private string fixture(string name)()
    {
        return import(name);
    }

    private void assertSame(string got, string expect, string name)
    {
        if (got == expect)
            return;
        stderr.writeln("mismatch ", name, " got ", got.length, " expect ", expect.length);
        auto left = got.split('\n');
        auto right = expect.split('\n');
        auto count = left.length < right.length ? left.length : right.length;
        foreach (i; 0 .. count)
        {
            if (left[i] != right[i])
            {
                stderr.writeln("line ", i);
                stderr.writeln("GOT ", left[i]);
                stderr.writeln("EXP ", right[i]);
                break;
            }
        }
        assert(false, name ~ " mismatch");
    }

    private string csvField(string value)
    {
        if (value is null)
            return "";
        bool quote;
        foreach (c; value)
        {
            if (c == ',' || c == '"' || c == '\n' || c == '\r')
                quote = true;
        }
        if (!quote)
            return value;
        return `"` ~ value.replace(`"`, `""`) ~ `"`;
    }

    private string csvJoin(string[] fields)
    {
        string line;
        foreach (i, field; fields)
        {
            if (i)
                line ~= ",";
            line ~= csvField(field);
        }
        return line ~ "\n";
    }

    private string csvLong(Nullable!long value)
    {
        import std.conv : to;
        return value.isNull ? "" : to!string(value.get);
    }

    private string csvText(string value)
    {
        return value is null ? "" : value;
    }

    private string ratesCSV(Rate[] rows)
    {
        string text = "city_slug,city_name,country_code,currency,product,unit,median,p25,p75,sample_size,property_count,operator_count,low_confidence,as_of\n";
        foreach (row; rows)
        {
            text ~= csvJoin([
                row.citySlug, row.cityName, csvText(row.countryCode), row.currency, row.product,
                csvText(row.unit), row.medianText, csvText(row.p25Text), csvText(row.p75Text),
                csvLong(Nullable!long(row.sampleSize)), csvLong(row.propertyCount),
                csvLong(row.operatorCount), row.lowConfidence ? "true" : "false", csvText(row.asOf)
            ]);
        }
        return text;
    }

    private string citiesCSV(City[] rows)
    {
        string text = "city_slug,city_name,country_code,currency,published,property_count,operator_count,entry_median,entry_min,entry_max,p25,p75,sample_size,as_of\n";
        foreach (row; rows)
        {
            text ~= csvJoin([
                row.citySlug, row.cityName, csvText(row.countryCode), csvText(row.currency),
                row.published ? "true" : "false", csvLong(row.propertyCount), csvLong(row.operatorCount),
                csvText(row.entryMedianText), csvText(row.entryMinText), csvText(row.entryMaxText),
                csvText(row.p25Text), csvText(row.p75Text), csvLong(row.sampleSize), csvText(row.asOf)
            ]);
        }
        return text;
    }

    private string listingsCSV(Listing[] rows)
    {
        string text = "slug,title,city_slug,zone_slug,operator_slug,operator_name,country_code,lat,lng,featured,market_verdict,market_median,market_sample_size,url,updated_at\n";
        foreach (row; rows)
        {
            string featured;
            if (!row.featured.isNull)
                featured = row.featured.get ? "true" : "false";
            text ~= csvJoin([
                row.slug, row.title, csvText(row.citySlug), csvText(row.zoneSlug),
                csvText(row.operatorSlug), csvText(row.operatorName), csvText(row.countryCode),
                csvText(row.latText), csvText(row.lngText), featured, csvText(row.marketVerdict),
                csvText(row.marketMedianText), csvLong(row.marketSampleSize), row.url,
                csvText(row.updatedAt)
            ]);
        }
        return text;
    }

    private string pricingCSV(PricingOption[] rows)
    {
        string text = "product,title,price,currency,billing_period,price_on_request,min_capacity,max_capacity\n";
        foreach (row; rows)
        {
            text ~= csvJoin([
                row.product, row.title, csvText(row.priceText), csvText(row.currency),
                row.billingPeriod, row.priceOnRequest ? "true" : "false", csvLong(row.minCapacity),
                csvLong(row.maxCapacity)
            ]);
        }
        return text;
    }

    unittest
    {
        auto rates = parseRates(parseJSON(fixture!"market_rates.json"));
        assertSame(ratesCSV(rates.data), fixture!"rates.csv", "rates");
        assert(rates.attribution.canFind("CoworkingView Price Index"));
        assert(rates.license == "https://creativecommons.org/licenses/by/4.0/");
        assert(rates.asOf == "2026-10-27T21:06:48.313Z");
        foreach (row; rates.data)
            assert(row.citySlug != "example-town");

        auto cities = parseCities(parseJSON(fixture!"market_rates.json"));
        assertSame(citiesCSV(cities.data), fixture!"cities.csv", "cities");
        assert(cities.data[$ - 1].citySlug == "example-town");
        assert(!cities.data[$ - 1].published);

        string attribution, notice, seed;
        Nullable!long pageCount, total;
        auto rows = parseListings(parseJSON(fixture!"properties_berlin.json"), "en",
            attribution, notice, seed, pageCount, total);
        assertSame(listingsCSV(rows), fixture!"spaces.csv", "spaces");
        assert(!total.isNull && total.get == 110);
        assert(attribution == "Source: CoworkingView — Coworking spaces in Berlin, https://coworkingview.com/en/coworking/berlin.");
        assert(notice.canFind("not permitted"));
        assert(!listingsCSV(rows).canFind("example.com"));
        assert(!listingsCSV(rows).canFind("Example description"));

        auto spanish = parseListings(parseJSON(fixture!"properties_berlin.json"), "es",
            attribution, notice, seed, pageCount, total);
        auto german = parseListings(parseJSON(fixture!"properties_berlin.json"), "de",
            attribution, notice, seed, pageCount, total);
        assert(spanish[0].url.startsWith("https://coworkingview.com/es/oficina/"));
        assert(german[0].url.startsWith("https://coworkingview.com/de/buero/"));

        auto space = parseSpace(parseJSON(fixture!"property_detail.json"), "en");
        assertSame(pricingCSV(space.pricing), fixture!"space_pricing.csv", "pricing");
        assert(space.amenities.length == 9);
        assert(space.marketVerdict == "around");
        assert(space.marketMedianText == "214");
        assert(space.capacity.isNull);
        assert(space.pricing[1].price.isNull);
        assert(space.pricing[1].currency is null);
        assert(space.pricing[1].priceOnRequest);
        assert(space.pricing[0].priceText == "209");
        assert(space.attribution.length);
        assert(space.notice.length);
        assert(space.url == "https://coworkingview.com/en/workspace/sankt-oberholz-rosenthaler-berlin");
        auto dumped = space.slug ~ space.title ~ space.address ~ space.url ~ space.attribution ~ space.notice;
        foreach (amenity; space.amenities)
            dumped ~= amenity;
        foreach (offer; space.pricing)
            dumped ~= offer.title ~ offer.product;
        assert(!dumped.canFind("Example description"));
        assert(!dumped.canFind("example.com"));

        auto usd = parseRates(parseJSON(fixture!"market_rates_berlin_usd.json")).data;
        assert(usd.length);
        foreach (row; usd)
        {
            assert(row.currency == "USD");
            assert(row.citySlug == "berlin");
        }
        assert(usd[0].product == "flex_desk");
        assert(usd[0].unit == "month");
        bool dayPass, meetingRoom;
        foreach (row; usd)
        {
            if (row.product == "day_pass" && row.unit == "day")
                dayPass = true;
            if (row.product == "meeting_room" && row.unit == "hour")
                meetingRoom = true;
        }
        assert(dayPass && meetingRoom);

        rows = parseListings(parseJSON(fixture!"properties_empty.json"), "en",
            attribution, notice, seed, pageCount, total);
        assert(rows.length == 0);
        assert(!total.isNull && total.get == 0);
        assert(listingsCSV(rows).split('\n').length == 2);
    }

    unittest
    {
        auto fresh = parseRates(parseJSON(`{"data":{"asOf":"2026-01-01T00:00:00Z","cities":[{"city":{"slug":"berlin","name":"Berlin"},"currency":"EUR","figures":[],"eventSpace":{"median":{"amount":100},"sampleSize":3},"rooftopBar":{"median":{"amount":12.5},"sampleSize":11}}]}}`)).data;
        assert(fresh.length == 2);
        assert(fresh[0].product == "event_space");
        assert(fresh[1].product == "rooftop_bar");
        assert(fresh[0].unit == "hour");
        assert(fresh[0].medianText == "100");
        assert(fresh[0].p25.isNull);
        assert(fresh[0].lowConfidence);
        assert(fresh[1].unit is null);
        assert(fresh[1].medianText == "12.5");
        assert(!fresh[1].lowConfidence);

        auto byType = parseRates(parseJSON(`{"data":{"asOf":"t","cities":[{"city":{"slug":"berlin","name":"Berlin"},"currency":"EUR","figures":[],"byType":[{"optionType":"fix_desk","median":{"amount":10},"sampleSize":4}]}]}}`)).data;
        assert(byType.length == 1);
        assert(byType[0].product == "fix_desk");
        assert(byType[0].unit == "month");
        assert(byType[0].lowConfidence);

        auto future = parseRates(parseJSON(`{"data":{"asOf":"2026-10-27T00:00:00Z","cities":[{"city":{"slug":"zurich","name":"Zurich"},"currency":"CHF","figures":[],"byType":[{"optionType":"private_office","median":{"amount":900},"sampleSize":12},{"optionType":"flex_desk","median":{"amount":400},"sampleSize":4}],"eventSpace":{"median":{"amount":150},"p25":{"amount":100},"p75":{"amount":200},"sampleSize":3},"virtualOffice":{"median":{"amount":60},"sampleSize":20},"parkingSpot":{"median":{"amount":120},"sampleSize":5},"aRooftop":{"median":{"amount":10},"sampleSize":1},"p25":{"amount":1},"insufficientData":false}],"unpublished":[{"city":{"slug":"bern","name":"Bern"}}]}}`)).data;
        string[] got;
        foreach (row; future)
        {
            got ~= row.product ~ "|" ~ (row.unit is null ? "" : row.unit) ~ "|" ~ row.medianText
                ~ "|" ~ (row.p25Text is null ? "" : row.p25Text) ~ "|"
                ~ (row.lowConfidence ? "true" : "false");
        }
        assert(got == [
            "flex_desk|month|400||true",
            "private_office|month|900||false",
            "event_space|hour|150|100|true",
            "virtual_office|month|60||false",
            "a_rooftop||10||true",
            "parking_spot||120||true",
        ]);
        assert(future[0].countryCode is null);
        assert(future[0].propertyCount.isNull);

        assert(snake("dayPass") == "day_pass");
        assert(snake("eventSpace") == "event_space");
        assert(snake("x") == "x");
        assert(snake("aRooftop") == "a_rooftop");
    }
}
