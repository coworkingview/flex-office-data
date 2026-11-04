package com.coworkingview.openrefine;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import java.io.IOException;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

/**
 * Turns one {@code GET /v1/market/rates} body into the object
 * {@code coworkingviewPriceIndex} returns.
 *
 * <p>Field selection follows the shared flex-office-data specification:
 * {@code figures} when that array is present, otherwise {@code byType}, plus a
 * city field whose value has both {@code median} and {@code sampleSize}
 * ({@code dayPass}, {@code meetingRoom}, and any later aggregate of that
 * shape). {@code min} and {@code max} are copied from the matching
 * {@code byType} item when {@code figures} does not carry them. Nothing is
 * filled in when the response omits it.
 */
final class PriceIndexParser {
    static final String DEFAULT_PRODUCT = "flex_desk";

    private static final ObjectMapper MAPPER = new ObjectMapper();
    private static final long LOW_CONFIDENCE_BELOW = 10L;

    private static final List<String> PRODUCT_ORDER = List.of(
            "flex_desk",
            "fix_desk",
            "private_office",
            "exclusive_bereich",
            "day_pass",
            "meeting_room",
            "event_space",
            "virtual_office",
            "membership");

    private PriceIndexParser() {
    }

    static ObjectNode parse(String body, String citySlug, String product) throws PriceIndexException {
        JsonNode root = read(body);
        JsonNode data = root.get("data");
        if (data == null || !data.isObject()) {
            throw new PriceIndexException("rates response has no data object");
        }
        JsonNode city = publishedCity(data, citySlug);
        Map<String, JsonNode> figures = options(city.get("figures"));
        Map<String, JsonNode> byType = options(city.get("byType"));
        Map<String, JsonNode> aggregates = aggregates(city);

        JsonNode stat = figures.get(product);
        JsonNode range = null;
        String unit = "month";
        if (stat != null) {
            range = byType.get(product);
        } else if (byType.containsKey(product)) {
            stat = byType.get(product);
            range = stat;
        } else if (aggregates.containsKey(product)) {
            stat = aggregates.get(product);
            range = stat;
            unit = unitForAggregate(product);
        }
        if (stat == null) {
            List<String> available = new ArrayList<String>();
            available.addAll(figures.keySet());
            for (String name : byType.keySet()) {
                if (!available.contains(name)) {
                    available.add(name);
                }
            }
            for (String name : aggregates.keySet()) {
                if (!available.contains(name)) {
                    available.add(name);
                }
            }
            available.sort(productOrder());
            String listed = available.isEmpty() ? "none" : String.join(", ", available);
            throw new PriceIndexException("unknown product '" + product + "'. Available: " + listed);
        }

        JsonNode median = stat.get("median");
        if (median == null || !median.isObject() || !median.has("amount") || !median.get("amount").isNumber()) {
            throw new PriceIndexException("median is not published for '" + product + "'");
        }
        JsonNode sampleSize = stat.get("sampleSize");
        if (sampleSize == null || !sampleSize.isNumber()) {
            throw new PriceIndexException("sample size is not published for '" + product + "'");
        }

        ObjectNode out = MAPPER.createObjectNode();
        out.put("citySlug", text(city.path("city"), "slug"));
        putText(out, "cityName", text(city.path("city"), "name"));
        putText(out, "countryCode", text(city, "countryCode"));
        putText(out, "currency", text(city, "currency"));
        out.put("product", product);
        if (unit != null) {
            out.put("unit", unit);
        }
        putAmount(out, "median", median);
        putAmount(out, "p25", stat.get("p25"));
        putAmount(out, "p75", stat.get("p75"));
        if (range != null) {
            if (!stat.has("min")) {
                putAmount(out, "min", range.get("min"));
            } else {
                putAmount(out, "min", stat.get("min"));
            }
            if (!stat.has("max")) {
                putAmount(out, "max", range.get("max"));
            } else {
                putAmount(out, "max", stat.get("max"));
            }
        }
        out.put("sampleSize", sampleSize.longValue());
        putLong(out, "propertyCount", stat.get("propertyCount"));
        putLong(out, "operatorCount", stat.get("operatorCount"));
        out.put("lowConfidence", sampleSize.longValue() < LOW_CONFIDENCE_BELOW);
        putText(out, "asOf", text(data, "asOf"));
        putText(out, "attribution", text(data, "attribution"));
        putText(out, "license", text(data, "licenseUrl"));
        return out;
    }

    static String citySlug(Object value) throws PriceIndexException {
        String text = argument(value);
        if (text == null || text.isEmpty()) {
            throw new PriceIndexException("city is required, for example berlin");
        }
        String slug = text.toLowerCase(Locale.ROOT).replace('_', '-').replace(' ', '-');
        while (slug.contains("--")) {
            slug = slug.replace("--", "-");
        }
        if (!slug.matches("[a-z0-9][a-z0-9-]*")) {
            throw new PriceIndexException("city must be a slug such as berlin");
        }
        return slug;
    }

