package io.github.coworkingview;

import java.util.Objects;

/**
 * Filters for {@link Client#spaces(SpacesQuery)}.
 *
 * <p>A fresh query asks for 50 spaces in random order. {@link #limit(int)} accepts 1 to
 * {@link Client#MAX_SPACES}. The object is mutable and not safe to change while a call
 * is reading it.
 */
public final class SpacesQuery {
    private String city;
    private String country;
    private String zone;
    private String operator;
    private Product product;
    private Integer minCapacity;
    private Double minPrice;
    private Double maxPrice;
    private Currency currency;
    private Sort sort = Sort.RANDOM;
    private Long seed;
    private Locale locale;
    private int limit = Client.DEFAULT_SPACES_LIMIT;

    /**
     * Creates a query for 50 spaces in random order.
     */
    public SpacesQuery() {}

    /**
     * Only this city (slug).
     *
     * @param city the slug, or {@code null} to clear the filter
     * @return this query
     * @throws IllegalArgumentException when {@code city} is blank
     */
    public SpacesQuery city(String city) {
        this.city = Checks.text("city", city);
        return this;
    }

    /**
     * Only this country (ISO 3166-1 alpha-2).
     *
     * @param country the code, or {@code null} to clear the filter
     * @return this query
     * @throws IllegalArgumentException when {@code country} is blank
     */
    public SpacesQuery country(String country) {
        this.country = Checks.text("country", country);
        return this;
    }

    /**
     * Only this neighbourhood (slug), for example {@code mitte}.
     *
     * @param zone the slug, or {@code null} to clear the filter
     * @return this query
     * @throws IllegalArgumentException when {@code zone} is blank
     */
    public SpacesQuery zone(String zone) {
        this.zone = Checks.text("zone", zone);
        return this;
    }

    /**
     * Only this operator (slug), for example {@code regus}.
     *
     * @param operator the slug, or {@code null} to clear the filter
     * @return this query
     * @throws IllegalArgumentException when {@code operator} is blank
     */
    public SpacesQuery operator(String operator) {
        this.operator = Checks.text("operator", operator);
        return this;
    }

    /**
     * Only spaces offering this product. Sent as {@code pricingOptionType}.
     *
     * @param product the product
     * @return this query
     * @throws NullPointerException when {@code product} is {@code null}
     */
    public SpacesQuery product(Product product) {
        this.product = Objects.requireNonNull(product, "product");
        return this;
    }

    /**
     * Only spaces offering this product.
     *
     * @param product the API spelling, for example {@code meeting_room}
     * @return this query
     * @throws IllegalArgumentException when the name is not a known product
     */
    public SpacesQuery product(String product) {
        return product(Product.parse(product));
    }

    /**
     * Only spaces with an offer for at least this many people.
     *
     * @param people the minimum, or {@code null} to clear the filter
     * @return this query
     * @throws IllegalArgumentException when {@code people} is negative
     */
    public SpacesQuery minCapacity(Integer people) {
        this.minCapacity = Checks.count("minCapacity", people);
        return this;
    }

    /**
     * Lowest price, in {@link #currency(Currency)} when that is set.
     *
     * @param minPrice the bound, or {@code null} to clear it
     * @return this query
     * @throws IllegalArgumentException when the price is negative or the range is empty
     */
    public SpacesQuery minPrice(Double minPrice) {
        this.minPrice = Checks.price("minPrice", minPrice);
        Checks.priceRange(this.minPrice, this.maxPrice);
        return this;
    }

    /**
     * Highest price, in {@link #currency(Currency)} when that is set.
     *
     * @param maxPrice the bound, or {@code null} to clear it
     * @return this query
     * @throws IllegalArgumentException when the price is negative or the range is empty
     */
    public SpacesQuery maxPrice(Double maxPrice) {
        this.maxPrice = Checks.price("maxPrice", maxPrice);
        Checks.priceRange(this.minPrice, this.maxPrice);
        return this;
    }

    /**
     * Currency of {@link #minPrice(Double)} and {@link #maxPrice(Double)}.
     *
     * @param currency the currency
     * @return this query
     * @throws NullPointerException when {@code currency} is {@code null}
     */
    public SpacesQuery currency(Currency currency) {
        this.currency = Objects.requireNonNull(currency, "currency");
        return this;
    }

