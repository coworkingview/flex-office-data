# Changelog

## 0.1.0

First release of the Ruby client for the public CoworkingView API.

- `rates`, `cities`, `spaces` and `space` call `GET /v1/market/rates`, `GET /v1/properties` and `GET /v1/properties/{slug}`.
- Same columns, ordering and HTTP behaviour as the Python, R, Java and Rust packages.
- Standard library only (`net/http` and `json`). Ruby 3.0 or newer.