    static String productCode(Object value) throws PriceIndexException {
        if (value == null) {
            return DEFAULT_PRODUCT;
        }
        String text = argument(value);
        if (text == null || text.isEmpty()) {
            throw new PriceIndexException("product is required, for example flex_desk");
        }
        String code = text.toLowerCase(Locale.ROOT).replace('-', ' ').replace('_', ' ').trim();
        code = String.join("_", code.split("\\s+"));
        if (!code.matches("[a-z][a-z0-9_]*")) {
            throw new PriceIndexException("product must be a code such as flex_desk");
        }
        return code;
    }

    private static JsonNode read(String body) throws PriceIndexException {
        if (body == null || body.isBlank()) {
            throw new PriceIndexException("rates response was empty");
        }
        try {
            JsonNode root = MAPPER.readTree(body);
            if (root == null || !root.isObject()) {
                throw new PriceIndexException("rates response was not a JSON object");
            }
            return root;
        } catch (IOException ex) {
            throw new PriceIndexException("rates response was not valid JSON");
        }
    }

    private static JsonNode publishedCity(JsonNode data, String slug) throws PriceIndexException {
        JsonNode cities = data.get("cities");
        if (cities != null && cities.isArray()) {
            for (JsonNode row : cities) {
                if (row != null && row.isObject() && slug.equals(text(row.path("city"), "slug"))) {
                    return row;
                }
            }
        }
        JsonNode unpublished = data.get("unpublished");
        if (unpublished != null && unpublished.isArray()) {
            for (JsonNode row : unpublished) {
                if (row != null && row.isObject() && slug.equals(text(row.path("city"), "slug"))) {
                    throw new PriceIndexException("no published price index for '" + slug + "'");
                }
            }
        }
        throw new PriceIndexException("unknown city '" + slug + "'");
    }

    private static Map<String, JsonNode> options(JsonNode array) {
        Map<String, JsonNode> found = new LinkedHashMap<String, JsonNode>();
        if (array == null || !array.isArray()) {
            return found;
        }
        for (JsonNode item : array) {
            if (item == null || !item.isObject()) {
                continue;
            }
            String type = text(item, "optionType");
            if (type != null && !found.containsKey(type)) {
                found.put(type, item);
            }
        }
        return found;
    }

    private static Map<String, JsonNode> aggregates(JsonNode city) {
        Map<String, JsonNode> found = new LinkedHashMap<String, JsonNode>();
        Iterator<Map.Entry<String, JsonNode>> fields = city.fields();
        while (fields.hasNext()) {
            Map.Entry<String, JsonNode> entry = fields.next();
            JsonNode value = entry.getValue();
            if (!isStat(value)) {
                continue;
            }
            found.put(snake(entry.getKey()), value);
        }
        return found;
    }

    private static boolean isStat(JsonNode value) {
        return value != null && value.isObject() && value.has("median") && value.has("sampleSize");
    }

    static String snake(String key) {
        StringBuilder out = new StringBuilder();
        for (int i = 0; i < key.length(); i++) {
            char c = key.charAt(i);
            if (Character.isUpperCase(c)) {
                out.append('_');
                out.append(Character.toLowerCase(c));
            } else {
                out.append(c);
            }
        }
        int start = 0;
        while (start < out.length() && out.charAt(start) == '_') {
            start++;
        }
        return out.substring(start);
    }

    private static String unitForAggregate(String product) {
        if ("day_pass".equals(product)) {
            return "day";
        }
        if ("meeting_room".equals(product) || "event_space".equals(product)) {
            return "hour";
        }
        if ("virtual_office".equals(product)) {
            return "month";
        }
        return null;
    }

    private static Comparator<String> productOrder() {
        return new Comparator<String>() {
            @Override
            public int compare(String left, String right) {
                int leftRank = PRODUCT_ORDER.indexOf(left);
                int rightRank = PRODUCT_ORDER.indexOf(right);
                if (leftRank < 0 && rightRank < 0) {
                    return left.compareTo(right);
                }
                if (leftRank < 0) {
                    return 1;
                }
                if (rightRank < 0) {
                    return -1;
                }
                return Integer.compare(leftRank, rightRank);
            }
        };
    }

    private static void putAmount(ObjectNode out, String field, JsonNode money) {
        if (money == null || !money.isObject()) {
            return;
        }
        JsonNode amount = money.get("amount");
        if (amount == null || !amount.isNumber()) {
            return;
        }
        if (amount.isIntegralNumber()) {
            out.put(field, amount.longValue());
        } else {
            out.put(field, amount.doubleValue());
        }
    }

    private static void putLong(ObjectNode out, String field, JsonNode value) {
        if (value != null && value.isNumber()) {
            out.put(field, value.longValue());
        }
    }

    private static void putText(ObjectNode out, String field, String value) {
        if (value != null && !value.isEmpty()) {
            out.put(field, value);
        }
    }

    private static String text(JsonNode node, String field) {
        if (node == null || !node.isObject()) {
            return null;
        }
        JsonNode value = node.get(field);
        if (value == null || !value.isTextual()) {
            return null;
        }
        String text = value.asText();
        return text.isEmpty() ? null : text;
    }

    private static String argument(Object value) {
        if (value == null) {
            return null;
        }
        String text = String.valueOf(value).trim();
        return text.isEmpty() ? "" : text;
    }
}
