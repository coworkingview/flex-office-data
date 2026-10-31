package io.github.coworkingview;

import io.github.coworkingview.Json.Value;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;
import java.util.Map;

/** Turns a response body into rows. Spec sections 3 to 6. No I/O. */
final class Parser {
    private final int status;
    private final String path;

    private Parser(int status, String path) {
        this.status = status;
        this.path = path;
    }

    static Dataset<List<Rate>> rates(int status, String body) {
        return new Parser(status, "/v1/market/rates").parseRates(body);
    }

    static Dataset<List<City>> cities(int status, String body) {
        return new Parser(status, "/v1/market/rates").parseCities(body);
    }

    static Page spaces(int status, String body, Locale locale) {
        return new Parser(status, "/v1/properties").parseSpaces(body, locale);
    }

    static Dataset<Space> space(int status, String body, Locale locale, String slug) {
        return new Parser(status, "/v1/properties/" + slug).parseSpace(body, locale);
    }

    static final class Page {
        final Dataset<List<Listing>> dataset;
        final Long pageCount;
        final String seed;

        Page(Dataset<List<Listing>> dataset, Long pageCount, String seed) {
            this.dataset = dataset;
            this.pageCount = pageCount;
            this.seed = seed;
        }
    }

    private Dataset<List<Rate>> parseRates(String body) {
        Value data = objectData(body);
        String asOf = data.optString("asOf");
        List<Rate> rows = new ArrayList<Rate>();
        for (Value city : array(data, "cities")) {
            if (!city.isObject()) {
                throw shape("`cities[]` is not an object");
            }
            Value identity = requireObject(city, "city");
            String citySlug = requireString(identity, "slug");
            String cityName = requireString(identity, "name");
            String country = city.optString("countryCode");
            String currency = requireString(city, "currency");
            for (Value item : monthly(city)) {
                if (!item.isObject()) {
                    throw shape("`figures[]` is not an object");
                }
                rows.add(rate(citySlug, cityName, country, currency, Product.fromApi(requireString(item, "optionType")), Unit.MONTH, item, asOf));
            }
            for (Map.Entry<String, Value> entry : city.fields().entrySet()) {
                Value stat = entry.getValue();
                if (!isStat(stat)) {
                    continue;
                }
                Product product = Product.fromApi(snake(entry.getKey()));
                rows.add(rate(citySlug, cityName, country, currency, product, Unit.forAggregate(product), stat, asOf));
            }
        }
        rows.sort(Comparator.comparing(Rate::getCitySlug).thenComparingInt(rate -> rate.getProduct().sortIndex()).thenComparing(rate -> rate.getProduct().getApiName()));
        return indexDataset(data, Collections.unmodifiableList(rows));
    }

    private Dataset<List<City>> parseCities(String body) {
        Value data = objectData(body);
        String asOf = data.optString("asOf");
        List<City> rows = new ArrayList<City>();
        for (Value city : array(data, "cities")) {
            if (!city.isObject()) {
                throw shape("`cities[]` is not an object");
            }
            Value identity = requireObject(city, "city");
            rows.add(new City(
                    requireString(identity, "slug"),
                    requireString(identity, "name"),
                    city.optString("countryCode"),
                    requireString(city, "currency"),
                    true,
                    optLong(city, "propertyCount"),
                    optLong(city, "operatorCount"),
                    amount(city, "entryMedian"),
                    amount(city, "entryMin"),
                    amount(city, "entryMax"),
                    amount(city, "p25"),
                    amount(city, "p75"),
                    optLong(city, "sampleSize"),
                    asOf));
        }
        for (Value city : array(data, "unpublished")) {
            if (!city.isObject()) {
                throw shape("`unpublished[]` is not an object");
            }
            Value identity = requireObject(city, "city");
            rows.add(new City(
                    requireString(identity, "slug"),
                    requireString(identity, "name"),
                    city.optString("countryCode"),
                    city.optString("currency"),
                    false,
                    null,
                    null,
                    null,
                    null,
                    null,
                    null,
                    null,
                    null,
                    asOf));
        }
        rows.sort(Comparator.comparing((City city) -> !city.isPublished()).thenComparing(City::getCitySlug));
        return indexDataset(data, Collections.unmodifiableList(rows));
    }

