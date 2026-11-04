package com.coworkingview.openrefine;

/** A price-index lookup that should be shown to the user as a GREL error. */
final class PriceIndexException extends Exception {
    private static final long serialVersionUID = 1L;

    PriceIndexException(String message) {
        super(message);
    }
}
