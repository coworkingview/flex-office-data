#' Read the attribution that travels with a result
#'
#' Every result of this package carries the text you must reproduce when you
#' publish data derived from it. The CoworkingView Price Index
#' ([cwv_rates()], [cwv_cities()]) is licensed under CC BY 4.0;
#' catalogue results ([cwv_spaces()], [cwv_space()]) carry a citation and the
#' catalogue terms.
#'
#' @param x A result of [cwv_rates()], [cwv_cities()], [cwv_spaces()] or
#'   [cwv_space()].
#' @param what Which piece to read: `"attribution"` (default) for the
#'   citation text, `"license"` for the licence URL (Price Index only),
#'   `"as_of"` for the timestamp of the index (Price Index only) or
#'   `"notice"` for the catalogue terms (catalogue only).
#'
#' @return A character string, or `NULL` when `x` does not carry that piece
#'   (for example when `x` is `NULL` because the API could not be reached).
#'
#' @seealso [cwv_rates()], [cwv_spaces()].
#' @export
#' @examplesIf interactive()
#' rates <- cwv_rates(city = "berlin")
#' cwv_attribution(rates)
#' cwv_attribution(rates, "license")
cwv_attribution <- function(x, what = c("attribution", "license", "as_of", "notice")) {
  what <- match.arg(what)
  value <- attr(x, what, exact = TRUE)
  if (is.null(value) || (length(value) == 1L && is.na(value))) {
    return(NULL)
  }
  value
}
