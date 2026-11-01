// Copyright (c) 2026 CoworkingView. License: MIT.
module coworkingview.error;

import std.conv : to;

/// Failure of one call, before a response is accepted or when the argument is rejected.
class CoworkingViewException : Exception
{
    this(string message, string file = __FILE__, size_t line = __LINE__, Throwable next = null)
    {
        super(message, file, line, next);
    }
}

/// One entry of an RFC 9457 `errors` array.
struct FieldError
{
    /// JSON path the API named, or `null` when it sent none.
    string path;
    /// What the API said about that field, or `null`.
    string message;
}

/**
The API answered with an error, or with a success body this client cannot read.

`status` is the HTTP status. `code`, `title` and `detail` come from the problem
JSON when the body has them. Otherwise `code` is `HTTP_<status>` and `title`
is the HTTP reason.
*/
class APIException : CoworkingViewException
{
    /// HTTP status from the response.
    int status;
    /// Machine-readable code, for example `VALIDATION_FAILED` or `BAD_RESPONSE`.
    string code;
    /// Short summary.
    string title;
    /// Longer explanation, or `null` when the body had none.
    string detail;
    /// Per-field problems. Empty when the body had none.
    FieldError[] errors;

    this(int status, string code, string title, string detail = null,
        FieldError[] errors = null, string file = __FILE__, size_t line = __LINE__)
    {
        this.status = status;
        this.code = code;
        this.title = title;
        this.detail = detail;
        this.errors = errors;
        super(apiMessage(status, code, title, detail), file, line);
    }
}

/// A success body this client cannot read. Converted to `APIException` at the call boundary.
package class ShapeException : Exception
{
    this(string message, string file = __FILE__, size_t line = __LINE__)
    {
        super(message, file, line);
    }
}

private string apiMessage(int status, string code, string title, string detail)
{
    auto text = to!string(status) ~ " " ~ code ~ ": " ~ title;
    if (detail.length)
        text ~= " (" ~ detail ~ ")";
    return text;
}
