package io.github.coworkingview;

/**
 * Language of city names and of the listing links this client builds.
 *
 * <p>Accepted values are {@code en}, {@code es} and {@code de}, spelled exactly like that.
 * The API default is English.
 */
public enum Locale {
    /** English. Listing links use {@code /en/workspace/}. */
    EN("en", "workspace"),
    /** Spanish. Listing links use {@code /es/oficina/}. */
    ES("es", "oficina"),
    /** German. Listing links use {@code /de/buero/}. */
    DE("de", "buero");

    private final String code;
    private final String workspacePath;

    Locale(String code, String workspacePath) {
        this.code = code;
        this.workspacePath = workspacePath;
    }

    /**
     * The API spelling: {@code en}, {@code es} or {@code de}.
     *
     * @return the code
     */
    public String getCode() {
        return code;
    }

    /** Path segment of a space page on coworkingview.com. */
    String workspacePath() {
        return workspacePath;
    }

    /**
     * Parses {@code en}, {@code es} or {@code de}.
     *
     * @param value the locale code
     * @return the locale
     * @throws IllegalArgumentException when {@code value} is not one of those three spellings
     */
    public static Locale parse(String value) {
        if (value != null) {
            for (Locale locale : values()) {
                if (locale.code.equals(value)) {
                    return locale;
                }
            }
        }
        throw new IllegalArgumentException(
                "locale='" + value + "' is not supported; use one of 'en', 'es', 'de'.");
    }
}
