package com.coworkingview.eclipse;

/**
 * A failed Price Index read. {@code code} is {@code BAD_RESPONSE}, {@code CONNECTION},
 * an HTTP status such as {@code HTTP_400}, or {@code SNAPSHOT}.
 */
public final class RatesException extends Exception {

    private static final long serialVersionUID = 1L;

    private final String code;

    public RatesException(String code, String message) {
        super(message);
        this.code = code;
    }

    public String code() {
        return code;
    }
}
