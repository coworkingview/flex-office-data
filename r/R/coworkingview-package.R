#' @keywords internal
#' @details
#' The package is a small client for the public, keyless CoworkingView API.
#'
#' **Price Index** (CC BY 4.0):
#' * [cwv_rates()] -- one row per city and product: flex desk, fixed desk and
#'   private office per month, day pass per day, meeting room per hour.
#' * [cwv_cities()] -- one row per city, with city-level figures.
#'
#' **Catalogue** (search and link only):
#' * [cwv_spaces()] -- search spaces (at most 200 per call).
#' * [cwv_space()] -- one space and its pricing table.
#'
#' [cwv_attribution()] reads the attribution every result carries.
#'
#' @section Options:
#' * `coworkingview.base_url`: base URL of the API. Defaults to the
#'   environment variable `COWORKINGVIEW_API_URL`, then
#'   `https://api.coworkingview.com`.
#'
#' @section Errors:
#' All errors inherit from the condition class `cwv_error`. Invalid arguments
#' raise `cwv_input_error`; responses with an HTTP error status raise
#' `cwv_api_error`, with the fields `status`, `code`, `title`, `detail` and
#' `errors` taken from the API's problem document. Requests answered with
#' 429 or a 5xx status are retried once after a short wait (at most 10
#' seconds). When the API cannot be reached at all, functions show a message
#' and return `NULL` instead of failing.
#'
#' @section Licence of the data:
#' The Price Index is published under the Creative Commons Attribution 4.0
#' International licence: you may share and adapt it, including commercially,
#' if you credit the source with the text returned by [cwv_attribution()].
#' Catalogue content belongs to the operators: it may be searched and linked
#' to, not bulk-copied.
"_PACKAGE"
