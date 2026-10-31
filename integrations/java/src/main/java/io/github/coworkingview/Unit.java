package io.github.coworkingview;

/**
 * What one Price Index figure buys: a month, a day or an hour.
 *
 * <p>Monthly products ({@code flex_desk}, {@code fix_desk}, {@code private_office}, and
 * the other rows taken from {@code figures} or {@code byType}) use {@link #MONTH}.
 * Aggregates use {@link #DAY} for {@code day_pass}, {@link #HOUR} for {@code meeting_room}
 * and {@code event_space}, and {@link #MONTH} for {@code virtual_office}. Anything else
 * has no unit: the field is left {@code null} rather than guessed.
 */
public enum Unit {
    /** Per month. */
    MONTH("month"),
    /** Per day. */
    DAY("day"),
    /** Per hour. */
    HOUR("hour");

    private final String apiName;

    Unit(String apiName) {
        this.apiName = apiName;
    }

    /**
     * {@code month}, {@code day} or {@code hour}.
     *
     * @return the name
     */
    public String getApiName() {
        return apiName;
    }

    static Unit forAggregate(Product product) {
        switch (product.getApiName()) {
            case "day_pass":
                return DAY;
            case "meeting_room":
            case "event_space":
                return HOUR;
            case "virtual_office":
                return MONTH;
            default:
                return null;
        }
    }
}
