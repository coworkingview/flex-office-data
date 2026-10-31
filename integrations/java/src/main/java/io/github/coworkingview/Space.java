package io.github.coworkingview;

import java.util.List;
import java.util.Objects;

/**
 * One space with its address, amenity codes and pricing table.
 *
 * <p>Scalar fields match {@link Listing}, plus {@link #getAddress()}, {@link #getCapacity()}
 * and {@link #getAmenities()}. {@link #getUrl()} is the response's {@code webUrl} when that
 * is a non-empty string, otherwise the listing URL for the locale of the call.
 * Descriptions, photos and logos are not fields of this class.
 */
public final class Space {
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
    private final String address;
    private final Long capacity;
    private final List<String> amenities;
    private final List<PricingOption> pricing;

    Space(
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
            String updatedAt,
            String address,
            Long capacity,
            List<String> amenities,
            List<PricingOption> pricing) {
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
        this.address = address;
        this.capacity = capacity;
        this.amenities = amenities;
        this.pricing = pricing;
    }

    /**
     * Space slug.
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
     * @return the slug, or {@code null} when the API omitted it
     */
    public String getCitySlug() {
        return citySlug;
    }

    /**
     * Neighbourhood slug.
     *
     * @return the slug, or {@code null} when the API omitted it
     */
    public String getZoneSlug() {
        return zoneSlug;
    }

    /**
     * Operator slug.
     *
     * @return the slug, or {@code null} when the API omitted it
     */
    public String getOperatorSlug() {
        return operatorSlug;
    }

    /**
     * Operator display name.
     *
     * @return the name, or {@code null} when the API omitted it
     */
    public String getOperatorName() {
        return operatorName;
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
     * Latitude, WGS 84.
     *
     * @return the latitude, or {@code null} when the API omitted coordinates
     */
    public Double getLat() {
        return Rate.decimal(latText);
    }

    /**
     * Latitude exactly as the API wrote it.
     *
     * @return the token, or {@code null}
     */
    public String getLatText() {
        return latText;
    }

    /**
     * Longitude, WGS 84.
     *
     * @return the longitude, or {@code null} when the API omitted coordinates
     */
    public Double getLng() {
        return Rate.decimal(lngText);
    }

    /**
     * Longitude exactly as the API wrote it.
     *
     * @return the token, or {@code null}
     */
    public String getLngText() {
        return lngText;
    }

    /**
     * Whether CoworkingView features the space.
     *
     * @return the flag, or {@code null} when the API omitted it. {@code null} is not {@code false}
     */
    public Boolean getFeatured() {
        return featured;
    }

    /**
     * Price versus the city median.
     *
     * @return {@code below}, {@code around} or {@code above}, or {@code null} when omitted
     */
    public String getMarketVerdict() {
        return marketVerdict;
    }

    /**
     * City median that {@link #getMarketVerdict()} compares against.
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
     * Price points behind the market median.
     *
     * @return the sample size, or {@code null} when omitted
     */
    public Long getMarketSampleSize() {
        return marketSampleSize;
    }

    /**
     * Listing page. This is {@code webUrl} when the API sent a non-empty one.
     *
     * @return the absolute URL
     */
    public String getUrl() {
        return url;
    }

    /**
     * Last update of the listing.
     *
     * @return an ISO 8601 timestamp, or {@code null} when omitted
     */
    public String getUpdatedAt() {
        return updatedAt;
    }

    /**
     * Street address.
     *
     * @return the address, or {@code null} when omitted
     */
    public String getAddress() {
        return address;
    }

    /**
     * Total capacity in people.
     *
     * @return the integer {@code capacity}, or {@code null} when it is absent or not an integer
     */
    public Long getCapacity() {
        return capacity;
    }

    /**
     * Amenity codes, for example {@code wifi} and {@code meeting_rooms}.
     *
     * @return an unmodifiable list, empty when the API omitted amenities
     */
    public List<String> getAmenities() {
        return amenities;
    }

    /**
     * The pricing table, one row per {@code pricingOptions} item, in the API's order.
     *
     * @return an unmodifiable list, empty when the API omitted pricing options
     */
    public List<PricingOption> getPricing() {
        return pricing;
    }

    @Override
    public boolean equals(Object other) {
        if (!(other instanceof Space)) {
            return false;
        }
        Space that = (Space) other;
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
                && Objects.equals(updatedAt, that.updatedAt)
                && Objects.equals(address, that.address)
                && Objects.equals(capacity, that.capacity)
                && Objects.equals(amenities, that.amenities)
                && Objects.equals(pricing, that.pricing);
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
                updatedAt,
                address,
                capacity,
                amenities,
                pricing);
    }

    @Override
    public String toString() {
        return "Space(" + slug + ", " + title + ", pricing=" + pricing.size() + ")";
    }
}
