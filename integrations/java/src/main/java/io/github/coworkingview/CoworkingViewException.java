package io.github.coworkingview;

/**
 * Base exception for this client.
 *
 * <p>Network failures (DNS, connection refused, timeout) are thrown as this class.
 * An HTTP response that is not a success, or a success body that is not the JSON
 * this client expects, is thrown as {@link ApiException}. Invalid arguments are
 * {@link IllegalArgumentException} and are raised before any request is sent.
 */
public class CoworkingViewException extends RuntimeException {
    /**
     * Creates an exception with a message.
     *
     * @param message what went wrong
     */
    public CoworkingViewException(String message) {
        super(message);
    }

    /**
     * Creates an exception with a message and a cause.
     *
     * @param message what went wrong
     * @param cause the underlying failure
     */
    public CoworkingViewException(String message, Throwable cause) {
        super(message, cause);
    }
}