    private Page parseSpaces(String body, Locale locale) {
        Value root = root(body);
        Value data = root.get("data");
        if (data == null || data.isNull()) {
            throw missingData();
        }
        if (!data.isArray()) {
            throw shape("Unexpected shape for properties");
        }
        List<Listing> rows = new ArrayList<Listing>();
        for (Value card : data.elements()) {
            if (!card.isObject()) {
                throw shape("`data[]` is not an object");
            }
            String slug = requireString(card, "slug");
            rows.add(listing(card, slug, listingUrl(slug, locale)));
        }
        Value meta = meta(root);
        return new Page(
                catalogueDataset(meta, Collections.unmodifiableList(rows)),
                pageCount(meta),
                seed(meta));
    }

    private Dataset<Space> parseSpace(String body, Locale locale) {
        Value root = root(body);
        Value data = root.get("data");
        if (data == null || data.isNull()) {
            throw missingData();
        }
        if (!data.isObject()) {
            throw shape("Unexpected shape for a property");
        }
        String slug = requireString(data, "slug");
        String webUrl = data.optString("webUrl");
        String url = webUrl == null || webUrl.isEmpty() ? listingUrl(slug, locale) : webUrl;
        Listing card = listing(data, slug, url);
        List<PricingOption> pricing = new ArrayList<PricingOption>();
        Value options = data.get("pricingOptions");
        if (options != null && !options.isNull()) {
            if (!options.isArray()) {
                throw shape("`pricingOptions` is not an array");
            }
            for (Value option : options.elements()) {
                if (!option.isObject()) {
                    throw shape("`pricingOptions[]` is not an object");
                }
                pricing.add(pricing(option));
            }
        }
        List<String> amenities = new ArrayList<String>();
        Value amenityValues = data.get("amenities");
        if (amenityValues != null && !amenityValues.isNull()) {
            if (!amenityValues.isArray()) {
                throw shape("`amenities` is not an array");
            }
            for (Value amenity : amenityValues.elements()) {
                if (amenity.isString()) {
                    amenities.add(amenity.string());
                }
            }
        }
        Space space = new Space(
                card.getSlug(),
                card.getTitle(),
                card.getCitySlug(),
                card.getZoneSlug(),
                card.getOperatorSlug(),
                card.getOperatorName(),
                card.getCountryCode(),
                card.getLatText(),
                card.getLngText(),
                card.getFeatured(),
                card.getMarketVerdict(),
                card.getMarketMedianText(),
                card.getMarketSampleSize(),
                card.getUrl(),
                card.getUpdatedAt(),
                data.optString("address"),
                optLong(data, "capacity"),
                Collections.unmodifiableList(amenities),
                Collections.unmodifiableList(pricing));
        return catalogueDataset(meta(root), space);
    }

    private Rate rate(
            String citySlug,
            String cityName,
            String country,
            String currency,
            Product product,
            Unit unit,
            Value stat,
            String asOf) {
        String median = amount(stat, "median");
        if (median == null) {
            throw shape("`median` is missing");
        }
        return new Rate(
                citySlug,
                cityName,
                country,
                currency,
                product,
                unit,
                median,
                amount(stat, "p25"),
                amount(stat, "p75"),
                reqLong(stat, "sampleSize"),
                optLong(stat, "propertyCount"),
                optLong(stat, "operatorCount"),
                asOf);
    }

