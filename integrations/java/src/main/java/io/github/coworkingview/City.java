package io.github.coworkingview;

import java.util.Objects;

/**
 * One city of the Price Index, published or not.
 *
 * <p>Unpublished cities ({@link #isPublished()} {@code false}) have a slug and a name
 * and no price figures: the counts and entry prices are {@code null} even if a future
 * payload carried them. Published cities use only the fields the response included.
 */
public final class City {
    private final String citySlug;
    private final String cityName;
    private final String countryCode;
    private final String currency;
    private final boolean published;
    private final Long propertyCount;
    private final Long operatorCount;
    private final String entryMedianText;
    private final String entryMinText;
    private final String entryMaxText;
    private final String p25Text;
    private final String p75Text;
    private final Long sampleSize;
    private final String asOf;

    City(
            String citySlug,
            String cityName,
            String countryCode,
            String currency,
            boolean published,
            Long propertyCount,
            Long operatorCount,
            String entryMedianText,
            String entryMinText,
            String entryMaxText,
            String p25Text,
            String p75Text,
            Long sampleSize,
            String asOf) {
        this.citySlug = citySlug;
        this.cityName = cityName;
        this.countryCode = countryCode;
        this.currency = currency;
        this.published = published;
        this.propertyCount = propertyCount;
        this.operatorCount = operatorCount;
        this.entryMedianText = entryMedianText;
        this.entryMinText = entryMinText;
        this.entryMaxText = entryMaxText;
        this.p25Text = p25Text;
        this.p75Text = p75Text;
        this.sampleSize = sampleSize;
        this.asOf = asOf;
    }

    /**
     * City slug.
     *
     * @return the slug
     */
    public String getCitySlug() {
        return citySlug;
    }

    /**
     * City name in the requested locale.
     *
     * @return the name
     */
    public String getCityName() {
        return cityName;
    }

    /**
     * ISO 3166-1 alpha-2 country code.
     *
     * @return the code, or {@code null} when the API omitted it
     */
    public String getCountryCode() {
        return countryCode;
    }

    /**
     * Currency of the amounts.
     *
     * @return the code, or {@code null} for an unpublished city that did not name one
     */
    public String getCurrency() {
        return currency;
    }

    /**
     * {@code false} when the city has too little data for published figures.
     *
     * @return whether the city is in {@code cities} rather than {@code unpublished}
     */
    public boolean isPublished() {
        return published;
    }

    /**
     * Spaces with prices in the city.
     *
     * @return the count, or {@code null} when the API omitted it or the city is unpublished
     */
    public Long getPropertyCount() {
        return propertyCount;
    }

    /**
     * Operators with prices in the city.
     *
     * @return the count, or {@code null} when the API omitted it or the city is unpublished
     */
    public Long getOperatorCount() {
        return operatorCount;
    }

    /**
     * Median of each space's cheapest monthly option.
     *
     * @return the median, or {@code null} when the API omitted it
     */
    public Double getEntryMedian() {
        return Rate.decimal(entryMedianText);
    }

    /**
     * {@link #getEntryMedian()} as the API wrote it.
     *
     * @return the token, or {@code null}
     */
    public String getEntryMedianText() {
        return entryMedianText;
    }

    /**
     * Cheapest monthly entry price.
     *
     * @return the price, or {@code null} when the API omitted it
     */
    public Double getEntryMin() {
        return Rate.decimal(entryMinText);
    }

    /**
     * {@link #getEntryMin()} as the API wrote it.
     *
     * @return the token, or {@code null}
     */
    public String getEntryMinText() {
        return entryMinText;
    }

    /**
     * Most expensive monthly entry price.
     *
     * @return the price, or {@code null} when the API omitted it
     */
    public Double getEntryMax() {
        return Rate.decimal(entryMaxText);
    }

    /**
     * {@link #getEntryMax()} as the API wrote it.
     *
     * @return the token, or {@code null}
     */
    public String getEntryMaxText() {
        return entryMaxText;
    }

    /**
     * City-level 25th percentile of entry prices.
     *
     * @return the percentile, or {@code null} when the API omitted it
     */
    public Double getP25() {
        return Rate.decimal(p25Text);
    }

    /**
     * {@link #getP25()} as the API wrote it.
     *
     * @return the token, or {@code null}
     */
    public String getP25Text() {
        return p25Text;
    }

    /**
     * City-level 75th percentile of entry prices.
     *
     * @return the percentile, or {@code null} when the API omitted it
     */
    public Double getP75() {
        return Rate.decimal(p75Text);
    }

    /**
     * {@link #getP75()} as the API wrote it.
     *
     * @return the token, or {@code null}
     */
    public String getP75Text() {
        return p75Text;
    }

    /**
     * City-level number of price points.
     *
     * @return the sample size, or {@code null} for an unpublished city
     */
    public Long getSampleSize() {
        return sampleSize;
    }

    /**
     * When the index was computed, ISO 8601.
     *
     * @return the timestamp, or {@code null} when the response omitted {@code asOf}
     */
    public String getAsOf() {
        return asOf;
    }

    @Override
    public boolean equals(Object other) {
        if (!(other instanceof City)) {
            return false;
        }
        City that = (City) other;
        return published == that.published
                && Objects.equals(citySlug, that.citySlug)
                && Objects.equals(cityName, that.cityName)
                && Objects.equals(countryCode, that.countryCode)
                && Objects.equals(currency, that.currency)
                && Objects.equals(propertyCount, that.propertyCount)
                && Objects.equals(operatorCount, that.operatorCount)
                && Objects.equals(entryMedianText, that.entryMedianText)
                && Objects.equals(entryMinText, that.entryMinText)
                && Objects.equals(entryMaxText, that.entryMaxText)
                && Objects.equals(p25Text, that.p25Text)
                && Objects.equals(p75Text, that.p75Text)
                && Objects.equals(sampleSize, that.sampleSize)
                && Objects.equals(asOf, that.asOf);
    }

    @Override
    public int hashCode() {
        return Objects.hash(
                citySlug,
                cityName,
                countryCode,
                currency,
                published,
                propertyCount,
                operatorCount,
                entryMedianText,
                entryMinText,
                entryMaxText,
                p25Text,
                p75Text,
                sampleSize,
                asOf);
    }

    @Override
    public String toString() {
        return "City(" + citySlug + ", published=" + published + ")";
    }
}
