//! The error type returned by [`Client`](crate::Client) and the parsers.

use std::fmt;

/// Convenience alias for `Result<T, coworkingview::Error>`.
pub type Result<T, E = Error> = std::result::Result<T, E>;

/// Everything that can go wrong talking to the API.
#[derive(Debug, thiserror::Error)]
#[non_exhaustive]
pub enum Error {
    /// The API answered with a non-2xx status (after the single retry for
    /// `429`/`5xx`). Carries the RFC 9457 problem details.
    #[error(transparent)]
    Api(Box<ApiError>),

    /// The API could not be reached: DNS, TLS, connection or timeout.
    #[error("could not reach {url}: {source}")]
    Network {
        /// The URL that was requested.
        url: String,
        /// The underlying transport error.
        #[source]
        source: Box<dyn std::error::Error + Send + Sync + 'static>,
    },

    /// A 2xx response whose body is not the JSON this crate expects
    /// (problem `code` `BAD_RESPONSE`).
    #[error("unexpected response from the API (HTTP {status}): {detail}")]
    BadResponse {
        /// HTTP status of the response.
        status: u16,
        /// What was wrong with it.
        detail: String,
    },

    /// A space slug that does not match `^[A-Za-z0-9][A-Za-z0-9._-]*$`.
    /// Rejected before any request is made (code `INVALID_SLUG`).
    #[error("invalid slug {0:?}: use letters, digits, '.', '_' and '-' (as printed by a search)")]
    InvalidSlug(String),
}

impl From<ApiError> for Error {
    fn from(e: ApiError) -> Self {
        Error::Api(Box::new(e))
    }
}

impl Error {
    /// A stable, machine-readable code: the problem `code` for
    /// [`Error::Api`], `"BAD_RESPONSE"` or `"NETWORK_ERROR"` otherwise.
    pub fn code(&self) -> &str {
        match self {
            Error::Api(e) => &e.code,
            Error::BadResponse { .. } => "BAD_RESPONSE",
            Error::Network { .. } => "NETWORK_ERROR",
            Error::InvalidSlug(_) => "INVALID_SLUG",
        }
    }

    /// The HTTP status, when a response was received.
    pub fn status(&self) -> Option<u16> {
        match self {
            Error::Api(e) => Some(e.status),
            Error::BadResponse { status, .. } => Some(*status),
            Error::Network { .. } | Error::InvalidSlug(_) => None,
        }
    }

    pub(crate) fn bad(status: u16, detail: impl Into<String>) -> Self {
        Error::BadResponse {
            status,
            detail: detail.into(),
        }
    }
}

/// An RFC 9457 problem returned by the API, e.g.
/// `400 VALIDATION_FAILED: currency "VES" has no approximate rate…`.
#[derive(Debug, Clone, PartialEq, Eq)]
#[non_exhaustive]
pub struct ApiError {
    /// HTTP status code.
    pub status: u16,
    /// Machine-readable problem code, e.g. `"VALIDATION_FAILED"`. When the
    /// body is not a problem document this is `"HTTP_<status>"`.
    pub code: String,
    /// Short summary (falls back to the HTTP reason phrase).
    pub title: String,
    /// Human-readable explanation, when given.
    pub detail: Option<String>,
    /// The problem `type` URI, when given.
    pub problem_type: Option<String>,
    /// Per-field validation messages, when given.
    pub errors: Vec<FieldError>,
}

/// One entry of a problem's `errors` array.
#[derive(Debug, Clone, PartialEq, Eq)]
#[non_exhaustive]
pub struct FieldError {
    /// The offending parameter, e.g. `"currency"`.
    pub path: String,
    /// What is wrong with it.
    pub message: String,
}

impl fmt::Display for ApiError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{} (HTTP {}, {})", self.title, self.status, self.code)?;
        if let Some(d) = &self.detail {
            write!(f, ": {d}")?;
        }
        Ok(())
    }
}

impl std::error::Error for ApiError {}

impl ApiError {
    /// Builds an error from a non-2xx response body, falling back to the HTTP
    /// reason phrase when the body is not a problem document.
    pub(crate) fn from_response(status: u16, body: &str) -> Self {
        let v: serde_json::Value = serde_json::from_str(body).unwrap_or_default();
        let s = |k: &str| v.get(k).and_then(|x| x.as_str()).map(str::to_owned);
        let errors = v
            .get("errors")
            .and_then(|e| e.as_array())
            .map(|a| {
                a.iter()
                    .map(|e| FieldError {
                        path: e.get("path").and_then(|x| x.as_str()).unwrap_or("").into(),
                        message: e
                            .get("message")
                            .and_then(|x| x.as_str())
                            .unwrap_or("")
                            .into(),
                    })
                    .collect()
            })
            .unwrap_or_default();
        ApiError {
            status,
            code: s("code").unwrap_or_else(|| format!("HTTP_{status}")),
            title: s("title").unwrap_or_else(|| reason(status).to_string()),
            detail: s("detail"),
            problem_type: s("type"),
            errors,
        }
    }
}

/// Reason phrases for the statuses this API is likely to return.
fn reason(status: u16) -> &'static str {
    match status {
        400 => "Bad Request",
        401 => "Unauthorized",
        403 => "Forbidden",
        404 => "Not Found",
        405 => "Method Not Allowed",
        406 => "Not Acceptable",
        408 => "Request Timeout",
        410 => "Gone",
        422 => "Unprocessable Content",
        429 => "Too Many Requests",
        500 => "Internal Server Error",
        502 => "Bad Gateway",
        503 => "Service Unavailable",
        504 => "Gateway Timeout",
        _ => "HTTP error",
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn problem_body() {
        let body = r#"{"type":"t","title":"Validation failed","status":400,"code":"VALIDATION_FAILED","detail":"bad currency","errors":[{"path":"currency","message":"nope"}]}"#;
        let e = ApiError::from_response(400, body);
        assert_eq!(e.code, "VALIDATION_FAILED");
        assert_eq!(e.errors[0].path, "currency");
        assert_eq!(
            e.to_string(),
            "Validation failed (HTTP 400, VALIDATION_FAILED): bad currency"
        );
    }

    #[test]
    fn non_problem_body_falls_back_to_reason() {
        let e = ApiError::from_response(502, "<html>bad gateway</html>");
        assert_eq!(e.code, "HTTP_502");
        assert_eq!(e.title, "Bad Gateway");
        assert_eq!(e.detail, None);
    }
}
