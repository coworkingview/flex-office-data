package com.coworkingview.eclipse;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

/**
 * Reads {@code GET /v1/market/rates} into the three monthly desk products the view shows.
 * {@code figures} is preferred because it carries percentiles. {@code byType} is the fallback.
 * Cities under {@code unpublished} are not listed.
 */
public final class RatesParser {

    private RatesParser() {
    }

    public static PriceIndex parse(String json) throws RatesException {
        Json.Value root;
        try {
            root = Json.parse(json);
        } catch (Json.JsonException exception) {
            throw new RatesException("BAD_RESPONSE", exception.getMessage());
        }
        if (!(root instanceof Json.Obj envelope)) {
            throw new RatesException("BAD_RESPONSE", "The rates response is not a JSON object.");
        }
        Json.Obj data = envelope.obj("data");
        if (data == null) {
            throw new RatesException("BAD_RESPONSE", "The rates response has no data object.");
        }
        List<CityPrice> rows = new ArrayList<>();
        Json.Arr cities = data.arr("cities");
        if (cities != null) {
            for (Json.Value item : cities.items()) {
                if (item instanceof Json.Obj city) {
                    CityPrice row = city(city);
                    if (row != null) {
                        rows.add(row);
                    }
                }
            }
        }
        rows.sort(Comparator.comparing(CityPrice::name, String.CASE_INSENSITIVE_ORDER)
                .thenComparing(CityPrice::slug));
        return new PriceIndex(
                List.copyOf(rows),
                data.str("asOf"),
                data.str("attribution"),
                data.str("licenseUrl"),
                Origin.LIVE,
                null);
    }

    private static CityPrice city(Json.Obj city) {
        Json.Obj identity = city.obj("city");
        if (identity == null) {
            return null;
        }
        String slug = identity.str("slug");
        String name = identity.str("name");
        if (slug == null || slug.isBlank() || name == null || name.isBlank()) {
            return null;
        }
        DeskQuote hot = null;
        DeskQuote dedicated = null;
        DeskQuote office = null;
        Json.Arr figures = city.arr("figures");
        boolean fromFigures = figures != null && !figures.items().isEmpty();
        Json.Arr source = fromFigures ? figures : city.arr("byType");
        if (source != null) {
            for (Json.Value item : source.items()) {
                if (!(item instanceof Json.Obj figure)) {
                    continue;
                }
                String type = figure.str("optionType");
                DeskQuote quote = quote(figure);
                if (quote == null || type == null) {
                    continue;
                }
                switch (type) {
                    case "flex_desk" -> hot = quote;
                    case "fix_desk" -> dedicated = quote;
                    case "private_office" -> office = quote;
                    default -> {
                        // Day passes, meeting rooms, and later products are not columns in this view.
                    }
                }
            }
        }
        return new CityPrice(slug, name, city.str("countryCode"), city.str("currency"), hot, dedicated, office);
    }

    private static DeskQuote quote(Json.Obj figure) {
        String median = amount(figure, "median");
        String low = amount(figure, "p25");
        String high = amount(figure, "p75");
        boolean percentile = low != null || high != null;
        if (!percentile) {
            low = amount(figure, "min");
            high = amount(figure, "max");
        }
        if (median == null && low == null && high == null) {
            return null;
        }
        return new DeskQuote(median, low, high, percentile, sampleSize(figure));
    }

    private static String amount(Json.Obj parent, String key) {
        Json.Value value = parent.get(key);
        if (!(value instanceof Json.Obj object)) {
            return null;
        }
        Json.Value amount = object.get("amount");
        if (amount instanceof Json.Num number) {
            return number.token();
        }
        if (amount instanceof Json.Str string) {
            return string.value();
        }
        return null;
    }

    private static int sampleSize(Json.Obj figure) {
        Json.Value value = figure.get("sampleSize");
        if (!(value instanceof Json.Num number)) {
            return 0;
        }
        try {
            return new BigDecimal(number.token()).intValueExact();
        } catch (ArithmeticException | NumberFormatException exception) {
            return 0;
        }
    }
}
