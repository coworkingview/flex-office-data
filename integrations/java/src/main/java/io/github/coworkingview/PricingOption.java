package io.github.coworkingview;

import java.util.Objects;

/**
 * One published offer of a space.
 *
 * <p>When {@link #isPriceOnRequest()} is {@code true} the API usually omits {@code price}.
 * {@link #getPrice()} and {@link #getCurrency()} are then {@code null}. This client does
 * not substitute a zero or a currency.
 */
public final class PricingOption {
    private final Product product;
    private final String title;
    private final String priceText;
    private final String currency;
    private final String billingPeriod;
    private final boolean priceOnRequest;
    private final Long minCapacity;
    private final Long maxCapacity;

    PricingOption(
            Product product,
            String title,
            String priceText,
            String currency,
            String billingPeriod,
            boolean priceOnRequest,
            Long minCapacity,
            Long maxCapacity) {
        this.product = product;
        this.title = title;
        this.priceText = priceText;
        this.currency = currency;
        this.billingPeriod = billingPeriod;
        this.priceOnRequest = priceOnRequest;
        this.minCapacity = minCapacity;
        this.maxCapacity = maxCapacity;
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
     * The operator's name for the offer.
     *
     * @return the title
     */
    public String getTitle() {
        return title;
    }

    /**
     * Price of the offer.
     *
     * @return the price, or {@code null} when it is on request or the API omitted {@code price}
     */
    public Double getPrice() {
        return Rate.decimal(priceText);
    }

    /**
     * {@link #getPrice()} as the API wrote it.
     *
     * @return the token, or {@code null}
     */
    public String getPriceText() {
        return priceText;
    }

    /**
     * Currency of {@link #getPrice()}.
     *
     * @return the code, or {@code null} when the API omitted {@code price} or its currency
     */
    public String getCurrency() {
        return currency;
    }

    /**
     * Billing period as the API states it, for example {@code month}, {@code day} or {@code once}.
     *
     * @return the period
     */
    public String getBillingPeriod() {
        return billingPeriod;
    }

    /**
     * Whether the operator quotes the price on request.
     *
     * @return the flag from {@code priceOnRequest}
     */
    public boolean isPriceOnRequest() {
        return priceOnRequest;
    }

    /**
     * Minimum people, when the operator stated one.
     *
     * @return the capacity, or {@code null} when omitted
     */
    public Long getMinCapacity() {
        return minCapacity;
    }

    /**
     * Maximum people, when the operator stated one.
     *
     * @return the capacity, or {@code null} when omitted
     */
    public Long getMaxCapacity() {
        return maxCapacity;
    }

    @Override
    public boolean equals(Object other) {
        if (!(other instanceof PricingOption)) {
            return false;
        }
        PricingOption that = (PricingOption) other;
        return priceOnRequest == that.priceOnRequest
                && Objects.equals(product, that.product)
                && Objects.equals(title, that.title)
                && Objects.equals(priceText, that.priceText)
                && Objects.equals(currency, that.currency)
                && Objects.equals(billingPeriod, that.billingPeriod)
                && Objects.equals(minCapacity, that.minCapacity)
                && Objects.equals(maxCapacity, that.maxCapacity);
    }

    @Override
    public int hashCode() {
        return Objects.hash(product, title, priceText, currency, billingPeriod, priceOnRequest, minCapacity, maxCapacity);
    }

    @Override
    public String toString() {
        return "PricingOption(" + product + " " + priceText + " " + currency + " " + billingPeriod + ")";
    }
}
