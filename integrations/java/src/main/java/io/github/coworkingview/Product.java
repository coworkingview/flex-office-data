package io.github.coworkingview;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/**
 * A flexible-office product. The API calls this {@code pricingOptionType} on search
 * and {@code optionType} on a price.
 *
 * <p>{@link #parse(String)} accepts only the products this version knows, spelled
 * exactly as the API spells them. {@link #fromApi(String)} is for responses: a product
 * this version does not know yet is kept as-is, so a new Price Index aggregate shows
 * up without a library release.
 */
public final class Product {
    private static final List<Product> KNOWN = new ArrayList<Product>();

    /** A hot desk in a shared area, billed monthly. */
    public static final Product FLEX_DESK = known("flex_desk");
    /** A dedicated desk, billed monthly. */
    public static final Product FIX_DESK = known("fix_desk");
    /** A lockable private office, billed monthly. */
    public static final Product PRIVATE_OFFICE = known("private_office");
    /** An exclusive area ({@code exclusive_bereich}), billed monthly. */
    public static final Product EXCLUSIVE_BEREICH = known("exclusive_bereich");
    /** A day pass, billed per day. */
    public static final Product DAY_PASS = known("day_pass");
    /** A meeting room, billed per hour. */
    public static final Product MEETING_ROOM = known("meeting_room");
    /** An event space, billed per hour. */
    public static final Product EVENT_SPACE = known("event_space");
    /** A virtual office, billed monthly. */
    public static final Product VIRTUAL_OFFICE = known("virtual_office");
    /** A membership. */
    public static final Product MEMBERSHIP = known("membership");

    private final String apiName;
    private final int index;

    private Product(String apiName, int index) {
        this.apiName = apiName;
        this.index = index;
    }

    private static Product known(String apiName) {
        Product product = new Product(apiName, KNOWN.size());
        KNOWN.add(product);
        return product;
    }

    /**
     * The products this version knows, in Price Index display order.
     *
     * @return an unmodifiable list
     */
    public static List<Product> knownValues() {
        return Collections.unmodifiableList(KNOWN);
    }

    /**
     * The API spelling, for example {@code flex_desk}.
     *
     * @return the name, never {@code null}
     */
    public String getApiName() {
        return apiName;
    }

    /**
     * A short English label, for example {@code Flex desk}.
     *
     * @return the label
     */
    public String getLabel() {
        switch (apiName) {
            case "flex_desk":
                return "Flex desk";
            case "fix_desk":
                return "Fixed desk";
            case "private_office":
                return "Private office";
            case "exclusive_bereich":
                return "Exclusive area";
            case "day_pass":
                return "Day pass";
            case "meeting_room":
                return "Meeting room";
            case "event_space":
                return "Event space";
            case "virtual_office":
                return "Virtual office";
            case "membership":
                return "Membership";
            default:
                if (apiName.isEmpty()) {
                    return apiName;
                }
                String spaced = apiName.replace('_', ' ');
                return Character.toUpperCase(spaced.charAt(0)) + spaced.substring(1);
        }
    }

    /**
     * Parses a product name a caller wants to filter on.
     *
     * @param value the API spelling, for example {@code meeting_room}
     * @return the product
     * @throws IllegalArgumentException when the name is not a known product
     */
    public static Product parse(String value) {
        if (value != null) {
            for (Product product : KNOWN) {
                if (product.apiName.equals(value)) {
                    return product;
                }
            }
        }
        throw new IllegalArgumentException(
                "product='" + value + "' is not supported; use one of " + choices() + ".");
    }

    /**
     * Reads a product name from a response. Unknown names are preserved.
     *
     * @param apiName the {@code optionType} or aggregate name
     * @return the product, never {@code null}
     * @throws IllegalArgumentException when {@code apiName} is {@code null}
     */
    public static Product fromApi(String apiName) {
        if (apiName == null) {
            throw new IllegalArgumentException("product is missing");
        }
        for (Product product : KNOWN) {
            if (product.apiName.equals(apiName)) {
                return product;
            }
        }
        return new Product(apiName, -1);
    }

    /** Known products sort in {@link #knownValues()} order; unknown ones sort after them. */
    int sortIndex() {
        return index >= 0 ? index : Integer.MAX_VALUE;
    }

    private static String choices() {
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < KNOWN.size(); i++) {
            if (i > 0) {
                sb.append(", ");
            }
            sb.append('\'').append(KNOWN.get(i).apiName).append('\'');
        }
        return sb.toString();
    }

    @Override
    public boolean equals(Object other) {
        if (this == other) {
            return true;
        }
        if (!(other instanceof Product)) {
            return false;
        }
        return apiName.equals(((Product) other).apiName);
    }

    @Override
    public int hashCode() {
        return apiName.hashCode();
    }

    @Override
    public String toString() {
        return apiName;
    }
}
