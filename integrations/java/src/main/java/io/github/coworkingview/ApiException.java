package io.github.coworkingview;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/**
 * The API answered with an error, or with a body that is not the JSON this client expects.
 *
 * <p>The fields mirror the RFC 9457 problem document. {@link #getStatus()} is always the
 * HTTP status of the response, not the {@code status} member of the body. When the body
 * is not a problem document, {@link #getCode()} is {@code HTTP_} followed by the status
 * and {@link #getTitle()} falls back to the reason phrase. A 2xx body that cannot be
 * parsed uses the code {@code BAD_RESPONSE}.
 */
public class ApiException extends CoworkingViewException {
    private final int status;
    private final String code;
    private final String title;
    private final String detail;
    private final String type;
    private final List<FieldError> errors;

    /**
     * Creates an API error.
     *
     * @param status HTTP status code
     * @param code machine-readable problem code, never {@code null}
     * @param title short summary, never {@code null}
     * @param detail longer explanation, or {@code null}
     * @param type the problem {@code type} URI, or {@code null}
     * @param errors per-field errors; copied, never {@code null}
     */
    public ApiException(int status, String code, String title, String detail, String type, List<FieldError> errors) {
        super(message(status, code, title, detail));
        this.status = status;
        this.code = code;
        this.title = title;
        this.detail = detail;
        this.type = type;
        this.errors = Collections.unmodifiableList(new ArrayList<FieldError>(errors));
    }

    private static String message(int status, String code, String title, String detail) {
        String message = status + " " + code + ": " + title;
        if (detail != null && !detail.isEmpty()) {
            message += " (" + detail + ")";
        }
        return message;
    }

    /**
     * HTTP status code, for example {@code 400}, {@code 404} or {@code 429}.
     *
     * @return the status
     */
    public int getStatus() {
        return status;
    }

    /**
     * Machine-readable code, for example {@code VALIDATION_FAILED}, {@code NOT_FOUND}
     * or {@code BAD_RESPONSE}.
     *
     * @return the code, never {@code null}
     */
    public String getCode() {
        return code;
    }

    /**
     * Short human-readable summary.
     *
     * @return the title, never {@code null}
     */
    public String getTitle() {
        return title;
    }

    /**
     * Longer explanation from the problem document.
     *
     * @return the detail, or {@code null} when the API gave none
     */
    public String getDetail() {
        return detail;
    }

    /**
     * The problem {@code type} URI.
     *
     * @return the type, or {@code null} when the API gave none
     */
    public String getType() {
        return type;
    }

    /**
     * Per-field validation errors.
     *
     * @return an unmodifiable list, empty when the API gave none
     */
    public List<FieldError> getErrors() {
        return errors;
    }
}
