package io.github.coworkingview;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.junit.jupiter.api.Assertions.fail;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import org.junit.jupiter.api.Test;

/** Parsing spec/fixtures must reproduce spec/golden. */
class GoldenTest {
    @Test
    void ratesMatchGolden() throws IOException {
        Dataset<List<Rate>> dataset = Parser.rates(200, fixture("market_rates.json"));
        assertText(golden("rates.csv"), ratesCsv(dataset.getData()));
        assertTrue(dataset.getAttribution().startsWith("Source: CoworkingView Price Index"));
        assertEquals("https://creativecommons.org/licenses/by/4.0/", dataset.getLicense());
        assertEquals("2026-10-27T21:06:48.313Z", dataset.getAsOf());
        assertNull(dataset.getNotice());
        assertNull(dataset.getTotal());
    }

    @Test
    void citiesMatchGolden() throws IOException {
        Dataset<List<City>> dataset = Parser.cities(200, fixture("market_rates.json"));
        assertText(golden("cities.csv"), citiesCsv(dataset.getData()));
        City last = dataset.getData().get(dataset.getData().size() - 1);
        assertFalse(last.isPublished());
        assertEquals("example-town", last.getCitySlug());
        assertNull(last.getEntryMedian());
        assertNull(last.getPropertyCount());
        assertNull(last.getCurrency());
    }

    @Test
    void spacesMatchGolden() throws IOException {
        Dataset<List<Listing>> dataset = Parser.spaces(200, fixture("properties_berlin.json"), Locale.EN).dataset;
        assertText(golden("spaces.csv"), listingsCsv(dataset.getData()));
        assertTrue(dataset.getAttribution().contains("Coworking spaces in Berlin"));
        assertTrue(dataset.getNotice().contains("Systematic extraction"));
        assertEquals("2026-10-27", dataset.getAsOf());
        assertEquals(Long.valueOf(110), dataset.getTotal());
        assertNull(dataset.getLicense());
    }

    @Test
    void spacePricingMatchesGolden() throws IOException {
        Dataset<Space> dataset = Parser.space(200, fixture("property_detail.json"), Locale.EN, "slug");
        Space space = dataset.getData();
        assertText(golden("space_pricing.csv"), pricingCsv(space.getPricing()));
        assertEquals("sankt-oberholz-rosenthaler-berlin", space.getSlug());
        assertEquals(
                "https://coworkingview.com/en/workspace/sankt-oberholz-rosenthaler-berlin", space.getUrl());
        assertEquals("Rosenthaler Straße 72a, 10119 Berlin, Germany", space.getAddress());
        assertEquals(9, space.getAmenities().size());
        assertEquals("around", space.getMarketVerdict());
        assertEquals("214", space.getMarketMedianText());
        assertNull(space.getCapacity());
        assertTrue(dataset.getAttribution() != null && dataset.getNotice() != null);
        assertNull(space.getPricing().get(1).getPrice());
        assertNull(space.getPricing().get(1).getCurrency());
        assertTrue(space.getPricing().get(1).isPriceOnRequest());
        assertFalse(space.toString().contains("Example description"));
    }

    @Test
    void spaceUrlsFollowLocale() throws IOException {
        String body = fixture("properties_berlin.json");
        Listing spanish = Parser.spaces(200, body, Locale.ES).dataset.getData().get(0);
        Listing german = Parser.spaces(200, body, Locale.DE).dataset.getData().get(0);
        assertTrue(spanish.getUrl().startsWith("https://coworkingview.com/es/oficina/"));
        assertTrue(german.getUrl().startsWith("https://coworkingview.com/de/buero/"));
    }

