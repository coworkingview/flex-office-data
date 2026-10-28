## Submission

This is a new submission.

## Test environments

* Local: Debian Linux (x86_64), R 4.5.3, `R CMD check --as-cran` with the PDF
  manual (TinyTeX) and HTML Tidy.

## R CMD check results

0 errors | 0 warnings | 2 notes

* Checking CRAN incoming feasibility: "New submission".
* Checking for future file timestamps: "unable to verify current time".
  The check machine could not reach a time server; this comes from the check
  environment, not from the package.

## Internet resources

* The package is a client for a public, keyless web API
  (<https://coworkingview.com/en/api>).
* Examples that need the API are wrapped in `@examplesIf interactive()`, so
  they do not run during checks.
* Tests use recorded API responses (`tests/testthat/fixtures/`) through
  `httr2::local_mocked_responses()` and make no network requests. Live tests
  call `skip_on_cran()` and run only when the environment variable
  `COWORKINGVIEW_LIVE_TESTS` is set to `1`.
* The vignette does not evaluate network code (`eval = FALSE`).
* When the API cannot be reached, functions show an informative message and
  return `NULL` instead of throwing an error.
