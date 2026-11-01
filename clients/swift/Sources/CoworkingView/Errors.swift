/// An error raised by ``Client`` before a response is accepted.
///
/// Connection failures are this type. HTTP error bodies and unreadable
/// success bodies are the subclass ``APIError``.
public class CoworkingViewError: Error, CustomStringConvertible, @unchecked Sendable {
    /// What went wrong, in one sentence.
    public let message: String

    /// Creates an error with a human-readable message.
    public init(_ message: String) {
        self.message = message
    }

    public var description: String { message }
}

/// One field from an RFC 9457 `errors` array.
public struct FieldError: Codable, Equatable, Hashable, Sendable {
    /// JSON path the API named, when it sent one.
    public let path: String?

    /// What the API said about that field.
    public let message: String?

    public init(path: String?, message: String?) {
        self.path = path
        self.message = message
    }
}

/// The API answered with an error, or with a success body this client cannot read.
///
/// `status` is the HTTP status. `code`, `title` and `detail` come from the
/// problem JSON when the body has them. Otherwise `code` is `HTTP_<status>`
/// and `title` is the HTTP reason.
public final class APIError: CoworkingViewError, @unchecked Sendable {
    /// HTTP status from the response.
    public let status: Int

    /// Machine-readable code, for example `VALIDATION_FAILED` or `BAD_RESPONSE`.
    public let code: String

    /// Short summary.
    public let title: String

    /// Longer explanation, when the API sent one.
    public let detail: String?

    /// Per-field problems. Empty when the body had none.
    public let errors: [FieldError]

    public init(
        status: Int,
        code: String,
        title: String,
        detail: String? = nil,
        errors: [FieldError] = []
    ) {
        self.status = status
        self.code = code
        self.title = title
        self.detail = detail
        self.errors = errors
        var text = "\(status) \(code): \(title)"
        if let detail, !detail.isEmpty {
            text += " (\(detail))"
        }
        super.init(text)
    }
}