    private Listing listing(Value card, String slug, String url) {
        Value market = card.get("marketPosition");
        if (market != null && (market.isNull() || !market.isObject())) {
            market = null;
        }
        return new Listing(
                slug,
                requireString(card, "title"),
                childString(card, "city", "slug"),
                childString(card, "zone", "slug"),
                childString(card, "operator", "slug"),
                childString(card, "operator", "name"),
                card.optString("countryCode"),
                coord(card, "lat"),
                coord(card, "lng"),
                flag(card, "featured"),
                market == null ? null : market.optString("verdict"),
                market == null ? null : amount(market, "median"),
                market == null ? null : optLong(market, "sampleSize"),
                url,
                card.optString("updatedAt"));
    }

    private PricingOption pricing(Value option) {
        Value price = option.get("price");
        String priceText = null;
        String currency = null;
        if (price != null && !price.isNull()) {
            if (!price.isObject()) {
                throw shape("`price` is not an object");
            }
            Value amount = price.get("amount");
            if (amount != null && !amount.isNull()) {
                if (!amount.isNumber()) {
                    throw shape("`price.amount` is not a number");
                }
                priceText = amount.rawNumber();
            }
            currency = price.optString("currency");
        }
        Value onRequest = option.get("priceOnRequest");
        if (onRequest == null || !onRequest.isBoolean()) {
            throw shape("`priceOnRequest` is not a boolean");
        }
        return new PricingOption(
                Product.fromApi(requireString(option, "optionType")),
                requireString(option, "title"),
                priceText,
                currency,
                requireString(option, "billingPeriod"),
                onRequest.bool(),
                optLong(option, "minCapacity"),
                optLong(option, "maxCapacity"));
    }

    private static boolean isStat(Value value) {
        return value != null && value.isObject() && value.has("median") && value.has("sampleSize");
    }

    private static List<Value> monthly(Value city) {
        Value figures = city.get("figures");
        if (figures != null && figures.isArray() && !figures.elements().isEmpty()) {
            return figures.elements();
        }
        Value byType = city.get("byType");
        if (byType != null && byType.isArray() && !byType.elements().isEmpty()) {
            return byType.elements();
        }
        return Collections.emptyList();
    }

    private static String snake(String key) {
        StringBuilder sb = new StringBuilder(key.length() + 4);
        for (int i = 0; i < key.length(); i++) {
            char c = key.charAt(i);
            if (i > 0 && Character.isUpperCase(c)) {
                sb.append('_');
            }
            sb.append(Character.toLowerCase(c));
        }
        return sb.toString();
    }

    static String listingUrl(String slug, Locale locale) {
        return "https://coworkingview.com/" + locale.getCode() + "/" + locale.workspacePath() + "/" + slug;
    }

    private <T> Dataset<T> indexDataset(Value data, T rows) {
        return new Dataset<T>(data.optString("attribution"), data.optString("licenseUrl"), data.optString("asOf"), null, null, rows);
    }

    private <T> Dataset<T> catalogueDataset(Value meta, T rows) {
        String attribution = null;
        String accessed = null;
        String notice = null;
        Long total = null;
        if (meta != null) {
            Value citation = meta.get("citation");
            if (citation != null && citation.isObject()) {
                attribution = citation.optString("text");
                accessed = citation.optString("accessed");
            }
            notice = meta.optString("catalogueNotice");
            Value pagination = meta.get("pagination");
            if (pagination != null && pagination.isObject()) {
                total = optLong(pagination, "total");
            }
        }
        return new Dataset<T>(attribution, null, accessed, notice, total, rows);
    }

    private static Long pageCount(Value meta) {
        if (meta == null) {
            return null;
        }
        Value pagination = meta.get("pagination");
        if (pagination == null || !pagination.isObject()) {
            return null;
        }
        return optLong(pagination, "pageCount");
    }

    private static String seed(Value meta) {
        if (meta == null) {
            return null;
        }
        Value seed = meta.get("seed");
        if (seed == null || seed.isNull()) {
            return null;
        }
        if (seed.isNumber()) {
            return seed.rawNumber();
        }
        if (seed.isString()) {
            return seed.string();
        }
        return null;
    }

