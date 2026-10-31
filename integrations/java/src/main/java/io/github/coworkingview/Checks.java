package io.github.coworkingview;

import java.util.regex.Pattern;

/** Argument checks. Failures are {@link IllegalArgumentException} and send no request. */
final class Checks {
    static final int MAX_SPACES = 200;
    private static final Pattern SLUG = Pattern.compile("^[A-Za-z0-9][A-Za-z0-9._-]*$");

    private Checks() {}

    static String text(String name, String value) {
        if (value == null) {
            return null;
        }
        String trimmed = value.trim();
        if (trimmed.isEmpty()) {
            throw new IllegalArgumentException(name + " must be a non-empty string, got '" + value + "'.");
        }
        return trimmed;
    }

    static int limit(int value) {
        if (value < 1) {
            throw new IllegalArgumentException("limit must be a positive integer, got " + value + ".");
        }
        if (value > MAX_SPACES) {
            throw new IllegalArgumentException("limit=" + value + " exceeds the maximum of " + MAX_SPACES
                    + ". The catalogue may be searched and linked to, not bulk-copied: its content belongs to"
                    + " the operators and the API's catalogue notice forbids systematic extraction. Narrow the"
                    + " search (city, zone, operator, product, price) instead.");
        }
        return value;
    }

    static Integer count(String name, Integer value) {
        if (value == null) {
            return null;
        }
        if (value < 0) {
            throw new IllegalArgumentException(name + " must be a non-negative integer, got " + value + ".");
        }
        return value;
    }

    static Double price(String name, Double value) {
        if (value == null) {
            return null;
        }
        if (value.isNaN() || value.isInfinite() || value < 0d) {
            throw new IllegalArgumentException(name + " must be a non-negative number, got " + value + ".");
        }
        return value;
    }

    static void priceRange(Double minPrice, Double maxPrice) {
        if (minPrice != null && maxPrice != null && minPrice > maxPrice) {
            throw new IllegalArgumentException(
                    "minPrice (" + decimal(minPrice) + ") is greater than maxPrice (" + decimal(maxPrice) + ").");
        }
    }

    static String slug(String value) {
        if (value == null || !SLUG.matcher(value).matches()) {
            throw new IllegalArgumentException("slug='" + value
                    + "' is not a valid slug; slugs are letters, digits, '.', '_' and '-', starting with a"
                    + " letter or digit (e.g. 'sankt-oberholz-rosenthaler-berlin').");
        }
        return value;
    }

    /** Whole numbers are sent without a fractional part ({@code 10}, not {@code 10.0}). */
    static String decimal(double value) {
        if (value == Math.rint(value) && !Double.isInfinite(value) && Math.abs(value) < 1.0e15d) {
            return Long.toString((long) value);
        }
        return Double.toString(value);
    }
}
