# Changelog

## 0.1.0

First release of the Java client for the public CoworkingView API.

- `rates`, `cities`, `spaces` and `space`, with the same endpoints, columns, ordering and HTTP behaviour as the Python, R and Rust packages.
- Locales `en`, `es` and `de`. No prices or fields are filled in when the API omits them.
- JDK only at runtime (`java.net.http.HttpClient`, no third-party JSON library).
- Maven Central coordinates `io.github.coworkingview:coworkingview:0.1.0`.
