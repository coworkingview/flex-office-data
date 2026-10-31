package io.github.coworkingview;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Objects;

/**
 * Filters for {@link Client#rates(RatesQuery)} and {@link Client#cities(RatesQuery)}.
 *
 * <p>The object is mutable and not safe to change while a call is reading it.
 * {@link #product(Product)} is applied locally after the response arrives. It is not an
 * API parameter. {@link Client#cities(RatesQuery)} ignores it. Omit a filter to leave
 * that dimension open: there is no price and no sample invented for a city the API did
 * not return.
 */
public final class RatesQuery {
    private String city;
    private String country;
    private Currency currency;
    private Locale locale;
    private final List<Product> products = new ArrayList<Product>();

    /**
     * Creates a query with no filters and the client's locale.
     */
    public RatesQuery() {}

    /**
     * Only this city (slug), for example {@code berlin}.
     *
     * @param city the slug, or {@code null} to clear the filter
     * @return this query
     * @throws IllegalArgumentException when {@code city} is blank
     */
    public RatesQuery city(String city) {
        this.city = Checks.text("city", city);
        return this;
    }

    /**
     * Only this country (ISO 3166-1 alpha-2), for example {@code DE}.
     *
     * @param country the code, or {@code null} to clear the filter
     * @return this query
     * @throws IllegalArgumentException when {@code country} is blank
     */
    public RatesQuery country(String country) {
        this.country = Checks.text("country", country);
        return this;
    }

    /**
     * Present figures in this currency. The default is each city's own currency.
     *
     * @param currency the currency
     * @return this query
     * @throws NullPointerException when {@code currency} is {@code null}
     */
    public RatesQuery currency(Currency currency) {
        this.currency = Objects.requireNonNull(currency, "currency");
        return this;
    }

    /**
     * Present figures in this currency.
     *
     * @param currency a supported code, case-insensitive
     * @return this query
     * @throws IllegalArgumentException when the code is not supported
     */
    public RatesQuery currency(String currency) {
        this.currency = Currency.parse(currency);
        return this;
    }

    /**
     * Language of city names.
     *
     * @param locale the locale
     * @return this query
     * @throws NullPointerException when {@code locale} is {@code null}
     */
    public RatesQuery locale(Locale locale) {
        this.locale = Objects.requireNonNull(locale, "locale");
        return this;
    }

    /**
     * Language of city names. {@code en}, {@code es} or {@code de}.
     *
     * @param locale the code
     * @return this query
     * @throws IllegalArgumentException when the code is not supported
     */
    public RatesQuery locale(String locale) {
        this.locale = Locale.parse(locale);
        return this;
    }

    /**
     * Keep this product. Call again to keep several. Applied locally, after the request.
     *
     * @param product the product
     * @return this query
     * @throws NullPointerException when {@code product} is {@code null}
     */
    public RatesQuery product(Product product) {
        this.products.add(Objects.requireNonNull(product, "product"));
        return this;
    }

    /**
     * Keep this product. See {@link #product(Product)}.
     *
     * @param product the API spelling, for example {@code flex_desk}
     * @return this query
     * @throws IllegalArgumentException when the name is not a known product
     */
    public RatesQuery product(String product) {
        return product(Product.parse(product));
    }

    /**
     * City slug filter.
     *
     * @return the slug, or {@code null} when the query does not filter by city
     */
    public String getCity() {
        return city;
    }

    /**
     * Country filter.
     *
     * @return the ISO code, or {@code null} when the query does not filter by country
     */
    public String getCountry() {
        return country;
    }

    /**
     * Currency the figures should be presented in.
     *
     * @return the currency, or {@code null} to keep each city's own currency
     */
    public Currency getCurrency() {
        return currency;
    }

    /**
     * Locale override for city names.
     *
     * @return the locale, or {@code null} to use the client's locale
     */
    public Locale getLocale() {
        return locale;
    }

    /**
     * Products to keep. Empty means all products the API returned.
     *
     * @return an unmodifiable view of the products added so far
     */
    public List<Product> getProducts() {
        return Collections.unmodifiableList(products);
    }
}
