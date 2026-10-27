## Submission

This is a new submission.

## TODO before submitting

* **The maintainer is a placeholder.** `Authors@R` lists
  `person("Maintainer", "Name", role = "cre", email = "info@coworkingview.com")`.
  CRAN requires the maintainer (`cre`) to be a natural person with a
  personal, monitored email address. Replace it with the real person's name
  and email before running `devtools::submit_cran()`; CRAN will send the
  confirmation email to that address.

## R CMD check results

0 errors | 0 warnings | 1 note

* This is a new release. ("New submission" NOTE.)

Checked locally with R 4.6.1 on macOS (aarch64), `R CMD check --as-cran`.

## Internet resources

* The package is a client for a public, keyless web API
  (<https://api.coworkingview.com>).
* Examples that need the API are wrapped in `@examplesIf interactive()`, so
  they do not run during checks.
* Tests use recorded API responses (`tests/testthat/fixtures/`) through
  `httr2::local_mocked_responses()` and make no network requests. Live tests
  run only when the environment variable `COWORKINGVIEW_LIVE_TESTS` is set
  to `1`, and are skipped on CRAN.
* The vignette does not evaluate network code.
* When the API cannot be reached, functions show an informative message and
  return `NULL` instead of throwing an error.
