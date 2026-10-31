package io.github.coworkingview;

import java.util.Objects;

/**
 * One entry of an RFC 9457 problem {@code errors} array.
 *
 * <p>Either field may be {@code null} when the API omitted it. This client does not
 * fill in a path or a message the response did not contain.
 */
public final class FieldError {
    private final String path;
    private final String message;

    /**
     * Creates a field error.
     *
     * @param path the parameter the API named, or {@code null}
     * @param message what the API said about it, or {@code null}
     */
    public FieldError(String path, String message) {
        this.path = path;
        this.message = message;
    }

    /**
     * The offending parameter, for example {@code currency}.
     *
     * @return the path, or {@code null} when the API omitted it
     */
    public String getPath() {
        return path;
    }

    /**
     * What is wrong with the parameter.
     *
     * @return the message, or {@code null} when the API omitted it
     */
    public String getMessage() {
        return message;
    }

    @Override
    public boolean equals(Object other) {
        if (!(other instanceof FieldError)) {
            return false;
        }
        FieldError that = (FieldError) other;
        return Objects.equals(path, that.path) && Objects.equals(message, that.message);
    }

    @Override
    public int hashCode() {
        return Objects.hash(path, message);
    }

    @Override
    public String toString() {
        return "FieldError(path=" + path + ", message=" + message + ")";
    }
}