    private static Value meta(Value root) {
        Value meta = root.get("meta");
        if (meta == null || meta.isNull()) {
            return null;
        }
        return meta.isObject() ? meta : null;
    }

    private Value objectData(String body) {
        Value root = root(body);
        Value data = root.get("data");
        if (data == null || data.isNull()) {
            throw missingData();
        }
        if (!data.isObject()) {
            throw shape("Unexpected shape for market rates");
        }
        return data;
    }

    private Value root(String body) {
        Value root;
        try {
            root = Json.parse(body);
        } catch (Json.JsonException ex) {
            throw new ApiException(
                    status,
                    "BAD_RESPONSE",
                    "The API returned a body that is not valid JSON",
                    "HTTP " + status + " " + Transport.reasonPhrase(status),
                    null,
                    Collections.<FieldError>emptyList());
        }
        if (!root.isObject()) {
            throw new ApiException(
                    status,
                    "BAD_RESPONSE",
                    "The API returned JSON that is not an object",
                    "GET " + path,
                    null,
                    Collections.<FieldError>emptyList());
        }
        return root;
    }

    private List<Value> array(Value object, String key) {
        Value value = object.get(key);
        if (value == null || value.isNull()) {
            return Collections.emptyList();
        }
        if (!value.isArray()) {
            throw shape("`" + key + "` is not an array");
        }
        return value.elements();
    }

    private Value requireObject(Value parent, String key) {
        Value value = parent.get(key);
        if (value == null || !value.isObject()) {
            throw shape("`" + key + "` is not an object");
        }
        return value;
    }

    private String requireString(Value object, String key) {
        String value = object.optString(key);
        if (value == null) {
            throw shape("`" + key + "` is not a string");
        }
        return value;
    }

    private String amount(Value object, String key) {
        Value money = object.get(key);
        if (money == null || money.isNull()) {
            return null;
        }
        if (!money.isObject()) {
            throw shape("`" + key + "` is not an object");
        }
        Value amount = money.get("amount");
        if (amount == null || amount.isNull() || !amount.isNumber()) {
            throw shape("`" + key + ".amount` is missing");
        }
        return amount.rawNumber();
    }

    private static Long optLong(Value object, String key) {
        Value value = object.get(key);
        if (value == null || value.isNull() || !value.isNumber() || !value.integral()) {
            return null;
        }
        try {
            long parsed = Long.parseLong(value.rawNumber());
            if (parsed < 0) {
                return null;
            }
            return Long.valueOf(parsed);
        } catch (NumberFormatException ex) {
            return null;
        }
    }

    private long reqLong(Value object, String key) {
        Long value = optLong(object, key);
        if (value == null) {
            throw shape("`" + key + "` is not a non-negative integer");
        }
        return value.longValue();
    }

    private static String childString(Value parent, String child, String field) {
        Value value = parent.get(child);
        if (value == null || !value.isObject()) {
            return null;
        }
        return value.optString(field);
    }

    private static String coord(Value card, String field) {
        Value coordinates = card.get("coordinates");
        if (coordinates == null || !coordinates.isObject()) {
            return null;
        }
        Value value = coordinates.get(field);
        if (value == null || !value.isNumber()) {
            return null;
        }
        return value.rawNumber();
    }

    private static Boolean flag(Value object, String key) {
        Value value = object.get(key);
        if (value == null || !value.isBoolean()) {
            return null;
        }
        return Boolean.valueOf(value.bool());
    }

    private ApiException missingData() {
        return new ApiException(
                status,
                "BAD_RESPONSE",
                "The API response has no 'data' member",
                "GET " + path,
                null,
                Collections.<FieldError>emptyList());
    }

    private ApiException shape(String detail) {
        return new ApiException(status, "BAD_RESPONSE", "Unexpected shape for " + path, detail, null, Collections.<FieldError>emptyList());
    }
}
