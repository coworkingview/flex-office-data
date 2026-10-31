package io.github.coworkingview;

/**
 * Currency the API can present prices in.
 *
 * <p>{@code VES} is accepted and sent as-is. The API answers 400 for cities it cannot
 * convert. Any other code is rejected before a request is sent. Parsing is
 * case-insensitive: {@code eur} and {@code EUR} are the same value.
 */
public final class Currency {
    /** Euro. */
    public static final Currency EUR = new Currency("EUR");
    /** Pound sterling. */
    public static final Currency GBP = new Currency("GBP");
    /** US dollar. */
    public static final Currency USD = new Currency("USD");
    /** Swiss franc. */
    public static final Currency CHF = new Currency("CHF");
    /** UAE dirham. */
    public static final Currency AED = new Currency("AED");
    /**
     * Venezuelan bolívar. Passed through to the API, which rejects it where it has
     * no conversion rate.
     */
    public static final Currency VES = new Currency("VES");

    private static final Currency[] ALL = {EUR, GBP, USD, CHF, AED, VES};

    private final String code;

    private Currency(String code) {
        this.code = code;
    }

    /**
     * ISO 4217 code, for example {@code EUR}.
     *
     * @return the code
     */
    public String getCode() {
        return code;
    }

    /**
     * Parses a supported currency code.
     *
     * @param value the code, case-insensitive
     * @return the currency
     * @throws IllegalArgumentException when the code is not supported
     */
    public static Currency parse(String value) {
        String code = value == null ? null : value.toUpperCase(java.util.Locale.ROOT);
        if (code != null) {
            for (Currency currency : ALL) {
                if (currency.code.equals(code)) {
                    return currency;
                }
            }
        }
        throw new IllegalArgumentException("currency='" + code + "' is not supported; use one of "
                + "'EUR', 'GBP', 'USD', 'CHF', 'AED', 'VES'.");
    }

    @Override
    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof Currency)) {
            return false;
        }
        return code.equals(((Currency) other).code);
    }

    @Override
    public int hashCode() {
        return code.hashCode();
    }

    @Override
    public String toString() {
        return code;
    }
}
