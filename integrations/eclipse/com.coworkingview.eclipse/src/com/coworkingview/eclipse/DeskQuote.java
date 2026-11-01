package com.coworkingview.eclipse;

/**
 * One monthly product for one city. Amounts stay as the JSON number tokens.
 * {@code lowText} and {@code highText} are the 25th and 75th percentiles when
 * {@code percentileRange} is true, otherwise the published minimum and maximum.
 */
public record DeskQuote(
        String medianText,
        String lowText,
        String highText,
        boolean percentileRange,
        int sampleSize) {

    public boolean lowConfidence() {
        return sampleSize < 10;
    }
}