    /**
     * Currency of the price bounds.
     *
     * @param currency a supported code, case-insensitive
     * @return this query
     * @throws IllegalArgumentException when the code is not supported
     */
    public SpacesQuery currency(String currency) {
        this.currency = Currency.parse(currency);
        return this;
    }

    /**
     * Result order. The default is {@link Sort#RANDOM}.
     *
     * @param sort the order
     * @return this query
     * @throws NullPointerException when {@code sort} is {@code null}
     */
    public SpacesQuery sort(Sort sort) {
        this.sort = Objects.requireNonNull(sort, "sort");
        return this;
    }

    /**
     * Result order.
     *
     * @param sort {@code random}, {@code price-asc}, {@code date-desc} or {@code date-asc}
     * @return this query
     * @throws IllegalArgumentException when the spelling is not supported
     */
    public SpacesQuery sort(String sort) {
        this.sort = Sort.parse(sort);
        return this;
    }

    /**
     * Seed for random order, to ask for the same order again. Sent on every page.
     *
     * @param seed the seed
     * @return this query
     */
    public SpacesQuery seed(long seed) {
        this.seed = Long.valueOf(seed);
        return this;
    }

    /**
     * Locale of the links built for each row. The default is the client's locale.
     *
     * @param locale the locale
     * @return this query
     * @throws NullPointerException when {@code locale} is {@code null}
     */
    public SpacesQuery locale(Locale locale) {
        this.locale = Objects.requireNonNull(locale, "locale");
        return this;
    }

    /**
     * Locale of the links. {@code en}, {@code es} or {@code de}.
     *
     * @param locale the code
     * @return this query
     * @throws IllegalArgumentException when the code is not supported
     */
    public SpacesQuery locale(String locale) {
        this.locale = Locale.parse(locale);
        return this;
    }

    /**
     * Most rows to return. The default is {@value Client#DEFAULT_SPACES_LIMIT}. The
     * maximum is {@value Client#MAX_SPACES}.
     *
     * @param limit the cap, from 1 to 200
     * @return this query
     * @throws IllegalArgumentException when {@code limit} is outside that range
     */
    public SpacesQuery limit(int limit) {
        this.limit = Checks.limit(limit);
        return this;
    }

    /**
     * City slug filter.
     *
     * @return the slug, or {@code null} when unset
     */
    public String getCity() {
        return city;
    }

    /**
     * Country filter.
     *
     * @return the ISO code, or {@code null} when unset
     */
    public String getCountry() {
        return country;
    }

    /**
     * Neighbourhood slug filter.
     *
     * @return the slug, or {@code null} when unset
     */
    public String getZone() {
        return zone;
    }

    /**
     * Operator slug filter.
     *
     * @return the slug, or {@code null} when unset
     */
    public String getOperator() {
        return operator;
    }

    /**
     * Product filter, sent as {@code pricingOptionType}.
     *
     * @return the product, or {@code null} when unset
     */
    public Product getProduct() {
        return product;
    }

    /**
     * Minimum capacity filter.
     *
     * @return the number of people, or {@code null} when unset
     */
    public Integer getMinCapacity() {
        return minCapacity;
    }

    /**
     * Lower price bound.
     *
     * @return the price, or {@code null} when unset
     */
    public Double getMinPrice() {
        return minPrice;
    }

    /**
     * Upper price bound.
     *
     * @return the price, or {@code null} when unset
     */
    public Double getMaxPrice() {
        return maxPrice;
    }

    /**
     * Currency of the price bounds.
     *
     * @return the currency, or {@code null} when unset
     */
    public Currency getCurrency() {
        return currency;
    }

    /**
     * Result order.
     *
     * @return the sort, never {@code null} ({@link Sort#RANDOM} by default)
     */
    public Sort getSort() {
        return sort;
    }

    /**
     * Caller-supplied random seed.
     *
     * @return the seed, or {@code null} when the client should take the API's seed
     */
    public Long getSeed() {
        return seed;
    }

    /**
     * Locale of the listing links.
     *
     * @return the locale, or {@code null} to use the client's locale
     */
    public Locale getLocale() {
        return locale;
    }

    /**
     * Most rows to return.
     *
     * @return the cap, from 1 to {@value Client#MAX_SPACES}
     */
    public int getLimit() {
        return limit;
    }
}