    @Test
    void convertedCurrencyParses() throws IOException {
        List<Rate> rates = Parser.rates(200, fixture("market_rates_berlin_usd.json")).getData();
        assertFalse(rates.isEmpty());
        for (Rate rate : rates) {
            assertEquals("USD", rate.getCurrency());
            assertEquals("berlin", rate.getCitySlug());
        }
        assertEquals(Product.FLEX_DESK, rates.get(0).getProduct());
        assertEquals(Unit.MONTH, rates.get(0).getUnit());
        assertTrue(rates.stream().anyMatch(rate -> rate.getProduct().equals(Product.DAY_PASS) && rate.getUnit() == Unit.DAY));
        assertTrue(rates.stream().anyMatch(rate -> rate.getProduct().equals(Product.MEETING_ROOM) && rate.getUnit() == Unit.HOUR));
    }

    @Test
    void emptySearchParses() throws IOException {
        Dataset<List<Listing>> dataset = Parser.spaces(200, fixture("properties_empty.json"), Locale.EN).dataset;
        assertTrue(dataset.getData().isEmpty());
        assertEquals(1, listingsCsv(dataset.getData()).lines().count());
        assertEquals(Long.valueOf(0), dataset.getTotal());
    }

    @Test
    void newAggregateAppearsWithoutACodeChange() {
        String body = "{\"data\":{\"asOf\":\"2026-01-01T00:00:00Z\",\"cities\":[{\"city\":{\"slug\":\"berlin\","
                + "\"name\":\"Berlin\"},\"currency\":\"EUR\",\"figures\":[],\"eventSpace\":{\"median\":{\"amount\":100},"
                + "\"sampleSize\":3},\"rooftopBar\":{\"median\":{\"amount\":12.5},\"sampleSize\":11}}]}}";
        List<Rate> rates = Parser.rates(200, body).getData();
        assertEquals(2, rates.size());
        assertEquals(Product.EVENT_SPACE, rates.get(0).getProduct());
        assertEquals(Unit.HOUR, rates.get(0).getUnit());
        assertEquals("100", rates.get(0).getMedianText());
        assertNull(rates.get(0).getP25());
        assertTrue(rates.get(0).isLowConfidence());
        assertEquals("rooftop_bar", rates.get(1).getProduct().getApiName());
        assertNull(rates.get(1).getUnit());
        assertEquals("12.5", rates.get(1).getMedianText());
        assertFalse(rates.get(1).isLowConfidence());
    }

    @Test
    void emptyFiguresFallsThroughToByType() {
        String body = "{\"data\":{\"asOf\":\"t\",\"cities\":[{\"city\":{\"slug\":\"berlin\",\"name\":\"Berlin\"},"
                + "\"currency\":\"EUR\",\"figures\":[],\"byType\":[{\"optionType\":\"fix_desk\",\"median\":{\"amount\":10},"
                + "\"sampleSize\":4}]}]}}";
        List<Rate> rates = Parser.rates(200, body).getData();
        assertEquals(1, rates.size());
        assertEquals(Product.FIX_DESK, rates.get(0).getProduct());
        assertEquals(Unit.MONTH, rates.get(0).getUnit());
        assertTrue(rates.get(0).isLowConfidence());
    }

    private static String ratesCsv(List<Rate> rows) {
        StringBuilder sb = new StringBuilder();
        sb.append("city_slug,city_name,country_code,currency,product,unit,median,p25,p75,sample_size,"
                + "property_count,operator_count,low_confidence,as_of\n");
        for (Rate rate : rows) {
            line(
                    sb,
                    rate.getCitySlug(),
                    rate.getCityName(),
                    rate.getCountryCode(),
                    rate.getCurrency(),
                    rate.getProduct().getApiName(),
                    rate.getUnit() == null ? null : rate.getUnit().getApiName(),
                    rate.getMedianText(),
                    rate.getP25Text(),
                    rate.getP75Text(),
                    Long.toString(rate.getSampleSize()),
                    text(rate.getPropertyCount()),
                    text(rate.getOperatorCount()),
                    Boolean.toString(rate.isLowConfidence()),
                    rate.getAsOf());
        }
        return sb.toString();
    }

