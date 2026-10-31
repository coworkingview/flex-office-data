package io.github.coworkingview;

import java.util.Objects;

/**
 * One Price Index figure: a city and a product.
 *
 * <p>Amounts are the numbers the API sent. {@code getMedian()} is that number as a
 * {@code double}. {@code getMedianText()} is the exact token ({@code 214}, not
 * {@code 214.0}) so a whole price is not given a fractional part the response did not
 * have. A missing percentile is {@code null}. Nothing here is estimated.
 */
public final class Rate {
    private final String citySlug;
    private final String cityName;
    private final String countryCode;
    private final String currency;
    private final Product product;
    private final Unit unit;
    private final String medianText;
    private final String p25Text;
    private final String p75Text;
    private final long sampleSize;
    private final Long propertyCount;
    private final Long operatorCount;
    private final boolean lowConfidence;
    private final String asOf;

    Rate(
            String citySlug,
            String cityName,
            String countryCode,
            String currency,
            Product product,
            Unit unit,
            String medianText,
            String p25Text,
            String p75Text,
            long sampleSize,
            Long propertyCount,
            Long operatorCount,
            String asOf) {
        this.citySlug = citySlug;
        this.cityName = cityName;
        this.countryCode = countryCode;
        this.currency = currency;
        this.product = product;
        this.unit = unit;
        this.medianText = medianText;
        this.p25Text = p25Text;
        this.p75Text = p75Text;
        this.sampleSize = sampleSize;
        this.propertyCount = propertyCount;
        this.operatorCount = operatorCount;
        this.lowConfidence = sampleSize < 10;
        this.asOf = asOf;
    }

    /**
     * City slug, for example {@code berlin}.
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
     * Currency of the amounts, as the API wrote it.
     *
     * @return the currency code
     */
    public String getCurrency() {
        return currency;
    }

    /**
     * The product.
     *
     * @return the product
     */
    public Product getProduct() {
        return product;
    }

    /**
     * What one price buys.
     *
     * @return the unit, or {@code null} for an aggregate this client has no unit for
     */
    public Unit getUnit() {
        return unit;
    }

    /**
     * Median price.
     *
     * @return the median, or {@code null} when {@code median} was absent
     */
    public Double getMedian() {
        return decimal(medianText);
    }

    /**
     * Median exactly as the API wrote it.
     *
     * @return the token, or {@code null} when {@code median} was absent
     */
    public String getMedianText() {
        return medianText;
    }

    /**
     * 25th percentile.
     *
     * @return the percentile, or {@code null} when the API did not publish it
     */
    public Double getP25() {
        return decimal(p25Text);
    }

    /**
     * 25th percentile exactly as the API wrote it.
     *
     * @return the token, or {@code null} when the API did not publish it
     */
    public String getP25Text() {
        return p25Text;
    }

    /**
     * 75th percentile.
     *
     * @return the percentile, or {@code null} when the API did not publish it
     */
    public Double getP75() {
        return decimal(p75Text);
    }

    /**
     * 75th percentile exactly as the API wrote it.
     *
     * @return the token, or {@code null} when the API did not publish it
     */
    public String getP75Text() {
        return p75Text;
    }

    /**
     * Number of price points behind the figure.
     *
     * @return the sample size
     */
    public long getSampleSize() {
        return sampleSize;
    }

    /**
     * Spaces behind the figure.
     *
     * @return the count, or {@code null} when the API omitted it
     */
    public Long getPropertyCount() {
        return propertyCount;
    }

    /**
     * Operators behind the figure.
     *
     * @return the count, or {@code null} when the API omitted it
     */
    public Long getOperatorCount() {
        return operatorCount;
    }

    /**
     * {@code true} when fewer than 10 price points are behind the figure.
     * Treat the row as indicative. This is derived from {@link #getSampleSize()},
     * not copied from a separate API field.
     *
     * @return whether the sample is small
     */
    public boolean isLowConfidence() {
        return lowConfidence;
    }

    /**
     * When the index was computed, ISO 8601.
     *
     * @return the timestamp, or {@code null} when the response omitted {@code asOf}
     */
    public String getAsOf() {
        return asOf;
    }

    static Double decimal(String text) {
        return text == null ? null : Double.valueOf(text);
    }

    @Override
    public boolean equals(Object other) {
        if (!(other instanceof Rate)) {
            return false;
        }
        Rate that = (Rate) other;
        return sampleSize == that.sampleSize
                && lowConfidence == that.lowConfidence
                && Objects.equals(citySlug, that.citySlug)
                && Objects.equals(cityName, that.cityName)
                && Objects.equals(countryCode, that.countryCode)
                && Objects.equals(currency, that.currency)
                && Objects.equals(product, that.product)
                && unit == that.unit
                && Objects.equals(medianText, that.medianText)
                && Objects.equals(p25Text, that.p25Text)
                && Objects.equals(p75Text, that.p75Text)
                && Objects.equals(propertyCount, that.propertyCount)
                && Objects.equals(operatorCount, that.operatorCount)
                && Objects.equals(asOf, that.asOf);
    }

    @Override
    public int hashCode() {
        return Objects.hash(
                citySlug,
                cityName,
                countryCode,
                currency,
                product,
                unit,
                medianText,
                p25Text,
                p75Text,
                sampleSize,
                propertyCount,
                operatorCount,
                lowConfidence,
                asOf);
    }

    @Override
    public String toString() {
        return "Rate(" + citySlug + " " + product + " " + medianText + " " + currency + ")";
    }
}
