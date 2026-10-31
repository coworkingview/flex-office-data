package io.github.coworkingview;

import java.util.Objects;

/**
 * One space in a catalogue search.
 *
 * <p>Descriptions, photos and logos are not copied off the response. Pass
 * {@link #getSlug()} to {@link Client#space(String)} for the address and the pricing table.
 * {@link #getUrl()} is the public listing page for the locale of the search.
 */
public final class Listing {
    private final String slug;
    private final String title;
    private final String citySlug;
    private final String zoneSlug;
    private final String operatorSlug;
    private final String operatorName;
    private final String countryCode;
    private final String latText;
    private final String lngText;
    private final Boolean featured;
    private final String marketVerdict;
    private final String marketMedianText;
    private final Long marketSampleSize;
    private final String url;
    private final String updatedAt;

    Listing(
            String slug,
            String title,
            String citySlug,
            String zoneSlug,
            String operatorSlug,
            String operatorName,
            String countryCode,
            String latText,
            String lngText,
            Boolean featured,
            String marketVerdict,
            String marketMedianText,
            Long marketSampleSize,
            String url,
            String updatedAt) {
        this.slug = slug;
        this.title = title;
        this.citySlug = citySlug;
        this.zoneSlug = zoneSlug;
        this.operatorSlug = operatorSlug;
        this.operatorName = operatorName;
        this.countryCode = countryCode;
        this.latText = latText;
        this.lngText = lngText;
        this.featured = featured;
        this.marketVerdict = marketVerdict;
        this.marketMedianText = marketMedianText;
        this.marketSampleSize = marketSampleSize;
        this.url = url;
        this.updatedAt = updatedAt;
    }

    /**
     * Stable identifier. Pass it to {@link Client#space(String)}.
     *
     * @return the slug
     */
    public String getSlug() {
        return slug;
    }

    /**
     * Name of the space.
     *
     * @return the title
     */
    public String getTitle() {
        return title;
    }

    /**
     * City slug.
     *
     * @return the slug, or {@code null} when the card has no city
     */
    public String getCitySlug() {
        return citySlug;
    }

    /**
     * Neighbourhood slug.
     *
     * @return the slug, or {@code null} when the card has no zone
     */
    public String getZoneSlug() {
        return zoneSlug;
    }

    /**
     * Operator slug.
     *
     * @return the slug, or {@code null} when the card has no operator
     */
    public String getOperatorSlug() {
        return operatorSlug;
    }

    /**
     * Operator display name.
     *
     * @return the name, or {@code null} when the card has no operator
     */
    public String getOperatorName() {
        return operatorName;
    }

    /**
     * ISO 3166-1 alpha-2 country code.
     *
     * @return the code, or {@code null} when omitted
     */
    public String getCountryCode() {
        return countryCode;
    }

    /**
     * Latitude, WGS 84.
     *
     * @return the latitude, or {@code null} when the card has no coordinates
     */
    public Double getLat() {
        return Rate.decimal(latText);
    }

    /**
     * {@link #getLat()} as the API wrote it.
     *
     * @return the token, or {@code null}
     */
    public String getLatText() {
        return latText;
    }

    /**
     * Longitude, WGS 84.
     *
     * @return the longitude, or {@code null} when the card has no coordinates
     */
    public Double getLng() {
        return Rate.decimal(lngText);
    }

    /**
     * {@link #getLng()} as the API wrote it.
     *
     * @return the token, or {@code null}
     */
    public String getLngText() {
        return lngText;
    }

    /**
     * Whether CoworkingView features the space.
     *
     * @return the flag, or {@code null} when the card omitted it. {@code null} is not {@code false}
     */
    public Boolean getFeatured() {
        return featured;
    }

    /**
     * Price versus the city median: {@code below}, {@code around} or {@code above}.
     *
     * @return the verdict, or {@code null} when the card has no market position
     */
    public String getMarketVerdict() {
        return marketVerdict;
    }

    /**
     * The city median that {@link #getMarketVerdict()} compares against.
     *
     * @return the median, or {@code null} when omitted
     */
    public Double getMarketMedian() {
        return Rate.decimal(marketMedianText);
    }

    /**
     * {@link #getMarketMedian()} as the API wrote it.
     *
     * @return the token, or {@code null}
     */
    public String getMarketMedianText() {
        return marketMedianText;
    }

    /**
     * Price points behind {@link #getMarketMedian()}.
     *
     * @return the sample size, or {@code null} when omitted
     */
    public Long getMarketSampleSize() {
        return marketSampleSize;
    }

    /**
     * Listing page on coworkingview.com.
     *
     * @return the absolute URL
     */
    public String getUrl() {
        return url;
    }

    /**
     * Last update of the listing, ISO 8601.
     *
     * @return the timestamp, or {@code null} when omitted
     */
    public String getUpdatedAt() {
        return updatedAt;
    }

    @Override
    public boolean equals(Object other) {
        if (!(other instanceof Listing)) {
            return false;
        }
        Listing that = (Listing) other;
        return Objects.equals(slug, that.slug)
                && Objects.equals(title, that.title)
                && Objects.equals(citySlug, that.citySlug)
                && Objects.equals(zoneSlug, that.zoneSlug)
                && Objects.equals(operatorSlug, that.operatorSlug)
                && Objects.equals(operatorName, that.operatorName)
                && Objects.equals(countryCode, that.countryCode)
                && Objects.equals(latText, that.latText)
                && Objects.equals(lngText, that.lngText)
                && Objects.equals(featured, that.featured)
                && Objects.equals(marketVerdict, that.marketVerdict)
                && Objects.equals(marketMedianText, that.marketMedianText)
                && Objects.equals(marketSampleSize, that.marketSampleSize)
                && Objects.equals(url, that.url)
                && Objects.equals(updatedAt, that.updatedAt);
    }

    @Override
    public int hashCode() {
        return Objects.hash(
                slug,
                title,
                citySlug,
                zoneSlug,
                operatorSlug,
                operatorName,
                countryCode,
                latText,
                lngText,
                featured,
                marketVerdict,
                marketMedianText,
                marketSampleSize,
                url,
                updatedAt);
    }

    @Override
    public String toString() {
        return "Listing(" + slug + ", " + title + ")";
    }
}