    private static String citiesCsv(List<City> rows) {
        StringBuilder sb = new StringBuilder();
        sb.append("city_slug,city_name,country_code,currency,published,property_count,operator_count,"
                + "entry_median,entry_min,entry_max,p25,p75,sample_size,as_of\n");
        for (City city : rows) {
            line(
                    sb,
                    city.getCitySlug(),
                    city.getCityName(),
                    city.getCountryCode(),
                    city.getCurrency(),
                    Boolean.toString(city.isPublished()),
                    text(city.getPropertyCount()),
                    text(city.getOperatorCount()),
                    city.getEntryMedianText(),
                    city.getEntryMinText(),
                    city.getEntryMaxText(),
                    city.getP25Text(),
                    city.getP75Text(),
                    text(city.getSampleSize()),
                    city.getAsOf());
        }
        return sb.toString();
    }

    private static String listingsCsv(List<Listing> rows) {
        StringBuilder sb = new StringBuilder();
        sb.append("slug,title,city_slug,zone_slug,operator_slug,operator_name,country_code,lat,lng,featured,"
                + "market_verdict,market_median,market_sample_size,url,updated_at\n");
        for (Listing row : rows) {
            line(
                    sb,
                    row.getSlug(),
                    row.getTitle(),
                    row.getCitySlug(),
                    row.getZoneSlug(),
                    row.getOperatorSlug(),
                    row.getOperatorName(),
                    row.getCountryCode(),
                    row.getLatText(),
                    row.getLngText(),
                    row.getFeatured() == null ? null : row.getFeatured().toString(),
                    row.getMarketVerdict(),
                    row.getMarketMedianText(),
                    text(row.getMarketSampleSize()),
                    row.getUrl(),
                    row.getUpdatedAt());
        }
        return sb.toString();
    }

    private static String pricingCsv(List<PricingOption> rows) {
        StringBuilder sb = new StringBuilder();
        sb.append("product,title,price,currency,billing_period,price_on_request,min_capacity,max_capacity\n");
        for (PricingOption row : rows) {
            line(
                    sb,
                    row.getProduct().getApiName(),
                    row.getTitle(),
                    row.getPriceText(),
                    row.getCurrency(),
                    row.getBillingPeriod(),
                    Boolean.toString(row.isPriceOnRequest()),
                    text(row.getMinCapacity()),
                    text(row.getMaxCapacity()));
        }
        return sb.toString();
    }

    private static String text(Long value) {
        return value == null ? null : value.toString();
    }

    private static void line(StringBuilder sb, String... cells) {
        for (int i = 0; i < cells.length; i++) {
            if (i > 0) {
                sb.append(',');
            }
            sb.append(escape(cells[i] == null ? "" : cells[i]));
        }
        sb.append('\n');
    }

    private static String escape(String value) {
        if (value.indexOf(',') >= 0 || value.indexOf('"') >= 0 || value.indexOf('\n') >= 0 || value.indexOf('\r') >= 0) {
            return '"' + value.replace("\"", "\"\"") + '"';
        }
        return value;
    }

    private static void assertText(String expected, String actual) {
        if (expected.equals(actual)) {
            return;
        }
        String[] left = expected.split("\n", -1);
        String[] right = actual.split("\n", -1);
        int n = Math.min(left.length, right.length);
        for (int i = 0; i < n; i++) {
            if (!left[i].equals(right[i])) {
                fail("line " + (i + 1) + "\nexpected: " + left[i] + "\nactual:   " + right[i]);
            }
        }
        fail("line count expected " + left.length + " actual " + right.length);
    }

    static String fixture(String name) throws IOException {
        return Files.readString(repo().resolve("spec/fixtures").resolve(name));
    }

    private static String golden(String name) throws IOException {
        return Files.readString(repo().resolve("spec/golden").resolve(name));
    }

    private static Path repo() {
        Path dir = Path.of("").toAbsolutePath();
        for (Path current = dir; current != null; current = current.getParent()) {
            if (Files.isDirectory(current.resolve("spec/fixtures"))) {
                return current;
            }
        }
        throw new IllegalStateException("spec/fixtures not found from " + dir);
    }
}
