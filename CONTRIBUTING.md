# Contributing

Thanks for helping. A few rules keep the packages in step.

## The spec comes first

`spec/SPEC.md` is the contract. A change to columns, ordering, HTTP behaviour
or limits goes there first, then into **every** package in the same pull
request, with the golden files regenerated:

```bash
python3 spec/tools/make_golden.py
```

CI fails if a package's output differs from `spec/golden/`.

## Fixtures

`spec/fixtures/` holds real API responses with operator descriptions, photos
and logos replaced by placeholders. Keep it that way: never commit operator
prose or images.

## Running the checks

| Package | Commands |
|---|---|
| Python | `cd python && uv run ruff check && uv run ruff format --check && uv run mypy && uv run pytest` |
| R | `cd r && Rscript -e 'roxygen2::roxygenise(); testthat::test_local()'` then `R CMD build . && R CMD check --as-cran coworkingview_*.tar.gz` |
| Rust | `cd rust && cargo fmt --check && cargo clippy --all-targets -- -D warnings && cargo test` |
| Java | `cd integrations/java && mvn -B verify` |
| Joplin | `cd integrations/joplin && npm ci && npm test && npm run dist` |
| Matomo | `cd integrations/matomo/CoworkingView && find . -name '*.php' -exec php -l {} + && php tests/parser.php` |
| LibreOffice | `cd integrations/libreoffice && ruff check . && python -m unittest discover -s tests && ./build.sh && ./tests/smoke.sh` |
| Nuxt | `cd integrations/nuxt && npm ci && npm run prepack && npm run lint && npm test` |

Tests never call the live API unless `COWORKINGVIEW_LIVE_TESTS=1` is set, and
then make at most three requests. The API is free and keyless; please keep it
that way for everyone by not load-testing it.

## Releases

Each package is versioned on its own (`python-v0.1.0`, `r-v0.1.0`,
`rust-v0.1.0` tags) and keeps its own `CHANGELOG.md`.
