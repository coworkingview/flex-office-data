package com.coworkingview.eclipse;

import java.math.BigDecimal;
import java.text.DecimalFormat;
import java.text.NumberFormat;
import java.util.Locale;

/** Turns a {@link DeskQuote} into the cell text and the hover text. */
public final class PriceText {

    private PriceText() {
    }

    public static String range(DeskQuote quote, Locale locale) {
        if (quote == null) {
            return "\u2014";
        }
        String low = format(quote.lowText(), locale);
        String high = format(quote.highText(), locale);
        String median = format(quote.medianText(), locale);
        String body;
        if (low != null && high != null) {
            body = low.equals(high) ? low : low + "\u2013" + high;
        } else if (median != null) {
            body = median;
        } else {
            body = low != null ? low : high;
        }
        if (body == null) {
            return "\u2014";
        }
        if (quote.lowConfidence()) {
            body = body + "*";
        }
        return body;
    }

    public static String tooltip(DeskQuote quote, String currency, Locale locale) {
        if (quote == null) {
            return "Not published for this city";
        }
        StringBuilder text = new StringBuilder();
        String median = format(quote.medianText(), locale);
        if (median != null) {
            text.append("Median ").append(median);
            if (currency != null && !currency.isBlank()) {
                text.append(' ').append(currency);
            }
            text.append(" per month");
        }
        if (quote.lowText() != null && quote.highText() != null) {
            if (text.length() > 0) {
                text.append(". ");
            }
            text.append(quote.percentileRange() ? "25th–75th percentile " : "Minimum–maximum ");
            text.append(format(quote.lowText(), locale)).append('\u2013').append(format(quote.highText(), locale));
        } else if (median != null) {
            text.append(". Percentiles were not published");
        }
        if (text.length() > 0) {
            text.append(". ");
        }
        text.append("n=").append(quote.sampleSize());
        if (quote.lowConfidence()) {
            text.append(". Fewer than 10 prices");
        }
        return text.toString();
    }

    static String format(String token, Locale locale) {
        if (token == null || token.isBlank()) {
            return null;
        }
        BigDecimal value;
        try {
            value = new BigDecimal(token).stripTrailingZeros();
        } catch (NumberFormatException exception) {
            return token;
        }
        DecimalFormat format = (DecimalFormat) NumberFormat.getNumberInstance(locale);
        format.setGroupingUsed(true);
        int scale = Math.max(value.scale(), 0);
        format.setMaximumFractionDigits(Math.min(scale, 2));
        format.setMinimumFractionDigits(0);
        return format.format(value);
    }
}
