package io.github.coworkingview;

/**
 * Order of catalogue search results. The API parameter is {@code sortBy}.
 *
 * <p>The default is {@link #RANDOM}. With random order, a search that needs more than
 * one page reuses the seed from the first page, so pages do not overlap.
 */
public enum Sort {
    /** Seeded random order. This is the API default. */
    RANDOM("random"),
    /** Cheapest published price first. */
    PRICE_ASC("price-asc"),
    /** Most recently updated first. */
    DATE_DESC("date-desc"),
    /** Least recently updated first. */
    DATE_ASC("date-asc");

    private final String apiName;

    Sort(String apiName) {
        this.apiName = apiName;
    }

    /**
     * The API spelling, for example {@code price-asc}.
     *
     * @return the name
     */
    public String getApiName() {
        return apiName;
    }

    /**
     * Parses {@code random}, {@code price-asc}, {@code date-desc} or {@code date-asc}.
     *
     * @param value the API spelling
     * @return the sort
     * @throws IllegalArgumentException when {@code value} is not one of those spellings
     */
    public static Sort parse(String value) {
        if (value != null) {
            for (Sort sort : values()) {
                if (sort.apiName.equals(value)) {
                    return sort;
                }
            }
        }
        throw new IllegalArgumentException("sort='" + value
                + "' is not supported; use one of 'random', 'price-asc', 'date-desc', 'date-asc'.");
    }
}
